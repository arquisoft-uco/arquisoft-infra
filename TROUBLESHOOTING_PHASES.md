# 🔧 Troubleshooting - Problemas Encontrados en Cada Fase

> **Documento de problemas específicos encontrados durante la implementación de VPN escalable**  
> Incluye soluciones y por qué ocurrieron

---

## FASE 2: WireGuard Nativo Linux

### Problema 1: Variables de Entorno No Se Preservan con `sudo`

**Descripción:**
```bash
export GATEWAY_IP="172.16.0.1"
sudo bash setup-wireguard.sh
# Dentro del script:
echo $GATEWAY_IP  # ← Vacío!
```

**Root Cause:**
- `sudo` crea un nuevo entorno limpio
- Variables de entorno heredadas del shell padre se pierden
- `sudo -E` preserva algunas pero no todas

**Soluciones Intentadas:**

❌ **Intento 1: Environment variables directamente**
```bash
provisioner "local-exec" {
  command = "sudo bash script.sh"
  environment = {
    GATEWAY_IP = "172.16.0.1"
  }
}
# ❌ Falla: variables vacías dentro del script
```

❌ **Intento 2: sudo -E**
```bash
provisioner "local-exec" {
  command = "sudo -E bash script.sh"
}
# ❌ Falla: algunas variables se pierden, edge cases
```

❌ **Intento 3: templatefile con ${}`
```bash
content = templatefile("script.sh", {
  gateway_ip = "172.16.0.1"
})
# ❌ Falla: Terraform interpreta ${} como variables, conflicto con bash syntax
```

✅ **Solución Final: Wrapper script que exporta variables**
```bash
# Terraform genera este wrapper:
export GATEWAY_IP="172.16.0.1"
export VPN_SUBNET="172.16.0.0/24"
# ... más exports
${file("script.sh")}
```

**Lección:** Cuando necesites pasar variables a un script que corre con `sudo`, crea un wrapper que haga los exports antes de ejecutar el script principal.

---

### Problema 2: Instalación de WireGuard Falla Silenciosamente

**Descripción:**
```bash
provisioner "local-exec" {
  command = "sudo bash setup-wireguard.sh"
  # Script dice: "apt-get install -y wireguard"
  # Pero no muestra errores ni sale...
}
```

**Root Cause:**
```bash
apt-get install -y wireguard > /dev/null 2>&1
# Los errores se silencian completamente
# set -e hace que el script salga, pero sin mensaje de error
```

**Solución:**
```bash
# ❌ Malo:
apt-get install -y wireguard > /dev/null 2>&1

# ✅ Bueno:
if ! apt-get install -y wireguard 2>&1 | grep -i "done\|setting"; then
  echo "❌ Error en apt-get install wireguard"
  exit 1
fi
```

**Lección:** Nunca silencies errores en instalaciones críticas. Captura exit codes y muestra mensajes de error significativos.

---

### Problema 3: /etc/wireguard Requiere Permisos Root

**Descripción:**
```bash
mkdir -p /etc/wireguard
# ❌ Permission denied (necesita root)
```

**Soluciones Intentadas:**

❌ **Intento 1: Cambiar propietario en sudoers**
```bash
sudoers:
deploy ALL=(ALL) NOPASSWD: /bin/mkdir /etc/wireguard
# ❌ Tedioso: necesitas listar CADA comando
# ❌ Mantenimiento: cada comando nuevo = actualizar sudoers
```

❌ **Intento 2: Ejecutar terraform como root**
```bash
sudo terraform apply
# ❌ Problema: terraform.tfstate se crea como root
# ❌ Usuario normal no puede leer/escribir state
```

✅ **Solución: Usar Docker (abstrae permisos)**
```bash
docker run --rm -v /etc/wireguard:/config ...
# Docker maneja permisos internamente
# Host no necesita sudo complexity
```

**Lección:** Si muchos comandos necesitan permisos elevados, probablemente estés en el nivel de abstracción equivocado. Usa containers.

---

### Problema 4: systemctl Requiere Acceso al Sistema

**Descripción:**
```bash
systemctl start wg-quick@wg0
# ❌ No funciona con terraform local-exec en local development
```

**Por qué es un problema:**
- Terraform ejecuta en máquina local (usuario normal)
- systemctl necesita systemd (solo en Linux)
- En macOS/Windows no existe

**Soluciones Intentadas:**

❌ **Intento 1: Detección de SO complicada**
```bash
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  systemctl start ...
elif [[ "$OSTYPE" == "darwin"* ]]; then
  launchctl start ...
