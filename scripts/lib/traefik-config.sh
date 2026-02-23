#!/bin/bash
# ==============================================================================
# Arquisoft - Módulo de Configuración de Traefik
# ==============================================================================
# Funciones para generar .htpasswd con BasicAuth
# ==============================================================================

# Generar .htpasswd para Traefik si no existe
generate_traefik_htpasswd() {
    local project_root=$1
    
    local htpasswd_file="$project_root/configs/traefik/certs/.htpasswd"
    local htpasswd_dir=$(dirname "$htpasswd_file")
    
    # Cargar funciones necesarias
    source "$project_root/scripts/lib/password-generator.sh"
    source "$project_root/scripts/lib/common.sh"
    
    # Verificar si ya existe
    if [[ -f "$htpasswd_file" ]]; then
        log_success "configs/traefik/certs/.htpasswd ya existe, se mantiene"
        return 0
    fi
    
    echo -e "${BLUE}Generando Traefik BasicAuth (.htpasswd)...${NC}"
    
    # Crear directorio si no existe
    mkdir -p "$htpasswd_dir"
    
    # Generar credenciales
    local basicauth_user="admin"
    local basicauth_pwd=$(generate_password)
    local basicauth_hash=$(generate_apr1_hash "$basicauth_pwd")
    
    # Crear archivo
    echo "${basicauth_user}:${basicauth_hash}" > "$htpasswd_file"
    chmod 600 "$htpasswd_file"
    
    log_success "Traefik .htpasswd generado"
    echo -e "  Credencial: ${YELLOW}${basicauth_user} / $(mask_credential "$basicauth_pwd")${NC}"
    echo ""
    
    return 0
}
