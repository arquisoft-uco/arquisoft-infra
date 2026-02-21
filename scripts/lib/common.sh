#!/bin/bash
# ==============================================================================
# Arquisoft - Funciones compartidas para scripts
# ==============================================================================
# Colores, logging y utilidades comunes.
# Uso: source "$SCRIPT_DIR/lib/common.sh"
# ==============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Contadores
ERRORS=0
WARNINGS=0

# Funciones de logging
log_info() { echo -e "${BLUE}ℹ ${NC}$1"; }
log_success() { echo -e "${GREEN}✓ ${NC}$1"; }
log_warning() { echo -e "${YELLOW}⚠ ${NC}$1"; ((WARNINGS+=1)); }
log_error() { echo -e "${RED}✗ ${NC}$1"; ((ERRORS+=1)); }

# Función para escapar caracteres especiales en valores para sed
escape_sed() {
    local str=$1
    printf '%s\n' "$str" | sed 's/[&/\$]/\\&/g'
}

# Resumen final de validación
print_summary() {
    local title="${1:-RESUMEN}"
    printf -v padded "%-60s" "$title"
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ${padded}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

    if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ Todas las verificaciones PASARON${NC}"
        return 0
    elif [[ $ERRORS -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Verificación completada con $WARNINGS advertencias${NC}"
        return 0
    else
        echo -e "${RED}✗ Verificación FALLIDA: $ERRORS errores, $WARNINGS advertencias${NC}"
        return 1
    fi
}

# Función para cargar archivo .env de forma segura
load_env_file() {
    local env_file="${1:-.env}"
    if [[ -f "$env_file" ]]; then
        log_success "Archivo .env existe"
        if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' "$env_file"; then
            # Parser seguro: leer línea por línea, sin eval
            while IFS= read -r line || [[ -n "$line" ]]; do
                # Ignorar líneas vacías y comentarios
                [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
                # Solo procesar líneas con formato KEY=VALUE
                if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
                    local key="${line%%=*}"
                    local value="${line#*=}"
                    export "$key=$value"
                fi
            done < "$env_file"
        else
            log_error "Archivo .env tiene formato inválido"
            return 1
        fi
    else
        log_error "Archivo .env no encontrado. Ejecutar: ./scripts/setup-env.sh"
        return 1
    fi
}

# Función para verificar el estado de salud de un contenedor Docker
check_container_health() {
    local container=$1
    local status=$(docker inspect --format='{{.State.Health.Status}}' "$container" 2>/dev/null || echo "not_found")

    case "$status" in
        "healthy")
            log_success "$container: healthy"
            ;;
        "unhealthy")
            log_error "$container: unhealthy"
            ;;
        "starting")
            log_warning "$container: still starting"
            ;;
        "not_found")
            log_error "$container: container not found"
            ;;
        *)
            log_warning "$container: status unknown ($status)"
            ;;
    esac
}

# Función para verificar estado HTTP/HTTPS de una URL
check_http_status() {
    local name=$1
    local url=$2
    local expected_codes=${3:-"200 204 302 401"}
    local timeout=${4:-10}

    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$timeout" --max-time $((timeout + 5)) "$url" 2>/dev/null || echo "000")

    if [[ " $expected_codes " =~ " $http_code " ]]; then
        log_success "$name: HTTP $http_code"
    elif [[ "$http_code" == "000" ]]; then
        log_error "$name: Unreachable ($url)"
    else
        log_warning "$name: HTTP $http_code (expected: $expected_codes)"
    fi
}

# Función para verificar headers de seguridad HTTP
check_security_headers() {
    local name=$1
    local url=$2

    local headers=$(curl -sI --connect-timeout 10 --max-time 15 "$url" 2>/dev/null)

    if [[ -z "$headers" ]]; then
        log_error "$name: No se pudo obtener headers de $url"
        return
    fi

    # HSTS
    if echo "$headers" | grep -qi "strict-transport-security"; then
        log_success "$name: HSTS presente"
    else
        log_warning "$name: HSTS ausente (Strict-Transport-Security)"
    fi

    # X-Frame-Options
    if echo "$headers" | grep -qi "x-frame-options"; then
        log_success "$name: X-Frame-Options presente"
    else
        log_warning "$name: X-Frame-Options ausente"
    fi

    # X-Content-Type-Options
    if echo "$headers" | grep -qi "x-content-type-options"; then
        log_success "$name: X-Content-Type-Options presente"
    else
        log_warning "$name: X-Content-Type-Options ausente"
    fi
}
