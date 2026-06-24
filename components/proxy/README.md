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
