#!/usr/bin/env bash
# Build the home lab Kibana dashboards from gen.py and import them (overwrite) into Kibana.
# Usage: apply.sh [hosts|containers|all]   (default: all)
# WARNING: writes to production Kibana. Objects have fixed ids (homelab-*), so reruns
# replace them, including any edits made in the Kibana UI.
set -euo pipefail
KIBANA=${KIBANA:-https://logs.viewpoint.house}
DIR=$(cd "$(dirname "$0")" && pwd)
which=${1:-all}
[ "$which" = all ] && set -- hosts containers || set -- "$which"

for d in "$@"; do
  # Python runs in a container, not on the workstation
  nd=$(docker run --rm -v "$DIR:/d:ro" python:3.13-alpine python -I /d/gen.py "$d")
  if ! out=$(curl -sS --fail-with-body -X POST "$KIBANA/api/saved_objects/_import?overwrite=true" \
    -H 'kbn-xsrf: true' -F "file=@-;filename=$d.ndjson" <<<"$nd"); then
    echo "$d: import failed: $out" >&2; exit 1
  fi
  echo "$d: $(jq -c '{success, successCount, errors}' <<<"$out")"
  # Every generated object must have imported
  jq -e --argjson n "$(grep -c . <<<"$nd")" '.success == true and .successCount == $n' <<<"$out" >/dev/null
done
