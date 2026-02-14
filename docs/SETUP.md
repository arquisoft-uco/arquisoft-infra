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
git clone https://github.com/UCO/arquisoft.git
cd arquisoft/infrastructure
```

### 2. Configurar Variables de Entorno

```bash
# Crear archivo de configuración
cp .env.example .env

# Editar configuración (opcional para desarrollo)
# nano .env
```

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
| RabbitMQ | http://localhost:15672 | admin / admin |
| MinIO Console | http://localhost:9001 | minioadmin / minioadmin123 |
| Keycloak | http://localhost:8180/admin | admin / admin |
| Grafana | http://localhost:3001 | admin / admin |
| Prometheus | http://localhost:9090 | - |
| Traefik Dashboard | http://localhost:8081 | - |

### Con Traefik Proxy

Agregar a `/etc/hosts` (Linux/Mac) o `C:\Windows\System32\drivers\etc\hosts` (Windows):

```
127.0.0.1 arquisoft.localhost
127.0.0.1 auth.arquisoft.localhost
127.0.0.1 grafana.arquisoft.localhost
127.0.0.1 storage.arquisoft.localhost
```

Luego acceder a:
- http://arquisoft.localhost - Aplicación
- http://auth.arquisoft.localhost - Keycloak
- http://grafana.arquisoft.localhost - Grafana

## Configuración de Servicios

### PostgreSQL

La base de datos se inicializa automáticamente con:
- 10 schemas (uno por bounded context)
- Tabla de auditoría
- Trigger de auditoría

Conexión desde aplicación:
```properties
spring.datasource.url=jdbc:postgresql://localhost:5432/arquisoft
spring.datasource.username=arquisoft
spring.datasource.password=arquisoft_dev_123
```

Schemas disponibles:
- `usuarios` - Gestión de usuarios y roles
- `fichas` - Fichas de trabajo de grado
- `proyectos` - Proyectos de grado
- `artefactos` - Artefactos de proyectos
- `repositorio` - Repositorio de artefactos
- `evaluaciones` - Evaluaciones definitivas
- `mapas_ruta` - Mapas de ruta
- `biblioteca` - Biblioteca institucional
- `solicitudes` - Solicitudes del sistema
- `notificaciones` - Sistema de notificaciones

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
spring.rabbitmq.username=arquisoft
spring.rabbitmq.password=arquisoft_dev_123
spring.rabbitmq.virtual-host=arquisoft
```

### MinIO

Bucket por defecto: `arquisoft-files`

Configuración:
```properties
minio.url=http://localhost:9000
minio.access-key=minioadmin
minio.secret-key=minioadmin123
minio.bucket=arquisoft-files
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
spring.security.oauth2.resourceserver.jwt.issuer-uri=http://localhost:8180/realms/arquisoft
spring.security.oauth2.resourceserver.jwt.jwk-set-uri=http://localhost:8180/realms/arquisoft/protocol/openid-connect/certs
```

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
