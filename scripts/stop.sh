#!/bin/bash
# ============================================
# Arquisoft Infrastructure - Stop Script
# ============================================
# Uso: ./stop.sh [options]
# Opciones:
#   --volumes    También elimina volúmenes (¡CUIDADO: elimina datos!)
#   --prune      Limpia imágenes y redes huérfanas
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
cd "$SCRIPT_DIR/.."

REMOVE_VOLUMES=false
PRUNE=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --volumes)
            REMOVE_VOLUMES=true
            shift
            ;;
        --prune)
            PRUNE=true
            shift
            ;;
    esac
done

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Arquisoft Infrastructure Shutdown${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Build compose command with all files
COMPOSE_FILES="-f docker-compose.yaml -f docker-compose.core.yaml -f docker-compose.auth.yaml -f docker-compose.observability.yaml -f docker-compose.proxy.yaml -f docker-compose.dev.yaml"

# Stop services
echo -e "${BLUE}Stopping services...${NC}"
docker compose $COMPOSE_FILES down

# Remove volumes if requested
if [ "$REMOVE_VOLUMES" = true ]; then
    echo ""
    echo -e "${RED}⚠ WARNING: Removing all volumes (data will be lost!)${NC}"
    read -p "Are you sure? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${YELLOW}Removing volumes...${NC}"
        docker compose $COMPOSE_FILES down -v
        echo -e "${GREEN}✓ Volumes removed${NC}"
    else
        echo -e "${BLUE}Volumes preserved${NC}"
    fi
fi

# Prune if requested
if [ "$PRUNE" = true ]; then
    echo ""
    echo -e "${BLUE}Pruning unused resources...${NC}"
    docker system prune -f
    echo -e "${GREEN}✓ Cleanup complete${NC}"
fi

echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Infrastructure Stopped Successfully!${NC}"
echo -e "${GREEN}============================================${NC}"
