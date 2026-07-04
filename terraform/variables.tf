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
variable "expose_data_ports" {
  description = "Exponer puertos de datos directamente en el host (dev: true, prod: false)"
  type        = bool
  default     = false
}

variable "enable_server_prep" {
  description = "Aplicar firewall del host (ufw) vía SSH antes de desplegar (solo destinos remotos)"
  type        = bool
  default     = false
}

# ---------- Usuarios / identificadores ----------
# Sin defaults: los valores van en prod.tfvars (gitignoreado) para no exponerlos en el repo.
variable "postgres_user"      { type = string }
variable "postgres_db"        { type = string }
variable "app_db_user"        { type = string }
variable "keycloak_admin_user" { type = string }
variable "keycloak_db_user"   { type = string }
variable "keycloak_db_name"   { type = string }
variable "keycloak_realm"     { type = string }
variable "keycloak_client_id" { type = string }
variable "rabbitmq_user"      { type = string }
variable "rabbitmq_vhost" {
  description = "vhost de RabbitMQ. La imagen del backend usa el vhost por defecto '/'."
  type        = string
}
variable "minio_root_user"    { type = string }
variable "minio_access_key" {
  description = "Access key de la cuenta de servicio del backend en MinIO"
  type        = string
}
variable "grafana_admin_user" { type = string }
variable "admin_auth_user" {
  description = "Usuario de BasicAuth para consolas admin (Traefik dashboard, etc.)"
  type        = string
}

# ---------- Observabilidad (multi-servidor) ----------
variable "loki_url" {
  description = "URL de push de Loki. En multi-servidor, IP privada del servidor de obs."
  type        = string
  default     = "http://loki:3100/loki/api/v1/push"
}
variable "prometheus_url" {
  description = "URL de remote-write de Prometheus. En multi-servidor, IP privada del servidor de obs."
  type        = string
  default     = "http://prometheus:9090/api/v1/write"
}
variable "backend_target" {
  description = "Host:puerto del actuator del backend (para scrape de métricas)."
  type        = string
  default     = "arquisoft-backend:8080"
}

# ---------- Secretos provistos externamente (vault-ready) ----------
# Mapa opcional para inyectar secretos desde un Key Vault en el futuro.
# Si una clave está presente, el módulo 'secrets' la usa en vez de generar.
# Claves: postgres_password, app_db_password, keycloak_admin_password,
# keycloak_db_password, keycloak_client_secret, rabbitmq_password, redis_password,
# minio_root_password, minio_secret_key, grafana_admin_password, admin_auth_password
variable "provided_secrets" {
  description = "Secretos provistos externamente (Key Vault). Vacío = generar con random_password."
  type        = map(string)
  default     = {}
  sensitive   = true
}

# ---------- WireGuard VPN — Acceso seguro a infraestructura ----------
variable "wireguard_port" {
  description = "Puerto UDP para WireGuard (default: 51820, NAT-friendly)"
  type        = number
  default     = 51820
}

variable "wireguard_subnet" {
  description = "Subnet privada de clientes VPN (default: 10.0.2.0/24, coincide con Docker)"
  type        = string
  default     = "10.0.2.0/24"
}

variable "wireguard_peers" {
  description = "Lista de nombres de clientes VPN a provisionar (ej: dev1, dev2, dev3, ...)"
  type        = list(string)
  default     = ["dev1", "dev2", "dev3"]
}

variable "wireguard_max_clients" {
  description = "Número máximo de clientes VPN activos simultáneamente"
  type        = number
  default     = 50
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
