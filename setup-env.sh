#!/usr/bin/env bash
# =============================================================================
# Arquisoft IaC — Generador de .env
# =============================================================================
# Uso:
#   ./setup-env.sh <env> [dominio] [acme_email]
#
#   env          dev | prod
#   dominio      ej. arquisoft.top   (default: arquisoft.localhost en dev)
#   acme_email   email para Let's Encrypt (obligatorio en prod)
#
# Idempotente parcial: si .env existe, no lo sobreescribe (borrarlo para regenerar).
# Autogenera todas las contraseñas marcadas como CHANGE_ME.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib/common.sh"
source "$ROOT_DIR/scripts/lib/password-generator.sh"
source "$ROOT_DIR/scripts/lib/env-config.sh"

ENV="${1:-dev}"
DOMAIN_ARG="${2:-}"
ACME_ARG="${3:-}"
ENV_FILE="$ROOT_DIR/.env"

[[ "$ENV" == "dev" || "$ENV" == "prod" ]] || { log_error "env debe ser 'dev' o 'prod'"; exit 1; }

if [[ -f "$ENV_FILE" ]]; then
  log_warning ".env ya existe — no se sobreescribe. Borrarlo para regenerar."
  exit 0
fi

cp "$ROOT_DIR/.env.example" "$ENV_FILE"

# Contraseñas / secretos a autogenerar
SECRET_VARS=(
  POSTGRES_PASSWORD APP_DB_PASSWORD
  KEYCLOAK_ADMIN_PASSWORD KEYCLOAK_DB_PASSWORD KC_REALM_ADMIN_PASSWORD KEYCLOAK_CLIENT_SECRET
  RABBITMQ_PASSWORD REDIS_PASSWORD
  MINIO_ROOT_PASSWORD MINIO_SECRET_KEY
  GRAFANA_ADMIN_PASSWORD ADMIN_AUTH_PASSWORD
)
for var in "${SECRET_VARS[@]}"; do
  set_env_var "$ENV_FILE" "$var" "$(generate_password)"
done

# Dominio / ACME
if [[ -n "$DOMAIN_ARG" ]]; then
  set_env_var "$ENV_FILE" "DOMAIN" "$DOMAIN_ARG"
elif [[ "$ENV" == "dev" ]]; then
  set_env_var "$ENV_FILE" "DOMAIN" "arquisoft.localhost"
fi

if [[ "$ENV" == "prod" ]]; then
  if [[ -n "$ACME_ARG" ]]; then
    set_env_var "$ENV_FILE" "ACME_EMAIL" "$ACME_ARG"
  elif grep -q '^ACME_EMAIL=admin@tu-dominio.com' "$ENV_FILE"; then
    log_warning "Configurar ACME_EMAIL en .env antes de desplegar en prod"
  fi
fi

chmod 600 "$ENV_FILE"
log_success ".env generado (env=$ENV, DOMAIN=$(get_env_var "$ENV_FILE" DOMAIN))"
log_info "Contraseñas autogeneradas para: ${SECRET_VARS[*]}"
[[ "$ENV" == "prod" ]] && log_warning "Revisar DOMAIN, ACME_EMAIL, BACKEND_IMAGE y FRONTEND_IMAGE antes del deploy."
echo ""
log_info "Siguiente paso:  ./deploy.sh $ENV"
