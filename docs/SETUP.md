# Guía de Setup - Arquisoft Infrastructure

## Prerrequisitos

### Software Requerido

- **Docker Desktop** 4.25+ (Windows/Mac) o **Docker Engine** 24.x+ (Linux)
- **Docker Compose** v2.20+
- **Git** 2.40+
- **curl** (para health checks)

### Recursos de Hardware

| Recurso | Mínimo | Recomendado |
|---------|--------|-------------|
| RAM | 8 GB | 16 GB |
| CPU | 4 cores | 8 cores |
| Disco | 50 GB SSD | 100 GB SSD |

## Instalación Rápida

### 1. Clonar Repositorio

```bash
git clone <URL_ARQUISOFT_INFRA>
cd arquisoft-infra
```

### 2. Configurar Variables de Entorno

```bash
# Generar archivo .env con credenciales seguras (recomendado)
bash scripts/setup-env.sh

# O copiar manualmente y editar
cp .env.example .env
nano .env  # Reemplazar CHANGE_ME_GENERATE_STRONG_PASSWORD
```

> ⚠️ **IMPORTANTE**: Nunca versionar el archivo `.env` con credenciales reales.

#### Variable `DOMAIN`

La variable `DOMAIN` es **requerida** y define el dominio base para todos los servicios expuestos por Traefik.

| Ambiente | Valor sugerido | Ejemplo |
|----------|---------------|---------|
| Desarrollo local | `arquisoft.localhost` | `http://arquisoft.localhost` |
| Servidor de desarrollo | Tu dominio DNS (ej. DuckDNS) | `https://mi-dominio.duckdns.org` |
| Producción | Dominio institucional | `https://arquisoft.uco.edu.co` |

El script `start.sh` generará automáticamente la configuración de Traefik a partir de los templates usando esta variable.

### 3. Iniciar Infraestructura

```bash
# En Windows (Git Bash o WSL)
bash scripts/start.sh dev

# En Linux/Mac
chmod +x scripts/*.sh
./scripts/start.sh dev
```

### 4. Verificar Estado

```bash
./scripts/health-check.sh
```

## Perfiles de Despliegue

### Solo Servicios Core

Para desarrollo del backend sin observabilidad:

```bash
./scripts/start.sh dev core
```

Incluye:
- PostgreSQL 15
- RabbitMQ 3.12
- MinIO

### Core + Autenticación

```bash
./scripts/start.sh dev auth
```

Incluye todo lo anterior más:
- Keycloak 22

### Stack Completo

```bash
./scripts/start.sh dev all
```

Incluye todo:
- Core (PostgreSQL, RabbitMQ, MinIO)
- Auth (Keycloak)
- Observability (Prometheus, Loki, Grafana, Promtail)
- Proxy (Traefik)

## Acceso a Servicios

### Desarrollo Local

> 🔒 **Seguridad:** Todos los puertos de desarrollo están vinculados a `127.0.0.1` (loopback). Solo son accesibles desde la máquina local. Para acceso remoto, usar Traefik proxy con subdominios HTTPS.

| Servicio | URL | Credenciales |
|----------|-----|--------------|
| RabbitMQ | http://localhost:15672 | Ver `RABBITMQ_USER` / `RABBITMQ_PASSWORD` en `.env` |
| MinIO Console | http://localhost:9001 | Ver `MINIO_ROOT_USER` / `MINIO_ROOT_PASSWORD` en `.env` |
| Keycloak | http://localhost:8080/admin | Ver `KEYCLOAK_ADMIN` / `KEYCLOAK_ADMIN_PASSWORD` en `.env` |
| Grafana | http://localhost:3000 | Ver `GRAFANA_ADMIN_USER` / `GRAFANA_ADMIN_PASSWORD` en `.env` |
| Prometheus | http://localhost:9090 | - |
| Traefik Dashboard | http://localhost:8081 | - |

### Con Traefik Proxy

Agregar a `/etc/hosts` (Linux/Mac) o `C:\Windows\System32\drivers\etc\hosts` (Windows), sustituyendo `<DOMAIN>` por el valor configurado en `.env` (ej. `arquisoft.localhost`):

```
127.0.0.1 <DOMAIN>
127.0.0.1 auth.<DOMAIN>
127.0.0.1 grafana.<DOMAIN>
127.0.0.1 rabbitmq.<DOMAIN>
127.0.0.1 storage.<DOMAIN>
127.0.0.1 traefik.<DOMAIN>
```

