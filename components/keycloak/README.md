# Componente: keycloak (Identity Provider)

Keycloak 26 con **base de datos PostgreSQL dedicada** (`keycloak-db`). No comparte el
PostgreSQL de la aplicación. Importa el realm `arquisoft` al arrancar.

## Servicios
- `keycloak-db` — PostgreSQL 18 exclusivo de Keycloak (volumen `arquisoft-keycloak-db-data`).
- `keycloak` — expuesto en `https://auth.${DOMAIN}` vía Traefik (labels).

## Realm
`config/realm-arquisoft.json.template` se renderiza a `config/realm-arquisoft.json` con
`deploy.sh` (envsubst con `KC_REALM_ADMIN_*` y `DOMAIN`). Se importa solo si el realm no existe.

## Uso
```bash
./deploy.sh dev keycloak     # start-dev, http://127.0.0.1:8080
./deploy.sh prod keycloak    # https://auth.${DOMAIN}

# Standalone
docker compose --env-file ../../.env up -d
```

## Notas de producción
- `KC_HOSTNAME=https://auth.${DOMAIN}` y `KC_PROXY_HEADERS=xforwarded` (detrás de Traefik).
- El usuario admin de arranque (`KC_BOOTSTRAP_ADMIN_*`) es temporal: crear un admin
  permanente en el realm `master` y rotar el de bootstrap.
- Multi-servidor: Keycloak y su DB van juntos en el servidor de aplicación.
