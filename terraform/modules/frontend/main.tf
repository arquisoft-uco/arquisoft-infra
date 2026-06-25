# =============================================================================
# Módulo frontend — SPA servida en la raíz del dominio (https://${domain})
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "domain" { type = string }
variable "timezone" { type = string }
variable "image" { type = string }
variable "tag" { type = string }
variable "port" {
  type    = number
  default = 80
}

locals {
  labels = {
    "traefik.enable"                                          = "true"
    "traefik.http.routers.frontend.rule"                      = "Host(`${var.domain}`)"
    "traefik.http.routers.frontend.entrypoints"               = "websecure"
    "traefik.http.routers.frontend.tls"                       = "true"
    "traefik.http.routers.frontend.tls.certresolver"          = "letsencrypt"
    "traefik.http.routers.frontend.middlewares"               = "secure-headers@file"
    "traefik.http.services.frontend.loadbalancer.server.port" = tostring(var.port)
  }
}

resource "docker_image" "frontend" {
  name         = "${var.image}:${var.tag}"
  keep_locally = true
}

resource "docker_container" "frontend" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name    = "arquisoft-frontend"
  image   = docker_image.frontend.image_id
  restart = "always"
  memory  = 512
  cpus    = "1.0"

  env = ["TZ=${var.timezone}"]

  networks_advanced {
    name    = var.network_name
    aliases = ["frontend"]
  }

  healthcheck {
    test         = ["CMD-SHELL", "wget -q --spider http://localhost:${var.port}/ || exit 1"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "20s"
  }

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "3" }
}