> En servidores con DNS público (ej. DuckDNS), no es necesario editar `/etc/hosts`.

Luego acceder a:
- `https://<DOMAIN>` — Aplicación
- `https://auth.<DOMAIN>/admin/` — Keycloak
- `https://grafana.<DOMAIN>/` — Grafana
- `https://rabbitmq.<DOMAIN>/` — RabbitMQ Management (BasicAuth)
- `https://storage.<DOMAIN>/` — MinIO Console (BasicAuth)
- `https://traefik.<DOMAIN>/` — Traefik Dashboard

## Configuración de Servicios

### PostgreSQL

La base de datos se inicializa automáticamente con:
- 10 schemas (uno por bounded context)
- Tabla de auditoría
- Trigger de auditoría

Conexión desde aplicación:
```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/arquisoft
spring.datasource.username=${POSTGRES_USER}  # Ver .env
spring.datasource.password=${POSTGRES_PASSWORD}  # Ver .env
```

Schemas disponibles:
- `usuarios` - Gestión de usuarios y roles
- `fichas_perfil` - Fichas y perfiles de trabajo de grado
- `proyectos_grado` - Proyectos de grado
- `artefactos` - Artefactos de proyectos
- `evaluaciones` - Evaluaciones definitivas
- `mapa_ruta` - Mapas de ruta
- `repositorio_artefactos` - Repositorio de artefactos institucionales
- `solicitudes` - Solicitudes del sistema
- `biblioteca` - Biblioteca institucional
- `entregables` - Entregables de proyectos

### RabbitMQ

Exchanges configurados:
- `arquisoft.events` (topic) - Eventos de dominio
- `arquisoft.events.dlx` (direct) - Dead Letter Exchange

Colas:
- `arquisoft.notificaciones.queue`
- `arquisoft.evaluaciones.queue`
- `arquisoft.artefactos.queue`
- `arquisoft.fichas.queue`
- `arquisoft.proyectos.queue`
- `arquisoft.dlq` (Dead Letter Queue)

Configuración Spring:
```properties
spring.rabbitmq.host=localhost
spring.rabbitmq.port=5672
spring.rabbitmq.username=${RABBITMQ_USER}  # Ver .env
spring.rabbitmq.password=${RABBITMQ_PASSWORD}  # Ver .env
spring.rabbitmq.virtual-host=arquisoft
```

### MinIO

Buckets por defecto:
- `artefactos` - Artefactos de proyectos
- `avatars` - Imágenes de perfil (acceso público)
- `backups` - Respaldos del sistema

Configuración:
```properties
minio.url=http://localhost:9000
minio.access-key=${MINIO_ROOT_USER}  # Ver .env
minio.secret-key=${MINIO_ROOT_PASSWORD}  # Ver .env
minio.bucket=artefactos
```

### Keycloak

Realm: `arquisoft`

Roles disponibles:
- ESTUDIANTE
- ASESOR
- ASESOR_FICHA
- COORDINADOR
- JURADO
- BIBLIOTECARIO
- REP_COMITE_CURRICULO
- ADMINISTRADOR

Configuración OAuth2:
```properties
spring.security.oauth2.resourceserver.jwt.issuer-uri=http://localhost:8080/realms/arquisoft
spring.security.oauth2.resourceserver.jwt.jwk-set-uri=http://localhost:8080/realms/arquisoft/protocol/openid-connect/certs
```

## Despliegue Remoto (Servidor de Desarrollo)

### Ambiente de Despliegue

| Parámetro | Valor |
|-----------|-------|
| **Sistema Operativo** | Windows 11 Pro |
| **IP** | `<SERVER_IP>` |
| **Acceso SSH** | Puerto `<SSH_PORT>`, usuario `<SSH_USER>` |
| **Puerto HTTPS** | 443 (Traefik como reverse proxy) |
| **Herramientas** | Docker, Git, Chocolatey |

> ⚠️ Los valores reales de IP, puerto SSH y usuario se deben obtener del administrador del sistema.

### Pasos para Despliegue

#### 1. Conectar al Servidor

```bash
ssh -p <SSH_PORT> <SSH_USER>@<SERVER_IP>
```

#### 2. Clonar Repositorio (primera vez)

```bash
git clone <url-arquisoft-infra>
cd arquisoft-infra
```

