# =============================================================================
# Módulo redis — caché / rate-limiting (solo red interna)
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "static_ip" {
  description = "IP estática dentro de la red (endpoint fijo vía VPN). null = dinámica"
  type        = string
  default     = null
}
variable "redis_password" {
  type      = string
  sensitive = true
}
# Usuario de aplicación (backend) vía ACL nativo de Redis 7. El usuario `default`
# (requirepass) queda como admin; este usuario tiene privilegio mínimo.
variable "redis_app_user" { type = string }
variable "redis_app_password" {
  type      = string
  sensitive = true
}
variable "expose_ports" {
  description = "Exponer puerto 6379 directamente en el host (solo dev)"
  type        = bool
  default     = false
}

resource "docker_image" "redis" {
  name         = "redis:7-alpine"
  keep_locally = true
}

resource "docker_volume" "data" {
  name = "arquisoft-redis-data"
}

resource "docker_container" "redis" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name    = "arquisoft-redis"
  image   = docker_image.redis.image_id
  restart = "always"
  memory  = 256
  cpus    = "0.5"

  # `default` = admin (requirepass). El usuario de app tiene ACL de privilegio mínimo:
  # acceso a todas las claves (~*) y canales (&*), todos los comandos EXCEPTO los
  # peligrosos (-@dangerous: FLUSHALL, CONFIG, SHUTDOWN, KEYS, etc.).
  # `+info` re-otorga solo INFO (read-only): lo necesita el health check de Spring
  # Boot (RedisHealthIndicator) y no es destructivo. El orden importa: se aplica de
  # izquierda a derecha (+@all quita @dangerous, luego +info lo vuelve a permitir).
  # `--user ...` debe ir al final: consume todos los tokens hasta el siguiente `--`.
  command = [
    "redis-server",
    "--requirepass", var.redis_password,
    "--appendonly", "yes",
    "--user", var.redis_app_user, "on", ">${var.redis_app_password}", "~*", "&*", "+@all", "-@dangerous", "+info",
  ]

  # El healthcheck lee la contraseña por env (no se incrusta en el comando del check).
  env = ["REDIS_PASSWORD=${var.redis_password}"]

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  dynamic "ports" {
    for_each = var.expose_ports ? [1] : []
    content {
      internal = 6379
      external = 6379
    }
  }

  networks_advanced {
    name         = var.network_name
    aliases      = ["redis"]
    ipv4_address = var.static_ip
  }

  healthcheck {
    test         = ["CMD-SHELL", "redis-cli -a \"$REDIS_PASSWORD\" ping | grep -q PONG"]
    interval     = "15s"
    timeout      = "5s"
    retries      = 5
    start_period = "10s"
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "3" }
}

output "alias" { value = "redis" }
