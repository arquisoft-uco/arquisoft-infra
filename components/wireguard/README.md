# WireGuard VPN — Acceso Seguro a Infraestructura

VPN moderna y segura basada en **WireGuard** para que desarrolladores accedan a:
- 🔒 Bases de datos (PostgreSQL en 172.16.1.x)
- 📊 Observabilidad (Grafana, Prometheus en 172.16.1.x)
- 🐰 APIs internas (RabbitMQ, Redis en 172.16.1.x)
- 🔑 Keycloak y otros servicios internos

## Arquitectura

```
Desarrollador (laptop/desktop)
  ↓ WireGuard client (172.16.0.2-254)
  ↓ Encriptado (UDP 51820)
  ↓
VPN Gateway (Oracle) → wg0 = 172.16.0.1
  ├─ Forwarding + MASQUERADE (contenedor linuxserver)
  ├─ Enruta 172.16.0.0/16 → servicios internos
  └─ Puerto 51820/udp abierto en el Security List de Oracle Cloud
  
Servicios internos (arquisoft-network = 172.16.1.0/24, IPs estáticas)
  ├─ postgres 172.16.1.10:5432   keycloak-db 172.16.1.11:5432
  ├─ redis    172.16.1.12:6379   rabbitmq    172.16.1.13:5672/15672
  ├─ minio    172.16.1.14:9000   keycloak    172.16.1.15:8080
  └─ grafana  172.16.1.16:3000   prometheus .17  loki .18
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
export WIREGUARD_SUBNET="172.16.0.0/24"
export TZ="America/Bogota"
export PEERS="dev1,dev2,dev3"

# Deploy
docker compose up -d
```

## Provisioning de Clientes

La imagen `linuxserver/wireguard` **genera automáticamente** configs de clientes:

```bash
# Ver clientes generados
docker exec arquisoft-wireguard sh -c 'ls -d /config/peer_*'

# Extraer config de un cliente (para distribución segura)
docker exec arquisoft-wireguard cat /config/peer_dev1/peer_dev1.conf

# Ver QR para conectarse desde móvil
docker exec arquisoft-wireguard cat /config/peer_dev1/peer_dev1.png
```

## Agregar un desarrollador nuevo (acceso VPN)

Los peers se definen en `terraform.tfvars` (`wireguard_peers`); el contenedor
`linuxserver/wireguard` genera la config de cada uno automáticamente.

1. **Añadir su nombre** a `wireguard_peers` en `terraform/terraform.tfvars` (en el
   servidor; `tfvars` es config por-entorno, gitignored):

   ```hcl
   wireguard_peers = ["dev1", "dev2", "dev3", "dev4"]   # ← nuevo: dev4
   ```

2. **Aplicar** (workspace `prod`). Solo recrea el contenedor wireguard (~segundos de
   corte; los peers existentes conservan sus llaves porque viven en el volumen):

   ```bash
   cd terraform && terraform workspace select prod
   terraform apply -target=module.wireguard
   ```

3. **Extraer la config** del nuevo peer:

   ```bash
   docker exec arquisoft-wireguard cat /config/peer_dev4/peer_dev4.conf
   docker exec arquisoft-wireguard cat /config/peer_dev4/peer_dev4.png   # QR móvil
   ```

4. **Enviar tal cual — ya no hace falta ajustar.** El contenedor genera la config
   con `AllowedIPs = 172.16.0.0/16` (split-tunnel: VPN + servicios sin perder
   internet) y `DNS = 1.1.1.1` (público: no enruta el DNS del dev por la VPN), vía
   las variables `wireguard_allowed_ips` / `wireguard_peer_dns`. El `Endpoint` ya
   apunta a `arquisoft.top:51820`.

5. **Enviar por canal SEGURO** — la config contiene la llave privada del dev. NO en
   claro por email/Slack; usar cifrado o un gestor de secretos.

6. El dev instala WireGuard (wireguard.com: Win/Mac/Linux/iOS/Android), importa el
   `.conf` (o escanea el QR) y conecta. Obtiene `172.16.0.x` y alcanza los servicios
   en `172.16.1.x` (cada uno con su propia autenticación).

### Revocar el acceso de un dev

```bash
# Quitar su nombre de wireguard_peers en tfvars, luego:
terraform apply -target=module.wireguard   # el servidor deja de aceptar ese peer
# (opcional) limpiar su config del volumen:
docker exec arquisoft-wireguard rm -rf /config/peer_devX
# verificar:
docker exec arquisoft-wireguard wg show
```

## Configuración del Cliente

### ⚠️ IMPORTANTE: AllowedIPs = `172.16.0.0/16` (split-tunnel)

Usa el supernet completo: cubre los clientes VPN (`172.16.0.x`) **y** la red de
servicios (`172.16.1.x`), sin redirigir tu internet por la VPN.

✅ **Correcto:**
```ini
AllowedIPs = 172.16.0.0/16   # VPN + servicios; tu internet sigue local
```

❌ **Evitar:**
```ini
AllowedIPs = 0.0.0.0/0       # full-tunnel: TODO tu tráfico sale por la VPN
```

