echo "----- Deploying to homeauto -----"
export DOCKER_HOST=ssh://bagpuss@172.24.32.13

docker compose -f network-stack/docker-compose.yaml up -d  # creates shared traefik_proxy + homeautomation networks
docker compose -f mdns_repeater/docker-compose.yaml up -d
docker compose -f komodo/docker-compose.yaml up -d  # Komodo Core + Periphery + MongoDB

echo "----- Deploying to ADS-B receiver (172.24.32.11) -----"
export DOCKER_HOST=ssh://bagpuss@172.24.32.11
docker compose -f komodo/docker-compose-sdrpi.yaml up -d  # Komodo Periphery agent

echo "----- Deploying to OctoPrint (172.24.32.18) -----"
export DOCKER_HOST=ssh://bagpuss@172.24.32.18
docker compose -f komodo/docker-compose-octoprint.yaml up -d  # Komodo Periphery agent

echo "----- Deploying to Blackbird -----"
export DOCKER_HOST=ssh://bagpuss@172.24.32.5
docker compose -f komodo/docker-compose-blackbird.yaml up -d  # Komodo Periphery agent

echo "----- Deploying to LittleGeek -----"
export DOCKER_HOST=ssh://bagpuss@100.92.153.11
docker compose -f komodo/docker-compose-littlegeek.yaml up -d  # Komodo Periphery agent

echo "----- Deploying to Deepcore -----"
export DOCKER_HOST=ssh://bagpuss@100.98.130.51
docker compose -f komodo/docker-compose-deepcore.yaml up -d  # Komodo Periphery agent
docker compose -f social-stack/docker-compose.yaml up -d
docker compose -f obsidian-sync/docker-compose.yaml up -d
