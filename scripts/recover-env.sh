#!/usr/bin/env bash
# =============================================================================
# recover-env.sh — Reconstruye el .env a partir de lo que está DESPLEGADO
# =============================================================================
# Cuando no se sabe qué .env se usó para levantar los contenedores, la fuente
# de verdad son los propios contenedores: Docker guarda el entorno con el que
# se crearon. Este script parte de un .env base (comentarios, orden y variables
# no recuperables) y sobrescribe cada secreto con el valor del contenedor que lo
# usa. NUNCA imprime valores: solo nombres de variables y de dónde salieron.
#
# Uso (en el servidor, con acceso a docker):
#   ./scripts/recover-env.sh [base.env] [salida]
#     base   default: <repo>/.env
#     salida default: ${TMPDIR:-/tmp}/arquisoft.env.recuperado   (modo 600)
#   ./scripts/verify-secrets.sh <salida>     # comprobar el resultado
#
# Limitaciones (el verificador las detecta):
#   - KEYCLOAK_ADMIN_PASSWORD y GRAFANA_ADMIN_PASSWORD solo se aplican en el
#     primer arranque: si se cambiaron desde la consola, el contenedor guarda el
#     valor original.
#   - ADMIN_AUTH_PASSWORD (BasicAuth) solo existe como hash: se conserva del base.
# =============================================================================
set -euo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="${1:-$INFRA_DIR/.env}"
OUT="${2:-${TMPDIR:-/tmp}/arquisoft.env.recuperado}"
umask 077

[[ -f "$BASE" ]] || { echo "✗ No existe el .env base: $BASE"; exit 1; }
command -v docker >/dev/null || { echo "✗ docker no disponible"; exit 1; }
[[ "$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")" != "$(cd "$(dirname "$BASE")" && pwd)/$(basename "$BASE")" ]] \
  || { echo "✗ La salida no puede ser el mismo archivo base"; exit 1; }

# --- Entorno de cada contenedor (cacheado; nunca se imprime) ------------------
declare -A CENV=()
cenv() { # contenedor VAR → valor por stdout (vacío si no existe)
  local c="$1" k="$2"
  if [[ -z "${CENV[$c]+x}" ]]; then
    CENV[$c]="$(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$c" 2>/dev/null || true)"
  fi
  K="$k" awk 'BEGIN{k=ENVIRON["K"]"="} index($0,k)==1 {print substr($0,length(k)+1); exit}' <<<"${CENV[$c]}"
}

# --- Escritura en el .env de salida -------------------------------------------
# Comillas simples cuando hace falta: literales para bash (source) y compose.
fmt_value() {
  local v="$1"
  if [[ "$v" =~ ^[A-Za-z0-9_./:@,+=%-]*$ ]]; then printf '%s' "$v"
  elif [[ "$v" != *"'"* ]]; then printf "'%s'" "$v"
  else v="${v//\\/\\\\}"; v="${v//\"/\\\"}"; printf '"%s"' "$v"
  fi
}
set_out() { # VAR valor (el valor viaja por ENVIRON, no por argumentos visibles)
  local line tmp; line="$1=$(fmt_value "$2")"
  [[ "$2" != *"'"* ]] || WARN+=("$1 contiene comillas simples: revisa su formato en la salida")
  tmp="$(mktemp "$OUT.XXXXXX")"
  K="$1" L="$line" awk 'BEGIN{k=ENVIRON["K"]"="; l=ENVIRON["L"]; done=0}
    index($0,k)==1 { if (!done) print l; done=1; next } {print}
    END{ if (!done) print l }' "$OUT" > "$tmp"
  mv "$tmp" "$OUT"
}
base_val() { # VAR → valor en el base (vía source en subshell, igual que deploy.sh)
  ( set +u; set -a; source "$BASE" >/dev/null 2>&1; set +a; printf '%s' "${!1:-}" )
}

cp "$BASE" "$OUT"; chmod 600 "$OUT"
CHANGED=(); SAME=(); NOSRC=(); WARN=()

