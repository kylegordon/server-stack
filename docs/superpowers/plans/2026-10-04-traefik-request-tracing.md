# Traefik Request Logging and Tracing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every request routed by homeauto's Traefik lands in Elasticsearch keyed on its W3C `trace.id`, secrets redacted, kept 30 days, joinable to the backend container's logs and — for capable apps — to the backend's own spans.

**Architecture:** Traefik exports access logs over OTLP to the existing apm-server; ES `@custom` ingest pipelines redact secrets and enrich with the backend container name; ILM enforces 30 days. Container log ingestion (currently broken) is repaired with all ELK config moved inline into `elk-stack/docker-compose.yaml`.

**Tech Stack:** Traefik v3.7.13, Elasticsearch / Kibana / Logstash / Filebeat / APM Server 9.5.4, Docker Compose v2.38.2, bash + curl + jq.

**Spec:** `docs/superpowers/specs/2026-10-04-traefik-request-tracing-design.md`

## Global Constraints

- ES: `http://172.24.32.13:9200`; Kibana: `https://logs.viewpoint.house`; apm-server OTLP (HTTP and gRPC): `172.24.32.13:8200`.
- Remote docker: `DOCKER_HOST=ssh://bagpuss@172.24.32.13`. Do **not** run `up.sh` or `docker compose up` without the user saying so in this session; ask, then deploy one stack at a time.
- `apply.sh` writes to production ES — ask before each run.
- Config reaching containers must be in the repo: `configs:` with `content:` only. No bind mounts or `configs: file:` pointing at repo files (they resolve on homeauto). Escape `$` as `$$` inside `content:`.
- Retention 30 days. Header allowlist / redact list exactly as spec component 1. Secret params: `apikey`, `api_key`, `token`, `access_token`, `auth`, `password`, `signature`, case-insensitive.
- Validate every changed compose file: `docker compose -f <file> config --quiet`.
- One PR per task group as marked; branch from `master`; PR text per `~/.claude/CLAUDE.md` (short, no boilerplate sections). No commits of credentials (GitGuardian).

## Review Focus

1. Secret param in an unusual position or case — `?ApiKey=x`, `?a=1&token=x#frag`, `?token=` (empty), URL-encoded name `api%5Fkey=x` — must not survive in any indexed field. Tests in Task 2.
2. Request with no query string, or a doc missing every URL field — pipeline must pass it through unchanged, not fail. Test in Task 2.
3. `$` in inlined Logstash/Filebeat config (regex `\s*$`, `${path.config}`) silently altered by Compose interpolation. Render-and-diff test in Task 5.
4. Container recreated with a different name after the service map was built — access-log docs must still index (without `container.name`). Test in Task 7.
5. LAN clients hairpinning via the host appear as the Docker gateway (`172.21.0.1`) in `ClientHost`; external clients must show their real IP. Live check in Task 4.

---

### Task 1: Phase 0 spike — Traefik OTLP access logs (PR 1)

**Files:**
- Modify: `traefik/docker-compose.yaml` (`command:` list)
- Create: `elk-stack/apm-custom/README.md`

**Interfaces:**
- Produces: in `README.md` under `## Field names`, the exact ES field paths for: request path, request host, router name, service name, client host, downstream status, each kept header. Later tasks reference these as `REQUEST_PATH_FIELD`, `SERVICE_NAME_FIELD`, etc.

- [ ] **Step 1: Add flags** — `--experimental.otlpLogs=true`, `--accesslog.format=json`, `--accesslog.bufferingsize=100`, `--accesslog.dualoutput=true`, `--accesslog.otlp.http.endpoint=http://172.24.32.13:8200/v1/logs`, `--accesslog.otlp.serviceName=traefik`. Leave `--accesslog=true`. No header flags yet.
- [ ] **Step 2: Validate** — `docker compose -f traefik/docker-compose.yaml config --quiet` → exit 0.
- [ ] **Step 3: Ask user to deploy Traefik** (or deploy on their go-ahead: `DOCKER_HOST=ssh://bagpuss@172.24.32.13 docker compose -f traefik/docker-compose.yaml up -d`).
- [ ] **Step 4: Generate and find a request**

