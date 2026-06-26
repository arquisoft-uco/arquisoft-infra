# =============================================================================
# Configuración de providers
# =============================================================================
# El provider Docker habla con UN daemon. La portabilidad "servidor propio vs
# cualquier VPS/VM cloud" se logra cambiando SOLO var.docker_host:
#   - dev/local : unix:///var/run/docker.sock
#   - prod/cloud: ssh://usuario@<ip-del-vps>   (Oracle/AWS/Azure/GCP/propio)
# No se hardcodean IPs: viven en el *.tfvars del entorno.
# =============================================================================

provider "docker" {
  host     = var.docker_host
  ssh_opts = var.docker_ssh_opts
}

provider "random" {}
