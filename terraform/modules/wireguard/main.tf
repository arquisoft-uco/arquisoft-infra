# =============================================================================
# WireGuard VPN Module — Acceso seguro a infraestructura desde equipos remotos
# =============================================================================
# Basado en linuxserver/wireguard (multi-arquitectura, bien mantenida)
#
# Características:
# - Criptografía moderna (Curve25519, ChaCha20-Poly1305)
# - Auto-provisioning de clientes con configs individuales
# - Bajo overhead (~50-100MB en uso, 0.5 CPU)
# - UDP puerto 51820 (NAT-friendly)
# - Subnet interna 10.0.0.0/24 para clientes
# - Healthcheck incorporado
# =============================================================================

resource "docker_image" "wireguard" {
  # Versión específica y estable de linuxserver/wireguard
  # Pattern: {wireguard_version}-r{revision}-ls{linuxserver_version}
  #
  # Cambio de versión:
  #  - Editar este valor
  #  - Ejecutar: terraform plan (verificar cambios)
  #  - Ejecutar: docker pull linuxserver/wireguard:NEW_TAG (pre-descargar si prefieres)
  #  - Ejecutar: terraform apply (redeploya contenedor)
  #
  # Historial de versiones disponibles:
  #  https://hub.docker.com/r/linuxserver/wireguard/tags
  #
  # Última actualización: 2026-07-04 (versión 1.0.20250521-r1-ls116)
  name         = "linuxserver/wireguard:1.0.20250521-r1-ls116"
  keep_locally = true
}

resource "docker_volume" "config" {
  name = "arquisoft-wireguard-config"
}

resource "docker_volume" "confs" {
  name = "arquisoft-wireguard-confs"
}

locals {
  peers_str = join(",", var.peers)
}

resource "docker_container" "wireguard" {
  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities]
  }

  name    = "arquisoft-wireguard"
  image   = docker_image.wireguard.image_id
  restart = "always"

  # Recursos ajustados para producción (WireGuard es muy eficiente)
  # Memory: 256MB (incluye buffer para tráfico)
  # CPU: 0.5 (puede servir 100+ clientes simultáneos)
  memory = 256
  cpus   = "0.5"

  # Variables de entorno del contenedor WireGuard
  env = [
    "TZ=${var.timezone}",
    "PUID=1000",
    "PGID=1000",
    # URL pública del servidor VPN (clientes se conectan a esto)
    "SERVERURL=${var.domain}",
    "SERVERPORT=${var.wireguard_port}",
    # Peers a generar automáticamente (configs individuales)
    "PEERS=${local.peers_str}",
    # DNS resolverá a WireGuard (clients usan 10.0.0.1)
    "PEERDNS=${cidrhost(var.wireguard_subnet, 1)}",
    # Subnet interna de clientes
    "INTERNAL_SUBNET=${var.wireguard_subnet}",
    # Permitir que clientes se comuniquen con cualquier red (control en firewall)
    "ALLOWEDIPS=0.0.0.0/0",
    # Log de configuraciones generadas
    "LOG_CONFS=true",
  ]

  # Volúmenes: configs + claves privadas persistentes
  volumes {
    volume_name    = docker_volume.config.name
    container_path = "/config"
  }
  volumes {
    volume_name    = docker_volume.confs.name
    container_path = "/config/peer_confs"
  }

  # Puerto UDP directo en el host (crucial para NAT traversal)
  # En dev, usar 127.0.0.1; en prod, 0.0.0.0 (todas las IPs)
  dynamic "ports" {
    for_each = [1]
    content {
      internal = 51820
      external = var.wireguard_port
      ip       = var.expose_vpn_port ? "0.0.0.0" : "127.0.0.1"
      protocol = "udp"
    }
  }

  # Capabilities necesarios para VPN a nivel kernel
  capabilities {
    add = [
      "NET_ADMIN",   # Crear interfaces de red
      "NET_RAW",     # Trabajo a nivel de paquetes
      "SYS_MODULE",  # Cargar módulos kernel (WireGuard)
    ]
  }

  # Kernel sysctls para IP forwarding (crucial para enrutamiento de tráfico)
  sysctls = {
    "net.ipv4.conf.all.forwarding"     = "1"
    "net.ipv4.conf.default.forwarding" = "1"
  }

  # Conectar a red Docker compartida con otros servicios
  networks_advanced {
    name    = var.network_name
    aliases = ["wireguard", "vpn"]
  }

  # Healthcheck: verificar que WireGuard está operativo
  healthcheck {
    # Comando: verificar que la interfaz wg0 existe y está activa
    test         = ["CMD-SHELL", "wg show all 2>/dev/null | grep -q interface || exit 1"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "20s"
  }

  # Seguridad: sin nuevos privilegios
  security_opts = ["no-new-privileges:true"]

  # Logging centralizado (JSON)
  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }
}

# Output para facilitar acceso a las configuraciones de clientes
# Los usuarios pueden hacer:
#   docker exec arquisoft-wireguard ls /config/peer_confs
#   docker cp arquisoft-wireguard:/config/peer_confs ./clientes
