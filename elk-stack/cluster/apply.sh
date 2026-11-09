#!/usr/bin/env bash
# Apply cluster-wide Elasticsearch settings that give every new index 0 replicas
# (es01 and es02 share one disk, so replicas add no safety and double disk use):
#  - logs@custom, metrics@custom, traces@custom component templates (data streams)
#  - a legacy template for the daily .monitoring-<product>-7-* indices (legacy internal collection)
# The Beats set theirs in their own config. Idempotent. WARNING: writes to production ES.
set -euo pipefail
ES=${ES:-http://172.24.32.13:9200}
DIR=$(cd "$(dirname "$0")" && pwd)

put() { # put <path> <file>
  local out
  out=$(curl -sS --fail-with-body -H 'Content-Type: application/json' -X PUT "$ES/$1" -d @"$2") \
    || { echo "PUT $1 failed: $out" >&2; exit 1; }
  echo "$1: $(jq -c . <<<"$out")"
}

for f in "$DIR"/component-templates/*.json; do
  put "_component_template/$(basename "$f" .json)" "$f"
done
put _template/monitoring-zero-replicas "$DIR/monitoring-zero-replicas.legacy-template.json"

# One stream per family must resolve to 0 replicas (Beats indices come from their own templates)
for idx in logs-docker-default logs-generic-default metrics-apm.app.traefik-default traces-apm-default; do
  # auto_expand_replicas (e.g. 0-1) would override number_of_replicas, so it must be off too
  r=$(curl -sS --fail-with-body -X POST "$ES/_index_template/_simulate_index/$idx" \
    | jq -r '.template.settings.index | "\(.number_of_replicas // "unset") \(.auto_expand_replicas // "false")"')
  echo "simulate $idx: replicas/auto_expand $r"
  [ "$r" = "0 false" ] || { echo "FAIL $idx would get replicas/auto_expand $r" >&2; exit 1; }
done

# _simulate_index ignores legacy templates: check ours outranks the built-in .monitoring-* ones
# (which set auto_expand_replicas 0-1) and turns both settings off
curl -sS --fail-with-body "$ES/_template/.monitoring-*,monitoring-zero-replicas" | jq -e '
  .["monitoring-zero-replicas"] as $m
  | ($m.settings.index.number_of_replicas == "0") and ($m.settings.index.auto_expand_replicas == "false")
    and ([to_entries[] | select(.key != "monitoring-zero-replicas") | .value.order] | all(. < $m.order))' >/dev/null \
  && echo "monitoring-zero-replicas: outranks .monitoring-* templates" \
  || { echo "FAIL monitoring-zero-replicas does not override the .monitoring-* templates" >&2; exit 1; }