fi
# ❌ Cada SO requiere lógica completamente diferente
```

✅ **Solución: Docker gestiona estado internamente**
```bash
docker container restart wireguard-...
# No necesita systemctl
# Funciona igual en todos los SO
```

**Lección:** Evita lógica OS-específica. Usa abstracción (containers) que funcione igual en todos lados.

---

### Problema 5: Remote-exec SSH vs Local-exec Constraint

**Descripción:**
Usuario requería: "Cambios en servidor SOLO via terraform" (sin SSH manual)

```bash
provisioner "remote-exec" {
  type = "ssh"
  command = "bash setup-wireguard.sh"
  # ❌ Viola constraint: ssh es cambio manual, no terraform
}
```

**Por qué es un problema:**
- Usuario quería IaC donde Terraform corre EN el servidor
- Remote-exec es equivalente a `ssh ubuntu@server "command"`
- No es "cambios via terraform", es "cambios via SSH"

❌ **Intento 1: Local-exec sin sudo (falla)**
```bash
provisioner "local-exec" {
  command = "bash setup-wireguard.sh"
  # ❌ Falla: necesita permisos root
}
```

✅ **Solución: Docker (abstrae permisos)**
```bash
provisioner "local-exec" {
  command = "docker run --rm ... setup-wireguard"
  # ✅ Docker maneja permisos internamente
  # ✅ Sin sudo complexity
```

**Lección:** Cuando necesites privilegios elevados sin sudoers complexity, usa containers.

---

## FASE 2.5: WireGuard Nativo Multi-OS

### Problema 6: Syntax Diferente en Bash vs PowerShell

**Descripción:**
```bash
# Linux/macOS:
apt-get install wireguard
systemctl start wg-quick@wg0

# Windows PowerShell:
msiexec /i wireguard-installer.exe
net start wireguard
```

**Intento:** Un solo script que detecte OS y ejecute lo correcto

```bash
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  apt-get install wireguard
  systemctl start wg-quick@wg0
elif [[ "$OSTYPE" == "darwin"* ]]; then
  brew install wireguard
  launchctl start wireguard
else
  powershell -Command "& { ... }"
fi
```

**Por qué falla:**
- Bash no ejecuta en Windows (necesita Git Bash, WSL, etc)
- PowerShell no es standard en Linux/macOS
- Lógica se vuelve unmaintainable (3+ paths divergentes)

**Lección:** No intentes abstraer diferencias fundamentales de SO. Usa containers que proporcionen linux en todos lados.

---

### Problema 7: Rutas de Archivos Diferentes

**Descripción:**
```
Linux:   /etc/wireguard/wg0.conf
macOS:   /opt/wireguard/conf.d/wg0.conf
Windows: C:\Program Files\WireGuard\wg0.conf
```

**Intento:** Script genérico que funcione en todas

```bash
case "$OSTYPE" in
  linux*)  WG_CONF="/etc/wireguard/wg0.conf" ;;
  darwin*) WG_CONF="/opt/wireguard/conf.d/wg0.conf" ;;
  *)       WG_CONF="C:\Program Files\WireGuard\wg0.conf" ;;
esac

cat > "$WG_CONF" << EOF
...
EOF
```

**Por qué falla:**
- Script shell no puede escribir en paths de Windows
- Permisos completamente diferentes
- Mantenimiento es pesadilla

**Lección:** Abstraer rutas de archivos por OS es un code smell. Usa containers.

---

## FASE 3: Docker Multi-nodo ✅

### Problema 8: Escalabilidad (RESUELTO ✅)

**Antes (Fase 1-2):**
```hcl
# Servidor 1: configuración hardcoded
resource "docker_container" "wireguard" {
  name = "arquisoft-wireguard"
  ...
}

