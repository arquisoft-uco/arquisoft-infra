# =============================================================================
# Módulo keycloak — Identity Provider + BD dedicada + import de realm
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "kc_db_static_ip" {
  description = "IP estática de la BD de Keycloak (endpoint fijo vía VPN). null = dinámica"
  type        = string
  default     = null
}
variable "keycloak_static_ip" {
  description = "IP estática de Keycloak (endpoint fijo vía VPN). null = dinámica"
  type        = string
  default     = null
}
variable "component_dir" { type = string } # components/keycloak (para realm template)
variable "domain" { type = string }

variable "admin_user" { type = string }
variable "admin_password" {
  type      = string
  sensitive = true
}
variable "db_user" { type = string }
variable "db_name" { type = string }
variable "db_password" {
  type      = string
  sensitive = true
}

variable "realm_name" {
  description = "Nombre del realm de Keycloak. Debe coincidir con KEYCLOAK_REALM del backend."
  type        = string
  default     = "arquisoft"
}
variable "client_id" { type = string }
variable "client_secret" {
  type      = string
  sensitive = true
}

# ---------------- Base de datos dedicada de Keycloak ----------------
resource "docker_image" "kc_db" {
  name         = "postgres:18-alpine"
  keep_locally = true
}

resource "docker_volume" "kc_db_data" {
  name = "arquisoft-keycloak-db-data"
}

resource "docker_container" "kc_db" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name    = "arquisoft-keycloak-db"
  image   = docker_image.kc_db.image_id
  restart = "always"
  memory  = 512
  cpus    = "1.0"

  env = [
    "POSTGRES_USER=${var.db_user}",
    "POSTGRES_PASSWORD=${var.db_password}",
    "POSTGRES_DB=${var.db_name}",
    "PGDATA=/var/lib/postgresql/data/pgdata",
  ]

  volumes {
    volume_name    = docker_volume.kc_db_data.name
    container_path = "/var/lib/postgresql/data"
  }

  networks_advanced {
    name         = var.network_name
    aliases      = ["keycloak-db"]
    ipv4_address = var.kc_db_static_ip
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U ${var.db_user} -d ${var.db_name}"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "20s"
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "3" }
}

# ---------------- Keycloak ----------------
resource "docker_image" "keycloak" {
  name         = "quay.io/keycloak/keycloak:26.6"
  keep_locally = true
}

locals {
  kc_labels = {
    "traefik.enable"                                          = "true"
    "traefik.http.routers.keycloak.rule"                      = "Host(`auth.${var.domain}`)"
    "traefik.http.routers.keycloak.entrypoints"               = "websecure"
    "traefik.http.routers.keycloak.tls"                       = "true"
    "traefik.http.routers.keycloak.tls.certresolver"          = "letsencrypt"
    "traefik.http.services.keycloak.loadbalancer.server.port" = "8080"
  }
}

resource "docker_container" "keycloak" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name       = "arquisoft-keycloak"
  image      = docker_image.keycloak.image_id
  restart    = "always"
  memory     = 2048
  cpus       = "2.0"
  command    = ["start", "--import-realm"]
  depends_on = [docker_container.kc_db]

  env = [
    "KC_BOOTSTRAP_ADMIN_USERNAME=${var.admin_user}",
    "KC_BOOTSTRAP_ADMIN_PASSWORD=${var.admin_password}",
    "KC_DB=postgres",
    "KC_DB_URL=jdbc:postgresql://keycloak-db:5432/${var.db_name}",
    "KC_DB_USERNAME=${var.db_user}",
    "KC_DB_PASSWORD=${var.db_password}",
    "KC_FEATURES=token-exchange,admin-fine-grained-authz",
    "KC_HEALTH_ENABLED=true",
    "KC_METRICS_ENABLED=true",
    "KC_HOSTNAME=https://auth.${var.domain}",
    "KC_HOSTNAME_STRICT=true",
    "KC_HTTP_ENABLED=true",
    "KC_PROXY_HEADERS=xforwarded",
  ]

  # Realm renderizado con replace() para compatibilidad con los ${...} internos de Keycloak
  # (i18n keys como ${role_*}, ${authBaseUrl}, etc.) que templatefile() no puede ignorar.
  upload {
    file = "/opt/keycloak/data/import/realm-arquisoft.json"
    content = replace(replace(replace(replace(
      file("${var.component_dir}/config/realm-arquisoft.json.template"),
      "$${KEYCLOAK_REALM}",         var.realm_name),
      "$${KEYCLOAK_CLIENT_ID}",     var.client_id),
      "$${KEYCLOAK_CLIENT_SECRET}", var.client_secret),
      "$${DOMAIN}",                 var.domain)
  }

  networks_advanced {
    name         = var.network_name
    aliases      = ["keycloak"]
    ipv4_address = var.keycloak_static_ip
  }

  healthcheck {
    test = ["CMD-SHELL", <<-EOT
      exec 3<>/dev/tcp/127.0.0.1/9000; echo -e 'GET /health/ready HTTP/1.1\r\nhost: localhost\r\nConnection: close\r\n\r\n' >&3; cat <&3 | grep -q '"status": "UP"'
    EOT
    ]
    interval     = "30s"
    timeout      = "10s"
    retries      = 5
    start_period = "2m0s" # el provider normaliza 120s -> 2m0s; usar la forma normalizada evita drift
  }

  dynamic "labels" {
    for_each = local.kc_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "5" }
}

output "alias" { value = "keycloak" }
output "internal_url" { value = "http://keycloak:8080" }
