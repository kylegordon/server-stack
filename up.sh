docker-compose -H ssh://bagpuss@172.24.32.13 -f core-stack/docker-compose.yaml up -d
docker-compose -H ssh://bagpuss@172.24.32.13 --env-file frontend/docker.env -f frontend/docker-compose.yaml up -d
docker-compose -H ssh://bagpuss@deepcore.glasgownet.com --env-file frontend/docker-deepcore.env -f frontend/docker-compose-deepcore.yaml up -d
docker-compose -H ssh://bagpuss@172.24.32.13 -f ha-stack/docker-compose.yaml up -d
docker-compose -H ssh://bagpuss@172.24.32.13 -f media-stack/docker-compose.yaml up -d
docker-compose -H ssh://bagpuss@172.24.32.13 -f monitoring-stack/docker-compose.yaml up -d
docker-compose -H ssh://bagpuss@172.24.32.13 -f elk-stack/docker-compose.yaml up -d
docker-compose -H ssh://bagpuss@172.24.32.13 -f elk-stack/docker-compose-deepcore.yaml up -d
docker-compose -H ssh://bagpuss@deepcore.glasgownet.com -f social-stack/docker-compose.yaml up -d
# docker-compose -H ssh://bagpuss@deepcore.glasgownet.com -f social-stack/pixelfed.yaml up -d
