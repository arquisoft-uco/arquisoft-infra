#!/usr/bin/env bash
# =============================================================================
# redeploy-app.sh — Redeploy de apps vía docker compose (sin Terraform)
# =============================================================================
# Llamado por GitHub Actions vía SSH para redesplegar backend o frontend.
# Obtiene el .env raíz con scripts/fetch-secrets.sh (Doppler o .env local) y
# solo cambia el tag de la imagen. El tag se persiste (en Doppler o en .env)
# DESPUÉS de un despliegue exitoso, para que despliegues posteriores no regresen
# a una imagen anterior.
#
# Uso:
#   ./scripts/redeploy-app.sh --service backend --tag sha-a1b2c3d
#   ./scripts/redeploy-app.sh --service frontend --tag sha-a1b2c3d
# =============================================================================
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE=""
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --service) SERVICE="$2"; shift 2 ;;
    --tag)     TAG="$2";     shift 2 ;;
    *) echo "Uso: $0 --service <backend|frontend> --tag <sha>"; exit 1 ;;
  esac
done

[[ -z "$SERVICE" ]] && { echo "ERROR: --service requerido"; exit 1; }
[[ -z "$TAG" ]]     && { echo "ERROR: --tag requerido";     exit 1; }

case "$SERVICE" in
  backend|frontend) ;;
  *) echo "ERROR: --service debe ser 'backend' o 'frontend'"; exit 1 ;;
esac

[[ "$TAG" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: --tag inválido: '$TAG'"; exit 1; }

COMPOSE_FILE="$INFRA_DIR/components/$SERVICE/docker-compose.yml"
ENV_FILE="$INFRA_DIR/.env"
FETCH_SECRETS="$INFRA_DIR/scripts/fetch-secrets.sh"

[[ ! -f "$COMPOSE_FILE" ]] && { echo "ERROR: no encontrado $COMPOSE_FILE"; exit 1; }

# Nombre de la variable de tag en .env
TAG_VAR="BACKEND_TAG"
[[ "$SERVICE" == "frontend" ]] && TAG_VAR="FRONTEND_TAG"

echo ">>> Secretos: proveedor $("$FETCH_SECRETS" provider)"
"$FETCH_SECRETS" fetch

# El tag nuevo entra como variable de entorno: en compose, el entorno del shell
# tiene prioridad sobre --env-file. Así no se persiste hasta que el deploy funcione.
export "${TAG_VAR}=${TAG}"

echo ">>> Pulling $SERVICE:$TAG ..."
docker compose \
  -f "$COMPOSE_FILE" \
  --env-file "$ENV_FILE" \
  pull "$SERVICE"

echo ">>> Recreando contenedor $SERVICE ..."
docker compose \
  -f "$COMPOSE_FILE" \
  --env-file "$ENV_FILE" \
  up -d --no-deps "$SERVICE"

# Persistir el tag (Doppler o .env) para que despliegues posteriores sean idempotentes
"$FETCH_SECRETS" set "${TAG_VAR}=${TAG}"
[[ "$("$FETCH_SECRETS" provider)" == "doppler" ]] && "$FETCH_SECRETS" fetch

echo ">>> $SERVICE desplegado con tag $TAG"
