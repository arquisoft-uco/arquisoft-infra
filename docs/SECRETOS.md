# Gestión de secretos (Doppler)

Los secretos del `.env` raíz viven en **Doppler** (proyecto `arquisoft-infra`, configs `dev` y
`prd`). Ningún script del repo llama a Doppler directamente salvo el adaptador
[`scripts/fetch-secrets.sh`](../scripts/fetch-secrets.sh): `deploy.sh`, `redeploy-app.sh` y los
compose solo consumen el `.env`. Cambiar de baúl = agregar un proveedor al adaptador.

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

## Quién accede y cómo

| Quién | Acceso |
|-------|--------|
| Administradores (2–3) | Cuenta personal en Doppler (correo propio + MFA) |
| GitHub Actions (`deploy.yml`) | Secret `DOPPLER_TOKEN` por GitHub Environment (`dev` / `prod`): service token **solo lectura** |
| Servidor (`redeploy-app.sh`) | Service token de `prd` **lectura/escritura** (escribe `BACKEND_TAG`/`FRONTEND_TAG`), con scope en `/opt/arquisoft-infra` |
| Resto del equipo | Service token **por persona** del config `dev` (revocable individualmente) |

No usar una cuenta compartida: se pierde la auditoría y la salida de un miembro obliga a rotar todo.

## Puesta en marcha

### 1. Doppler (una vez)
```bash
doppler login
doppler projects create arquisoft-infra
doppler configs delete stg --project arquisoft-infra --yes      # si no usan staging
doppler secrets upload .env.dev  --project arquisoft-infra --config dev
doppler secrets upload .env.prod --project arquisoft-infra --config prd
```
⚠️ Subir los valores **actuales**. No regenerarlos: los volúmenes ya inicializados (Postgres,
Keycloak, RabbitMQ) dejarían de autenticar.

### 2. Tokens
```bash
doppler configs tokens create github-actions  --project arquisoft-infra --config dev --plain
doppler configs tokens create github-actions  --project arquisoft-infra --config prd --plain
doppler configs tokens create server-redeploy --project arquisoft-infra --config prd --access read/write --plain

gh secret set DOPPLER_TOKEN --env dev  --repo arquisoft-uco/arquisoft-infra
gh secret set DOPPLER_TOKEN --env prod --repo arquisoft-uco/arquisoft-infra
```

### 3. Local (Git Bash, NO PowerShell: `>` en PS 5.1 agrega BOM)
```bash
doppler setup --project arquisoft-infra --config dev
./scripts/fetch-secrets.sh fetch
./deploy.sh dev
```

### 4. Servidor (runner self-hosted + redeploy por SSH)
```bash
(curl -Ls --tlsv1.2 --proto "=https" --retry 3 https://cli.doppler.com/install.sh || \
 wget -t 3 -qO- https://cli.doppler.com/install.sh) | sudo sh       # detecta amd64/arm64
# El token se guarda en el ~/.doppler del usuario que corre redeploy-app.sh por SSH
# (`deploy`, ver CD-BACKEND.md). El runner de Actions NO lo necesita: usa DOPPLER_TOKEN.
cd /opt/arquisoft-infra
sudo -u deploy doppler configure set token <token server-redeploy> --scope /opt/arquisoft-infra
sudo -u deploy ./scripts/fetch-secrets.sh provider    # → doppler
sudo -u deploy ./scripts/fetch-secrets.sh fetch
```

### 5. Corte
1. Validar `deploy.yml` en `dev` y luego en `prod` con un componente inocuo; luego un redeploy
   del backend y confirmar `BACKEND_TAG` en Doppler.
2. Eliminar el secret `ENV_FILE` de los environments de GitHub.
3. Borrar copias sueltas del `.env` (workspace del runner, archivos locales de migración).

## Rotar un token
```bash
doppler configs tokens revoke <nombre> --project arquisoft-infra --config <dev|prd>
# crear uno nuevo y actualizar el secret de GitHub / `doppler configure set token` del servidor
```
