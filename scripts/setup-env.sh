#!/bin/bash
# ==============================================================================
# Arquisoft - Script de Configuración de Variables de Entorno
# ==============================================================================
# Genera archivos de configuración necesarios para la infraestructura
#
# Principios:
#   - Idempotente: Puede ejecutarse múltiples veces sin efectos secundarios
#   - No destructivo: Nunca sobrescribe archivos existentes
#   - Modular: Delega a módulos especializados
#
# Uso:
#   ./scripts/setup-env.sh              # Modo desarrollo (default)
#   ./scripts/setup-env.sh dev          # Modo desarrollo explícito
#   ./scripts/setup-env.sh prod         # Modo producción
#
# Variables de entorno opcionales:
#   DOMAIN=unyai.duckdns.org ACME_EMAIL=admin@example.com ./scripts/setup-env.sh prod
#
# Para regenerar archivos:
#   rm .env && ./scripts/setup-env.sh prod          # Regenerar .env
#   rm configs/prometheus/web.yml && ...            # Regenerar web.yml
#   rm configs/traefik/certs/.htpasswd && ...       # Regenerar .htpasswd
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Cargar módulos
source "$SCRIPT_DIR/lib/common.sh"
source "$SCRIPT_DIR/lib/password-generator.sh"
source "$SCRIPT_DIR/lib/env-config.sh"
source "$SCRIPT_DIR/lib/prometheus-config.sh"
source "$SCRIPT_DIR/lib/traefik-config.sh"

ENV_EXAMPLE="$PROJECT_ROOT/.env.example"
ENV_FILE="$PROJECT_ROOT/.env"

# Parsear entorno
ENVIRONMENT="${1:-dev}"
if [[ "$ENVIRONMENT" != "dev" && "$ENVIRONMENT" != "prod" ]]; then
    echo -e "Uso: $(basename "$0") [dev|prod]"
    echo -e "  dev   Modo desarrollo (default)"
    echo -e "  prod  Modo producción"
    exit 1
fi

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Arquisoft - Configuración de Variables de Entorno      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo -e "${YELLOW}Entorno:${NC} $ENVIRONMENT"
echo -e "${YELLOW}Modo:${NC} Idempotente (mantiene archivos existentes)"
echo ""

# ==============================================================================
# 1. Verificar prerequisitos
# ==============================================================================
if [[ ! -f "$ENV_EXAMPLE" ]]; then
    log_error "No se encontró $ENV_EXAMPLE"
    exit 1
fi

# ==============================================================================
# 2. Generar .env si no existe
# ==============================================================================
if [[ -f "$ENV_FILE" ]]; then
    log_success "Archivo .env ya existe, se mantiene"
    echo ""
else
    generate_env_from_template "$ENV_EXAMPLE" "$ENV_FILE" "$PROJECT_ROOT"
fi

# ==============================================================================
# 3. Configurar variables específicas del entorno
# ==============================================================================
if [[ "$ENVIRONMENT" == "prod" ]]; then
    DEPLOY_MODE="producción"
    
    echo -e "${YELLOW}─── Configuración de Producción ───${NC}"
    echo ""
    
    # ----- DOMAIN -----
    DOMAIN_VALUE=$(get_env_var "$ENV_FILE" "DOMAIN")
    
    if [[ -n "$DOMAIN" ]]; then
        # Variable de entorno tiene prioridad
        DOMAIN_VALUE="$DOMAIN"
        DOMAIN_ESC=$(escape_sed "$DOMAIN_VALUE")
        set_env_var "$ENV_FILE" "DOMAIN" "$DOMAIN_ESC"
        log_success "DOMAIN configurado desde variable de entorno: $DOMAIN_VALUE"
    elif [[ -z "$DOMAIN_VALUE" ]] || [[ "$DOMAIN_VALUE" == "arquisoft.localhost" ]] || [[ "$DOMAIN_VALUE" == "CHANGE_ME" ]]; then
        log_error "DOMAIN no configurado en .env"
        log_error "Configura DOMAIN en .env o pasa como variable: DOMAIN=tu-dominio.com"
        exit 1
    else
        log_success "Usando DOMAIN desde .env: $DOMAIN_VALUE"
    fi
    
    # ----- ACME_EMAIL -----
    ACME_EMAIL_VALUE=$(get_env_var "$ENV_FILE" "ACME_EMAIL")
    
    if [[ -n "$ACME_EMAIL" ]]; then
        # Variable de entorno tiene prioridad
        ACME_EMAIL_VALUE="$ACME_EMAIL"
        
        # Validar formato email
        if [[ ! "$ACME_EMAIL_VALUE" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
            log_error "ACME_EMAIL no tiene formato válido: $ACME_EMAIL_VALUE"
            exit 1
        fi
        
        ACME_ESC=$(escape_sed "$ACME_EMAIL_VALUE")
        uncomment_env_var "$ENV_FILE" "ACME_EMAIL" "$ACME_ESC"
        log_success "ACME_EMAIL configurado desde variable de entorno: $ACME_EMAIL_VALUE"
    elif [[ -z "$ACME_EMAIL_VALUE" ]]; then
        log_error "ACME_EMAIL no configurado en .env"
        log_error "Configura ACME_EMAIL en .env o pasa como variable: ACME_EMAIL=tu@email.com"
        exit 1
    else
        log_success "Usando ACME_EMAIL desde .env: $ACME_EMAIL_VALUE"
    fi
    
    echo ""
    
    # ----- Generar Prometheus web.yml -----
    generate_prometheus_web_config "$PROJECT_ROOT" "$ENV_FILE"
    
    CONFIGURED_DOMAIN="$DOMAIN_VALUE"
    CONFIGURED_ACME_EMAIL="$ACME_EMAIL_VALUE"
else
    DEPLOY_MODE="desarrollo"
    CONFIGURED_DOMAIN=$(get_env_var "$ENV_FILE" "DOMAIN")
fi

# ==============================================================================
# 4. Generar archivos de configuración adicionales
# ==============================================================================
generate_traefik_htpasswd "$PROJECT_ROOT"

# ==============================================================================
# 5. Resumen
# ==============================================================================
echo -e "${GREEN}✓ Configuración completada${NC}"
echo ""
log_warning "Archivos existentes se mantuvieron sin cambios"
log_warning "Para regenerar: elimina el archivo y ejecuta nuevamente este script"
echo ""

echo -e "${BLUE}─── Resumen ───${NC}"
if [[ "$DEPLOY_MODE" == "producción" ]]; then
    echo -e "  Modo:       ${YELLOW}PRODUCCIÓN${NC}"
    echo -e "  Dominio:    ${YELLOW}$CONFIGURED_DOMAIN${NC}"
    echo -e "  ACME Email: ${YELLOW}$CONFIGURED_ACME_EMAIL${NC}"
    echo -e "  SSL:        ${GREEN}Let's Encrypt (automático)${NC}"
    echo ""
    echo -e "${GREEN}Próximo paso:${NC} ./scripts/start.sh prod"
else
    echo -e "  Modo:       ${GREEN}DESARROLLO${NC}"
    echo -e "  Dominio:    ${GREEN}$CONFIGURED_DOMAIN${NC}"
    echo -e "  SSL:        ${YELLOW}N/A (desarrollo local)${NC}"
    echo ""
    echo -e "${GREEN}Próximo paso:${NC} ./scripts/start.sh dev"
fi
echo ""
echo -e "${BLUE}Credenciales completas en:${NC} .env (permisos 600)"
