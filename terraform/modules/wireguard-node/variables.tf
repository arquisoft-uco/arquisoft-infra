# =============================================================================
# Variables — Módulo WireGuard Node (Escalable, Multi-servidor)
# =============================================================================
# Este módulo representa UN nodo con WireGuard + Red Docker propia
# Puede ser instanciado múltiples veces para arquitectura distribuida

variable "node_name" {
  description = "Nombre único del nodo (ej: db-server, obs-server, app-server)"
  type        = string
}

variable "domain" {
  description = "Dominio público para endpoint VPN"
  type        = string
}

variable "timezone" {
  description = "Zona horaria para contenedores"
  type        = string
  default     = "America/Bogota"
}

# =============================================================================
# VPN - Configuración compartida entre todos los nodos
# =============================================================================
variable "vpn_subnet" {
  description = "Subnet VPN compartida (TODOS los nodos en esta red)"
  type        = string
  default     = "172.16.0.0/24"
}

variable "wireguard_port" {
  description = "Puerto UDP para WireGuard"
  type        = number
  default     = 51820
}

variable "wireguard_peers" {
  description = "Lista de peers VPN (clientes) - mismo en todos los nodos"
  type        = list(string)
}

variable "expose_vpn_port" {
  description = "Exponer puerto VPN públicamente (false=localhost solo, true=0.0.0.0)"
  type        = bool
  default     = false
}

# =============================================================================
# Red Docker — Única por nodo
# =============================================================================
variable "docker_subnet" {
  description = "Subnet Docker para este nodo (ÚNICA por servidor)"
  type        = string
  # Ejemplos: 172.16.1.0/24, 172.16.2.0/24, 172.16.3.0/24
}

variable "docker_network_name" {
  description = "Nombre de la red Docker en este nodo"
  type        = string
}

# =============================================================================
# Servicios en este nodo (opcional)
# =============================================================================
variable "services" {
  description = "Servicios a desplegar en la red Docker de este nodo"
  type = map(object({
    image = string
    ports = optional(map(number))  # puerto_contenedor = puerto_host
    env   = optional(map(string))
  }))
  default = {}
}

# =============================================================================
# Recursos Docker
# =============================================================================
variable "wireguard_memory" {
  description = "Memoria RAM para contenedor WireGuard (MB)"
  type        = number
  default     = 256
}

variable "wireguard_cpus" {
  description = "CPUs asignados a WireGuard"
  type        = string
  default     = "0.5"
}

variable "wireguard_image" {
  description = "Imagen Docker de WireGuard"
  type        = string
  default     = "linuxserver/wireguard:1.0.20250521-r1-ls116"
}