# recover VAR "contenedor:VAR_CONTENEDOR ..."  — la primera fuente con valor gana
recover() {
  local var="$1" src val="" from="" c k v
  for src in $2; do
    c="${src%%:*}"; k="${src#*:}"; v="$(cenv "$c" "$k")"
    [[ -n "$v" ]] || continue
    if [[ -z "$from" ]]; then val="$v"; from="$c"
    elif [[ "$v" != "$val" ]]; then WARN+=("$var: $from y $c tienen valores distintos (se usa $from)"); fi
  done
  apply "$var" "$val" "$from"
}
apply() { # VAR valor fuente
  local var="$1" val="$2" from="$3"
  if [[ -z "$from" ]]; then NOSRC+=("$var"); return; fi
  if [[ "$(base_val "$var")" == "$val" ]]; then SAME+=("$var")
  else set_out "$var" "$val"; CHANGED+=("$var ← $from"); fi
}

# --- ¿Desde qué carpeta se desplegó cada contenedor? --------------------------
echo "== Carpetas desde las que se desplegaron los contenedores arquisoft-*"
docker ps --filter name=arquisoft- --format '{{.Label "com.docker.compose.project.working_dir"}}|{{.Names}}' \
  | sort | awk -F'|' '$1!=p {if (p!="") print ""; printf "  %s:", ($1==""?"(sin compose)":$1); p=$1} {printf " %s", $2} END{print ""}'

# --- Secretos y configuración ------------------------------------------------
recover POSTGRES_USER           "arquisoft-postgres:POSTGRES_USER"
recover POSTGRES_PASSWORD       "arquisoft-postgres:POSTGRES_PASSWORD"
recover POSTGRES_DB             "arquisoft-postgres:POSTGRES_DB"
recover APP_DB_USER             "arquisoft-backend:DB_USUARIOS_USERNAME arquisoft-postgres:APP_DB_USER"
recover APP_DB_PASSWORD         "arquisoft-backend:DB_USUARIOS_PASSWORD arquisoft-postgres:APP_DB_PASSWORD"
recover KEYCLOAK_DB_USER        "arquisoft-keycloak:KC_DB_USERNAME arquisoft-keycloak-db:POSTGRES_USER"
recover KEYCLOAK_DB_PASSWORD    "arquisoft-keycloak:KC_DB_PASSWORD arquisoft-keycloak-db:POSTGRES_PASSWORD"
recover KEYCLOAK_DB_NAME        "arquisoft-keycloak-db:POSTGRES_DB"
recover KEYCLOAK_ADMIN          "arquisoft-keycloak:KC_BOOTSTRAP_ADMIN_USERNAME"
recover KEYCLOAK_ADMIN_PASSWORD "arquisoft-keycloak:KC_BOOTSTRAP_ADMIN_PASSWORD"
recover KEYCLOAK_REALM          "arquisoft-backend:KEYCLOAK_REALM"
recover KEYCLOAK_CLIENT_ID      "arquisoft-backend:KEYCLOAK_CLIENT_ID"
recover KEYCLOAK_CLIENT_SECRET  "arquisoft-backend:KEYCLOAK_CLIENT_SECRET"
recover REDIS_PASSWORD          "arquisoft-redis:REDIS_PASSWORD arquisoft-backend:REDIS_PASSWORD"
recover REDIS_USER              "arquisoft-backend:REDIS_USER"
recover REDIS_HOST              "arquisoft-backend:REDIS_HOST"
recover REDIS_PORT              "arquisoft-backend:REDIS_PORT"
recover RABBITMQ_HOST           "arquisoft-backend:RABBITMQ_HOST"
recover RABBITMQ_PORT           "arquisoft-backend:RABBITMQ_PORT"
recover MINIO_ROOT_USER         "arquisoft-minio:MINIO_ROOT_USER"
recover MINIO_ROOT_PASSWORD     "arquisoft-minio:MINIO_ROOT_PASSWORD"
recover MINIO_ACCESS_KEY        "arquisoft-backend:MINIO_ACCESS_KEY"
recover MINIO_SECRET_KEY        "arquisoft-backend:MINIO_SECRET_KEY"
recover MINIO_ENDPOINT          "arquisoft-backend:MINIO_ENDPOINT"
recover GRAFANA_ADMIN_USER      "arquisoft-grafana:GF_SECURITY_ADMIN_USER"
recover GRAFANA_ADMIN_PASSWORD  "arquisoft-grafana:GF_SECURITY_ADMIN_PASSWORD"
recover SPRING_PROFILES_ACTIVE  "arquisoft-backend:SPRING_PROFILES_ACTIVE"
recover JAVA_TOOL_OPTIONS       "arquisoft-backend:JAVA_TOOL_OPTIONS"

