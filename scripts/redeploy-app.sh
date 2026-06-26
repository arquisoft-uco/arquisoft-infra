#!/usr/bin/env bash
# =============================================================================
# redeploy-app.sh — Redeploy de apps vía docker compose (sin Terraform)
# =============================================================================
# Llamado por GitHub Actions vía SSH para redesplegar backend o frontend.
# Lee credenciales del .env raíz; solo actualiza el tag de la imagen.
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

COMPOSE_FILE="$INFRA_DIR/components/$SERVICE/docker-compose.yml"
ENV_FILE="$INFRA_DIR/.env"

[[ ! -f "$COMPOSE_FILE" ]] && { echo "ERROR: no encontrado $COMPOSE_FILE"; exit 1; }
[[ ! -f "$ENV_FILE" ]]     && { echo "ERROR: no encontrado $ENV_FILE";     exit 1; }

# Nombre de la variable de tag en .env
TAG_VAR="BACKEND_TAG"
[[ "$SERVICE" == "frontend" ]] && TAG_VAR="FRONTEND_TAG"

# Actualizar el tag en .env para que cualquier apply posterior sea idempotente
if grep -q "^${TAG_VAR}=" "$ENV_FILE"; then
  sed -i "s|^${TAG_VAR}=.*|${TAG_VAR}=${TAG}|" "$ENV_FILE"
else
  echo "${TAG_VAR}=${TAG}" >> "$ENV_FILE"
fi

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

echo ">>> $SERVICE desplegado con tag $TAG"
