#!/usr/bin/env bash
# =============================================================================
# Arquisoft IaC — Orquestador de despliegue
# =============================================================================
# Uso:
#   ./deploy.sh <env> [comando] [componente...]
#
#   env        dev | prod
#   comando    up (default) | down | status
#
# Ejemplos:
#   ./deploy.sh dev                      # levanta toda la infra (dev)
#   ./deploy.sh prod                     # levanta todo (prod, HTTPS)
#   ./deploy.sh dev up postgres redis    # solo esos componentes
#   ./deploy.sh prod down keycloak       # baja un componente
#   ./deploy.sh prod status              # estado de todos
#
# Componentes (orden de dependencias):
#   proxy postgres redis rabbitmq minio keycloak observability backend frontend
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib/common.sh"
source "$ROOT_DIR/scripts/lib/password-generator.sh"

NETWORK="arquisoft-network"
ENV_FILE="$ROOT_DIR/.env"
ALL_COMPONENTS=(proxy postgres redis rabbitmq minio keycloak observability backend frontend)

# ---------- Parseo de argumentos ----------
ENV="${1:-}"; shift || true
case "$ENV" in
  dev|prod) ;;
  *) log_error "Primer argumento debe ser 'dev' o 'prod'"; exit 1 ;;
esac

CMD="up"
if [[ "${1:-}" =~ ^(up|down|status)$ ]]; then CMD="$1"; shift || true; fi
COMPONENTS=("$@")

# ---------- Validaciones de entorno ----------
[[ -f "$ENV_FILE" ]] || { log_error ".env no encontrado. Ejecutar: ./setup-env.sh $ENV"; exit 1; }
set -a; source "$ENV_FILE"; set +a

if [[ -z "${DOMAIN:-}" ]]; then log_error "DOMAIN no definido en .env"; exit 1; fi
if [[ "$ENV" == "prod" && -z "${ACME_EMAIL:-}" ]]; then
  log_error "ACME_EMAIL requerido en prod (Let's Encrypt)"; exit 1
fi

# ---------- Selección de componentes por defecto ----------
if [[ ${#COMPONENTS[@]} -eq 0 ]]; then
  for c in "${ALL_COMPONENTS[@]}"; do
    # En dev el proxy es opcional (acceso por puertos 127.0.0.1)
    [[ "$ENV" == "dev" && "$c" == "proxy" ]] && continue
    # backend/frontend solo si su imagen está configurada
    [[ "$c" == "backend"  && -z "${BACKEND_IMAGE:-}"  ]] && { log_warning "backend omitido (BACKEND_IMAGE vacío)"; continue; }
    [[ "$c" == "frontend" && -z "${FRONTEND_IMAGE:-}" ]] && { log_warning "frontend omitido (FRONTEND_IMAGE vacío)"; continue; }
    COMPONENTS+=("$c")
  done
fi

# ---------- Utilidades ----------
ensure_network() {
  if ! docker network inspect "$NETWORK" >/dev/null 2>&1; then
    docker network create "$NETWORK" >/dev/null
    log_success "Red '$NETWORK' creada"
  fi
}

need_envsubst() {
  command -v envsubst >/dev/null 2>&1 || { log_error "envsubst no encontrado. Instalar 'gettext'"; exit 1; }
}

# Renderiza plantillas y secretos del componente antes de levantarlo
prepare_component() {
  local c="$1" dir="components/$1"
  case "$c" in
    proxy)
      mkdir -p "$dir/config/dynamic"
      if [[ "$ENV" == "prod" ]]; then
        need_envsubst
        envsubst '${ACME_EMAIL}' < "$dir/config/traefik.yml.template" > "$dir/config/traefik.yml"
      fi
      # .htpasswd para BasicAuth de consolas admin
      local hash; hash=$(generate_apr1_hash "${ADMIN_AUTH_PASSWORD:-admin}")
      printf '%s:%s\n' "${ADMIN_AUTH_USER:-admin}" "$hash" > "$dir/config/dynamic/.htpasswd"
      # Legible por el usuario de Traefik dentro del contenedor (solo es un hash)
      chmod 644 "$dir/config/dynamic/.htpasswd"
      ;;
    keycloak)
      need_envsubst
      envsubst '${KC_REALM_ADMIN_EMAIL} ${KC_REALM_ADMIN_FIRST_NAME} ${KC_REALM_ADMIN_LAST_NAME} ${KC_REALM_ADMIN_PASSWORD} ${DOMAIN} ${KEYCLOAK_CLIENT_ID} ${KEYCLOAK_CLIENT_SECRET}' \
        < "$dir/config/realm-arquisoft.json.template" > "$dir/config/realm-arquisoft.json"
      ;;
    rabbitmq)
      need_envsubst
      envsubst '${RABBITMQ_USER} ${RABBITMQ_PASSWORD}' \
        < "$dir/config/definitions.json.template" > "$dir/config/definitions.json"
      ;;
  esac
}

compose_files() {
  local dir="components/$1"
  local files=(-f "$dir/docker-compose.yml")
  if [[ "$ENV" == "dev" && -f "$dir/docker-compose.dev.yml" ]]; then
    files+=(-f "$dir/docker-compose.dev.yml")
  fi
  printf '%s\n' "${files[@]}"
}

run_compose() {
  local c="$1"; shift
  mapfile -t files < <(compose_files "$c")
  docker compose --env-file "$ENV_FILE" -p "arquisoft-$c" "${files[@]}" "$@"
}

# ---------- Comandos ----------
echo -e "${CYAN}== Arquisoft IaC == env=$ENV cmd=$CMD componentes: ${COMPONENTS[*]}${NC}"

case "$CMD" in
  up)
    ensure_network
    for c in "${COMPONENTS[@]}"; do
      log_info "Desplegando '$c'..."
      prepare_component "$c"
      run_compose "$c" up -d
      log_success "'$c' desplegado"
    done
    echo ""
    log_success "Despliegue completado (env=$ENV)"
    ;;
  down)
    for c in "${COMPONENTS[@]}"; do
      log_info "Bajando '$c'..."
      run_compose "$c" down || true
    done
    log_success "Componentes detenidos"
    ;;
  status)
    for c in "${COMPONENTS[@]}"; do
      echo -e "${BLUE}── $c ──${NC}"
      run_compose "$c" ps || true
    done
    ;;
esac