---

### En Linux/macOS — Guía Paso a Paso

#### **PASO 1: Instalar WireGuard**

```bash
# Ubuntu/Debian/Pop!_OS
sudo apt update
sudo apt install -y wireguard wireguard-tools resolvconf

# macOS
brew install wireguard-tools
```

#### **PASO 2: Obtener Configuración del Servidor**

```bash
# Descargar desde servidor
scp oracle:/home/ubuntu/arquisoft-infra/peer_dev1/peer_dev1.conf ~/peer_dev1.conf

# O copiar manualmente desde Slack/email
```

**Verificar que contenga:**
```ini
[Interface]
Address = 172.16.0.2
PrivateKey = ...
DNS = 172.16.0.1

[Peer]
PublicKey = ...
Endpoint = arquisoft.top:51820
AllowedIPs = 172.16.0.0/16    # ✅ DEBE SER ESTO, NO 0.0.0.0/0
```

#### **PASO 3: Copiar a Directorio de Sistema**

```bash
# Copiar config
sudo cp ~/peer_dev1.conf /etc/wireguard/dev1.conf

# Ajustar permisos (crucial)
sudo chmod 600 /etc/wireguard/dev1.conf
```

#### **PASO 4: Conectar a VPN**

```bash
sudo wg-quick up dev1
```

**Salida esperada:**
```
[#] ip link add dev1 type wireguard
[#] wg setconf dev1 /dev/fd/63
[#] ip -4 address add 172.16.0.2/32 dev dev1
[#] ip link set mtu 1420 up dev dev1
[#] wg set dev1 fwmark 51820
[#] iptables -t mangle -I FORWARD -o dev1 -j MARK --set-xmark 0xca6c/0xffffffff
[#] iptables -t nat -I POSTROUTING -o dev1 -j MASQUERADE
```

#### **PASO 5: Verificar Conexión**

```bash
# Ver estado de WireGuard
sudo wg show dev1

# Ver IP asignada
ip addr show dev1
# Debe mostrar: inet 172.16.0.2/32 dev dev1

# Test de internet (debe funcionar normalmente)
ping google.com

# Test de infraestructura
ping 172.16.0.1
# Latencia esperada: < 1ms
```

**Salida esperada:**
```
interface: dev1
  public key: ...
  listening port: 51820

peer: 2UB/fw+...
  preshared key: (hidden)
  allowed ips: 172.16.0.0/24
  latest handshake: 2 seconds ago
  transfer: 1.23 MiB received, 5.67 MiB sent
```

#### **PASO 6: Desconectar (cuando sea necesario)**

```bash
sudo wg-quick down dev1
```

#### **PASO 7 (Opcional): Conectar Automáticamente en Boot**

```bash
# Habilitar autoconexión
sudo systemctl enable wg-quick@dev1

# Ver estado
sudo systemctl status wg-quick@dev1

# Ver logs
sudo journalctl -u wg-quick@dev1 -f
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

En el servidor VPN, agregar rutas estáticas a la subnet 172.16.0.0/24:

```bash
# SSH al servidor
ssh oracle

# Verificar interfaces de red
ip addr show
# → VPN interface: wg0 (172.16.0.1)
# → Docker interface: docker0 (172.17.0.1)

# Agregar ruta Docker ↔ VPN (si es necesario)
sudo ip route add 172.16.0.0/24 dev wg0
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

## Troubleshooting — Problemas y Soluciones

### ❌ "Pierdo Internet Cuando Conecto la VPN"

**Causa:** `AllowedIPs = 0.0.0.0/0` redirige TODO el tráfico por VPN.

**Solución:**

1. **Desconectar inmediatamente:**
   ```bash
   sudo wg-quick down dev1
   ```

2. **Verificar configuración:**
   ```bash
   grep "AllowedIPs" /etc/wireguard/dev1.conf
   # Debe mostrar: AllowedIPs = 172.16.0.0/16
   # NO: AllowedIPs = 0.0.0.0/0
   ```

3. **Si está mal, corregir:**
   ```bash
   # Editar archivo
   sudo nano /etc/wireguard/dev1.conf
   
   # Cambiar esta línea:
   # AllowedIPs = 0.0.0.0/0     ← ELIMINAR
   # AllowedIPs = 172.16.0.0/16    ← AGREGAR
   ```

4. **Guardar y reconectar:**
   ```bash
   # Presionar Ctrl+X, luego Y, Enter (en nano)
   sudo wg-quick up dev1
   
   # Verificar internet funciona
   ping google.com
   ```

---

### ❌ "VPN no Aparece en la Sección de Red del Sistema"

**Causa:** `wg-quick` es una herramienta CLI. NetworkManager no la integra automáticamente.

**Solución:** Es normal. La VPN funciona correctamente desde terminal:

```bash
# Verificar que está activa
ip link show dev1
# Debe mostrar: <POINTOPOINT,NOARP,UP,LOWER_UP>

# Probar conectividad
ping 172.16.0.1  # Gateway VPN
ping 8.8.8.8   # Internet
```

