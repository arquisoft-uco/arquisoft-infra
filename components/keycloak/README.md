# Componente: keycloak (Identity Provider)

Keycloak 26 con **base de datos PostgreSQL dedicada** (`keycloak-db`). No comparte el
PostgreSQL de la aplicación. Importa el realm `arquisoft` al arrancar.

## Servicios
- `keycloak-db` — PostgreSQL 18 exclusivo de Keycloak (volumen `arquisoft-keycloak-db-data`).
- `keycloak` — expuesto en `https://auth.${DOMAIN}` vía Traefik (labels).

## Realm
`config/realm-arquisoft.json.template` se renderiza a `config/realm-arquisoft.json` con
`deploy.sh` (envsubst con `KC_REALM_ADMIN_*` y `DOMAIN`). Se importa solo si el realm no existe.

### Audience en los access tokens (`arquisoft-api`)
El backend valida el claim `aud` del access token contra su propio `client_id`
(`arquisoft-api`) mediante un `AudienceValidator` (RFC 9700). Por defecto Keycloak **no**
incluye el client id propio en `aud` — solo `azp`. Sin un protocol mapper de tipo *Audience*,
el login funciona pero cualquier endpoint protegido responde `401` con:
```
An error occurred while attempting to decode the Jwt: El token no contiene la audiencia requerida: arquisoft-api
```
El template ya incluye este mapper (`oidc-audience-mapper`, Included Client Audience =
`arquisoft-api`, Add to access token = ON, Add to ID token = OFF) tanto en el cliente
`arquisoft-api` (tokens por password/client-credentials grant directo) como en `react-app`
(tokens del login del frontend que también llaman al backend). Se aplica automáticamente en
un import de realm nuevo (volumen `keycloak-db-data` vacío).

**Si ya tienes un realm importado previamente** (Keycloak solo importa si el realm no existe
aún), el mapper no aparece solo — hay que agregarlo a mano desde la consola de admin:
1. `https://auth.${DOMAIN}` (o `http://localhost:8080` en dev) → login como admin.
2. Realm `arquisoft` → **Clients** → `arquisoft-api`.
3. **Client scopes** → `arquisoft-api-dedicated` → **Add mapper** → **By configuration**.
4. Elegir **Audience** → *Included Client Audience*: `arquisoft-api` → *Add to access token*: ON
   → *Add to ID token*: OFF → **Save**.
5. Repetir en el cliente `react-app` si el frontend llama directamente al backend.

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
