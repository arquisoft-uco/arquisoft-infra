# Firewall — Arquisoft IaC

Guía **global** de hardening de red, válida para cualquier servidor donde se despliegue la infra
(un solo servidor o varios). El control se define por **rol del servidor**, no por una máquina
concreta. Postura por defecto: **denegar todo lo entrante, permitir solo lo necesario.**

> Defensa en profundidad: la IaC ya no publica puertos de datos al host (solo Traefik expone
> 80/443). El firewall refuerza esa postura y protege servicios del host (SSH y cualquier puerto
> ajeno a Docker).

## Postura por defecto
- `default deny incoming` · `default allow outgoing`.
- SSH (22) permitido — **restringirlo a una IP/red de administración** cuando sea posible.
- Solo se abren los puertos que el **rol** del servidor requiere.

## Roles y puertos

| Rol del servidor | Servicios | Puertos a permitir | Origen permitido |
|------------------|-----------|--------------------|------------------|
| Proxy / público | Traefik | 80, 443 | Internet |
| Aplicación | backend, keycloak, frontend (+ su Traefik) | 80, 443 | Internet |
| Datos | postgres, redis, rabbitmq, minio | 5432, 5672, 6379, 9000 | **Solo IP privada del servidor de aplicación** |
| Observabilidad | loki, prometheus | 3100, 9090 | **Solo IP privada del servidor de aplicación (Alloy)** |
| Todos | SSH | 22 | IP/red de administración |

Los puertos de datos y de observabilidad **nunca** deben abrirse a Internet.

## Uso del script (`firewall.sh`)
Ejecutar en **cada servidor** con las banderas de su rol (requiere `sudo`):

```bash
# Único servidor (todo junto)
sudo ./firewall.sh --public

# Servidor de aplicación (público) con SSH restringido a la red de admin
sudo ./firewall.sh --public --ssh-from 203.0.113.0/24

# Servidor de datos: abre 5432/5672/6379/9000 solo desde el servidor de aplicación
sudo ./firewall.sh --data-from 10.0.0.11

# Servidor de observabilidad: abre 3100/9090 solo desde el servidor de aplicación
sudo ./firewall.sh --obs-from 10.0.0.11

# Ver estado
sudo ./firewall.sh --status
```
El script permite SSH **antes** de habilitar ufw para no perder el acceso, y es idempotente.

## Mapeo a los escenarios de arquitectura
Referencia: [coolify/ARQUITECTURA_DESPLIEGUE.md](../coolify/ARQUITECTURA_DESPLIEGUE.md).

| Escenario | Servidor | Comando |
|-----------|----------|---------|
| 2 servidores | S1 (app+datos, público) | `sudo ./firewall.sh --public --ssh-from <admin>` |
| 2 servidores | S2 (observabilidad) | `sudo ./firewall.sh --obs-from <ip_privada_S1>` |
| 3 servidores | S1 (app, público) | `sudo ./firewall.sh --public --ssh-from <admin>` |
| 3 servidores | S2 (datos) | `sudo ./firewall.sh --data-from <ip_privada_S1>` |
| 3 servidores | S3 (observabilidad) | `sudo ./firewall.sh --obs-from <ip_privada_S1>` |

> Si un servidor de datos/observabilidad también corre su propio Traefik para exponer una consola
> por HTTPS (p.ej. `minio.`/`grafana.`), agregar `--public` en ese servidor.

## Caveat importante: Docker + ufw
Docker publica los puertos mapeados escribiendo reglas en iptables que **evitan la cadena INPUT
de ufw**. Por eso un `ufw deny` **no** filtra un puerto publicado por Docker (`ports:` a `0.0.0.0`).

Control correcto de los puertos de datos en multi-servidor (en orden de preferencia):
1. **No publicarlos a `0.0.0.0`**: enlazarlos a la **IP privada** (p.ej. `OBS_BIND_IP` para
   Loki/Prometheus) para que solo escuchen en la red interna.
2. **Security Group / reglas de entrada del proveedor cloud** restringidas a la IP privada de
   origen (la capa más confiable: actúa antes de llegar al host).
3. Reglas en la cadena `DOCKER-USER` o la herramienta [`ufw-docker`](https://github.com/chaifeng/ufw-docker)
   si se necesita filtrar puertos publicados por Docker con ufw.

`firewall.sh` cubre el nivel de host (SSH y puertos no-Docker) y abre 80/443/datos según el rol;
combínalo siempre con el bind a IP privada y el Security Group del proveedor.

## Proveedores cloud
En AWS/GCP/Azure/Hetzner/Oracle, replicar la misma matriz **rol → puerto → origen** en los
Security Groups / Firewall Rules / Network Security Groups del panel del proveedor. Esta capa es
independiente de ufw y se recomienda como control principal.

## Revisar puertos inesperados
Antes y después de aplicar, listar lo que escucha en el host y cerrar lo que no deba estar
público:
```bash
ss -ltnp | awk '$4 ~ /0.0.0.0|\[::\]/'
```
