output "name" {
  description = "Nombre de la red (para networks_advanced de los servicios)"
  value       = docker_network.this.name
}

output "id" {
  value = docker_network.this.id
}
