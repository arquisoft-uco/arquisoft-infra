# =============================================================================
# Composición raíz — wiring de módulos
# =============================================================================
# Patrón: módulos base (network, secrets) producen outputs que se inyectan a los
# módulos de servicio. Los servicios se descubren por alias de red (nombre de
# servicio), nunca por IP.
# =============================================================================

locals {
  network_name = "arquisoft-network"
}

module "network" {
  source = "./modules/network"
  name   = local.network_name
  subnet = var.docker_subnet
}

module "secrets" {
  source           = "./modules/secrets"
  provided_secrets = var.provided_secrets
}

locals {
  # Rutas absolutas a los componentes (fuente de configs reutilizada por los módulos)
  components_dir = abspath("${path.module}/../components")
  secrets        = module.secrets.values

  # IPs estáticas de servicios dentro de docker_subnet → endpoints fijos vía VPN
  # (DBeaver, apps locales). null cuando docker_subnet es null (dev): Docker asigna.
  svc_ip = var.docker_subnet == null ? {} : {
    postgres    = cidrhost(var.docker_subnet, 10)
    keycloak_db = cidrhost(var.docker_subnet, 11)
    redis       = cidrhost(var.docker_subnet, 12)
    rabbitmq    = cidrhost(var.docker_subnet, 13)
    minio       = cidrhost(var.docker_subnet, 14)
    keycloak    = cidrhost(var.docker_subnet, 15)
    grafana     = cidrhost(var.docker_subnet, 16)
    prometheus  = cidrhost(var.docker_subnet, 17)
    loki        = cidrhost(var.docker_subnet, 18)
    alloy       = cidrhost(var.docker_subnet, 19)
    traefik     = cidrhost(var.docker_subnet, 20)
    wireguard   = cidrhost(var.docker_subnet, 21)
  }
}

# ---------- Datos ----------
module "postgres" {
  source            = "./modules/postgres"
  network_name      = module.network.name
  component_dir     = "${local.components_dir}/postgres"
  postgres_user     = var.postgres_user
  postgres_db       = var.postgres_db
  postgres_password = local.secrets["postgres_password"]
  app_db_user       = var.app_db_user
  app_db_password   = local.secrets["app_db_password"]
  expose_ports      = var.expose_data_ports
  static_ip         = lookup(local.svc_ip, "postgres", null)
}

module "redis" {
  source         = "./modules/redis"
  network_name   = module.network.name
  redis_password = local.secrets["redis_password"]
  expose_ports   = var.expose_data_ports
  static_ip      = lookup(local.svc_ip, "redis", null)
}

module "rabbitmq" {
  source            = "./modules/rabbitmq"
  network_name      = module.network.name
  component_dir     = "${local.components_dir}/rabbitmq"
  domain            = var.domain
  rabbitmq_user     = var.rabbitmq_user
  rabbitmq_password = local.secrets["rabbitmq_password"]
  rabbitmq_vhost    = var.rabbitmq_vhost
  expose_ports      = var.expose_data_ports
  static_ip         = lookup(local.svc_ip, "rabbitmq", null)
}

module "minio" {
  source              = "./modules/minio"
  network_name        = module.network.name
  domain              = var.domain
  timezone            = var.timezone
  minio_root_user     = var.minio_root_user
  minio_root_password = local.secrets["minio_root_password"]
  minio_access_key    = var.minio_access_key
  minio_secret_key    = local.secrets["minio_secret_key"]
  expose_ports        = var.expose_data_ports
  static_ip           = lookup(local.svc_ip, "minio", null)
}

# ---------- Identidad ----------
module "keycloak" {
  source                 = "./modules/keycloak"
  network_name           = module.network.name
  component_dir          = "${local.components_dir}/keycloak"
  domain                 = var.domain
  realm_name             = var.keycloak_realm
  admin_user             = var.keycloak_admin_user
  admin_password         = local.secrets["keycloak_admin_password"]
  db_user                = var.keycloak_db_user
  db_name                = var.keycloak_db_name
  db_password            = local.secrets["keycloak_db_password"]
  client_id              = var.keycloak_client_id
  client_secret          = local.secrets["keycloak_client_secret"]
  kc_db_static_ip        = lookup(local.svc_ip, "keycloak_db", null)
  keycloak_static_ip     = lookup(local.svc_ip, "keycloak", null)
}

# ---------- Observabilidad ----------
module "observability" {
  source                 = "./modules/observability"
  network_name           = module.network.name
  component_dir          = "${local.components_dir}/observability"
  domain                 = var.domain
  grafana_admin_user     = var.grafana_admin_user
  grafana_admin_password = local.secrets["grafana_admin_password"]
  loki_static_ip         = lookup(local.svc_ip, "loki", null)
  prometheus_static_ip   = lookup(local.svc_ip, "prometheus", null)
  grafana_static_ip      = lookup(local.svc_ip, "grafana", null)
}

# ---------- Proxy (Traefik) ----------
module "proxy" {
  source        = "./modules/proxy"
  network_name  = module.network.name
  component_dir = "${local.components_dir}/proxy"
  domain        = var.domain
  acme_email    = var.acme_email
  timezone      = var.timezone
  admin_user    = var.admin_auth_user
  admin_bcrypt  = module.secrets.admin_auth_bcrypt
  static_ip     = lookup(local.svc_ip, "traefik", null)
}

# ---------- Alloy (agente de observabilidad) ----------
module "alloy" {
  source         = "./modules/alloy"
  network_name   = module.network.name
  component_dir  = "${local.components_dir}/alloy"
  loki_url       = var.loki_url
  prometheus_url = var.prometheus_url
  backend_target = var.backend_target
  static_ip      = lookup(local.svc_ip, "alloy", null)
}

# ---------- VPN (WireGuard) — Acceso seguro a infraestructura ----------
module "wireguard" {
  source             = "./modules/wireguard"
  network_name       = module.network.name
  domain             = var.domain
  wireguard_port     = var.wireguard_port
  wireguard_subnet   = var.wireguard_subnet
  timezone           = var.timezone
  expose_vpn_port    = var.expose_vpn_port  # VPN pública (punto de entrada seguro), independiente de los puertos de datos
  peers              = var.wireguard_peers
  max_clients        = var.wireguard_max_clients
  static_ip          = lookup(local.svc_ip, "wireguard", null)
  allowed_ips        = var.wireguard_allowed_ips  # split-tunnel: no bloquea internet del cliente
  peer_dns           = var.wireguard_peer_dns     # público: no enruta el DNS del dev por la VPN
}

# ---------- Preparación de red del servidor (firewall) ----------
module "server_prep" {
  source               = "./modules/server_prep"
  enabled              = var.enable_server_prep
  role                 = "--public"
  firewall_script      = abspath("${path.module}/../firewall.sh")
  ssh_host             = var.ssh_host
  ssh_user             = var.ssh_user
  ssh_private_key_path = var.ssh_private_key_path
}
