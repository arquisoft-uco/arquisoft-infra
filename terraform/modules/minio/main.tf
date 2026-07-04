# =============================================================================
# Módulo minio — Object Storage S3 (consola + API S3 vía Traefik)
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "domain" { type = string }
variable "timezone" { type = string }
variable "minio_root_user" { type = string }
variable "static_ip" {
  description = "IP estática dentro de la red (endpoint fijo vía VPN). null = dinámica"
  type        = string
  default     = null
}
variable "minio_root_password" {
  type      = string
  sensitive = true
}
variable "minio_access_key" { type = string }
variable "minio_secret_key" {
  type      = string
  sensitive = true
}
variable "expose_ports" {
  description = "Exponer puertos 9000 (API S3) y 9001 (consola) directamente en el host (solo dev)"
  type        = bool
  default     = false
}

locals {
  image = "pgsty/minio:RELEASE.2026-04-17T00-00-00Z"
  labels = {
    "traefik.enable"                                               = "true"
    "traefik.http.routers.minio-console.rule"                      = "Host(`minio.${var.domain}`)"
    "traefik.http.routers.minio-console.entrypoints"               = "websecure"
    "traefik.http.routers.minio-console.tls"                       = "true"
    "traefik.http.routers.minio-console.tls.certresolver"          = "letsencrypt"
    "traefik.http.routers.minio-console.service"                   = "minio-console"
    "traefik.http.routers.minio-console.middlewares"               = "secure-headers@file"
    "traefik.http.services.minio-console.loadbalancer.server.port" = "9001"
    "traefik.http.routers.minio-api.rule"                          = "Host(`s3.${var.domain}`)"
    "traefik.http.routers.minio-api.entrypoints"                   = "websecure"
    "traefik.http.routers.minio-api.tls"                           = "true"
    "traefik.http.routers.minio-api.tls.certresolver"              = "letsencrypt"
    "traefik.http.routers.minio-api.service"                       = "minio-api"
    "traefik.http.services.minio-api.loadbalancer.server.port"     = "9000"
  }
}

resource "docker_image" "minio" {
  name         = local.image
  keep_locally = true
}

resource "docker_volume" "data" {
  name = "arquisoft-minio-data"
}

resource "docker_container" "minio" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name    = "arquisoft-minio"
  image   = docker_image.minio.image_id
  restart = "always"
  memory  = 1024
  cpus    = "1.0"

  command = ["server", "/data", "--console-address", ":9001"]

  env = [
    "MINIO_ROOT_USER=${var.minio_root_user}",
    "MINIO_ROOT_PASSWORD=${var.minio_root_password}",
    "MINIO_SERVER_URL=https://s3.${var.domain}",
    "MINIO_BROWSER_REDIRECT_URL=https://minio.${var.domain}",
    "TZ=${var.timezone}",
  ]

  security_opts = ["no-new-privileges:true"]

  volumes {
    volume_name    = docker_volume.data.name
    container_path = "/data"
  }

  dynamic "ports" {
    for_each = var.expose_ports ? [
      { internal = 9000, external = 9000 },
      { internal = 9001, external = 9001 },
    ] : []
    content {
      internal = ports.value.internal
      external = ports.value.external
    }
  }

  networks_advanced {
    name         = var.network_name
    aliases      = ["minio"]
    ipv4_address = var.static_ip
  }

  healthcheck {
    test         = ["CMD", "mcli", "ready", "local"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "30s"
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

# Inicializa buckets y la cuenta de servicio del backend. Espera a que MinIO
# esté listo (bucle until), luego crea recursos y termina (one-shot).
resource "docker_container" "minio_init" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name       = "arquisoft-minio-init"
  image      = docker_image.minio.image_id
  restart    = "no"
  must_run   = false
  depends_on = [docker_container.minio]

  env = [
    "MINIO_ROOT_USER=${var.minio_root_user}",
    "MINIO_ROOT_PASSWORD=${var.minio_root_password}",
    "BACKEND_S3_ACCESS_KEY=${var.minio_access_key}",
    "BACKEND_S3_SECRET_KEY=${var.minio_secret_key}",
  ]

  entrypoint = ["/bin/sh", "-c", <<-EOT
    set -e
    until mcli alias set local http://minio:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null 2>&1; do
      echo 'esperando a minio...'; sleep 2;
    done
    mcli mb --ignore-existing local/artefactos
    mcli mb --ignore-existing local/avatars
    mcli mb --ignore-existing local/backups
    mcli anonymous set download local/avatars
    if [ -n "$BACKEND_S3_ACCESS_KEY" ] && [ -n "$BACKEND_S3_SECRET_KEY" ]; then
      mcli admin user add local "$BACKEND_S3_ACCESS_KEY" "$BACKEND_S3_SECRET_KEY" || true
      mcli admin policy attach local readwrite --user "$BACKEND_S3_ACCESS_KEY" || true
      echo 'Cuenta de servicio del backend lista'
    fi
    echo 'Buckets inicializados'
  EOT
  ]

  networks_advanced {
    name = var.network_name
  }
}

output "alias" { value = "minio" }
output "endpoint" { value = "http://minio:9000" }
