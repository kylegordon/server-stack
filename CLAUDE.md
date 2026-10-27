# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of Docker Compose files that define the home server infrastructure, deployed across multiple physical hosts. There is no build step — the "code" is YAML configuration for Docker services.

Docker Compose v2.38.2 / Docker 28.0.4.

## Hosts and deployment targets

| Host | Address | Role |
|------|---------|------|
| homeauto | 172.24.32.13 | Primary server — runs the majority of stacks |
| adsb | 172.24.32.11 | ADS-B receiver (ultrafeeder, SDR) |
| octoprint | 172.24.32.18 | 3D printer host |
| blackbird | 172.24.32.5 | NFS storage server |
| littlegeek | 100.92.153.11 | Secondary/laptop |
| deepcore | 100.98.130.51 | Public-facing server (Tailscale) |

All remote `docker compose` commands set `DOCKER_HOST=ssh://bagpuss@<address>` before running.

## Validating compose files

```bash
# Validate syntax (exit 0 = valid; missing .env files warn but don't fail)
docker compose -f <path>/docker-compose.yaml config --quiet

# Batch check all services
for f in */docker-compose.yaml; do docker compose -f "$f" config --quiet 2>&1 | grep -i error && echo "Error in $f"; done
```

Do **not** run `up.sh`, `pull.sh`, or any `docker compose up` commands unless the user explicitly asks — they use SSH to remote hosts and won't work in a sandbox.

## Deploying

Deploy all stacks to all hosts (except the stacks with `deploy = true` in `komodo-stacks.toml`, which Komodo deploys; see Komodo below):
```bash
./up.sh
```

Deploy a single stack (example):
```bash
export DOCKER_HOST=ssh://bagpuss@172.24.32.13
docker compose -f traefik/docker-compose.yaml up -d
```

Pull images without restarting:
```bash
./pull.sh
```

`stackup.sh` is a legacy Docker Swarm deployment script — it is no longer the primary deploy method.

## Architecture

### Shared infrastructure (deploy first)

1. **`network-stack`** — creates the `traefik_proxy` and `homeautomation` Docker networks. A keepalive container holds these networks so they survive stack restarts. All other stacks reference these networks as external.
2. **`traefik`** — reverse proxy and TLS termination for all HTTPS services (see `traefik/README.md`).
3. **`core-stack`** — infrastructure services (TFTP, Authelia placeholder, Meshtastic).

### Common includes

`common/networks.yaml` and `common/volumes.yaml` define shared external network references and NFS volume definitions. Many stacks `include:` these files rather than redeclaring networks.

### Aggregate stacks

Some directories are umbrella compose files that `include:` several individual service directories:

- **`ha-stack`** — Home Assistant and tightly coupled services (Frigate, Node-RED, double-take, GivTCP, ESPHome, Zigbee2MQTT, Mosquitto, Matter Server, Predbat)
- **`monitoring-stack`**, **`elk-stack`**, **`social-stack`**, **`lemmy-stack`** — similar groupings

### NFS volumes

Persistent data lives on the NFS server at 172.24.32.5 (`/srv/nfs4/docker_nfs/…`). Volumes are declared with `driver: local` and NFS4 mount options. Media files are under `/media/Tank/`.

### Traefik / TLS

On **homeauto**, certificates are Let's Encrypt via AWS Route 53 DNS challenge, issued by the `letsencrypt` resolver. Wildcard routers for `viewpoint.house` / `glasgownet.com` are declared on the Traefik container itself, but in practice **each service gets its own per-service certificate** — so every service router needs `tls.certresolver=letsencrypt`.

There is **no global HTTP→HTTPS redirect** on the `web` entrypoint (no `--entrypoints.web.http.redirections.*` in `traefik/docker-compose.yaml`). Each service declares its own redirect via a second router on `web` plus a `redirectscheme` middleware. Omit it and the service simply doesn't answer on port 80.

Full label set when adding a service:

```yaml
labels:
  - traefik.enable=true
  # http -> https redirect
  - traefik.http.routers.<name>-http.entrypoints=web
  - traefik.http.routers.<name>-http.rule=Host(`myservice.viewpoint.house`)
  - traefik.http.routers.<name>-http.middlewares=<name>-https
  - traefik.http.middlewares.<name>-https.redirectscheme.scheme=https
  # https
  - traefik.http.routers.<name>.rule=Host(`myservice.viewpoint.house`)
  - traefik.http.routers.<name>.entrypoints=websecure
  - traefik.http.routers.<name>.tls=true
  - traefik.http.routers.<name>.tls.certresolver=letsencrypt
  - traefik.http.services.<name>.loadbalancer.server.port=<port>
```

Do **not** add `tls.domains` to individual service routers.

**Deepcore is the exception, and works differently.** It holds no AWS credential, issues
per-name certificates over HTTP-01, and supports no wildcards; services there name
`tls.certresolver=letsencrypt-http` (not `letsencrypt`) on their own router. Its entire static configuration
lives in `traefik/docker-compose-deepcore.yaml`'s `command:` list and must stay there — a
`/etc/traefik/traefik.yaml` on the host silently discards that whole list, which hid a
broken certificate resolver for a year. See `traefik/README.md` before changing it.

### ELK config and request tracing