O actualizar si ya existe:

```bash
cd arquisoft-infra
git pull origin develop
```

#### 3. Generar Credenciales Seguras

```bash
bash scripts/setup-env.sh
```

> ⚠️ Guardar las credenciales generadas en un lugar seguro. El archivo `.env` tiene permisos 600.

#### 4. Iniciar Infraestructura

```bash
bash scripts/start.sh dev
```

#### 5. Validar Despliegue

```bash
bash scripts/health-check.sh
bash scripts/validate-dev.sh
bash scripts/validate-security.sh
```

> Los tres scripts deben terminar con exit code 0. `validate-security.sh` debe reportar **0 errores, 0 warnings**.

### Limpieza de Infraestructura Legacy

Si existe un despliegue anterior que debe limpiarse:

```bash
# Detener y eliminar contenedores, redes y volúmenes
docker-compose down -v --remove-orphans
docker network prune -f
docker volume prune -f

# Verificar limpieza
docker ps -a && docker volume ls && docker network ls
```

### Notas para Windows

- Usar **Git Bash** o **WSL** para ejecutar los scripts bash
- Los permisos de archivo (`chmod 600`) no aplican nativamente; Docker gestiona los permisos internamente
- `validate-security.sh` detecta Windows automáticamente: usa `netstat -an` con filtrado de columna Local Address (evita falsos positivos con Foreign Address `0.0.0.0:0`) y omite verificación de permisos `.env`/`.htpasswd`

---

## Despliegue a Producción

### Checklist Pre-Despliegue

Antes de ejecutar el despliegue a producción, verificar que se cumplen todos los prerrequisitos:

