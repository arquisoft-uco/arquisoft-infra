#!/bin/bash
# ==============================================================================
# Arquisoft - Módulo de Generación de Passwords
# ==============================================================================
# Funciones para generar passwords seguros y hashes
# ==============================================================================

# Generar contraseña segura
# Garantiza: ≥1 mayúscula, ≥1 dígito, ≥1 carácter especial
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

# Enmascarar credenciales para logs (muestra solo primeros 4 y últimos 4 caracteres)
mask_credential() {
    local cred=$1
    local len=${#cred}
    if [[ $len -le 8 ]]; then
        echo "********"
    else
        echo "${cred:0:4}$(printf '*%.0s' $(seq 1 $((len - 8))))${cred: -4}"
    fi
}

# Generar hash APR1 MD5 usando openssl (para Apache/Traefik)
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
