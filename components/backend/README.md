# Componente: backend (Spring Boot) + Grafana Alloy

Despliega la imagen del backend (construida en el repo `arquisoft-backend`) junto a su
agente de observabilidad **Grafana Alloy** (reemplaza a Promtail).

## Qué incluye
- **backend** — expuesto en `https://api.${DOMAIN}`. Wiring de entorno: 7 BDs por contexto,
  RabbitMQ, Redis, Keycloak y MinIO. Lleva el label `monitoring=arquisoft-backend`.
- **alloy** — captura los logs del backend (vía label) y los empuja a Loki; expone métricas
  del sistema y scrapea `/actuator/prometheus`, empujando todo a Prometheus (remote_write).

## Configurar la imagen
En el `.env` raíz: `BACKEND_IMAGE` y `BACKEND_TAG`. No hay que editar el compose.

## Uso
```bash
./deploy.sh dev backend      # perfil dev, API en 127.0.0.1:8080
./deploy.sh prod backend     # https://api.${DOMAIN}

# Standalone
docker compose --env-file ../../.env up -d
```

## Multi-servidor
El backend y Alloy corren en el servidor de aplicación. Ajustar en el `.env`:
- `POSTGRES_HOST`, `RABBITMQ_HOST`, `REDIS_HOST`, `KEYCLOAK_HOST`, `MINIO_ENDPOINT` → IP privada del servidor de datos.
- `LOKI_URL`, `PROMETHEUS_URL` → IP privada del servidor de observabilidad.
