# =============================================================================
# Outputs — WireGuard VPN module
# =============================================================================

output "alias" {
  description = "Alias de red de WireGuard en Docker"
  value       = "wireguard"
}

output "container_id" {
  description = "ID del contenedor Docker de WireGuard"
  value       = docker_container.wireguard.id
}

output "container_name" {
  description = "Nombre del contenedor WireGuard"
  value       = docker_container.wireguard.name
}

output "vpn_endpoint" {
  description = "Endpoint público del VPN (para clientes: domain:port)"
  value       = "${var.domain}:${var.wireguard_port}"
}

output "vpn_subnet" {
  description = "Subnet privada de clientes VPN"
  value       = var.wireguard_subnet
}

output "config_volume" {
  description = "Volumen Docker donde están las configs de clientes"
  value       = docker_volume.config.name
}

output "peers_volume" {
  description = "Volumen Docker donde están las configuraciones de peers"
  value       = docker_volume.confs.name
}

output "provisioning_command" {
  description = "Comando para extraer configuraciones de clientes"
  value       = "docker exec arquisoft-wireguard ls /config/peer_confs"
}
