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

case "${1:-all}" in
  pipelines) pipelines ;;
  ilm|enrich|kibana) echo "section '$1' not implemented yet" >&2 ;;
  all) pipelines ;;
  *) echo "usage: $0 [pipelines|ilm|enrich|kibana|all]" >&2; exit 2 ;;
esac
