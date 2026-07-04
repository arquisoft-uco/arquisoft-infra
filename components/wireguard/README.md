# WireGuard VPN — Acceso Seguro a Infraestructura

VPN moderna y segura basada en **WireGuard** para que desarrolladores accedan a:
- 🔒 Bases de datos (PostgreSQL en 10.0.0.x)
- 📊 Observabilidad (Grafana, Prometheus en 10.0.0.x)
- 🐰 APIs internas (RabbitMQ, Redis en 10.0.0.x)
- 🔑 Keycloak y otros servicios internos

## Arquitectura

```
Desarrollador (laptop/desktop)
  ↓ WireGuard client (10.0.0.2-254)
  ↓ Encriptado (UDP 51820)
  ↓
VPN Gateway (Oracle/VPS) → 10.0.0.1
  ├─ Forwarding habilitado (net.ipv4.ip_forward=1)
  ├─ Enruta tráfico 10.0.0.0/24 → servicios internos
  └─ Cortafuegos permite solo puertos específicos
  
Servicios internos (red Docker arquisoft-network)
  ├─ postgres:5432 (10.0.0.254)
  ├─ redis:6379 (10.0.0.254)
  ├─ rabbitmq:5672 (10.0.0.254)
  └─ grafana:3000, loki:3100, etc. (10.0.0.254)
```

## Deployment

### Opción 1: Vía Terraform (RECOMENDADO)

```bash
# 1. Generar .env (incluye contraseñas)
./setup-env.sh prod vpn.arquisoft.top admin@arquisoft.top

# 2. Aplicar Terraform (crea + configura WireGuard)
terraform -chdir=terraform apply -target=module.wireguard

# 3. Extraer configuraciones de clientes
docker exec arquisoft-wireguard ls -la /config/peer_confs
docker cp arquisoft-wireguard:/config/peer_confs ./clientes
```

### Opción 2: Docker Compose standalone

```bash
# Setup manual de .env
export WIREGUARD_HOST="vpn.arquisoft.top"
export WIREGUARD_PORT=51820
export WIREGUARD_SUBNET="10.0.0.0/24"
export TZ="America/Bogota"
export PEERS="dev1,dev2,dev3"

# Deploy
docker compose up -d
```

## Provisioning de Clientes

La imagen `linuxserver/wireguard` **genera automáticamente** configs de clientes:

```bash
# Ver clientes generados
docker exec arquisoft-wireguard ls /config/peer_confs

# Extraer config de un cliente (para email/distribución)
docker exec arquisoft-wireguard cat /config/peer_confs/dev1/dev1.conf

# Ver QR para conectarse (si está disponible)
docker exec arquisoft-wireguard cat /config/peer_confs/dev1/dev1.png
```

## Configuración del Cliente

### En Linux/macOS

```bash
# 1. Instalar WireGuard
# macOS: brew install wireguard-tools
# Ubuntu/Debian: sudo apt install wireguard wireguard-tools

# 2. Copiar config desde el servidor
scp oracle@vpn.arquisoft.top:~/clientes/dev1/dev1.conf /etc/wireguard/
sudo chmod 600 /etc/wireguard/dev1.conf

# 3. Conectar
sudo wg-quick up dev1

# 4. Verificar
sudo wg show dev1
sudo ip addr show dev1
```

### En Windows

1. Descargar WireGuard: https://www.wireguard.com/install/
2. Importar config `dev1.conf` 
3. Activar

### En iOS/Android

1. Generar QR desde el servidor
2. Escanear con WireGuard app
3. Conectar

## Enrutamiento de Servicios Internos

En el servidor VPN, agregar rutas estáticas a la subnet 10.0.0.0/24:

```bash
# SSH al servidor
ssh oracle

# Verificar interfaces de red
ip addr show
# → VPN interface: wg0 (10.0.0.1)
# → Docker interface: docker0 (172.17.0.1)

# Agregar ruta Docker ↔ VPN (si es necesario)
sudo ip route add 10.0.0.0/24 dev wg0
sudo ip route add 172.17.0.0/16 dev docker0

# Persistir en /etc/netplan (Debian/Ubuntu) o /etc/network/interfaces
```

## Seguridad (Best Practices)

### Firewall del Servidor

```bash
# Solo permitir puerto VPN desde internet
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 51820/udp  # VPN
sudo ufw allow 22/tcp     # SSH

# Bloquear acceso directo a servicios internos desde internet
# (solo accesibles desde VPN)
sudo ufw deny 5432  # PostgreSQL
sudo ufw deny 6379  # Redis
sudo ufw deny 3000  # Grafana (acceso via Traefik solamente)
```

### Validación de Clientes

- Cada cliente tiene keypair único (Ed25519 + Curve25519)
- Configs se regen en cada `docker compose up` (usar `PEERS=` con lista fija)
- Revocar cliente: eliminar archivo `/config/peer_confs/<peer_name>/`

### Monitoreo

```bash
# Ver conexiones activas
docker exec arquisoft-wireguard wg show all

# Ver logs del contenedor
docker logs -f arquisoft-wireguard

# Monitoreo con Prometheus (si está configurado)
# WireGuard expone métricas en /metrics (si prometheus-wg-exporter está enable)
```

## Troubleshooting

### "No se puede alcanzar BD desde el cliente"

```bash
# En el servidor VPN
docker exec arquisoft-wireguard wg show

# Verificar que:
# - Cliente tiene peer_key en el servidor
# - Allowed IPs incluye subnet VPN (10.0.0.0/24)
# - IP del cliente es 10.0.0.2+

# En el cliente
sudo wg show dev1
# → Debe mostrar estado "last handshake" reciente
```

### "Conexión lenta"

- VPN usa UDP (faster than TCP)
- Si hay packet loss, revisar MTU: `ip link show dev wg0`
- Ajustar si es necesario: `ip link set dev wg0 mtu 1420`

### "DNS no funciona"

- Cliente debe usar `PEERDNS=10.0.0.1` (resolvedor interno)
- O configurar manualmente en cliente: `10.0.0.1` como nameserver

## Recursos de Referencias

- [WireGuard Official Docs](https://www.wireguard.com/)
- [linuxserver/wireguard](https://docs.linuxserver.io/images/docker-wireguard/)
- [WireGuard Performance](https://www.wireguard.com/performance/)
- [WireGuard Cryptography](https://www.wireguard.com/protocol/)
