#!/usr/bin/env bash
# =============================================================================
# Arquisoft IaC — Hardening de firewall (ufw)
# =============================================================================
# Guía GLOBAL por rol de servidor. Se ejecuta en CADA servidor de la topología
# con las banderas que correspondan a su rol. Postura por defecto:
#   - deny incoming  /  allow outgoing
#   - SSH siempre permitido (restringible a una IP/red de administración)
#
# Uso (combinable según el rol del servidor):
#   sudo ./firewall.sh --public                 # servidor con Traefik público (abre 80/443)
#   sudo ./firewall.sh --ssh-from <CIDR>        # restringe SSH a una IP/red de admin
#   sudo ./firewall.sh --ssh-port <n>           # puerto SSH alterno (default 22)
#   sudo ./firewall.sh --data-from <CIDR>       # rol DATOS: 5432/5672/6379/9000 solo desde <CIDR>
#   sudo ./firewall.sh --obs-from <CIDR>        # rol OBSERVABILIDAD: 3100/9090 solo desde <CIDR>
#   sudo ./firewall.sh --status                 # muestra el estado y sale
#
# Ejemplos por rol (ver docs/FIREWALL.md):
#   Único servidor (todo junto):  sudo ./firewall.sh --public
#   Servidor de aplicación:        sudo ./firewall.sh --public --ssh-from 203.0.113.10
#   Servidor de datos:             sudo ./firewall.sh --data-from 10.0.0.11
#   Servidor de observabilidad:    sudo ./firewall.sh --obs-from 10.0.0.11
#
# IMPORTANTE: Docker publica puertos vía iptables y EVITA la cadena INPUT de ufw.
# Por eso el control primario de los puertos de datos es el bind a la IP privada
# (ver OBS_BIND_IP) + el Security Group del proveedor. Este script es defensa en
# profundidad a nivel de host. Ver docs/FIREWALL.md.
# =============================================================================
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/scripts/lib/common.sh"

DATA_PORTS=(5432 5672 6379 9000)   # postgres, rabbitmq-amqp, redis, minio-s3
OBS_PORTS=(3100 9090)              # loki push, prometheus remote-write

SSH_PORT=22
SSH_FROM=""
ALLOW_PUBLIC=false
DATA_FROM=""
OBS_FROM=""
SHOW_STATUS=false

# ---------- Parseo de argumentos ----------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --public)    ALLOW_PUBLIC=true; shift ;;
    --ssh-from)  SSH_FROM="${2:?--ssh-from requiere una IP/CIDR}"; shift 2 ;;
    --ssh-port)  SSH_PORT="${2:?--ssh-port requiere un número}"; shift 2 ;;
    --data-from) DATA_FROM="${2:?--data-from requiere una IP/CIDR}"; shift 2 ;;
    --obs-from)  OBS_FROM="${2:?--obs-from requiere una IP/CIDR}"; shift 2 ;;
    --status)    SHOW_STATUS=true; shift ;;
    -h|--help)   grep -E '^#( |!)' "$0" | sed 's/^#//'; exit 0 ;;
    *) log_error "Argumento desconocido: $1"; exit 1 ;;
  esac
done

# ---------- Validaciones ----------
if [[ "$(id -u)" -ne 0 ]]; then
  log_error "Se requiere root. Ejecutar: sudo ./firewall.sh $*"
  exit 1
fi
if ! command -v ufw >/dev/null 2>&1; then
  log_error "ufw no está instalado. Debian/Ubuntu: apt-get install -y ufw"
  exit 1
fi

if [[ "$SHOW_STATUS" == true ]]; then
  ufw status numbered
  exit 0
fi

# ---------- Configuración ----------
log_info "Configurando ufw (default deny incoming / allow outgoing)..."

# SSH PRIMERO para no perder el acceso al habilitar el firewall
if [[ -n "$SSH_FROM" ]]; then
  ufw allow from "$SSH_FROM" to any port "$SSH_PORT" proto tcp comment 'SSH (admin)'
  log_success "SSH ${SSH_PORT}/tcp permitido desde ${SSH_FROM}"
else
  ufw allow "${SSH_PORT}/tcp" comment 'SSH'
  log_warning "SSH ${SSH_PORT}/tcp permitido desde cualquier origen (usar --ssh-from para restringir)"
fi

ufw default deny incoming
ufw default allow outgoing

if [[ "$ALLOW_PUBLIC" == true ]]; then
  ufw allow 80/tcp  comment 'HTTP (ACME + redirección)'
  ufw allow 443/tcp comment 'HTTPS (Traefik)'
  log_success "80/tcp y 443/tcp abiertos a Internet"
fi

if [[ -n "$DATA_FROM" ]]; then
  for p in "${DATA_PORTS[@]}"; do
    ufw allow from "$DATA_FROM" to any port "$p" proto tcp comment 'Datos (red privada)'
  done
  log_success "Puertos de datos ${DATA_PORTS[*]} permitidos solo desde ${DATA_FROM}"
fi

if [[ -n "$OBS_FROM" ]]; then
  for p in "${OBS_PORTS[@]}"; do
    ufw allow from "$OBS_FROM" to any port "$p" proto tcp comment 'Observabilidad (red privada)'
  done
  log_success "Puertos de observabilidad ${OBS_PORTS[*]} permitidos solo desde ${OBS_FROM}"
fi

# Habilitar (idempotente)
yes | ufw enable >/dev/null
log_success "Firewall activo"
echo ""
ufw status numbered
