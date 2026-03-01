# Komodo Stack

Komodo is a self-hosted Docker management platform for building and deploying software across multiple servers.

## About

Komodo provides:
- Docker container lifecycle management (deploy, start, stop, restart)
- Docker Compose stack management
- Build automation and image management
- Resource monitoring and alerting
- Web-based UI for server and container management

**Website**: https://komo.do/
**GitHub**: https://github.com/moghtech/komodo

## Services

- **komodo**: Main Komodo Core application with web UI (port 9120)
- **periphery**: Komodo Periphery agent for Docker management (port 8120)
- **mongo**: MongoDB database for Komodo data storage

The Periphery agent runs alongside Core and provides the ability to manage Docker containers on the local host.

## Configuration

### Environment Variables

Create a `.env` file in this directory based on `.env.example`:

```bash
cp .env.example .env
```

Edit the `.env` file and set secure credentials:

- `KOMODO_DB_USERNAME`: MongoDB username (default: komodo)
- `KOMODO_DB_PASSWORD`: MongoDB password (change this!)

### First Server Connection

The stack is configured to automatically connect to the Periphery agent running on homeauto:

- **Server Address**: http://172.24.32.13:8120
- **Server Name**: homeauto

## Storage

All persistent data is stored on NFS4 shares:

- **Komodo data**: `/srv/nfs4/docker_nfs/komodo/`
- **Periphery data**: `/srv/nfs4/docker_nfs/komodo/periphery/`
- **MongoDB data**: `/srv/nfs4/docker_nfs/komodo/mongo/`
- **MongoDB config**: `/srv/nfs4/docker_nfs/komodo/mongo_config/`

Ensure these directories exist on the NFS server (172.24.32.5) before deployment.

## Access

Once deployed, Komodo will be available at:

**https://komodo.viewpoint.house**

## Deployment

This stack is deployed to **homeauto** (172.24.32.13) as part of the automated deployment:

```bash
# Deploy Komodo stack specifically
export DOCKER_HOST=ssh://bagpuss@172.24.32.13
docker compose -f komodo/docker-compose.yaml up -d

# Or deploy all stacks
./up.sh
```

## Initial Setup

1. Navigate to https://komodo.viewpoint.house
2. Complete the initial setup wizard
3. Create your first admin user account
4. The homeauto periphery agent should already be connected (running locally in the stack)

## Features

- **Deployments**: Deploy individual Docker containers with full configuration control
- **Stacks**: Manage Docker Compose applications
- **Builds**: Build Docker images from Dockerfiles or repos
- **Servers**: Manage multiple server connections via Periphery agents
- **Procedures**: Create automated workflows combining multiple operations
- **Variables & Secrets**: Centralized configuration management with interpolation support
- **Resource Syncs**: GitOps-style resource management using TOML files
- **Monitoring**: Track server stats, container status, and receive alerts

## Notes

- Requires Docker socket access for local container management
- MongoDB authentication is enabled by default
- The stack uses the `traefik_proxy` network for web access via Traefik
- Auto-updates enabled via Watchtower labels
