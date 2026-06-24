# Arquisoft — Infraestructura como Código

IaC modular en Docker Compose, **independiente de Coolify**. Cada servicio vive en
`components/<servicio>/` y se despliega solo o en conjunto. Traefik gestiona el **SSL
automático** (Let's Encrypt) mediante labels. Soporta **un servidor o varios**.

## Estructura
```
arquisoft-infra/
├── deploy.sh            # Orquestador (up / down / status)
├── setup-env.sh         # Genera .env con contraseñas seguras
├── backup.sh            # Backup de BDs y MinIO
├── restore.sh           # Restauración de backups
├── firewall.sh          # Hardening de firewall (ufw) por rol de servidor
├── .env.example         # Variables (fuente única)
├── components/          # Un componente por carpeta (compose + config + README)
│   ├── proxy/           # Traefik (SSL por labels)
│   ├── postgres/        # PostgreSQL app — 7 BDs por bounded context
│   ├── keycloak/        # Keycloak + PostgreSQL DEDICADO
│   ├── rabbitmq/  redis/  minio/
│   ├── observability/   # Loki, Prometheus, Grafana (logs/métricas vía Alloy)
│   ├── backend/         # Imagen del backend + Grafana Alloy (sidecar)
│   └── frontend/
├── scripts/lib/         # Helpers compartidos (bash)
├── docs/                # DESPLIEGUE / BACKUP / RESTORE
└── coolify/             # Referencia/legacy (guías del despliegue anterior)
```

## Inicio rápido
```bash
# 1. Variables (contraseñas autogeneradas)
./setup-env.sh dev                                    # local
# ./setup-env.sh prod arquisoft.top admin@arquisoft.top   # producción

# 2. Desplegar
./deploy.sh dev            # todo en local (HTTP, puertos 127.0.0.1)
./deploy.sh prod          # todo en producción (HTTPS automático)

# Subconjunto / operaciones
./deploy.sh prod up postgres redis keycloak
./deploy.sh prod status
./deploy.sh prod down keycloak
```

## Modelo de datos
El backend usa **7 bases de datos por bounded context** (no esquemas):
`usuarios`, `fichas_perfil`, `artefactos`, `repositorio_artefactos`, `proyectos_grado`,
`entregables`, `evaluaciones` (usuario `arquisoft_user`). La BD de Keycloak es **dedicada**
(componente `keycloak`), separada del PostgreSQL de la aplicación.

## Documentación
- [docs/DESPLIEGUE.md](docs/DESPLIEGUE.md) — single-server y multi-servidor, firewall, DNS.
- [docs/FIREWALL.md](docs/FIREWALL.md) — hardening de red por rol de servidor (global).
- [docs/BACKUP.md](docs/BACKUP.md) y [docs/RESTORE.md](docs/RESTORE.md).
- README de cada componente en `components/<servicio>/README.md`.

## Observabilidad
Sin Promtail. **Grafana Alloy** corre junto al backend: empuja logs a Loki y métricas
(sistema + `/actuator/prometheus`) a Prometheus por remote-write.