**Alternativa (Opcional):** Si quieres que aparezca en GUI, instala plugin de NetworkManager:

```bash
sudo apt install network-manager-wireguard
sudo systemctl restart NetworkManager
```

---

### ❌ "No Tengo Permisos para Ejecutar `sudo apt install`"

**Causa:** En algunos contextos (IDE, shell remota), `sudo` requiere terminal interactiva.

**Solución:**

**Opción A: Ejecutar en Terminal Nueva (Recomendado)**
```bash
# Abre una terminal en tu máquina (no en IDE)
Ctrl+Alt+T

# Ejecuta el comando
sudo apt update
sudo apt install -y wireguard wireguard-tools resolvconf
```

**Opción B: Script Automatizado**
```bash
# En terminal real:
bash /tmp/setup-wireguard.sh
```

---

### ❌ "No se puede alcanzar BD (172.16.1.10)"

**Causas posibles:**

1. **VPN no está conectada:**
   ```bash
   ip link show dev1
   # Debe mostrar: <POINTOPOINT,NOARP,UP,LOWER_UP>
   ```

2. **Firewall del servidor bloquea:**
   ```bash
   # En servidor (ssh oracle):
   sudo ufw status
   
   # Permitir si es necesario:
   sudo ufw allow 5432/tcp  # PostgreSQL
   sudo ufw allow 6379/tcp  # Redis
   ```

3. **Servicio interno no está corriendo:**
   ```bash
   # En servidor:
   docker ps | grep -E "postgres|redis"
   ```

**Solución:**

```bash
# 1. Verificar VPN está conectada
sudo wg show dev1
# → Debe mostrar "latest handshake" reciente

# 2. Verificar conectividad al gateway
ping 172.16.0.1

# 3. Intentar conexión a BD
psql -h 172.16.1.10 -U postgres -c "SELECT 1;"
```

---

### ❌ "Conexión Lenta o Packet Loss"

**Síntomas:**
- Latencia alta (> 100ms)
- Packet loss en ping
- Desconexiones frecuentes

**Soluciones:**

1. **Verificar MTU:**
   ```bash
   ip link show dev1
   # Debe mostrar: mtu 1420
   
   # Si no, ajustar:
   sudo ip link set dev1 mtu 1420
   ```

2. **Verificar endpoint del servidor:**
   ```bash
   grep Endpoint /etc/wireguard/dev1.conf
   # Debe ser: Endpoint = arquisoft.top:51820
   
   # Verificar que resuelve:
   nslookup arquisoft.top
   ```

3. **Revisar logs del servidor:**
   ```bash
   ssh oracle
   docker logs -f arquisoft-wireguard
   ```

4. **Probar latencia:**
   ```bash
   # Ping al gateway
   ping -c 10 172.16.0.1
   # Esperado: < 1ms (conexión local)
   ```

---

### ❌ "DNS no Funciona desde VPN"

**Síntoma:** No puedo resolver nombres (nslookup falla desde VPN)

**Solución:**

1. **Verificar DNS está configurado:**
   ```bash
   grep DNS /etc/wireguard/dev1.conf
   # Debe mostrar: DNS = 172.16.0.1
   ```

2. **Forzar DNS:**
   ```bash
   # Temporal
   sudo systemctl restart systemd-resolved
   
   # Verificar
   resolvectl
   ```

3. **Si sigue sin funcionar, usar DNS público:**
   ```bash
   # Editar config
   sudo nano /etc/wireguard/dev1.conf
   
   # Cambiar DNS:
   # DNS = 172.16.0.1         ← Interno (si falla)
   # DNS = 8.8.8.8 8.8.4.4  ← Google (si necesitas fallback)
   
   # Reconectar
   sudo wg-quick down dev1
   sudo wg-quick up dev1
   ```

---

### ✅ "Verificar que TODO Funciona"

Ejecuta este script para diagnóstico completo:

```bash
#!/bin/bash
echo "=== Verificación WireGuard ==="
echo ""
echo "1. Interfaz VPN:"
ip link show dev1 | grep -E "<.*UP.*>"
echo ""
echo "2. IP Asignada:"
ip addr show dev1 | grep inet
echo ""
echo "3. Internet:"
ping -c 1 8.8.8.8 && echo "✅ Internet OK" || echo "❌ Sin internet"
echo ""
echo "4. Gateway VPN:"
ping -c 1 172.16.0.1 && echo "✅ Gateway OK" || echo "❌ Sin gateway"
echo ""
echo "5. Estado WireGuard:"
sudo wg show dev1 | head -5
```

Guarda como `/tmp/check-vpn.sh` y ejecuta:
```bash
bash /tmp/check-vpn.sh
```

## Recursos de Referencias

- [WireGuard Official Docs](https://www.wireguard.com/)
- [linuxserver/wireguard](https://docs.linuxserver.io/images/docker-wireguard/)
- [WireGuard Performance](https://www.wireguard.com/performance/)
- [WireGuard Cryptography](https://www.wireguard.com/protocol/)
