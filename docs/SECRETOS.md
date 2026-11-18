# Gestión de secretos (Doppler)

Los secretos viven en **Doppler**, workplace `arquisoft` (plan gratuito), en dos proyectos:

| Proyecto / config | Contenido | Lo consume |
|-------------------|-----------|------------|
| `arquisoft-infra/test` | `.env` raíz de la plataforma (postgres, redis, rabbitmq, minio, keycloak, traefik, observabilidad) | `~/arquisoft-infra/.env` del usuario `ubuntu` en el servidor Oracle, vía `scripts/fetch-secrets.sh` |
| `arquisoft-backend/test` | `.env` de runtime del backend | `deploy.yml` del repo **arquisoft-backend**: el servidor lo descarga en `/home/deploy/arquisoft/.env` en cada despliegue |

El config `dev` de `arquisoft-infra` queda reservado para desarrollo local (sin uso). El backend en
local sigue usando su propio `.env`, fuera de Doppler.

> **Por qué dos proyectos.** El backend tiene ~90 variables propias (logs, PEP, sesión,
> notificaciones, buckets…) y nombra distinto las credenciales compartidas (`DB_USUARIOS_PASSWORD`
> en vez de `APP_DB_PASSWORD`); además `REDIS_PASSWORD` significa cosas distintas en cada lado.
> Las referencias entre proyectos (`${proyecto.config.CLAVE}`) son de pago, así que las
> credenciales compartidas están **copiadas** (ver [Rotar una credencial](#rotar-una-credencial)).

Ningún script del repo llama a Doppler directamente salvo el adaptador
[`scripts/fetch-secrets.sh`](../scripts/fetch-secrets.sh): `deploy.sh` y los compose solo consumen
el `.env`. Cambiar de baúl = agregar un proveedor al adaptador.

## Dónde vive cada secreto

| Lugar | Qué va ahí | Criterio |
|-------|-----------|----------|
| **Doppler** | Contraseñas, claves y configuración que usan los servicios **en ejecución** | El servidor las lee con su propio token; nunca pasan por GitHub |
| **GitHub — Secrets** | Solo lo que el **pipeline** necesita para actuar: entrar al servidor por SSH y herramientas del CI | Nunca credenciales de la aplicación ni de la infraestructura |
| **GitHub — Variables** | Configuración **pública** de build (termina en el bundle del navegador) | Nunca un valor sensible |
| **Solo en el servidor** | Tokens de servicio de Doppler (`doppler configure set token`) | Ni en GitHub ni en el repo |
| **Cuenta personal** | Acceso de administradores a Doppler (correo propio + MFA) | No se comparte |

> Las credenciales SSH tienen que estar en GitHub mientras el despliegue lo **empuje** GitHub
> (Actions entra al servidor). Quitarlas exige invertir el modelo: que el servidor jale las imágenes
> nuevas por su cuenta.

### GitHub

| Repo | Tipo | Nombre | Para qué |
|------|------|--------|----------|
| arquisoft-backend | Secret | `SSH_HOST`, `SSH_PORT`, `SSH_USER`, `SSH_PRIVATE_KEY` | CD: conexión al servidor (usuario `deploy`) |
| | Secret | `BASE_DOMAIN` | Regla de Traefik `api.<dominio>` |
| | Secret | `SONAR_TOKEN`, `SONAR_HOST_URL` | Análisis de SonarQube en el CI |
| | Secret (opcional) | `GHCR_USERNAME`, `GHCR_TOKEN`, `DOCKER_NETWORK` | Solo si el paquete de GHCR es privado o la red cambia. Hoy no existen |
| arquisoft-frontend | Secret | `SSH_HOST`, `SSH_PORT`, `SSH_USER`, `SSH_PRIVATE_KEY` | CD: conexión al servidor (usuario `deploy`) |
| | Secret | `BASE_DOMAIN` | Regla de Traefik `<dominio>` |
| | Variable | `VITE_ENV_FILE` | `VITE_*` de build en formato `.env`: URL de API, Keycloak y PDP, realm, client id |
| arquisoft-infra | — | ninguno | La infra se despliega a mano en el servidor |

`GITHUB_TOKEN` lo crea GitHub en cada ejecución; no se configura.

### Doppler `arquisoft-infra/test`
🔒 = secreto. El resto es configuración que vive junto a sus credenciales.

| Grupo | Variables |
|-------|-----------|
| General | `DOMAIN`, `ACME_EMAIL`, `TIMEZONE` |
| PostgreSQL | `POSTGRES_USER`, `POSTGRES_PASSWORD` 🔒, `POSTGRES_DB`, `POSTGRES_HOST`, `APP_DB_USER`, `APP_DB_PASSWORD` 🔒 |
| Keycloak | `KEYCLOAK_ADMIN`, `KEYCLOAK_ADMIN_PASSWORD` 🔒, `KC_REALM_ADMIN_PASSWORD` 🔒, `KEYCLOAK_DB_NAME`, `KEYCLOAK_DB_USER`, `KEYCLOAK_DB_PASSWORD` 🔒, `KEYCLOAK_REALM`, `KEYCLOAK_CLIENT_ID`, `KEYCLOAK_CLIENT_SECRET` 🔒, `KEYCLOAK_HOST` |
| RabbitMQ | `RABBITMQ_USER`, `RABBITMQ_PASSWORD` 🔒, `RABBITMQ_APP_USER`, `RABBITMQ_APP_PASSWORD` 🔒, `RABBITMQ_VHOST`, `RABBITMQ_HOST`, `RABBITMQ_PORT` |
| Redis | `REDIS_USER`, `REDIS_PASSWORD` 🔒, `REDIS_APP_USER`, `REDIS_APP_PASSWORD` 🔒, `REDIS_HOST`, `REDIS_PORT` |
| MinIO | `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD` 🔒, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY` 🔒, `MINIO_ENDPOINT` |
| Observabilidad | `GRAFANA_ADMIN_USER`, `GRAFANA_ADMIN_PASSWORD` 🔒, `LOKI_URL`, `PROMETHEUS_URL`, `OBS_BIND_IP` |
| Traefik (BasicAuth) | `ADMIN_AUTH_USER`, `ADMIN_AUTH_PASSWORD` 🔒 |
| WireGuard | `WIREGUARD_HOST`, `WIREGUARD_PORT`, `WIREGUARD_SUBNET`, `PEERS` |
| Mailpit (herramienta) | `MAIL_USERNAME`, `MAIL_PASSWORD` 🔒 (copia del backend), `MAILPIT_UI_USER`, `MAILPIT_UI_PASSWORD` 🔒, `MAILPIT_MAX_MESSAGES`, `MAILPIT_MAX_AGE` |
| SonarQube (herramienta) | `SONAR_DB_USER`, `SONAR_DB_PASSWORD` 🔒, `SONAR_DB_NAME` |
| Apps (solo `redeploy-app.sh`, sin uso hoy) | `BACKEND_IMAGE`, `BACKEND_TAG`, `BACKEND_TARGET`, `FRONTEND_IMAGE`, `FRONTEND_TAG`, `FRONTEND_PORT`, `JAVA_TOOL_OPTIONS`, `SPRING_PROFILES_ACTIVE` |

### Doppler `arquisoft-backend/test`
~90 variables de runtime del backend. Los secretos son:

| Variables 🔒 | Origen |
|--------------|--------|
| `DB_*_PASSWORD` (una por cada una de las 11 bases) | Copia de `APP_DB_PASSWORD` de infra |
| `REDIS_PASSWORD`, `RABBITMQ_PASSWORD`, `MINIO_SECRET_KEY`, `KEYCLOAK_CLIENT_SECRET` | Copias de las credenciales de app de infra (ver [Rotar una credencial](#rotar-una-credencial)) |
| `MAIL_PASSWORD`, `PEP_REGISTRATION_TOKEN` | Solo existen en el backend |

El resto es configuración: `DB_*_URL`/`DB_*_USERNAME`, `LOG_*`, `PEP_*`, `MAIL_*`, `RATE_*`,
`KEYCLOAK_*`, `MINIO_*` (buckets y endpoint), `CORS_*`, `SPRING_PROFILES_ACTIVE`, `JAVA_TOOL_OPTIONS`.

### Herramientas (fuera de Terraform)
Mailpit y SonarQube se levantan con `docker compose` desde su carpeta y leen
`components/<c>/.env`. Ese archivo **no se edita a mano**: lo genera el adaptador a partir del
`.env` raíz (o sea, de Doppler), con solo las claves que declara su `.env.example`.
`duckdns` no está desplegado (sus variables no están en Doppler y el adaptador lo omite);
`wireguard` lo gestiona Terraform con las variables de la tabla anterior.

## Adaptador `scripts/fetch-secrets.sh`

```bash
scripts/fetch-secrets.sh fetch              # genera/valida el .env raíz
scripts/fetch-secrets.sh set BACKEND_TAG=x  # persiste un valor NO secreto
scripts/fetch-secrets.sh provider           # proveedor resuelto (doppler | file)
scripts/fetch-secrets.sh tools --check      # compara components/<c>/.env con el .env raíz (solo nombres)
scripts/fetch-secrets.sh tools [c...]       # escribe el .env de mailpit / sonarqube / duckdns
```

`tools` nunca escribe a medias: omite un componente si falta una clave en el baúl o si su `.env`
actual tiene claves que el `.env.example` no declara. Si el archivo ya era idéntico no lo toca; si
cambia, deja una copia `.env.bak-<fecha>`. Cambiar el `.env` no reinicia nada: el contenedor toma
los valores nuevos al hacer `docker compose up -d` (y en mailpit, tras `./setup.sh`).

| `SECRETS_PROVIDER` | Comportamiento |
|--------------------|----------------|
| `auto` (default) | `doppler` si el CLI está instalado y hay `DOPPLER_TOKEN`, o token + proyecto configurados para el directorio. Si no, `file`. |
| `doppler` | Descarga el config a `.env` (`--format env`, sin caché local). Si falla, **el script falla**: nunca usa en silencio un `.env` viejo. |
| `file` | Usa el `.env` existente (comportamiento previo a Doppler; útil sin conexión). |

> Usar siempre `--format env` (valores entre comillas). `--format docker` rompe el `source` de
> `deploy.sh` con valores que tienen espacios (`JAVA_TOOL_OPTIONS`). Evitar `$` en los valores.
> `doppler secrets download <archivo>` (sin `--no-file`) escribe el archivo **cifrado**: redirigir stdout.
> (El backend sí usa `--format docker`, porque lo lee `docker run --env-file`, no `source`.)

## Verificador `scripts/verify-secrets.sh`

Valida un `.env` contra lo **desplegado**, sin imprimir valores: (1) que estén todas las variables
que exigen los componentes que corren (para mailpit/sonarqube, las claves de su `.env.example`),
(2) que cada credencial sea aceptada por su servicio (Postgres, Keycloak-DB, Redis, RabbitMQ
admin/app, MinIO root/backend, Keycloak admin/cliente, Grafana, BasicAuth de Traefik, SonarQube-DB,
y en Mailpit que los archivos `smtp-auth.txt`/`ui-auth.txt` montados coincidan) y (3) que `BACKEND_TAG`/`FRONTEND_TAG` coincidan con la imagen que
corre. Exit 0 si no hay ❌. Úsalo antes de subir valores a Doppler y después de rotar.

Son **avisos ⚠** (no bloquean):
- **Keycloak admin de arranque** (`KEYCLOAK_ADMIN/PASSWORD` = `KC_BOOTSTRAP_ADMIN_*`): Keycloak solo
  lo crea con la BD vacía y lo normal es borrarlo tras crear administradores personales. Se conserva
  en Doppler porque es el que Keycloak recrearía si la BD se reconstruye desde cero.
- **Tags de backend/frontend**: los publica el pipeline de cada app y se desfasan en cada despliegue.

```bash
cd ~/arquisoft-infra
./scripts/verify-secrets.sh .env
```

### Si el `.env` no coincide: `scripts/recover-env.sh`
Reconstruye el `.env` a partir del entorno con el que Docker creó cada contenedor (y del
`definitions.json` de RabbitMQ). Parte de un `.env` base, sobrescribe solo lo recuperable e
imprime nombres, nunca valores. También indica desde qué carpeta se desplegó cada contenedor.
```bash
./scripts/recover-env.sh .env /tmp/env.recuperado
./scripts/verify-secrets.sh /tmp/env.recuperado
```
No puede recuperar lo que el servicio solo usa en el primer arranque y luego guarda en su base de
datos (`KEYCLOAK_ADMIN_PASSWORD`, `GRAFANA_ADMIN_PASSWORD`, si se cambiaron desde la consola) ni
`ADMIN_AUTH_PASSWORD` (solo existe como hash). Esas se restablecen o se rotan.

## Quién accede y cómo

| Quién | Token | Acceso | Dónde |
|-------|-------|--------|-------|
| Administradores (2–3) | Cuenta personal (correo propio + MFA) | Total | Solo en su equipo. Nunca `doppler login` en el servidor. |
| Servidor — infra | `servidor-oracle` de `arquisoft-infra/test` | Lectura/escritura | Usuario `ubuntu`, scope `~/arquisoft-infra` |
| Servidor — backend | `servidor-oracle` de `arquisoft-backend/test` | **Solo lectura** | Usuario `deploy`, scope `/home/deploy/arquisoft` |
| Compañeros (futuro, local) | Uno **por persona** del config `dev` | Lectura | Revocable individualmente |

**Ningún token de Doppler vive en GitHub.** El pipeline del backend entra por SSH como `deploy` y el
CLI del servidor usa el token de ese usuario. El `.github/workflows/deploy.yml` de este repo
(self-hosted runner + `DOPPLER_TOKEN` en un GitHub Environment) está **inactivo**: no hay runner ni
environments configurados. La infra se despliega a mano en el servidor.

```bash
# Ver los tokens existentes (solo nombres y fechas) desde tu equipo
doppler configs tokens --project arquisoft-infra --config test
doppler configs tokens --project arquisoft-backend --config test
```

## Operación en el servidor

### Infra (usuario `ubuntu`)
```bash
cd ~/arquisoft-infra
git pull
./scripts/fetch-secrets.sh fetch          # .env desde arquisoft-infra/test
./scripts/verify-secrets.sh .env
./scripts/fetch-secrets.sh tools --check  # .env de mailpit y sonarqube al día con el baúl
```

### Backend (usuario `deploy`)
No se opera a mano: cada despliegue del repo backend reescribe `/home/deploy/arquisoft/.env` desde
Doppler. Para cambiar una variable, editarla en `arquisoft-backend/test` y volver a desplegar
(merge a `develop` o *Run workflow*). Una edición manual del archivo se pierde en el siguiente deploy.

```bash
# Comprobar el token del backend sin mostrar secretos
sudo -u deploy -H sh -c 'cd ~/arquisoft && doppler secrets get DOPPLER_PROJECT DOPPLER_CONFIG --plain'
```

## Preparar un servidor nuevo

### 1. CLI de Doppler
```bash
(curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh || \
 wget -t 3 -qO- https://cli.doppler.com/install.sh) | sudo sh       # detecta amd64/arm64
```

### 2. Tokens
Crear el token en tu equipo (va al portapapeles, no se muestra):
```bash
doppler configs tokens create servidor-oracle --project arquisoft-infra --config test --access read/write --plain | clip
doppler configs tokens create servidor-oracle --project arquisoft-backend --config test --plain | clip   # solo lectura
```

Configurarlo en el servidor. El token entra por **stdin**, nunca como argumento: `sudo` registra
la línea de comando completa en `/var/log/auth.log`.
```bash
# Infra, como ubuntu
read -rs -p "Token infra: " T; echo
printf '%s' "$T" | doppler configure set token --scope ~/arquisoft-infra; unset T

# Backend, para el usuario deploy
read -rs -p "Token backend: " T; echo
printf '%s' "$T" | sudo -u deploy -H doppler configure set token --scope /home/deploy/arquisoft; unset T
```

Un service token no guarda proyecto ni config en la configuración local; se comprueban con
`doppler secrets get DOPPLER_PROJECT DOPPLER_CONFIG --plain` dentro del directorio del scope.

## Subir un `.env` existente a Doppler
Siempre desde el servidor, con un token **temporal** de escritura y comparando ida y vuelta:
```bash
# En tu equipo: token de 1 hora
doppler configs tokens create migracion --project <proyecto> --config test --access read/write --max-age 1h --plain | clip

# En el servidor
umask 077
grep -E '^[A-Z_][A-Z0-9_]*=' <ruta/.env> > /tmp/m.env
read -rs -p "Token temporal: " DOPPLER_TOKEN; echo
export DOPPLER_TOKEN
doppler secrets upload /tmp/m.env --silent
doppler secrets download --no-file --format docker --no-fallback --silent \
  | grep -vE '^DOPPLER_(PROJECT|CONFIG|ENVIRONMENT)=' | sort > /tmp/m.doppler
unset DOPPLER_TOKEN
tac /tmp/m.env | awk -F= '!s[$1]++' | sort > /tmp/m.orig
diff /tmp/m.orig /tmp/m.doppler | sed -n 's/^[<>] \([A-Z_0-9]*\)=.*/\1/p' | sort -u   # vacío = idéntico
shred -u /tmp/m.env /tmp/m.orig /tmp/m.doppler
```
Antes de subir el `.env` de infra, pasarlo por `verify-secrets.sh` sin ❌.

## Rotar una credencial
Las credenciales compartidas están en **los dos proyectos** con nombres distintos; al rotar una hay
que actualizar ambos y luego volver a desplegar el servicio y el backend.

| `arquisoft-infra` | `arquisoft-backend` |
|-------------------|---------------------|
| `APP_DB_USER` / `APP_DB_PASSWORD` | `DB_*_USERNAME` / `DB_*_PASSWORD` (una por base de datos) |
| `REDIS_APP_USER` / `REDIS_APP_PASSWORD` | `REDIS_USER` / `REDIS_PASSWORD` |
| `RABBITMQ_APP_USER` / `RABBITMQ_APP_PASSWORD` | `RABBITMQ_USERNAME` / `RABBITMQ_PASSWORD` |
| `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` | `MINIO_ACCESS_KEY` / `MINIO_SECRET_KEY` |
| `KEYCLOAK_CLIENT_ID` / `KEYCLOAK_CLIENT_SECRET` | `KEYCLOAK_CLIENT_ID` / `KEYCLOAK_CLIENT_SECRET` |
| `MAIL_USERNAME` / `MAIL_PASSWORD` (Mailpit) | `MAIL_USERNAME` / `MAIL_PASSWORD` |

## Rotar un token
```bash
doppler configs tokens --project <proyecto> --config test                      # ver slugs
doppler configs tokens revoke --slug <slug> --project <proyecto> --config test
# crear uno nuevo y configurarlo en el servidor (ver "Preparar un servidor nuevo")
```
Varios tokens pueden llamarse igual: revocar siempre por `--slug`, no por nombre.

## Desarrollo local (opcional)
```bash
doppler setup --project arquisoft-infra --config dev   # en Git Bash, no PowerShell (BOM)
./scripts/fetch-secrets.sh fetch
./deploy.sh dev
```
