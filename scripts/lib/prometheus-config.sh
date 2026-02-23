#!/bin/bash
# ==============================================================================
# Arquisoft - Módulo de Configuración de Prometheus
# ==============================================================================
# Funciones para generar web.yml con Basic Auth
# ==============================================================================

# Generar web.yml para Prometheus si no existe
generate_prometheus_web_config() {
    local project_root=$1
    local env_file=$2
    
    local web_yml="$project_root/configs/prometheus/web.yml"
    
    # Cargar funciones necesarias
    source "$project_root/scripts/lib/password-generator.sh"
    source "$project_root/scripts/lib/env-config.sh"
    source "$project_root/scripts/lib/common.sh"
    
    # Verificar si ya existe
    if [[ -f "$web_yml" ]]; then
        log_success "configs/prometheus/web.yml ya existe, se mantiene"
        return 0
    fi
    
    # Eliminar directorio erróneo si existe (creado por Docker)
    if [[ -d "$web_yml" ]]; then
        log_warning "Eliminando directorio erróneo: $web_yml"
        rm -rf "$web_yml"
    fi
    
    echo -e "${BLUE}Generando Prometheus web.yml...${NC}"
    
    # Obtener o generar PROMETHEUS_PASSWORD
    local prometheus_pwd=$(get_env_var "$env_file" "PROMETHEUS_PASSWORD")
    
    if [[ -z "$prometheus_pwd" ]]; then
        # Generar nueva password
        prometheus_pwd=$(generate_password)
        
        # Guardar en .env
        local prometheus_pwd_esc=$(escape_sed "$prometheus_pwd")
        uncomment_env_var "$env_file" "PROMETHEUS_PASSWORD" "$prometheus_pwd_esc"
        
        echo -e "${GREEN}✓ Nueva PROMETHEUS_PASSWORD generada${NC}"
    else
        echo -e "${GREEN}✓ Usando PROMETHEUS_PASSWORD existente desde .env${NC}"
    fi
    
    # Generar hash bcrypt
    local bcrypt_hash=$(generate_bcrypt_hash "$prometheus_pwd")
    
    if [[ -z "$bcrypt_hash" ]]; then
        log_error "No se pudo generar hash bcrypt. Instala htpasswd o Docker."
        return 1
    fi
    
    # Crear web.yml
    cat > "$web_yml" <<EOF
# Generado automáticamente por setup-env.sh — NO editar manualmente
# Para regenerar: rm configs/prometheus/web.yml && bash scripts/setup-env.sh prod
basic_auth_users:
  prometheus: "$bcrypt_hash"
EOF
    
    # Permisos 644: owner rw, group r, others r
    # Necesario para que Docker pueda leer el archivo desde el contenedor
    chmod 644 "$web_yml"
    
    log_success "Prometheus web.yml generado con Basic Auth"
    echo -e "  Credencial: ${YELLOW}prometheus / $(mask_credential "$prometheus_pwd")${NC}"
    echo ""
    
    return 0
}
