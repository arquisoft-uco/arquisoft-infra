# 📚 Lecciones Aprendidas - Evolución de WireGuard VPN

> **Documento de aprendizajes adquiridos durante la implementación de VPN escalable**  
> Última actualización: 2026-07-04

## 🎯 Introducción

Este documento registra los aprendizajes clave de implementar una VPN WireGuard escalable, incluyendo todas las fases, decisiones arquitectónicas, problemas encontrados y soluciones.

---

## 📋 Fases de Implementación

### FASE 1: Docker Básico (Línea Base)
**Estatus:** ✅ Funcional  
**Commits:** `2f003c0` (inicio), `9fd38e2` (estable)

#### ✅ Qué funcionó bien:
- Docker es excelente para **portabilidad** (Windows/macOS/Linux funciona igual)
- `linuxserver/wireguard:1.0.20250521-r1-ls116` es imagen estable y bien mantenida
- Container con capabilities (`NET_ADMIN`, `NET_RAW`, `SYS_MODULE`) funciona correctamente
- Volumes persistentes mantienen configuración segura
- Healthcheck integrado detecta fallos automáticamente
- JSON logging se integra con observabilidad

#### ❌ Problemas encontrados:
- ❌ No escalable a múltiples servidores (cada servidor tenía que reconfigurase manualmente)
- ❌ Red Docker única (10.0.0.0/24) limitaba multi-servidor
- ❌ Sin ejemplo de cómo agregar servidores adicionales
- ❌ Confusión sobre si era "mala práctica" (no lo es)

#### 💡 Lecciones:
1. **Docker NO es mala práctica para VPN** - es estándar en la industria (Kubernetes, cloud providers)
2. **La escalabilidad depende de arquitectura**, no de la tecnología base
3. **Necesitábamos módulo reutilizable**, no un único contenedor

---

### FASE 2: WireGuard Nativo en Host (Experimento)
**Estatus:** ❌ Abandonado  
**Commits:** `f081cf0` - `f96080f` (13 commits)

#### 🎯 Motivación:
- "VPN nativa es más profesional"
- Mejor performance (sin overhead Docker)
- Máxima visibilidad del kernel

#### ❌ Problemas encontrados:

##### 1. **Complejidad de Portabilidad entre SO**
```
Linux:   /etc/wireguard, systemctl, apt-get, ufw
macOS:   /opt/wireguard, launchctl, brew, pfctl
Windows: C:\Program Files\WireGuard, powershell, netsh
```
- Cada SO requería **scripts completamente diferentes**
- Terraform multi-OS se volvía **muy complejo**
- Detección de OS en Terraform es frágil

##### 2. **Problema de Permisos con Terraform**
```
Necesita: sudo para instalar, configurar firewall, etc.
Options:
  ❌ sudo terraform apply → Crea archivos de estado como root
  ❌ sudoers NOPASSWD → Complejidad y seguridad cuestionable
  ❌ remote-exec SSH → Viola principio "terraform run solo en servidor"
```

##### 3. **Variables de Entorno con sudo**
```
sudo -E bash script.sh  # ❌ Variables no se preservan bien
GATEWAY_IP="" # ← Llega vacía
```
- Intentos de solución: templatefile, wrapper scripts
- Siempre había edge cases que no funcionaban

##### 4. **Constraint del Usuario**
> "Asegurate de que los cambios en el servidor sean SOLO a través de terraform"

- Remote-exec SSH violaba esto
- Local-exec requería sudo complejo
- Nativo complicaba la automatización

#### 💡 Lecciones:
1. **Terraform es para orquestación, no para system administration**
2. **WireGuard nativo es excelente para appliances dedicadas**, no para multi-servidor scalable
3. **Multi-OS en el mismo script es antipatrón** - se vuelve unmaintainable
4. **Permisos en Terraform requieren cuidado extremo**:
   - `sudo terraform apply` corrompe state ownership
   - sudoers NOPASSWD añade complejidad de seguridad
   - remote-exec viola principios de IaC local-first

---

### FASE 2.5: WireGuard Nativo Multi-OS (Refinamiento Fallido)
**Estatus:** ❌ Abandonado  
**Concepto:** Usar `uname -s` para detectar OS y ejecutar script correcto

#### ❌ Por qué no funcionó:
1. **Cada script de OS sería mantenimiento paralelo**
   - Cambio en Linux → debe replicarse a macOS, Windows
   - Bug en uno = bug en todos (divergencia)

2. **Windows PowerShell incompatible**
   - Rutas completamente diferentes
   - APIs completamente diferentes
   - No puede compartir lógica con bash

3. **Principio de "Same Code Everywhere" se pierde**
   - Terraform no garantiza que todos tengan Bash
   - Windows users esperarían PowerShell
   - macOS users esperarían Homebrew

