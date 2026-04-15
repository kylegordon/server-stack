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

Edit the `.env` file and set secure credentials. **Critical variables to change**:

- `KOMODO_DB_PASSWORD`: MongoDB password
- `KOMODO_PASSKEY`: Used for Core/Periphery authentication (generate with `openssl rand -hex 32`)
- `KOMODO_WEBHOOK_SECRET`: Used for webhook authentication (generate with `openssl rand -hex 32`)
- `KOMODO_JWT_SECRET`: Used for JWT token generation (generate with `openssl rand -hex 32`)
- `KOMODO_INIT_ADMIN_PASSWORD`: Initial admin user password

See `SETUP.md` for detailed configuration instructions.

### Server Connections

The stack includes:

**Homeauto (primary):**
- Deploys: Komodo Core, Periphery, and MongoDB
- Periphery automatically connects as the "homeauto" server
- Address: `http://172.24.32.13:8120`

**Blackbird:**
- Deploys: Periphery agent only (`docker-compose-blackbird.yaml`)
- Must be manually added in Komodo UI after deployment
- Address: `http://172.24.32.5:8120`
- Uses the same `KOMODO_PASSKEY` for authentication

**ADS-B Receiver:**
- Deploys: Periphery agent only (`docker-compose-sdrpi.yaml`)
- Must be manually added in Komodo UI after deployment
- Address: `http://172.24.32.11:8120`
- Uses the same `KOMODO_PASSKEY` for authentication

**OctoPrint:**
- Deploys: Periphery agent only (`docker-compose-octoprint.yaml`)
- Must be manually added in Komodo UI after deployment
- Address: `http://172.24.32.18:8120`
- Uses the same `KOMODO_PASSKEY` for authentication

All periphery agents connect using external IP addresses, maintaining a consistent connection model across all servers.

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

### Homeauto (Primary Stack)

Deploys Komodo Core, Periphery, and MongoDB to **homeauto** (172.24.32.13):

```bash
# Deploy Komodo stack specifically
export DOCKER_HOST=ssh://bagpuss@172.24.32.13
docker compose -f komodo/docker-compose.yaml up -d

# Or deploy all stacks
./up.sh
```

### Blackbird (Periphery Only)

Deploys Periphery agent to **blackbird** (172.24.32.5):

```bash
# Deploy blackbird periphery specifically
export DOCKER_HOST=ssh://bagpuss@172.24.32.5
docker compose -f komodo/docker-compose-blackbird.yaml up -d

# Or deploy all stacks (includes blackbird)
./up.sh
```

After deploying blackbird, add it as a server in the Komodo UI:
1. Navigate to **Servers** → **Create Server**
2. Name: `blackbird`
3. Address: `http://172.24.32.5:8120`
4. The passkey will be validated automatically

### ADS-B Receiver (Periphery Only)

Deploys Periphery agent to **ADS-B receiver** (172.24.32.11):

```bash
# Deploy ADS-B periphery specifically
export DOCKER_HOST=ssh://bagpuss@172.24.32.11
docker compose -f komodo/docker-compose-sdrpi.yaml up -d

# Or deploy all stacks (includes ADS-B receiver)
./up.sh
```

After deploying, add it as a server in the Komodo UI:
1. Navigate to **Servers** → **Create Server**
2. Name: `adsb-receiver` (or your preferred name)
3. Address: `http://172.24.32.11:8120`
4. The passkey will be validated automatically

### OctoPrint (Periphery Only)

Deploys Periphery agent to **OctoPrint** (172.24.32.18):

```bash
# Deploy OctoPrint periphery specifically
export DOCKER_HOST=ssh://bagpuss@172.24.32.18
docker compose -f komodo/docker-compose-octoprint.yaml up -d

# Or deploy all stacks (includes OctoPrint)
./up.sh
```

After deploying, add it as a server in the Komodo UI:
1. Navigate to **Servers** → **Create Server**
2. Name: `octoprint` (or your preferred name)
3. Address: `http://172.24.32.18:8120`
4. The passkey will be validated automatically

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

## Deployment Structure

**docker-compose.yaml** (homeauto):
- Komodo Core (web UI)
- Komodo Periphery (local agent)
- MongoDB (database)
- Uses NFS4 for persistent storage

**docker-compose-blackbird.yaml** (blackbird):
- Komodo Periphery (agent only)
- Uses local Docker volumes
- Connects to Core running on homeauto

**docker-compose-sdrpi.yaml** (ADS-B receiver / sdrpi):
- Komodo Periphery (agent only)
- Uses local Docker volumes
- Connects to Core running on homeauto

**docker-compose-octoprint.yaml** (OctoPrint):
- Komodo Periphery (agent only)
- Uses local Docker volumes
- Connects to Core running on homeauto

## Notes

- Requires Docker socket access for local container management
- MongoDB authentication is enabled by default
- The stack uses the `traefik_proxy` network for web access via Traefik
- Auto-updates enabled via Watchtower labels
- The same `.env` file is used on all hosts for shared passkey authentication
- Periphery agents (blackbird, ADS-B, OctoPrint) use local Docker volumes (not NFS) for simplicity
