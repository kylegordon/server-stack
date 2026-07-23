# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

A collection of Docker Compose files that define the home server infrastructure, deployed across multiple physical hosts. There is no build step — the "code" is YAML configuration for Docker services.

Docker Compose v2.38.2 / Docker 28.0.4.

## Hosts and deployment targets

| Host | Address | Role |
|------|---------|------|
| homeauto | 172.24.32.13 | Primary server — runs the majority of stacks |
| adsb | 172.24.32.11 | ADS-B receiver (ultrafeeder, SDR) |
| octoprint | 172.24.32.18 | 3D printer host |
| blackbird | 172.24.32.5 | NFS storage server |
| littlegeek | 100.92.153.11 | Secondary/laptop |
| deepcore | 100.98.130.51 | Public-facing server (Tailscale) |

All remote `docker compose` commands set `DOCKER_HOST=ssh://bagpuss@<address>` before running.

## Validating compose files

```bash
# Validate syntax (exit 0 = valid; missing .env files warn but don't fail)
docker compose -f <path>/docker-compose.yaml config --quiet

# Batch check all services
for f in */docker-compose.yaml; do docker compose -f "$f" config --quiet 2>&1 | grep -i error && echo "Error in $f"; done
```

Do **not** run `up.sh`, `pull.sh`, or any `docker compose up` commands unless the user explicitly asks — they use SSH to remote hosts and won't work in a sandbox.

## Deploying

Deploy all stacks to all hosts:
```bash
./up.sh
```

Deploy a single stack (example):
```bash
export DOCKER_HOST=ssh://bagpuss@172.24.32.13
docker compose -f traefik/docker-compose.yaml up -d
```

Pull images without restarting:
```bash
./pull.sh
```

`stackup.sh` is a legacy Docker Swarm deployment script — it is no longer the primary deploy method.

## Architecture

### Shared infrastructure (deploy first)

1. **`network-stack`** — creates the `traefik_proxy` and `homeautomation` Docker networks. A keepalive container holds these networks so they survive stack restarts. All other stacks reference these networks as external.
2. **`traefik`** — reverse proxy and TLS termination for all HTTPS services (see `traefik/README.md`).
3. **`core-stack`** — infrastructure services (TFTP, Authelia placeholder, Meshtastic).

### Common includes

`common/networks.yaml` and `common/volumes.yaml` define shared external network references and NFS volume definitions. Many stacks `include:` these files rather than redeclaring networks.

### Aggregate stacks

Some directories are umbrella compose files that `include:` several individual service directories:

- **`ha-stack`** — Home Assistant and tightly coupled services (Frigate, Node-RED, double-take, GivTCP, ESPHome, Zigbee2MQTT, Mosquitto, Matter Server, Predbat)
- **`media-stack`** — Sonarr, Radarr, Calibre, Jellyfin, nzbget, Hydra, Music Assistant
- **`monitoring-stack`**, **`elk-stack`**, **`social-stack`**, **`lemmy-stack`** — similar groupings

### NFS volumes

Persistent data lives on the NFS server at 172.24.32.5 (`/srv/nfs4/docker_nfs/…`). Volumes are declared with `driver: local` and NFS4 mount options. Media files are under `/media/Tank/`.

### Traefik / TLS

All HTTPS services use wildcard Let's Encrypt certificates for `*.viewpoint.house` and `*.glasgownet.com` via AWS Route 53 DNS challenge. When adding a service, use only:

```yaml
labels:
  - traefik.enable=true
  - traefik.http.routers.<name>.rule=Host(`myservice.viewpoint.house`)
  - traefik.http.routers.<name>.entrypoints=websecure
  - traefik.http.routers.<name>.tls=true
  - traefik.http.services.<name>.loadbalancer.server.port=<port>
```

Do **not** add `tls.certresolver` or `tls.domains` to individual service routers — this defeats the shared wildcard certificate.

### Watchtower auto-updates

Most services opt in to Watchtower image auto-updates:
```yaml
labels:
  - com.centurylinklabs.watchtower.enable=true
```

### Homepage integration

Services expose themselves to the [homepage](https://gethomepage.dev) dashboard via container labels:
```yaml
- homepage.group=<Group>
- homepage.name=<Display Name>
- homepage.icon=<icon>
- homepage.href=https://<service>.viewpoint.house
- homepage.description=<description>
```

## CI

`.github/workflows/gitguardian.yaml` runs GitGuardian secret scanning on every push and PR. Failures block merge — never commit credentials or tokens.

## File naming conventions

- Primary: `docker-compose.yaml`
- Host-specific variants: `docker-compose-<hostname>.yaml` (e.g. `docker-compose-deepcore.yaml`, `docker-compose-blackbird.yaml`)
- Env file examples: `<service>.env.example` or `.<service>.env.example`

## Known TODOs in the codebase

- `elk-stack/docker-compose.yaml:45` — remove `--environment container` flag after Elasticsearch 8.17.1/8.18.0
- `up.sh:15` — monitoring-stack `librenms env_file environment duplication` needs review
- Commented-out services in `up.sh`: miniflux, watchtower, warpgate, pixelfed

## Komodo

`komodo-stacks.toml` declares all stacks for Komodo (a container management platform). Komodo pulls from this repo and deploys stacks to the appropriate server. The `deploy = false` flag means Komodo tracks but does not auto-deploy on sync.

## Secrets / environment files

`.env` files are gitignored. Each service that needs secrets has a `*.env.example` template committed alongside. Copy the example and fill in real values:

```bash
cp traefik/traefik.env.example traefik/.env
# edit with real values
```

Services reference their env file via `env_file:` in the compose YAML. AWS credentials for Traefik's Route 53 DNS challenge are in `traefik/.env`.

## Renovate

`renovate.json` configures automated Docker image tag updates. Minor/patch updates are automerged. Major updates require manual approval. `getmeili/meilisearch` and `britkat/giv_tcp-ma` are pinned (updates disabled).
