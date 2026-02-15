#!/bin/bash
# ==============================================================================
# Arquisoft - Script de Validación de Seguridad
# ==============================================================================
# Valida los criterios de seguridad para exposición a internet:
# - Servicios sensibles NO accesibles desde IP externa
# - Redirección HTTP→HTTPS funciona
# - Headers de seguridad presentes
# - Autenticación requerida en consolas administrativas
#
# Uso: ./scripts/validate-security.sh [EXTERNAL_IP]
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Cargar funciones compartidas
source "$SCRIPT_DIR/lib/common.sh"

# IP externa para pruebas (opcional)
EXTERNAL_IP="${1:-$(curl -s ifconfig.me 2>/dev/null || echo "")}"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║        Arquisoft - Validación de Seguridad                   ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [[ -n "$EXTERNAL_IP" ]]; then
    log_info "IP externa detectada: $EXTERNAL_IP"
else
    log_warning "No se pudo detectar IP externa. Algunas pruebas se omitirán."
fi
echo ""

# ==============================================================================
# 1. Servicios NO expuestos externamente
# ==============================================================================
echo -e "${BLUE}━━━ 1. Servicios Sensibles NO Expuestos ━━━${NC}"

check_port_not_exposed() {
    local name=$1
    local port=$2
    
    # Verificar si el puerto está escuchando en 0.0.0.0 (todas las interfaces)
    local listening=""
    
    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]] || command -v cmd.exe &>/dev/null; then
        # Windows: usar netstat con formato Windows (requiere Git Bash o WSL)
        listening=$(netstat -an 2>/dev/null | grep "LISTENING" | grep ":$port " | grep "0.0.0.0" || echo "")
    else
        # Linux/macOS
        listening=$(netstat -tuln 2>/dev/null | grep ":$port " | grep "0.0.0.0" || ss -tuln 2>/dev/null | grep ":$port " | grep "0.0.0.0" || echo "")
    fi
    
    if [[ -z "$listening" ]]; then
        log_success "$name (puerto $port): No expuesto globalmente"
        return 0
    else
        log_error "$name (puerto $port): ¡EXPUESTO en 0.0.0.0!"
        return 1
    fi
}

# PostgreSQL no debe estar expuesto
check_port_not_exposed "PostgreSQL" "5432"

# RabbitMQ AMQP no debe estar expuesto
check_port_not_exposed "RabbitMQ AMQP" "5672"

# MinIO API no debe estar expuesta directamente
check_port_not_exposed "MinIO API" "9000"

echo ""

# ==============================================================================
# 2. Servicios requieren autenticación
# ==============================================================================
echo -e "${BLUE}━━━ 2. Autenticación Requerida en Consolas ━━━${NC}"

check_requires_auth() {
    local name=$1
    local url=$2
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    
    # 401 = Unauthorized, 403 = Forbidden, 302/303 = Redirect to login
    if [[ "$http_code" =~ ^(401|403|302|303)$ ]]; then
        log_success "$name: Requiere autenticación (HTTP $http_code)"
        return 0
    elif [[ "$http_code" == "200" ]]; then
        log_warning "$name: Acceso sin autenticación permitido (HTTP 200)"
        return 1
    else
        log_info "$name: HTTP $http_code"
        return 0
    fi
}

check_requires_auth "RabbitMQ Management" "http://localhost:15672/api/overview"
check_requires_auth "MinIO Console" "http://localhost:9001"
check_requires_auth "Keycloak Admin" "http://localhost:8080/admin"
check_requires_auth "Grafana" "http://localhost:3000/api/admin/settings"

echo ""

# ==============================================================================
# 3. Headers de Seguridad (si Traefik está configurado)
# ==============================================================================
echo -e "${BLUE}━━━ 3. Headers de Seguridad ━━━${NC}"

check_security_headers() {
    local url=$1
    local headers=$(curl -s -I --connect-timeout 5 "$url" 2>/dev/null | grep -i "^X-\|^Strict-Transport" || echo "")
    
    if [[ -z "$headers" ]]; then
        log_warning "No se pudieron verificar headers en $url"
        return 1
    fi
    
    # Verificar headers específicos
    if echo "$headers" | grep -qi "X-Frame-Options"; then
        log_success "X-Frame-Options: presente"
    else
        log_warning "X-Frame-Options: ausente"
    fi
    
    if echo "$headers" | grep -qi "X-Content-Type-Options"; then
        log_success "X-Content-Type-Options: presente"
    else
        log_warning "X-Content-Type-Options: ausente"
    fi
    
    if echo "$headers" | grep -qi "Strict-Transport-Security"; then
        log_success "Strict-Transport-Security (HSTS): presente"
    else
        log_info "Strict-Transport-Security: ausente (normal en desarrollo HTTP)"
    fi
}

# Solo verificar si Traefik está corriendo
if docker ps --format '{{.Names}}' | grep -q "arquisoft-traefik"; then
    check_security_headers "http://localhost"
else
    log_info "Traefik no está corriendo. Omitiendo verificación de headers."
fi

echo ""

