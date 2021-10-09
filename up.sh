docker-compose -f ha-stack/docker-compose.yaml -H ssh://bagpuss@172.24.32.13 up -d
docker-compose -f media-stack/docker-compose.yaml -H ssh://bagpuss@172.24.32.13 up -d
#docker-compose -f elk-stack/docker-compose.yaml -H ssh://bagpuss@172.24.32.13 up -d
