#!/usr/bin/env bash
# =============================================================================
# fetch-secrets.sh — Adaptador del baúl de secretos
# =============================================================================
# ÚNICO punto del repo que sabe de dónde salen los secretos. El resto
# (deploy.sh, redeploy-app.sh, compose) solo consume el .env raíz.
# Cambiar de baúl (Doppler → SOPS, Infisical, …) = agregar un proveedor aquí.
#
# Uso:
#   scripts/fetch-secrets.sh [fetch]         # genera/valida el .env raíz
#   scripts/fetch-secrets.sh set KEY=VALUE   # persiste un valor NO secreto (p. ej. BACKEND_TAG)
#   scripts/fetch-secrets.sh provider        # imprime el proveedor resuelto
#   scripts/fetch-secrets.sh tools --check   # compara components/<c>/.env con el baúl
#   scripts/fetch-secrets.sh tools [c...]    # escribe el .env de mailpit/sonarqube/duckdns
#
# Variables:
#   SECRETS_PROVIDER  auto (default) | doppler | file
#                       auto    → doppler si el CLI está instalado y hay token
#                                 (DOPPLER_TOKEN o token configurado para este
#                                 directorio); si no, file.
#                       doppler → descarga el config de Doppler al .env.
#                       file    → usa el .env existente tal cual (comportamiento previo).
#   ENV_FILE          ruta del .env (default: <repo>/.env)
#   DOPPLER_TOKEN     service token (CI). Opcional si hay token configurado con
#                     `doppler configure set token <t> --scope <repo>` o `doppler setup`.
#
# Si el proveedor es doppler y falla (red, token), el script FALLA: nunca cae
# en silencio al .env local, para no desplegar valores desactualizados.
# =============================================================================
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$INFRA_DIR/scripts/lib/common.sh"

ENV_FILE="${ENV_FILE:-$INFRA_DIR/.env}"
CMD="${1:-fetch}"

# ---------- Resolución del proveedor ----------
# Doppler está "configurado" para este repo si hay service token en el entorno
# (ya implica proyecto/config) o si el directorio tiene token Y proyecto
# (`doppler setup`, o `doppler configure set token/project/config --scope`).
# Tener solo sesión iniciada (`doppler login`) NO basta.
doppler_configured() {
  command -v doppler >/dev/null 2>&1 || return 1
  [[ -n "${DOPPLER_TOKEN:-}" ]] && return 0
  local t p
  t="$(cd "$INFRA_DIR" && doppler configure get token --plain 2>/dev/null || true)"
  p="$(cd "$INFRA_DIR" && doppler configure get enclave.project --plain 2>/dev/null || true)"
  [[ -n "$t" && -n "$p" ]] && return 0
  # Service token por scope: el token ya trae proyecto/config
  [[ "$t" == dp.st.* ]]
}

resolve_provider() {
  local p="${SECRETS_PROVIDER:-auto}"
  case "$p" in
    auto) if doppler_configured; then echo doppler; else echo file; fi ;;
    doppler|file) echo "$p" ;;
    *) log_error "SECRETS_PROVIDER inválido: '$p' (auto | doppler | file)" >&2; exit 1 ;;
  esac
}

require_env_file() {
  [[ -f "$ENV_FILE" ]] || { log_error ".env no encontrado ($ENV_FILE). Ejecutar ./setup-env.sh o configurar Doppler"; exit 1; }
}

validate_env_content() {
  grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' "$1" || { log_error "El .env generado está vacío o no tiene variables"; return 1; }
}

