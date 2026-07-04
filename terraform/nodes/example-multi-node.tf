# =============================================================================
# Ejemplo: Arquitectura Multi-nodo Escalable con WireGuard
# =============================================================================
# Este archivo muestra cómo desplegar múltiples servidores con WireGuard
# Cada servidor tiene su propia red Docker pero todos comparten la VPN
#
# Arquitectura:
# - VPN compartida: 172.16.0.0/24 (acceso remoto)
# - Nodo 1 (DB): 172.16.1.0/24 (PostgreSQL, Redis)
# - Nodo 2 (OBS): 172.16.2.0/24 (Grafana, Prometheus)
# - Nodo 3 (APP): 172.16.3.0/24 (Aplicación + tests)

# =============================================================================
# Nodo 1: Base de Datos y Cache
# =============================================================================
module "wireguard_node_db" {
  source = "../modules/wireguard-node"

  node_name            = "db-server"
  domain               = var.domain
  timezone             = var.timezone
  vpn_subnet           = "172.16.0.0/24"
  docker_subnet        = "172.16.1.0/24"
  docker_network_name  = "arquisoft-db-network"
  wireguard_peers      = var.wireguard_peers
  expose_vpn_port      = false  # Solo en desarrollo

  # Servicios de este nodo
  services = {
    postgres = {
      image = "postgres:18-alpine"
      ports = {
        5432 = 5432
      }
      env = {
        POSTGRES_DB       = "arquisoft"
        POSTGRES_USER     = "arquisoft_user"
        POSTGRES_PASSWORD = "cambiar_en_produccion"
      }
    }
    redis = {
      image = "redis:7-alpine"
      ports = {
        6379 = 6379
      }
    }
  }
}

# =============================================================================
# Nodo 2: Observabilidad (Grafana, Prometheus, Loki)
# =============================================================================
module "wireguard_node_obs" {
  source = "../modules/wireguard-node"

  node_name            = "obs-server"
  domain               = var.domain
  timezone             = var.timezone
  vpn_subnet           = "172.16.0.0/24"
  docker_subnet        = "172.16.2.0/24"
  docker_network_name  = "arquisoft-obs-network"
  wireguard_peers      = var.wireguard_peers
  expose_vpn_port      = false

  # Servicios de observabilidad
  services = {
    grafana = {
      image = "grafana/grafana:11.5.0"
      ports = {
        3000 = 3000
      }
      env = {
        GF_SECURITY_ADMIN_PASSWORD = "cambiar_en_produccion"
      }
    }
    prometheus = {
      image = "prom/prometheus:v3.1.0"
      ports = {
        9090 = 9090
      }
    }
    loki = {
      image = "grafana/loki:3.3.2"
      ports = {
        3100 = 3100
      }
    }
  }
}

# =============================================================================
# Nodo 3: Aplicación
# =============================================================================
module "wireguard_node_app" {
  source = "../modules/wireguard-node"

  node_name            = "app-server"
  domain               = var.domain
  timezone             = var.timezone
  vpn_subnet           = "172.16.0.0/24"
  docker_subnet        = "172.16.3.0/24"
  docker_network_name  = "arquisoft-app-network"
  wireguard_peers      = var.wireguard_peers
  expose_vpn_port      = false

  # Servicios de la aplicación
  services = {
    backend = {
      image = var.backend_image != "" ? var.backend_image : "ghcr.io/arquisoft-uco/arquisoft-backend:latest"
      ports = {
        8080 = 8080
      }
      env = {
        SPRING_DATASOURCE_URL = "jdbc:postgresql://postgres:5432/arquisoft"
        SPRING_DATASOURCE_USERNAME = "arquisoft_user"
      }
    }
    frontend = {
      image = var.frontend_image != "" ? var.frontend_image : "ghcr.io/arquisoft-uco/arquisoft-frontend:latest"
      ports = {
        3000 = 3000
      }
    }
  }
}

# =============================================================================
# Outputs combinados
# =============================================================================
output "vpn_architecture" {
  value = {
    vpn_subnet = "172.16.0.0/24"
    nodes = {
      db = {
        subnet    = module.wireguard_node_db.docker_subnet
        services  = ["postgres", "redis"]
        container = module.wireguard_node_db.wireguard_container_name
      }
      obs = {
        subnet    = module.wireguard_node_obs.docker_subnet
        services  = ["grafana", "prometheus", "loki"]
        container = module.wireguard_node_obs.wireguard_container_name
      }
      app = {
        subnet    = module.wireguard_node_app.docker_subnet
        services  = ["backend", "frontend"]
        container = module.wireguard_node_app.wireguard_container_name
      }
    }
  }
  description = "Arquitectura completa multi-nodo"
}