# DOMAIN: el backend recibe KEYCLOAK_URL=https://auth.${DOMAIN}
kc_url="$(cenv arquisoft-backend KEYCLOAK_URL)"
if [[ "$kc_url" == https://auth.* ]]; then apply DOMAIN "${kc_url#https://auth.}" arquisoft-backend
else NOSRC+=(DOMAIN); fi
# MINIO_PUBLIC_ENDPOINT: solo si difiere del default https://s3.${DOMAIN}
mpe="$(cenv arquisoft-backend MINIO_PUBLIC_ENDPOINT)"; dom="${kc_url#https://auth.}"
if [[ -n "$mpe" && ( "$mpe" != "https://s3.$dom" || -n "$(base_val MINIO_PUBLIC_ENDPOINT)" ) ]]; then
  apply MINIO_PUBLIC_ENDPOINT "$mpe" arquisoft-backend
fi

# RabbitMQ: los usuarios reales salen de definitions.json (se importa en cada
# arranque); RABBITMQ_DEFAULT_* y el backend quedan como respaldo.
RMQ_FROM_DEFS=0
defs="$(docker exec arquisoft-rabbitmq cat /etc/rabbitmq/definitions.json 2>/dev/null || true)"
if [[ -n "$defs" ]] && command -v python3 >/dev/null; then
  # Salida: rol<TAB>usuario<TAB>password por línea (solo a variables, nunca a pantalla)
  rmq="$(python3 -c '
import json, sys
for u in json.load(sys.stdin).get("users", []):
    tags = u.get("tags", [])
    tags = tags if isinstance(tags, list) else str(tags).split(",")
    role = "admin" if "administrator" in tags else "app"
    print(role, u.get("name", ""), u.get("password", ""), sep="\t")
' <<<"$defs" 2>/dev/null || true)"
  while IFS=$'\t' read -r role name pass; do
    [[ -n "$name" ]] || continue
    if [[ "$role" == admin ]]; then u=RABBITMQ_USER; p=RABBITMQ_PASSWORD; RMQ_FROM_DEFS=1
    else u=RABBITMQ_APP_USER; p=RABBITMQ_APP_PASSWORD; fi
    apply "$u" "$name" definitions.json
    if [[ -n "$pass" ]]; then apply "$p" "$pass" definitions.json
    else WARN+=("$p: definitions.json usa password_hash (no recuperable)"); fi
  done <<<"$rmq"
fi
if (( ! RMQ_FROM_DEFS )); then
  recover RABBITMQ_USER     "arquisoft-backend:RABBITMQ_USERNAME arquisoft-rabbitmq:RABBITMQ_DEFAULT_USER"
  recover RABBITMQ_PASSWORD "arquisoft-backend:RABBITMQ_PASSWORD arquisoft-rabbitmq:RABBITMQ_DEFAULT_PASS"
fi

# Imágenes de las apps (repo:tag)
img_split() { # contenedor VAR_IMAGE VAR_TAG
  local img; img="$(docker inspect -f '{{.Config.Image}}' "$1" 2>/dev/null || true)"
  [[ -n "$img" ]] || { NOSRC+=("$2" "$3"); return; }
  if [[ "${img##*/}" == *:* ]]; then apply "$2" "${img%:*}" "$1"; apply "$3" "${img##*:}" "$1"
  else apply "$2" "$img" "$1"; apply "$3" latest "$1"; fi
}
img_split arquisoft-backend  BACKEND_IMAGE  BACKEND_TAG
img_split arquisoft-frontend FRONTEND_IMAGE FRONTEND_TAG

# --- Resumen (solo nombres) --------------------------------------------------
echo "== Recuperadas de los contenedores (cambian respecto al base)"
if (( ${#CHANGED[@]} )); then printf '  ✏️  %s\n' "${CHANGED[@]}"; else echo "  (ninguna)"; fi
echo "== Ya coincidían con el base"
if (( ${#SAME[@]} )); then echo "  ${SAME[*]}"; else echo "  (ninguna)"; fi
echo "== Sin fuente en los contenedores (se conservan del base)"
if (( ${#NOSRC[@]} )); then echo "  ${NOSRC[*]}"; else echo "  (ninguna)"; fi
echo "  + todo lo que no es credencial (TIMEZONE, ACME_EMAIL, ADMIN_AUTH_*, URLs de observabilidad…)"
if (( ${#WARN[@]} )); then echo "== Avisos"; printf '  ⚠  %s\n' "${WARN[@]}"; fi
echo
echo "✓ Escrito $OUT (modo 600). Siguiente paso:"
echo "  ./scripts/verify-secrets.sh $OUT"
