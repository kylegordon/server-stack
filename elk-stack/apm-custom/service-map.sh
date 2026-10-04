#!/usr/bin/env bash
# Rebuild the traefik-service-map index (service "<name>@docker" -> container.name)
# from Traefik's API + docker inspect, then execute the enrich policy.
# Usage: service-map.sh [--dry-run]   (dry run prints the docs, writes nothing)
# WARNING: writes to production ES.
set -euo pipefail
ES=${ES:-http://172.24.32.13:9200}
TRAEFIK_API=${TRAEFIK_API:-http://172.24.32.13:8090}
export DOCKER_HOST=${DOCKER_HOST:-ssh://bagpuss@172.24.32.13}
DRY=${1:-}

svcs=$(curl -sf "$TRAEFIK_API/api/http/services?per_page=1000")
# one record per running container: name, IPs on every network, host networking, labels
ctrs=$(docker ps -q | xargs docker inspect | jq -c '[.[] | {
  name: (.Name|ltrimstr("/")),
  host: (.HostConfig.NetworkMode=="host"),
  ips: ([.NetworkSettings.Networks[]?.IPAddress] | map(select(.!=""))),
  labels: (.Config.Labels // {})}]')

# Join: IP match (several candidates -> prefer the one carrying a label for the
# service); host networking -> match by the traefik.http.services.<svc>.loadbalancer.server.port/.url label.
docs=$(jq -c -n --slurpfile s <(echo "$svcs") --slurpfile c <(echo "$ctrs") '
  $s[0] as $s | $c[0] as $c |
  [$s[] | select(.provider=="docker") | . as $svc
   | ($svc.name|sub("@docker$";"")) as $n
   | (($svc.loadBalancer.servers // [])[0].url // "") as $url0
   | if $url0=="" then {service:$svc.name, url:"", container:null} else
   ($url0 | capture("^[a-z]+://(?<ip>[^:/]+)(:(?<port>[0-9]+))?")) as $u
   | ([$c[] | select(.host|not) | select(.ips|index($u.ip))]) as $byip
   | ([$c[] | select(.host) | select(.labels["traefik.http.services.\($n).loadbalancer.server.port"] == $u.port or .labels["traefik.http.services.\($n).loadbalancer.server.url"] == $svc.loadBalancer.servers[0].url)]) as $byport
   | ($byip | map(select(.labels|keys|any(contains("." + $n + ".") or contains(".services." + $n)))) ) as $pref
   | (if ($byip|length)==1 then $byip[0].name
      elif ($pref|length)==1 then $pref[0].name
      elif ($byip|length)==0 and ($byport|length)==1 then $byport[0].name
      else null end) as $cn
   | {service: $svc.name, url: $url0, container: $cn} end]')

jq -r '.[] | select(.container==null) | "UNMAPPED \(.service) \(.url)"' <<<"$docs" >&2
if [[ $DRY == --dry-run ]]; then jq -c '.[]' <<<"$docs"; exit 0; fi

n=$(jq '[.[]|select(.container!=null)]|length' <<<"$docs")
[[ $n -gt 0 ]] || { echo "abort: computed map has 0 docs, leaving index untouched" >&2; exit 1; }
curl -sf -X POST "$ES/traefik-service-map/_delete_by_query?refresh=true&conflicts=proceed" \
  -H 'Content-Type: application/json' -d '{"query":{"match_all":{}}}' | jq -c '{deleted}'
jq -c '.[] | select(.container!=null) | {index:{_index:"traefik-service-map",_id:.service}}, {service:.service, container:{name:.container}}' <<<"$docs" |
  curl -sf -X POST "$ES/_bulk?refresh=true" -H 'Content-Type: application/x-ndjson' --data-binary @- |
  jq -e -c '{errors, items: (.items|length)} | if .errors then error("bulk errors") else . end' ||
  { echo "abort: bulk load reported errors" >&2; exit 1; }
curl -sf -X POST "$ES/_enrich/policy/traefik-service-map/_execute" | jq -c .
