# 🏗️ Arquitectura WireGuard Escalable Multi-nodo

> **Estado:** Refactor completado - Arquitectura Docker escalable lista para testing

## 📋 Resumen

Esta es una **arquitectura profesional y escalable** para VPN basada en **Docker** que permite:

- ✅ Múltiples servidores con infraestructura distribuida
- ✅ Cada servidor en su propia red Docker aislada
- ✅ Todos conectados por UNA VPN centralizada
- ✅ Acceso remoto a servicios en cualquier servidor
- ✅ Compatible Windows/macOS/Linux
- ✅ Fácil de escalar (agregar nodo = copiar módulo)

---

## 🌐 Topología de Red

```
INTERNET
    │
    └─ Cliente Dev (172.16.0.2)
         │
         └─ VPN Overlay (172.16.0.0/24)
             │
             ├─────────────────┬─────────────────┬──────────────────┐
             │                 │                 │                  │
        ┌────▼────┐       ┌────▼────┐       ┌────▼────┐      ┌────▼────┐
        │ Nodo DB │       │ Nodo OBS │       │ Nodo APP │      │Nodo Custom
        │(172.16.1)       │(172.16.2)       │(172.16.3)       │(172.16.N)
        └────┬────┘       └────┬────┘       └────┬────┘      └────┬────┘
             │                 │                 │                  │
        ┌────▼──────────┐ ┌────▼──────────┐ ┌───▼──────────┐
        │Docker Network │ │Docker Network │ │Docker Network │
        │172.16.1.0/24  │ │172.16.2.0/24  │ │172.16.3.0/24  │
        ├────────────────┤ ├────────────────┤ ├───────────────┤
        │ PostgreSQL     │ │ Grafana        │ │ Backend       │
        │ Redis          │ │ Prometheus     │ │ Frontend      │
        │ RabbitMQ       │ │ Loki           │ │ Tests DB      │
        └────────────────┘ └────────────────┘ └───────────────┘
```

## 🎯 Características Clave

### 1. VPN Centralizada (Compartida)
```
vpn_subnet = "172.16.0.0/24"
```
- Todos los nodos usan la MISMA subnet VPN
- Clientes conectan ONCE a esta red
- Pueden acceder a servicios en CUALQUIER nodo

### 2. Redes Docker Independientes (Por nodo)
```
Nodo DB:   docker_subnet = "172.16.1.0/24"
Nodo OBS:  docker_subnet = "172.16.2.0/24"
Nodo APP:  docker_subnet = "172.16.3.0/24"
```
- Cada nodo aislado en su propia red
- Sin conflictos de IPs
- Fácil de escalar

### 3. Módulo Reutilizable
El módulo `wireguard-node` puede instanciarse múltiples veces:
```hcl
module "wireguard_node_1" {
  source = "../modules/wireguard-node"
  node_name   = "server-1"
  docker_subnet = "172.16.1.0/24"
  services = { ... }
}

module "wireguard_node_2" {
  source = "../modules/wireguard-node"
  node_name   = "server-2"
  docker_subnet = "172.16.2.0/24"
  services = { ... }
}
```

---

## 📁 Estructura de Directorios

```
terraform/
├── modules/
│   ├── wireguard/                    # Módulo original (compatibilidad)
│   │   ├── main.tf
│   │   ├── variables.tf
│   │   ├── outputs.tf
│   │   └── scripts/
│   │
│   └── wireguard-node/               # 🆕 Módulo genérico escalable
│       ├── main.tf                   # Contenedor + red Docker
│       ├── variables.tf              # Configuración flexible
│       ├── outputs.tf                # Información de nodo
│       └── versions.tf               # Providers
│
└── nodes/
    └── example-multi-node.tf         # 🆕 Ejemplo: 3 nodos
        ├── db-server (172.16.1.x)
        ├── obs-server (172.16.2.x)
        └── app-server (172.16.3.x)
```

---

## 🚀 Cómo Usar

### 1. Desplegar Arquitectura de Ejemplo

