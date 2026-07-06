# =============================================================================
# Outputs — información de conexión (sin IPs; por dominio / alias de red)
# =============================================================================
output "network_name" {
  description = "Red Docker compartida"
  value       = module.network.name
}

output "environment" {
  value = var.environment
}

output "docker_host" {
  description = "Destino Docker activo (local o ssh://...)"
  value       = var.docker_host
}

output "endpoints" {
  description = "URLs públicas (vía Traefik)"
  value = {
    frontend = "https://${var.domain}"
    api      = "https://api.${var.domain}/api"
    auth     = "https://auth.${var.domain}"
    grafana  = "https://grafana.${var.domain}"
    minio    = "https://minio.${var.domain}"
    s3       = "https://s3.${var.domain}"
    traefik  = "https://traefik.${var.domain}"
  }
}

# Todas las claves generadas (nombre -> valor).
#   Verlas todas:        terraform output -json secrets | jq
#   Una sola:            terraform output -json secrets | jq -r '.rabbitmq_password'
output "secrets" {
  description = "Mapa de todas las claves generadas (sensible)"
  value       = module.secrets.values
  sensitive   = true
}

# Secretos generados — para consultarlos: terraform output -raw <name>
output "grafana_admin_password" {
  value     = module.secrets.values["grafana_admin_password"]
  sensitive = true
}
output "keycloak_admin_password" {
  value     = module.secrets.values["keycloak_admin_password"]
  sensitive = true
}
output "admin_auth_password" {
  description = "BasicAuth de consolas admin (Traefik dashboard)"
  value       = module.secrets.values["admin_auth_password"]
  sensitive   = true
}

# Credenciales de APLICACIÓN (backend) — privilegio mínimo, separadas de las admin.
output "rabbitmq_app_password" {
  description = "Password del usuario de aplicación de RabbitMQ (sin admin)"
  value       = module.secrets.values["rabbitmq_app_password"]
  sensitive   = true
}
output "redis_app_password" {
  description = "Password del usuario ACL de aplicación de Redis (sin comandos peligrosos)"
  value       = module.secrets.values["redis_app_password"]
  sensitive   = true
}
