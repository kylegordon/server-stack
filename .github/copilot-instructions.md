# Copilot Instructions for server-stack Repository

## Repository Overview

This is a **Docker Compose-based home server infrastructure** repository containing 50+ microservices deployed across multiple hosts. It manages a complete home automation, media, monitoring, and networking stack using Docker Compose with NFS4-backed persistent storage.

**Repository Size**: ~60 directories, 60+ docker-compose files  
**Primary Language**: YAML (Docker Compose v2.38.2)  
**Docker Version**: 28.0.4  
**Deployment Model**: Multi-host SSH-based remote Docker deployment

## Architecture & Project Layout

### Directory Structure
- **Root level**: Each directory represents a self-contained service with its own `docker-compose.yaml`
- **Key services**: `traefik/` (reverse proxy), `ha-stack/` (Home Assistant + dependencies), `media-stack/` (Sonarr/Radarr/Jellyfin), `elk-stack/` (logging), `monitoring-stack/` (LibreNMS/Grafana)
- **Deployment scripts**: `up.sh` (deploys all services), `pull.sh` (pulls latest images)
- **Config files**: `renovate.json` (dependency updates), `warrior.yaml` (standalone compose)

### Storage Architecture
**All volumes use NFS4 mounts** pointing to `172.24.32.5:/srv/nfs4/docker_nfs/<service>/` or `/media/Tank/` paths. This is critical for understanding volume configuration.

### Network Architecture
- **Primary network**: `traefik_traefik_proxy` - External network for all web-accessible services
- **Service-specific networks**: `homeautomation`, `monitoring`, `elastic`, etc.
- Services requiring external network access **must** specify: `name: traefik_traefik_proxy` and `external: true`

### Multi-Host Deployment
Three deployment targets controlled via `DOCKER_HOST` environment variable:
1. **homeauto** (172.24.32.13) - Main server with most services
2. **blackbird** (172.24.32.5) - NFS storage server with scrutiny/beszel
3. **deepcore** (deepcore.glasgownet.com) - Public-facing services (Traefik, social-stack, RSS)

### Service Dependencies (include: directive)
Several compose files use `include:` to depend on other services:
- `ha-stack/docker-compose.yaml` includes: double-take, frigate, node-red, predbat, givtcp, esphome, zigbee2mqtt, eclipse-mosquitto
- `media-stack/docker-compose.yaml` includes: sonarr, radarr, calibre, jellyfin, nzbget, hydra, music-assistant

## Build & Validation Instructions

### Validating Docker Compose Files

**Basic syntax validation** (works without env files):
```bash
docker compose -f <path>/docker-compose.yaml config --quiet
```
**Exit code 0** = valid syntax. **Exit code 1** = syntax error. Missing `.env` files will generate warnings but return exit code 0.

**Example validation workflow**:
```bash
# Validate a single service
docker compose -f warrior.yaml config --quiet && echo "Valid"

# Validate a stack with includes (will warn about missing .env files)
docker compose -f ha-stack/docker-compose.yaml config --quiet

# Validate multiple files
for f in */docker-compose.yaml; do docker compose -f "$f" config --quiet 2>&1 | grep -i error && echo "Error in $f"; done
```

### Environment File Requirements

**Many services require `.env` files** but these are gitignored (see `.gitignore`). The repository includes:
- `traefik/traefik.env.example` - Shows required format for AWS Route53 + Let's Encrypt
- Services commonly needing `.env`: traefik, pihole, frigate, grafana, miniflux, monitoring-stack, elk-stack, eplzones, fr24feed, ebusd, karakeep, matter-hub, mdns_repeater

**When modifying services with `env_file:` directive**, validation will fail without the `.env` file present. This is expected behavior - the service owner maintains these files separately.

### Deployment Workflow

**Do NOT run deployment commands** unless specifically instructed by the user. The deployment scripts use SSH to remote Docker hosts which won't work in the sandbox environment.

Deployment sequence (from `up.sh`):
```bash
# 1. Set target host
export DOCKER_HOST=ssh://bagpuss@172.24.32.13

# 2. Deploy services in specific order (dependencies first)
docker compose -f pihole/docker-compose.yaml up -d
docker compose -f core-stack/docker-compose.yaml up -d
docker compose -f traefik/docker-compose.yaml up -d
docker compose -f ha-stack/docker-compose.yaml up -d
# ... continues for all services

# 3. Switch hosts for secondary deployments
export DOCKER_HOST=ssh://bagpuss@172.24.32.5
docker compose -f scrutiny/docker-compose-blackbird.yaml up -d
```

**Deployment order matters**: pihole → core-stack → traefik → ha-stack are deployed first due to DNS and network dependencies.

