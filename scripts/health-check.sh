#!/bin/bash
# ============================================
# Arquisoft Infrastructure - Health Check Script
# ============================================
# Uso: ./health-check.sh
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Arquisoft Infrastructure Health Check${NC}"
echo -e "${BLUE}============================================${NC}"
echo ""

# Track overall status
OVERALL_STATUS=0

# Function to check service health
check_service() {
    local name=$1
    local url=$2
    local expected=$3
    
    printf "%-20s" "$name:"
    
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 "$url" 2>/dev/null) || HTTP_CODE="000"
    
    if [ "$HTTP_CODE" = "$expected" ] || [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "204" ]; then
        echo -e "${GREEN}✓ Healthy (HTTP $HTTP_CODE)${NC}"
    elif [ "$HTTP_CODE" = "000" ]; then
        echo -e "${RED}✗ Unreachable${NC}"
        OVERALL_STATUS=1
    else
        echo -e "${YELLOW}⚠ Unexpected (HTTP $HTTP_CODE)${NC}"
        OVERALL_STATUS=1
    fi
}

# Function to check TCP service
check_tcp() {
    local name=$1
    local host=$2
    local port=$3
    
    printf "%-20s" "$name:"
    
    if (echo > /dev/tcp/$host/$port) 2>/dev/null; then
        echo -e "${GREEN}✓ Listening on port $port${NC}"
    elif nc -z -w5 "$host" "$port" 2>/dev/null; then
        echo -e "${GREEN}✓ Listening on port $port${NC}"
    else
        echo -e "${RED}✗ Port $port not accessible${NC}"
        OVERALL_STATUS=1
    fi
}

echo -e "${BLUE}Checking Core Services...${NC}"
echo "----------------------------------------"
check_tcp "PostgreSQL" "localhost" 5432
check_tcp "RabbitMQ (AMQP)" "localhost" 5672
check_service "RabbitMQ (Mgmt)" "http://localhost:15672/api/overview" "200"
check_tcp "MinIO (API)" "localhost" 9000
check_service "MinIO (Console)" "http://localhost:9001" "200"

echo ""
echo -e "${BLUE}Checking Auth Services...${NC}"
echo "----------------------------------------"
check_service "Keycloak" "http://localhost:8080/realms/master" "200"

echo ""
echo -e "${BLUE}Checking Observability Stack...${NC}"
echo "----------------------------------------"
check_service "Prometheus" "http://localhost:9090/-/healthy" "200"
check_service "Loki" "http://localhost:3100/ready" "200"
check_service "Grafana" "http://localhost:3000/api/health" "200"

echo ""
echo -e "${BLUE}Checking Proxy...${NC}"
echo "----------------------------------------"
check_service "Traefik" "http://localhost:8081/ping" "200"

echo ""
echo -e "${BLUE}Checking Application (if running)...${NC}"
echo "----------------------------------------"
check_service "Backend Health" "http://localhost:8080/actuator/health" "200"

echo ""
echo "============================================"

# Docker container status
echo -e "${BLUE}Container Status:${NC}"
echo "----------------------------------------"
docker compose -f docker-compose.yaml \
    -f docker-compose.core.yaml \
    -f docker-compose.auth.yaml \
    -f docker-compose.observability.yaml \
    -f docker-compose.proxy.yaml \
    ps --format "table {{.Name}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null || echo "Could not get container status"

echo ""
echo "============================================"

# Resource usage
echo -e "${BLUE}Resource Usage:${NC}"
echo "----------------------------------------"
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>/dev/null | head -15 || echo "Could not get resource usage"

echo ""
echo "============================================"

if [ $OVERALL_STATUS -eq 0 ]; then
    echo -e "${GREEN}All services are healthy!${NC}"
else
    echo -e "${YELLOW}Some services need attention.${NC}"
fi

exit $OVERALL_STATUS
