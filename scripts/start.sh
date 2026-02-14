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
    echo -e "${YELLOW}⚠ .env file not found. Creating from .env.example...${NC}"
    if [ -f .env.example ]; then
        cp .env.example .env
        echo -e "${GREEN}✓ .env created. Please review and update values.${NC}"
    else
        echo -e "${RED}✗ .env.example not found. Cannot continue.${NC}"
        exit 1
    fi
fi

# Source environment variables
source .env

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

# Pull latest images
echo -e "${BLUE}Pulling latest images...${NC}"
docker compose $COMPOSE_FILES pull

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
    echo -e "  ${YELLOW}App:${NC}            https://${DOMAIN:-arquisoft.uco.edu.co}"
    echo -e "  ${YELLOW}API:${NC}            https://api.${DOMAIN:-arquisoft.uco.edu.co}"
    echo -e "  ${YELLOW}Auth:${NC}           https://auth.${DOMAIN:-arquisoft.uco.edu.co}"
    echo -e "  ${YELLOW}Grafana:${NC}        https://grafana.${DOMAIN:-arquisoft.uco.edu.co}"
    echo -e "  ${YELLOW}Dashboard:${NC}      https://traefik.${DOMAIN:-arquisoft.uco.edu.co}"
else
    echo -e "Access URLs (Development):"
    echo -e "  ${YELLOW}PostgreSQL:${NC}     localhost:5432"
    echo -e "  ${YELLOW}RabbitMQ:${NC}       http://localhost:15672 (admin/admin)"
    echo -e "  ${YELLOW}MinIO Console:${NC}  http://localhost:9001 (minioadmin/minioadmin)"
    echo -e "  ${YELLOW}Keycloak:${NC}       http://localhost:8180/admin (admin/admin)"
    echo -e "  ${YELLOW}Grafana:${NC}        http://localhost:3001 (admin/admin)"
    echo -e "  ${YELLOW}Prometheus:${NC}     http://localhost:9090"
    echo ""
    echo -e "With Traefik proxy:"
    echo -e "  ${YELLOW}App:${NC}            http://arquisoft.localhost"
    echo -e "  ${YELLOW}Auth:${NC}           http://auth.arquisoft.localhost"
    echo -e "  ${YELLOW}Grafana:${NC}        http://grafana.arquisoft.localhost"
fi
echo ""
