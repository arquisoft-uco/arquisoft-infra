#!/usr/bin/env bash
# =============================================================================
# verify-secrets.sh — Valida un .env contra lo que está DESPLEGADO
# =============================================================================
# Antes de migrar (o tras rotar) secretos, responde dos preguntas sin imprimir
# ningún valor:
#   1. ¿Están TODAS las variables que exigen los componentes que hoy corren?
#   2. ¿Las credenciales son las que REALMENTE aceptan los servicios?
#      (se autentica contra cada contenedor: Postgres, Keycloak-DB, Redis,
#       RabbitMQ, MinIO, Keycloak, Grafana, BasicAuth de Traefik)
#
# Uso (en el servidor, con acceso a docker):
#   ./scripts/verify-secrets.sh [ruta/.env]        # default: <repo>/.env
#
# Las contraseñas viajan a los contenedores por variables de entorno
# (`docker exec -e NOMBRE`), nunca como argumentos visibles en `ps` del host.
# Salida: ✅ correcto · ❌ incorrecto/faltante · ⏭  no aplica (contenedor no corre)
# Exit code: 0 si no hay ❌, 1 si hay alguno.
# =============================================================================
set -uo pipefail

INFRA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENV_FILE="${1:-$INFRA_DIR/.env}"
[[ -f "$ENV_FILE" ]] || { echo "✗ No existe $ENV_FILE"; exit 1; }
command -v docker >/dev/null || { echo "✗ docker no disponible"; exit 1; }

set -a; source "$ENV_FILE"; set +a

FAIL=0
ok()   { echo "  ✅ $1"; }
bad()  { echo "  ❌ $1"; FAIL=1; }
skip() { echo "  ⏭  $1"; }
running() { [[ "$(docker inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" == "true" ]]; }

