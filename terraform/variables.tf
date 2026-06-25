# =============================================================================
# Variables raíz
# =============================================================================

# ---------- Destino Docker (portabilidad propio/cloud) ----------
variable "docker_host" {
  description = "Endpoint del daemon Docker. Local: unix:///var/run/docker.sock. Remoto: ssh://user@ip"
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "docker_ssh_opts" {
  description = "Opciones SSH para host=ssh:// (p.ej. -i <llave> -o StrictHostKeyChecking=accept-new)"
  type        = list(string)
  default     = []
}

# ---------- Entorno / dominio ----------
variable "environment" {
  description = "Nombre del entorno (solo para nomenclatura/estado): dev | prod"
  type        = string
  default     = "prod"
}

variable "domain" {
  description = "Dominio público base (api., auth., grafana., minio., s3., rabbitmq., traefik.)"
  type        = string
}

variable "acme_email" {
  description = "Email para Let's Encrypt (Traefik)"
  type        = string
}

variable "timezone" {
  description = "Zona horaria de los contenedores"
  type        = string
  default     = "America/Bogota"
}

# ---------- Toggles de despliegue ----------
variable "deploy_backend" {
  description = "Desplegar el backend (+ Alloy). Requiere backend_image."
  type        = bool
  default     = true
}

variable "deploy_frontend" {
  description = "Desplegar el frontend. Requiere frontend_image."
  type        = bool
  default     = false
}

variable "enable_server_prep" {
  description = "Aplicar firewall del host (ufw) vía SSH antes de desplegar (solo destinos remotos)"
  type        = bool
  default     = false
}

# ---------- Imágenes externas ----------
variable "backend_image" {
  type    = string
  default = "ghcr.io/arquisoft-uco/arquisoft-backend"
}
variable "backend_tag" {
  type    = string
  default = "sha-f906ef4"
}
variable "frontend_image" {
  type    = string
  default = ""
}
variable "frontend_tag" {
  type    = string
  default = "latest"
}

# ---------- Usuarios / identificadores (no secretos) ----------
variable "postgres_user" {
  type    = string
  default = "postgres"
}
variable "postgres_db" {
  type    = string
  default = "postgres"
}
variable "app_db_user" {
  type    = string
  default = "arquisoft_user"
}

variable "keycloak_admin_user" {
  type    = string
  default = "admin"
}
variable "keycloak_db_user" {
  type    = string
  default = "keycloak"
}
variable "keycloak_db_name" {
  type    = string
  default = "keycloak"
}
variable "keycloak_realm" {
  type    = string
  default = "arquisoft"
}
variable "keycloak_client_id" {
  type    = string
  default = "arquisoft-api"
}
variable "kc_realm_admin_email" {
  type    = string
  default = "admin@uco.edu.co"
}
variable "kc_realm_admin_first_name" {
  type    = string
  default = "Admin"
}
variable "kc_realm_admin_last_name" {
  type    = string
  default = "Sistema"
}

variable "rabbitmq_user" {
  type    = string
  default = "arquisoft"
}
variable "rabbitmq_vhost" {
  description = "vhost de RabbitMQ. La imagen del backend usa el vhost por defecto '/'."
  type        = string
  default     = "/"
}

variable "minio_root_user" {
  type    = string
  default = "arquisoft"
}
variable "minio_access_key" {
  description = "Access key de la cuenta de servicio del backend en MinIO"
  type        = string
  default     = "arquisoft-backend"
}

variable "grafana_admin_user" {
  type    = string
  default = "admin"
}

variable "admin_auth_user" {
  description = "Usuario de BasicAuth para consolas admin (Traefik dashboard, etc.)"
  type        = string
  default     = "admin"
}

# ---------- Observabilidad (multi-servidor) ----------
variable "loki_url" {
  type    = string
  default = "http://loki:3100/loki/api/v1/push"
}
variable "prometheus_url" {
  type    = string
  default = "http://prometheus:9090/api/v1/write"
}
variable "backend_target" {
  type    = string
  default = "arquisoft-backend:8080"
}

# ---------- Secretos provistos externamente (vault-ready) ----------
# Mapa opcional para inyectar secretos desde un Key Vault en el futuro.
# Si una clave está presente, el módulo 'secrets' la usa en vez de generar.
# Claves: postgres_password, app_db_password, keycloak_admin_password,
# keycloak_db_password, kc_realm_admin_password, keycloak_client_secret,
# rabbitmq_password, redis_password, minio_root_password, minio_secret_key,
# grafana_admin_password, admin_auth_password
variable "provided_secrets" {
  description = "Secretos provistos externamente (Key Vault). Vacío = generar con random_password."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ---------- Conexión SSH para server_prep (firewall) ----------
variable "ssh_host" {
  type    = string
  default = ""
}
variable "ssh_user" {
  type    = string
  default = "ubuntu"
}
variable "ssh_private_key_path" {
  type    = string
  default = ""
}
