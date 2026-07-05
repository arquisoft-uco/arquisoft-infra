# =============================================================================
# Variables — WireGuard VPN module
# =============================================================================

variable "network_name" {
  description = "Nombre de la red Docker compartida"
  type        = string
}

variable "static_ip" {
  description = "IP estática dentro de la red (endpoint fijo vía VPN). null = dinámica"
  type        = string
  default     = null
}

variable "allowed_ips" {
  description = "AllowedIPs de los configs de cliente generados. Split-tunnel (172.16.0.0/16) = alcanza VPN+servicios sin bloquear el internet del cliente. Full-tunnel = 0.0.0.0/0."
  type        = string
  default     = "172.16.0.0/16"
}

variable "peer_dns" {
  description = "DNS de los configs de cliente. Público (1.1.1.1) evita enrutar el DNS del dev por la VPN; usar el gateway (cidrhost(subnet,1)) solo si se requiere resolver nombres internos."
  type        = string
  default     = "1.1.1.1"
}

variable "domain" {
  description = "Dominio público del servidor VPN (vpn.arquisoft.top)"
  type        = string
}

variable "wireguard_port" {
  description = "Puerto UDP para WireGuard (default: 51820, NAT-friendly)"
  type        = number
  default     = 51820
}

variable "wireguard_subnet" {
  description = "Subnet privada de clientes VPN (default: 10.0.0.0/24)"
  type        = string
  default     = "10.0.0.0/24"
}

variable "timezone" {
  description = "Zona horaria de la imagen"
  type        = string
  default     = "America/Bogota"
}

variable "expose_vpn_port" {
  description = "Exponer puerto VPN en todas las IPs (prod: 0.0.0.0, dev: 127.0.0.1)"
  type        = bool
  default     = true
}

variable "peers" {
  description = "Lista de nombres de clientes VPN a provisionar (ej: ['dev1', 'dev2', 'dev3'])"
  type        = list(string)
  default     = ["dev1", "dev2", "dev3"]
}

variable "max_clients" {
  description = "Número máximo de clientes VPN activos simultáneamente"
  type        = number
  default     = 50
}
