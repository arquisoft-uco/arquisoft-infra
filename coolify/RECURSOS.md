# Recursos de Producción — Coolify

Guía de referencia para los límites (`limits`) y reservas (`reservations`) de CPU y RAM
de cada servicio desplegado en Coolify bajo ambiente de producción.

Los valores se aplican en Coolify en **Settings → Resource Limits** de cada recurso,
o directamente bajo `deploy.resources` en los stacks de Docker Compose personalizados:

```yaml
deploy:
  replicas: <replicas>
  resources:
    limits:
      cpus: '<limits.cpus>'
      memory: <limits.memory>
    reservations:
      cpus: '<reservations.cpus>'
      memory: <reservations.memory>
```

## Arquitectura de servidores

| Servidor | Servicios desplegados |
|----------|----------------------|
| **S1 — Backend** | Traefik, PostgreSQL, Keycloak + DB, RabbitMQ, Redis, MinIO, Backend, Alloy, Frontend |
| **S2 — Observabilidad** | Loki, Prometheus, Grafana |

> Todos los servicios pueden correr en un único servidor durante etapas tempranas;
> la separación S1/S2 es la configuración recomendada para producción estable.

---

## Tabla 1 — Mínimos (~200 usuarios concurrentes)

Configuración de arranque para atender ~200 usuarios activos con carga moderada.

| Recurso | Servidor | `replicas` | `limits.cpus` | `reservations.cpus` | `reservations.memory` | `limits.memory` |
|---------|:--------:|:----------:|:-------------:|:-------------------:|:---------------------:|:---------------:|
| Traefik ¹ | S1 / S2 | `1` | `'0.50'` | `'0.10'` | `64M` | `128M` |
| PostgreSQL | S1 | `1` | `'1.00'` | `'0.25'` | `256M` | `512M` |
| Keycloak | S1 | `1` | `'1.00'` | `'0.25'` | `512M` | `1G` |
| Keycloak DB ² | S1 | `1` | `'0.50'` | `'0.10'` | `128M` | `256M` |
| RabbitMQ | S1 | `1` | `'0.50'` | `'0.10'` | `128M` | `256M` |
| Redis | S1 | `1` | `'0.25'` | `'0.05'` | `64M` | `128M` |
| MinIO | S1 | `1` | `'0.50'` | `'0.25'` | `256M` | `512M` |
| Backend (Spring Boot) | S1 | `1` | `'1.00'` | `'0.50'` | `512M` | `1G` |
| Grafana Alloy | S1 | `1` | `'0.25'` | `'0.05'` | `128M` | `256M` |
| Frontend | S1 | `1` | `'0.50'` | `'0.10'` | `64M` | `256M` |
| Loki | S2 | `1` | `'1.00'` | `'0.25'` | `384M` | `1G` |
| Prometheus | S2 | `1` | `'0.50'` | `'0.10'` | `192M` | `512M` |
| Grafana | S2 | `1` | `'0.25'` | `'0.05'` | `96M` | `256M` |

### Hardware mínimo

| Servidor | vCPU | RAM | Disco |
|----------|:----:|:---:|:-----:|
| S1 | 4 | 8 GB | 80 GB SSD |
| S2 | 2 | 4 GB | 60 GB SSD |

---

## Tabla 2 — Recomendado (~200–500 usuarios concurrentes)

Configuración con headroom suficiente para picos de tráfico y JVM cálida.
Punto de partida recomendado para producción.

