# MinIO en Coolify — Manual de Configuración, Instalación y Despliegue

## 1. Contexto, alternativas evaluadas y decisión final

### Por qué MinIO original ya no aplica

A finales de octubre de 2025, MinIO dejó de publicar imágenes Docker en Docker Hub y Quay.io. En diciembre de 2025 entró en modo mantenimiento y en abril de 2026 el repositorio fue archivado (solo lectura). El último tag oficial disponible fue `RELEASE.2025-10-15T17-29-55Z`. MinIO sigue siendo técnicamente software open source bajo AGPL v3, pero es software abandonado sin parches de seguridad futuros.

### Restricción técnica del proyecto

El proyecto tiene como restricción técnica el uso de alternativas open source bajo licencias válidas. Los criterios relevantes para evaluar si una licencia es "válida" en este contexto son:

- Licencia aprobada por la OSI (Open Source Initiative)
- Software activamente mantenido (recibe actualizaciones y parches de seguridad)
- Aplicable a uso en red privada sin obligaciones adicionales sobre el código del backend

### Alternativas evaluadas

| Proyecto | Licencia (SPDX) | OSI aprobada | Estado (mayo 2026) | Producción | Consola web | Compat. S3 |
|---|---|---|---|---|---|---|
| **MinIO** (original) | AGPL-3.0 | Sí | Archivado (abr 2026) | **No** — sin mantenimiento | Sí (última versión) | Completa |
| **pgsty/minio** (fork) | AGPL-3.0 | Sí | Activo (abr 2026) | **Sí** | Sí (restaurada) | Completa |
| **Garage** | AGPL-3.0 | Sí | Activo (v2.2.0, ene 2026) | **Sí** | No (solo CLI) | Parcial (sin versionado) |
| **RustFS** | Apache-2.0 | Sí | Beta (v1.0.0-beta.3) | **No** — explícitamente no recomendado para producción | Sí | Completa (en desarrollo) |

### Análisis de cada alternativa

**`pgsty/minio`** es un fork comunitario de MinIO creado como respuesta directa al abandono del proyecto original. Está disponible en Docker Hub (`pgsty/minio`), aplica parches de CVEs sobre el código fuente original de MinIO, restaura la consola web completa (que MinIO Inc. eliminó de la edición comunitaria), mantiene compatibilidad binaria total con el protocolo S3 de MinIO y sigue siendo AGPL v3. Última actualización registrada: 17 de abril de 2026. Es una opción de drop-in replacement: ningún cliente SDK ni configuración existente requiere cambios.

**Garage** (garagehq.deuxfleurs.fr) es un servidor de objetos S3-compatible escrito en Rust, desarrollado por la cooperativa de alojamiento francesa Deuxfleurs desde 2020 y con financiación de la UE. La versión 2.2.0 fue lanzada en enero de 2026 y tuvo presentación en FOSDEM 2026. Está en producción en múltiples organizaciones sin fines de lucro. Su diseño está optimizado para despliegues distribuidos geo-replicados entre múltiples nodos; en modo nodo único funciona pero sin redundancia de datos. No implementa versionado de objetos ni la consola web, la gestión de buckets se hace por CLI o API S3.

**RustFS** (github.com/rustfs/rustfs) es una reescritura completa en Rust del servidor S3, con licencia Apache 2.0 (más permisiva que AGPL). Fue publicado como open source en julio de 2025, tiene 27.4k estrellas en GitHub y en mayo de 2026 llegó a la versión beta.3. Su propia documentación oficial advierte explícitamente que no debe usarse en entornos de producción. Su ingreso al programa NVIDIA Inception (abril 2026) sugiere que apunta a un mercado comercial. Es la opción a monitorear para el mediano plazo (estimado de madurez: segundo semestre 2026 o 2027).

### Decisión: `pgsty/minio`

Para este proyecto, `pgsty/minio` es la mejor opción porque:

