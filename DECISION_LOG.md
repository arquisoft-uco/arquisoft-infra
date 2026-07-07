# 🏛️ Architectural Decision Log (ADL) - WireGuard VPN

> **Registro de decisiones arquitectónicas tomadas durante la evolución de la VPN escalable**  
> Formato: ADR (Architectural Decision Record) - RFC 5706

---

## ADR-001: Usar WireGuard (No OpenVPN/Tailscale)

**Fecha:** 2026-06-15  
**Status:** ✅ ACCEPTED  
**Contexto:** Necesitamos VPN para acceso remoto a infraestructura

**Opciones Consideradas:**
1. **WireGuard** - Moderno, ligero, Curve25519
2. OpenVPN - Maduro, overhead mayor
3. Tailscale - SaaS, menos control

**Decisión:** **WireGuard**

**Rationale:**
- ✅ Criptografía moderna (Curve25519, ChaCha20-Poly1305)
- ✅ Kernel-based (mejor performance que userspace)
- ✅ Overhead mínimo (~50-100MB)
- ✅ Open source (no vendor lock-in)
- ✅ Ampliamente soportado (Linux, macOS, Windows, iOS, Android)

**Implicaciones:**
- Requiere kernel >= 5.6 (o wireguard-go para versiones viejas)
- No soporta FIPS (si es requisito, use OpenVPN)

**Relacionado:** ADR-002, ADR-003

---

## ADR-002: FASE 1 - Docker (Línea Base)

**Fecha:** 2026-06-20  
**Status:** ✅ ACCEPTED (pero se reemplazó)  
**Contexto:** ¿Cómo desplegar WireGuard?

**Opciones Consideradas:**
1. **Docker Container** (linuxserver/wireguard)
2. Sistema nativo Linux (apt-get install wireguard)
3. Máquina virtual dedicada

**Decisión:** **Docker Container**

**Rationale:**
- ✅ Portabilidad (Linux/macOS/Windows via Docker Desktop)
- ✅ Imagen bien mantenida (linuxserver)
- ✅ Isolamiento de permisos
- ✅ Fácil de actualizar (cambiar tag de imagen)
- ✅ Healthcheck integrado

**Implicaciones:**
- Requiere Docker en host
- Pequeño overhead de containerización (negligible para VPN)

**Notas:**
- Funcionó bien para single-server
- Problema: no escalaba a múltiples servidores

**Próxima Decisión:** ADR-004

---

## ADR-003: FASE 2 - WireGuard Nativo (Experimento)

**Fecha:** 2026-06-25  
**Status:** ❌ REJECTED (después de 13 commits)  
**Contexto:** Presunción: "WireGuard nativo es más profesional"

**Opciones Consideradas:**
1. **WireGuard Nativo** (instalar en host vía apt-get)
2. Continuar con Docker (mantener simplicidad)

**Decisión Inicial:** **WireGuard Nativo**

**Rationale Inicial:**
- ✅ Mejor performance (sin overhead container)
- ✅ Más control sobre kernel
- ✅ Menos dependencias (no necesita Docker)

**Problemas Encontrados:**
- ❌ Permisos root requieren sudoers complexity
- ❌ Variables de entorno no se preservan con sudo
- ❌ Scripts OS-específicos necesarios
- ❌ No escalable a múltiples servidores
- ❌ Violaba constraint "cambios via terraform"
- ❌ Terraform diseñado para orquestación, no sysadmin

**Implicaciones de Rechazo:**
- 13 commits de trabajo descartados (pero valioso aprendizaje)
- Validó que "más control" ≠ "mejor solución"
- Enseñó importancia de elegir layer de abstracción correcto

**Lecciones:**
- Terraform es para infrastructure orchestration, no system administration
- Performance micro-optimizations (< 1%) no valen la complejidad
- Multi-OS en bash scripts es unmaintainable