```bash
curl -s -o /dev/null 'https://logs.viewpoint.house/spike-check?ok=1'
sleep 15
curl -s 'http://172.24.32.13:9200/logs-apm.app.traefik-*/_search?size=1&sort=@timestamp:desc&q=spike-check' | jq '.hits.hits[0]._source'
```
Expected: one hit with non-empty `trace.id`. Then `curl -s 'http://172.24.32.13:9200/traces-apm-default/_search?q=trace.id:<that id>' | jq '.hits.total.value'` ≥ 1.
**If `trace.id` is absent: stop, report to the user; spec fallback is a request-ID plugin.**
- [ ] **Step 5: Record field names** in `elk-stack/apm-custom/README.md` (`## Field names`, as above) plus the data stream name observed. Also note whether `docker logs traefik --tail 1` is JSON.
- [ ] **Step 6: Commit, push, PR** — `feat(traefik): export access logs over OTLP`.

### Task 2: Redaction pipeline with simulate tests (PR 2)

**Files:**
- Create: `elk-stack/apm-custom/pipelines/redact-secrets.json`, `elk-stack/apm-custom/pipelines/traces-apm@custom.json`, `elk-stack/apm-custom/pipelines/logs-apm.app@custom.json`, `elk-stack/apm-custom/test.sh`, `elk-stack/apm-custom/apply.sh`

**Interfaces:**
- Consumes: `REQUEST_PATH_FIELD` (Task 1).
- Produces: pipeline `redact-secrets`; `apply.sh [pipelines|ilm|enrich|kibana|all]` (idempotent, `ES=${ES:-http://172.24.32.13:9200}`); `test.sh` exits non-zero on any failed case and prints `PASS`/`FAIL <case>` per case. Later tasks add cases to `test.sh` and sections to `apply.sh`.

- [ ] **Step 1: Write `test.sh`** — each case POSTs `_ingest/pipeline/_simulate` with the pipeline JSON from disk inlined (`jq` builds `{pipeline: <file>, docs: [...]}`), so tests need no prior PUT. Cases (field = each of `url.original`, `url.full`, `url.query`, `message`, `REQUEST_PATH_FIELD`):

| Case | Input | Expected |
|---|---|---|
| basic | `/x?apikey=SECRET&ok=1` | `/x?apikey=REDACTED&ok=1` |
| case | `/x?ApiKey=SECRET` | `/x?ApiKey=REDACTED` |
| last+fragment | `/x?a=1&token=SECRET#f` | `/x?a=1&token=REDACTED#f` |
| empty | `/x?token=` | `/x?token=REDACTED` |
| encoded name | `/x?api%5Fkey=SECRET` | `/x?api%5Fkey=REDACTED` |
| all names | one param each of the 7 names | all 7 `REDACTED` |
| lookalike | `/x?tokenizer=keep` | unchanged |
| no query | `/x` | unchanged, no `error.message` |
| no fields | `{}` | unchanged, no `error.message` |
| failure | `url.original` set to an object (forces processor error) | URL fields removed, `error.message` present |

- [ ] **Step 2: Run** `bash elk-stack/apm-custom/test.sh` → FAIL (pipeline file missing).
- [ ] **Step 3: Implement `redact-secrets.json`** — one `gsub` per field, `ignore_missing: true`, pattern `(?i)([?&](?:apikey|api_key|api%5fkey|token|access_token|auth|password|signature)=)[^&#]*` → `$1REDACTED`; pipeline-level `on_failure`: `remove` all five fields (`ignore_missing`) and `set error.message` to `{{ _ingest.on_failure_message }}`. `traces-apm@custom.json` and `logs-apm.app@custom.json` each contain one `pipeline` processor calling `redact-secrets`.
- [ ] **Step 4: Run** `test.sh` → all PASS.
- [ ] **Step 5: Implement `apply.sh pipelines`** — PUT the three pipelines (`redact-secrets` first).
- [ ] **Step 6: Ask, then run** `bash elk-stack/apm-custom/apply.sh pipelines`; verify `curl -s $ES/_ingest/pipeline/traces-apm@custom | jq 'keys'` → `["traces-apm@custom"]`.
- [ ] **Step 7: Live check** — `curl -s -o /dev/null 'https://logs.viewpoint.house/redact-check?apikey=SECRET&ok=1'`; after 15 s, neither `logs-apm.app.traefik-*` nor `traces-apm-default` returns hits for `q=SECRET`, and both return a hit for `q=redact-check` containing `apikey=REDACTED`.
- [ ] **Step 8: Commit** (PR 2 continues in Task 3).

