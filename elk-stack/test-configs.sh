#!/usr/bin/env bash
# Check the inline Logstash and Beats configs in elk-stack/docker-compose.yaml.
#  1. Every pipeline passes `logstash --config.test_and_exit`.
#  2. filebeat_yml has the expected content and passes `filebeat test config`.
#  3. auditbeat_yml and metricbeat_yml resolve to dashboards disabled and pass `test config`.
#  4. The opnsense pipeline parses only filterlog as firewall CSV and converts local time to UTC.
# Needs local docker only; the inline configs in the compose file are the source of truth.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

rendered=$(docker compose -f elk-stack/docker-compose.yaml config --format json) || exit 1
IMAGE=$(jq -r '.services.logstash.image' <<<"$rendered")
FB_IMAGE=$(jq -r '.services.filebeat.image' <<<"$rendered")
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

# --- opnsense pipeline behaviour: stdin in, json out ---
# Only filterlog is parsed as firewall CSV, and local (BST) time becomes UTC.
sed -E '/^input \{/,/^\}/d; /^output \{/,$d' "$tmp/p/syslog-opnsense.conf" >"$tmp/opn.conf"
{ echo 'input { stdin { type => "opnsense" } }'; cat "$tmp/opn.conf"; echo 'output { stdout { codec => json_lines } }'; } >"$tmp/opn-test.conf"
opn=$(printf '%s\n' \
  '<134>Jul  1 12:00:00 fw filterlog[1]: 69,,,abc,pppoe0,match,block,in,4,0x0,,60,0,0,none,6,tcp,40,198.51.100.7,203.0.113.9,52095,10044,0,S,1,,65535,,' \
  '<29>Jul  1 12:00:00 fw dhcp6c[2]: Sending Solicit on pppoe0' \
  '<134>Jul  1 12:00:00 fw filterlog[3]: 70,,,abc,pppoe0,match,block,in,6,0x00,0x00000,64,tcp,6,40,2001:db8::1,2001:db8::2,51000,443,0,S,1,,65535,,' \
  | timeout 300 docker run --rm -i -v "$tmp/opn-test.conf:/t.conf:ro" "$IMAGE" \
    logstash --path.data /tmp/d -f /t.conf --log.level error 2>/dev/null | grep '^{')
fl=$(jq -c 'select(."process.name"=="filterlog" and (.message|not))' <<<"$opn")
v6=$(jq -c 'select(."process.name"=="filterlog" and .message)' <<<"$opn")
dh=$(jq -c 'select(."process.name"=="dhcp6c")' <<<"$opn")
if jq -e '."event.action"=="deny" and ."destination.port"==10044 and (."@timestamp"|endswith("T11:00:00.000Z"))' <<<"$fl" >/dev/null 2>&1; then
  echo "ok   opnsense: filterlog parsed, BST -> UTC"
else echo "FAIL opnsense: filterlog line: $fl"; fail=1; fi
if jq -e '(.message|test("Sending Solicit")) and ."rule_number"==null and ."event.category"==null' <<<"$dh" >/dev/null 2>&1; then
  echo "ok   opnsense: non-filterlog keeps message, no firewall fields"
else echo "FAIL opnsense: non-filterlog line: $dh"; fail=1; fi
if jq -e '(.message|test("2001:db8::1")) and ."source.ip"==null' <<<"$v6" >/dev/null 2>&1; then
  echo "ok   opnsense: IPv6 filterlog kept raw, not parsed with IPv4 columns"
else echo "FAIL opnsense: IPv6 filterlog line: $v6"; fail=1; fi

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
