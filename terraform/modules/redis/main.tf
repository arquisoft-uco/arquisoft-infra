# =============================================================================
# Módulo redis — caché / rate-limiting (solo red interna)
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "redis_password" {
  type      = string
  sensitive = true
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

  command = ["redis-server", "--requirepass", var.redis_password, "--appendonly", "yes"]

  # El healthcheck lee la contraseña por env (no se incrusta en el comando del check).
  env = ["REDIS_PASSWORD=${var.redis_password}"]

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["redis"]
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
