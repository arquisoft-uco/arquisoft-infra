#!/bin/bash
# ==============================================================================
# Arquisoft - Script de Validación de Ambiente de Producción
# ==============================================================================
# Valida todos los criterios de aceptación de HT-002:
# - Escenario 1: Variables de producción configuradas
# - Escenario 2: SSL automático con Let's Encrypt
# - Escenario 3: Acceso HTTPS a todas las URLs
# - Escenario 4: Recursos limitados por contenedor
#
# Uso: ./scripts/validate-prod.sh
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Cargar funciones compartidas
source "$SCRIPT_DIR/lib/common.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Arquisoft - Validación de Ambiente de Producción        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ==============================================================================
# Sección 1: Prerrequisitos
# ==============================================================================
echo -e "${BLUE}━━━ Prerrequisitos ━━━${NC}"

# Verificar y cargar .env
load_env_file ".env" || exit 1

# Verificar DOMAIN configurado y no es localhost
if [[ -z "$DOMAIN" ]]; then
    log_error "DOMAIN no configurado en .env"
    exit 1
elif [[ "$DOMAIN" == *".localhost" ]]; then
    log_error "DOMAIN es '$DOMAIN' (localhost). Este script es para producción. Usar validate-dev.sh para desarrollo."
    exit 1
else
    log_success "DOMAIN configurado: $DOMAIN"
fi

# Verificar ACME_EMAIL
if [[ -z "$ACME_EMAIL" ]]; then
    log_error "ACME_EMAIL no configurado en .env (obligatorio para producción)"
    exit 1
else
    log_success "ACME_EMAIL configurado: $ACME_EMAIL"
fi

# Verificar .htpasswd
HTPASSWD_FILE="configs/traefik/certs/.htpasswd"
if [[ -f "$HTPASSWD_FILE" ]]; then
    log_success "Archivo .htpasswd existe"
else
    log_warning "Archivo .htpasswd no encontrado. Las consolas admin requerirán BasicAuth."
fi

# Verificar Docker
if command -v docker &> /dev/null; then
    log_success "Docker instalado: $(docker --version | head -1)"
else
    log_error "Docker no instalado"
    exit 1
fi

echo ""

# ==============================================================================
# Sección 2: Verificación DNS
# ==============================================================================
echo -e "${BLUE}━━━ Verificación DNS ━━━${NC}"

check_dns() {
    local subdomain=$1
    local fqdn=$2

    # Intentar con dig primero, luego nslookup
    if command -v dig &> /dev/null; then
        local result=$(dig +short "$fqdn" 2>/dev/null | head -1)
    elif command -v nslookup &> /dev/null; then
        local result=$(nslookup "$fqdn" 2>/dev/null | grep -A1 "Name:" | grep "Address:" | awk '{print $2}' | head -1)
    else
        log_warning "Ni dig ni nslookup disponibles. Saltando verificación DNS."
        return
    fi

    if [[ -n "$result" ]]; then
        log_success "$fqdn resuelve a: $result"
    else
        log_error "$fqdn no resuelve (DNS no configurado o no propagado)"
    fi
}

check_dns "root" "$DOMAIN"
check_dns "api" "api.$DOMAIN"
check_dns "auth" "auth.$DOMAIN"
check_dns "grafana" "grafana.$DOMAIN"

echo ""

# ==============================================================================
# Sección 3: Verificación SSL
# ==============================================================================
echo -e "${BLUE}━━━ Verificación SSL ━━━${NC}"