### Task 3: 30-day ILM for APM streams (PR 2)

**Files:**
- Create: `elk-stack/apm-custom/ilm/apm-30d.json`, `elk-stack/apm-custom/component-templates/traces-apm@custom.json`, `elk-stack/apm-custom/component-templates/logs-apm.app@custom.json`
- Modify: `elk-stack/apm-custom/apply.sh` (add `ilm` section)

**Interfaces:**
- Produces: ILM policy `apm-30d`.

- [ ] **Step 1: Write policy** — hot: `rollover {max_age: 1d, max_primary_shard_size: 50gb}`; delete: `min_age: 30d`, `delete`. Component templates: `template.settings.index.lifecycle.name: apm-30d`, `index.lifecycle.prefer_ilm: true`.
- [ ] **Step 2: Implement `apply.sh ilm`** — PUT policy, PUT both component templates, PUT `_settings` `index.lifecycle.name=apm-30d` on `traces-apm-default` and `logs-apm.app.traefik-default` backing indices, then `POST <stream>/_rollover` for both.
- [ ] **Step 3: Ask, then run**; verify `curl -s "$ES/traces-apm-default/_ilm/explain" | jq '[.indices[].policy]|unique'` → `["apm-30d"]`, same for `logs-apm.app.traefik-default`.
- [ ] **Step 4: Check Curator** — `grep -rn "apm" elk-stack/curator/` → no action targets `traces-apm*`/`logs-apm*`; if one does, note it in the PR.
- [ ] **Step 5: Document** apply/test usage in `elk-stack/apm-custom/README.md`.
- [ ] **Step 6: Commit, push, PR** — `feat(elk): redact secrets and keep APM data 30 days`.

### Task 4: Traefik header allowlist (PR 3)

**Files:**
- Modify: `traefik/docker-compose.yaml` (`command:` list)

- [ ] **Step 1: Add** `--accesslog.fields.headers.defaultmode=drop`; `--accesslog.fields.headers.names.<H>=keep` for `User-Agent`, `Referer`, `X-Forwarded-For`, `X-Real-Ip`, `Content-Type`, `Traceparent`, `X-Request-Id`; `=redact` for `Authorization`, `Cookie`, `Set-Cookie`, `X-Api-Key`, `X-Ha-Access`.
- [ ] **Step 2: Validate** compose; ask user to deploy Traefik.
- [ ] **Step 3: Live check**

```bash
curl -s -o /dev/null -H 'Authorization: Bearer secret' -H 'X-Unlisted: nope' 'https://logs.viewpoint.house/hdr-check'
```
After 15 s the doc for `hdr-check` has: Authorization field = `REDACTED`; User-Agent field present; no field containing `nope`. Record the header field paths in README `## Field names` if they differ from Task 1.
- [ ] **Step 4: Client IP check** — ask the user to hit `https://logs.viewpoint.house/ip-check` from a phone on mobile data; the doc's client-host field is a public IP, not `172.21.0.1`. Record the result in the PR description either way.
- [ ] **Step 5: Commit, push, PR** — `feat(traefik): access-log header allowlist`.

### Task 5: Logstash config into the repo, GELF fix (PR 4)

**Files:**
- Modify: `elk-stack/docker-compose.yaml` (top-level `configs:`; `logstash` service `configs:`; remove its three bind mounts)
- Create: `elk-stack/test-configs.sh`

**Interfaces:**
- Produces: config names `logstash_yml`, `logstash_pipelines_yml`, `logstash_syslog`, `logstash_gelf`, `logstash_fluentd`, `logstash_esphome`, `logstash_opnsense`, targets unchanged (`/usr/share/logstash/config/logstash.yml`, `/usr/share/logstash/config/pipelines.yml`, `/usr/share/logstash/pipelines/<file>.conf`). Data stream `logs-docker-default`.

