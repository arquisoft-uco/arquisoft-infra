# Despliegue con Terraform — Arquisoft IaC

Guía mínima para desplegar el stack con Terraform. El mismo código sirve para **dev** y
**prod**: solo cambian el *workspace*, el `.tfvars` y el `docker_host` de destino.

## Prerrequisitos

**En tu equipo (donde corres Terraform):**
- Terraform ≥ 1.6 y cliente `ssh`.
- Tu llave SSH privada del servidor.

**En el servidor destino:**
- Docker Engine instalado.
- El usuario SSH pertenece al grupo `docker` (`sudo usermod -aG docker <usuario>` y reconectar), o usas `root`.
- Puertos **80** y **443** abiertos desde Internet (Security Group del cloud + firewall del host).

**DNS (para certificados Let's Encrypt):** registros **A** apuntando a la IP pública del servidor:
| Tipo | Nombre | Valor |
|------|--------|-------|
| A | `<dominio-del-entorno>` | `<IP_SERVIDOR>` |
| A | `*.<dominio-del-entorno>` | `<IP_SERVIDOR>` |

> El comodín cubre todos los subdominios (`api`, `auth`, `grafana`, `minio`, `s3`, `rabbitmq`, `traefik`).
> El apex (`tudominio.tld`) requiere su propio registro A si despliegas el `frontend`.

---

## Dónde corres Terraform (2 modos)

El `docker_host` del `.tfvars` decide desde dónde operas y **dónde queda el state**:

| Modo | `docker_host` | Terraform corre en | State queda en |
|------|---------------|--------------------|----------------|
| **Desde tu equipo** (remoto por SSH) | `ssh://<alias>` (usa `~/.ssh/config`) | tu máquina | tu máquina |
| **En el servidor** (autónomo) | `unix:///var/run/docker.sock` | el servidor | el servidor |

Para el **modo servidor**, prepara el host una vez:
```bash
# 1. Instalar Terraform (ej. Ubuntu ARM64; ajusta arch/versión)
VER=1.15.7; cd /tmp
curl -fsSL -o tf.zip "https://releases.hashicorp.com/terraform/${VER}/terraform_${VER}_linux_arm64.zip"
python3 -c "import zipfile; zipfile.ZipFile('tf.zip').extractall('.')"   # si no hay 'unzip'
sudo mv terraform /usr/local/bin/ && sudo chmod +x /usr/local/bin/terraform

# 2. Clonar el repo PRIVADO con un token de GitHub de solo lectura
#    GitHub → Settings → Developer settings → Fine-grained tokens → Generate:
#    Repository access = solo 'arquisoft-infra', Permissions = "Contents: Read-only", con expiración.
git clone https://<TOKEN>@github.com/arquisoft-uco/arquisoft-infra.git ~/arquisoft-infra

# 3. Crear el .tfvars EN el servidor (gitignored, no viene en el clone),
#    con docker_host = "unix:///var/run/docker.sock" y sin docker_ssh_opts.
```

---

## Orden de comandos

Trabaja siempre desde `terraform/`:
```bash
cd terraform
terraform init      # una sola vez (descarga providers)
```

### DEV
```bash
# 1. Configurar el entorno (una vez): copia y edita docker_host, domain, acme_email
cp environments/dev.tfvars.example environments/dev.tfvars
chmod 600 environments/dev.tfvars

# 2. Seleccionar workspace dev
terraform workspace select dev || terraform workspace new dev

# 3. Revisar y aplicar
terraform plan  -var-file=environments/dev.tfvars
terraform apply -var-file=environments/dev.tfvars     # escribe 'yes'
```

### PROD
```bash
# 1. Configurar el entorno (una vez)
cp environments/prod.tfvars.example environments/prod.tfvars
chmod 600 environments/prod.tfvars

# 2. Seleccionar workspace prod
terraform workspace select prod || terraform workspace new prod

# 3. Revisar y aplicar
terraform plan  -var-file=environments/prod.tfvars
terraform apply -var-file=environments/prod.tfvars    # escribe 'yes'
```

### Diferencias entre entornos
Van en su respectivo `.tfvars` (nada en el código cambia):

| Variable | dev | prod |
|----------|-----|------|
| `docker_host` | destino de dev (p. ej. `ssh://oracle`) | destino de prod (p. ej. `ssh://usuario@IP` o socket local) |
| `domain` | `dev.tudominio.tld` | `tudominio.tld` |
| `expose_data_ports` | `true` (conectar BDs desde tu equipo) | `false` (datos solo en red interna) |
| `backend_image` / `frontend_image` | opcional | imagen a desplegar |

> Los **workspaces** aíslan el estado por entorno; nunca mezclan recursos de dev y prod.
> `ssh://<alias>` usa tu `~/.ssh/config` (usuario + llave), sin exponer IP ni ruta de clave en el `.tfvars`.

---

## Verificar que quedó bien

```bash
# 1. Contenedores arquisoft-* healthy en el servidor destino
ssh <servidor> 'docker ps'

# 2. Idempotencia: tras un apply, debe decir "No changes"
terraform plan -var-file=environments/<env>.tfvars

# 3. DNS resuelve a la IP del servidor
dig +short auth.<dominio-del-entorno>

# 4. TLS válido de Let's Encrypt y servicio respondiendo (200)
curl -sS -o /dev/null -w "%{http_code}\n" \
  https://auth.<dominio-del-entorno>/realms/<realm>/.well-known/openid-configuration
curl -sSv https://auth.<dominio-del-entorno>/ 2>&1 | grep -i 'issuer:'   # -> Let's Encrypt
```

Si un certificado no se emite, revisa DNS y reintenta forzando ACME:
```bash
ssh <servidor> 'docker restart arquisoft-traefik'
```

---

## Estado de Terraform: dónde vive y cómo reutilizarlo

Terraform guarda en el **archivo de estado** el mapa de todo lo que creó (contenedores, redes,
volúmenes, claves). Lo lee en cada `plan`/`apply` para calcular el diff y **converger** en vez de
recrear. Es el artefacto que debes **conservar** para hacer cambios futuros sin perder el rastro.

**Dónde queda** (un archivo por workspace, en la máquina que corrió el `apply` — tu equipo o el
servidor, según el modo de arriba):
```
terraform/terraform.tfstate.d/dev/terraform.tfstate     # workspace dev
terraform/terraform.tfstate.d/prod/terraform.tfstate    # workspace prod
```
Está **gitignored** (`*.tfstate*`), así que vive **solo donde se ejecutó Terraform**.

**Reutilizarlo en cambios futuros:**
- Ejecuta siempre desde el **mismo `terraform/`** y **mismo workspace** (`terraform workspace show`
  antes de aplicar) para que use ese estado.
- **No lo borres.** Si se pierde, Terraform "olvida" lo desplegado e intentará recrearlo (choque de
  nombres/puertos). Respáldalo:
  ```bash
  cp terraform.tfstate.d/dev/terraform.tfstate ~/backups/dev-$(date +%F).tfstate
  ```
- **Equipo o CI/CD** (varias máquinas comparten el mismo estado): usa un **backend remoto** cifrado
  con *locking* (S3/GCS/Azure). Descomenta el bloque `backend` en `versions.tf`, crea el
  bucket/tabla de lock y `terraform init` migrará el estado local al remoto.

---

## Claves generadas: dónde quedan y cómo verlas

**No se escriben a mano.** Terraform las genera con `random_password` durante el `apply` y las
**inyecta** a los contenedores como variables de entorno por el canal SSH.

**Dónde se almacenan:** únicamente en el **state de Terraform**, en claro, por workspace:
```
terraform/terraform.tfstate.d/<workspace>/terraform.tfstate   # dev, prod, ...
```
Están marcadas como `sensitive`, así que **no aparecen** en `plan`, `apply` ni logs, y **no** se
versionan (`*.tfstate*` está en `.gitignore`).

**Cómo visualizarlas** (asegúrate de estar en el workspace correcto: `terraform workspace show`):
```bash
# Todas las claves (nombre -> valor)
terraform output -json secrets | jq

# Una sola clave
terraform output -json secrets | jq -r '.rabbitmq_password'

# Atajos para las de uso frecuente
terraform output -raw grafana_admin_password
terraform output -raw keycloak_admin_password
terraform output -raw admin_auth_password       # BasicAuth del dashboard de Traefik
```

Claves disponibles en el mapa `secrets`:
`postgres_password`, `app_db_password`, `keycloak_db_password`, `keycloak_admin_password`,
`keycloak_client_secret`, `redis_password`, `rabbitmq_password`, `minio_root_password`,
`minio_secret_key`, `grafana_admin_password`, `admin_auth_password`.

**Usuarios admin** (el valor es la clave correspondiente): Keycloak / Grafana / dashboard Traefik =
`admin`; RabbitMQ / MinIO = `arquisoft` (ajustables en el `.tfvars`).

> Seguridad: no vuelques todo a una terminal compartida. Para copiar una clave sin imprimirla:
> `terraform output -raw grafana_admin_password | xclip -selection clipboard` (o `wl-copy`/`pbcopy`).

---

## Backup y restauración (migrar datos entre despliegues)

`backup.sh`/`restore.sh` (raíz del repo) usan `docker exec` contra el **daemon Docker local**, así
que **corren donde está el stack**: en modo servidor, ejecútalos **en el servidor** (por eso el repo
se clona ahí). No necesitan `.env` si usas los nombres por defecto (`arquisoft-postgres`,
`arquisoft-keycloak-db`, volumen `arquisoft-minio-data`).

```bash
# Backup (postgres + keycloak + minio) -> ./backups del servidor; luego copia a tu equipo
ssh <servidor> 'cd ~/arquisoft-infra && ./backup.sh all'
rsync -avz <servidor>:'~/arquisoft-infra/backups/*' ./backups/

# Restaurar (DESTRUCTIVO; pide confirmación 'si'). Keycloak/MinIO exigen su contenedor detenido.
ssh <servidor> 'cd ~/arquisoft-infra && echo si | ./restore.sh backups/postgres_<ts>.sql.gz'
ssh <servidor> 'cd ~/arquisoft-infra && docker stop arquisoft-keycloak && echo si | ./restore.sh backups/keycloak_<ts>.sql.gz && docker start arquisoft-keycloak'
ssh <servidor> 'cd ~/arquisoft-infra && docker stop arquisoft-minio    && echo si | ./restore.sh backups/minio_<ts>.tar.gz    && docker start arquisoft-minio'
```

**Migrar de un entorno a otro (p. ej. dev → prod en el mismo host):**
1. `./backup.sh all` en el servidor (y copia a tu equipo).
2. `terraform destroy -var-file=environments/dev.tfvars` — ⚠️ borra los volúmenes, por eso el backup va **primero**.
3. `terraform apply -var-file=environments/prod.tfvars` y espera los certificados.
4. Restaura los 3 backups (comandos de arriba). Los **UUIDs** de usuarios de Keycloak se preservan (las FKs de negocio quedan intactas).

---

## Operación

```bash
# Actualizar imagen del backend: edita backend_tag en el .tfvars y re-aplica
terraform apply -var-file=environments/<env>.tfvars

# Rotar una clave (regenera y recrea los servicios que la usan)
terraform apply -replace='module.secrets.random_password.this["redis_password"]' \
  -var-file=environments/<env>.tfvars

# Bajar todo un entorno
terraform destroy -var-file=environments/<env>.tfvars
```

> El *state* contiene los secretos en claro (`chmod 600` los `.tfvars`/`.tfstate`, ya gitignored).
> Para prod compartido, usa un backend remoto cifrado con locking (bloque `backend` en `versions.tf`).
