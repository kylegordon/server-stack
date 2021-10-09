docker-compose -f ha-stack/docker-compose.yaml -H ssh://bagpuss@homeauto.vpn.glasgownet.com pull
docker-compose -f media-stack/docker-compose.yaml -H ssh://bagpuss@homeauto.vpn.glasgownet.com pull
docker-compose -f elk-stack/docker-compose.yaml -H ssh://bagpuss@homeauto.vpn.glasgownet.com pull

