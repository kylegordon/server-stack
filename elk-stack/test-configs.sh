#!/usr/bin/env bash
# Check the inline Logstash configs in elk-stack/docker-compose.yaml.
#  1. Each rendered config is identical to the file on homeauto (gelf excepted: it is intentionally changed).
#  2. Every pipeline passes `logstash --config.test_and_exit`.
#  3. filebeat_yml differs from the host file only by the intended changes, and passes `filebeat test config`.
set -uo pipefail
cd "$(dirname "$0")/.."

HOST=bagpuss@172.24.32.13
BASE=/docker/logstash/config
IMAGE=docker.elastic.co/logstash/logstash:9.5.4
FB_IMAGE=docker.elastic.co/beats/filebeat:9.5.4
fail=0

read -r -d '' GELF_EXPECTED_DIFF <<'EOD'
17a18,27
>
>     # GELF "host" is a string but ECS maps host as an object; move into ECS fields.
>     mutate {
>       rename => {
>         "host"           => "[host][name]"
>         "container_name" => "[container][name]"
>         "container_id"   => "[container][id]"
>         "image_name"     => "[container][image][name]"
>       }
>     }
57c67,70
<     #index => "logstash-%{+YYYY.MM.dd}"
---
>     data_stream => "true"
>     data_stream_type => "logs"
>     data_stream_dataset => "docker"
>     data_stream_namespace => "default"
EOD

rendered=$(docker compose -f elk-stack/docker-compose.yaml config --format json) || exit 1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/p"

# name:host path (relative to $BASE):local file in $tmp
for entry in \
  logstash_yml:logstash.yml:logstash.yml \
  logstash_pipelines_yml:pipelines.yml:pipelines.yml \
  logstash_syslog:pipelines/syslog.conf:p/syslog.conf \
  logstash_gelf:pipelines/gelf.conf:p/gelf.conf \
  logstash_fluentd:pipelines/fluentd.conf:p/fluentd.conf \
  logstash_esphome:pipelines/syslog-esphome.conf:p/syslog-esphome.conf \
  logstash_opnsense:pipelines/syslog-opnsense.conf:p/syslog-opnsense.conf; do
  IFS=: read -r name hostfile local <<<"$entry"
  if ! jq -e ".configs.$name.content" <<<"$rendered" >/dev/null 2>&1; then
    echo "FAIL $name: config missing"; fail=1; continue
  fi
  # `compose config` re-escapes $ as $$; the container receives a single $
  jq -j ".configs.$name.content" <<<"$rendered" | sed 's/\$\$/$/g' >"$tmp/$local"
  if [ "$name" = logstash_gelf ]; then
    # only the intended additions may differ from the host file
    got=$(diff <(ssh -o BatchMode=yes "$HOST" cat "$BASE/$hostfile") "$tmp/$local" | sed 's/[[:space:]]*$//')
    if [ "$got" = "$GELF_EXPECTED_DIFF" ]; then echo "ok   $name (differs from host only as intended)"
    else echo "FAIL $name: unexpected diff vs host:"; echo "$got" | head -40; fail=1; fi
  elif diff <(ssh -o BatchMode=yes "$HOST" cat "$BASE/$hostfile") "$tmp/$local" >/dev/null; then
    echo "ok   $name identical to host"
  else
    echo "FAIL $name differs from host:"
    diff <(ssh -o BatchMode=yes "$HOST" cat "$BASE/$hostfile") "$tmp/$local" | head -20; fail=1
  fi
done

for f in "$tmp"/p/*.conf; do
  [ -s "$f" ] || { echo "FAIL $(basename "$f"): empty"; fail=1; continue; }
  out=$(docker run --rm -v "$tmp/p:/tmp/p:ro" "$IMAGE" logstash --path.data /tmp/lsdata --config.test_and_exit -f "/tmp/p/$(basename "$f")" 2>&1)
  if grep -q 'Configuration OK' <<<"$out"; then
    echo "ok   $(basename "$f"): Configuration OK"
  else
    echo "FAIL $(basename "$f"): config test"; fail=1
  fi
done

# --- filebeat ---
fb="$tmp/filebeat.yml"
jq -j '.configs.filebeat_yml.content' <<<"$rendered" | sed 's/\$\$/$/g' >"$fb"
if [ ! -s "$fb" ]; then echo "FAIL filebeat_yml: missing"; exit 1; fi
for want in '/var/lib/docker/containers/*/*-json.log' 'add_docker_metadata' 'logs-docker-default' 'target: "json"'; do
  grep -qF -- "$want" "$fb" && echo "ok   filebeat_yml contains $want" || { echo "FAIL filebeat_yml: missing $want"; fail=1; }
done
# lines removed from the host file, ignoring comments and blanks, must be exactly the old path and dashboards=true
removed=$(diff <(ssh -o BatchMode=yes "$HOST" cat /docker/filebeat/config/filebeat.yml) "$fb" | grep '^< ' | grep -vE '^< *(#|$)' || true)
want_removed=$(printf '%s\n' '<     - /var/lib/docker/containers/*.log' '< setup.dashboards.enabled: true')
if [ "$removed" = "$want_removed" ]; then echo "ok   filebeat_yml removes only the old path and dashboards=true from the host file"
else echo "FAIL filebeat_yml: unexpected removals vs host:"; echo "$removed"; fail=1; fi
chmod 600 "$fb"
out=$(docker run --rm --user root -v "$fb:/usr/share/filebeat/filebeat.yml:ro" "$FB_IMAGE" test config -c /usr/share/filebeat/filebeat.yml --strict.perms=false 2>&1)
if grep -q 'Config OK' <<<"$out"; then echo "ok   filebeat_yml: Config OK"; else echo "FAIL filebeat_yml: filebeat test config"; echo "$out" | tail -10; fail=1; fi
exit $fail
