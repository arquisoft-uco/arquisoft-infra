# Componente: observability (Loki + Prometheus + Grafana)

Stack de observabilidad. **No usa Promtail**: los logs y métricas los empuja **Grafana Alloy**
(que corre junto al backend, ver `components/backend`).

## Servicios
- **Loki** `:3100` — recibe logs (push de Alloy).
- **Prometheus** `:9090` — `--web.enable-remote-write-receiver` para el push de Alloy.
- **Grafana** — dashboards en `https://grafana.${DOMAIN}` (dev: `http://127.0.0.1:3000`).
  Datasources Prometheus y Loki ya aprovisionados.

## Uso
```bash
./deploy.sh dev observability
./deploy.sh prod observability

# Standalone
docker compose --env-file ../../.env up -d
```

## Multi-servidor
Este stack vive en el servidor de observabilidad. Para que Alloy (en otro servidor) empuje
datos, fijar `OBS_BIND_IP` a la IP privada de este servidor y abrir 3100/9090 **solo** a la
IP privada del servidor de aplicación (firewall). Single-server: dejar `OBS_BIND_IP=127.0.0.1`.