# -----------------------------------------------------------------------------
echo "== 1. Variables requeridas por los componentes en ejecución"
# Solo los componentes que consumen el .env RAÍZ (deploy.sh + apps). Los demás
# (duckdns, mailpit, sonarqube, wireguard) se despliegan con su propio .env.
ROOT_ENV_COMPONENTS=" proxy postgres redis rabbitmq minio keycloak observability alloy backend frontend "
# Un componente cuenta si alguno de sus container_name está corriendo.
# Requeridas = ${VAR:?...} y ${VAR} sin default (no ${VAR:-x} ni $${VAR}).
missing_total=0
for compose in "$INFRA_DIR"/components/*/docker-compose.yml; do
  comp="$(basename "$(dirname "$compose")")"
  is_up=0
  while read -r cname; do running "$cname" && is_up=1; done \
    < <(grep -oE 'container_name:[[:space:]]*[A-Za-z0-9_.-]+' "$compose" | awk '{print $2}')
  (( is_up )) || continue
  if [[ "$ROOT_ENV_COMPONENTS" != *" $comp "* ]]; then
    skip "$comp: usa su propio components/$comp/.env (fuera de Doppler por ahora)"; continue
  fi

  files=("$compose")
  for t in "$INFRA_DIR/components/$comp"/config/*.template; do [[ -f "$t" ]] && files+=("$t"); done
  req="$(grep -hoE '(^|[^$])\$\{[A-Z_][A-Z0-9_]*(:\?[^}]*)?\}' "${files[@]}" 2>/dev/null \
         | grep -oE '\{[A-Z_][A-Z0-9_]*' | tr -d '{' | sort -u)"
  miss=()
  for v in $req; do [[ -n "${!v:-}" ]] || miss+=("$v"); done
  if (( ${#miss[@]} )); then bad "$comp: faltan ${miss[*]}"; missing_total=1
  else ok "$comp: completo"; fi
done
(( missing_total )) || echo "  (todas las variables requeridas están presentes)"

# -----------------------------------------------------------------------------
echo "== 2. Credenciales contra los servicios en ejecución"

# PostgreSQL: se conecta por la IP del contenedor (no loopback) para forzar
# autenticación por contraseña; 127.0.0.1 es 'trust' en la imagen oficial.
check_pg() { # contenedor usuario password base etiqueta
  local c="$1" label="$5"
  running "$c" || { skip "$label (contenedor $c no corre)"; return; }
  [[ -n "$2" && -n "$3" ]] || { bad "$label: usuario/contraseña vacíos en el .env"; return; }
  if PGUSER="$2" PGPASSWORD="$3" PGDATABASE="$4" docker exec -e PGUSER -e PGPASSWORD -e PGDATABASE "$c" \
       sh -c 'psql -h "$(hostname -i | awk "{print \$1}")" -tAc "select 1"' >/dev/null 2>&1; then
    ok "$label"
  else bad "$label: el servicio rechaza la credencial"; fi
}
check_pg arquisoft-postgres    "${POSTGRES_USER:-postgres}"     "${POSTGRES_PASSWORD:-}"    "${POSTGRES_DB:-postgres}" "PostgreSQL superusuario (POSTGRES_USER/PASSWORD)"
check_pg arquisoft-postgres    "${APP_DB_USER:-arquisoft_user}" "${APP_DB_PASSWORD:-}"      "usuarios"                 "PostgreSQL app (APP_DB_USER/PASSWORD)"
check_pg arquisoft-keycloak-db "${KEYCLOAK_DB_USER:-keycloak}"  "${KEYCLOAK_DB_PASSWORD:-}" "${KEYCLOAK_DB_NAME:-keycloak}" "Keycloak DB (KEYCLOAK_DB_USER/PASSWORD)"

# Redis (requirepass → usuario default)
if running arquisoft-redis; then
  if [[ "$(REDISCLI_AUTH="${REDIS_PASSWORD:-}" docker exec -e REDISCLI_AUTH arquisoft-redis redis-cli --no-auth-warning ping 2>/dev/null)" == "PONG" ]]; then
    ok "Redis (REDIS_PASSWORD)"
  else bad "Redis (REDIS_PASSWORD): el servicio rechaza la credencial"; fi
else skip "Redis (contenedor no corre)"; fi

# RabbitMQ: admin y usuario de aplicación
check_rmq() { # usuario password etiqueta
  [[ -n "$1" ]] || { skip "$3 (no definido en el .env)"; return; }
  if RU="$1" RP="$2" docker exec -e RU -e RP arquisoft-rabbitmq \
       sh -c 'rabbitmqctl authenticate_user "$RU" "$RP"' >/dev/null 2>&1; then ok "$3"
  else bad "$3: el servicio rechaza la credencial"; fi
}
if running arquisoft-rabbitmq; then
  check_rmq "${RABBITMQ_USER:-}"     "${RABBITMQ_PASSWORD:-}"     "RabbitMQ admin (RABBITMQ_USER/PASSWORD)"
  check_rmq "${RABBITMQ_APP_USER:-}" "${RABBITMQ_APP_PASSWORD:-}" "RabbitMQ app (RABBITMQ_APP_USER/PASSWORD)"
else skip "RabbitMQ (contenedor no corre)"; fi

# MinIO: root y cuenta del backend (mcli valida la credencial al crear el alias)
check_minio() { # access secret etiqueta
  [[ -n "$1" ]] || { skip "$3 (no definido en el .env)"; return; }
  if MU="$1" MP="$2" docker exec -e MU -e MP arquisoft-minio \
       sh -c 'mcli --config-dir /tmp/.mcli-verify alias set chk http://localhost:9000 "$MU" "$MP" >/dev/null 2>&1; r=$?; rm -rf /tmp/.mcli-verify; exit $r' >/dev/null 2>&1; then
    ok "$3"
  else bad "$3: el servicio rechaza la credencial"; fi
}
if running arquisoft-minio; then
  check_minio "${MINIO_ROOT_USER:-}"  "${MINIO_ROOT_PASSWORD:-}" "MinIO root (MINIO_ROOT_USER/PASSWORD)"
  check_minio "${MINIO_ACCESS_KEY:-}" "${MINIO_SECRET_KEY:-}"    "MinIO backend (MINIO_ACCESS_KEY/SECRET_KEY)"
else skip "MinIO (contenedor no corre)"; fi

# Keycloak: admin de la consola y secreto del cliente del backend.
# $1 = argumentos de kcadm con referencias "$KU"... que expande el sh DEL CONTENEDOR
# (los valores llegan por -e, no por la línea de comandos del host).
check_kc() { # 'args-kcadm' etiqueta VAR...
  local args="$1" label="$2"; shift 2
  local envs=(); for v in "$@"; do envs+=(-e "$v"); done
  if docker exec "${envs[@]}" arquisoft-keycloak sh -c \
       "/opt/keycloak/bin/kcadm.sh config credentials --server http://localhost:8080 --config /tmp/kcadm-verify.config $args >/dev/null 2>&1; r=\$?; rm -f /tmp/kcadm-verify.config; exit \$r" >/dev/null 2>&1; then
    ok "$label"
  else bad "$label: el servicio rechaza la credencial"; fi
}
if running arquisoft-keycloak; then
  export KU="${KEYCLOAK_ADMIN:-admin}" KP="${KEYCLOAK_ADMIN_PASSWORD:-}"
  check_kc '--realm master --user "$KU" --password "$KP"' "Keycloak admin (KEYCLOAK_ADMIN/PASSWORD)" KU KP
  if [[ -n "${KEYCLOAK_CLIENT_SECRET:-}" ]]; then
    export KR="${KEYCLOAK_REALM:-arquisoft}" KCID="${KEYCLOAK_CLIENT_ID:-arquisoft-api}" KS="$KEYCLOAK_CLIENT_SECRET"
    check_kc '--realm "$KR" --client "$KCID" --secret "$KS"' "Keycloak cliente del backend (KEYCLOAK_CLIENT_SECRET)" KR KCID KS
  else skip "Keycloak cliente del backend (KEYCLOAK_CLIENT_SECRET vacío)"; fi
  unset KU KP KR KCID KS
else skip "Keycloak (contenedor no corre)"; fi

# Grafana
if running arquisoft-grafana; then
  if GU="${GRAFANA_ADMIN_USER:-admin}" GP="${GRAFANA_ADMIN_PASSWORD:-}" docker exec -e GU -e GP arquisoft-grafana \
       sh -c 'wget -qO- --header "Authorization: Basic $(printf %s "$GU:$GP" | base64)" http://localhost:3000/api/user' >/dev/null 2>&1; then
    ok "Grafana (GRAFANA_ADMIN_USER/PASSWORD)"
  else bad "Grafana (GRAFANA_ADMIN_USER/PASSWORD): el servicio rechaza la credencial"; fi
else skip "Grafana (contenedor no corre)"; fi

# BasicAuth de consolas (Traefik dashboard) — HTTPS contra el Traefik local
# (--resolve evita depender del DNS/NAT público desde el propio servidor)
if running arquisoft-traefik && [[ -n "${DOMAIN:-}" && -n "${ADMIN_AUTH_USER:-}" ]] && command -v curl >/dev/null; then
  code="$(printf 'user = "%s:%s"\n' "$ADMIN_AUTH_USER" "${ADMIN_AUTH_PASSWORD:-}" \
          | curl -s -o /dev/null -w '%{http_code}' --max-time 10 -K - \
              --resolve "traefik.${DOMAIN}:443:127.0.0.1" "https://traefik.${DOMAIN}/dashboard/" 2>/dev/null)"
  case "$code" in
    2*|3*) ok "BasicAuth consolas (ADMIN_AUTH_USER/PASSWORD)" ;;
    401)   bad "BasicAuth consolas (ADMIN_AUTH_USER/PASSWORD): Traefik responde 401" ;;
    *)     skip "BasicAuth consolas: no se pudo comprobar (HTTP $code)" ;;
  esac
else skip "BasicAuth consolas (Traefik no corre, falta DOMAIN/ADMIN_AUTH_USER o curl)"; fi

# -----------------------------------------------------------------------------
echo "== 3. Imágenes desplegadas vs tags del .env"
check_img() { # contenedor VAR_IMAGE VAR_TAG
  local c="$1" want got
  running "$c" || { skip "$c (no corre)"; return; }
  want="${!2:-}:${!3:-latest}"
  got="$(docker inspect -f '{{.Config.Image}}' "$c")"
  [[ "$got" == "$want" ]] && ok "$c usa $3 del .env" || bad "$c corre '$got' pero el .env dice '$want' (actualiza $3)"
}
check_img arquisoft-backend  BACKEND_IMAGE  BACKEND_TAG
check_img arquisoft-frontend FRONTEND_IMAGE FRONTEND_TAG

echo "== No verificables aquí (servicios externos): DUCKDNS_TOKEN, MAIL_USERNAME/PASSWORD"
echo
(( FAIL )) && { echo "✗ Hay diferencias: corrige el .env antes de subirlo a Doppler"; exit 1; }
echo "✓ El .env coincide con lo desplegado"
