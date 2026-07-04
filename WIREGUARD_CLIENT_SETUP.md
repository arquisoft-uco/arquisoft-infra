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
Address = 10.0.0.2
PrivateKey = IGmsBi9i3VAkcoOtFKOgj41/Daz0+DZYBgXsXWXxCWM=
ListenPort = 51820
DNS = 10.0.0.1

[Peer]
PublicKey = 2UB/fw+9tJ9ubCxNZDsntrBw/gNRKrdelTnaijERTjE=
PresharedKey = VfujI7ybCZhpX7DvlBnciQl+h9vbRghvPdJI2BG5LYY=
Endpoint = arquisoft.top:51820
AllowedIPs = 10.0.0.0/24
```

⚠️ **CRÍTICO:** Línea 12 DEBE ser `AllowedIPs = 10.0.0.0/24` (NO `0.0.0.0/0`)

### PASO 3: Copiar a Sistema

```bash
# Crear directorio si no existe
mkdir -p ~/.wireguard

# Copiar archivo (si está en ~/Downloads)
cp ~/Downloads/peer_dev1.conf ~/.wireguard/

# Copiar a directorio del sistema
sudo cp ~/.wireguard/peer_dev1.conf /etc/wireguard/dev1.conf

# Ajustar permisos (importante)
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
[#] ip -4 address add 10.0.0.2/32 dev dev1
...
```

### PASO 5: Verificar Funcionamiento

```bash
# Test 1: ¿Internet funciona?
ping google.com

# Test 2: ¿Puedo alcanzar infraestructura?
ping 10.0.0.1

# Test 3: Ver estado de VPN
sudo wg show dev1

# Test 4: Acceso a BD (si tienes permisos)
psql -h 10.0.0.254 -U postgres -c "SELECT version();"
```

**Resultados esperados:**

```
✅ Ping google.com: ~20-30ms (internet normal)
✅ Ping 10.0.0.1: <1ms (infraestructura)
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

```bash
sudo wg-quick down dev1
sudo nano /etc/wireguard/dev1.conf
# Cambiar: AllowedIPs = 0.0.0.0/0
# A esto: AllowedIPs = 10.0.0.0/24
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
ping 10.0.0.1      # Debe responder
```

### "No Puedo Conectar a BD (PostgreSQL)"

```bash
# 1. Verificar VPN está activa
sudo wg show dev1
# Debe mostrar "latest handshake" reciente

# 2. Probar ping
ping 10.0.0.1

# 3. Intentar conexión
psql -h 10.0.0.254 -U postgres -c "SELECT 1;"
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
ping 10.0.0.1            # Gateway VPN
ping 8.8.8.8             # Internet
ping 10.0.0.254          # Host servidor
```

---

## 📝 Checklist de Configuración

- [ ] WireGuard instalado
- [ ] Archivo `peer_dev1.conf` descargado y copiado
- [ ] Permisos correctos: `sudo chmod 600 /etc/wireguard/dev1.conf`
- [ ] Conectado: `sudo wg-quick up dev1`
- [ ] Internet funciona: `ping google.com` → <50ms
- [ ] Infraestructura accesible: `ping 10.0.0.1` → <5ms
- [ ] AllowedIPs correcto: `grep AllowedIPs /etc/wireguard/dev1.conf` → `10.0.0.0/24`
- [ ] Estado mostrado: `sudo wg show dev1` → `latest handshake` reciente

---

## 🆘 Soporte

Si tienes problemas:

1. Ejecuta: `sudo wg show dev1`
2. Ejecuta: `ping 10.0.0.1`
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
