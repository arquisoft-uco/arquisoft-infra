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

### Los archivos de configuración son generados — no están en git

`deploy.sh prepare_component proxy` genera dos archivos desde el `.env` de la raíz:

| Generado | Desde | Requiere |
|----------|-------|----------|
| `config/traefik.yml` | `config/traefik.yml.template` | `ACME_EMAIL` |
| `config/dynamic/.htpasswd` | hash apr1 de la contraseña | `ADMIN_AUTH_USER`, `ADMIN_AUTH_PASSWORD` |

Ambos están gitignored. **Nunca recrear el contenedor sin haberlos generado antes**: el
compose los monta por bind mount y, si no existen en disco, Traefik arranca sin resolver
ACME ni middlewares y el enrutamiento de toda la plataforma deja de funcionar. La forma
segura de levantarlo es siempre `./deploy.sh prod up proxy`, que los genera primero.

Los certificados viven en el volumen `arquisoft-traefik-letsencrypt` y **sobreviven** a
recrear el contenedor. No usar `down -v` sobre este componente: borraría `acme.json` y
forzaría la reemisión de todos los certificados, con riesgo de topar los límites de
Let's Encrypt.

### El `.htpasswd` debe coincidir con el `.env` vigente

El hash se calcula desde `ADMIN_AUTH_PASSWORD` **en el momento de generarlo**. Si después
se regenera el `.env` (p. ej. re-ejecutando `setup-env.sh`), el `.htpasswd` queda obsoleto
y `admin-auth@file` rechaza las credenciales del `.env` con un 401 indistinguible de "no
enviaste credenciales". Tras cambiar `ADMIN_AUTH_PASSWORD` hay que volver a desplegar el
proxy para regenerarlo.

Para comprobar si están sincronizados:

```bash
source .env
docker run --rm -v "$PWD/components/proxy/config/dynamic:/d" httpd:2.4-alpine \
  htpasswd -vb /d/.htpasswd "$ADMIN_AUTH_USER" "$ADMIN_AUTH_PASSWORD"
```

### El dashboard requiere su propio registro DNS

El router `dashboard` expone `https://traefik.${DOMAIN}`, y el resolver ACME usa el desafío
**HTTP-01**: si ese registro A no existe, Let's Encrypt responde `NXDOMAIN` y Traefik
**reintenta indefinidamente**, dejando un error recurrente en los logs y consumiendo cuota
de validaciones fallidas del dominio.

No afecta al resto de servicios, pero conviene resolverlo de una de estas dos formas:

- **Crear el registro A** `traefik.<DOMAIN>` apuntando a la IP del servidor (queda el
  dashboard accesible, protegido por `admin-auth@file`), o
- **quitar los labels del router `dashboard`** de `docker-compose.yml` si no se va a usar.

Para diagnosticarlo:

```bash
docker logs arquisoft-traefik 2>&1 | grep 'dashboard@docker' | tail -3
```
