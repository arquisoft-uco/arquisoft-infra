# =============================================================================
# Módulo alloy — Grafana Alloy (agente de observabilidad independiente)
# =============================================================================
# Corre de forma desacoplada del backend. Descubre logs vía Docker socket
# (label monitoring=arquisoft-backend) y los envía a Loki. Scrape métricas
# del sistema y del actuator y las envía a Prometheus via remote-write.
# Al ser independiente, sigue corriendo durante redespliegues del backend y
# se reconecta automáticamente al nuevo contenedor.
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name"  { type = string }
variable "static_ip" {
  description = "IP estática dentro de la red (endpoint fijo vía VPN). null = dinámica"
  type        = string
  default     = null
}
variable "component_dir" { type = string }

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

resource "docker_image" "alloy" {
  name         = "grafana/alloy:v1.5.1"
  keep_locally = true
}

resource "docker_volume" "alloy_data" {
  name = "arquisoft-alloy-data"
}

resource "docker_container" "alloy" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities]
  }

  name    = "arquisoft-alloy"
  image   = docker_image.alloy.image_id
  restart = "always"
  memory  = 512
  cpus    = "0.5"
  command = ["run", "--storage.path=/var/lib/alloy/data", "/etc/alloy/config.alloy"]

  env = [
    "LOKI_URL=${var.loki_url}",
    "PROMETHEUS_URL=${var.prometheus_url}",
    "BACKEND_TARGET=${var.backend_target}",
  ]

  volumes {
    host_path      = "/var/run/docker.sock"
    container_path = "/var/run/docker.sock"
    read_only      = true
  }
  volumes {
    volume_name    = docker_volume.alloy_data.name
    container_path = "/var/lib/alloy/data"
  }
  upload {
    file    = "/etc/alloy/config.alloy"
    content = file("${var.component_dir}/config/config.alloy")
  }

  networks_advanced {
    name         = var.network_name
    ipv4_address = var.static_ip
  }

  healthcheck {
    test     = ["CMD", "bash", "-c", "echo > /dev/tcp/localhost/12345"]
    interval = "15s"
    timeout  = "5s"
    retries  = 3
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "3" }
}
