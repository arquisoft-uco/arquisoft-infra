#!/usr/bin/env bash
# =============================================================================
# Arquisoft IaC — Backup de bases de datos y almacenamiento
# =============================================================================
# Uso:
#   ./backup.sh [objetivo]
#
#   objetivo:  all (default) | postgres | keycloak | minio
#
# Genera archivos con timestamp en ./backups y conserva los últimos
# BACKUP_RETENTION_DAYS días (default 7).
#
# Requiere los contenedores corriendo (postgres, keycloak-db, minio).
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"
source "$ROOT_DIR/scripts/lib/common.sh"

[[ -f .env ]] && { set -a; source .env; set +a; }

TARGET="${1:-all}"
BACKUP_DIR="${BACKUP_DIR:-$ROOT_DIR/backups}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-7}"
TS="$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

PG_CONTAINER="${PG_CONTAINER:-arquisoft-postgres}"
KC_DB_CONTAINER="${KC_DB_CONTAINER:-arquisoft-keycloak-db}"
MINIO_VOLUME="${MINIO_VOLUME:-arquisoft-minio-data}"

backup_postgres() {
  local out="$BACKUP_DIR/postgres_${TS}.sql.gz"
  log_info "Backup PostgreSQL (app, 7 BDs) desde $PG_CONTAINER..."
  docker exec -t "$PG_CONTAINER" pg_dumpall --clean --if-exists -U "${POSTGRES_USER:-postgres}" | gzip > "$out"
  log_success "PostgreSQL -> $out ($(du -h "$out" | cut -f1))"
}

backup_keycloak() {
  local out="$BACKUP_DIR/keycloak_${TS}.sql.gz"
  log_info "Backup Keycloak DB desde $KC_DB_CONTAINER..."
  docker exec -t "$KC_DB_CONTAINER" \
    pg_dump --clean --if-exists -U "${KEYCLOAK_DB_USER:-keycloak}" -d "${KEYCLOAK_DB_NAME:-keycloak}" | gzip > "$out"
  log_success "Keycloak DB -> $out ($(du -h "$out" | cut -f1))"
}

backup_minio() {
  local out="$BACKUP_DIR/minio_${TS}.tar.gz"
  log_info "Backup MinIO (volumen $MINIO_VOLUME)..."
  docker run --rm -v "${MINIO_VOLUME}:/data:ro" -v "$BACKUP_DIR:/backup" alpine \
    tar czf "/backup/minio_${TS}.tar.gz" -C /data .
  log_success "MinIO -> $out ($(du -h "$out" | cut -f1))"
}

case "$TARGET" in
  postgres) backup_postgres ;;
  keycloak) backup_keycloak ;;
  minio)    backup_minio ;;
  all)      backup_postgres; backup_keycloak; backup_minio ;;
  *) log_error "Objetivo inválido: $TARGET (all|postgres|keycloak|minio)"; exit 1 ;;
esac

log_info "Limpiando backups con más de $RETENTION_DAYS días..."
find "$BACKUP_DIR" -type f -mtime +"$RETENTION_DAYS" -delete 2>/dev/null || true
log_success "Backup completado en $BACKUP_DIR"
