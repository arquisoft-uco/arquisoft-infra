#!/bin/bash
# ============================================
# Arquisoft Infrastructure - Start Script
# ============================================
# Uso: ./start.sh [environment] [profile]
# Ejemplos:
#   ./start.sh              # Inicia todo en modo desarrollo
#   ./start.sh dev          # Inicia todo en modo desarrollo
#   ./start.sh prod         # Inicia todo en modo producción
#   ./start.sh dev core     # Inicia solo servicios core (DB, MQ, MinIO)
#   ./start.sh dev all      # Inicia todos los servicios
# ============================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INFRA_DIR="$(dirname "$SCRIPT_DIR")"
cd "$INFRA_DIR"

ENVIRONMENT="${1:-dev}"
PROFILE="${2:-all}"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Arquisoft Infrastructure Startup${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "${YELLOW}Environment:${NC} $ENVIRONMENT"
echo -e "${YELLOW}Profile:${NC} $PROFILE"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${YELLOW}⚠ .env file not found.${NC}"
    if [ -f .env.example ]; then
        echo -e "${RED}✗ Ejecutar primero: bash scripts/setup-env.sh${NC}"
        echo -e "${YELLOW}  O copiar manualmente: cp .env.example .env && editar valores${NC}"
    else
        echo -e "${RED}✗ .env.example not found. Cannot continue.${NC}"
    fi
    exit 1
fi

# Load environment variables safely (avoid arbitrary code execution)
set -a
eval "$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | sed 's/#.*//')"
set +a

# Validate DOMAIN is set
if [ -z "$DOMAIN" ] || [ "$DOMAIN" = "CHANGE_ME" ]; then
    echo -e "${RED}✗ Variable DOMAIN no configurada en .env${NC}"
    echo -e "${YELLOW}  Desarrollo: DOMAIN=arquisoft.localhost${NC}"
    echo -e "${YELLOW}  Producción: DOMAIN=tu-dominio.com${NC}"
    exit 1
fi

# Generate config files from templates using envsubst
echo -e "${BLUE}Generating config from templates (DOMAIN=$DOMAIN)...${NC}"
if command -v envsubst &> /dev/null; then
    # Traefik dev dynamic config
    if [ -f "configs/traefik/dynamic.yaml.template" ]; then
        mkdir -p "configs/traefik/dynamic"
        envsubst '${DOMAIN}' < "configs/traefik/dynamic.yaml.template" > "configs/traefik/dynamic/dynamic.yaml"
        echo -e "${GREEN}✓ configs/traefik/dynamic/dynamic.yaml generado${NC}"
    fi
    # Traefik prod dynamic config
    if [ -f "configs/traefik/dynamic-prod/routing.yaml.template" ]; then
        envsubst '${DOMAIN}' < "configs/traefik/dynamic-prod/routing.yaml.template" > "configs/traefik/dynamic-prod/routing.yaml"
        echo -e "${GREEN}✓ configs/traefik/dynamic-prod/routing.yaml generado${NC}"
    fi
    # Traefik prod static config (ACME email)
    if [ -f "configs/traefik/traefik-prod.yaml.template" ]; then
        envsubst '${ACME_EMAIL}' < "configs/traefik/traefik-prod.yaml.template" > "configs/traefik/traefik-prod.yaml"
        echo -e "${GREEN}✓ configs/traefik/traefik-prod.yaml generado${NC}"
    fi
    # RabbitMQ definitions (user from .env)
    if [ -f "configs/rabbitmq/definitions.json.template" ]; then
        envsubst '${RABBITMQ_USER} ${RABBITMQ_PASSWORD}' < "configs/rabbitmq/definitions.json.template" > "configs/rabbitmq/definitions.json"
        echo -e "${GREEN}✓ configs/rabbitmq/definitions.json generado${NC}"
    fi
    # Keycloak realm (admin seed user from .env)
    if [ -f "configs/keycloak/realm-arquisoft.json.template" ]; then
        envsubst '${KC_REALM_ADMIN_EMAIL} ${KC_REALM_ADMIN_FIRST_NAME} ${KC_REALM_ADMIN_LAST_NAME} ${KC_REALM_ADMIN_PASSWORD}' < "configs/keycloak/realm-arquisoft.json.template" > "configs/keycloak/realm-arquisoft.json"
        echo -e "${GREEN}✓ configs/keycloak/realm-arquisoft.json generado${NC}"
    fi
else
    echo -e "${YELLOW}⚠ envsubst no encontrado. Usando sed como fallback...${NC}"
    if [ -f "configs/traefik/dynamic.yaml.template" ]; then
        mkdir -p "configs/traefik/dynamic"
        sed "s/\${DOMAIN}/$DOMAIN/g" "configs/traefik/dynamic.yaml.template" > "configs/traefik/dynamic/dynamic.yaml"
    fi
    if [ -f "configs/traefik/dynamic-prod/routing.yaml.template" ]; then
        sed "s/\${DOMAIN}/$DOMAIN/g" "configs/traefik/dynamic-prod/routing.yaml.template" > "configs/traefik/dynamic-prod/routing.yaml"
    fi
    if [ -f "configs/traefik/traefik-prod.yaml.template" ]; then
        sed "s/\${ACME_EMAIL}/$ACME_EMAIL/g" "configs/traefik/traefik-prod.yaml.template" > "configs/traefik/traefik-prod.yaml"
    fi
    if [ -f "configs/rabbitmq/definitions.json.template" ]; then
        sed -e "s/\${RABBITMQ_USER}/$RABBITMQ_USER/g" \
            -e "s/\${RABBITMQ_PASSWORD}/$RABBITMQ_PASSWORD/g" \
            "configs/rabbitmq/definitions.json.template" > "configs/rabbitmq/definitions.json"
    fi
    if [ -f "configs/keycloak/realm-arquisoft.json.template" ]; then
        sed -e "s/\${KC_REALM_ADMIN_EMAIL}/$KC_REALM_ADMIN_EMAIL/g" \
            -e "s/\${KC_REALM_ADMIN_FIRST_NAME}/$KC_REALM_ADMIN_FIRST_NAME/g" \
            -e "s/\${KC_REALM_ADMIN_LAST_NAME}/$KC_REALM_ADMIN_LAST_NAME/g" \
            -e "s/\${KC_REALM_ADMIN_PASSWORD}/$KC_REALM_ADMIN_PASSWORD/g" \
            "configs/keycloak/realm-arquisoft.json.template" > "configs/keycloak/realm-arquisoft.json"
    fi
fi
echo ""

# Build compose command based on profile
COMPOSE_FILES="-f docker-compose.yaml"

case $PROFILE in
    "core")
        echo -e "${BLUE}Starting core services only (PostgreSQL, RabbitMQ, MinIO)...${NC}"
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.core.yaml"
        ;;
    "auth")
        echo -e "${BLUE}Starting core + auth services...${NC}"
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.core.yaml -f docker-compose.auth.yaml"
        ;;
    "observability")
        echo -e "${BLUE}Starting observability stack only...${NC}"
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.observability.yaml"
        ;;
    "all"|*)
        echo -e "${BLUE}Starting all services...${NC}"
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.core.yaml -f docker-compose.auth.yaml -f docker-compose.observability.yaml"
        ;;
