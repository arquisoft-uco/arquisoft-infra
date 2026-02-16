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
    log_error "No se encontró $ENV_EXAMPLE"
    exit 1
fi

# Verificar si ya existe .env
if [[ -f "$ENV_FILE" ]]; then
    log_warning "Ya existe un archivo .env"
    read -p "¿Deseas sobrescribirlo? (s/N): " overwrite
    if [[ ! "$overwrite" =~ ^[Ss]$ ]]; then
        log_success "Operación cancelada. El archivo .env existente se mantiene."
        exit 0
    fi
    echo ""
fi

# Función para generar contraseña segura
# Garantiza: ≥1 mayúscula, ≥1 dígito, ≥1 carácter especial (requerido por política Keycloak)
generate_password() {
    local base
    if command -v openssl &> /dev/null; then
        base=$(openssl rand -base64 24 | tr -d '/+=' | head -c 21)
    else
        base=$(tr -dc 'a-zA-Z0-9' < /dev/urandom | fold -w 21 | head -n 1)
    fi
    # Añadir sufijo que garantiza mayúscula + dígito + especial
    echo "${base}A1!"
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

# Generar hash bcrypt para Prometheus web.yml
generate_bcrypt_hash() {
    local password=$1
    if command -v htpasswd &>/dev/null; then
        htpasswd -nbBC 10 "" "$password" | tr -d ':\n'
    else
        # Usar imagen httpd de Docker como fallback
        docker run --rm httpd:2.4-alpine htpasswd -nbBC 10 "" "$password" 2>/dev/null | tr -d ':\n'
    fi
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
# Detectar modo producción (DOMAIN no es *.localhost)
# ==============================================================================
CONFIGURED_DOMAIN=$(grep -E '^DOMAIN=' "$ENV_FILE" | cut -d'=' -f2)

if [[ "$CONFIGURED_DOMAIN" != *".localhost" ]]; then
    DEPLOY_MODE="producción"
    echo -e "${YELLOW}━━━ Modo Producción Detectado (DOMAIN=$CONFIGURED_DOMAIN) ━━━${NC}"
    echo ""

    # Solicitar ACME_EMAIL para Let's Encrypt
    echo -e "${BLUE}Let's Encrypt requiere un email para notificaciones de certificados SSL.${NC}"
    read -p "Ingresa ACME_EMAIL para Let's Encrypt: " ACME_EMAIL_INPUT

    if [[ -z "$ACME_EMAIL_INPUT" ]]; then
        log_error "ACME_EMAIL es obligatorio para producción."
        exit 1
    fi

    # Validar formato email básico
    if [[ ! "$ACME_EMAIL_INPUT" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$ ]]; then
        log_error "ACME_EMAIL no tiene formato de email válido: $ACME_EMAIL_INPUT"
        exit 1
    fi

    # Escapar para uso seguro en sed
    ACME_ESCAPED=$(escape_sed "$ACME_EMAIL_INPUT")

    # Descomentar y establecer ACME_EMAIL en .env
    if grep -q "^# ACME_EMAIL=" "$ENV_FILE"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^# ACME_EMAIL=.*/ACME_EMAIL=$ACME_ESCAPED/" "$ENV_FILE"
        else
            sed -i "s/^# ACME_EMAIL=.*/ACME_EMAIL=$ACME_ESCAPED/" "$ENV_FILE"
        fi
    elif grep -q "^ACME_EMAIL=" "$ENV_FILE"; then
        replace_in_env "^ACME_EMAIL=.*" "ACME_EMAIL=$ACME_ESCAPED"
    else
        echo "ACME_EMAIL=$ACME_EMAIL_INPUT" >> "$ENV_FILE"
    fi

    log_success "ACME_EMAIL configurado: $ACME_EMAIL_INPUT"
    echo ""

    # ------------------------------------------------------------------
    # Generar Prometheus web.yml con Basic Auth (bcrypt)
    # ------------------------------------------------------------------
    PROMETHEUS_WEB_YML="$PROJECT_ROOT/configs/prometheus/web.yml"
    PROMETHEUS_PWD=$(generate_password)

    echo -e "${BLUE}Generando credenciales Basic Auth para Prometheus (web.yml)...${NC}"

    PROM_BCRYPT_HASH=$(generate_bcrypt_hash "$PROMETHEUS_PWD")

    if [[ -z "$PROM_BCRYPT_HASH" ]]; then
        log_error "No se pudo generar hash bcrypt para Prometheus. Instala htpasswd o Docker."
        exit 1
    fi

    cat > "$PROMETHEUS_WEB_YML" <<EOF
# Generado automáticamente por setup-env.sh — NO editar manualmente
basic_auth_users:
  prometheus: "$PROM_BCRYPT_HASH"
EOF
    chmod 600 "$PROMETHEUS_WEB_YML"
    log_success "Prometheus web.yml generado con Basic Auth"

    # Guardar PROMETHEUS_PASSWORD en .env (requerido por healthcheck en prod)
    if grep -q "^# PROMETHEUS_PASSWORD=" "$ENV_FILE"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^# PROMETHEUS_PASSWORD=.*/PROMETHEUS_PASSWORD=$(escape_sed "$PROMETHEUS_PWD")/" "$ENV_FILE"
        else
            sed -i "s/^# PROMETHEUS_PASSWORD=.*/PROMETHEUS_PASSWORD=$(escape_sed "$PROMETHEUS_PWD")/" "$ENV_FILE"
        fi
    elif grep -q "^PROMETHEUS_PASSWORD=" "$ENV_FILE"; then
        replace_in_env "^PROMETHEUS_PASSWORD=.*" "PROMETHEUS_PASSWORD=$(escape_sed "$PROMETHEUS_PWD")"
    else
        echo "PROMETHEUS_PASSWORD=$PROMETHEUS_PWD" >> "$ENV_FILE"
    fi
    echo ""

else
    DEPLOY_MODE="desarrollo"
fi

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
if [[ "$DEPLOY_MODE" == "producción" ]]; then
    echo -e "  Prometheus:      ${YELLOW}prometheus / $(mask_credential "$PROMETHEUS_PWD")${NC} (web.yml Basic Auth)"
fi
echo ""
log_warning "IMPORTANTE: Las credenciales completas están en el archivo .env"
echo -e "${YELLOW}  Consultar: cat .env (archivo con permisos 600)${NC}"
echo -e "${YELLOW}  Los archivos .env, .htpasswd y web.yml tienen permisos restringidos.${NC}"
echo ""

# ==============================================================================
# Resumen de modo de despliegue
# ==============================================================================
echo -e "${BLUE}━━━ Modo Detectado ━━━${NC}"
if [[ "$DEPLOY_MODE" == "producción" ]]; then
    echo -e "  Modo:       ${YELLOW}PRODUCCIÓN${NC}"
    echo -e "  Dominio:    ${YELLOW}$CONFIGURED_DOMAIN${NC}"
    echo -e "  ACME Email: ${YELLOW}$ACME_EMAIL_INPUT${NC}"
    echo -e "  SSL:        ${GREEN}Let's Encrypt (automático)${NC}"
    echo ""
    echo -e "${GREEN}Próximo paso: ./scripts/start.sh prod${NC}"
else
    echo -e "  Modo:       ${GREEN}DESARROLLO${NC}"
    echo -e "  Dominio:    ${GREEN}$CONFIGURED_DOMAIN${NC}"
    echo -e "  SSL:        ${YELLOW}N/A (desarrollo local)${NC}"
    echo ""
    echo -e "${GREEN}Próximo paso: ./scripts/start.sh dev${NC}"
fi