```bash
cd terraform

# Inicializar
terraform init

# Ver plan
terraform plan -target=module.wireguard_node_db \
              -target=module.wireguard_node_obs \
              -target=module.wireguard_node_app

# Aplicar
terraform apply \
  -target=module.wireguard_node_db \
  -target=module.wireguard_node_obs \
  -target=module.wireguard_node_app
```

### 2. Agregar un Nuevo Nodo

```hcl
# En terraform/nodes/

module "wireguard_node_custom" {
  source = "../modules/wireguard-node"
  
  node_name           = "custom-server"
  domain              = var.domain
  vpn_subnet          = "172.16.0.0/24"
  docker_subnet       = "172.16.4.0/24"  # Nueva subnet
  docker_network_name = "arquisoft-custom-network"
  wireguard_peers     = var.wireguard_peers
  
  services = {
    my_app = {
      image = "my-image:latest"
      ports = { 5000 = 5000 }
    }
  }
}
```

### 3. Conectar un Cliente

```bash
# En máquina cliente

# 1. Descargar config del contenedor WireGuard
docker exec wireguard-db-server cat /config/peer_confs/dev1/dev1.conf > dev1.conf

# 2. Instalar WireGuard
# Windows/macOS: Descargar desde wireguard.com
# Linux: sudo apt install wireguard

# 3. Conectar
sudo wg-quick up ./dev1.conf

# 4. Probar acceso a servicios en TODOS los nodos
ping 172.16.1.5     # PostgreSQL en nodo DB
ping 172.16.2.10    # Grafana en nodo OBS
ping 172.16.3.20    # Backend en nodo APP
```

---

## 🔒 Seguridad

- **VPN Nativa:** WireGuard (Curve25519, ChaCha20-Poly1305)
- **Aislamiento:** Cada nodo en red Docker separada
- **Acceso:** Solo a través de VPN (no puertos expuestos públicamente)
- **Firewall:** ufw configurado en host si es necesario

---

## 📊 Escalabilidad

| Aspecto | Capacidad |
|---------|-----------|
| Nodos | Ilimitado (agregar módulo) |
| Clientes VPN | 254 (172.16.0.2 - 172.16.0.254) |
| Servicios/nodo | Ilimitado (agregar a `services`) |
| Subnets Docker | 65.536 (172.16.0.0/12) |

---

## ✅ Diferencias con FASE 2 (Nativo)

| Aspecto | Docker (Nuevo) | Nativo (FASE 2) |
|---------|--|--|
| **Multi-servidor** | ✅ Trivial | ❌ Complejo |
| **Portabilidad** | ✅ Windows/macOS/Linux | ❌ Linux only |
| **Escalabilidad** | ✅ Excelente | ⚠️ Limitada |
| **Kubernetes** | ✅ Nativo | ❌ Workaround |
| **Performance** | ✅ Excelente (Docker overhead mínimo) | ✅ Máximo |

---

## 🔧 Troubleshooting

### Conectar a VPN desde cliente
```bash
sudo wg-quick up ./config.conf
ip -4 route show table 51820  # Ver rutas
wg show                        # Ver estado WireGuard
```

### Ver logs del contenedor WireGuard
```bash
docker logs -f wireguard-db-server
docker exec wireguard-db-server wg show wg0
```

### Acceder a servicios en nodo remoto
```bash
# PostgreSQL desde cliente VPN (usuario de app; una BD por bounded context)
psql -h 172.16.1.10 -U arquisoft_user -d usuarios

# Redis desde cliente VPN (usuario ACL de app)
redis-cli -h 172.16.1.12 --user arquisoft_backend

# Grafana desde navegador
# http://172.16.2.10:3000
```

---

## 📚 Próximos Pasos

1. ✅ **Testing Local:** Probar con docker-compose en PC
2. ⏳ **Production Deploy:** Terraform en Oracle
3. ⏳ **Kubernetes:** Escalar con K8s
4. ⏳ **Multi-cloud:** Agregar nodos en AWS/GCP

---

## 📄 Referencias

- [WireGuard Official](https://www.wireguard.com/)
- [linuxserver/wireguard Docker](https://hub.docker.com/r/linuxserver/wireguard)
- [Terraform Docker Provider](https://registry.terraform.io/providers/kreuzwerker/docker/latest/docs)
