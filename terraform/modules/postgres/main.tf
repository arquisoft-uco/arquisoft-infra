# =============================================================================
# Módulo postgres — PostgreSQL de la aplicación (7 BDs por bounded context)
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "static_ip" {
  description = "IP estática dentro de la red (para endpoint fijo vía VPN, ej. DBeaver). null = dinámica"
  type        = string
  default     = null
}
variable "component_dir" {
  description = "Ruta absoluta a components/postgres (para el init script)"
  type        = string
}
variable "postgres_user" { type = string }
variable "postgres_db" { type = string }
variable "postgres_password" {
  type      = string
  sensitive = true
}
variable "app_db_user" { type = string }
variable "app_db_password" {
  type      = string
  sensitive = true
}
variable "expose_ports" {
  description = "Exponer puerto 5432 directamente en el host (solo dev)"
  type        = bool
  default     = false
}

resource "docker_image" "postgres" {
  name         = "postgres:18-alpine"
  keep_locally = true
}

resource "docker_volume" "data" {
  name = "arquisoft-postgres-data"
}

resource "docker_container" "postgres" {
  # El provider Docker reporta "drift" en atributos que calcula el daemon
  # (memory_swap=2x memory, log_opts por defecto, capabilities); ignorarlos
  # mantiene `terraform apply` idempotente.
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities]
  }

  name    = "arquisoft-postgres"
  image   = docker_image.postgres.image_id
  restart = "always"
  memory  = 1024
  cpus    = "2.0"

  env = [
    "POSTGRES_USER=${var.postgres_user}",
    "POSTGRES_PASSWORD=${var.postgres_password}",
    "POSTGRES_DB=${var.postgres_db}",
    "APP_DB_USER=${var.app_db_user}",
    "APP_DB_PASSWORD=${var.app_db_password}",
    "PGDATA=/var/lib/postgresql/data/pgdata",
  ]

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/postgresql/data"
  }

  # Script de init (crea las 7 BDs + usuario app). Se ejecuta solo al crear el volumen.
  upload {
    file       = "/docker-entrypoint-initdb.d/01-init-databases.sh"
    content    = file("${var.component_dir}/init/01-init-databases.sh")
    executable = true
  }

  dynamic "ports" {
    for_each = var.expose_ports ? [1] : []
    content {
      internal = 5432
      external = 5432
    }
  }

  networks_advanced {
    name         = var.network_name
    aliases      = ["postgres"]
    ipv4_address = var.static_ip
  }

  healthcheck {
    test         = ["CMD-SHELL", "pg_isready -U ${var.postgres_user}"]
    interval     = "10s"
    timeout      = "5s"
    retries      = 5
    start_period = "30s"
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "5" }
}

output "alias" { value = "postgres" }
