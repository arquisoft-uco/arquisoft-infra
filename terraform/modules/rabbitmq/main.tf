# =============================================================================
# Módulo rabbitmq — broker de mensajería
# =============================================================================
# El backend (Spring AMQP) declara su propia topología al arrancar en el vhost
# por defecto "/". Aquí solo se aprovisiona el usuario y sus permisos sobre "/"
# (definitions.json) + la config base (rabbitmq.conf).
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
variable "component_dir" {
  description = "Ruta absoluta a components/rabbitmq (config y definitions.json.template)"
  type        = string
}
variable "domain" { type = string }
variable "rabbitmq_user" { type = string }
variable "rabbitmq_password" {
  type      = string
  sensitive = true
}
variable "rabbitmq_vhost" { type = string }
variable "expose_ports" {
  description = "Exponer puertos 5672 (AMQP) y 15672 (UI) directamente en el host (solo dev)"
  type        = bool
  default     = false
}

locals {
  # Consola de administración (UI) publicada vía Traefik en rabbitmq.${domain} (puerto 15672)
  labels = {
    "traefik.enable"                                          = "true"
    "traefik.http.routers.rabbitmq.rule"                      = "Host(`rabbitmq.${var.domain}`)"
    "traefik.http.routers.rabbitmq.entrypoints"               = "websecure"
    "traefik.http.routers.rabbitmq.tls"                       = "true"
    "traefik.http.routers.rabbitmq.tls.certresolver"          = "letsencrypt"
    "traefik.http.routers.rabbitmq.middlewares"               = "secure-headers@file"
    "traefik.http.services.rabbitmq.loadbalancer.server.port" = "15672"
  }
}

resource "docker_image" "rabbitmq" {
  name         = "rabbitmq:4.2.5-management-alpine"
  keep_locally = true
}

resource "docker_volume" "data" {
  name = "arquisoft-rabbitmq-data"
}

resource "docker_container" "rabbitmq" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name    = "arquisoft-rabbitmq"
  image   = docker_image.rabbitmq.image_id
  restart = "always"
  memory  = 512
  cpus    = "1.0"

  env = [
    "RABBITMQ_DEFAULT_USER=${var.rabbitmq_user}",
    "RABBITMQ_DEFAULT_PASS=${var.rabbitmq_password}",
    "RABBITMQ_DEFAULT_VHOST=${var.rabbitmq_vhost}",
  ]

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/var/lib/rabbitmq"
  }

  upload {
    file    = "/etc/rabbitmq/rabbitmq.conf"
    content = file("${var.component_dir}/config/rabbitmq.conf")
  }

  upload {
    file = "/etc/rabbitmq/definitions.json"
    content = templatefile("${var.component_dir}/config/definitions.json.template", {
      RABBITMQ_USER     = var.rabbitmq_user
      RABBITMQ_PASSWORD = var.rabbitmq_password
    })
  }

  dynamic "ports" {
    for_each = var.expose_ports ? [
      { internal = 5672,  external = 5672  },
      { internal = 15672, external = 15672 },
    ] : []
    content {
      internal = ports.value.internal
      external = ports.value.external
    }
  }

  networks_advanced {
    name         = var.network_name
    aliases      = ["rabbitmq"]
    ipv4_address = var.static_ip
  }

  healthcheck {
    test     = ["CMD", "rabbitmq-diagnostics", "-q", "ping"]
    interval = "15s"
    timeout  = "10s"
    retries  = 5
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

output "alias" { value = "rabbitmq" }
