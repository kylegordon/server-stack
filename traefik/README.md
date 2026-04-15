# Traefik

Traefik is the reverse proxy and TLS termination layer for the entire stack. It automatically discovers services via Docker labels and routes HTTPS traffic to them.

## Overview

- **Reverse proxy**: routes `*.viewpoint.house` and `*.glasgownet.com` traffic to the correct container
- **TLS termination**: wildcard certificates from Let's Encrypt, obtained via DNS challenge
- **HTTP → HTTPS redirect**: handled per-service using Traefik middlewares
- **Multi-host**: `docker-compose.yaml` targets **homeauto** (172.24.32.13); `docker-compose-deepcore.yaml` targets **deepcore** (deepcore.glasgownet.com)

## TLS / Certificate strategy

Certificates are issued by **Let's Encrypt** using an **AWS Route 53 DNS challenge**. Because all services share two domain families (`*.viewpoint.house` and `*.glasgownet.com`), **wildcard certificates** are used instead of per-service certificates. This reduces Let's Encrypt API calls from ~50 individual requests down to 2.

### How it works

Two dedicated routers are defined on the Traefik container itself. Each router's sole purpose is to cause Traefik to request (and renew) the wildcard certificate for its domain:

```yaml
# viewpoint.house wildcard
- "traefik.http.routers.wildcard-viewpoint.rule=Host(`viewpoint.house`)"
- "traefik.http.routers.wildcard-viewpoint.entrypoints=websecure"
- "traefik.http.routers.wildcard-viewpoint.service=api@internal"
- "traefik.http.routers.wildcard-viewpoint.tls.certresolver=letsencrypt"
- "traefik.http.routers.wildcard-viewpoint.tls.domains[0].main=viewpoint.house"
- "traefik.http.routers.wildcard-viewpoint.tls.domains[0].sans=*.viewpoint.house"

# glasgownet.com wildcard
- "traefik.http.routers.wildcard-glasgownet.rule=Host(`glasgownet.com`)"
- "traefik.http.routers.wildcard-glasgownet.entrypoints=websecure"
- "traefik.http.routers.wildcard-glasgownet.service=api@internal"
- "traefik.http.routers.wildcard-glasgownet.tls.certresolver=letsencrypt"
- "traefik.http.routers.wildcard-glasgownet.tls.domains[0].main=glasgownet.com"
- "traefik.http.routers.wildcard-glasgownet.tls.domains[0].sans=*.glasgownet.com"
```

Traefik stores the certificates in `acme.json` on the NFS volume. When an individual service router specifies `tls=true` without a `certresolver`, Traefik automatically matches the service's `Host(...)` rule against the certificates already in its store and serves the correct wildcard certificate — no additional API call is made.

### Adding a new service

A service on either `*.viewpoint.house` or `*.glasgownet.com` needs only:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.<name>.rule=Host(`myservice.viewpoint.house`)
  - traefik.http.routers.<name>.entrypoints=websecure
  - traefik.http.routers.<name>.tls=true                    # uses wildcard cert automatically
  - traefik.http.services.<name>.loadbalancer.server.port=<port>
```

Do **not** add `tls.certresolver` or `tls.domains` to individual service routers — this would cause Traefik to request a separate certificate for that subdomain, defeating the wildcard approach.

### Adding a new domain

If a new top-level domain (other than `viewpoint.house` or `glasgownet.com`) needs a wildcard certificate, add a new router block to the Traefik service labels in both compose files, following the same pattern as the existing two routers.

## Environment variables

Copy `traefik.env.example` to `.env` and fill in real values before deploying:

| Variable | Description |
|---|---|
| `LETSENCRYPT_EMAIL` | Contact email for Let's Encrypt account registration |
| `AWS_ACCESS_KEY_ID` | IAM key with Route 53 write access for DNS challenge |
| `AWS_SECRET_ACCESS_KEY` | Corresponding IAM secret |
| `AWS_REGION` | AWS region containing the hosted zone (e.g. `eu-west-1`) |
| `AWS_HOSTED_ZONE_ID` | Route 53 hosted zone ID for the domain |

## Deployment

### homeauto (primary)

```bash
export DOCKER_HOST=ssh://bagpuss@172.24.32.13
docker compose -f traefik/docker-compose.yaml up -d
```

### deepcore (public-facing)

```bash
export DOCKER_HOST=ssh://bagpuss@deepcore.glasgownet.com
docker compose -f traefik/docker-compose-deepcore.yaml up -d
```

Or deploy both as part of the full stack:

```bash
./up.sh
```

## Storage

The ACME certificate store (`acme.json`) is persisted on an NFS4 volume:

- **homeauto**: `172.24.32.5:/srv/nfs4/docker_nfs/traefik/letsencrypt/`
- **deepcore**: local Docker volume (`traefik_letsencrypt`)

This means certificates survive container restarts and image upgrades without re-requesting them from Let's Encrypt.

## Access

- **Traefik dashboard** (homeauto): http://172.24.32.13:8090
- **Traefik dashboard** (deepcore): http://deepcore.glasgownet.com:8080
