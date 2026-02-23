#!/bin/bash
# ==============================================================================
# Arquisoft - Módulo de Configuración de .env
# ==============================================================================
# Funciones para manejo del archivo .env
# ==============================================================================

# Reemplazar placeholders en .env (compatible macOS y Linux)
replace_in_env() {
    local env_file=$1
    local pattern=$2
    local replacement=$3
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "s/$pattern/$replacement/" "$env_file"
    else
        sed -i "s/$pattern/$replacement/" "$env_file"
    fi
}

# Leer variable desde .env
get_env_var() {
    local env_file=$1
    local var_name=$2
    
    if [[ -f "$env_file" ]] && grep -q "^${var_name}=" "$env_file"; then
        grep "^${var_name}=" "$env_file" | cut -d'=' -f2-
    else
        echo ""
    fi
}

# Verificar si variable existe en .env
has_env_var() {
    local env_file=$1
    local var_name=$2
    
    [[ -f "$env_file" ]] && grep -q "^${var_name}=" "$env_file"
}

# Establecer variable en .env (crea o actualiza)
set_env_var() {
    local env_file=$1
    local var_name=$2
    local var_value=$3
    
    if has_env_var "$env_file" "$var_name"; then
        # Actualizar existente
        replace_in_env "$env_file" "^${var_name}=.*" "${var_name}=${var_value}"
    else
        # Agregar nueva
        echo "${var_name}=${var_value}" >> "$env_file"
    fi
}

# Descomentar variable en .env
uncomment_env_var() {
    local env_file=$1
    local var_name=$2
    local var_value=$3
    
    if grep -q "^# ${var_name}=" "$env_file"; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            sed -i '' "s/^# ${var_name}=.*/${var_name}=${var_value}/" "$env_file"
        else
            sed -i "s/^# ${var_name}=.*/${var_name}=${var_value}/" "$env_file"
        fi
    else
        set_env_var "$env_file" "$var_name" "$var_value"
    fi
}

# Generar .env desde .env.example con passwords aleatorias
generate_env_from_template() {
    local env_example=$1
    local env_file=$2
    local project_root=$3
    
    # Cargar funciones de password
    source "$project_root/scripts/lib/password-generator.sh"
    source "$project_root/scripts/lib/common.sh"
    
    echo -e "${BLUE}Generando archivo .env con credenciales seguras...${NC}"
    
    # Copiar template
    cp "$env_example" "$env_file"
    
    # Generar passwords
    local postgres_pwd=$(generate_password)
    local rabbitmq_pwd=$(generate_password)
    local minio_pwd=$(generate_password)
    local keycloak_pwd=$(generate_password)
    local kc_realm_admin_pwd=$(generate_password)
    local grafana_pwd=$(generate_password)
    
    # Escapar para sed
    local postgres_pwd_esc=$(escape_sed "$postgres_pwd")
    local rabbitmq_pwd_esc=$(escape_sed "$rabbitmq_pwd")
    local minio_pwd_esc=$(escape_sed "$minio_pwd")
    local keycloak_pwd_esc=$(escape_sed "$keycloak_pwd")
    local kc_realm_admin_pwd_esc=$(escape_sed "$kc_realm_admin_pwd")
    local grafana_pwd_esc=$(escape_sed "$grafana_pwd")
    
    # Reemplazar placeholders
    replace_in_env "$env_file" "POSTGRES_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "POSTGRES_PASSWORD=$postgres_pwd_esc"
    replace_in_env "$env_file" "RABBITMQ_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "RABBITMQ_PASSWORD=$rabbitmq_pwd_esc"
    replace_in_env "$env_file" "MINIO_ROOT_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "MINIO_ROOT_PASSWORD=$minio_pwd_esc"
    replace_in_env "$env_file" "KEYCLOAK_ADMIN_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "KEYCLOAK_ADMIN_PASSWORD=$keycloak_pwd_esc"
    replace_in_env "$env_file" "KC_REALM_ADMIN_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "KC_REALM_ADMIN_PASSWORD=$kc_realm_admin_pwd_esc"
    replace_in_env "$env_file" "GRAFANA_ADMIN_PASSWORD=CHANGE_ME_GENERATE_STRONG_PASSWORD" "GRAFANA_ADMIN_PASSWORD=$grafana_pwd_esc"
    
    # Permisos restrictivos
    chmod 600 "$env_file"
    
    echo -e "${GREEN}✓ Archivo .env generado${NC}"
    echo -e "${BLUE}Credenciales (enmascaradas):${NC}"
    echo -e "  PostgreSQL:      ${YELLOW}$(mask_credential "$postgres_pwd")${NC}"
    echo -e "  RabbitMQ:        ${YELLOW}$(mask_credential "$rabbitmq_pwd")${NC}"
    echo -e "  MinIO:           ${YELLOW}$(mask_credential "$minio_pwd")${NC}"
    echo -e "  Keycloak Master: ${YELLOW}$(mask_credential "$keycloak_pwd")${NC}"
    echo -e "  Keycloak Realm:  ${YELLOW}$(mask_credential "$kc_realm_admin_pwd")${NC}"
    echo -e "  Grafana:         ${YELLOW}$(mask_credential "$grafana_pwd")${NC}"
    echo ""
}