# ==============================================================================
# 4. HTTPS Configurado (si aplica producción)
# ==============================================================================
echo -e "${BLUE}━━━ 4. Configuración HTTPS ━━━${NC}"

# Verificar si existe configuración de certificados
if [[ -f "$PROJECT_ROOT/configs/traefik/dynamic.yaml" ]]; then
    if grep -q "tls\|certResolver\|letsencrypt" "$PROJECT_ROOT/configs/traefik/dynamic.yaml" 2>/dev/null; then
        log_success "Configuración TLS encontrada en Traefik"
    else
        log_info "Sin configuración TLS explícita (normal para desarrollo)"
    fi
else
    log_info "Archivo dynamic.yaml no encontrado"
fi

# Verificar si acme.json existe y tiene permisos correctos
if [[ -f "$PROJECT_ROOT/acme.json" ]]; then
    PERMS=$(stat -c "%a" "$PROJECT_ROOT/acme.json" 2>/dev/null || stat -f "%OLp" "$PROJECT_ROOT/acme.json" 2>/dev/null)
    if [[ "$PERMS" == "600" ]]; then
        log_success "acme.json tiene permisos correctos (600)"
    else
        log_warning "acme.json tiene permisos $PERMS (debería ser 600)"
    fi
else
    log_info "acme.json no existe (se creará al solicitar certificados)"
fi

echo ""

# ==============================================================================
# 5. Variables de Entorno Seguras
# ==============================================================================
echo -e "${BLUE}━━━ 5. Gestión de Credenciales ━━━${NC}"

# Verificar que no hay credenciales por defecto en docker-compose
INSECURE_FILES=0
for compose_file in docker-compose.core.yaml docker-compose.auth.yaml docker-compose.observability.yaml; do
    if [[ -f "$compose_file" ]]; then
        if grep -E '\$\{[A-Z_]+:-[^}]+\}' "$compose_file" | grep -qi "password\|secret" 2>/dev/null; then
            log_error "$compose_file: Contiene credenciales por defecto"
            ((INSECURE_FILES+=1))
        fi
    fi
done

if [[ $INSECURE_FILES -eq 0 ]]; then
    log_success "No hay credenciales por defecto en archivos compose"
fi

# Verificar que no hay credenciales inline en Traefik dynamic.yaml
if [[ -f "configs/traefik/dynamic.yaml" ]]; then
    if grep -q "users:" "configs/traefik/dynamic.yaml" 2>/dev/null && grep -q '\$apr1\$' "configs/traefik/dynamic.yaml" 2>/dev/null; then
        log_error "dynamic.yaml contiene credenciales BasicAuth inline"
    else
        log_success "dynamic.yaml usa usersFile (credenciales externas)"
    fi
fi

# Verificar permisos de .env
if [[ -f ".env" ]]; then
    PERMS=$(stat -c "%a" ".env" 2>/dev/null || stat -f "%OLp" ".env" 2>/dev/null || echo "unknown")
    if [[ "$PERMS" == "600" || "$PERMS" == "640" ]]; then
        log_success ".env tiene permisos restrictivos ($PERMS)"
    elif [[ "$PERMS" == "unknown" ]]; then
        log_info "No se pudieron verificar permisos de .env (Windows)"
    else
        log_warning ".env tiene permisos $PERMS (recomendado: 600)"
    fi
fi

# Verificar que .env no está en git
if git ls-files --error-unmatch .env &>/dev/null; then
    log_error ".env está siendo rastreado por Git!"
else
    log_success ".env no está versionado en Git"
fi

# Verificar archivo .htpasswd para BasicAuth
HTPASSWD_FILE="$PROJECT_ROOT/configs/traefik/certs/.htpasswd"
if [[ -f "$HTPASSWD_FILE" ]]; then
    PERMS=$(stat -c "%a" "$HTPASSWD_FILE" 2>/dev/null || stat -f "%OLp" "$HTPASSWD_FILE" 2>/dev/null || echo "unknown")
    if [[ "$PERMS" == "600" || "$PERMS" == "640" ]]; then
        log_success ".htpasswd tiene permisos restrictivos ($PERMS)"
    elif [[ "$PERMS" == "unknown" ]]; then
        log_info "No se pudieron verificar permisos de .htpasswd (Windows)"
    else
        log_warning ".htpasswd tiene permisos $PERMS (recomendado: 600)"
    fi
    
    # Verificar que no está en git
    if git ls-files --error-unmatch "$HTPASSWD_FILE" &>/dev/null; then
        log_error ".htpasswd está siendo rastreado por Git!"
    else
        log_success ".htpasswd no está versionado en Git"
    fi
else
    log_error ".htpasswd no existe. Ejecutar: ./scripts/setup-env.sh"
fi

echo ""

# ==============================================================================
# Resumen
# ==============================================================================
print_summary "RESUMEN DE SEGURIDAD"
result=$?
if [[ $ERRORS -gt 0 ]]; then
    echo -e "${RED}  NO exponer a internet hasta resolver errores${NC}"
elif [[ $WARNINGS -gt 0 ]]; then
    echo -e "${YELLOW}  Revisar advertencias antes de exponer a internet${NC}"
fi
echo ""
exit $result
