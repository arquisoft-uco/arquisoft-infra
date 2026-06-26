# =============================================================================
# Módulo server_prep — preparación de red del servidor (firewall)
# =============================================================================
# Aplica el firewall del host (ufw) vía SSH reutilizando firewall.sh. Abstraído
# por var.role para soportar distintos roles (público/datos/observabilidad).
# En cloud, este módulo se puede sustituir por uno que cree security groups
# nativos (aws_security_group / azurerm_network_security_group / google_compute_firewall)
# sin cambiar el resto de la composición.
# =============================================================================
terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

variable "enabled" {
  type    = bool
  default = false
}
variable "role" {
  description = "Rol del firewall (argumento de firewall.sh): --public | --data-from <ip> | --obs-from <ip>"
  type        = string
  default     = "--public"
}
variable "firewall_script" {
  description = "Ruta absoluta a firewall.sh"
  type        = string
}
variable "ssh_host" { type = string }
variable "ssh_user" { type = string }
variable "ssh_private_key_path" { type = string }

resource "null_resource" "firewall" {
  count = var.enabled ? 1 : 0

  triggers = {
    role = var.role
    host = var.ssh_host
  }

  connection {
    type        = "ssh"
    host        = var.ssh_host
    user        = var.ssh_user
    private_key = file(var.ssh_private_key_path)
  }

  provisioner "file" {
    source      = var.firewall_script
    destination = "/tmp/arquisoft-firewall.sh"
  }

  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/arquisoft-firewall.sh",
      "sudo bash /tmp/arquisoft-firewall.sh ${var.role}",
    ]
  }
}
