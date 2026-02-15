#!/bin/bash
# ==============================================================================
# Arquisoft - Script de Validación de Ambiente de Desarrollo
# ==============================================================================
# Valida todos los criterios de aceptación de HT-001:
# - Escenario 1: Servicios core levantados con healthchecks
# - Escenario 2: Conectividad a consolas de administración
# - Escenario 3: Esquemas PostgreSQL creados
# - Escenario 4: Persistencia de datos (opcional con --persistence)
#
# Uso: ./scripts/validate-dev.sh [--persistence]
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_ROOT"

# Cargar funciones compartidas
source "$SCRIPT_DIR/lib/common.sh"

echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║      Arquisoft - Validación de Ambiente de Desarrollo        ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# ==============================================================================
# Prerrequisitos
# ==============================================================================
echo -e "${BLUE}━━━ Prerrequisitos ━━━${NC}"

# Verificar .env
if [[ -f ".env" ]]; then
    log_success "Archivo .env existe"
    # Cargar variables de forma segura: solo líneas KEY=VALUE, ignorar comentarios y líneas vacías
    if grep -qE '^[A-Za-z_][A-Za-z0-9_]*=' ".env"; then
        set -a
        eval "$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | sed 's/#.*//')"
        set +a
    else
        log_error "Archivo .env tiene formato inválido"
        exit 1
    fi
else
    log_error "Archivo .env no encontrado. Ejecutar: ./scripts/setup-env.sh"
    exit 1
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
# Escenario 1: Servicios Core con Healthchecks
# ==============================================================================
echo -e "${BLUE}━━━ Escenario 1: Servicios Core con Healthchecks ━━━${NC}"

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

# Traefik (puede no tener healthcheck)
if docker ps --format '{{.Names}}' | grep -q "arquisoft-traefik"; then
    log_success "arquisoft-traefik: running"
else
    log_warning "arquisoft-traefik: not running (optional)"
fi

echo ""

# ==============================================================================
# Escenario 2: Conectividad a Consolas
# ==============================================================================
echo -e "${BLUE}━━━ Escenario 2: Conectividad a Consolas ━━━${NC}"

check_http() {
    local name=$1
    local url=$2
    local expected_codes=${3:-"200 204 302 401"}
    
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null || echo "000")
    
    if [[ " $expected_codes " =~ " $http_code " ]]; then
        log_success "$name: HTTP $http_code"
    elif [[ "$http_code" == "000" ]]; then
        log_error "$name: Unreachable"
    else
        log_warning "$name: HTTP $http_code (expected: $expected_codes)"
    fi
}

check_http "RabbitMQ Management" "http://localhost:15672" "200 401"
check_http "MinIO Console" "http://localhost:9001" "200 302 403"
check_http "Keycloak Admin" "http://localhost:8080" "200 302 303"
check_http "Grafana" "http://localhost:3000" "200 302"
check_http "Prometheus" "http://localhost:9090/-/healthy" "200"

echo ""

# ==============================================================================
# Escenario 3: Esquemas PostgreSQL
# ==============================================================================
echo -e "${BLUE}━━━ Escenario 3: Esquemas PostgreSQL ━━━${NC}"

# Esquemas esperados: 10 bounded contexts + keycloak (schema técnico de Keycloak)
# AC dice "10 esquemas de bounded contexts" — keycloak no es un BC sino schema interno del IdP
EXPECTED_BC_SCHEMAS=(
    "usuarios"
    "fichas_perfil"
    "proyectos_grado"
    "artefactos"
    "evaluaciones"
    "mapa_ruta"
    "repositorio_artefactos"
    "solicitudes"
    "biblioteca"
    "entregables"
)

EXPECTED_TECHNICAL_SCHEMAS=(
    "keycloak"
)

