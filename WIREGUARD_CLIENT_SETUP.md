# Guía Rápida: Configuración del Cliente WireGuard

**Para:** Desarrolladores queriendo conectarse a la infraestructura de Arquisoft  
**Tiempo:** ~5 minutos  
**Prerrequisitos:** Terminal de Linux/macOS o PowerShell (Windows)

---

## 🚀 Configuración Rápida (Linux/macOS)

### PASO 1: Instalar WireGuard

```bash
# Ubuntu/Debian/Pop!_OS
sudo apt update
sudo apt install -y wireguard wireguard-tools resolvconf

# macOS
brew install wireguard-tools
```

### PASO 2: Obtener Archivo de Configuración

Solicita el archivo `peer_dev1.conf` a tu líder técnico (vía email, Slack, etc.)

**El archivo debe tener este contenido (solo el tuyo será diferente):**

```ini
[Interface]
Address = 172.16.0.2                    # tu IP asignada (172.16.0.x)
PrivateKey = <clave-privada-del-peer>
ListenPort = 51820
DNS = 172.16.0.1                        # CoreDNS interno (NO una IP pública)

[Peer]
PublicKey = <clave-pública-del-servidor>
PresharedKey = <preshared-key>
Endpoint = arquisoft.top:51820
AllowedIPs = 172.16.0.0/16
```

⚠️ **CRÍTICO:**
- `AllowedIPs = 172.16.0.0/16` (NO `0.0.0.0/0`).
- `DNS = 172.16.0.1` (CoreDNS interno). **NO** una IP pública como `1.1.1.1`: rompería tu DNS al
  conectar (ver "Pierdo Internet al Conectar"). El servidor ya lo genera bien con `peer_dns=auto`.

### PASO 3: Instalar en el Sistema

**Recomendado — traer el `.conf` directo del servidor** (fuente de verdad; evita copias locales
desactualizadas, causa típica del "pierdo internet"). Requiere acceso SSH (`ssh oracle` o equiv.):
```bash
ssh oracle 'docker exec arquisoft-wireguard cat /config/peer_dev1/peer_dev1.conf' \
  | sudo tee /etc/wireguard/dev1.conf >/dev/null
sudo chmod 600 /etc/wireguard/dev1.conf
```
Este mismo comando es el **procedimiento de refresco** cuando el servidor regenera claves/DNS.

**Alternativo — si te pasaron el archivo:**
```bash
sudo cp ~/Downloads/peer_dev1.conf /etc/wireguard/dev1.conf
sudo chmod 600 /etc/wireguard/dev1.conf
```

### PASO 4: Conectar

```bash
sudo wg-quick up dev1
```

**Salida esperada:**
```
[#] ip link add dev1 type wireguard
[#] wg setconf dev1 /dev/fd/63
[#] ip -4 address add 172.16.0.2/32 dev dev1
...
```

### PASO 5: Verificar Funcionamiento

```bash
# Test 1: ¿Internet funciona?
ping google.com

# Test 2: ¿Puedo alcanzar infraestructura?
ping 172.16.0.1

# Test 3: Ver estado de VPN
sudo wg show dev1

# Test 4: Acceso a BD (si tienes permisos)
psql -h 172.16.1.10 -U postgres -c "SELECT version();"
```

**Resultados esperados:**

```
✅ Ping google.com: ~20-30ms (internet normal)
✅ Ping 172.16.0.1: <1ms (infraestructura)
✅ psql: Conexión exitosa a BD
```

### PASO 6: Desconectar (cuando necesites)

```bash
sudo wg-quick down dev1
```

### PASO 7 (Opcional): Conectar Automáticamente en Boot

```bash
sudo systemctl enable wg-quick@dev1
sudo systemctl start wg-quick@dev1
```

---

## 🪟 Configuración Rápida (Windows)

1. Descargar WireGuard: https://www.wireguard.com/install/
2. Instalar y abrir
3. `Add Tunnel` → Seleccionar `peer_dev1.conf`
4. Click `Activate`
5. Verificar en PowerShell: `wg show`

---

## 🍎 Configuración Rápida (macOS)

