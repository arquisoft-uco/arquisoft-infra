# =============================================================================
# Módulo backend — Spring Boot + Grafana Alloy (sidecar)
# =============================================================================
terraform {
  required_providers {
    docker = { source = "kreuzwerker/docker", version = "~> 3.0" }
  }
}

variable "network_name" { type = string }
variable "component_dir" { type = string } # components/backend (config.alloy)
variable "domain" { type = string }

variable "image" { type = string }
variable "tag" { type = string }
variable "spring_profile" {
  type    = string
  default = "prod"
}

# Hosts de dependencias (alias de red por defecto; en multi-servidor, IP privada)
variable "postgres_host" {
  type    = string
  default = "postgres"
}
variable "rabbitmq_host" {
  type    = string
  default = "rabbitmq"
}
variable "redis_host" {
  type    = string
  default = "redis"
}
variable "minio_endpoint" {
  type    = string
  default = "http://minio:9000"
}

# Issuer Keycloak: vacío => https://auth.<domain> (debe coincidir con KC_HOSTNAME)
variable "keycloak_url" {
  type    = string
  default = ""
}
variable "keycloak_realm" { type = string }
variable "keycloak_client_id" { type = string }
variable "keycloak_client_secret" {
  type      = string
  sensitive = true
}

variable "app_db_user" { type = string }
variable "app_db_password" {
  type      = string
  sensitive = true
}
variable "rabbitmq_user" { type = string }
variable "rabbitmq_password" {
  type      = string
  sensitive = true
}
variable "redis_password" {
  type      = string
  sensitive = true
}
variable "minio_access_key" { type = string }
variable "minio_secret_key" {
  type      = string
  sensitive = true
}

variable "loki_url" { type = string }
variable "prometheus_url" { type = string }
variable "backend_target" { type = string }
variable "java_tool_options" {
  type    = string
  default = "-XX:MaxRAMPercentage=70.0 -XX:InitialRAMPercentage=40.0"
}

locals {
  keycloak_url = var.keycloak_url != "" ? var.keycloak_url : "https://auth.${var.domain}"

  # 7 BDs por bounded context: prefijo de env -> nombre de BD
  db_map = {
    USUARIOS        = "usuarios"
    FICHAS          = "fichas_perfil"
    PROYECTOS       = "proyectos_grado"
    ARTEFACTOS      = "artefactos"
    REPO_ARTEFACTOS = "repositorio_artefactos"
    ENTREGABLES     = "entregables"
    EVALUACIONES    = "evaluaciones"
  }

  db_env = flatten([
    for k, db in local.db_map : [
      "DB_${k}_URL=jdbc:postgresql://${var.postgres_host}:5432/${db}",
      "DB_${k}_USERNAME=${var.app_db_user}",
      "DB_${k}_PASSWORD=${var.app_db_password}",
    ]
  ])

  backend_env = concat(local.db_env, [
    "SPRING_PROFILES_ACTIVE=${var.spring_profile}",
    "RABBITMQ_HOST=${var.rabbitmq_host}",
    "RABBITMQ_PORT=5672",
    "RABBITMQ_USERNAME=${var.rabbitmq_user}",
    "RABBITMQ_PASSWORD=${var.rabbitmq_password}",
    "REDIS_HOST=${var.redis_host}",
    "REDIS_PORT=6379",
    "REDIS_USER=default",
    "REDIS_PASSWORD=${var.redis_password}",
    "KEYCLOAK_AUTH_SERVER_URL=${local.keycloak_url}",
    "KEYCLOAK_URL=${local.keycloak_url}",
    "KEYCLOAK_REALM=${var.keycloak_realm}",
    "KEYCLOAK_CLIENT_ID=${var.keycloak_client_id}",
    "KEYCLOAK_CLIENT_SECRET=${var.keycloak_client_secret}",
    "MINIO_ENDPOINT=${var.minio_endpoint}",
    "MINIO_ACCESS_KEY=${var.minio_access_key}",
    "MINIO_SECRET_KEY=${var.minio_secret_key}",
    "CORS_ALLOWED_ORIGINS=https://${var.domain},https://api.${var.domain}",
    "JAVA_TOOL_OPTIONS=${var.java_tool_options}",
  ])

  backend_labels = {
    "monitoring"                                             = "arquisoft-backend"
    "traefik.enable"                                         = "true"
    "traefik.http.routers.backend.rule"                      = "Host(`api.${var.domain}`)"
    "traefik.http.routers.backend.entrypoints"               = "websecure"
    "traefik.http.routers.backend.tls"                       = "true"
    "traefik.http.routers.backend.tls.certresolver"          = "letsencrypt"
    "traefik.http.routers.backend.middlewares"               = "secure-headers@file"
    "traefik.http.services.backend.loadbalancer.server.port" = "8080"
  }
}

resource "docker_image" "backend" {
  name         = "${var.image}:${var.tag}"
  keep_locally = true
}

resource "docker_container" "backend" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
  }

  name    = "arquisoft-backend"
  image   = docker_image.backend.image_id
  restart = "always"
  memory  = 2048
  cpus    = "2.0"

  env = local.backend_env

  networks_advanced {
    name    = var.network_name
    aliases = ["backend", "arquisoft-backend"]
  }

  # Sin healthcheck propio: la imagen ya define HEALTHCHECK en /api/actuator/health.

  dynamic "labels" {
    for_each = local.backend_labels
    content {
      label = labels.key
      value = labels.value
    }
  }

  log_driver = "json-file"
  log_opts   = { max-size = "10m", max-file = "5" }
}

# ---------------- Grafana Alloy (sidecar de observabilidad) ----------------
resource "docker_image" "alloy" {
  name         = "grafana/alloy:v1.5.1"
  keep_locally = true
}

resource "docker_volume" "alloy_data" {
  name = "arquisoft-alloy-data"
}

resource "docker_container" "alloy" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities] # drift calculado por el daemon Docker
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
    name = var.network_name
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

output "alias" { value = "arquisoft-backend" }
