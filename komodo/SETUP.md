# Komodo Setup Instructions

## Prerequisites

1. **Create NFS directories** on the NFS server (172.24.32.5):
   ```bash
   ssh bagpuss@172.24.32.5
   sudo mkdir -p /srv/nfs4/docker_nfs/komodo/mongo
   sudo mkdir -p /srv/nfs4/docker_nfs/komodo/mongo_config
   sudo mkdir -p /srv/nfs4/docker_nfs/komodo/periphery
   ```

2. **Configure environment variables**:
   ```bash
   cd /home/kyleg/docker-composes/server-stack/komodo

   # Copy the example file (already done)
   # cp .env.example .env

   # Edit the .env file
   nano .env
   ```

## Required Environment Variables

**CRITICAL**: You must change these security-related variables before deployment:

### Generate Random Secrets

Use this command to generate secure random secrets:
```bash
openssl rand -hex 32
```

Run it three times to generate values for:
- `KOMODO_PASSKEY`
- `KOMODO_WEBHOOK_SECRET`
- `KOMODO_JWT_SECRET`

### Minimum Required Changes

In your `.env` file, change:
1. `KOMODO_DB_PASSWORD` - MongoDB password
2. `KOMODO_PASSKEY` - Used for Core/Periphery authentication
3. `KOMODO_WEBHOOK_SECRET` - Used for webhook authentication
4. `KOMODO_JWT_SECRET` - Used for JWT token generation
5. `KOMODO_INIT_ADMIN_PASSWORD` - Initial admin user password

### Optional Configuration

- `KOMODO_HOST` - Already set to https://komodo.viewpoint.house
- `KOMODO_FIRST_SERVER` - Already configured for homeauto
- `TZ` - Set to Europe/London, change if needed
- `KOMODO_MONITORING_INTERVAL` - Default is 15-sec
- `KOMODO_RESOURCE_POLL_INTERVAL` - Default is 1-hr

## Deployment

### Deploy the Stack

```bash
cd /home/kyleg/docker-composes/server-stack

# Deploy just Komodo
export DOCKER_HOST=ssh://bagpuss@172.24.32.13
docker compose -f komodo/docker-compose.yaml up -d

# Or deploy all stacks
./up.sh
```

### Verify Deployment

```bash
export DOCKER_HOST=ssh://bagpuss@172.24.32.13

# Check container status
docker compose -f komodo/docker-compose.yaml ps

# View logs
docker compose -f komodo/docker-compose.yaml logs -f komodo
docker compose -f komodo/docker-compose.yaml logs -f mongo
```

## Initial Setup

1. Navigate to: **https://komodo.viewpoint.house**

2. You should see the Komodo login page

3. **If KOMODO_INIT_ADMIN_USERNAME is set** (default: admin):
   - Login with the admin username and password from your `.env` file
   - Change the password after first login

4. **If KOMODO_INIT_ADMIN_USERNAME is commented out**:
   - Click the "Sign Up" button
   - Create your first admin user
   - This disables further signups unless `KOMODO_DISABLE_USER_REGISTRATION=false`

5. The **homeauto** server should already be connected automatically via the local Periphery container

## Architecture

The stack deploys three containers:

1. **MongoDB** - Database for Komodo data
2. **Komodo Core** - Main application with web UI (port 9120)
3. **Komodo Periphery** - Agent for managing Docker on the local host (port 8120)

The Periphery agent runs alongside Core and automatically connects as the "first server". This allows Komodo to manage containers on the homeauto host immediately after deployment.

## Post-Setup Configuration

### Verify First Server Connection

1. Go to **Servers** in the sidebar
2. You should see "homeauto" with status "Ok"
3. The local Periphery container should be automatically connected
4. If not connected, check:
   - Periphery container is running: `docker ps | grep komodo-periphery`
   - The passkey matches in your `.env` file
   - Check logs: `docker logs komodo-periphery`

### Security Best Practices

1. **Change default admin password** immediately after first login
2. **Disable user registration** after creating admin:
   ```bash
   # In .env file:
   KOMODO_DISABLE_USER_REGISTRATION=true

   # Restart to apply
   docker compose -f komodo/docker-compose.yaml restart komodo
   ```

3. **Review authentication settings**:
   - Consider enabling OIDC or OAuth for additional security
   - Configure MFA if your auth provider supports it

### Configure Additional Servers

The local Periphery agent manages the homeauto host. To add more servers:

1. Install Komodo Periphery on target servers (see official docs)
2. Configure each periphery with the same `KOMODO_PASSKEY`
3. In Komodo UI: Servers → Create Server
4. Add server details (address, port) and connect

**Note**: You could also install additional Periphery agents on other hosts using the same docker-compose pattern, or use systemd-based installation for bare metal servers.

## Important Labels

The compose file includes these important labels:

- `komodo.skip` - Prevents Komodo from stopping its own containers with "Stop All Containers"
- Traefik labels - For HTTPS access via reverse proxy
- Watchtower labels - For automatic updates
- Homepage labels - For dashboard integration

## Troubleshooting

### Cannot Access UI

1. Check Traefik is running and configured
2. Verify DNS resolves komodo.viewpoint.house
3. Check container logs:
   ```bash
   docker compose -f komodo/docker-compose.yaml logs komodo
   ```

### Database Connection Issues

1. Check MongoDB is running:
   ```bash
   docker compose -f komodo/docker-compose.yaml ps mongo
   ```

2. Verify credentials in `.env` match
3. Check MongoDB logs:
   ```bash
   docker compose -f komodo/docker-compose.yaml logs mongo
   ```

### Cannot Connect to First Server

1. Verify all three containers are running:
   ```bash
   docker compose -f komodo/docker-compose.yaml ps
   ```

2. Check Periphery is accessible from Core container:
   ```bash
   docker exec komodo curl http://periphery:8120/health
   ```

3. Check passkey matches in `.env` file (used by both Core and Periphery)
4. Review logs:
   ```bash
   docker logs komodo
   docker logs komodo-periphery
   ```

## Environment Variables Reference

See the official documentation for all available options:
- **Core Config**: https://github.com/moghtech/komodo/blob/main/config/core.config.toml
- **Periphery Config**: https://github.com/moghtech/komodo/blob/main/config/periphery.config.toml

## Backup

Komodo includes built-in database backup functionality. To enable:

1. Uncomment the backup volume mount in docker-compose.yaml
2. Configure backup schedule in Komodo UI
3. Backups are stored in the mounted volume

## Updates

The stack uses `ghcr.io/moghtech/komodo-core:latest` and has Watchtower labels enabled, so it will automatically update to the latest version.

To manually update:
```bash
cd /home/kyleg/docker-composes/server-stack
./pull.sh
./up.sh
```