1. `brew install wireguard-tools`
2. Copiar `peer_dev1.conf` a `~/.wireguard/`
3. Ejecutar:
   ```bash
   sudo wg-quick up dev1
   ```
4. Verificar: `sudo wg show dev1`

---

## ❌ Problemas Comunes

### "Pierdo Internet al Conectar"

**Causa más común — DNS.** Si el `.conf` trae `DNS = 1.1.1.1` (IP pública), `wg-quick` crea el
dominio catch-all `~.` y enruta TODO el DNS por el túnel split → no resuelve nada (`resolvectl
query github.com` falla), aunque la conectividad IP siga. Fix definitivo (infra):
`wireguard_peer_dns = "auto"` → el `.conf` sale con `DNS = 172.16.0.1`; reinstala el `.conf` del
servidor (PASO 3) y reconecta. Temporal: `sudo resolvectl domain dev1 ''`.

**Otra causa — routing** (`AllowedIPs = 0.0.0.0/0`):
```bash
sudo wg-quick down dev1
sudo nano /etc/wireguard/dev1.conf
# Cambiar: AllowedIPs = 0.0.0.0/0  →  AllowedIPs = 172.16.0.0/16
sudo wg-quick up dev1
```

### "No Tengo Permisos para Instalar"

Abre una terminal real en tu máquina (no en IDE):
```bash
Ctrl+Alt+T
sudo apt update
sudo apt install -y wireguard wireguard-tools
```

### "No Veo VPN en Panel de Red"

Es normal. Funciona desde terminal. Ejecuta:
```bash
ip link show dev1  # Debe mostrar: UP, LOWER_UP
ping 172.16.0.1      # Debe responder
```

### "No Puedo Conectar a BD (PostgreSQL)"

```bash
# 1. Verificar VPN está activa
sudo wg show dev1
# Debe mostrar "latest handshake" reciente

# 2. Probar ping
ping 172.16.0.1

# 3. Intentar conexión (usuario de app; ver credenciales con terraform output)
psql -h 172.16.1.10 -U arquisoft_user -d usuarios -c "SELECT 1;"
```

---

## 🔧 Comandos Útiles

```bash
# Ver estado VPN
sudo wg show dev1

# Ver logs
sudo journalctl -u wg-quick@dev1 -f

# Desconectar
sudo wg-quick down dev1

# Conectar
sudo wg-quick up dev1

# Ver status del servicio
sudo systemctl status wg-quick@dev1

# Editar configuración
sudo nano /etc/wireguard/dev1.conf

# Ver IP asignada
ip addr show dev1

# Pruebas de conectividad
ping 172.16.0.1            # Gateway VPN
ping 8.8.8.8             # Internet
ping 172.16.1.10          # Host servidor
```

---

## 📝 Checklist de Configuración

- [ ] WireGuard instalado
- [ ] Archivo `peer_dev1.conf` descargado y copiado
- [ ] Permisos correctos: `sudo chmod 600 /etc/wireguard/dev1.conf`
- [ ] Conectado: `sudo wg-quick up dev1`
- [ ] Internet funciona: `ping google.com` → <50ms
- [ ] Infraestructura accesible: `ping 172.16.0.1` → <5ms
- [ ] AllowedIPs correcto: `grep AllowedIPs /etc/wireguard/dev1.conf` → `172.16.0.0/16`
- [ ] Estado mostrado: `sudo wg show dev1` → `latest handshake` reciente

---

## 🆘 Soporte

Si tienes problemas:

1. Ejecuta: `sudo wg show dev1`
2. Ejecuta: `ping 172.16.0.1`
3. Ejecuta: `ping 8.8.8.8`
4. Contacta al equipo de infraestructura con los resultados

---

## 📚 Más Información

- Documentación completa: `components/wireguard/README.md`
- Troubleshooting detallado: `DEPLOYMENT_WIREGUARD.md`
- Versiones de imagen: `WIREGUARD_VERSION_MANAGEMENT.md`

---

**Última actualización:** 2026-07-04  
**Autor:** Equipo de Infraestructura Arquisoft