# ---------- Proveedor: doppler ----------
doppler_fetch() {
  command -v doppler >/dev/null 2>&1 || { log_error "Doppler CLI no instalado (ver docs/SECRETOS.md)"; exit 1; }
  local tmp
  tmp="$(mktemp "${ENV_FILE}.XXXXXX")"          # mktemp crea con permisos 600
  trap 'rm -f "$tmp"' EXIT
  # --format env entrecomilla los valores (JAVA_TOOL_OPTIONS lleva espacios);
  # --format docker NO sirve: rompe el `source` de deploy.sh.
  # --no-fallback: sin caché local; si Doppler no responde, se falla (nada de valores viejos).
  if ! (cd "$INFRA_DIR" && doppler secrets download --no-file --format env \
          --no-fallback --no-check-version --silent) > "$tmp"; then
    log_error "No se pudieron descargar los secretos de Doppler (token, red o config)"; exit 1
  fi
  # Quitar metadatos que agrega Doppler para que el .env quede igual al formato de .env.example
  sed -i -E '/^DOPPLER_(PROJECT|CONFIG|ENVIRONMENT)=/d' "$tmp"
  validate_env_content "$tmp" || exit 1
  mv -f "$tmp" "$ENV_FILE"
  trap - EXIT
  chmod 600 "$ENV_FILE"
  log_success ".env generado desde Doppler ($(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=' "$ENV_FILE") variables)"
}

doppler_set() {
  (cd "$INFRA_DIR" && doppler secrets set "$1=$2" --silent --no-check-version >/dev/null) \
    || { log_error "No se pudo actualizar $1 en Doppler (¿el token es de solo lectura?)"; exit 1; }
  log_success "$1 actualizado en Doppler"
}

# ---------- Proveedor: file ----------
file_fetch() {
  require_env_file
  validate_env_content "$ENV_FILE" || exit 1
  log_info "Usando .env local (SECRETS_PROVIDER=file)"
}

file_set() {
  require_env_file
  local tmp
  tmp="$(mktemp)"
  if grep -q "^$1=" "$ENV_FILE"; then
    awk -v k="$1" -v v="$2" 'index($0, k"=")==1 {print k"="v; next} {print}' "$ENV_FILE" > "$tmp"
  else
    cat "$ENV_FILE" > "$tmp"; printf '%s=%s\n' "$1" "$2" >> "$tmp"
  fi
  cat "$tmp" > "$ENV_FILE"   # conserva permisos y dueño del .env
  rm -f "$tmp"
  log_success "$1 actualizado en .env"
}

# ---------- .env de herramientas (fuera de Terraform) ----------
# mailpit, sonarqube y duckdns se levantan con `docker compose` desde su carpeta y
# leen components/<c>/.env. Sus valores viven en el mismo config del baúl (y por
# tanto en el .env raíz); aquí se copian SOLO las claves que declara su .env.example.
# No depende del proveedor: sale del .env raíz ya generado por `fetch`.
TOOLS_DEFAULT="mailpit sonarqube duckdns"

has_key() { grep -qE "^$2=" "$1"; }

# Valor de la clave $2 en el archivo $1 (última aparición), sin las comillas que
# agrega `doppler --format env` ni las simples de un .env escrito a mano.
key_value() {
  awk -v k="$2" '
    index($0, k "=") == 1 { v = substr($0, length(k) + 2) }
    END {
      if (v ~ /^".*"$/)      { v = substr(v, 2, length(v) - 2); gsub(/\\"/, "\"", v) }
      else if (v ~ /^\047.*\047$/) { v = substr(v, 2, length(v) - 2) }
      printf "%s", v
    }' "$1"
}

# Escribe el valor tal cual si es seguro; si no, entre comillas simples (docker
# compose no interpola dentro de ellas, así un `$` no se pierde).
format_value() {
  if [[ "$1" =~ ^[A-Za-z0-9_./:@,+=%-]*$ ]]; then printf '%s' "$1"
  elif [[ "$1" != *"'"* ]]; then printf "'%s'" "$1"
  else return 1; fi
}

