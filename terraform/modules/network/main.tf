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

  # El provider kreuzwerker/docker marca ipam_config como ForceNew y ve un diff
  # espurio en cada plan (Docker auto-asigna el gateway .1, que queda en el estado
  # pero no se declara aquí) → querría recrear la red siempre. La red es estable;
  # para renumerarla se usa -replace explícito. Ignorar el diff evita recreaciones
  # accidentales en cascada al aplicar otros recursos.
  lifecycle {
    ignore_changes = [ipam_config]
  }
}
