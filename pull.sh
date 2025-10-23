export DOCKER_HOST=ssh://bagpuss@172.24.32.13
echo "Pulling core stack"
docker compose -f core-stack/docker-compose.yaml pull
echo "Pulling Traefik stack"
docker compose -f traefik/docker-compose.yaml pull
echo "Pulling HA stack"
docker compose -f ha-stack/docker-compose.yaml pull
echo "Pulling media stack"
docker compose -f media-stack/docker-compose.yaml pull
echo "Pulling elk stack"
docker compose -f elk-stack/docker-compose.yaml pull
echo "Pulling monitoring stack"
docker compose -f monitoring-stack/docker-compose.yaml pull
docker compose -f dawarich/docker-compose.yml pull
docker compose -f warrior.yaml pull
docker compose -f ollama/docker-compose.yaml pull

export DOCKER_HOST=ssh://bagpuss@172.24.32.5
docker compose -f scrutiny/docker-compose-blackbird.yaml pull

export DOCKER_HOST=ssh://bagpuss@deepcore.glasgownet.com
echo "Pulling deepcore stacks"
docker compose -f traefik/docker-compose-deepcore.yaml pull
docker compose -f pixelfed/docker-compose.yaml pull
docker compose -f social-stack/docker-compose.yaml pull
docker compose -f rss/docker-compose.yaml pull
docker compose -f obsidian-sync/docker-compose.yaml pull
docker compose -f wallabag/docker-compose.yaml pull
