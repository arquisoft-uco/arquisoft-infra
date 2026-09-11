#!/usr/bin/env bash
# =============================================================================
# mailpit — genera los archivos de credenciales desde el .env de esta carpeta
# =============================================================================
# Mailpit sólo acepta credenciales desde archivos (user:password por línea), no
# por variable de entorno. Este script los genera desde el .env local:
#   config/smtp-auth.txt  -> autenticación SMTP (la usa arquisoft-backend)
#   config/ui-auth.txt    -> autenticación de la bandeja web y la API
# Ambos contienen secretos y están gitignored.
# =============================================================================
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"

[[ -f .env ]] || { echo "ERROR: falta .env. Ejecutar: cp .env.example .env" >&2; exit 1; }

set -a; source .env; set +a

require() {
  local name="$1" value="${!1:-}"
  [[ -n "$value" ]] || { echo "ERROR: $name requerido en .env" >&2; exit 1; }
  [[ "$value" != "CHANGE_ME" ]] || { echo "ERROR: $name sigue en CHANGE_ME. Definir un valor real en .env" >&2; exit 1; }
}

require MAIL_USERNAME
require MAIL_PASSWORD
require MAILPIT_UI_USER
require MAILPIT_UI_PASSWORD

# El usuario de Mailpit no es root: los archivos deben ser legibles por otros.
envsubst < config/smtp-auth.txt.template > config/smtp-auth.txt
envsubst < config/ui-auth.txt.template   > config/ui-auth.txt
chmod 644 config/smtp-auth.txt config/ui-auth.txt

echo "OK  config/smtp-auth.txt  -> usuario SMTP '${MAIL_USERNAME}'"
echo "OK  config/ui-auth.txt    -> usuario bandeja '${MAILPIT_UI_USER}'"
echo "    Recordar: MAIL_USERNAME/MAIL_PASSWORD del backend deben coincidir."