**Decisión Revertida:** ADR-004 (volver a Docker)

---

## ADR-004: FASE 2.5 - Nativo Multi-OS (Intento Fallido)

**Fecha:** 2026-06-28  
**Status:** ❌ REJECTED  
**Contexto:** Intento de rescatar FASE 2 haciendo multi-OS

**Opciones Consideradas:**
1. **Detectar OS y ejecutar script correcto** (uname -s)
2. Admitir que Docker es mejor
3. Aceptar solo Linux

**Decisión Propuesta:** Multi-OS con detección

**Problemas Encontrados Inmediatamente:**
- ❌ Bash no funciona en PowerShell Windows
- ❌ Rutas de archivos completamente diferentes
- ❌ Permisos completamente diferentes
- ❌ Cada OS requiere código disjunto (unmaintainable)
- ❌ "Abstracción" crea más complejidad, no menos

**Lecciones Claves:**
- No intentes abstraer diferencias fundamentales de SO en bash
- "One script to rule them all" es antipatrón
- Cuando el paradigma no funciona, cambia el paradigma

**Decisión Final:** ❌ Rechazado  
**Transición:** ADR-005 (aceptar que Docker es correcto)

---

## ADR-005: FASE 3 - Docker Multi-nodo Escalable ✅

**Fecha:** 2026-07-04  
**Status:** ✅ ACCEPTED  
**Contexto:** Necesitamos escalabilidad, portabilidad, mantenibilidad

**Opciones Consideradas:**
1. **Docker + Módulo Reutilizable** (wireguard-node)
2. Continuar con shell scripts nativo (rechazado en ADR-003, ADR-004)
3. Usar Kubernetes desde el inicio (overcomplicated)

**Decisión:** **Docker Multi-nodo con Módulo Genérico**

**Rationale:**
- ✅ Escalable (agregar nodo = copiar módulo)
- ✅ Portable (Windows/macOS/Linux funciona igual)
- ✅ Mantenible (una fuente de verdad)
- ✅ Cloud-ready (AWS, GCP, Azure, Kubernetes)
- ✅ Sin sudoers complexity
- ✅ Sin permisos root en terraform.tfstate

**Architectural Decisions:**

### ADR-005a: Subnet Segmentation

**Decisión:** VPN compartida (172.16.0.0/24) + Docker segments únicos

```
VPN: 172.16.0.0/24      (todos los clientes)
├─ Nodo 1: 172.16.1.0/24
├─ Nodo 2: 172.16.2.0/24
└─ Nodo 3: 172.16.3.0/24
```

**Rationale:**
- ✅ Cero conflictos de IP
- ✅ Clientes se conectan UNA VEZ
- ✅ Acceso a servicios en CUALQUIER nodo
- ✅ Escalable a N nodos

### ADR-005b: Módulo Genérico (Reutilizable)

**Decisión:** `wireguard-node` módulo parametrizable

```hcl
module "wireguard_node_X" {
  source = "../modules/wireguard-node"
  node_name       = "..."
  docker_subnet   = "..."
  services        = { ... }
}
```