### Image Update Workflow (from `pull.sh`)
```bash
export DOCKER_HOST=ssh://bagpuss@172.24.32.13
docker compose -f core-stack/docker-compose.yaml pull
docker compose -f traefik/docker-compose.yaml pull
# ... continues for all stacks
```

## Continuous Integration

### GitHub Actions Workflows
**Location**: `.github/workflows/gitguardian.yaml`

**GitGuardian Secret Scanning**:
- Triggers: On every push and pull request
- Purpose: Prevents secrets from being committed
- **Critical**: Never commit secrets, API keys, or credentials to any files
- Failures will block PR merge

**No build/test pipelines exist** - this is an infrastructure-as-code repository with no compilation step.

## Common Patterns & Conventions

### Docker Compose File Structure
All services follow this pattern:
```yaml
---
networks:
  traefik_proxy:
    external: true
    name: traefik_traefik_proxy

volumes:
  service_data:
    driver: local
    driver_opts:
      type: nfs4
      o: addr=172.24.32.5,rw
      device: ":/srv/nfs4/docker_nfs/service/"

services:
  service_name:
    image: namespace/image:version
    container_name: service_name
    networks:
      - traefik_proxy
    volumes:
      - service_data:/data
    labels:
      - traefik.enable=true
      - traefik.http.routers.service.rule=Host(`service.viewpoint.house`)
      - com.centurylinklabs.watchtower.enable=true
      - homepage.group=Category
    restart: unless-stopped
```

### Traefik Labels Convention
Services exposed via Traefik **must** include:
- `traefik.enable=true`
- Router rule: `traefik.http.routers.<name>.rule=Host(\`domain\`)`
- Entrypoint: `traefik.http.routers.<name>.entrypoints=web` or `websecure`
- Service port: `traefik.http.services.<name>.loadbalancer.server.port=<port>`
- For HTTPS: `traefik.http.routers.<name>.tls.certresolver=letsencrypt`
- Network specification: `traefik.docker.network=traefik_traefik_proxy`

### Watchtower Auto-Update Labels
Most services include: `com.centurylinklabs.watchtower.enable=true` for automatic updates

### Homepage Dashboard Labels
Services visible on homepage dashboard include:
- `homepage.group=<Category>`
- `homepage.name=<Display Name>`
- `homepage.href=<URL>`
- `homepage.icon=<mdi-icon>`

## Known Issues & Workarounds

### TODO Items
- `elk-stack/docker-compose.yaml:45` - Contains TODO comment about removing `--environment container` flag after Elasticsearch 8.17.1/8.18.0
- `up.sh:15` - monitoring-stack has note: "needs librenms env_file environment duplication looked at"
- Several services are commented out in `up.sh`: miniflux, watchtower, warpgate, pixelfed, obsidian-sync

### Compose Config Validation Quirks
- **Missing .env files generate warnings but are not errors** - exit code is still 0
- **Network name mismatches** cause: "invalid cluster node while attaching to network" - always use `name: traefik_traefik_proxy` for external networks
- **Some services have multiple compose files** (e.g., traefik/docker-compose-deepcore.yaml, scrutiny/docker-compose-blackbird.yaml) for different deployment hosts

### Renovate Dependency Management
- Renovate bot automatically updates Docker image versions
- `getmeili/meilisearch` updates are disabled (see `renovate.json`)
- Minor/patch updates auto-merge, major updates require manual approval

## Making Changes

### When Adding/Modifying Services:
1. **Always validate compose syntax**: `docker compose -f <file> config --quiet`
2. **Check for external network usage**: If exposing via Traefik, use `traefik_traefik_proxy` network with correct name
3. **Use NFS4 volumes**: Follow existing patterns for volume mounts pointing to 172.24.32.5
4. **Add appropriate labels**: Traefik routing, Watchtower updates, Homepage dashboard
5. **Consider deployment host**: Determine if service belongs on homeauto, blackbird, or deepcore
6. **Update deployment scripts if needed**: Add to `up.sh` and `pull.sh` in the correct host section

### File Naming Conventions
- Primary compose files: `docker-compose.yaml`
- Host-specific variants: `docker-compose-<hostname>.yaml`
- Environment examples: `<service>.env.example` or `traefik.env.example`

### When to Search vs. Trust Instructions
**Trust these instructions for**: Architecture, deployment workflow, validation commands, common patterns, network/volume conventions

**Search/explore when**: Finding specific service configurations not mentioned here, understanding service-specific environment variables, investigating uncommented service configurations in compose files

---
**Last Updated**: 2026-01-19 | **Docker Compose**: v2.38.2 | **Docker**: 28.0.4