# tools_env check|write [componentes...]
#   check → compara sin escribir: idéntico / distinto / sin .env (solo nombres)
#   write → escribe components/<c>/.env (600). Si ya era idéntico no lo toca; si
#           cambia, guarda una copia .env.bak-<fecha>. Nunca escribe a medias:
#           omite el componente si falta una clave en el baúl o si el .env actual
#           tiene claves que el .env.example no declara (se perderían).
tools_env() {
  local mode="$1"; shift
  local comps=("$@")
  [[ ${#comps[@]} -gt 0 ]] || read -r -a comps <<< "$TOOLS_DEFAULT"
  require_env_file
  local rc=0 c ex out keys k v fv tmp missing extra diff
  for c in "${comps[@]}"; do
    ex="$INFRA_DIR/components/$c/.env.example"; out="$INFRA_DIR/components/$c/.env"
    [[ -f "$ex" ]] || { log_error "$c: no existe components/$c/.env.example"; rc=1; continue; }
    keys="$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$ex" | tr -d '=')"

    missing=""
    for k in $keys; do has_key "$ENV_FILE" "$k" || missing+=" $k"; done
    if [[ -n "$missing" ]]; then log_warning "$c: omitido, faltan en el baúl:$missing"; continue; fi

    tmp="$(mktemp)"
    for k in $keys; do
      v="$(key_value "$ENV_FILE" "$k")"
      fv="$(format_value "$v")" \
        || { log_error "$c: $k tiene comillas simples y caracteres especiales; no se puede escribir"; rm -f "$tmp"; rc=1; continue 2; }
      printf '%s=%s\n' "$k" "$fv" >> "$tmp"
    done

    diff=""; extra=""
    if [[ -f "$out" ]]; then
      for k in $keys; do
        if ! has_key "$out" "$k" || [[ "$(key_value "$out" "$k")" != "$(key_value "$tmp" "$k")" ]]; then diff+=" $k"; fi
      done
      for k in $(grep -oE '^[A-Za-z_][A-Za-z0-9_]*=' "$out" | tr -d '=' | sort -u); do
        grep -qxF "$k" <<< "$keys" || extra+=" $k"
      done
    fi

    if [[ "$mode" == check ]]; then
      if [[ ! -f "$out" ]]; then log_info "$c: sin .env (se crearía)"
      elif [[ -z "$diff$extra" ]]; then log_success "$c: idéntico al baúl"
      else
        [[ -n "$diff" ]] && log_warning "$c: distinto en:$diff"
        [[ -n "$extra" ]] && log_warning "$c: el .env actual tiene claves que el .env.example no declara:$extra"
      fi
      rm -f "$tmp"; continue
    fi

    if [[ -n "$extra" ]]; then
      log_error "$c: no se escribe; el .env actual tiene claves fuera del .env.example:$extra"
      rm -f "$tmp"; rc=1; continue
    fi
    if [[ -f "$out" && -z "$diff" ]]; then
      log_success "$c: sin cambios"; rm -f "$tmp"; continue
    fi
    if [[ -f "$out" ]]; then
      cp -p "$out" "$out.bak-$(date +%Y%m%d-%H%M%S)"
      cat "$tmp" > "$out"          # conserva permisos y dueño
      log_success "$c: .env actualizado (cambió:$diff; copia previa .env.bak-*)"
    else
      install -m 600 "$tmp" "$out"
      log_success "$c: .env creado"
    fi
    rm -f "$tmp"
  done
  return "$rc"
}

# ---------- Main ----------
PROVIDER="$(resolve_provider)"

case "$CMD" in
  fetch)
    "${PROVIDER}_fetch"
    ;;
  set)
    kv="${2:-}"
    [[ "$kv" == *=* ]] || { log_error "Uso: $0 set KEY=VALUE"; exit 1; }
    key="${kv%%=*}"; val="${kv#*=}"
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || { log_error "Nombre de variable inválido: '$key'"; exit 1; }
    "${PROVIDER}_set" "$key" "$val"
    ;;
  provider)
    echo "$PROVIDER"
    ;;
  tools)
    shift
    if [[ "${1:-}" == "--check" ]]; then shift; tools_env check "$@"; else tools_env write "$@"; fi
    ;;
  *)
    echo "Uso: $0 [fetch | set KEY=VALUE | provider | tools [--check] [componentes...]]"; exit 1
    ;;
esac
