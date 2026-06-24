# Guía de Despliegue — Arquisoft IaC

Infraestructura como código modular, **sin Coolify**. Cada servicio vive en `components/<servicio>/`
y se despliega de forma independiente o en conjunto con `deploy.sh`. Traefik gestiona el SSL
automáticamente (Let's Encrypt) mediante labels.

## Requisitos
- Docker Engine 24+ y Docker Compose v2.
- `gettext` (provee `envsubst`) y `openssl`.
- En prod: dominio propio + registros DNS, y puertos 80/443 abiertos.

## Componentes
| Componente | Servicio | Expuesto a Internet |
|------------|----------|:-------------------:|
| `proxy` | Traefik (SSL) | Sí (`:80`, `:443`) |
| `postgres` | PostgreSQL app (7 BDs por contexto) | No |
| `keycloak` | Keycloak + BD dedicada | Sí (`auth.${DOMAIN}`) |
| `rabbitmq` | RabbitMQ | Consola: `rabbitmq.${DOMAIN}` |
| `redis` | Redis | No |
| `minio` | MinIO (pgsty) | `minio.${DOMAIN}`, `s3.${DOMAIN}` |
| `observability` | Loki, Prometheus, Grafana | Grafana: `grafana.${DOMAIN}` |
| `backend` | Spring Boot + Grafana Alloy | `api.${DOMAIN}` |
| `frontend` | SPA | `${DOMAIN}` |

---

## 1. Configuración inicial
```bash
# Genera .env con contraseñas seguras
./setup-env.sh dev                              # desarrollo local
./setup-env.sh prod arquisoft.top admin@arquisoft.top   # producción
```
Editar `.env` y completar `BACKEND_IMAGE`, `FRONTEND_IMAGE` (y `KEYCLOAK_CLIENT_SECRET`).

---

## 2. Despliegue en un solo servidor (single-server)
Todos los componentes comparten la red Docker `arquisoft-network` y se comunican por
nombre de servicio.

```bash
# Toda la infraestructura
./deploy.sh dev          # local (HTTP, puertos en 127.0.0.1)
./deploy.sh prod         # producción (HTTPS automático)

# Subconjunto / un componente
./deploy.sh prod up postgres redis keycloak
./deploy.sh prod status
./deploy.sh prod down keycloak
```
En **dev** el proxy se omite por defecto: cada servicio se accede por su puerto `127.0.0.1`.
`backend` y `frontend` se omiten si su `*_IMAGE` está vacío.

---

## 3. Despliegue en múltiples servidores
Cada servidor ejecuta `deploy.sh` con **solo los componentes que le tocan**, y los servicios
apuntan a sus dependencias por **IP privada** (variables `*_HOST` / `*_URL` en el `.env`).
Cada servidor con servicios públicos corre su **propia** instancia de `proxy`.

### Escenario recomendado (2 servidores)
- **S1 — Aplicación + Datos:** `proxy postgres redis rabbitmq minio keycloak backend frontend`
- **S2 — Observabilidad:** `observability`

En el `.env` de **S1**:
```ini
# Apuntar Alloy al servidor de observabilidad (IP privada de S2)
LOKI_URL=http://10.0.0.2:3100/loki/api/v1/push
PROMETHEUS_URL=http://10.0.0.2:9090/api/v1/write
```
En el `.env` de **S2**:
```ini
# Publicar Loki/Prometheus en la IP privada para recibir el push de Alloy
OBS_BIND_IP=10.0.0.2
```
```bash
# En S1
./deploy.sh prod up proxy postgres redis rabbitmq minio keycloak backend frontend
# En S2
./deploy.sh prod up observability
```

### Separar la capa de datos (3 servidores)
Mover `postgres redis rabbitmq minio` a un **S2 — Datos** y, en el `.env` de S1,
apuntar el backend a su IP privada:
```ini
POSTGRES_HOST=10.0.0.3
RABBITMQ_HOST=10.0.0.3
REDIS_HOST=10.0.0.3
MINIO_ENDPOINT=http://10.0.0.3:9000
```

> Mapa de servidores y dimensionamiento (CPU/RAM): ver
> [coolify/ARQUITECTURA_DESPLIEGUE.md](../coolify/ARQUITECTURA_DESPLIEGUE.md) y
> [coolify/RECURSOS.md](../coolify/RECURSOS.md) (ignorar lo específico de Coolify).

---

## 4. Firewall
| Puerto | Origen permitido | Uso |
|:------:|------------------|-----|
| 80, 443 | Internet | Traefik (HTTP-01 ACME + HTTPS) |
| 22 | Tu IP de administración | SSH |
| 5432, 5672, 6379, 9000 | Solo IP privada del servidor de aplicación | Datos (Postgres, RabbitMQ, Redis, MinIO) |
| 3100, 9090 | Solo IP privada del servidor de aplicación | Push de Alloy (Loki, Prometheus) |

Nunca exponer los puertos de datos/observabilidad a Internet.

---

## 5. DNS (producción)
Crear registros **A** hacia la IP del servidor que corre `proxy`:
`@` (raíz), `api`, `auth`, `grafana`, `rabbitmq`, `minio`, `s3`, `traefik`.

---

## 6. Backup y restauración
Ver [BACKUP.md](BACKUP.md) y [RESTORE.md](RESTORE.md).
