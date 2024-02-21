echo "Pulling core stack"
docker-compose -H ssh://bagpuss@172.24.32.13 -f core-stack/docker-compose.yaml pull
echo "Pulling FrontEnd stack"
docker-compose -H ssh://bagpuss@172.24.32.13 --env-file frontend/docker.env -f frontend/docker-compose.yaml pull
echo "Pulling HA stack"
docker-compose -H ssh://bagpuss@172.24.32.13 -f ha-stack/docker-compose.yaml pull
echo "Pulling media stack"
docker-compose -H ssh://bagpuss@172.24.32.13 -f media-stack/docker-compose.yaml pull
echo "Pulling elk stack"
docker-compose -H ssh://bagpuss@172.24.32.13 -f elk-stack/docker-compose.yaml pull
echo "Pulling monitoring stack"
docker-compose -H ssh://bagpuss@172.24.32.13 -f monitoring-stack/docker-compose.yaml pull
echo "Pulling deepcore stacks"
docker-compose -H ssh://bagpuss@deepcore.glasgownet.com --env-file frontend/docker-deepcore.env -f frontend/docker-compose-deepcore.yaml pull
docker-compose -H ssh://bagpuss@deepcore.glasgownet.com -f pixelfed/docker-compose.yaml pull
docker-compose -H ssh://bagpuss@deepcore.glasgownet.com -f social-stack/docker-compose.yaml pull
