#!/bin/bash
# =============================================================================
# provision-clients.sh — Utilidad para provisioning de clientes WireGuard
# =============================================================================
# Uso:
#   ./provision-clients.sh list              # Listar clientes generados
#   ./provision-clients.sh extract dev1      # Extraer config de dev1
#   ./provision-clients.sh export <destino>  # Exportar todas las configs
#   ./provision-clients.sh show-qr <peer>    # Mostrar QR del cliente
# =============================================================================

set -euo pipefail

CONTAINER="arquisoft-wireguard"
CONFIG_PATH="/config/peer_confs"

# Colores
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
  echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
  echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
  echo -e "${RED}[ERROR]${NC} $*" >&2
}

# Verificar que el contenedor existe y está ejecutándose
check_container() {
  if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER}$"; then
    log_error "Contenedor '${CONTAINER}' no está ejecutándose"
    log_info "Inicia con: docker compose up -d"
    exit 1
  fi
}

# Listar clientes
list_clients() {
  check_container
  log_info "Clientes WireGuard provisioned:"
  docker exec "${CONTAINER}" ls -1 "${CONFIG_PATH}" 2>/dev/null || {
    log_warn "No hay clientes generados aún. Espera a que WireGuard inicialice (~15s)"
    exit 0
  }
}

# Extraer configuración de un cliente específico
extract_client() {
  local peer=$1
  check_container

  local conf_file="${CONFIG_PATH}/${peer}/${peer}.conf"

  if ! docker exec "${CONTAINER}" test -f "${conf_file}" 2>/dev/null; then
    log_error "Cliente '${peer}' no encontrado en ${CONFIG_PATH}"
    list_clients
    exit 1
  fi

  log_info "Extrayendo config de '${peer}'..."
  docker cp "${CONTAINER}:${conf_file}" "./${peer}.conf"
  log_info "✓ Guardado en: ./${peer}.conf"

  # Mostrar snippet
  echo ""
  echo "=== Primeras líneas de la configuración ==="
  head -5 "./${peer}.conf"
  echo "..."
}

# Exportar todas las configuraciones
export_all() {
  local dest=${1:-.}
  check_container

  mkdir -p "${dest}/peer_confs"

  log_info "Exportando todas las configuraciones a: ${dest}/peer_confs/"
  docker cp "${CONTAINER}:${CONFIG_PATH}/." "${dest}/peer_confs/" 2>/dev/null || {
    log_error "No hay configuraciones para exportar"
    exit 1
  }

  log_info "✓ Exportadas $(find "${dest}/peer_confs" -name '*.conf' | wc -l) configuraciones"
  log_info "Distribución:"
  find "${dest}/peer_confs" -name '*.conf' | xargs -I {} basename {} | sed 's/.conf//'
}

# Mostrar QR de un cliente (si está disponible)
show_qr() {
  local peer=$1
  check_container

  local qr_file="${CONFIG_PATH}/${peer}/${peer}.png"

  if ! docker exec "${CONTAINER}" test -f "${qr_file}" 2>/dev/null; then
    log_error "QR para '${peer}' no encontrado. Verifica que el cliente existe."
    list_clients
    exit 1
  fi

  local tmp_qr=$(mktemp --suffix=.png)
  docker cp "${CONTAINER}:${qr_file}" "${tmp_qr}"
  log_info "QR para '${peer}' guardado en: ${tmp_qr}"
  log_info "Abre la imagen para escanear desde app móvil WireGuard"

  # Intentar abrir con visor de imágenes (si existe)
  if command -v xdg-open &> /dev/null; then
    xdg-open "${tmp_qr}"
  elif command -v open &> /dev/null; then
    open "${tmp_qr}"
  fi
}

# Mostrar estado de conexiones activas
show_status() {
  check_container
  log_info "Conexiones activas en WireGuard:"
  docker exec "${CONTAINER}" wg show all || {
    log_warn "WireGuard no está listo aún"
  }
}

# Revocar acceso de un cliente
revoke_client() {
  local peer=$1
  check_container

  log_warn "Revocando acceso para '${peer}'..."
  docker exec "${CONTAINER}" rm -rf "${CONFIG_PATH}/${peer}" || {
    log_error "Cliente '${peer}' no encontrado"
    exit 1
  }

  log_info "✓ Cliente '${peer}' revocado"
  log_info "Recarga WireGuard: docker compose restart"
}

# Main
usage() {
  cat << EOF
Uso: $(basename "$0") <comando> [argumentos]

Comandos:
  list                  Listar clientes generados
  extract <peer>        Extraer configuración de un cliente
  export [destino]      Exportar todas las configs (default: ./peer_confs/)
  show-qr <peer>        Mostrar QR para escanear en móvil
  status                Ver conexiones activas
  revoke <peer>         Revocar acceso de un cliente

Ejemplos:
  $(basename "$0") list
  $(basename "$0") extract dev1
  $(basename "$0") export ~/vpn-configs
  $(basename "$0") show-qr dev2
  $(basename "$0") revoke old-developer

EOF
  exit 1
}

if [[ $# -eq 0 ]]; then
  usage
fi

case "${1:-}" in
  list)
    list_clients
    ;;
  extract)
    [[ $# -lt 2 ]] && { log_error "Falta el nombre del peer"; usage; }
    extract_client "$2"
    ;;
  export)
    export_all "${2:-.}"
    ;;
  show-qr)
    [[ $# -lt 2 ]] && { log_error "Falta el nombre del peer"; usage; }
    show_qr "$2"
    ;;
  status)
    show_status
    ;;
  revoke)
    [[ $# -lt 2 ]] && { log_error "Falta el nombre del peer"; usage; }
    revoke_client "$2"
    ;;
  *)
    log_error "Comando desconocido: $1"
    usage
    ;;
esac
