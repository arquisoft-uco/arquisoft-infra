# =============================================================================
# Módulo network — red Docker compartida (abstracción de red)
# =============================================================================
# Crea la red como RECURSO de Terraform (no un 'docker network create' suelto).
# Su nombre se expone por output y se inyecta a cada servicio → descubrimiento
# por alias de red, sin hardcodear IPs.
# =============================================================================

resource "docker_network" "this" {
  name   = var.name
  driver = "bridge"

  # Subnet explícita opcional. Se usa para alinear la red al supernet 172.16.0.0/16
  # del esquema VPN (ej. 172.16.1.0/24), permitiendo IPs estáticas y acceso por VPN.
  dynamic "ipam_config" {
    for_each = var.subnet == null ? [] : [var.subnet]
    content {
      subnet = ipam_config.value
    }
  }
}