esac

# Add environment-specific overrides
case $ENVIRONMENT in
    "prod")
        echo -e "${YELLOW}🔒 Production mode: SSL enabled with Let's Encrypt${NC}"
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.proxy-prod.yaml -f docker-compose.prod.yaml"
        ;;
    "dev"|*)
        COMPOSE_FILES="$COMPOSE_FILES -f docker-compose.proxy.yaml -f docker-compose.dev.yaml"
        ;;
esac

echo -e "${YELLOW}Compose files:${NC} $COMPOSE_FILES"
echo ""

# Pull latest images (non-blocking: images are public, pull may fail with credential helper issues)
echo -e "${BLUE}Pulling latest images...${NC}"
if ! docker compose $COMPOSE_FILES pull 2>&1; then
    echo -e "${YELLOW}⚠ Pull falló (posible problema de credential helper). Continuando con imágenes locales/cache...${NC}"
fi

# Start services
echo -e "${BLUE}Starting services...${NC}"
docker compose $COMPOSE_FILES up -d

# Wait for services to be healthy
echo ""
echo -e "${BLUE}Waiting for services to be ready...${NC}"
sleep 5

# Check service health
echo ""
echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Service Status${NC}"
echo -e "${BLUE}============================================${NC}"
docker compose $COMPOSE_FILES ps

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Infrastructure Started Successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""

if [ "$ENVIRONMENT" = "prod" ]; then
    echo -e "🔒 ${GREEN}Production URLs (HTTPS):${NC}"
    echo -e "  ${YELLOW}App:${NC}            https://${DOMAIN}"
    echo -e "  ${YELLOW}API:${NC}            https://api.${DOMAIN}"
    echo -e "  ${YELLOW}Auth:${NC}           https://auth.${DOMAIN}"
    echo -e "  ${YELLOW}Grafana:${NC}        https://grafana.${DOMAIN}"
    echo -e "  ${YELLOW}Dashboard:${NC}      https://traefik.${DOMAIN}"
else
    echo -e "Access URLs (Development):"
    echo -e "  ${YELLOW}PostgreSQL:${NC}     localhost:5432"
    echo -e "  ${YELLOW}RabbitMQ:${NC}       http://localhost:15672 (ver credenciales en .env)"
    echo -e "  ${YELLOW}MinIO Console:${NC}  http://localhost:9001 (ver credenciales en .env)"
    echo -e "  ${YELLOW}Keycloak:${NC}       http://localhost:8080/admin (ver credenciales en .env)"
    echo -e "  ${YELLOW}Grafana:${NC}        http://localhost:3000 (ver credenciales en .env)"
    echo -e "  ${YELLOW}Prometheus:${NC}     http://localhost:9090"
    echo ""
    echo -e "With Traefik proxy (DOMAIN=$DOMAIN):"
    echo -e "  ${YELLOW}App:${NC}            http://${DOMAIN}"
    echo -e "  ${YELLOW}Auth:${NC}           http://auth.${DOMAIN}"
    echo -e "  ${YELLOW}Grafana:${NC}        http://grafana.${DOMAIN}"
fi
echo ""
