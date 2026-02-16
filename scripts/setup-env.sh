#!/bin/bash
# ==============================================================================
# Arquisoft - Script de configuración de variables de entorno
# ==============================================================================
# Genera el archivo .env a partir de .env.example con contraseñas seguras
#
# Uso: ./scripts/setup-env.sh
# ==============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Cargar funciones compartidas
source "$SCRIPT_DIR/lib/common.sh"

ENV_EXAMPLE="$PROJECT_ROOT/.env.example"
ENV_FILE="$PROJECT_ROOT/.env"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║       Arquisoft - Configuración de Variables de Entorno      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Verificar que existe .env.example
if [[ ! -f "$ENV_EXAMPLE" ]]; then
    echo -e "${RED}✗ Error: No se encontró $ENV_EXAMPLE${NC}"
    exit 1
fi

# Verificar si ya existe .env
if [[ -f "$ENV_FILE" ]]; then
    echo -e "${YELLOW}⚠ Ya existe un archivo .env${NC}"
    read -p "¿Deseas sobrescribirlo? (s/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Ss]$ ]]; then
        echo -e "${GREEN}✓ Operación cancelada. El archivo .env existente se mantiene.${NC}"
        exit 0
    fi
    echo ""
fi

# Función para generar contraseña segura
generate_password() {
    if command -v openssl &> /dev/null; then
        openssl rand -base64 24 | tr -d '/+=' | head -c 24
    else
        # Fallback para sistemas sin openssl
        tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 24 | head -n 1
    fi
}

# Función para enmascarar credenciales (muestra solo primeros 4 y últimos 4 caracteres)
mask_credential() {
    local cred=$1
    local len=${#cred}
    if [[ $len -le 8 ]]; then
        echo "********"
    else
        echo "${cred:0:4}$(printf '*%.0s' $(seq 1 $((len - 8))))${cred: -4}"
    fi
}

# Función para reemplazar placeholders en .env (compatible macOS y Linux)
replace_in_env() {
    local pattern=$1
    local replacement=$2
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/$pattern/$replacement/" "$ENV_FILE"
    else
        sed -i "s/$pattern/$replacement/" "$ENV_FILE"
    fi
}

# Generar hash APR1 MD5 usando openssl (compatible sin htpasswd)
generate_apr1_hash() {
    local password=$1
    local salt=$(openssl rand -base64 8 | tr -dc 'a-zA-Z0-9' | head -c 8)
    openssl passwd -apr1 -salt "$salt" "$password"
}

echo -e "${BLUE}Generando archivo .env con credenciales seguras...${NC}"
echo ""

# Copiar .env.example a .env
cp "$ENV_EXAMPLE" "$ENV_FILE"

# Generar contraseñas seguras para cada servicio
POSTGRES_PWD=$(generate_password)
RABBITMQ_PWD=$(generate_password)
MINIO_PWD=$(generate_password)
KEYCLOAK_PWD=$(generate_password)
KC_REALM_ADMIN_PWD=$(generate_password)
GRAFANA_PWD=$(generate_password)

# Reemplazar placeholders con contraseñas generadas (escapando caracteres especiales)
POSTGRES_PWD_ESC=$(escape_sed "$POSTGRES_PWD")
RABBITMQ_PWD_ESC=$(escape_sed "$RABBITMQ_PWD")
MINIO_PWD_ESC=$(escape_sed "$MINIO_PWD")
KEYCLOAK_PWD_ESC=$(escape_sed "$KEYCLOAK_PWD")
KC_REALM_ADMIN_PWD_ESC=$(escape_sed "$KC_REALM_ADMIN_PWD")
GRAFANA_PWD_ESC=$(escape_sed "$GRAFANA_PWD")

replace_in_env "POSTGRES_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "POSTGRES_PASSWORD=$POSTGRES_PWD_ESC"
replace_in_env "RABBITMQ_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "RABBITMQ_PASSWORD=$RABBITMQ_PWD_ESC"
replace_in_env "MINIO_ROOT_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "MINIO_ROOT_PASSWORD=$MINIO_PWD_ESC"
replace_in_env "KEYCLOAK_ADMIN_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "KEYCLOAK_ADMIN_PASSWORD=$KEYCLOAK_PWD_ESC"
replace_in_env "KC_REALM_ADMIN_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "KC_REALM_ADMIN_PASSWORD=$KC_REALM_ADMIN_PWD_ESC"
replace_in_env "GRAFANA_ADMIN_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "GRAFANA_ADMIN_PASSWORD=$GRAFANA_PWD_ESC"

# Establecer permisos restrictivos
chmod 600 "$ENV_FILE"

# ==============================================================================
# Generar credenciales BasicAuth para Traefik
# ==============================================================================
HTPASSWD_FILE="$PROJECT_ROOT/configs/traefik/certs/.htpasswd"
HTPASSWD_DIR="$(dirname "$HTPASSWD_FILE")"

echo -e "${BLUE}Generando credenciales BasicAuth para Traefik...${NC}"

# Crear directorio si no existe
mkdir -p "$HTPASSWD_DIR"

# Generar contraseña para BasicAuth
BASICAUTH_USER="admin"
BASICAUTH_PWD=$(generate_password)

BASICAUTH_HASH=$(generate_apr1_hash "$BASICAUTH_PWD")
echo "${BASICAUTH_USER}:${BASICAUTH_HASH}" > "$HTPASSWD_FILE"
chmod 600 "$HTPASSWD_FILE"

echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║              ✓ Archivo .env generado exitosamente            ║${NC}"
echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${BLUE}Credenciales generadas (enmascaradas por seguridad):${NC}"
echo -e "  PostgreSQL:      ${YELLOW}$(mask_credential "$POSTGRES_PWD")${NC}"
echo -e "  RabbitMQ:        ${YELLOW}$(mask_credential "$RABBITMQ_PWD")${NC}"
echo -e "  MinIO:           ${YELLOW}$(mask_credential "$MINIO_PWD")${NC}"
echo -e "  Keycloak Master: ${YELLOW}$(mask_credential "$KEYCLOAK_PWD")${NC}"
echo -e "  Keycloak Realm:  ${YELLOW}$(mask_credential "$KC_REALM_ADMIN_PWD")${NC} (admin@uco.edu.co - temporal)"
echo -e "  Grafana:         ${YELLOW}$(mask_credential "$GRAFANA_PWD")${NC}"
echo -e "  BasicAuth:       ${YELLOW}$BASICAUTH_USER / $(mask_credential "$BASICAUTH_PWD")${NC} (Traefik admin panels)"
echo ""
echo -e "${YELLOW}⚠ IMPORTANTE: Las credenciales completas están en el archivo .env${NC}"
echo -e "${YELLOW}  Consultar: cat .env (archivo con permisos 600)${NC}"
echo -e "${YELLOW}  Los archivos .env y .htpasswd tienen permisos restringidos.${NC}"
echo ""
echo -e "${GREEN}Próximo paso: ./scripts/start.sh dev${NC}"
