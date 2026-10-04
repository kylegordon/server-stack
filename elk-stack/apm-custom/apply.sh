#!/usr/bin/env bash
# Idempotent apply of elk-stack/apm-custom config to Elasticsearch/Kibana.
# Usage: apply.sh [pipelines|ilm|enrich|kibana|all]   (default: all)
# WARNING: writes to production ES.
set -euo pipefail
ES=${ES:-http://172.24.32.13:9200}
DIR=$(cd "$(dirname "$0")" && pwd)

put() { # put <path> <file>
  curl -sf -H 'Content-Type: application/json' -X PUT "$ES/$1" -d @"$2" | jq -c . ; }

pipelines() {
  # redact-secrets first: the @custom pipelines call it
  for n in redact-secrets traces-apm@custom logs-apm.app@custom; do
    echo "pipeline $n"; put "_ingest/pipeline/$n" "$DIR/pipelines/$n.json"
  done
}

ilm() {
  echo "ilm policy apm-30d"; put _ilm/policy/apm-30d "$DIR/ilm/apm-30d.json"
  for n in traces-apm@custom logs-apm.app@custom; do
    echo "component template $n"; put "_component_template/$n" "$DIR/component-templates/$n.json"
  done
  for ds in traces-apm-default logs-apm.app.traefik-default; do
    # Roll over only if the write index is not yet on apm-30d (keeps reruns from
    # creating a new empty index every time). Checked before the settings PUT.
    write_idx=$(curl -sf "$ES/_data_stream/$ds" | jq -r '.data_streams[0].indices[-1].index_name')
    cur=$(curl -sf "$ES/$write_idx/_ilm/explain" | jq -r '.indices[].policy // "none"')
    echo "settings $ds (write index $write_idx, policy $cur)"
    put "$ds/_settings" <(echo '{"index.lifecycle.name":"apm-30d"}')
    if [ "$cur" != apm-30d ]; then
      echo "rollover $ds"
      curl -sf -X POST "$ES/$ds/_rollover" | jq -c .
    fi
  done
}

case "${1:-all}" in
  pipelines) pipelines ;;
  ilm) ilm ;;
  enrich|kibana) echo "section '$1' not implemented yet" >&2 ;;
  all) pipelines; ilm ;;
  *) echo "usage: $0 [pipelines|ilm|enrich|kibana|all]" >&2; exit 2 ;;
esac