1. **Cumple la restricción open source**: AGPL v3, aprobada por OSI, código público y auditado.
2. **Mantenimiento activo**: aplica parches de seguridad sobre el código fuente de MinIO, incluyendo CVEs.
3. **Compatibilidad S3 completa**: el backend Spring Boot no requiere cambios en el SDK ni en la configuración.
4. **Consola web funcional**: permite la gestión manual de buckets sin herramientas adicionales.
5. **Multi-arquitectura**: imágenes disponibles para AMD64 y ARM64.
6. **Contexto del proyecto**: red privada, uso académico, carga ligera — el fork mantiene la madurez del código de MinIO sin el riesgo de usar software de un proveedor comercial sin soporte.

La restricción técnica de open source **sí aplica** a este componente (es software que se despliega y opera directamente en la infraestructura del proyecto, no un servicio de terceros). La decisión de usar `pgsty/minio` en lugar del MinIO original **refuerza** el cumplimiento de esa restricción, ya que el fork está activamente mantenido y el original está abandonado.

---

## 2. Legalidad: AGPL v3 y el backend Spring Boot

`pgsty/minio` hereda la licencia AGPL v3 del proyecto original. Los efectos sobre el backend son idénticos a los del MinIO original.

La cláusula central del AGPLv3 (Sección 13) exige compartir el código fuente solo si se **modifica** el código de MinIO y se proporciona ese servicio modificado a través de una red. Las condiciones de este proyecto eliminan ese requerimiento:

1. No se modifica el código fuente de MinIO ni del fork.
2. El backend accede a MinIO exclusivamente vía protocolo S3 estándar (SDK Java).
3. Los usuarios finales interactúan con la aplicación web, no directamente con MinIO.
4. El servicio corre en red privada.

La interpretación estándar del AGPLv3 (Software Freedom Conservancy) establece que comunicarse con un servidor AGPL a través de una interfaz de red usando protocolos estándar no crea una obra derivada ni obliga a publicar el código cliente. Para un proyecto académico sin ánimo de lucro en red privada, el riesgo legal es mínimo.

---

## 3. Requerimientos de infraestructura

### 3.1 Contexto de carga del proyecto

Con 200 usuarios semanales que interactúan a través de una aplicación web, el volumen de tráfico real es:

- **Usuarios concurrentes promedio:** 5–15 (distribución en horario académico)
- **Pico de concurrencia estimado:** 30–40 usuarios simultáneos
- **Solicitudes por segundo (promedio):** ~1–2 RPS totales al servidor
- **Solicitudes por segundo (pico):** ~4–6 RPS en horario de mayor actividad
- **Carga sobre el almacenamiento:** operaciones puntuales de carga/descarga de archivos, no flujo continuo

Esta carga es ligera para cualquier infraestructura moderna. Un servidor de gama media puede manejar este stack completo sin degradación.

