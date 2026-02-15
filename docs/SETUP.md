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

### Ambiente de Despliegue\n\n| Parámetro | Valor |\n|-----------|-------|\n| **Sistema Operativo** | Windows 11 Pro |\n| **IP** | `<SERVER_IP>` |\n| **Acceso SSH** | Puerto `<SSH_PORT>`, usuario `<SSH_USER>` |\n| **Puerto HTTPS** | 443 (Traefik como reverse proxy) |\n| **Herramientas** | Docker, Git, Chocolatey |\n\n> ⚠️ Los valores reales de IP, puerto SSH y usuario se deben obtener del administrador del sistema.\n\n### Pasos para Despliegue\n\n#### 1. Conectar al Servidor\n\n```bash\nssh -p <SSH_PORT> <SSH_USER>@<SERVER_IP>\n```

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
- `netstat` en Windows tiene output diferente; usar Git Bash para compatibilidad con los scripts de validación

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
