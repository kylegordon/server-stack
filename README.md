A collection of Docker Compose files that comprise the bulk of the home server setup.

[Home-Assistant Config](https://github.com/kylegordon/home-assistant-config/)

## TLS / Certificates

All HTTPS services are fronted by Traefik, which uses wildcard Let's Encrypt certificates (DNS challenge via Route 53) for `*.viewpoint.house` and `*.glasgownet.com`. See [`traefik/README.md`](traefik/README.md) for details on how the certificate strategy works and how to add new services.