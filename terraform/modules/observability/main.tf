# =============================================================================
# Módulo observability — Loki + Prometheus + Grafana
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "component_dir" { type = string } # components/observability
variable "domain" { type = string }
variable "obs_bind_ip" {
  description = "IP donde publicar Loki/Prometheus (push de Alloy). Single-server: 127.0.0.1"
  type        = string
  default     = "127.0.0.1"
}
variable "grafana_admin_user" { type = string }
variable "grafana_admin_password" {
  type      = string
  sensitive = true
}

# ---------------- Loki ----------------
resource "docker_image" "loki" {
  name         = "grafana/loki:3.3.2"
  keep_locally = true
}
resource "docker_volume" "loki" { name = "arquisoft-loki-data" }

resource "docker_container" "loki" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name    = "arquisoft-loki"
  image   = docker_image.loki.image_id
  restart = "always"
  memory  = 1536
  command = ["-config.file=/etc/loki/loki-config.yaml"]

  volumes {
    volume_name    = docker_volume.loki.name
    container_path = "/loki"
  }
  upload {
    file    = "/etc/loki/loki-config.yaml"
    content = file("${var.component_dir}/config/loki/loki-config.yaml")
  }

  ports {
    internal = 3100
    external = 3100
    ip       = var.obs_bind_ip
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["loki"]
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -q --spider http://localhost:3100/ready || exit 1"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "3" }
}

# ---------------- Prometheus ----------------
resource "docker_image" "prometheus" {
  name         = "prom/prometheus:v3.1.0"
  keep_locally = true
}
resource "docker_volume" "prometheus" { name = "arquisoft-prometheus-data" }

resource "docker_container" "prometheus" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name    = "arquisoft-prometheus"
  image   = docker_image.prometheus.image_id
  restart = "always"
  memory  = 1024
  command = [
    "--config.file=/etc/prometheus/prometheus.yml",
    "--storage.tsdb.path=/prometheus",
    "--storage.tsdb.retention.time=30d",
    "--web.enable-lifecycle",
    "--web.enable-remote-write-receiver",
  ]

  volumes {
    volume_name    = docker_volume.prometheus.name
    container_path = "/prometheus"
  }
  upload {
    file    = "/etc/prometheus/prometheus.yml"
    content = file("${var.component_dir}/config/prometheus/prometheus.yml")
  }
  upload {
    file    = "/etc/prometheus/alerts.yml"
    content = file("${var.component_dir}/config/prometheus/alerts.yml")
  }

  ports {
    internal = 9090
    external = 9090
    ip       = var.obs_bind_ip
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["prometheus"]
  }

  healthcheck {
    test         = ["CMD", "wget", "-q", "--spider", "http://localhost:9090/-/healthy"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "3" }
}

# ---------------- Grafana ----------------
resource "docker_image" "grafana" {
  name         = "grafana/grafana:11.5.0"
  keep_locally = true
}
resource "docker_volume" "grafana" { name = "arquisoft-grafana-data" }

locals {
  grafana_labels = {
    "traefik.enable"                                         = "true"
    "traefik.http.routers.grafana.rule"                      = "Host(`grafana.${var.domain}`)"
    "traefik.http.routers.grafana.entrypoints"               = "websecure"
    "traefik.http.routers.grafana.tls"                       = "true"
    "traefik.http.routers.grafana.tls.certresolver"          = "letsencrypt"
    "traefik.http.routers.grafana.middlewares"               = "secure-headers@file"
    "traefik.http.services.grafana.loadbalancer.server.port" = "3000"
  }
}

resource "docker_container" "grafana" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name       = "arquisoft-grafana"
  image      = docker_image.grafana.image_id
  restart    = "always"
  memory     = 512
  depends_on = [docker_container.prometheus, docker_container.loki]

  env = [
    "GF_SECURITY_ADMIN_USER=${var.grafana_admin_user}",
    "GF_SECURITY_ADMIN_PASSWORD=${var.grafana_admin_password}",
    "GF_USERS_ALLOW_SIGN_UP=false",
    "GF_AUTH_ANONYMOUS_ENABLED=false",
    "GF_SERVER_ROOT_URL=https://grafana.${var.domain}",
    "GF_INSTALL_PLUGINS=grafana-clock-panel,grafana-piechart-panel",
  ]

  volumes {
    volume_name    = docker_volume.grafana.name
    container_path = "/var/lib/grafana"
  }
  upload {
    file    = "/etc/grafana/provisioning/datasources/datasources.yaml"
    content = file("${var.component_dir}/config/grafana/provisioning/datasources/datasources.yaml")
  }
  upload {
    file    = "/etc/grafana/provisioning/dashboards/dashboards.yaml"
    content = file("${var.component_dir}/config/grafana/provisioning/dashboards/dashboards.yaml")
  }
  upload {
    file    = "/etc/grafana/provisioning/dashboards/json/arquisoft-overview.json"
    content = file("${var.component_dir}/config/grafana/provisioning/dashboards/json/arquisoft-overview.json")
  }

  networks_advanced {
    name    = var.network_name
    aliases = ["grafana"]
  }

  healthcheck {
    test     = ["CMD-SHELL", "wget -q --spider http://localhost:3000/api/health || exit 1"]
    interval = "30s"
    timeout  = "10s"
    retries  = 3
  }

  dynamic "labels" {
    for_each = local.grafana_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "3" }
}

output "grafana_alias" { value = "grafana" }