- [ ] **Step 1: Write `test-configs.sh`** — for each config name, render with `docker compose -f elk-stack/docker-compose.yaml config --format json | jq -r '.configs.<name>.content'` and `diff` against `ssh bagpuss@172.24.32.13 cat <host path>`; expected identical for all except `logstash_gelf`. Then run `docker run --rm` of `docker.elastic.co/logstash/logstash:9.5.4` with the rendered files mounted from a temp dir and `logstash --config.test_and_exit -f /tmp/p/<file>.conf` per pipeline → `Configuration OK`.
- [ ] **Step 2: Run** → FAIL (configs absent).
- [ ] **Step 3: Implement** — copy the six host files verbatim into `content: |` blocks, escaping every `$` as `$$`. In `logstash_gelf` add, inside `if "gelf" in [tags]`, `mutate { rename => { "host" => "[host][name]" "container_name" => "[container][name]" "container_id" => "[container][id]" "image_name" => "[container][image][name]" } }`, and set its output to `data_stream => "true"`, `data_stream_type => "logs"`, `data_stream_dataset => "docker"`, `data_stream_namespace => "default"`.
- [ ] **Step 4: Run** `bash elk-stack/test-configs.sh` → all identical except gelf; all `Configuration OK`.
- [ ] **Step 5: Ask user to deploy elk-stack logstash**; then `curl -s "$ES/logs-docker-default/_search?size=0&q=container.name:radarr"` → total > 0 within 5 min, and `docker logs --since 5m logstash 2>&1 | grep -c 'status: 400'` → 0. Syslog still flowing: `logs-generic-default` has docs with `@timestamp` > deploy time.
- [ ] **Step 6: Commit** (PR 4 continues in Task 6).

### Task 6: Filebeat config into the repo, container input fix (PR 4)

**Files:**
- Modify: `elk-stack/docker-compose.yaml` (`filebeat_yml` config; `filebeat` service mounts)
- Modify: `elk-stack/test-configs.sh` (diff + `filebeat test config`)

- [ ] **Step 1: Extend test** — render `filebeat_yml`; run `docker run --rm docker.elastic.co/beats/filebeat:9.5.4 test config -c <rendered>` → `Config OK`; assert rendered text contains `/var/lib/docker/containers/*/*-json.log` and `add_docker_metadata`.
- [ ] **Step 2: Run** → FAIL.
- [ ] **Step 3: Implement** — `filebeat_yml` = host file verbatim (`$` → `$$`) with: container input path `/var/lib/docker/containers/*/*-json.log`; processor `add_docker_metadata: {host: "unix:///var/run/docker.sock"}`; `output.elasticsearch.indices: [{index: "logs-docker-default", when.has_fields: ["container.id"]}]`. Service: replace the filebeat.yml bind mount with `configs: [{source: filebeat_yml, target: /usr/share/filebeat/filebeat.yml}]`; add volumes `/var/lib/docker/containers:/var/lib/docker/containers:ro`, `/var/run/docker.sock:/var/run/docker.sock:ro`. Keep `/docker/filebeat/...` modules dir untouched only if the host has one (`ssh ... ls /docker/filebeat/config`); if `modules.d` exists, inline its enabled module files too.
- [ ] **Step 4: Run** test → PASS.
- [ ] **Step 5: Ask user to deploy filebeat**; `curl -s "$ES/logs-docker-default/_search?size=0&q=container.name:traefik"` → > 0 within 5 min.
- [ ] **Step 6: Commit, push, PR** — `fix(elk): move ELK config into repo and restore container logs`. PR notes: host `/docker/logstash` and `/docker/filebeat` are now unused and can be deleted later.

### Task 7: Service map and enrich (PR 5)

**Files:**
- Create: `elk-stack/apm-custom/service-map.sh`, `elk-stack/apm-custom/enrich/traefik-service-map.json`
- Modify: `elk-stack/apm-custom/pipelines/logs-apm.app@custom.json`, `test.sh`, `apply.sh` (`enrich` section)

**Interfaces:**
- Consumes: `SERVICE_NAME_FIELD` (Task 1).
- Produces: index `traefik-service-map` docs `{service: "<name>@docker", container: {name}}`; enrich policy `traefik-service-map` (match field `service`, enrich field `container.name`).

