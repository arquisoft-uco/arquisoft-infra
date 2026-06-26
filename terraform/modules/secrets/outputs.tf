# Mapa de secretos efectivos (provistos externamente o generados).
output "values" {
  description = "Mapa nombre→secreto (sensible)"
  value = merge(
    { for k, r in random_password.this : k => lookup(var.provided_secrets, k, r.result) },
  )
  sensitive = true
}

# Hash bcrypt ESTABLE del password de BasicAuth admin (para el .htpasswd de Traefik).
# Se usa el atributo bcrypt_hash de random_password (en state, sin churn de la función bcrypt()).
output "admin_auth_bcrypt" {
  description = "Hash bcrypt del usuario admin para usersFile de Traefik"
  value       = random_password.this["admin_auth_password"].bcrypt_hash
  sensitive   = true
}