> **Referencia de escala:** Para volúmenes similares (plataformas educativas universitarias con Spring Boot + PostgreSQL + almacenamiento de objetos), el stack completo consume entre 3–6 GB RAM en estado estable con picos de hasta 8–10 GB durante cargas máximas concurrentes. Fuente: análisis de carga documentado en [SystemsArchitect.io](https://www.systemsarchitect.io/docs/requirements/estimates/initial/rps-requests-per-second) y deployments de referencia en la comunidad de Coolify.

---

### 3.2 Sizing por servicio

La siguiente tabla muestra los requerimientos reales para este proyecto (no los requerimientos enterprise de MinIO para miles de usuarios concurrentes):

| Servicio | RAM Reserva | RAM Límite | CPU Reserva | CPU Límite |
|---|---|---|---|---|
| PostgreSQL | 512 MB | 1 GB | 0.5 cores | 1.5 cores |
| Keycloak | 512 MB | 1 GB | 0.5 cores | 1.0 core |
| RabbitMQ | 200 MB | 300 MB | 0.25 cores | 0.5 cores |
| pgsty/minio | 256 MB | 512 MB | 0.25 cores | 0.5 cores |
| Spring Boot backend | 512 MB | 1 GB | 0.5 cores | 1.0 core |
| Frontend (Nginx) | 64 MB | 128 MB | 0.05 cores | 0.1 cores |
| Prometheus | 150 MB | 300 MB | 0.1 cores | 0.25 cores |
| Loki | 150 MB | 300 MB | 0.1 cores | 0.25 cores |
| Grafana | 128 MB | 256 MB | 0.05 cores | 0.1 cores |
| Traefik | 64 MB | 256 MB | 0.05 cores | 0.1 cores |
| OS + Docker overhead | ~1 GB | — | ~0.5 cores | — |
| **TOTAL** | **~3.5 GB** | **~5.9 GB** | **~3 cores** | **~5.3 cores** |

> **Nota sobre sizing de MinIO/pgsty/minio:** La documentación oficial de MinIO publica requerimientos de 8 GB RAM y 4 cores como mínimo, pero esos valores corresponden a cargas enterprise con miles de operaciones por segundo y terabytes de datos. Para este proyecto (operaciones de archivos ocasionales, menos de 50 usuarios concurrentes), 256–512 MB RAM y 0.25–0.5 cores son suficientes, como lo confirma la configuración existente en `docker-compose.prod.yaml`.

---

### 3.3 Sizing del servidor

#### Límite inferior (mínimo funcional)

**4 cores — 8 GB RAM — 80 GB SSD**

- Funciona con el stack completo en estado estable. Los límites definidos (~5.9 GB) dejan ~2 GB de margen.
- Sin holgura para picos simultáneos de Keycloak + backend + tarea de backup. Si algún servicio necesita más memoria al arranque, puede haber contención.
- 80 GB de disco cubre el software y aproximadamente 50 GB de datos en el almacenamiento de objetos.
- Referencia: Coolify documenta 4 GB RAM y 2 CPU como mínimo de producción para múltiples servicios. Con 8 GB se duplica ese mínimo, lo que es razonable para este stack.

#### Recomendado

**4 cores — 16 GB RAM — 150 GB SSD**

- Todos los servicios pueden operar en sus límites definidos con ~10 GB libres de margen.
- Soporta crecimiento hasta 600–800 usuarios semanales sin cambios de configuración.
- Permite ejecutar tareas de mantenimiento (backups, reindexado) sin afectar el rendimiento de usuarios activos.
- Aumenta la retención de logs y métricas en Prometheus y Loki.
- Referencia de mercado: Hetzner CX31 (4 vCPU, 16 GB, 160 GB NVMe, ~€11/mes) es la configuración más común en la comunidad de Coolify para stacks de esta naturaleza.

#### Óptimo

**8 cores — 32 GB RAM — 200 GB NVMe SSD**

- Adecuado si el proyecto crece a 1000–2000 usuarios semanales, o si Keycloak pasa a ser el IdP de múltiples aplicaciones del ecosistema.
- Permite duplicar los límites de recursos por servicio y agregar instancias adicionales del backend con balanceo de carga por Traefik.
- Soporta hasta 200 usuarios concurrentes simultáneos sin degradación.
- El tipo de disco NVMe impacta directamente en la latencia de escritura de MinIO y PostgreSQL: ~0.1 ms (NVMe) vs ~1 ms (SSD SATA), perceptible en cargas de subida simultánea de archivos.

---

### 3.4 Almacenamiento: estimación de crecimiento en MinIO

| Escenario | Tamaño promedio por artefacto | Cargas por usuario/semana | Crecimiento mensual | Crecimiento anual |
|---|---|---|---|---|
| Conservador (documentos, diagramas) | 2 MB | 3 | ~5 GB | ~60 GB |
| Moderado (código + documentos) | 10 MB | 3 | ~25 GB | ~300 GB |
| Alto (binarios, multimedia) | 50 MB | 2 | ~80 GB | ~1 TB |

Para el escenario conservador (típico de un proyecto académico de arquitectura de software), 80–100 GB son suficientes para el primer año. Para el escenario moderado, planificar al menos 200–300 GB dedicados a MinIO. Coolify permite agregar volúmenes adicionales al servidor sin redesplegue del contenedor.

---

## 4. Archivo de referencia

El archivo Docker Compose para este despliegue se encuentra en:

`coolify/docker-compose.minio.yml`

Este archivo define el servicio `minio` con imagen `pgsty/minio:RELEASE.2026-04-17T00-00-00Z`, configuración de Traefik para dos dominios (API S3 y consola web), healthcheck via `mcli ready local`, volumen de datos persistente, límites de recursos y logging.

> **Tag anclado:** La imagen está fijada a `RELEASE.2026-04-17T00-00-00Z`, el último release verificado de `pgsty/minio` al momento de la escritura de este manual (mayo 2026). Para actualizar, consultar las releases en `github.com/pgsty/minio/releases`, ejecutar un nuevo escaneo Trivy sobre el tag candidato, y si el resultado es aceptable, actualizar el tag en el compose y redesplegar desde Coolify.

---

## 5. Prerrequisitos

- Coolify instalado y operativo en el servidor de producción.
- Proyecto `arquisoft-project` creado con el ambiente `production` activo.
- Dominio base registrado con acceso al panel DNS del proveedor.
- Dos subdominios DNS por crear (ver sección 6).
- IP pública del servidor conocida.

---

## 6. Configuración DNS

MinIO requiere dos subdominios: el servidor S3 (API) y la consola web operan en puertos distintos.

En el panel DNS del proveedor, crear los siguientes registros tipo **A**:

| Subdominio | Tipo | Valor | Descripción |
|---|---|---|---|
| `minio.arquisoft.top` | A | IP pública del servidor | Consola web de MinIO |
| `s3.arquisoft.top` | A | IP pública del servidor | Endpoint API S3 (requerido para login de consola y presigned URLs) |

Verificar propagación antes de desplegar:

```
nslookup minio.arquisoft.top
nslookup s3.arquisoft.top
```

Ambos deben retornar la IP del servidor. La propagación puede tomar entre 5 minutos y 2 horas.

---

## 7. Variables de entorno

Configurar en `Environment Variables` del recurso en Coolify **antes** del primer despliegue:

| Variable | Descripción | Ejemplo |
|---|---|---|
| `MINIO_ROOT_USER` | Usuario administrador raíz. Evitar valores genéricos como `admin` o `minio`. | `arquisoft-minio-admin` |
| `MINIO_ROOT_PASSWORD` | Contraseña del administrador raíz. Mínimo 8 caracteres, se recomienda 20+ caracteres aleatorios. | (generada con gestor de contraseñas) |
| `MINIO_API_DOMAIN` | Subdominio para la API S3, sin protocolo. Usado en los labels Traefik del compose. | `s3.arquisoft.top` |
| `MINIO_CONSOLE_DOMAIN` | Subdominio para la consola web, sin protocolo. | `minio.arquisoft.top` |

A partir de esas variables, el compose construye internamente:

- **`MINIO_SERVER_URL`** (`https://${MINIO_API_DOMAIN}`): informa a MinIO cuál es su URL pública. La consola la usa para autenticar al usuario (hace una llamada interna a este endpoint) y para generar presigned URLs. **Requisito**: el dominio `MINIO_API_DOMAIN` debe tener DNS configurado apuntando al servidor y el certificado TLS de Let's Encrypt debe estar emitido antes de intentar el primer login. Si el cert no existe aún (recién se desplegó), el login falla con 503 hasta que Traefik lo emita.
- **`MINIO_BROWSER_REDIRECT_URL`** (`https://${MINIO_CONSOLE_DOMAIN}`): indica a MinIO la URL pública de su consola. MinIO la usa para redirigir al navegador cuando alguien accede al puerto S3 (9000) vía browser en lugar de un SDK. No interfiere con el tráfico del router de la consola (puerto 9001).

---

## 8. Despliegue en Coolify

### 8.1. Crear el recurso

1. Acceder al panel de Coolify y navegar al proyecto `arquisoft-project`, ambiente `production`.
2. En la vista `Resources`, dar clic en `+ New Resource`.
3. Seleccionar `Docker Compose Empty`.
4. Si Coolify solicita seleccionar servidor, seleccionar el servidor de producción.
5. Copiar y pegar el contenido completo del archivo `coolify/docker-compose.minio.yml`.
6. Dar clic en `Save`.

### 8.2. Asignar nombre al recurso

En `Configuration → General`, cambiar el nombre del recurso a `minio` y guardar.

### 8.3. Configurar variables de entorno

1. Ir a `Configuration → Environment Variables`.
2. Agregar las cuatro variables de la sección 7.
3. Guardar los cambios.

### 8.4. Dominios — dejar vacío en la UI de Coolify

Ambos dominios están gestionados íntegramente por las etiquetas Traefik en el compose (`traefik.http.routers.minio-console.*` y `traefik.http.routers.minio-api.*`). Traefik solicita los certificados TLS a Let's Encrypt directamente cuando detecta esos routers.

**No configurar ningún dominio en la UI de Coolify** (Services → Settings → Domains). Si se configura un dominio ahí, Coolify genera etiquetas Traefik adicionales que crean un router duplicado y conflictos de enrutamiento que se manifiestan como `ERR_TOO_MANY_REDIRECTS` o `ERR_NETWORK_CHANGED`.

> **Regla**: nunca mezclar `coolify.proxy.port` con routers Traefik explícitos para el mismo servicio. Elegir uno u otro. Para MinIO, donde se necesitan dos puertos con dos dominios diferentes, los routers explícitos son la única opción que funciona.

### 8.5. Desplegar

1. Dar clic en `Deploy`.
2. Monitorear los logs hasta confirmar que MinIO levantó correctamente.
3. Verificar que el estado del recurso sea `Running (healthy)`.

---

## 9. Verificación del despliegue

```
curl -I https://minio.arquisoft.top
```

Debe retornar `HTTP/2 200` o `HTTP/2 303`. Verificar también que el certificado TLS sea válido (Let's Encrypt) accediendo desde un navegador.

```
curl -I https://s3.arquisoft.top/minio/health/live
```

Debe retornar `HTTP/2 200`. Si hay error de conexión, verificar propagación DNS del subdominio `s3.arquisoft.top` y los logs del contenedor.

> El endpoint S3 es necesario aunque el backend use la red interna. La consola web (browser) hace llamadas al puerto 9000 durante el login (endpoint STS) y para operaciones sobre objetos.

---

## 10. Primer acceso a la consola

1. Abrir un navegador y acceder a `https://minio.arquisoft.top`.
2. Iniciar sesión con el usuario y contraseña configurados en `MINIO_ROOT_USER` y `MINIO_ROOT_PASSWORD`.
3. La consola cargará el panel principal de MinIO.

---

## 11. Creación manual de buckets

### Crear un bucket

1. En el menú lateral, ir a `Buckets`.
2. Dar clic en `Create Bucket`.
3. Ingresar el nombre del bucket en minúsculas (letras, números y guiones; sin guión inicial o final).
4. Dejar `Versioning` y `Object Locking` desactivados.
5. Dar clic en `Create Bucket`.

Buckets sugeridos para este proyecto: `artefactos`, `avatars`, `backups`.

### Configurar acceso público (solo para avatars)

1. Seleccionar el bucket `avatars`.
2. Ir a la pestaña `Access Policy`.
3. Cambiar la política a `Public` para acceso de lectura anónima.
4. Guardar.

Los buckets `artefactos` y `backups` deben permanecer en modo `Private`.

---

## 12. Creación de usuario de servicio para el backend

El backend **no debe usar las credenciales raíz**. Crear un Access Key dedicado:

1. En la consola, ir a `Access Keys` en el menú lateral.
2. Dar clic en `Create access key`.
3. Guardar el `Access Key` y el `Secret Key` generados antes de cerrar — el `Secret Key` no es recuperable.
4. Opcionalmente, restringir en `Policy` el acceso solo a los buckets que el backend necesita.

Parámetros de conexión para el SDK Java según la topología de despliegue:

- **Backend en el mismo servidor (red Docker `coolify`):** endpoint `http://minio:9000`, TLS deshabilitado. El nombre `minio` resuelve al contenedor dentro de la red Docker. Es la opción más eficiente — el tráfico no sale del servidor.

- **Backend en servidor diferente, misma red privada (LAN):** el puerto 9000 no está expuesto al host por defecto. Para habilitarlo sin exponerlo a internet, agregar en el compose la sección `ports` con un binding a la IP privada del servidor de MinIO:
  ```yaml
  ports:
    - "<ip-privada-servidor-minio>:9000:9000"
  ```
  El backend conecta entonces a `http://<ip-privada-servidor-minio>:9000`, TLS deshabilitado. Este puerto no es alcanzable desde internet, solo desde la LAN privada.

- **Backend en servidor diferente, sin red privada compartida:** descomentar los labels `minio-api` en el compose para exponer `s3.arquisoft.top` via Traefik. El backend conecta a `https://s3.arquisoft.top`, puerto `443`, TLS habilitado.

---

## 13. Persistencia y backup

Los datos se almacenan en el volumen Docker `minio_data`, gestionado por Coolify. Persiste entre reinicios y redespliegues. Para backup, usar la herramienta `mc` (MinIO Client) desde la terminal del servidor apuntando al endpoint interno, o hacer copia directa del directorio del volumen.

---

## 14. Análisis de seguridad — Escaneo Trivy

El siguiente escaneo fue ejecutado el **16 de mayo de 2026** sobre la imagen `pgsty/minio:RELEASE.2026-04-17T00-00-00Z` usando **Trivy v0.70.0** con base de datos de vulnerabilidades actualizada al momento de la ejecución. El escaneo cubre severidades MEDIUM, HIGH y CRITICAL.

Comando ejecutado:

```
trivy image --severity CRITICAL,HIGH,MEDIUM pgsty/minio:RELEASE.2026-04-17T00-00-00Z
```

### Resumen general

| Target | Tipo | CRITICAL | HIGH | MEDIUM |
|---|---|---|---|---|
| OS base (redhat 9.7) | Sistema operativo | **0** | 1 | 16 |
| `/usr/bin/mcli` | Binario Go (MinIO Client) | **0** | 7 | 5 |
| `/usr/bin/minio` | Binario Go (MinIO Server) | **0** | 8 | 6 |
| **TOTAL** | | **0** | **16** | **27** |
| **Secretos detectados** | | — | — | **Ninguno** |

**No se detectaron vulnerabilidades CRITICAL ni secretos embebidos en la imagen.**

---

### Capa del sistema operativo — redhat 9.7 (17 hallazgos)

**1 HIGH — CVE-2026-4878 en `libcap`**

| Campo | Valor |
|---|---|
| CVE | CVE-2026-4878 |
| Severidad | HIGH |
| Estado | **fixed** — parche disponible en `2.48-10.el9_7.1` |
| Descripción | Escalada de privilegios vía condición de carrera TOCTOU en `cap_set_file()` |

La función `cap_set_file()` requiere que el proceso la invoque explícitamente para ser vulnerable. MinIO no usa `cap_set_file()` en su flujo normal de operación. Sumado a la red privada y a que `security_opt: no-new-privileges:true` está configurado en el compose, la explotabilidad práctica es mínima. El parche está disponible a nivel del SO base; se resolverá cuando `pgsty` publique una imagen con la base RedHat 9.7 actualizada.

**16 MEDIUM — Vulnerabilidades en `glibc` y `coreutils-single`**

Todas tienen estado `affected` (RedHat aún no ha publicado parches upstream para RedHat 9.7). Los tipos de fallo incluyen: denegación de servicio vía `iconv()`, desbordamiento de búfer en `scanf`, fuga de información en `ungetwc`, y lectura fuera de límites en `sort`. Ninguno es explotable remotamente sin acceso directo al proceso del sistema operativo. No accionables hasta que RedHat libere los parches correspondientes.

---

### Binario `/usr/bin/mcli` — MinIO Client (12 hallazgos)

`mcli` es la herramienta de administración en línea de comandos incluida en la imagen. No es el servidor de objetos sino una utilidad de gestión. Todos los hallazgos tienen parche disponible.

**7 HIGH — dependencias Go (`stdlib`, `prometheus/prometheus`)**

| CVE | Biblioteca | Fix disponible | Descripción resumida |
|---|---|---|---|
| CVE-2026-33811 | stdlib | 1.25.10 / 1.26.3 | DoS vía CNAME extremadamente largo en DNS resolver con cgo |
| CVE-2026-33814 | stdlib | 1.25.10 / 1.26.3 | Loop infinito al procesar frames HTTP/2 SETTINGS |
| CVE-2026-39820 | stdlib | 1.25.10 / 1.26.3 | Entradas malformadas en `ParseAddress` de `net/mail` |
| CVE-2026-39836 | stdlib | 1.25.10 / 1.26.3 | Panic en `Dial`/`LookupPort` con byte NUL (solo Windows) |
| CVE-2026-42499 | stdlib | 1.25.10 / 1.26.3 | DoS en parsing de frases en `net/mail` |
| CVE-2026-42151 | prometheus | 0.311.3 | Vulnerabilidad en el sistema de monitoreo (detalles internos) |
| CVE-2026-42154 | prometheus | 0.311.3 | Vulnerabilidad en el sistema de monitoreo (detalles internos) |

**5 MEDIUM — dependencias Go (`stdlib`, `prometheus/prometheus`)**

Stored XSS en la UI de Prometheus, exposición de parámetros de query en `ReverseProxy`, inyección en templates `<script>`. Requieren acceso a la interfaz web de Prometheus para ser explotables, lo cual no aplica a este despliegue.

---

### Binario `/usr/bin/minio` — MinIO Server (14 hallazgos)

**8 HIGH — dependencias Go (`stdlib`, `prometheus`, `apache/thrift`, `Azure/go-ntlmssp`)**

Comparte los CVEs de `stdlib` y `prometheus` con `mcli`, más:

| CVE | Biblioteca | Fix disponible | Descripción resumida |
|---|---|---|---|
| CVE-2026-41602 | apache/thrift | 0.23.0 | Desbordamiento de entero en `TFramedTransport` (protocolo Thrift) |
| CVE-2026-33811 | stdlib | 1.25.10 / 1.26.3 | DNS resolver DoS vía CNAME largo |
| CVE-2026-33814 | stdlib | 1.25.10 / 1.26.3 | Loop infinito HTTP/2 |
| CVE-2026-39820 | stdlib | 1.25.10 / 1.26.3 | Parsing de email malformado |
| CVE-2026-39836 | stdlib | 1.25.10 / 1.26.3 | Panic con NUL byte (solo Windows) |
| CVE-2026-42499 | stdlib | 1.25.10 / 1.26.3 | DoS en net/mail |
| CVE-2026-42151 | prometheus | 0.311.3 | (ver arriba) |
| CVE-2026-42154 | prometheus | 0.311.3 | (ver arriba) |

**6 MEDIUM** — mismos CVEs de Prometheus XSS y stdlib `ReverseProxy` que en `mcli`.

---

### Interpretación del riesgo para este proyecto

**Riesgo efectivo: BAJO**

Los argumentos que reducen el riesgo práctico de estos hallazgos:

1. **Red privada**: todos los CVEs de red (DNS DoS, HTTP/2 loop, parsing de email) requieren que un atacante envíe tráfico malicioso al servidor MinIO. Al no estar expuesto a internet, el vector de ataque está eliminado para actores externos.

2. **Sin CVEs críticos**: ningún hallazgo permite ejecución remota de código arbitrario (RCE) sin autenticación previa. Este es el indicador más importante en un análisis de riesgo.

3. **Sin secretos embebidos**: Trivy no detectó tokens, contraseñas ni claves privadas hardcodeadas en la imagen.

4. **Mitigación activa en el compose**: `security_opt: no-new-privileges:true` bloquea la escalada de privilegios, lo que mitiga directamente el HIGH más relevante (CVE-2026-4878 en libcap).

5. **Parches disponibles**: el 100% de los HIGH en los binarios Go tienen versiones corregidas publicadas. La resolución depende de que `pgsty` publique una nueva imagen con las dependencias actualizadas.

**Acción recomendada**: monitorear `github.com/pgsty/minio/releases` para nuevas versiones. Cuando se publique una imagen posterior a `RELEASE.2026-04-17T00-00-00Z` que actualice `stdlib` a 1.26.3+ y `libcap` a 2.48-10.el9_7.1, actualizar el tag en el compose y redesplegar.

---

## 15. Consideraciones de seguridad en producción

### Medidas implementadas en el compose

- **Versión anclada** (`RELEASE.2026-04-17T00-00-00Z`): garantiza que el ambiente es reproducible y que una actualización inesperada del tag `:latest` no introduce cambios no auditados.
- **`security_opt: no-new-privileges:true`**: impide que cualquier proceso dentro del contenedor obtenga privilegios adicionales mediante `setuid`, `setgid` u otros mecanismos. Mitiga directamente CVE-2026-4878.
- **Puertos no expuestos al host por defecto**: los puertos 9000 y 9001 solo son accesibles dentro de la red Docker `coolify`. El acceso externo a la consola pasa por Traefik con TLS. El puerto 9000 (API S3) puede exponerse selectivamente a una IP privada via `ports:` si el backend está en otro servidor de la misma LAN (ver sección 12).
- **Logging con rotación**: limita el consumo de disco por logs de acceso.

### Medidas adicionales recomendadas en el servidor

**Bloqueo de egreso a internet desde el contenedor**

El contenedor de MinIO no necesita salir a internet. Configurar una regla de firewall en el servidor host que bloquee el tráfico saliente del contenedor hacia destinos externos. Esto convierte cualquier código comprometido en "ciego y mudo" frente a servidores de comando y control externos.

En un servidor Linux con iptables, identificar el ID del contenedor con `docker inspect minio --format '{{.NetworkSettings.Networks.coolify.IPAddress}}'` y agregar una regla de DROP para ese rango de IPs hacia destinos fuera de la red interna.

**Escaneo periódico con Trivy**

Volver a ejecutar el escaneo cada vez que se actualice la imagen o cada 30 días como mínimo:

```
trivy image --severity CRITICAL,HIGH,MEDIUM pgsty/minio:<nuevo-tag>
```

Si aparece algún CVE con severidad CRITICAL o un HIGH con estado `fixed` en una dependencia directa del binario `minio`, priorizar la actualización del tag antes del siguiente ciclo de despliegue.

**Credenciales**

- Usar contraseñas de al menos 20 caracteres aleatorios para `MINIO_ROOT_PASSWORD`. Los gestores de contraseñas como Bitwarden o 1Password generan contraseñas de esta longitud automáticamente.
- Las credenciales raíz no deben ser usadas por el backend de Spring Boot. Crear Access Keys con permisos limitados (sección 12 de este manual).
- Rotar las Access Keys de los usuarios de servicio cada 90 días o inmediatamente si se sospecha compromiso.

**Certificados TLS**

Let's Encrypt renueva los certificados automáticamente a través de Coolify. Verificar periódicamente en la UI de Coolify que los certificados estén vigentes y que las renovaciones automáticas funcionen correctamente.
