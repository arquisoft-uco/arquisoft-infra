variable "name" {
  description = "Nombre de la red Docker compartida"
  type        = string
  default     = "arquisoft-network"
}

variable "subnet" {
  description = "Subnet CIDR explícita para la red (ej. 172.16.1.0/24). Si es null, Docker asigna del pool por defecto."
  type        = string
  default     = null
}
