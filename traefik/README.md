# Traefik

Traefik is the reverse proxy and TLS termination layer for the entire stack. It automatically discovers services via Docker labels and routes HTTPS traffic to them.

## Overview

- **Reverse proxy**: routes `*.viewpoint.house` and `*.glasgownet.com` traffic to the correct container
- **TLS termination**: on homeauto, wildcard certificates from Let's Encrypt via a Route 53
  DNS-01 challenge. **Deepcore is different** — it holds no AWS credential and issues
  per-name certificates over HTTP-01; see [Deepcore](#deepcore-http-01-per-name-not-wildcards)
- **HTTP → HTTPS redirect**: handled per-service using Traefik middlewares
- **Multi-host**: `docker-compose.yaml` targets **homeauto** (172.24.32.13); `docker-compose-deepcore.yaml` targets **deepcore** (deepcore.glasgownet.com)

## TLS / Certificate strategy (homeauto)

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

### Adding a new service (homeauto)

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

### Adding a new domain (homeauto)

If a new top-level domain (other than `viewpoint.house` or `glasgownet.com`) needs a wildcard certificate, add a new router block to the Traefik service labels in both compose files, following the same pattern as the existing two routers.

## Deepcore: HTTP-01 per-name, not wildcards

> Everything above describes **homeauto**. Deepcore does not work that way and never has.

Deepcore's `traefik` service carries **no `env_file:`** and therefore no AWS credential —
`docker inspect traefik` on that host shows `PATH` and nothing else. It also serves names in
zones Route 53 does not host at all: `swtvc.org`, `swtvc.org.uk`, `rlotte.me.uk`, and
`smart-timing.co.uk`. DNS-01 could never have issued any of them.

What deepcore actually runs is **two HTTP-01 resolvers**:

| Resolver | Store | Used by |
|---|---|---|
| `letsencrypt` | `/letsencrypt/letsencrypt.json` | everything on the host, including the `@file` routers |
| `letsencrypt-http` | `/letsencrypt/acme-http.json` | names opted in explicitly — currently rmonitor's `live.smart-timing.co.uk` |

Both are HTTP-01, so on this host they differ only in which store they write to. The split
exists so an opted-in third-party name cannot share a certificate, or a renewal failure, with
the host's own names.

Because these are HTTP-01, **wildcards are not available on deepcore.** A router asking for
`*.example.com` here will fail. Add each name explicitly.

### The static-config trap that hid this

> Fixed 2026-09-14. Worth reading before touching deepcore's `command:` list.

Traefik's three static-configuration sources — a config file, CLI arguments, and environment
variables — are **mutually exclusive**. Traefik auto-discovers `/etc/traefik/traefik.yml`,
`.yaml` or `.toml`; if one exists it is used and **the entire `command:` list is discarded**,
with nothing logged above DEBUG to say so.

Deepcore had a `/docker/traefik/traefik.yaml`, mounted in via `/docker/traefik/:/etc/traefik/`.
So every argument in `docker-compose-deepcore.yaml` had always been inert, and the compose file
had drifted into describing a configuration that was not running: it declared DNS-01 via Route 53
and a store at `acme.json`, while the live resolver was HTTP-01 writing `letsencrypt.json`. The
file also set `log.level: DEBUG` against the compose file's `INFO`, which was the visible tell.

The failure this produced was silent in the usual way. `rmonitor`'s router named
`tls.certresolver=letsencrypt-http`, a resolver declared only in the discarded `command:` list.
The router loaded, reported `status: enabled`, never placed an ACME order, and served
`TRAEFIK DEFAULT CERT` indefinitely. The only evidence was one line, at ERR, on each config
reload:

```
ERR > Router uses a nonexistent certificate resolver \
      certificateResolver=letsencrypt-http routerName=timing-smart@docker
```

**The fix:** the whole static configuration now lives in the compose `command:` list, and the
host file is gone (kept as `/docker/traefik/traefik.yaml.disabled-2026-09-14`). The repo is now
the source of truth for it.

`/docker/traefik/` is still mounted at `/etc/traefik/`, because the file *provider* reads
`config.yml` from it — the routers and services for `lodge`, `glasgownet.com`,
`www.glasgownet.com`, `www.rlotte.me.uk` and `swtvc`. That is *dynamic* config, is hot-reloaded,
and is unaffected by any of the above. It remains host-only state and is not in this repo.

**Keep that directory free of a `traefik.yaml`.** Static config goes in `command:`.

### Why static config cannot be a repo file

These stacks are deployed remotely, with `DOCKER_HOST=ssh://bagpuss@<host>`. Compose reads
`build:` contexts, `env_file:` and `configs:` sources from the **client** machine, while paths
in `volumes:` resolve on the **daemon** machine. So a static config file committed here could
not be bind-mounted to the target: the path would be interpreted on deepcore, where the repo
may not exist. Inline `command:` arguments have no filesystem dependency on either end, which
is why they are the right home for this.

For the same reason `LETSENCRYPT_EMAIL` carries an in-file default
(`${LETSENCRYPT_EMAIL:-kyle@glasgownet.com}`). It is not a secret, and an unset variable would
otherwise register the ACME account with an empty contact address — another silent, deferred
certificate failure.

### Opting a name in

HTTP-01 needs no credential; the `web` entrypoint is already `:80` and already published, which
is all the challenge requires. A service on deepcore opts in on its own router:

```yaml
- traefik.http.routers.<name>.tls=true
- traefik.http.routers.<name>.tls.certresolver=letsencrypt-http
```

HTTP-01 is compatible with the HTTP → HTTPS redirection this repo does per-service. Traefik's
`acme-http@internal` router matches `PathPrefix('/.well-known/acme-challenge/')` at the maximum
possible priority (`9223372036854775807`), so it outranks both a plain `Host(...)` router and the
`web-to-websecure@internal` router that entrypoint-level redirection would create. Verified on
the pinned `v3.7.13`: `/.well-known/acme-challenge/<token>` on `:80` is answered by the ACME
router while every other path redirects.
([traefik#7825](https://github.com/traefik/traefik/issues/7825) describes older behaviour and
does not apply to this version.)

### Applying a change to deepcore's static config

The `command:` list is read only at startup, so any change to it **recreates the `traefik`
container and briefly interrupts every service on that host** — not just the one being changed.
Pick the moment rather than rolling it out alongside something unrelated. Afterwards:

```bash
export DOCKER_HOST=ssh://bagpuss@deepcore.glasgownet.com
# both resolvers present, and no router pointing at a missing one
docker exec traefik wget -qO- http://127.0.0.1:8080/api/overview
docker logs traefik 2>&1 | grep -iE "nonexistent certificate resolver|acme|error"
```

and spot-check that the existing sites still serve their own certificates.

## Environment variables

Copy `traefik.env.example` to `.env` and fill in real values before deploying:

| Variable | Host | Description |
|---|---|---|
| `LETSENCRYPT_EMAIL` | both | Contact email for Let's Encrypt account registration. Deepcore defaults it in-file, so an unset value cannot silently break ACME registration there. |
| `AWS_ACCESS_KEY_ID` | homeauto | IAM key with Route 53 write access for DNS challenge |
| `AWS_SECRET_ACCESS_KEY` | homeauto | Corresponding IAM secret |
| `AWS_REGION` | homeauto | AWS region containing the hosted zone (e.g. `eu-west-1`) |
| `AWS_HOSTED_ZONE_ID` | homeauto | Route 53 hosted zone ID for the domain |

Deepcore needs **none** of the AWS variables — its `traefik` service deliberately has no
`env_file:`, and HTTP-01 requires no DNS provider.

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

The ACME certificate store is persisted per host:

- **homeauto**: `acme.json` on the NFS4 volume `172.24.32.5:/srv/nfs4/docker_nfs/traefik/letsencrypt/`
- **deepcore**: local Docker volume (`traefik_letsencrypt`), holding **two** stores —
  `letsencrypt.json` (the `letsencrypt` resolver, ~11 per-name certificates) and
  `acme-http.json` (the `letsencrypt-http` resolver). Note the first is `letsencrypt.json`,
  **not** `acme.json`: that name is inherited from the old host config file, and renaming it
  would reissue every certificate on the host.

This means certificates survive container restarts and image upgrades without re-requesting them from Let's Encrypt.

## Access

- **Traefik dashboard** (homeauto): http://172.24.32.13:8090
- **Traefik dashboard** (deepcore): http://deepcore.glasgownet.com:8080
