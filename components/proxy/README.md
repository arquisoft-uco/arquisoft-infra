# Componente: proxy (Traefik)

Reverse proxy con **SSL automático** (Let's Encrypt). Cada servicio publica su ruta
mediante **labels de Docker** — no hay que tocar este componente al agregar servicios.

## Qué hace
- Entrypoints `:80` (redirige a HTTPS) y `:443`.
- Resolver ACME `letsencrypt` por HTTP-01.
- Dashboard en `https://traefik.${DOMAIN}` protegido con BasicAuth.
- Middlewares reutilizables en `config/dynamic/middlewares.yml` (`secure-headers`, `admin-auth`).

## Requisitos
- Red externa `arquisoft-network` creada (`docker network create arquisoft-network`).
- Puertos 80 y 443 abiertos en el firewall.
- DNS de los subdominios apuntando a la IP del servidor.
- `ACME_EMAIL` definido en el `.env` raíz (solo prod).

## Uso
```bash
# Producción (desde la raíz del repo)
./deploy.sh prod proxy

# Standalone
docker compose --env-file ../../.env up -d
```

## Cómo exponer un servicio (patrón de labels)
```yaml
labels:
  - "traefik.enable=true"
  - "traefik.http.routers.miapp.rule=Host(`miapp.${DOMAIN}`)"
  - "traefik.http.routers.miapp.entrypoints=websecure"
  - "traefik.http.routers.miapp.tls=true"
  - "traefik.http.routers.miapp.tls.certresolver=letsencrypt"
  - "traefik.http.services.miapp.loadbalancer.server.port=8080"
```

## Multi-servidor
Cada servidor con servicios expuestos a Internet corre su **propia** instancia de este
componente. El certificado se emite localmente en cada nodo.

## Notas operativas

### Quién gestiona realmente este componente

En el despliegue actual **Traefik lo gestiona Terraform**, no `docker compose`:
`terraform/modules/proxy/main.tf` define `docker_container.traefik`. La configuración
**no se monta por bind mount**: se inyecta dentro del contenedor con bloques `upload`.

| Archivo dentro del contenedor | Origen en Terraform |
|-------------------------------|---------------------|
| `/etc/traefik/traefik.yml` | `templatefile(config/traefik.yml.template, { ACME_EMAIL })` |
| `/etc/traefik/dynamic/middlewares.yml` | `file(config/dynamic/middlewares.yml)` |
| `/etc/traefik/dynamic/.htpasswd` | `"${var.admin_user}:${var.admin_bcrypt}"` |

Por eso **es normal** que `config/traefik.yml` y `config/dynamic/.htpasswd` no existan en
disco: solo viven dentro del contenedor. No es un despliegue incompleto.

> **No mezclar los dos métodos.** El `docker-compose.yml` de esta carpeta y
> `./deploy.sh prod up proxy` son una vía **alternativa** que monta la config por bind
> mount y crea un contenedor que Terraform no conoce. Usarla sobre un entorno gestionado
> por Terraform deja dos gestores compitiendo por el nombre `arquisoft-traefik`: el
> siguiente `terraform apply` intentará recrear el suyo y chocará. Si el entorno se
> despliega con Terraform, el proxy se toca **solo** con Terraform.

### Las credenciales del dashboard no salen del `.env` raíz

El `.htpasswd` que usa `admin-auth@file` lo escribe Terraform con `var.admin_bcrypt`, que
viene del módulo `secrets` (`random_password.this["admin_auth_password"].bcrypt_hash`).
`ADMIN_AUTH_USER` / `ADMIN_AUTH_PASSWORD` del `.env` de la raíz **son otra fuente distinta**,
usada solo por la vía de `deploy.sh`. No son la misma credencial y no tienen por qué
coincidir: en un entorno Terraform, la contraseña del dashboard se consulta en el estado
(`terraform output`), no en el `.env`.

Un 401 de `admin-auth@file` es indistinguible de "no enviaste credenciales", así que ante
la duda conviene verificar de qué fuente sale el hash antes de suponer que está roto.

### Los certificados están en un volumen y sobreviven

`arquisoft-traefik-letsencrypt` guarda `acme.json` y persiste aunque el contenedor se
recree. **No usar `down -v`** ni borrar ese volumen: forzaría la reemisión de todos los
certificados, con riesgo de topar los límites de Let's Encrypt.

### El dashboard requiere su propio registro DNS

El router `dashboard` expone `https://traefik.${DOMAIN}` y el resolver ACME usa el desafío
**HTTP-01**: si ese registro A no existe, Let's Encrypt responde `NXDOMAIN` y Traefik
**reintenta indefinidamente** (con backoff), dejando un error recurrente en los logs y
consumiendo cuota de validaciones fallidas del dominio.

No afecta al resto de servicios — es solo el dashboard. Dos salidas posibles:

- **Crear el registro A** `traefik.<DOMAIN>` apuntando a la IP del servidor, o
- **quitar los labels del router `dashboard`**, que están en `local.labels` de
  `terraform/modules/proxy/main.tf` (y replicados en el `docker-compose.yml` de esta
  carpeta). Requiere `apply` y **recrea el contenedor**.

Para diagnosticarlo:

```bash
docker logs arquisoft-traefik 2>&1 | grep 'dashboard@docker' | tail -3
```

### Qué expone el dashboard

Sale a Internet por el entrypoint `websecure` (443), pero `api.insecure: false` significa
que **no hay ningún puerto sin protección**: solo se llega por ese router, detrás de
`admin-auth@file` y `secure-headers@file`. Muestra routers, servicios, middlewares,
certificados y salud de los backends. No expone datos de la aplicación, pero sí revela la
topología interna, por lo que el BasicAuth no es opcional. Es puramente administrativo: la
plataforma funciona igual sin él.
