# sonarqube — análisis estático de calidad de código (herramienta aislada)

SonarQube **Community Build** con su propio PostgreSQL. Recibe los análisis que
ejecutan los pipelines de GitHub Actions de `arquisoft-backend` y
`arquisoft-frontend` y publica el reporte (bugs, vulnerabilidades, *code
smells*, cobertura, duplicación y Quality Gate) en `https://sonar.<DOMAIN>`.

> **Independiente de la plataforma.** No forma parte de `deploy.sh` ni del `.env`
> de la raíz: lee su propio `.env` de esta carpeta y se levanta por su cuenta.
> Ningún servicio de la aplicación depende de él.

| | |
|---|---|
| Imagen | `sonarqube:26.10.0.133078-community` (versión fijada, amd64 y arm64) |
| Base de datos | `postgres:18-alpine` dedicada, en la red interna `arquisoft-sonarqube-internal` |
| UI y API | `https://sonar.<DOMAIN>` vía Traefik (sin puertos publicados al host) |
| Persistencia | volúmenes `arquisoft-sonarqube-{db-data,data,extensions,logs}` |
| Recursos | SonarQube: límite 4 GB / 2 CPU (reserva 2 GB). BD: límite 512 MB / 1 CPU |

## Cómo funciona

```
push / PR ──> GitHub Actions (backend o frontend)
                1. compila y corre los tests (+ cobertura)
                2. scanner de Sonar ──HTTPS + token──> https://sonar.<DOMAIN>
                3. espera el Quality Gate (si falla, el job falla)
```

El análisis lo ejecuta el CI, no el servidor: SonarQube solo procesa y guarda
los resultados.

### Limitaciones de Community Build

- Analiza **una sola rama** por proyecto (`main`). No analiza otras ramas ni PRs,
  y no comenta en los PRs de GitHub (eso es de las ediciones de pago).
- Por eso los pipelines solo ejecutan el análisis en `push` a `main`.

## Requisitos previos

1. **DNS.** El registro **A de `sonar.<DOMAIN>`** debe apuntar a la IP pública
   del servidor **antes** de levantar el servicio. Traefik usa el desafío
   HTTP-01 de Let's Encrypt: si el nombre no resuelve, el certificado falla.
   No hay que abrir puertos nuevos: Traefik ya escucha en 80/443.
2. **Kernel.** El Elasticsearch embebido exige `vm.max_map_count >= 524288`:

   ```bash
   sysctl vm.max_map_count        # verificar
   # Si es menor:
   echo 'vm.max_map_count=524288' | sudo tee /etc/sysctl.d/99-sonarqube.conf
   sudo sysctl --system
   ```
3. **Memoria.** Unos 2–4 GB libres en el servidor.

## Despliegue

```bash
cd ~/arquisoft-infra && git pull
cd components/sonarqube
cp .env.example .env
# Rellenar SONAR_DB_PASSWORD, p. ej.:
sed -i "s|^SONAR_DB_PASSWORD=.*|SONAR_DB_PASSWORD=$(openssl rand -base64 32 | tr -d '/+=' | cut -c1-32)|" .env
chmod 600 .env

docker compose config --quiet   # validar
docker compose up -d
docker compose ps               # esperar a (healthy); el 1er arranque tarda 2–4 min
docker compose logs -f sonarqube
```

Modo local, sin Traefik ni TLS (UI en `http://127.0.0.1:9000`):

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

## Configuración inicial (una sola vez, desde la UI)

1. Entrar a `https://sonar.<DOMAIN>` con `admin` / `admin`. SonarQube **obliga a
   cambiar la contraseña** en el primer inicio. Guardarla en el gestor del equipo.
2. **Administration → Configuration → General → Server base URL** =
   `https://sonar.<DOMAIN>` (los links del CI y de los correos usan este valor).
3. **Administration → Security → Force user authentication**: activado (valor por
   defecto). Así el código analizado no queda público.
4. Crear los proyectos (*Create project → Local project*):

   | Project key | Rama principal |
   |---|---|
   | `arquisoft-backend` | `main` |
   | `arquisoft-frontend` | `main` |

5. Crear un token para el CI: **My Account → Security → Generate token**,
   tipo *Project analysis token* (uno por proyecto) o *Global analysis token*.
6. Usuarios del equipo: **Administration → Security → Users → Create user**.

## Secretos de GitHub (en cada repo que se analiza)

| Secret | Valor |
|---|---|
| `SONAR_TOKEN` | token generado en el paso 5 |
| `SONAR_HOST_URL` | `https://sonar.<DOMAIN>` |

La configuración del scanner vive en cada repo (`build.gradle` + workflow en el
backend, `sonar-project.properties` + workflow en el frontend).

## Backup y restauración

Lo único que hay que respaldar es la BD (los índices de Elasticsearch se
reconstruyen solos desde ella).

```bash
# Backup
docker exec arquisoft-sonarqube-db pg_dump -U sonarqube -d sonarqube -Fc \
  > ~/arquisoft-infra/backups/sonarqube_$(date +%Y%m%d_%H%M%S).dump

# Restauración (con SonarQube detenido)
docker compose stop sonarqube
docker exec -i arquisoft-sonarqube-db pg_restore -U sonarqube -d sonarqube --clean --if-exists \
  < ~/arquisoft-infra/backups/sonarqube_<ts>.dump
docker compose start sonarqube
```

## Actualización de versión

Community Build publica una versión al mes. Para actualizar:

1. Leer las notas de versión (a veces exigen pasar por una versión intermedia).
2. Hacer **backup** de la BD (sección anterior).
3. Cambiar la etiqueta `image:` en `docker-compose.yml`, commit + PR + `git pull`.
4. `docker compose up -d`. Si la UI muestra *maintenance*, entrar a
   `https://sonar.<DOMAIN>/setup` y lanzar la migración de la BD.

## Operación

```bash
docker compose ps
docker compose logs -f sonarqube
docker compose restart sonarqube
docker compose down          # detener (conserva los datos)
docker compose down -v       # BORRA todos los análisis (destructivo)
```

## Problemas comunes

| Síntoma | Causa / solución |
|---|---|
| El contenedor se reinicia con `max virtual memory areas vm.max_map_count [...] is too low` | Ajustar `vm.max_map_count` (Requisitos previos, paso 2). |
| Certificado inválido en `sonar.<DOMAIN>` | Falta el registro DNS A, o aún no propaga. Ver `docker logs arquisoft-traefik`. |
| `404` en `sonar.<DOMAIN>` | SonarQube no está *healthy* todavía, o Traefik no lo ve: revisar que esté en `arquisoft-network`. |
| El CI falla con `401` | `SONAR_TOKEN` incorrecto o revocado. |
| Se cae por memoria (OOMKilled) | Subir `limits.memory` de `sonarqube` (mínimo recomendado 2 GB). |