- [ ] **Step 1: Add test cases** to `test.sh` (these run against the live enrich index, so after Step 5): doc with `SERVICE_NAME_FIELD=kibana01@docker` → `container.name == "kibana"`; doc with `SERVICE_NAME_FIELD=nonexistent@docker` → no `container.name`, no `error.message`.
- [ ] **Step 2: Implement `service-map.sh`** — `docker ps --format '{{.Names}}'` + `docker inspect --format '{{json .Config.Labels}}'` over `DOCKER_HOST=ssh://bagpuss@172.24.32.13`; for each `traefik.http.services.<svc>.*` label emit `<svc>@docker → container name`; for routed containers with no explicit service label, emit `<container-name-derived router>@docker` per Traefik's default (service name = router's service = compose service name + `-<project>`; check against values seen in `SERVICE_NAME_FIELD` from Task 1 and match that form). Bulk-load into `traefik-service-map` after deleting old docs, then `POST _enrich/policy/traefik-service-map/_execute`.
- [ ] **Step 3: Add enrich processor** to `logs-apm.app@custom` after the redact call: `enrich {policy_name: traefik-service-map, field: SERVICE_NAME_FIELD, target_field: _svcmap, ignore_missing: true}` then `set container.name` from `_svcmap.container.name` (`ignore_empty_value`) and `remove _svcmap`.
- [ ] **Step 4: Ask, then run** `apply.sh enrich` (PUT policy, run `service-map.sh`, PUT pipeline).
- [ ] **Step 5: Run** `test.sh` → all PASS. Coverage check: `curl -s "$ES/logs-apm.app.traefik-*/_search?size=0" -d '{"query":{"range":{"@timestamp":{"gte":"now-15m"}}},"aggs":{"m":{"missing":{"field":"container.name"}}}}'` → missing count < 5% of total; list unmapped service names in the PR.
- [ ] **Step 6: Commit, push, PR** — `feat(elk): enrich access logs with backend container`.

### Task 8: Kibana saved searches (PR 5)

**Files:**
- Create: `elk-stack/apm-custom/kibana/saved-objects.ndjson`
- Modify: `apply.sh` (`kibana` section: `POST https://logs.viewpoint.house/api/saved_objects/_import?overwrite=true` with `kbn-xsrf: true`)

- [ ] **Step 1: Create in Kibana UI** (with the user or via API): data views `logs-apm.app.traefik-*` and `logs-docker-default`; saved search **Traefik access log** (columns: router, status, client host, request path, duration, `container.name`, `trace.id`); saved search **Container logs** (columns: `container.name`, `message`).
- [ ] **Step 2: Export** to `saved-objects.ndjson` via `POST /api/saved_objects/_export` with the four object ids.
- [ ] **Step 3: Verify import** — `apply.sh kibana` returns `"success":true`.
- [ ] **Step 4: Document** the Tier 2 lookup in README: from an access-log doc, filter Container logs on its `container.name` and `@timestamp` ± 2 s.
- [ ] **Step 5: Commit, push** to PR 5.

### Task 9: Tier 1 apps (PR 6)

**Files:**
- Modify: `grafana/docker-compose.yaml`, `elk-stack/docker-compose.yaml` (kibana01), `nautobot/docker-compose.yaml`, `ollama/docker-compose.yaml` (ollama-webui), `homebox/docker-compose.yaml`, `karakeep/docker-compose.yaml`, `immich/docker-compose.yaml`

- [ ] **Step 1: Grafana first** — add the spec's env vars; validate; ask to deploy; `curl -s -o /dev/null https://<grafana host>/api/health`; find that request's `trace.id` in `logs-apm.app.traefik-*`, then `curl -s "$ES/traces-apm-default/_search?q=trace.id:<id>" | jq '[.hits.hits[]._source.service.name]|unique'` → contains `traefik` and `grafana`.
- [ ] **Step 2: Repeat Step 1** for Kibana, Nautobot, Open WebUI, Homebox, Karakeep (an `/api/` path), Immich — env vars exactly as the spec's Tier 1 table. Any app that does not show its own service name under the shared trace: revert its env vars and record it in the PR as Tier 2.
- [ ] **Step 3: Commit, push, PR** — `feat: join Traefik traces from OTel-capable apps`, listing verified apps.

### Task 10: Close-out

- [ ] Update `CLAUDE.md` (Architecture → ELK: config inline via `configs: content:`; access logs/tracing pointer to `elk-stack/apm-custom/README.md`).
- [ ] Update project memory `traefik-request-tracing-design` and the Obsidian project note with final state and disk usage (`_cat/allocation`).