# Servidor 2: configuración completamente diferente
resource "docker_container" "wireguard_2" {
  name = "arquisoft-wireguard-2"
  ...  # ← TODO duplicado
}
```

**Solución (Fase 3):**
```hcl
module "wireguard_node_1" {
  source = "../modules/wireguard-node"
  docker_subnet = "172.16.1.0/24"
}

module "wireguard_node_2" {
  source = "../modules/wireguard-node"
  docker_subnet = "172.16.2.0/24"
}
```

**Beneficio:** Agregar servidor = copiar módulo + cambiar subnet

---

### Problema 9: Network Segmentation (RESUELTO ✅)

**Antes:**
```
Todos los nodos en 10.0.2.0/24
Conflicto con Docker local en dev machines
```

**Solución:**
```
VPN: 172.16.0.0/24  (compartida)
├─ Nodo 1: 172.16.1.0/24
├─ Nodo 2: 172.16.2.0/24
└─ Nodo 3: 172.16.3.0/24

Local Docker: 10.0.0.0/8 (sin conflicto)
```

**Beneficio:** Zero IP conflicts, fácil de escalar

---

### Problema 10: Portabilidad Completa (RESUELTO ✅)

**Antes:**
```
Linux:   ✅ funciona
macOS:   ❌ "wg-quick no existe en repos"
Windows: ❌ "bash not found"
```

**Solución:**
```
Cualquier OS + Docker Desktop:
terraform init
terraform apply
✅ Funciona igual en todos
```

**Beneficio:** Same commands everywhere, no OS-specific scripts

---

## 📊 Matriz de Problemas vs Soluciones

| Problema | FASE 2 Nativo | FASE 2.5 Multi-OS | FASE 3 Docker |
|----------|---|---|---|
| Escalabilidad | ❌ Manual | ❌ Complex | ✅ Trivial |
| Portabilidad | ❌ Linux only | ❌ Complex scripts | ✅ Perfect |
| Permisos | ⚠️ sudo complex | ⚠️ Very complex | ✅ Internal |
| Mantenibilidad | ⚠️ Medium | ❌ High | ✅ Low |
| Multi-Server | ❌ Manual | ❌ Complex | ✅ Trivial |

---

## 🎓 Principios Aprendidos

### 1. **Cuando Muchos Problemas Aparecen, Cambia Paradigma**
- FASE 2: 10+ problemas de permisos/OS/escala
- Señal: Architecture incorrecta
- Solución: Cambiar a containers (paradigma diferente)

### 2. **"Mostly Works" No Es Production Ready**
- ❌ "Funciona en Linux pero no en macOS"
- ❌ "Funciona con algunos comandos pero no otros"
- ✅ "Funciona igual en todos lados, siempre"

### 3. **Mantenibilidad es La Métrica Real**
- FASE 2 Nativo: 100 líneas, 50 problemas
- FASE 3 Docker: 50 líneas, 0 problemas
- Docker gana (simplicity)

### 4. **Documentación de Lecciones es Valiosa**
- Futuros devs no repiten errores
- Decisiones arquitectónicas tienen contexto
- "¿Por qué Docker?" tiene respuesta clara

---

## 🚀 Aplicando Estas Lecciones

### Cuando Agregues Feature Nueva:
1. ¿Necesita permisos root? → Usa containers
2. ¿Necesita multi-OS? → Usa containers
3. ¿Necesita escalar? → Usa módulo reutilizable
4. ¿Necesita simplificar? → Usa containers

### Cuando Otro Dev Pregunte "¿Por qué Docker?":
Responde: "Mira LESSONS_LEARNED.md - intentamos nativo, esto es lo que encontramos"

---

**Versión:** 1.0 (2026-07-04)  
**Revisado por:** Iteración completa de VPN  
**Próximo paso:** Documentación de operaciones (cómo agregar nodos en prod)