# Verificar conexión a PostgreSQL
if docker exec arquisoft-postgres pg_isready -U "${POSTGRES_USER:-arquisoft}" &>/dev/null; then
    log_success "PostgreSQL acepta conexiones"
    
    # Obtener schemas existentes
    EXISTING_SCHEMAS=$(docker exec arquisoft-postgres psql -U "${POSTGRES_USER:-arquisoft}" -d "${POSTGRES_DB:-arquisoft}" -t -c "SELECT schema_name FROM information_schema.schemata WHERE schema_name NOT IN ('pg_catalog', 'information_schema', 'pg_toast', 'public');" 2>/dev/null | tr -d ' ')
    
    # Verificar schemas de bounded contexts (10 requeridos por AC)
    BC_COUNT=0
    for schema in "${EXPECTED_BC_SCHEMAS[@]}"; do
        if echo "$EXISTING_SCHEMAS" | grep -q "^${schema}$"; then
            log_success "Schema BC '$schema' existe"
            ((BC_COUNT+=1))
        else
            log_error "Schema BC '$schema' NO existe"
        fi
    done
    log_info "Schemas de bounded context verificados: $BC_COUNT/10"
    
    # Verificar schemas técnicos (informativos)
    for schema in "${EXPECTED_TECHNICAL_SCHEMAS[@]}"; do
        if echo "$EXISTING_SCHEMAS" | grep -q "^${schema}$"; then
            log_success "Schema técnico '$schema' existe"
        else
            log_warning "Schema técnico '$schema' NO existe (se crea cuando Keycloak inicia)"
        fi
    done
    
    # Verificar tabla audit_log
    AUDIT_EXISTS=$(docker exec arquisoft-postgres psql -U "${POSTGRES_USER:-arquisoft}" -d "${POSTGRES_DB:-arquisoft}" -t -c "SELECT EXISTS (SELECT FROM pg_tables WHERE schemaname = 'public' AND tablename = 'audit_log');" 2>/dev/null | tr -d ' ')
    
    if [[ "$AUDIT_EXISTS" == "t" ]]; then
        log_success "Tabla 'audit_log' existe"
    else
        log_error "Tabla 'audit_log' NO existe"
    fi
else
    log_error "No se puede conectar a PostgreSQL"
fi

echo ""

# ==============================================================================
# Escenario 4: Persistencia (opcional)
# ==============================================================================
if [[ "$1" == "--persistence" ]]; then
    echo -e "${BLUE}━━━ Escenario 4: Test de Persistencia ━━━${NC}"
    
    log_info "Creando datos de prueba..."
    
    # Insertar registro de prueba en audit_log
    TEST_ID=$(docker exec arquisoft-postgres psql -U "${POSTGRES_USER:-arquisoft}" -d "${POSTGRES_DB:-arquisoft}" -t -c "INSERT INTO audit_log (schema_name, table_name, operation) VALUES ('test', 'persistence_test', 'INSERT') RETURNING id;" 2>/dev/null | tr -d ' ')
    
    if [[ -n "$TEST_ID" ]]; then
        # Validar que TEST_ID es numérico para prevenir inyección SQL
        if [[ ! "$TEST_ID" =~ ^[0-9]+$ ]]; then
            log_error "TEST_ID no es numérico: $TEST_ID"
            exit 1
        fi
        log_success "Registro de prueba creado: $TEST_ID"
        
        log_info "Reiniciando contenedores..."
        docker compose down
        sleep 3
        docker compose up -d
        
        log_info "Esperando que los servicios estén listos..."
        sleep 30
        
        # Verificar que el registro persiste
        RECORD_EXISTS=$(docker exec arquisoft-postgres psql -U "${POSTGRES_USER:-arquisoft}" -d "${POSTGRES_DB:-arquisoft}" -t -c "SELECT EXISTS (SELECT FROM audit_log WHERE id = '$TEST_ID');" 2>/dev/null | tr -d ' ')
        
        if [[ "$RECORD_EXISTS" == "t" ]]; then
            log_success "Datos persistidos correctamente después del reinicio"
            
            # Limpiar registro de prueba
            docker exec arquisoft-postgres psql -U "${POSTGRES_USER:-arquisoft}" -d "${POSTGRES_DB:-arquisoft}" -c "DELETE FROM audit_log WHERE id = '$TEST_ID';" &>/dev/null
        else
            log_error "Los datos NO persistieron después del reinicio"
        fi
    else
        log_error "No se pudo crear registro de prueba"
    fi
    
    echo ""
fi

# ==============================================================================
# Resumen
# ==============================================================================
print_summary "RESUMEN"
exit $?
