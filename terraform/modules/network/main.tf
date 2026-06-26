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
}
