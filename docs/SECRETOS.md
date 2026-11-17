# Gestión de secretos (Doppler)

Los secretos del `.env` raíz viven en **Doppler**, workplace `arquisoft`, proyecto `arquisoft-infra`:

| Entorno / config | Uso |
|------------------|-----|
| `test` | Servidor Oracle (lo consume `deploy.yml` y `redeploy-app.sh`) |
| `dev` | Reservado para desarrollo local (sin uso por ahora) |

Ningún script del repo llama a Doppler directamente salvo el adaptador
[`scripts/fetch-secrets.sh`](../scripts/fetch-secrets.sh): `deploy.sh`, `redeploy-app.sh` y los
compose solo consumen el `.env`. Cambiar de baúl = agregar un proveedor al adaptador.

> **Nombres distintos, mismo destino.** El config de Doppler (`test`) no tiene que coincidir con el
> GitHub Environment (`prod`) ni con el modo de `deploy.sh` (`prod` = servidor con HTTPS): los une el
> token. `DOPPLER_TOKEN` del environment `prod` es un token del config `test`.

## Adaptador `scripts/fetch-secrets.sh`

```bash
scripts/fetch-secrets.sh fetch              # genera/valida el .env raíz
scripts/fetch-secrets.sh set BACKEND_TAG=x  # persiste un valor NO secreto
scripts/fetch-secrets.sh provider           # proveedor resuelto (doppler | file)
```

| `SECRETS_PROVIDER` | Comportamiento |
|--------------------|----------------|
| `auto` (default) | `doppler` si el CLI está instalado y hay `DOPPLER_TOKEN`, o token + proyecto configurados para el directorio. Si no, `file`. |
| `doppler` | Descarga el config a `.env` (`--format env`, sin caché local). Si falla, **el script falla**: nunca usa en silencio un `.env` viejo. |
| `file` | Usa el `.env` existente (comportamiento previo a Doppler; útil sin conexión). |

> Usar siempre `--format env` (valores entre comillas). `--format docker` rompe el `source` de
> `deploy.sh` con valores que tienen espacios (`JAVA_TOOL_OPTIONS`). Evitar `$` en los valores.
> `doppler secrets download <archivo>` (sin `--no-file`) escribe el archivo **cifrado**: redirigir stdout.

## Verificador `scripts/verify-secrets.sh`

Valida un `.env` contra lo **desplegado**, sin imprimir valores: (1) que estén todas las variables
que exigen los componentes que corren, (2) que cada credencial sea aceptada por su servicio
(Postgres, Keycloak-DB, Redis, RabbitMQ admin/app, MinIO root/backend, Keycloak admin/cliente,
Grafana, BasicAuth de Traefik) y (3) que `BACKEND_TAG`/`FRONTEND_TAG` coincidan con la imagen que
corre. Exit 0 solo si todo coincide. Úsalo antes de subir valores a Doppler y después de rotar.

```bash
sudo -u deploy ./scripts/verify-secrets.sh /ruta/al/.env
```

`duckdns`, `mailpit`, `sonarqube` y `wireguard` usan su propio `components/<c>/.env` y quedan
fuera de Doppler por ahora.

## Quién accede y cómo

| Quién | Acceso |
|-------|--------|
| Administradores (2–3) | Cuenta personal en Doppler (correo propio + MFA). Nunca `doppler login` en el servidor. |
| GitHub Actions (`deploy.yml`) | Secret `DOPPLER_TOKEN` del GitHub Environment `prod`: service token **solo lectura** del config `test` |
| Servidor (`redeploy-app.sh`) | Service token del config `test` **lectura/escritura** (escribe `BACKEND_TAG`/`FRONTEND_TAG`), usuario `deploy`, scope `/opt/arquisoft-infra` |
| Compañeros (futuro, local) | Service token **por persona** del config `dev`, revocable individualmente |

## Puesta en marcha

### 1. Doppler (en tu equipo, una vez)
```bash
doppler projects create arquisoft-infra
doppler environments create "Test" test --project arquisoft-infra
doppler environments delete stg --project arquisoft-infra --yes
doppler environments delete prd --project arquisoft-infra --yes
```

### 2. Tokens (en tu equipo; no se muestran en pantalla)
```bash
# GitHub Actions — solo lectura, directo al secret del environment prod
doppler configs tokens create github-actions --project arquisoft-infra --config test --plain \
  | gh secret set DOPPLER_TOKEN --env prod --repo arquisoft-uco/arquisoft-infra

# Servidor — lectura/escritura, al portapapeles para pegarlo en el servidor
doppler configs tokens create server-redeploy --project arquisoft-infra --config test --access read/write --plain | clip
```

### 3. Servidor: CLI y token del usuario `deploy`
```bash
(curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh || \
 wget -t 3 -qO- https://cli.doppler.com/install.sh) | sudo sh       # detecta amd64/arm64
read -rs -p "Token server-redeploy: " T; echo
sudo -u deploy doppler configure set token "$T" --scope /opt/arquisoft-infra
unset T
```

### 4. Servidor: migrar el `.env` desplegado a Doppler
El `.env` completo ya existe en el servidor (el workflow anterior lo escribía desde `ENV_FILE` en
el workspace del runner y no lo borraba; `redeploy-app.sh` usa `/opt/arquisoft-infra/.env`).
```bash
cd /opt/arquisoft-infra
git fetch && git checkout feature/doppler            # o main, tras el merge

# a) Ubicar el .env vigente (comparar si hay más de uno)
ls -l .env
sudo find / -path '*/_work/*' -name .env -path '*arquisoft-infra*' 2>/dev/null
sudo sha256sum .env <ruta-del-runner>/.env

# b) Validarlo contra lo desplegado — no seguir hasta que no haya ❌
sudo install -m 600 -o deploy <ruta-del-.env-vigente> /tmp/migr.env
sudo -u deploy ./scripts/verify-secrets.sh /tmp/migr.env

# c) Subir solo las variables activas al config test
sudo -u deploy sh -c 'grep -E "^[A-Z_][A-Z0-9_]*=" /tmp/migr.env > /tmp/migr.clean && doppler secrets upload /tmp/migr.clean --silent'
sudo shred -u /tmp/migr.env /tmp/migr.clean

# d) Ida y vuelta: lo que devuelve Doppler también debe pasar la verificación
cp .env .env.pre-doppler 2>/dev/null || true
sudo -u deploy ./scripts/fetch-secrets.sh fetch
sudo -u deploy ./scripts/verify-secrets.sh .env
```

### 5. Validación del workflow y corte
1. **Actions → Deploy → Run workflow**, "Use workflow from" = `feature/doppler`, environment `prod`,
   un componente inocuo (p. ej. `redis`).
2. Redeploy del backend desde su repo; confirmar `BACKEND_TAG` en Doppler
   (`doppler secrets get BACKEND_TAG --project arquisoft-infra --config test --plain`).
3. Merge del PR; en el servidor `git checkout main && git pull`.
4. Eliminar el secret de repositorio `ENV_FILE`; tras unos días estable, borrar `.env.pre-doppler`.

## Desarrollo local (opcional)
```bash
doppler setup --project arquisoft-infra --config dev   # en Git Bash, no PowerShell (BOM)
./scripts/fetch-secrets.sh fetch
./deploy.sh dev
```

## Rotar un token
```bash
doppler configs tokens revoke <nombre> --project arquisoft-infra --config <test|dev>
# crear uno nuevo y actualizar el secret de GitHub / `doppler configure set token` del servidor
```
