# =============================================================================
# Módulo secrets — generación de secretos (interfaz vault-ready)
# =============================================================================
# Genera cada secreto con random_password (versionado en el state, rotable).
# Interfaz desacoplada: si var.provided_secrets trae una clave, se usa ESA en
# vez de la generada. Migrar a Vault/Key Vault luego = alimentar ese mapa desde
# data sources (vault_generic_secret / azurerm_key_vault_secret / aws_secretsmanager),
# SIN tocar a los consumidores (siguen leyendo los outputs de este módulo).
# =============================================================================

locals {
  # Secretos alfanuméricos (seguros en cadenas de conexión, JSON y args de shell).
  secret_names = [
    "postgres_password",
    "app_db_password",
    "keycloak_admin_password",
    "keycloak_db_password",
    "keycloak_client_secret",
    "rabbitmq_password",
    "rabbitmq_app_password",
    "redis_password",
    "redis_app_password",
    "minio_root_password",
    "minio_secret_key",
    "grafana_admin_password",
    "admin_auth_password",
  ]
}

resource "random_password" "this" {
  for_each = toset(local.secret_names)

  length  = 32
  special = false # alfanumérico: evita romper URLs JDBC / cadenas de conexión
}