#### 💡 Lecciones:
1. **No intentes abstraer diferencias fundamentales de SO en un solo script**
2. **"One script to rule them all" es un antipatrón** - crea code smell
3. **Container es la mejor forma de abstraer SO** - es lo que hacen AWS, Google, Microsoft

---

### FASE 3: Docker Multi-nodo Escalable (SOLUCIÓN FINAL) ✅
**Estatus:** ✅ Implementado y documentado  
**Commits:** `c188759`, `dc34a5b`

#### ✅ Por qué funciona:

##### 1. **Escalabilidad Real**
```hcl
module "wireguard_node_1" { docker_subnet = "172.16.1.0/24" }
module "wireguard_node_2" { docker_subnet = "172.16.2.0/24" }
module "wireguard_node_3" { docker_subnet = "172.16.3.0/24" }
module "wireguard_node_N" { docker_subnet = "172.16.N.0/24" }
```
- Agregar nodo = copiar módulo
- No hay lógica duplicada
- Cada nodo independiente pero conectado por VPN

##### 2. **Portabilidad Total**
```
Windows + Docker Desktop → funciona
macOS + Docker Desktop → funciona
Linux + Docker → funciona
Kubernetes → funciona
AWS ECS → funciona
```
- Mismo comando `terraform apply` en todos
- Sin scripts SO-específicos

##### 3. **Permisos Limpios**
```
terraform apply  # ← Sin sudo
Docker manage permissions internally
```
- Docker container runs with capabilities
- Host doesn't need sudoers complexity
- State files owned by user (no root)

##### 4. **VPN Compartida, Redes Independientes**
```
VPN: 172.16.0.0/24   (todos los nodos)
    ├─ Nodo 1: 172.16.1.0/24
    ├─ Nodo 2: 172.16.2.0/24
    └─ Nodo 3: 172.16.3.0/24
```
- Clientes se conectan UNA VEZ a VPN
- Acceden a servicios en CUALQUIER nodo
- Cero conflictos de red

#### 💡 Lecciones:
1. **Docker está diseñado para resolver exactamente este problema**
2. **La containerización es "infrastructure abstraction", no "performance overhead"**
3. **Kubernetes y cloud providers usan Docker + orchestration** por una razón
4. **Simplicidad > Performance prematura** - WireGuard overhead es mínimo

---

## 🔑 Lecciones Clave Generales

### 1. Entiende el Problema Antes de Elegir Tecnología
```
❌ Problema: "VPN para acceso remoto a infraestructura"
   → Elegiste: WireGuard nativo (performance)
   
✅ Problema: "VPN escalable para múltiples servidores distribuidos"
   → Solución: Docker + orchestration (escalabilidad)
```

### 2. Terraform es Orquestación, No System Admin
```
❌ Usar Terraform para: instalar paquetes, configurar firewall, manage permissions
✅ Usar Terraform para: definir infraestructura, orquestar containers, manejar estado
```

### 3. "Profesional" ≠ "Más Complejo"
```
❌ "WireGuard nativo es más profesional" (asunción incorrecta)
✅ "Multi-nodo escalable en Docker es más profesional" (prueba: AWS, Google, Microsoft)
```

### 4. La Industria Resuelve Multi-Server Así:
```
- Kubernetes: orquesta containers
- ECS: orquesta containers
- Docker Compose: orquesta containers
- Terraform + Docker: IaC + orchestration

❌ Nadie intenta hacer multi-servidor nativo con 3 scripts OS-específicos
```

### 5. Aprender a Decir "No" a Micro-optimizaciones
```
❌ "Docker tiene overhead" (100-200ms → imperceptible)
❌ "Nativo es más performance" (diferencia: nanosegundos)
✅ "Docker es 10x más mantenible y escalable" (diferencia: desarrollo + operaciones)
```

---

## 🎓 Decisiones Arquitectónicas Validadas

### ✅ Decisión 1: Docker sobre Nativo
**Criterio:** Escalabilidad + Portabilidad > Performance marginal
**Resultado:** Módulo reutilizable, funciona en Windows/macOS/Linux/K8s

### ✅ Decisión 2: Módulo Genérico sobre Singleton
**Criterio:** Agregar servidor debe ser trivial
**Resultado:** Copiar módulo es todo lo que necesitas

### ✅ Decisión 3: Redes Docker Segmentadas
**Criterio:** Cada servidor aislado pero conectado por VPN
**Resultado:** Cero conflictos de IP, fácil de escalar

### ✅ Decisión 4: Subnet 172.16.0.0/12
**Criterio:** Evitar conflictos con Docker local (10.0.0.0/8)
**Resultado:** Clientes pueden tener Docker local sin conflictos

