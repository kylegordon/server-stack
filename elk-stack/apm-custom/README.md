# Traefik access logs via OTLP

Observed 2026-10-04 after enabling `--accesslog.otlp.*` on Traefik v3.7.13 (APM Server 9.5.4).

Data stream: `logs-apm.app.traefik-default` (type `logs`, dataset `apm.app.traefik`, namespace `default`).
Backing index: `.ds-logs-apm.app.traefik-default-YYYY.MM.DD-000001`.

`docker logs traefik --tail 1` is JSON (dualoutput works).

`trace.id` is populated (equals the `traces-apm-default` trace id; the spike request matched 2 trace docs).

## Field names

The access log JSON is also in `message` as a string. APM stores each log attribute as a flat
`labels.*` (strings) or `numeric_labels.*` (numbers) field.

| Meaning | ES field |
|---|---|
| Trace id | `trace.id` (also `labels.trace_id`, `labels.TraceId`) |
| Span id | `span.id` |
| Request path (includes query string) | `labels.RequestPath` |
| Request host | `labels.RequestHost` |
| Request method | `labels.RequestMethod` |
| Router name | `labels.RouterName` (e.g. `kibana01@docker`) |
| Service name (Traefik backend) | `labels.ServiceName` (e.g. `kibana01@docker`) |
| Client host | `labels.ClientHost` |
| Downstream status | `numeric_labels.DownstreamStatus` |
| Origin status | `numeric_labels.OriginStatus` |
| Duration (ns) | `numeric_labels.Duration` |
| Entrypoint | `labels.entryPointName` |

Note: `service.name` is `traefik` (the OTLP serviceName), not the backend service.

Headers: none kept yet (no `--accesslog.fields.headers.*` flags), so no header fields present.

## Redaction pipeline

`pipelines/redact-secrets.json` masks secret query values (`apikey`, `api_key`,
`token`, `access_token`, `auth`, `password`, `signature`, case-insensitive) in
`url.original`, `url.full`, `url.query`, `message` and `labels.RequestPath`.
It is called by `traces-apm@custom` and `logs-apm.app@custom`. On any processor
error the five fields are removed and `error.message` is set.

- `bash test.sh` runs `_simulate` cases against `$ES` (no PUT needed); exits non-zero on failure.
- `bash apply.sh pipelines` PUTs the pipelines (writes to production ES).