**Rationale:**
- ✅ DRY principle (Don't Repeat Yourself)
- ✅ Agregar nodo = copia-pega
- ✅ Cambios aplican a todos los nodos
- ✅ Mantenimiento único

### ADR-005c: Docker > Nativo Performance

**Decisión:** Acceptar overhead negligible de Docker

**Rationale:**
- WireGuard overhead: ~100ms latency, ~1% CPU
- Docker overhead: ~50ms latency, ~0.5% CPU
- Total: ~150ms, <2% CPU (imperceptible)
- Benefit: 10x simpler, scales infinitely

**Trade-off Analysis:**
```
Performance (micro-optimized):  10/10
Mantenibilidad (Docker):        9/10
Overall score: Mantenibilidad >> Performance micro
```

**Implicaciones:**
- No hacer baremarcas de performance
- Si latency crítica en futuro, nativo sería re-evaluated
- Docker es correcta por ahora

### ADR-005d: Terraform Local-Exec (No Remote-Exec)

**Decisión:** Terraform runs donde necesita, not SSH remote

**Rationale:**
- ✅ Respeta constraint "cambios solo via terraform"
- ✅ State files no corruptos por permisos root
- ✅ Funciona en Windows/macOS/Linux
- ✅ No requiere SSH setup

**Implicaciones:**
- Terraform debe tener Docker instalado
- En serverless/cloud, usar cloud-init en lugar

---

## ADR-006: Arquitectura: Multi-Server Mesh vs VPN Centralizada

**Fecha:** 2026-07-04  
**Status:** ✅ ACCEPTED  
**Contexto:** Cómo conectar múltiples nodos

**Opciones Consideradas:**
1. **VPN Centralizada** (un gateway, todos los clientes conectan)
2. Mesh Network (cada nodo conecta a todos los otros)
3. Punto-a-punto (cada cliente solo accede un servidor)

**Decisión:** **VPN Centralizada**

**Rationale:**
- ✅ Modelo simple (cliente → gateway → servicios)
- ✅ Escalable sin actualizar configuración
- ✅ Un único punto de conexión para clientes
- ✅ Matches WireGuard design (no es mesh-ready)

**Implicaciones:**
- Gateway es single point (mitigation: failover en futuro)
- Todos los datos pasan por gateway (latency: negligible)
- Fácil de monitorear (un punto)

**Alternativas Futuras:**
- WireGuard mesh (si necesarios múltiples gateways)
- Kubernetes networking (si escalas a 100+ nodos)

---

## ADR-007: Documentation Strategy

**Fecha:** 2026-07-04  
**Status:** ✅ ACCEPTED  
**Contexto:** Cómo documentar decisiones y aprendizajes

**Opciones Consideradas:**
1. **Documentación arquitectónica + Lessons Learned** (esta)
2. Solo código (sin documentación)
3. Wiki interno (difficul to maintain)

**Decisión:** **ADR + Lessons Learned + Troubleshooting**

**Archivos:**
- `WIREGUARD_ARCHITECTURE.md` - Uso operacional
- `LESSONS_LEARNED.md` - Por qué cada decisión
- `TROUBLESHOOTING_PHASES.md` - Problemas y soluciones
- `DECISION_LOG.md` - Este archivo

**Rationale:**
- ✅ Futuro devs entienden contexto
- ✅ Evita repetir errores
- ✅ Argumentos claros para cada decisión

---

## ADR-008: Versioning Strategy

**Fecha:** 2026-07-04  
**Status:** ✅ ACCEPTED  
**Contexto:** ¿Cómo versionear WireGuard image?

**Opciones Consideradas:**
1. **Fixed version tag** (1.0.20250521-r1-ls116)
2. Latest (siempre actualizar)
3. Major version only (1.0.*)

**Decisión:** **Fixed version tag**

**Rationale:**
- ✅ Deterministic (terraform apply siempre igual)
- ✅ Reproducible (bug fix es intentional)
- ✅ Auditable (qué versión está en prod)
- ✅ No "surprise" security updates

**Process Para Actualizar:**
1. Cambiar `wireguard_image` en variables.tf
2. `terraform plan` para verificar
3. `terraform apply` para actualizar

---

## ADR-009: Testing Strategy

**Fecha:** 2026-07-04  
**Status:** 🔄 DEFERRED  
**Contexto:** Cómo validar VPN funciona

**Decisión Pendiente:** 
- ¿Terraform tests? (terratest, checkov)
- ¿Integration tests? (client connect)
- ¿Health checks? (prometheus metrics)

**Opciones a Evaluar Later:**
1. Terratest para validar outputs
2. Client connectivity tests
3. Prometheus for alerting

**Nota:** Testing es futuro, actualmente usar manual testing

---

## 📊 Resumen de Decisiones

| ADR | Decisión | Fecha | Status | Rationale |
|-----|----------|-------|--------|-----------|
| 001 | WireGuard | 06-15 | ✅ | Modern crypto, lightweight |
| 002 | Docker | 06-20 | ✅ | Portability, simplicity |
| 003 | Nativo Linux | 06-25 | ❌ | Complexity > performance |
| 004 | Multi-OS | 06-28 | ❌ | Unmaintainable abstraction |
| 005 | Docker Multi-node | 07-04 | ✅ | Scalable, portable, maintainable |
| 005a | VPN + Docker Segments | 07-04 | ✅ | Zero conflicts, scalable |
| 005b | Módulo Genérico | 07-04 | ✅ | DRY, reusable |
| 005c | Docker > Nativo | 07-04 | ✅ | Overhead negligible, benefits huge |
| 005d | Local-Exec | 07-04 | ✅ | Respeta constraints, scalable |
| 006 | VPN Centralizada | 07-04 | ✅ | Simple, scalable, WireGuard-native |
| 007 | Full Documentation | 07-04 | ✅ | Prevents repeating errors |
| 008 | Fixed Version Tag | 07-04 | ✅ | Deterministic, auditable |
| 009 | Testing Strategy | 07-04 | 🔄 | Deferred to phase 2 |

---

## 🎓 Principios Aplicados

1. **Simplicity over Premature Optimization**
   - ADR-005c: Docker overhead < Maintenance burden

2. **Constraints Drive Architecture**
   - ADR-005d: User constraint respeto

3. **When Paradigm Fails, Change Paradigm**
   - ADR-002 → ADR-003 → ADR-005: Nativo falló, Docker ganó

4. **Document Decisions, Not Just Code**
   - ADR-007: Future readers entienden por qué

5. **Architectural Decisions are Reversible**
   - ADR-005c: Si latency crítica futuro, eval nativo

---

## ADR-013: PEERDNS=auto (CoreDNS interno) para el DNS de los peers ✅

**Contexto:** con `DNS = 1.1.1.1` (IP pública) en los peer `.conf`, wg-quick + systemd-resolved
enrutan TODO el DNS por el túnel split (dominio catch-all `~.`), y 1.1.1.1 no está en `AllowedIPs`
→ el cliente pierde toda resolución (incluido github.com) al conectar.

**Decisión:** `wireguard_peer_dns = "auto"`. La imagen linuxserver SIEMPRE escribe una línea DNS;
con `auto` usa `${INTERFACE}.1` = `172.16.0.1` (CoreDNS interno del gateway), alcanzable por el
túnel y que reenvía externas + resuelve nombres de servicios (postgres, redis...).

**Alternativas descartadas:** (a) IP pública → rompe el DNS (era el bug). (b) Omitir la línea DNS
→ la imagen no lo soporta. (c) `resolvectl domain dev1 ''` en cliente → solo temporal.

**Consecuencias:** el DNS del cliente pasa por la VPN mientras está conectado (aceptable para
acceso a infra; bonus: servicios por nombre). Commit `ebe6eb7`.

---

## 🔮 Decisiones Futuras

### ADR-010: Multi-Region (Candidata)
- Gateway en múltiples regiones?
- Mesh networking entre gateways?

### ADR-011: Kubernetes Integration (Candidata)
- Converger a K8s networking?
- Helm charts en lugar de Terraform modules?

### ADR-012: High Availability (Candidata)
- Failover automático?
- Multiple gateways?

---

## 📚 Referencias

- RFC 5706 - ADR template
- Terraform Best Practices
- WireGuard Official Docs
- 12 Factor App - Process isolation

---

**Versión:** 1.0 (2026-07-04)  
**Autor:** Iteración VPN Escalable  
**Próxima Revisión:** 2026-09-04 (después de 3 meses producción)