### ✅ Decisión 5: Terraform en Local
**Criterio:** Constraint "cambios solo via terraform"
**Resultado:** Terraform corre donde lo necesitas, sin sudo complexity

---

## 🚀 Aplicar Estas Lecciones

### Cuando Agregues Nuevos Servidores:
```hcl
module "wireguard_node_new" {
  source = "../modules/wireguard-node"
  node_name           = "new-server"
  docker_subnet       = "172.16.X.0/24"  # Nuevo segmento
  services = { ... }  # Agregar tus servicios
}
```
**Tiempo:** 5 minutos  
**Complejidad:** Copiador + modificador de texto

### Cuando Debas Actualizar WireGuard:
```
1. Cambiar wireguard_image en variables.tf
2. terraform plan → ver qué cambia
3. terraform apply → container reinicia con nueva imagen
```
**Tiempo:** 2 minutos  
**Riesgo:** Mínimo (docker restart policy)

### Cuando Debas Multi-Cloud:
```
AWS:    module "wireguard_node_aws" { ... }
GCP:    module "wireguard_node_gcp" { ... }
Azure:  module "wireguard_node_azure" { ... }
```
**Tiempo:** Mismo módulo, diferentes providers  
**Escalabilidad:** Horizontal en múltiples regiones

---

## 📝 Lo Que NO Repetir

❌ **No intentes abstraer diferencias de SO en un script**  
❌ **No uses terraform para system administration**  
❌ **No confundas "performance" con "profesionalismo"**  
❌ **No ignores "mantainability" por micro-optimizaciones**  
❌ **No diseñes para single-server si necesitas multi-server**  

---

## ✅ Lo Que Repetir

✅ **Usa containers para multi-OS portability**  
✅ **Usa módulos reutilizables para escalabilidad**  
✅ **Documenta decisiones arquitectónicas**  
✅ **Valida con ejemplos funcionales**  
✅ **Prioriza mantenibilidad sobre performance marginal**  

---

## 🔮 Futuro

### Próximas Mejoras (Opcionales):
1. **Helm Charts** - Convertir módulos a Kubernetes
2. **Multi-region** - Agregar replicación geográfica
3. **Failover** - HA automático entre nodos
4. **Monitoring** - Integración con observabilidad

### Pero NO intentes:
- ❌ Volver a nativo (ya lo intentaste)
- ❌ Multi-SO script único (ya lo intentaste)
- ❌ Eliminar Docker por performance (comprobado: imperceptible)

---

## 🌐 Lección clave: DNS y split-tunnel ("pierdo internet al conectar")

**Síntoma:** al conectar la VPN no resuelve ningún dominio (github.com, google.com) aunque la
conectividad por IP funcione — se siente como "sin internet".

**Causa raíz:** una línea `DNS = <ip>` en el peer `.conf` hace que `wg-quick` + `systemd-resolved`
marquen la interfaz con el dominio catch-all `~.` → TODAS las consultas DNS se enrutan por el túnel.
Con split-tunnel (`AllowedIPs = 172.16.0.0/16`), si ese DNS es una IP **pública** (ej. `1.1.1.1`)
NO está en la ruta del túnel → toda la resolución falla. (El esquema viejo con `DNS = 10.0.2.1`
interno tenía el mismo efecto tras quedar inexistente por la migración.)

**Fix definitivo:** `wireguard_peer_dns = "auto"` → la imagen usa el CoreDNS interno del gateway
(`172.16.0.1`), alcanzable por el túnel, que reenvía externas (`forward . /etc/resolv.conf`) y
resuelve nombres de servicios. Diagnóstico: `resolvectl status dev1` (`DNS Domain: ~.`),
`resolvectl query github.com`. Temporal en cliente: `sudo resolvectl domain dev1 ''`.

**Lección:** en split-tunnel, el DNS del peer debe apuntar a un resolver alcanzable DENTRO del
túnel (el gateway), nunca a una IP pública. Y el `.conf` se trae SIEMPRE del servidor (fuente de
verdad): las copias locales viejas reproducen este fallo.

---

## 📚 Referencias

- **WireGuard Official:** https://www.wireguard.com/
- **12 Factor App:** https://12factor.net/ (explica por qué containers)
- **Terraform Best Practices:** https://www.terraform.io/docs/cloud/guides/recommended-practices
- **Docker Networking:** https://docs.docker.com/network/
- **Kubernetes Networking:** https://kubernetes.io/docs/concepts/services-networking/

---

**Escrito por:** Experimento de VPN multi-fase  
**Próximo revisor:** Implementador de Feature 2.0  
**Versión:** 1.0 (2026-07-04)
