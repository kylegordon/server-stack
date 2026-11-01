export DOCKER_HOST=ssh://bagpuss@172.24.32.13
echo "Pulling core stack"
# docker compose -f core-stack/docker-compose.yaml pull  --- Deployed by Komodo
echo "Pulling Traefik stack"
docker compose -f traefik/docker-compose.yaml pull
echo "Pulling Infisical stack"
# docker compose -f infisical/docker-compose.yaml pull  --- Deployed by Komodo
echo "Pulling HA stack"
# docker compose -f eclipse-mosquitto/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f zigbee2mqtt/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f matter-server/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f home-assistant/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f frigate/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f double-take/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f node-red/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f givtcp/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f predbat/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f esphome/docker-compose.yaml pull  --- Deployed by Komodo
echo "Pulling media stack"
docker compose -f media-stack/docker-compose.yaml pull
echo "Pulling elk stack"
# docker compose -f elk-stack/docker-compose.yaml pull  --- Deployed by Komodo
echo "Pulling monitoring stack"
docker compose -f monitoring-stack/docker-compose.yaml pull
docker compose -f dawarich/docker-compose.yml pull
# docker compose -f warrior/docker-compose.yaml pull  --- Deployed by Komodo
# docker compose -f ollama/docker-compose.yaml pull
docker compose -f komodo/docker-compose.yaml pull
# docker compose -f borg-ui/docker-compose.yaml pull  --- Deployed by Komodo
docker compose -f selenium/docker-compose.yaml pull
docker compose -f immich/docker-compose.yaml pull
docker compose -f borgmatic-ui/docker-compose.yaml pull

export DOCKER_HOST=ssh://bagpuss@172.24.32.11
echo "Pulling ultrafeeder stack"
docker compose -f ultrafeeder/docker-compose.yaml pull
docker compose -f komodo/docker-compose-sdrpi.yaml pull

export DOCKER_HOST=ssh://bagpuss@172.24.32.18
echo "Pulling octoprint stack"
docker compose -f octoprint/docker-compose.yaml pull
docker compose -f komodo/docker-compose-octoprint.yaml pull

export DOCKER_HOST=ssh://bagpuss@172.24.32.5
# docker compose -f scrutiny/docker-compose-blackbird.yaml pull  --- Deployed by Komodo
docker compose -f komodo/docker-compose-blackbird.yaml pull

export DOCKER_HOST=ssh://bagpuss@deepcore.glasgownet.com
echo "Pulling deepcore stacks"
docker compose -f traefik/docker-compose-deepcore.yaml pull
docker compose -f social-stack/docker-compose.yaml pull
# docker compose -f rss/docker-compose.yaml pull  --- Deployed by Komodo
docker compose -f obsidian-sync/docker-compose.yaml pull
# docker compose -f wallabag/docker-compose.yaml pull  --- Deployed by Komodo
