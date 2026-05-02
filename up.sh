echo "----- Deploying to homeauto -----"
export DOCKER_HOST=ssh://bagpuss@172.24.32.13

docker compose -f core-stack/docker-compose.yaml up -d
docker compose -f traefik/docker-compose.yaml up -d
docker compose -f infisical/docker-compose.yaml up -d
docker compose -f unifi/docker-compose.yaml up -d
docker compose -f ha-stack/docker-compose.yaml up -d
docker compose -f piper/docker-compose.yaml up -d
docker compose -f whisper/docker-compose.yaml up -d
docker compose -f eplzones/docker-compose.yaml up -d
docker compose -f paperless/docker-compose.yaml up -d
docker compose -f grafana/docker-compose.yaml up -d
docker compose -f media-stack/docker-compose.yaml up -d
docker compose -f monitoring-stack/docker-compose.yaml up -d  # needs librenms env_file environemt duplication looked at
docker compose -f elk-stack/docker-compose.yaml up -d
docker compose -f dawarich/docker-compose.yml up -d
docker compose -f warrior.yaml up -d
docker compose -f ollama/docker-compose.yaml up -d
docker compose -f homepage/docker-compose.yaml up -d
docker compose -f peanut/docker-compose.yaml up -d
# docker compose -f miniflux/docker-compose.yaml up -d
docker compose -f scrutiny/docker-compose.yaml up -d
docker compose -f ebusd/docker-compose.yaml up -d
# docker compose -f watchtower/docker-compose.yaml up -d
docker compose -f uptime-kuma/docker-compose.yaml up -d
docker compose -f influxdb/docker-compose.yaml up -d
docker compose -f mdns_repeater/docker-compose.yaml up -d
docker compose -f nginx_core/docker-compose.yaml up -d
docker compose -f homebox/docker-compose.yaml up -d
docker compose -f matter-hub/docker-compose.yaml up -d
docker compose -f whatsupdocker/docker-compose.yaml up -d
docker compose -f beszel/docker-compose.yaml up -d
docker compose -f photoprism/docker-compose.yaml up -d
docker compose -f immich/docker-compose.yaml up -d
docker compose -f komodo/docker-compose.yaml up -d  # Komodo Core + Periphery + MongoDB
# docker compose -f warpgate/docker-compose.yaml up -d  --- Warpgate disabled - unlikely to be of use ---
docker compose -f netalertx/docker-compose.yaml up -d  # NetAlertX - network monitoring and alerting tool
docker compose -f borg-ui/docker-compose.yaml up -d
docker compose -f selenium/docker-compose.yaml up -d

docker compose -f opensky/docker-compose.yaml up -d
docker compose -f piaware/docker-compose.yaml up -d
docker compose -f planefinder/docker-compose.yaml up -d
docker compose -f fr24feed/docker-compose.yaml up -d

### PHPMyAdmin needs access to other services' networks
docker compose -f phpmyadmin/docker-compose.yaml up -d


echo "----- Deploying to ADS-B receiver (172.24.32.11) -----"
export DOCKER_HOST=ssh://bagpuss@172.24.32.11
docker compose -f ultrafeeder/docker-compose.yaml up -d
docker compose -f komodo/docker-compose-sdrpi.yaml up -d  # Komodo Periphery agent

echo "----- Deploying to OctoPrint (172.24.32.18) -----"
export DOCKER_HOST=ssh://bagpuss@172.24.32.18
docker compose -f octoprint/docker-compose.yaml up -d
docker compose -f komodo/docker-compose-octoprint.yaml up -d  # Komodo Periphery agent

echo "----- Deploying to Blackbird -----"
export DOCKER_HOST=ssh://bagpuss@172.24.32.5
docker compose -f scrutiny/docker-compose-blackbird.yaml up -d
docker compose -f beszel/docker-compose-blackbird.yaml up -d
docker compose -f komodo/docker-compose-blackbird.yaml up -d  # Komodo Periphery agent

echo "----- Deploying to LittleGeek -----"
# export DOCKER_HOST=ssh://bagpuss@littlegeek.tailc78bf3.ts.net
export DOCKER_HOST=ssh://bagpuss@100.92.153.11
docker compose -f beszel/docker-compose-littlegeek.yaml up -d
docker compose -f komodo/docker-compose-littlegeek.yaml up -d  # Komodo Periphery agent

echo "----- Deploying to Deepcore -----"
# export DOCKER_HOST=ssh://bagpuss@149.202.95.105
export DOCKER_HOST=ssh://bagpuss@100.98.130.51
docker compose -f beszel/docker-compose-deepcore.yaml up -d
docker compose -f komodo/docker-compose-deepcore.yaml up -d  # Komodo Periphery agent
docker compose -f scrutiny/docker-compose-deepcore.yaml up -d
docker compose -f traefik/docker-compose-deepcore.yaml up -d
docker compose -f wallabag/docker-compose.yaml up -d
docker compose -f rss/docker-compose.yaml up -d
# docker compose -f pixelfed/docker-compose.yaml up -d
docker compose -f social-stack/docker-compose.yaml up -d
docker compose -f obsidian-sync/docker-compose.yaml up -d
