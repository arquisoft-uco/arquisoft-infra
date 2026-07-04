# =============================================================================
# WireGuard Node — Módulo reutilizable para cada servidor
# =============================================================================
# Despliega:
# 1. Contenedor WireGuard (conexión VPN centralizada)
# 2. Red Docker privada (servicios del nodo)
# 3. Servicios asociados (opcional)
#
# Cada nodo:
# - Conecta a la MISMA VPN (172.16.0.0/24)
# - Tiene ÚNICA red Docker (172.16.1.x, 172.16.2.x, etc)
# - Ofrece sus servicios a través de la VPN

resource "docker_network" "node_network" {
  name   = var.docker_network_name
  driver = "bridge"

  ipam_config {
    subnet = var.docker_subnet
  }
}

# =============================================================================
# Imagen Docker de WireGuard
# =============================================================================
resource "docker_image" "wireguard" {
  name          = var.wireguard_image
  keep_locally  = true
  pull_triggers = [var.wireguard_image]
}

# =============================================================================
# Volúmenes para configuración persistente
# =============================================================================
resource "docker_volume" "wireguard_config" {
  name = "wireguard-${var.node_name}-config"
}

resource "docker_volume" "wireguard_peers" {
  name = "wireguard-${var.node_name}-peers"
}

# =============================================================================
# Contenedor WireGuard
# =============================================================================
resource "docker_container" "wireguard" {
  name    = "wireguard-${var.node_name}"
  image   = docker_image.wireguard.image_id
  restart = "always"

  # Recursos
  memory = var.wireguard_memory
  cpus   = var.wireguard_cpus

  # Variables de entorno
  env = [
    "TZ=${var.timezone}",
    "PUID=1000",
    "PGID=1000",
    "SERVERURL=${var.domain}",
    "SERVERPORT=${var.wireguard_port}",
    "PEERS=${join(",", var.wireguard_peers)}",
    "PEERDNS=${cidrhost(var.vpn_subnet, 1)}",
    "INTERNAL_SUBNET=${var.vpn_subnet}",
    "ALLOWEDIPS=0.0.0.0/0",
    "LOG_CONFS=true",
  ]

  # Volúmenes persistentes
  volumes {
    volume_name    = docker_volume.wireguard_config.name
    container_path = "/config"
  }

  volumes {
    volume_name    = docker_volume.wireguard_peers.name
    container_path = "/config/peer_confs"
  }

  # Puerto VPN
  ports {
    internal = 51820
    external = var.wireguard_port
    ip       = var.expose_vpn_port ? "0.0.0.0" : "127.0.0.1"
    protocol = "udp"
  }

  # Capabilities para VPN
  capabilities {
    add = ["NET_ADMIN", "NET_RAW", "SYS_MODULE"]
  }

  # IP Forwarding
  sysctls = {
    "net.ipv4.conf.all.forwarding"     = "1"
    "net.ipv4.conf.default.forwarding" = "1"
  }

  # Conectar a red Docker del nodo
  networks_advanced {
    name    = docker_network.node_network.name
    aliases = ["wireguard", "vpn"]
  }

  # Healthcheck
  healthcheck {
    test         = ["CMD-SHELL", "wg show all 2>/dev/null | grep -q interface || exit 1"]
    interval     = "30s"
    timeout      = "10s"
    retries      = 3
    start_period = "20s"
  }

  # Seguridad
  security_opts = ["no-new-privileges:true"]

  # Logging
  log_driver = "json-file"
  log_opts = {
    "max-size" = "10m"
    "max-file" = "3"
  }

  lifecycle {
    ignore_changes = [memory_swap, log_opts, capabilities]
  }
}

# =============================================================================
# Servicios adicionales en la red del nodo (opcional)
# =============================================================================
resource "docker_container" "node_services" {
  for_each = var.services

  name    = "${var.node_name}-${each.key}"
  image   = each.value.image
  restart = "always"

  # Conectar a red Docker del nodo
  networks_advanced {
    name = docker_network.node_network.name
  }

  # Puertos (si aplican)
  dynamic "ports" {
    for_each = each.value.ports != null ? each.value.ports : {}
    content {
      internal = ports.key
      external = ports.value
    }
  }

  # Variables de entorno
  env = [
    for k, v in(each.value.env != null ? each.value.env : {}) : "${k}=${v}"
  ]

  depends_on = [docker_container.wireguard]
}