| Recurso | Servidor | `replicas` | `limits.cpus` | `reservations.cpus` | `reservations.memory` | `limits.memory` |
|---------|:--------:|:----------:|:-------------:|:-------------------:|:---------------------:|:---------------:|
| Traefik ¹ | S1 / S2 | `1` | `'1.00'` | `'0.20'` | `128M` | `256M` |
| PostgreSQL | S1 | `1` | `'2.00'` | `'1.00'` | `512M` | `1G` |
| Keycloak | S1 | `1` | `'2.00'` | `'1.00'` | `768M` | `2G` |
| Keycloak DB ² | S1 | `1` | `'1.00'` | `'0.25'` | `256M` | `512M` |
| RabbitMQ | S1 | `1` | `'1.00'` | `'0.25'` | `256M` | `512M` |
| Redis | S1 | `1` | `'0.50'` | `'0.10'` | `128M` | `256M` |
| MinIO | S1 | `1` | `'1.00'` | `'0.50'` | `512M` | `1G` |
| Backend (Spring Boot) | S1 | `1` | `'2.00'` | `'1.00'` | `1G` | `2G` |
| Grafana Alloy | S1 | `1` | `'0.50'` | `'0.10'` | `192M` | `512M` |
| Frontend | S1 | `1` | `'1.00'` | `'0.25'` | `128M` | `512M` |
| Loki | S2 | `1` | `'1.00'` | `'0.25'` | `512M` | `1536M` |
| Prometheus | S2 | `1` | `'1.00'` | `'0.25'` | `384M` | `1G` |
| Grafana | S2 | `1` | `'0.50'` | `'0.10'` | `128M` | `512M` |

### Hardware recomendado

| Servidor | vCPU | RAM | Disco |
|----------|:----:|:---:|:-----:|
| S1 | 8 | 16 GB | 120 GB SSD |
| S2 | 4 | 8 GB | 80 GB SSD |

---

## Tabla 3 — Escalado (>500 usuarios concurrentes)

Configuración para alta disponibilidad con réplicas horizontales en los servicios
críticos. Los valores de CPU y RAM corresponden a **una sola instancia**. ³

| Recurso | Servidor | `replicas` | `limits.cpus` | `reservations.cpus` | `reservations.memory` | `limits.memory` |
|---------|:--------:|:----------:|:-------------:|:-------------------:|:---------------------:|:---------------:|
| Traefik ¹ | S1 / S2 | `1` | `'2.00'` | `'1.00'` | `256M` | `512M` |
| PostgreSQL | S1 | `1` | `'4.00'` | `'2.00'` | `1G` | `2G` |
| Keycloak | S1 | `2` | `'2.00'` | `'0.50'` | `1G` | `2G` |
| Keycloak DB ² | S1 | `1` | `'2.00'` | `'0.50'` | `512M` | `1G` |
| RabbitMQ | S1 | `1` | `'2.00'` | `'0.50'` | `512M` | `1G` |
| Redis | S1 | `1` | `'1.00'` | `'0.25'` | `256M` | `512M` |
| MinIO | S1 | `1` | `'2.00'` | `'0.50'` | `1G` | `2G` |
| Backend (Spring Boot) | S1 | `2` | `'2.00'` | `'1.00'` | `1536M` | `3G` |
| Grafana Alloy | S1 | `1` | `'1.00'` | `'0.25'` | `256M` | `512M` |
| Frontend | S1 | `2` | `'1.00'` | `'0.25'` | `256M` | `512M` |
| Loki | S2 | `1` | `'2.00'` | `'0.50'` | `1G` | `2G` |
| Prometheus | S2 | `1` | `'2.00'` | `'0.50'` | `512M` | `1536M` |
| Grafana | S2 | `1` | `'1.00'` | `'0.25'` | `256M` | `512M` |

### Hardware para escalar

| Servidor | vCPU | RAM | Disco |
|----------|:----:|:---:|:-----:|
| S1 | 16 | 32 GB | 200 GB SSD NVMe |
| S2 | 8 | 16 GB | 120 GB SSD |

---

## Notas

¹ **Traefik** es gestionado automáticamente por Coolify y no se despliega como
recurso independiente del usuario. Los valores son una referencia orientativa; para
ajustarlos se debe modificar la configuración del servidor en **Servers → Settings**
de la consola de Coolify.

² **Keycloak DB** es la instancia de PostgreSQL interna del recurso
`keycloak-with-postgres`. Sus límites se configuran en el sub-servicio `postgres`
dentro de ese mismo recurso en Coolify, no como un servicio PostgreSQL separado.

³ En la Tabla 3 los valores corresponden a **una sola instancia**. El recurso total
del servidor para servicios con réplicas es `valor × N réplicas`. Ejemplo: Backend
×2 con `limits.cpus: '2.00'` y `limits.memory: 3G` consume hasta 4 cores y 6 GB en total.
