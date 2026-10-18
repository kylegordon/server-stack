#!/usr/bin/env bash
# Check the inline Logstash and Beats configs in elk-stack/docker-compose.yaml.
#  1. Every pipeline passes `logstash --config.test_and_exit`.
#  2. filebeat_yml has the expected content and passes `filebeat test config`.
#  3. auditbeat_yml and metricbeat_yml resolve to dashboards disabled and pass `test config`.
# Needs local docker only; the inline configs in the compose file are the source of truth.
set -uo pipefail
cd "$(dirname "$0")/.."

IMAGE=docker.elastic.co/logstash/logstash:9.5.4
FB_IMAGE=docker.elastic.co/beats/filebeat:9.5.4
fail=0

rendered=$(docker compose -f elk-stack/docker-compose.yaml config --format json) || exit 1
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/p"

# name:file name in $tmp
for entry in \
  logstash_yml:logstash.yml \
  logstash_pipelines_yml:pipelines.yml \
  logstash_syslog:p/syslog.conf \
  logstash_gelf:p/gelf.conf \
  logstash_fluentd:p/fluentd.conf \
  logstash_esphome:p/syslog-esphome.conf \
  logstash_opnsense:p/syslog-opnsense.conf; do
  IFS=: read -r name local <<<"$entry"
  if ! jq -e ".configs.$name.content" <<<"$rendered" >/dev/null 2>&1; then
    echo "FAIL $name: config missing"; fail=1; continue
  fi
  # `compose config` re-escapes $ as $$; the container receives a single $
  jq -j ".configs.$name.content" <<<"$rendered" | sed 's/\$\$/$/g' >"$tmp/$local"
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
chmod 600 "$fb"
out=$(docker run --rm --user root -v "$fb:/usr/share/filebeat/filebeat.yml:ro" "$FB_IMAGE" test config -c /usr/share/filebeat/filebeat.yml --strict.perms=false 2>&1)
if grep -q 'Config OK' <<<"$out"; then echo "ok   filebeat_yml: Config OK"; else echo "FAIL filebeat_yml: filebeat test config"; echo "$out" | tail -10; fail=1; fi

# --- auditbeat, metricbeat ---
for beat in auditbeat metricbeat; do
  cfg="$tmp/$beat.yml"
  jq -j ".configs.${beat}_yml.content // empty" <<<"$rendered" | sed 's/\$\$/$/g' >"$cfg"
  if [ ! -s "$cfg" ]; then echo "FAIL ${beat}_yml: missing"; fail=1; continue; fi
  if grep -qF 'path.config' "$cfg" && ! grep -qF '${path.config}/modules.d/*.yml' "$cfg"; then echo "FAIL ${beat}_yml: \${path.config} lost (write \$\${path.config})"; fail=1; fi
  chmod 600 "$cfg"
  run=(docker run --rm --user root -v "$cfg:/usr/share/$beat/$beat.yml:ro" "$(jq -r ".services.$beat.image" <<<"$rendered")")
  # Check the setting as the Beat resolves it, so a later override or commented line can't fool the test
  if "${run[@]}" export config -c "/usr/share/$beat/$beat.yml" --strict.perms=false 2>&1 | grep -A1 -E '^  dashboards:$' | grep -qE '^    enabled: false$'; then
    echo "ok   ${beat}_yml: dashboards disabled"
  else
    echo "FAIL ${beat}_yml: setup.dashboards.enabled must be false (Beat 9 exits otherwise)"; fail=1
  fi
  # `test config` does not validate auditd audit_rules
  out=$("${run[@]}" test config -c "/usr/share/$beat/$beat.yml" --strict.perms=false 2>&1)
  if grep -q 'Config OK' <<<"$out"; then echo "ok   ${beat}_yml: Config OK"; else echo "FAIL ${beat}_yml: $beat test config"; echo "$out" | tail -10; fail=1; fi
done
exit $fail
