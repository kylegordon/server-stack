export DOCKER_HOST=ssh://bagpuss@172.24.32.13
docker compose -f pihole/docker-compose.yaml up -d
docker compose -f core-stack/docker-compose.yaml up -d
docker compose -f traefik/docker-compose.yaml up -d
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
docker compose -f miniflux/docker-compose.yaml up -d
docker compose -f scrutiny/docker-compose.yaml up -d
docker compose -f ebusd/docker-compose.yaml up -d
docker compose -f watchtower/docker-compose.yaml up -d
docker compose -f homepage/docker-compose.yaml up -d
docker compose -f uptime-kuma/docker-compose.yaml up -d
docker compose -f influxdb/docker-compose.yaml up -d
docker compose -f mdns_repeater/docker-compose.yaml up -d

export DOCKER_HOST=ssh://bagpuss@172.24.32.5
docker compose -f scrutiny/docker-compose-blackbird.yaml up -d

export DOCKER_HOST=ssh://bagpuss@deepcore.glasgownet.com
# docker compose -f scrutiny/docker-compose-deepcore.yaml up -d
docker compose -f traefik/docker-compose-deepcore.yaml up -d
docker compose -f social-stack/docker-compose.yaml up -d
docker compose -f pixelfed/docker-compose.yaml up -d
docker compose -f rss/docker-compose.yaml up -d
docker compose -f obsidian-sync/docker-compose.yaml up -d
docker compose -f wallabag/docker-compose.yaml up -d
