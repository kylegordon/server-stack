# Traefik

Traefik is the reverse proxy and TLS termination layer for the entire stack. It automatically discovers services via Docker labels and routes HTTPS traffic to them.

## Overview

- **Reverse proxy**: routes `*.viewpoint.house` and `*.glasgownet.com` traffic to the correct container
- **TLS termination**: wildcard certificates from Let's Encrypt, obtained via a Route 53 DNS-01 challenge; deepcore additionally carries an HTTP-01 resolver for names in zones Route 53 does not host
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

### Adding a domain in a zone Route 53 does not host (deepcore)

> **Status:** configured on **deepcore only**, applied 2026-09-13 for the rmonitor live
> timing service.

The guidance above assumes the new domain is in a Route 53 hosted zone this stack holds
credentials for. **When it is not, that pattern cannot work at all**, and the failure is
silent: the router deploys cleanly, Traefik requests a certificate, the DNS challenge can
never be answered, and the site serves `TRAEFIK DEFAULT CERT` indefinitely with nothing in
the compose file looking wrong.

The `letsencrypt` resolver on both hosts is DNS-01 via Route 53:

```
--certificatesresolvers.letsencrypt.acme.dnschallenge=true
--certificatesresolvers.letsencrypt.acme.dnschallenge.provider=route53
```

It is scoped to one `AWS_HOSTED_ZONE_ID`, so it can only prove control of names in that
zone. A CNAME does not extend its reach: validation queries `_acme-challenge.<name>`, and a
CNAME at `<name>` covers that exact name only, not names beneath it.

#### The concrete case

`smart-timing.co.uk` is a third party's zone, served by Heart Internet. Two names in it —
`live.smart-timing.co.uk` and `live-timing.smart-timing.co.uk` — already CNAME to
`timing.glasgownet.com`, and serve the rmonitor timing page on deepcore. The zone's owner
will not be adding further records, so **HTTP-01 is the only challenge available**; DNS-01
is closed off in both forms (no usable provider for Heart Internet, and the
`_acme-challenge` delegation trick would itself need a new record in their zone).

#### The second resolver

`docker-compose-deepcore.yaml` carries a **second** resolver in the `traefik` service's
`command:` list, alongside the existing `letsencrypt` resolver, which is untouched:

```yaml
- --certificatesresolvers.letsencrypt-http.acme.httpchallenge=true
- --certificatesresolvers.letsencrypt-http.acme.httpchallenge.entrypoint=web
- --certificatesresolvers.letsencrypt-http.acme.email=${LETSENCRYPT_EMAIL}
- --certificatesresolvers.letsencrypt-http.acme.storage=/letsencrypt/acme-http.json
```

Notes on the shape of this:

- **Additive by design.** The `letsencrypt` resolver, the Route 53 credential and
  `acme.json` are not touched, so every certificate in the stack — both wildcards
  included — keeps renewing exactly as it did before.
- **Separate storage.** `acme-http.json`, not `acme.json`, so the two resolvers cannot
  interfere with one another.
- **No new credential.** HTTP-01 needs no DNS provider and no AWS access; the `web`
  entrypoint is already `:80` and already published, which is all the challenge requires.
- **Requesting services opt in explicitly** by naming `tls.certresolver=letsencrypt-http`
  on their own router. Nothing that does not name it is affected. This is the one documented
  exception to the "do not add `tls.certresolver` to individual service routers" rule above —
  that rule exists to protect the wildcard strategy, which by definition cannot cover a zone
  Route 53 does not host.
- **HTTP-01 tolerates this stack's redirect pattern — but only because the redirect is
  per-service.** Deepcore declares no **entrypoint-level** redirection: its `web` and
  `websecure` entrypoints in `docker-compose-deepcore.yaml` have no `redirections` sub-key.
  HTTP → HTTPS is done per-service with a `redirectscheme` middleware on the service's own
  `web` router, and Traefik's `acme-http@internal` router matches
  `PathPrefix('/.well-known/acme-challenge/')` at maximum priority, so it outranks a plain
  `Host(...)` service router. **Do not add an entrypoint-level redirect to deepcore**
  (`--entrypoints.web.http.redirections.entrypoint.to=websecure`): it creates a
  `web-to-websecure@internal` router that swallows the challenge request, and HTTP-01
  renewals then fail *silently*, surfacing ~60 days later as an expired certificate. See
  <https://github.com/traefik/traefik/issues/7825>.

#### Applying it

These are *static* arguments, read only at startup, so applying them **recreated the
`traefik` container and briefly interrupted every service behind it on that host** — not
just the one requesting the certificate. The same holds for any future change to these
arguments: worth picking the moment rather than rolling it out alongside an unrelated
change. Afterwards, check `docker logs traefik` for `letsencrypt-http` and for any
certificate-resolver error, and spot-check that existing sites still serve their current
certificates.

The resolver now exists on deepcore, so a service on that host may name
`tls.certresolver=letsencrypt-http` on its own router. This is **deepcore only** —
homeauto's `docker-compose.yaml` has no such resolver, and a router there naming one
Traefik does not have is rejected at load.

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

The ACME certificate store is persisted per host:

- **homeauto**: `acme.json` on the NFS4 volume `172.24.32.5:/srv/nfs4/docker_nfs/traefik/letsencrypt/`
- **deepcore**: local Docker volume (`traefik_letsencrypt`), which now holds **two** stores —
  `acme.json` for the DNS-01 resolver and `acme-http.json` for the HTTP-01 one

This means certificates survive container restarts and image upgrades without re-requesting them from Let's Encrypt.

## Access

- **Traefik dashboard** (homeauto): http://172.24.32.13:8090
- **Traefik dashboard** (deepcore): http://deepcore.glasgownet.com:8080