ELK config lives in the repo, inline in `elk-stack/docker-compose.yaml` as top-level `configs:`
with `content:` (Logstash `logstash.yml`, `pipelines.yml` and the 5 pipelines; `filebeat.yml`,
`auditbeat.yml`, `metricbeat.yml`). A literal `$` must be written `$$`. Bind mounts and
`configs: file:` resolve on the *remote* host when `DOCKER_HOST=ssh://` is used, which is why
the config is inline; no ELK service reads from `/docker` on homeauto. Keep `setup.dashboards.enabled: false` in every Beat: Kibana hides its
version from unauthenticated callers and a Beat 9 that tries to load dashboards exits at
startup. Syslog senders log local time with no offset, so the Logstash date filters set
`timezone => "Europe/London"`. Validate with (local docker only; runs
`logstash --config.test_and_exit` on every pipeline and `test config` on each Beat, content
assertions on `filebeat.yml`, and a stdin→stdout run of the opnsense pipeline):

```bash
elk-stack/test-configs.sh
```

Container logs land in `logs-docker-default` with `container.name` (GELF via Logstash,
json-file via Filebeat).

Request logging/tracing: Traefik exports OTLP access logs and traces to apm-server. Every
access-log doc in `logs-apm.app.traefik-*` carries `trace.id`. Secrets are redacted and a 30-day
ILM applies via `elk-stack/apm-custom/` (`apply.sh`, `test.sh`, `service-map.sh`). Rerun
`service-map.sh` after adding or removing routed services. Grafana, Kibana and Nautobot join
traces via OTLP env vars. Details: `elk-stack/apm-custom/README.md`.

### Watchtower auto-updates

Most services opt in to Watchtower image auto-updates:
```yaml
labels:
  - com.centurylinklabs.watchtower.enable=true
```

### Homepage integration

Services expose themselves to the [homepage](https://gethomepage.dev) dashboard via container labels:
```yaml
- homepage.group=<Group>
- homepage.name=<Display Name>
- homepage.icon=<icon>
- homepage.href=https://<service>.viewpoint.house
- homepage.description=<description>
```

## CI

`.github/workflows/gitguardian.yaml` runs GitGuardian secret scanning on every push and PR. Failures block merge — never commit credentials or tokens.

## File naming conventions

- Primary: `docker-compose.yaml`
- Host-specific variants: `docker-compose-<hostname>.yaml` (e.g. `docker-compose-deepcore.yaml`, `docker-compose-blackbird.yaml`)
- Env file examples: `<service>.env.example` or `.<service>.env.example`

## Known TODOs in the codebase

- `elk-stack/docker-compose.yaml:652` — remove `--environment container` flag after Elasticsearch 8.17.1/8.18.0
- `up.sh:15` — monitoring-stack `librenms env_file environment duplication` needs review
- Disabled (commented-out) services in `up.sh`: watchtower, whatsupdocker, warpgate, selenium, ollama (incl. Open WebUI). Lines marked `--- Deployed by Komodo` are live under Komodo; don't re-enable them in `up.sh`.

## Komodo

`komodo-stacks.toml` declares all stacks for Komodo (a container management platform). Komodo pulls from this repo and deploys stacks to the appropriate server. The `deploy = false` flag means Komodo tracks but does not auto-deploy on sync. Keep it in step with `up.sh`: every `up.sh` line (including commented-out ones whose compose file still exists) has a matching `[[stack]]` on the same server.

Stacks with `deploy = true` are deployed by Komodo, not `up.sh`. The Komodo procedure "Sync Server-Stack" runs the sync every 5 minutes, and Komodo redeploys a stack when its files change on `master`, so merging a Renovate bump deploys it (once Komodo next refreshes the stack's files; the resource poll interval is one hour). To migrate a stack, in one PR: set `deploy = true`, comment out its `up.sh` line with `--- Deployed by Komodo`, and comment out its `pull.sh` line if it has one. After the merge, press Deploy on the stack in Komodo once: a sync only redeploys a running stack when its files differ from the ones Komodo last deployed, and a stack adopted from `up.sh` has no deployed files recorded (its deployed hash in Komodo is empty), so until that first manual Deploy, merged file changes (including Renovate bumps) are not deployed. The exception is a PR that changes a `deploy = true` stack's `environment` in the toml: the sync deploys that config change itself, but check the stack has a successful Deploy Update dated after the merge, and press Deploy if it doesn't. Changing a Variable's value in Komodo is not a config change and needs a manual Deploy. A stack with secrets also needs Komodo secret Variables referenced as `[[STACK__KEY]]` in its `environment`; the repo is public, so only the `[[ref]]`s go in the toml. Komodo writes `environment` to `<run_directory>/.env`, so if the compose reads a different env file (e.g. `.librenms.env`), or the stack `include:`s subdirectories with their own `.env`, set `env_file_path` or rework the compose first. Keep the stack's gitignored `.env` in the workstation checkout that `up.sh` uses; Komodo doesn't read it, and its Variables are the source of truth, so the local copy can go stale. When a stack's `name` differs from its `run_directory`, set `project_name` to the directory name: `up.sh` projects are named after the directory, and Komodo otherwise uses the stack name, so it won't recognise the running containers and a deploy would start duplicates. Stacks tagged `up-sh-only` (`komodo` itself and the `komodo-periphery-*` agents) are tracked for status only: deploy them with `up.sh`, never Stop/Destroy/Redeploy from Komodo, since that would take down the agent Komodo uses to reach the host.

## Secrets / environment files

`.env` files are gitignored. Each service that needs secrets has a `*.env.example` template committed alongside. Copy the example and fill in real values:

```bash
cp traefik/traefik.env.example traefik/.env
# edit with real values
```

Services reference their env file via `env_file:` in the compose YAML. AWS credentials for Traefik's Route 53 DNS challenge are in `traefik/.env`.

## Renovate

`renovate.json` configures automated Docker image tag updates. Minor/patch updates are automerged. Major updates require manual approval. `getmeili/meilisearch` and `britkat/giv_tcp-ma` are pinned (updates disabled).
