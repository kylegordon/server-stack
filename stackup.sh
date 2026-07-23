export DOCKER_HOST=ssh://bagpuss@172.24.32.2
docker stack deploy -d --with-registry-auth --compose-file frontend/docker-compose.yaml frontend
docker stack deploy -d --with-registry-auth --compose-file ha-stack/docker-compose.yaml ha-stack
docker stack deploy -d --with-registry-auth --compose-file core-stack/docker-compose.yaml core-stack
docker stack deploy -d --with-registry-auth --compose-file media-stack/docker-compose.yaml media-stack
docker stack deploy -d --with-registry-auth --compose-file monitoring-stack/docker-compose.yaml monitoring-stack
docker stack deploy -d --with-registry-auth --compose-file warrior.yaml warrior
docker stack deploy -d --with-registry-auth --compose-file dawarich/docker-compose.yml dawarich