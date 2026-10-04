#!/usr/bin/env bash
# Check the inline Logstash configs in elk-stack/docker-compose.yaml.
#  1. Each rendered config is identical to the file on homeauto (gelf excepted: it is intentionally changed).
#  2. Every pipeline passes `logstash --config.test_and_exit`.
set -uo pipefail
cd "$(dirname "$0")/.."

HOST=bagpuss@172.24.32.13
BASE=/docker/logstash/config
IMAGE=docker.elastic.co/logstash/logstash:9.5.4
fail=0

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
  jq -j ".configs.$name.content" <<<"$rendered" >"$tmp/$local"
  if [ "$name" = logstash_gelf ]; then
    grep -q 'data_stream_dataset => "docker"' "$tmp/$local" && echo "ok   $name (changed: data_stream)" \
      || { echo "FAIL $name: no data_stream output"; fail=1; }
  elif diff <(ssh -o BatchMode=yes "$HOST" cat "$BASE/$hostfile") "$tmp/$local" >/dev/null; then
    echo "ok   $name identical to host"
  else
    echo "FAIL $name differs from host:"
    diff <(ssh -o BatchMode=yes "$HOST" cat "$BASE/$hostfile") "$tmp/$local" | head -20; fail=1
  fi
done

for f in "$tmp"/p/*.conf; do
  [ -s "$f" ] || { echo "FAIL $(basename "$f"): empty"; fail=1; continue; }
  if docker run --rm -v "$tmp/p:/tmp/p:ro" "$IMAGE" logstash --path.data /tmp/lsdata --config.test_and_exit -f "/tmp/p/$(basename "$f")" 2>&1 | grep -q 'Configuration OK'; then
    echo "ok   $(basename "$f"): Configuration OK"
  else
    echo "FAIL $(basename "$f"): config test"; fail=1
  fi
done
exit $fail
