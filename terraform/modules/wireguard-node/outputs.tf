# =============================================================================
# Outputs — WireGuard Node
# =============================================================================

output "wireguard_container_id" {
  value       = docker_container.wireguard.id
  description = "ID del contenedor WireGuard en este nodo"
}

output "wireguard_container_name" {
  value       = docker_container.wireguard.name
  description = "Nombre del contenedor WireGuard"
}

output "docker_network_id" {
  value       = docker_network.node_network.id
  description = "ID de la red Docker de este nodo"
}

output "docker_network_name" {
  value       = docker_network.node_network.name
  description = "Nombre de la red Docker"
}

output "docker_subnet" {
  value       = var.docker_subnet
  description = "Subnet Docker de este nodo"
}

output "vpn_gateway_ip" {
  value       = cidrhost(var.vpn_subnet, 1)
  description = "IP del gateway VPN (compartida entre nodos)"
}

output "vpn_subnet" {
  value       = var.vpn_subnet
  description = "Subnet VPN (compartida entre nodos)"
}

output "deployed_services" {
  value       = [for k, v in docker_container.node_services : "${var.node_name}-${k}"]
  description = "Servicios desplegados en este nodo"
}

output "wireguard_config_volume" {
  value       = docker_volume.wireguard_config.name
  description = "Volumen de configuración de WireGuard"
}

output "wireguard_peers_volume" {
  value       = docker_volume.wireguard_peers.name
  description = "Volumen de configuraciones de peers"
}

output "node_summary" {
  value = {
    node_name        = var.node_name
    vpn_subnet       = var.vpn_subnet
    docker_subnet    = var.docker_subnet
    wireguard_container = docker_container.wireguard.name
    services_count   = length(var.services)
  }
  description = "Resumen del nodo"
}
