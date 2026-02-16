#!/bin/bash
# ==============================================================================
# Arquisoft - Funciones compartidas para scripts
# ==============================================================================
# Colores, logging y utilidades comunes.
# Uso: source "$SCRIPT_DIR/lib/common.sh"
# ==============================================================================

# Colores para output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Contadores
ERRORS=0
WARNINGS=0

# Funciones de logging
log_info() { echo -e "${BLUE}ℹ ${NC}$1"; }
log_success() { echo -e "${GREEN}✓ ${NC}$1"; }
log_warning() { echo -e "${YELLOW}⚠ ${NC}$1"; ((WARNINGS+=1)); }
log_error() { echo -e "${RED}✗ ${NC}$1"; ((ERRORS+=1)); }

# Función para escapar caracteres especiales en valores para sed
escape_sed() {
    local str=$1
    printf '%s\n' "$str" | sed 's/[&/\$]/\\&/g'
}

# Resumen final de validación
print_summary() {
    local title="${1:-RESUMEN}"
    printf -v padded "%-60s" "$title"
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  ${padded}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════════╝${NC}"

    if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
        echo -e "${GREEN}✓ Todas las verificaciones PASARON${NC}"
        return 0
    elif [[ $ERRORS -eq 0 ]]; then
        echo -e "${YELLOW}⚠ Verificación completada con $WARNINGS advertencias${NC}"
        return 0
    else
        echo -e "${RED}✗ Verificación FALLIDA: $ERRORS errores, $WARNINGS advertencias${NC}"
        return 1
    fi
}