check_ssl() {
    local fqdn=$1

    # Verificar certificado SSL vía openssl
    if ! command -v openssl &> /dev/null; then
        log_warning "openssl no disponible. Saltando verificación SSL."
        return
    fi

    local cert_info
    cert_info=$(echo | openssl s_client -servername "$fqdn" -connect "$fqdn:443" 2>/dev/null)
    local ssl_exit=$?

    if [[ $ssl_exit -ne 0 ]] || echo "$cert_info" | grep -q "connect:errno"; then
        log_error "$fqdn: No se pudo conectar al puerto 443"
        return
    fi

    # Verificar que el certificado no es auto-firmado
    local issuer=$(echo "$cert_info" | openssl x509 -noout -issuer 2>/dev/null)
    if echo "$issuer" | grep -qi "Let's Encrypt\|R3\|R10\|R11\|E5\|E6"; then
        log_success "$fqdn: Certificado Let's Encrypt válido"
    elif echo "$issuer" | grep -qi "ISRG"; then
        log_success "$fqdn: Certificado ISRG (Let's Encrypt) válido"
    else
        log_warning "$fqdn: Certificado presente pero no es Let's Encrypt ($issuer)"
    fi

    # Verificar expiración
    local expiry=$(echo "$cert_info" | openssl x509 -noout -enddate 2>/dev/null | cut -d= -f2)
    if [[ -n "$expiry" ]]; then
        local expiry_epoch=$(date -d "$expiry" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$expiry" +%s 2>/dev/null)
        local now_epoch=$(date +%s)
        if [[ -n "$expiry_epoch" ]] && [[ "$expiry_epoch" -gt "$now_epoch" ]]; then
            local days_left=$(( (expiry_epoch - now_epoch) / 86400 ))
            if [[ "$days_left" -lt 7 ]]; then
                log_warning "$fqdn: Certificado expira en $days_left días ($expiry)"
            else
                log_success "$fqdn: Certificado válido por $days_left días (expira: $expiry)"
            fi
        else
            log_error "$fqdn: Certificado expirado ($expiry)"
        fi
    fi
}

check_ssl "$DOMAIN"
check_ssl "api.$DOMAIN"
check_ssl "auth.$DOMAIN"
check_ssl "grafana.$DOMAIN"

echo ""

# ==============================================================================
# Sección 4: Verificación HTTPS
# ==============================================================================
echo -e "${BLUE}━━━ Verificación HTTPS ━━━${NC}"

check_http_status "App (Frontend)" "https://$DOMAIN" "200 302"
check_http_status "API (Backend)" "https://api.$DOMAIN" "200 302 404"
check_http_status "Auth (Keycloak)" "https://auth.$DOMAIN" "200 302 303"
check_http_status "Grafana" "https://grafana.$DOMAIN" "200 302"

echo ""

# ==============================================================================
# Sección 5: Redirect HTTP → HTTPS + Headers de Seguridad (consolidado)
# ==============================================================================
echo -e "${BLUE}━━━ Redirect HTTP → HTTPS + Headers de Seguridad ━━━${NC}"

# Función consolidada: 1 curl HTTP (redirect) + 1 curl HTTPS (headers) por endpoint
check_endpoint_security() {
    local name=$1
    local domain=$2

    # --- Redirect HTTP → HTTPS ---
    local response
    response=$(curl -sI --connect-timeout 10 --max-time 15 "http://$domain" 2>/dev/null)
    local http_code
    http_code=$(echo "$response" | head -1 | awk '{print $2}')
    local location
    location=$(echo "$response" | grep -i "^location:" | awk '{print $2}' | tr -d '\r')

    if [[ "$http_code" =~ ^(301|308|302|307)$ ]]; then
        if echo "$location" | grep -qi "^https://"; then
            log_success "$name: HTTP → HTTPS redirect ($http_code)"
        else
            log_warning "$name: Redirect $http_code pero Location no es HTTPS: $location"
        fi
    elif [[ -z "$http_code" ]]; then
        log_error "$name: No se pudo conectar a http://$domain"
    else
        log_error "$name: Sin redirect HTTP→HTTPS (HTTP $http_code)"
    fi

    # --- Headers de seguridad (reutiliza un único curl HTTPS) ---
    local headers
    headers=$(curl -sI --connect-timeout 10 --max-time 15 "https://$domain" 2>/dev/null)

    if [[ -z "$headers" ]]; then
        log_error "$name: No se pudo obtener headers HTTPS de $domain"
        return
    fi

    if echo "$headers" | grep -qi "strict-transport-security"; then
        log_success "$name: HSTS presente"
    else
        log_warning "$name: HSTS ausente"
    fi

    if echo "$headers" | grep -qi "x-frame-options"; then
        log_success "$name: X-Frame-Options presente"
    else
        log_warning "$name: X-Frame-Options ausente"
    fi

    if echo "$headers" | grep -qi "x-content-type-options"; then
        log_success "$name: X-Content-Type-Options presente"
    else
        log_warning "$name: X-Content-Type-Options ausente"
    fi
}

check_endpoint_security "App" "$DOMAIN"
check_endpoint_security "API" "api.$DOMAIN"
check_endpoint_security "Auth" "auth.$DOMAIN"
check_endpoint_security "Grafana" "grafana.$DOMAIN"

echo ""

# ==============================================================================
# Sección 7: Recursos de Contenedores
# ==============================================================================
echo -e "${BLUE}━━━ Recursos de Contenedores ━━━${NC}"

EXPECTED_CONTAINERS=(
    "arquisoft-postgres"
    "arquisoft-rabbitmq"
    "arquisoft-minio"
    "arquisoft-keycloak"
    "arquisoft-prometheus"
    "arquisoft-loki"
    "arquisoft-grafana"
    "arquisoft-traefik"
)

if docker ps --format '{{.Names}}' | grep -q "arquisoft-"; then
    # Batch inspect: obtener Memory y NanoCpus de todos los contenedores en una sola invocación
    RUNNING_CONTAINERS=$(docker ps --format '{{.Names}}' | grep "^arquisoft-" | sort)

    if [[ -n "$RUNNING_CONTAINERS" ]]; then
        # Una sola llamada docker inspect para todos los contenedores corriendo
        INSPECT_DATA=$(docker inspect --format='{{.Name}}|{{.HostConfig.Memory}}|{{.HostConfig.NanoCpus}}' $RUNNING_CONTAINERS 2>/dev/null)

        for container in "${EXPECTED_CONTAINERS[@]}"; do
            CONTAINER_LINE=$(echo "$INSPECT_DATA" | grep "/$container|" || true)

            if [[ -z "$CONTAINER_LINE" ]]; then
                log_warning "$container: no está corriendo, saltando verificación de limits"
                continue
            fi

            local_mem_limit=$(echo "$CONTAINER_LINE" | cut -d'|' -f2)
            local_cpu_limit=$(echo "$CONTAINER_LINE" | cut -d'|' -f3)

            if [[ "$local_mem_limit" -eq 0 ]]; then
                log_error "$container: SIN límite de memoria configurado"
            else
                local mem_mb=$((local_mem_limit / 1048576))
                log_success "$container: Límite memoria ${mem_mb}MB"
            fi

            if [[ "$local_cpu_limit" -eq 0 ]]; then
                log_warning "$container: Sin límite de CPU configurado"
            else
                local cpu_val=$(echo "scale=2; $local_cpu_limit / 1000000000" | bc 2>/dev/null || echo "N/A")
                log_success "$container: Límite CPU ${cpu_val} cores"
            fi
        done
    fi

    echo ""
    echo -e "${BLUE}Uso actual de recursos:${NC}"
    docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | grep "arquisoft-" | while read line; do
        echo -e "  $line"
    done
else
    log_error "No se encontraron contenedores arquisoft-* corriendo"
fi

echo ""

# ==============================================================================
# Sección 8: Healthchecks de Contenedores
# ==============================================================================
echo -e "${BLUE}━━━ Healthchecks de Contenedores ━━━${NC}"

# Servicios Core
check_container_health "arquisoft-postgres"
check_container_health "arquisoft-rabbitmq"
check_container_health "arquisoft-minio"

# Servicios Auth
check_container_health "arquisoft-keycloak"

# Servicios Observability
check_container_health "arquisoft-prometheus"
check_container_health "arquisoft-loki"
check_container_health "arquisoft-grafana"

# Traefik
if docker ps --format '{{.Names}}' | grep -q "arquisoft-traefik"; then
    log_success "arquisoft-traefik: running"
else
    log_error "arquisoft-traefik: not running (required in production)"
fi

echo ""

# ==============================================================================
# Resumen
# ==============================================================================
print_summary "RESUMEN VALIDACIÓN PRODUCCIÓN"
exit $?
