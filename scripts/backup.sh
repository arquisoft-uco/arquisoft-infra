#!/bin/bash
# ============================================
# Arquisoft Infrastructure - Backup Script
# ============================================
# Uso: ./backup.sh [component]
# Componentes:
#   all         Backup completo (default)
#   postgres    Solo PostgreSQL
#   minio       Solo MinIO
#   keycloak    Solo Keycloak
# ============================================

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

BACKUP_DIR="${BACKUP_DIR:-./backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
COMPONENT="${1:-all}"

# Load environment safely
if [ -f .env ]; then
    set -a
    eval "$(grep -E '^[A-Za-z_][A-Za-z0-9_]*=' .env | sed 's/#.*//')"
    set +a
fi

# Create backup directory
mkdir -p "$BACKUP_DIR"

echo -e "${BLUE}============================================${NC}"
echo -e "${BLUE}   Arquisoft Infrastructure Backup${NC}"
echo -e "${BLUE}============================================${NC}"
echo -e "${YELLOW}Timestamp:${NC} $TIMESTAMP"
echo -e "${YELLOW}Component:${NC} $COMPONENT"
echo -e "${YELLOW}Backup Dir:${NC} $BACKUP_DIR"
echo ""

# Function to backup PostgreSQL
backup_postgres() {
    echo -e "${BLUE}Backing up PostgreSQL...${NC}"
    
    POSTGRES_BACKUP="$BACKUP_DIR/postgres_${TIMESTAMP}.sql.gz"
    
    docker compose -f docker-compose.yaml -f docker-compose.core.yaml exec -T postgres \
        pg_dumpall -U "${POSTGRES_USER:-arquisoft}" | gzip > "$POSTGRES_BACKUP"
    
    if [ -f "$POSTGRES_BACKUP" ]; then
        SIZE=$(du -h "$POSTGRES_BACKUP" | cut -f1)
        echo -e "${GREEN}✓ PostgreSQL backup complete: $POSTGRES_BACKUP ($SIZE)${NC}"
    else
        echo -e "${RED}✗ PostgreSQL backup failed${NC}"
        return 1
    fi
}

# Function to backup MinIO
backup_minio() {
    echo -e "${BLUE}Backing up MinIO...${NC}"
    
    MINIO_BACKUP="$BACKUP_DIR/minio_${TIMESTAMP}.tar.gz"
    
    # Using docker volume to backup
    docker run --rm \
        -v arquisoft_minio-data:/data \
        -v "$(pwd)/$BACKUP_DIR:/backup" \
        alpine tar czf "/backup/minio_${TIMESTAMP}.tar.gz" -C /data .
    
    if [ -f "$MINIO_BACKUP" ]; then
        SIZE=$(du -h "$MINIO_BACKUP" | cut -f1)
        echo -e "${GREEN}✓ MinIO backup complete: $MINIO_BACKUP ($SIZE)${NC}"
    else
        echo -e "${RED}✗ MinIO backup failed${NC}"
        return 1
    fi
}

# Function to backup Keycloak (export realm)
backup_keycloak() {
    echo -e "${BLUE}Backing up Keycloak realm...${NC}"
    
    KEYCLOAK_BACKUP="$BACKUP_DIR/keycloak_realm_${TIMESTAMP}.json"
    
    # Export realm using Keycloak CLI
    docker compose -f docker-compose.yaml -f docker-compose.auth.yaml exec -T keycloak \
        /opt/keycloak/bin/kc.sh export --dir /tmp/export --realm arquisoft 2>/dev/null || true
    
    docker compose -f docker-compose.yaml -f docker-compose.auth.yaml \
        cp keycloak:/tmp/export/arquisoft-realm.json "$KEYCLOAK_BACKUP" 2>/dev/null || {
            echo -e "${YELLOW}⚠ Keycloak realm export not available (realm may not exist yet)${NC}"
            return 0
        }
    
    if [ -f "$KEYCLOAK_BACKUP" ]; then
        SIZE=$(du -h "$KEYCLOAK_BACKUP" | cut -f1)
        echo -e "${GREEN}✓ Keycloak backup complete: $KEYCLOAK_BACKUP ($SIZE)${NC}"
    fi
}

# Execute backup based on component
case $COMPONENT in
    "postgres")
        backup_postgres
        ;;
    "minio")
        backup_minio
        ;;
    "keycloak")
        backup_keycloak
        ;;
    "all"|*)
        backup_postgres
        echo ""
        backup_minio
        echo ""
        backup_keycloak
        ;;
esac

# Cleanup old backups (keep last 7 days)
echo ""
echo -e "${BLUE}Cleaning up old backups (keeping last 7 days)...${NC}"
find "$BACKUP_DIR" -type f -mtime +7 -delete 2>/dev/null || true
echo -e "${GREEN}✓ Cleanup complete${NC}"

# Summary
echo ""
echo -e "${GREEN}============================================${NC}"
echo -e "${GREEN}   Backup Complete!${NC}"
echo -e "${GREEN}============================================${NC}"
echo ""
echo -e "Backups stored in: ${YELLOW}$BACKUP_DIR${NC}"
ls -lh "$BACKUP_DIR"/*_${TIMESTAMP}* 2>/dev/null || echo "No files created"
