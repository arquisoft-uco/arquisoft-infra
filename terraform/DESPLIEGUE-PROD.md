# Despliegue en producción (servidor remoto por SSH) — Terraform

Guía paso a paso para desplegar la IaC en un servidor/VM de producción al que tienes acceso SSH
(propio o cloud: Oracle/AWS/Azure/GCP). El provider Docker se conecta al daemon remoto por SSH;
**no se abren puertos extra** y **ningún secreto viaja por la terminal ni se versiona**.

## Modelo de credenciales (cómo y dónde viven los secretos)
- **Se generan** con `random_password` en el `apply` — nunca se escriben a mano ni van en el repo.
- **Se almacenan** solo en el **state** de Terraform (artefacto sensible → ver paso 2).
- **Se inyectan** a los contenedores como variables de entorno por el canal SSH cifrado.
- Todas las variables/outputs de secreto son `sensitive` → **no aparecen** en `plan`, `apply`, ni logs.
- `*.tfvars` y `*.tfstate*` están en `.gitignore`; solo se versionan los `*.tfvars.example`.

---

## 0. Prerrequisitos
**En tu máquina (donde corres Terraform):** Terraform ≥ 1.6, cliente `ssh`, y tu llave SSH privada.
**En el servidor:** Docker Engine + el usuario SSH en el grupo `docker`:
```bash
ssh usuario@SERVIDOR 'sudo usermod -aG docker $USER'   # reconectar tras esto
```
**DNS:** registros **A** → IP del servidor para `@`, `api`, `auth`, `grafana`, `minio`, `s3`, `rabbitmq`, `traefik`.
**Puertos públicos:** solo **80** y **443** (Traefik/Let's Encrypt). Ver paso 1.

## 1. Asegurar el servidor a nivel de red (firewall + SSH)
Defensa en profundidad: denegar todo lo entrante salvo lo necesario.
```bash
# En el servidor (rol público): abre 80/443; SSH restringido a tu IP de administración
sudo ./firewall.sh --public --ssh-from <TU_IP_ADMIN>/32
```
Endurecer SSH (en `/etc/ssh/sshd_config`): `PasswordAuthentication no`, `PermitRootLogin no`
(solo llave). El socket Docker equivale a root: **limita quién tiene SSH/grupo docker**.

> Alternativa IaC: `enable_server_prep = true` + `ssh_*` aplica `firewall.sh` desde Terraform.

## 2. Estado remoto y cifrado (recomendado para producción)
El state contiene los secretos en claro. **No uses state local en prod compartido.** Activa un
backend remoto cifrado y con bloqueo (descomenta en `versions.tf` el que aplique):
```hcl
backend "s3" {
  bucket = "arquisoft-tfstate"; key = "infra/terraform.tfstate"; region = "us-east-1"
  dynamodb_table = "arquisoft-tflock"; encrypt = true     # cifrado + state locking
}
```
Beneficios: cifrado en reposo, control de acceso (IAM), bloqueo concurrente y versionado.
Si por ahora usas state local: mantenlo en `chmod 600` y **nunca** lo subas (ya está gitignored).

## 3. Configurar el entorno (sin secretos)
```bash
cd terraform
cp environments/prod.tfvars.example environments/prod.tfvars
chmod 600 environments/prod.tfvars
```
Edita `prod.tfvars` (solo datos NO sensibles: host, dominio, imágenes):
```hcl
docker_host     = "ssh://usuario@IP_DEL_SERVIDOR"
docker_ssh_opts = ["-i", "~/.ssh/tu_llave", "-o", "StrictHostKeyChecking=accept-new"]
domain          = "tudominio.tld"
acme_email      = "tu-email@tudominio.tld"
backend_image   = "ghcr.io/arquisoft-uco/arquisoft-backend"
backend_tag     = "sha-XXXXXXX"
```

## 4. Desplegar
```bash
terraform init                                   # descarga providers
terraform workspace new prod                     # (o: terraform workspace select prod)
terraform apply -var-file=environments/prod.tfvars
```
El `apply` genera las credenciales, crea la red, los volúmenes y los 12 servicios, y Traefik
emite los certificados Let's Encrypt automáticamente en el primer acceso.

> ¿Vienes de un despliegue previo con certificados? Conserva el volumen importándolo antes del
> apply (evita reemitir y el rate-limit de LE):
> `terraform import 'module.proxy.docker_volume.letsencrypt' arquisoft-traefik-letsencrypt`

## 5. Obtener las credenciales generadas (de forma segura)
Mostrar secretos en pantalla es una exposición (scrollback, screen-share, logs de CI). Reglas:
- **No** vuelques todo a la terminal (evita `terraform output -json secrets`).
- Recupera **una** clave y mándala al portapapeles, sin imprimirla:
```bash
terraform output -raw grafana_admin_password | xclip -selection clipboard   # o wl-copy / pbcopy
```
- Si debes verla, hazlo en una terminal **no compartida** y limpia el scrollback (`printf '\033[3J'`).
- Nunca uses `echo`/`printenv <SECRET>` en terminales o CI compartidos.
- Lo ideal: no recuperarlas a mano (las apps ya las consumen del entorno); para humanos, usar un
  gestor de secretos (Vault/Key Vault) con control de acceso propio.

Usuarios admin por consola (estándar: identidades separadas por sistema):
Keycloak / Grafana / dashboard Traefik = `admin`; RabbitMQ / MinIO = `arquisoft`;
login del realm Keycloak (app) = `admin@uco.edu.co`. (Ajustables por variable.)

## 6. Verificar
```bash
terraform plan -var-file=environments/prod.tfvars     # debe decir "No changes" (idempotente)
ssh usuario@SERVIDOR 'docker ps'                       # contenedores arquisoft-* healthy
curl -fsS https://api.tudominio.tld/api/actuator/health   # {"status":"UP"} con cert válido
```

## 7. Operación
- **Actualizar imagen:** cambia `backend_tag` en `prod.tfvars` → `terraform apply`.
- **Rotar un secreto:** `terraform apply -replace='module.secrets.random_password.this["redis_password"]'`
  (regenera y recrea los servicios que lo usan).
- **Bajar todo:** `terraform destroy -var-file=environments/prod.tfvars`.

---

## Checklist de seguridad (estándar de industria)
- [x] Secretos **generados** por Terraform (no hardcodeados, no en el repo).
- [x] Variables y outputs de secreto marcados `sensitive` → no se imprimen en plan/apply/logs.
- [x] `*.tfvars` reales y `*.tfstate*` en `.gitignore` (solo `*.example` versionados).
- [ ] **State remoto cifrado + locking + IAM** (paso 2) — o state local en `chmod 600`.
- [ ] **Firewall**: solo 80/443 público; 22 restringido a IP de admin; datos solo en red interna.
- [ ] **SSH**: solo llave (sin password), acceso mínimo (el grupo docker = root en el host).
- [ ] Llave SSH protegida (`chmod 600`), idealmente con passphrase/agent.
- [ ] Rotación periódica de credenciales (paso 7).
- [ ] Futuro: mover los secretos a Vault/Key Vault vía `var.provided_secrets` (interfaz ya lista).
