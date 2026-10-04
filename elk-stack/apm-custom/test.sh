#!/usr/bin/env bash
# Simulate-based tests for the ingest pipelines. No PUT needed: the pipeline
# JSON is inlined into _ingest/pipeline/_simulate.
set -u
ES=${ES:-http://172.24.32.13:9200}
DIR=$(cd "$(dirname "$0")" && pwd)
FIELDS=(url.original url.full url.query message labels.RequestPath labels.request_Referer)
fails=0

# sim <field> <value>  -> prints the simulate result for one doc
sim() {
  jq -n --slurpfile p "$DIR/pipelines/redact-secrets.json" --arg f "$1" --arg v "$2" \
    '{pipeline: $p[0], docs: [{_source: ({} | setpath($f|split("."); $v))}]}' |
    curl -s -H 'Content-Type: application/json' -X POST "$ES/_ingest/pipeline/_simulate" -d @-
}

# check <label> <field> <input> <expected>
check() {
  local label=$1 f=$2 in=$3 want=$4 out got err
  out=$(sim "$f" "$in")
  got=$(jq -r --arg f "$f" '.docs[0].doc._source | getpath($f|split("."))' <<<"$out")
  err=$(jq -r '.docs[0].doc._source.error.message // empty' <<<"$out")
  if [[ $got == "$want" && -z $err ]]; then echo "PASS $label [$f]"
  else echo "FAIL $label [$f]: got '$got' want '$want' err '$err'"; fails=$((fails+1)); fi
}

each_field() { for f in "${FIELDS[@]}"; do check "$1" "$f" "$2" "$3"; done; }

each_field basic '/x?apikey=SECRET&ok=1' '/x?apikey=REDACTED&ok=1'
each_field case '/x?ApiKey=SECRET' '/x?ApiKey=REDACTED'
each_field last+fragment '/x?a=1&token=SECRET#f' '/x?a=1&token=REDACTED#f'
each_field empty '/x?token=' '/x?token=REDACTED'
each_field encoded-name '/x?api%5Fkey=SECRET' '/x?api%5Fkey=REDACTED'
each_field all-names \
  '/x?apikey=1&api_key=2&api%5Fkey=3&token=4&access_token=5&auth=6&password=7&signature=8' \
  '/x?apikey=REDACTED&api_key=REDACTED&api%5Fkey=REDACTED&token=REDACTED&access_token=REDACTED&auth=REDACTED&password=REDACTED&signature=REDACTED'
each_field authsig '/api/x?authSig=JWT.A.B&ok=1' '/api/x?authSig=REDACTED&ok=1'
each_field lookalike '/x?tokenizer=keep' '/x?tokenizer=keep'
each_field no-query '/x' '/x'

# message is JSON text: the value must not swallow the rest of the JSON
check json-message message '{"RequestPath":"/x?apikey=SECRET","RouterName":"r1"}' \
  '{"RequestPath":"/x?apikey=REDACTED","RouterName":"r1"}'
# Go JSON encoding stores & as the six chars backslash-u0026 inside message
AMP='\u0026'
check json-escaped-amp message '{"RequestPath":"/x?a=1'$AMP'token=SECRET","RouterName":"r1"}' \
  '{"RequestPath":"/x?a=1'$AMP'token=REDACTED","RouterName":"r1"}'
check json-escaped-two message '{"RequestPath":"/x?apikey=S1'$AMP'token=S2","RouterName":"r1"}' \
  '{"RequestPath":"/x?apikey=REDACTED'$AMP'token=REDACTED","RouterName":"r1"}'
check json-escaped-keep message '{"RequestPath":"/x?apikey=S1'$AMP'ok=1","RouterName":"r1"}' \
  '{"RequestPath":"/x?apikey=REDACTED'$AMP'ok=1","RouterName":"r1"}'
# url.query has no leading ? for its first param
check query-first url.query 'apikey=SECRET&ok=1' 'apikey=REDACTED&ok=1'

# no fields at all: unchanged, no error
out=$(jq -n --slurpfile p "$DIR/pipelines/redact-secrets.json" '{pipeline:$p[0],docs:[{_source:{}}]}' |
  curl -s -H 'Content-Type: application/json' -X POST "$ES/_ingest/pipeline/_simulate" -d @-)
if [[ $(jq -c '.docs[0].doc._source' <<<"$out") == '{}' ]]; then echo "PASS no-fields"
else echo "FAIL no-fields: $(jq -c '.docs[0]' <<<"$out")"; fails=$((fails+1)); fi

# failure: url.original an object forces a processor error -> URL fields removed
out=$(jq -n --slurpfile p "$DIR/pipelines/redact-secrets.json" \
  '{pipeline:$p[0],docs:[{_source:{url:{original:{a:1},full:"/x?token=S"},message:"m",labels:{RequestPath:"/x?token=S",request_Referer:"/x?token=S"}}}]}' |
  curl -s -H 'Content-Type: application/json' -X POST "$ES/_ingest/pipeline/_simulate" -d @-)
if jq -e '.docs[0].doc._source | (.error.message|type=="string") and (.url.original==null) and (.url.full==null) and (.message==null) and (.labels.RequestPath==null) and (.labels.request_Referer==null)' <<<"$out" >/dev/null
then echo "PASS failure-removes-fields"
else echo "FAIL failure-removes-fields: $(jq -c '.docs[0]' <<<"$out")"; fails=$((fails+1)); fi

# enrich: simulate the STORED pipeline (needs `apply.sh enrich` to have run)
sim_stored() { # sim_stored <ServiceName value>
  jq -n --arg v "$1" '{docs:[{_source:{labels:{ServiceName:$v}}}]}' |
    curl -s -H 'Content-Type: application/json' -X POST "$ES/_ingest/pipeline/logs-apm.app@custom/_simulate" -d @-
}
check_enrich() { # check_enrich <label> <service> <expected container.name or "">
  local out got err
  out=$(sim_stored "$2")
  got=$(jq -r '.docs[0].doc._source.container.name // ""' <<<"$out")
  err=$(jq -r '(.docs[0].error.reason // .docs[0].doc._source.error.message) // empty' <<<"$out")
  if [[ $got == "$3" && -z $err && $(jq -r '.docs[0].doc._source | has("_svcmap")' <<<"$out") == false ]]; then echo "PASS $1"
  else echo "FAIL $1: got '$got' want '$3' err '$err'"; fails=$((fails+1)); fi
}
check_enrich enrich-known kibana01@docker kibana
check_enrich enrich-host-network music@docker music-assistant-server
check_enrich enrich-nonexistent nonexistent@docker ""
check_enrich enrich-ghost-container ghost@docker ""
check_enrich enrich-internal api@internal ""
# no ServiceName at all: no error
out=$(jq -n '{docs:[{_source:{message:"x"}}]}' |
  curl -s -H 'Content-Type: application/json' -X POST "$ES/_ingest/pipeline/logs-apm.app@custom/_simulate" -d @-)
if jq -e '.docs[0].doc._source | (.container.name==null) and (.error==null)' <<<"$out" >/dev/null
then echo "PASS enrich-no-servicename"; else echo "FAIL enrich-no-servicename: $(jq -c '.docs[0]' <<<"$out")"; fails=$((fails+1)); fi

# enrich is best-effort. A missing policy is rejected when the pipeline is built (so it can never
# reach a doc), so force a runtime failure instead: container is a string, so setting container.name
# fails. The doc must still come back, redacted, with no _svcmap and no error. Proven necessary by
# the negative control (same pipeline without ignore_failure must fail).
fail_doc='{labels:{ServiceName:"kibana01@docker",RequestPath:"/x?token=S"},container:"x"}'
run_fail() { jq -n --slurpfile p "$DIR/pipelines/logs-apm.app@custom.json" "\$p[0] | $1 | {pipeline:., docs:[{_source:$fail_doc}]}" |
  curl -s -H 'Content-Type: application/json' -X POST "$ES/_ingest/pipeline/_simulate" -d @-; }
out=$(run_fail '.')
if jq -e '.docs[0].doc._source | (._svcmap==null) and (.error==null) and (.labels.RequestPath=="/x?token=REDACTED")' <<<"$out" >/dev/null
then echo "PASS enrich-failure-best-effort"; else echo "FAIL enrich-failure-best-effort: $(jq -c '.docs[0]' <<<"$out")"; fails=$((fails+1)); fi
out=$(run_fail 'del(.processors[].[]?.ignore_failure)')
if jq -e '.docs[0].error != null' <<<"$out" >/dev/null
then echo "PASS enrich-failure-control (fails without ignore_failure)"; else echo "FAIL enrich-failure-control: failure not reproduced"; fails=$((fails+1)); fi

[[ $fails -eq 0 ]] && echo "ALL PASS" || echo "$fails FAILED"
exit $((fails>0))