- [ ] **DNS configurado:** Registros A/CNAME para `DOMAIN`, `api.DOMAIN`, `auth.DOMAIN` apuntando a la IP del servidor
- [ ] **Puertos abiertos:** 80 (HTTP, requerido por Let's Encrypt challenge) y 443 (HTTPS)
- [ ] **Acceso SSH:** Conectividad al servidor de producción
- [ ] **Docker instalado:** Docker Engine 24.x+ y Docker Compose v2.20+
- [ ] **Repositorio clonado:** `arquisoft-infra` en el servidor
- [ ] **`.env` generado:** Ejecutar `setup-env.sh` con dominio real (no `*.localhost`)
- [ ] **`ACME_EMAIL` configurado:** Email válido en `.env` para notificaciones Let's Encrypt
- [ ] **`.htpasswd` generado:** Credenciales BasicAuth para consolas admin (generado por `setup-env.sh`)

### Pasos de Ejecución

#### 1. Configurar DNS

Crear registros DNS apuntando al servidor de producción:

| Registro | Tipo | Valor |
|----------|------|-------|
| `DOMAIN` | A | `<IP_SERVIDOR>` |
| `api.DOMAIN` | CNAME | `DOMAIN` |
| `auth.DOMAIN` | CNAME | `DOMAIN` |
| `grafana.DOMAIN` | CNAME | `DOMAIN` |

Verificar propagación DNS:

```bash
nslookup DOMAIN
nslookup api.DOMAIN
nslookup auth.DOMAIN
```

> ⚠️ La propagación DNS puede tardar entre 5 minutos y 48 horas. Let's Encrypt requiere que el dominio resuelva al servidor **antes** de emitir certificados.

#### 2. Generar Credenciales de Producción

```bash
cd arquisoft-infra

# Generar .env con credenciales seguras
# El script detecta dominio no-localhost y solicita ACME_EMAIL automáticamente
bash scripts/setup-env.sh
```

#### 3. Verificar Configuración

```bash
# Verificar que DOMAIN y ACME_EMAIL están correctos
grep -E '^(DOMAIN|ACME_EMAIL)=' .env

# Verificar que .htpasswd fue generado
ls -la configs/traefik/certs/.htpasswd
```

#### 4. Iniciar Infraestructura de Producción

```bash
bash scripts/start.sh prod
```

> Esperar ~60 segundos para que Let's Encrypt emita los certificados SSL. Traefik solicita los certificados automáticamente al iniciar.

#### 5. Validar Despliegue

```bash
# Validación automatizada de producción
bash scripts/validate-prod.sh
```

El script verifica: DNS, SSL, HTTPS, redirects, headers de seguridad, recursos y healthchecks.

### Verificación Post-Despliegue

Después de ejecutar `validate-prod.sh`, verificar manualmente:

| Verificación | Comando/URL | Esperado |
|-------------|-------------|----------|
| App HTTPS | `https://DOMAIN` | HTTP 200 con certificado válido |
| API HTTPS | `https://api.DOMAIN` | HTTP 200/302 con certificado válido |
| Auth HTTPS | `https://auth.DOMAIN` | HTTP 200/302 (Keycloak login) |
| Redirect HTTP→HTTPS | `curl -I http://DOMAIN` | 301/308 → `https://DOMAIN` |
| Certificado SSL | Icono candado en navegador | Let's Encrypt (R3/R10) |
| Recursos | `docker stats --no-stream` | Dentro de limits del compose |
| Backup | `bash scripts/backup.sh all` | Backup completado sin errores |
| Health checks | `bash scripts/health-check.sh` | Todos los servicios healthy |

### Troubleshooting SSL / Let's Encrypt

#### Certificado no emitido

```bash
# Ver logs de Traefik para errores ACME
docker logs arquisoft-traefik 2>&1 | grep -i "acme\|certificate\|challenge"

# Verificar que el puerto 80 es accesible desde Internet
curl -I http://DOMAIN  # Debe responder (Traefik escucha)
```

**Causas comunes:**
- DNS no propagado (verificar con `nslookup DOMAIN`)
- Puerto 80 bloqueado por firewall
- `ACME_EMAIL` vacío o inválido
- Rate limit excedido (ver abajo)

#### Rate Limits de Let's Encrypt

| Límite | Valor |
|--------|-------|
| Certificados por dominio registrado | 50/semana |
| Duplicados exactos | 5/semana |
| Solicitudes fallidas | 5/hora |

Para pruebas iniciales, considerar usar el **staging** de Let's Encrypt (certificados no válidos para navegador, pero sin rate limits):

```bash
# En docker-compose.prod.yaml, agregar temporalmente al command de Traefik:
# --certificatesresolvers.letsencrypt.acme.caserver=https://acme-staging-v02.api.letsencrypt.org/directory
```

> ⚠️ Remover la línea de staging y reiniciar para obtener certificados reales después de verificar que todo funciona.

#### Renovación de Certificados

Traefik renueva automáticamente los certificados 30 días antes de su expiración. Los certificados Let's Encrypt tienen validez de 90 días.

Verificar estado de certificados:

```bash
# Fecha de expiración del certificado actual
echo | openssl s_client -servername DOMAIN -connect DOMAIN:443 2>/dev/null | openssl x509 -noout -enddate

# Verificar archivo acme.json (almacén de certificados de Traefik)
docker exec arquisoft-traefik ls -la /etc/traefik/certs/acme.json
```

---

## Operaciones Comunes

### Ver Logs

```bash
# Todos los servicios
docker compose logs -f

# Servicio específico
docker compose logs -f postgres
docker compose logs -f rabbitmq
```

### Reiniciar Servicio

```bash
docker compose restart keycloak
```

### Backup

```bash
# Backup completo
./scripts/backup.sh all

# Solo PostgreSQL
./scripts/backup.sh postgres
```

### Detener Todo

```bash
# Mantener datos
./scripts/stop.sh

# Eliminar datos (cuidado!)
./scripts/stop.sh --volumes
```

## Troubleshooting

### Puerto en Uso

```bash
# Identificar proceso
netstat -tulpn | grep 5432
lsof -i :5432

# Matar proceso
kill -9 <PID>
```

### Contenedor No Inicia

```bash
# Ver logs del contenedor
docker logs arquisoft-postgres

# Verificar estado
docker inspect arquisoft-postgres
```

### Reiniciar desde Cero

```bash
# Detener y eliminar todo
./scripts/stop.sh --volumes --prune

# Volver a iniciar
./scripts/start.sh dev
```

### Problemas de Memoria

Si Docker se queda sin memoria:

```bash
# Limpiar recursos no utilizados
docker system prune -a

# Verificar uso
docker system df
```

## Próximos Pasos

1. **Desarrollar Backend**: Conectar aplicación Spring Boot a la infraestructura
2. **Configurar CI/CD**: Pipeline de integración continua
3. **Probar Observabilidad**: Verificar métricas y logs en Grafana
4. **Personalizar Keycloak**: Agregar usuarios de prueba
