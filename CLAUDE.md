# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Does

Infrastructure-as-code for the Arquisoft platform using modular Docker Compose. Manages PostgreSQL, RabbitMQ, MinIO, Keycloak, Prometheus, Loki, Grafana, and Traefik. Two deployment environments: `dev` (HTTP, localhost ports exposed) and `prod` (HTTPS via Let's Encrypt, all ports internal).

## Key Commands

### First-time setup
```bash
# Generate .env and supporting config files (idempotent — safe to re-run)
./scripts/setup-env.sh dev        # or prod

# To regenerate a specific file: delete it, then re-run setup-env.sh
rm .env && ./scripts/setup-env.sh prod
```

### Start / Stop
```bash
./scripts/start.sh dev            # All services, dev mode
./scripts/start.sh dev core       # Only PostgreSQL, RabbitMQ, MinIO
./scripts/start.sh dev auth       # Core + Keycloak
./scripts/start.sh prod           # All services, prod mode (requires DOMAIN + ACME_EMAIL)

./scripts/stop.sh [dev|prod]
./scripts/stop.sh dev --volumes   # Also destroys data volumes (destructive)
./scripts/stop.sh dev --prune     # Also prunes unused Docker resources
```

### Validation & Health
```bash
./scripts/validate-dev.sh               # Checks all dev acceptance criteria
./scripts/validate-dev.sh --persistence # Also tests volume persistence (restarts containers)
./scripts/validate-prod.sh              # DNS, SSL, HTTPS, security headers, resource limits
./scripts/health-check.sh              # Quick HTTP + TCP service health snapshot
```

### Manual docker compose (equivalent to start.sh)
```bash
docker compose \
  -f docker-compose.yaml \
  -f docker-compose.core.yaml \
  -f docker-compose.auth.yaml \
  -f docker-compose.observability.yaml \
  -f docker-compose.proxy.yaml \
  -f docker-compose.dev.yaml \
  up -d
```

## Architecture

### Compose File Layering

`docker-compose.yaml` is the mandatory base (defines the shared `arquisoft-network` bridge and all named volumes). Every `docker compose` invocation must include it first.

The remaining files are stacked on top:

| File | Purpose |
|------|---------|
| `docker-compose.core.yaml` | PostgreSQL, RabbitMQ, MinIO |
| `docker-compose.auth.yaml` | Keycloak |
| `docker-compose.observability.yaml` | Prometheus, Loki, Grafana |
| `docker-compose.proxy.yaml` | Traefik dev (HTTP only) |
| `docker-compose.proxy-prod.yaml` | Traefik prod (Let's Encrypt SSL) |
| `docker-compose.dev.yaml` | Dev overrides (exposes ports to 127.0.0.1) |
| `docker-compose.prod.yaml` | Prod overrides (resource limits, no exposed ports) |

### Template → Generated Files

`start.sh` uses `envsubst` (falls back to `sed`) to expand these templates at startup:

| Template | Generated |
|----------|-----------|
| `configs/traefik/dynamic.yaml.template` | `configs/traefik/dynamic/dynamic.yaml` |
| `configs/traefik/traefik-prod.yaml.template` | `configs/traefik/traefik-prod.yaml` |
| `configs/rabbitmq/definitions.json.template` | `configs/rabbitmq/definitions.json` |
| `configs/keycloak/realm-arquisoft.json.template` | `configs/keycloak/realm-arquisoft.json` |

Generated files are gitignored. Never edit them directly — edit the `.template` source.

### Shared Script Library (`scripts/lib/`)

All scripts source from `scripts/lib/`:
- `common.sh` — color output helpers (`log_success`, `log_error`, `log_warning`), `check_container_health`, `check_http_status`, `check_security_headers`, `print_summary`, `escape_sed`
- `env-config.sh` — `get_env_var`, `set_env_var`, `uncomment_env_var`
- `password-generator.sh` — secure random password generation
- `prometheus-config.sh` — generates `configs/prometheus/web.yml` (BasicAuth for prod)
- `traefik-config.sh` — generates `configs/traefik/certs/.htpasswd`

### PostgreSQL Schema Design

`configs/postgres/init.sql` runs once on first container creation. It creates:
- 10 bounded-context schemas: `usuarios`, `fichas_perfil`, `proyectos_grado`, `artefactos`, `evaluaciones`, `mapa_ruta`, `repositorio_artefactos`, `solicitudes`, `biblioteca`, `entregables`
- 1 technical schema: `keycloak` (used by Keycloak when it shares the database)
- Extensions: `uuid-ossp`, `pg_trgm`
- Global `audit_log` table in the `public` schema with a reusable trigger function

### Prometheus Scraping

Prometheus scrapes `host.docker.internal:8080/actuator/prometheus` for the backend application. This target resolves to the Docker host, so the backend can run outside the compose network during development. Other scrape targets (RabbitMQ, MinIO, Keycloak, Traefik, Loki) use internal Docker service names.

## CI/CD

Single workflow: `.github/workflows/deploy.yml` — manual trigger only (`workflow_dispatch`). Runs on a self-hosted runner (on-premise server). Requires the `ENV_FILE` repository secret to contain the full `.env` content. Inputs: `environment` (dev|prod) and `profile` (all|core|auth).

## Environment Variables

Copy `.env.example` to `.env` (or run `setup-env.sh`). Required variables:
- `DOMAIN` — `arquisoft.localhost` for dev, real domain for prod
- `ACME_EMAIL` — required only for prod (Let's Encrypt registration)
- All `*_PASSWORD` fields — auto-generated by `setup-env.sh` if not set

Prod-only files generated by `setup-env.sh`:
- `configs/prometheus/web.yml` — enables BasicAuth on Prometheus endpoints
- `configs/traefik/certs/.htpasswd` — BasicAuth for admin consoles (MinIO, Traefik dashboard)
