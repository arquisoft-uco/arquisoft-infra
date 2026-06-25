variable "provided_secrets" {
  description = "Secretos externos (Key Vault). Si una clave existe, se usa en vez de la generada."
  type        = map(string)
  default     = {}
  sensitive   = true
}
