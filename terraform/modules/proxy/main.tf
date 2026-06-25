# =============================================================================
# Módulo proxy — Traefik (SSL automático Let's Encrypt + routing por labels)
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "component_dir" { type = string } # components/proxy
variable "domain" { type = string }
variable "acme_email" { type = string }
variable "timezone" { type = string }
variable "docker_api_version" {
  type    = string
  default = "1.44"
}
variable "admin_user" { type = string }
variable "admin_bcrypt" {
  description = "Hash bcrypt del usuario admin (usersFile de BasicAuth)"
  type        = string
  sensitive   = true
}

resource "docker_image" "traefik" {
  name         = "traefik:v3.6"
  keep_locally = true
}

resource "docker_volume" "letsencrypt" {
  name = "arquisoft-traefik-letsencrypt"
}
resource "docker_volume" "logs" {
  name = "arquisoft-traefik-logs"
}

locals {
  labels = {
    "traefik.enable"                                  = "true"
    "traefik.http.routers.dashboard.rule"             = "Host(`traefik.${var.domain}`)"
    "traefik.http.routers.dashboard.entrypoints"      = "websecure"
    "traefik.http.routers.dashboard.tls"              = "true"
    "traefik.http.routers.dashboard.tls.certresolver" = "letsencrypt"
    "traefik.http.routers.dashboard.service"          = "api@internal"
    "traefik.http.routers.dashboard.middlewares"      = "admin-auth@file,secure-headers@file"
  }
}

resource "docker_container" "traefik" {
  # capabilities/entrypoint los reporta el daemon distinto a la config (ForceNew) → ignorar
  # evita recrear Traefik en cada apply. memory_swap/log_opts: idem (drift del daemon).
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities, entrypoint]
  }

  name    = "arquisoft-traefik"
  image   = docker_image.traefik.image_id
  restart = "always"
  memory  = 256
  command = ["--configFile=/etc/traefik/traefik.yml"]

  env = [
    "TZ=${var.timezone}",
    "DOCKER_API_VERSION=${var.docker_api_version}",
  ]

  ports {
    internal = 80
    external = 80
  }
  ports {
    internal = 443
    external = 443
  }

  # Socket Docker (lectura de labels) + volúmenes de certificados y logs
  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.letsencrypt.name
    container_path = "/letsencrypt"
  }
  volumes {
    volume_name    = docker_volume.logs.name
    container_path = "/var/log/traefik"
  }

  # Config estática (renderiza ACME_EMAIL), middlewares dinámicos y .htpasswd
  upload {
    file    = "/etc/traefik/traefik.yml"
    content = templatefile("${var.component_dir}/config/traefik.yml.template", { ACME_EMAIL = var.acme_email })
  }
  upload {
    file    = "/etc/traefik/dynamic/middlewares.yml"
    content = file("${var.component_dir}/config/dynamic/middlewares.yml")
  }
  upload {
    file    = "/etc/traefik/dynamic/.htpasswd"
    content = "${var.admin_user}:${var.admin_bcrypt}\n"
  }

  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }

  networks_advanced {
    name = var.network_name
  }

  healthcheck {
    test         = ["CMD", "traefik", "healthcheck", "--ping"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "20s"
  }

  security_opts = ["no-new-privileges:true"]
  capabilities {
    drop = ["ALL"]
    add  = ["NET_BIND_SERVICE"]
  }

  dynamic "labels" {
    for_each = local.labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "5" }
}
