export DOCKER_HOST=ssh://bagpuss@172.24.32.13
echo "Pulling media stack"
docker compose -f media-stack/docker-compose.yaml pull
docker compose -f komodo/docker-compose.yaml pull
docker compose -f selenium/docker-compose.yaml pull

export DOCKER_HOST=ssh://bagpuss@172.24.32.11
docker compose -f komodo/docker-compose-sdrpi.yaml pull

export DOCKER_HOST=ssh://bagpuss@172.24.32.18
docker compose -f komodo/docker-compose-octoprint.yaml pull

export DOCKER_HOST=ssh://bagpuss@172.24.32.5
docker compose -f komodo/docker-compose-blackbird.yaml pull

export DOCKER_HOST=ssh://bagpuss@deepcore.glasgownet.com
echo "Pulling deepcore stacks"
docker compose -f social-stack/docker-compose.yaml pull
docker compose -f obsidian-sync/docker-compose.yaml pull
