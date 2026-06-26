#!/usr/bin/env bash
# =============================================================================
# Arquisoft IaC — Restauración de backups
# =============================================================================
# Uso:
#   ./restore.sh <archivo-backup>
#
# El tipo se detecta por el prefijo del nombre del archivo:
#   postgres_*.sql.gz   -> restaura en el PostgreSQL de la app (todas las BDs)
#   keycloak_*.sql.gz   -> restaura en la BD dedicada de Keycloak
#   minio_*.tar.gz      -> restaura el volumen de MinIO
#
# ¡DESTRUCTIVO! Sobrescribe datos existentes. Pide confirmación.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib/common.sh"

[[ -f .env ]] && { set -a; source .env; set +a; }

FILE="${1:-}"
[[ -n "$FILE" && -f "$FILE" ]] || { log_error "Archivo de backup inválido. Uso: ./restore.sh <archivo>"; exit 1; }

PG_CONTAINER="${PG_CONTAINER:-arquisoft-postgres}"
KC_DB_CONTAINER="${KC_DB_CONTAINER:-arquisoft-keycloak-db}"
MINIO_VOLUME="${MINIO_VOLUME:-arquisoft-minio-data}"
BACKEND_CONTAINER="${BACKEND_CONTAINER:-arquisoft-backend}"
KC_CONTAINER="${KC_CONTAINER:-arquisoft-keycloak}"
MINIO_CONTAINER="${MINIO_CONTAINER:-arquisoft-minio}"

base="$(basename "$FILE")"

container_is_running() {
  [ -n "$(docker ps -q --filter "name=^${1}$" --filter "status=running")" ]
}

confirm() {
  read -r -p "$(echo -e "${YELLOW}Esto sobrescribirá datos en $1. ¿Continuar? (escribir 'si'): ${NC}")" ans
  [[ "$ans" == "si" ]] || { log_warning "Cancelado"; exit 0; }
}

case "$base" in
  postgres_*.sql.gz)
    if container_is_running "$BACKEND_CONTAINER"; then
      log_error "El contenedor '$BACKEND_CONTAINER' está corriendo. Detenlo antes de restaurar:"
      log_error "  docker stop $BACKEND_CONTAINER"
      exit 1
    fi
    confirm "el PostgreSQL de la app ($PG_CONTAINER)"
    log_info "Restaurando $base ..."
    gunzip -c "$FILE" | docker exec -i "$PG_CONTAINER" psql -U "${POSTGRES_USER:-postgres}" -d postgres
    log_success "PostgreSQL restaurado"
    ;;
  keycloak_*.sql.gz)
    if container_is_running "$KC_CONTAINER"; then
      log_error "El contenedor '$KC_CONTAINER' está corriendo. Detenlo antes de restaurar:"
      log_error "  docker stop $KC_CONTAINER"
      exit 1
    fi
    confirm "la BD de Keycloak ($KC_DB_CONTAINER)"
    log_info "Restaurando $base ..."
    gunzip -c "$FILE" | docker exec -i "$KC_DB_CONTAINER" \
      psql -U "${KEYCLOAK_DB_USER:-keycloak}" -d "${KEYCLOAK_DB_NAME:-keycloak}"
    log_success "Keycloak DB restaurada"
    ;;
  minio_*.tar.gz)
    if container_is_running "$MINIO_CONTAINER"; then
      log_error "El contenedor '$MINIO_CONTAINER' está corriendo. Detenlo antes de restaurar:"
      log_error "  docker stop $MINIO_CONTAINER"
      exit 1
    fi
    confirm "el volumen de MinIO ($MINIO_VOLUME)"
    log_info "Restaurando $base ..."
    docker run --rm -v "${MINIO_VOLUME}:/data" -v "$(cd "$(dirname "$FILE")" && pwd):/backup:ro" alpine \
      sh -c "rm -rf /data/* && tar xzf /backup/$base -C /data"
    log_success "MinIO restaurado. Levanta el contenedor: docker start $MINIO_CONTAINER"
    ;;
  *)
    log_error "No se reconoce el tipo de backup por su nombre: $base"
    exit 1
    ;;
esac
