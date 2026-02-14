# Arquisoft - Infraestructura

Este directorio contiene la configuración de infraestructura para desplegar Arquisoft usando Docker Compose con arquitectura modular.

## Estructura

```
infrastructure/
├── docker-compose.yaml              # Base: networks, volumes
├── docker-compose.core.yaml         # PostgreSQL, RabbitMQ, MinIO
├── docker-compose.auth.yaml         # Keycloak
├── docker-compose.observability.yaml # Prometheus, Loki, Grafana
├── docker-compose.proxy.yaml        # Traefik (desarrollo, HTTP)
├── docker-compose.proxy-prod.yaml   # Traefik (producción, SSL)
├── docker-compose.dev.yaml          # Overrides desarrollo
├── docker-compose.prod.yaml         # Overrides producción
├── configs/                         # Configuración por servicio
│   └── traefik/
│       ├── dynamic/                 # Config dinámica desarrollo
│       └── dynamic-prod/            # Config dinámica producción (SSL)
└── scripts/                         # Scripts de operación
```

## Comandos Rápidos

### Desarrollo Local

```bash
# Levantar toda la infraestructura
./scripts/start.sh dev

# O manualmente:
docker-compose -f docker-compose.yaml \
               -f docker-compose.core.yaml \
               -f docker-compose.auth.yaml \
               -f docker-compose.observability.yaml \
               -f docker-compose.dev.yaml \
               up -d

# Levantar solo servicios core
docker-compose -f docker-compose.yaml -f docker-compose.core.yaml up -d

# Ver logs
docker-compose -f docker-compose.yaml -f docker-compose.core.yaml logs -f

# Detener todo
./scripts/stop.sh
```

### Producción

```bash
# Levantar con SSL automático (Let's Encrypt)
./scripts/start.sh prod

# O manualmente:
docker-compose -f docker-compose.yaml \
               -f docker-compose.core.yaml \
               -f docker-compose.auth.yaml \
               -f docker-compose.observability.yaml \
               -f docker-compose.proxy-prod.yaml \
               -f docker-compose.prod.yaml \
               up -d
```

**Requisitos producción:**
- Dominio configurado apuntando al servidor (ej: `arquisoft.uco.edu.co`)
- Puertos 80 y 443 abiertos
- Configurar `DOMAIN` y `ACME_EMAIL` en `.env`

**URLs producción (HTTPS automático):**
- App: `https://arquisoft.uco.edu.co`
- API: `https://api.arquisoft.uco.edu.co`
- Auth: `https://auth.arquisoft.uco.edu.co`
- Grafana: `https://grafana.arquisoft.uco.edu.co`

## Servicios y Puertos

| Servicio | Puerto Interno | Puerto Desarrollo | URL |
|----------|----------------|-------------------|-----|
| PostgreSQL | 5432 | 5432 | - |
| RabbitMQ | 5672 | 5672 | - |
| RabbitMQ Management | 15672 | 15672 | http://localhost:15672 |
| MinIO API | 9000 | 9000 | http://localhost:9000 |
| MinIO Console | 9001 | 9001 | http://localhost:9001 |
| Keycloak | 8080 | 8080 | http://localhost:8080 |
| Prometheus | 9090 | 9090 | http://localhost:9090 |
| Grafana | 3000 | 3000 | http://localhost:3000 |
| Loki | 3100 | 3100 | - |
| Traefik Dashboard | 8081 | 8081 | http://localhost:8081 |

## Credenciales por Defecto (Desarrollo)

> ⚠️ **NUNCA usar estas credenciales en producción**

| Servicio | Usuario | Contraseña |
|----------|---------|------------|
| PostgreSQL | arquisoft | arquisoft_dev_123 |
| RabbitMQ | arquisoft | arquisoft_dev_123 |
| MinIO | arquisoft | arquisoft_dev_123 |
| Keycloak Admin | admin | admin |
| Grafana | admin | admin |

## Requisitos

- Docker Engine 24.x+
- Docker Compose v2.20+
- 8 GB RAM mínimo (16 GB recomendado)
- 50 GB espacio en disco

## Documentación Adicional

- [Guía de Setup Completo](docs/SETUP.md)
- [Spike de Evaluación](../docs/spikes/SPIKE-001-orquestacion-infraestructura.md)
- [ADR-INFRA: Especificaciones Servidor](../docs/architecture/decisions/ADR-INFRA-especificaciones-servidor.md)
