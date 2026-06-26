# CD del Backend — Redeploy automático vía GitHub Actions + SSH

## División de responsabilidades

| Herramienta | Gestiona |
|-------------|----------|
| **Terraform** | Red, volúmenes, Postgres, Redis, RabbitMQ, MinIO, Keycloak, Observabilidad, Traefik |
| **GitHub Actions + SSH** | Backend (Spring Boot + Alloy), Frontend |

Backend y frontend cambian en cada push — Terraform está pensado para infraestructura que
cambia poco. Gestionarlos con `terraform apply` introduce drift de state, obliga a usar
`-target` como workaround permanente y acopla el ciclo de CI con el ciclo de IaC.

---

## Flujo completo

```
arquisoft-backend (repo)
  └─ push a main
       └─ job build-push: docker build → push a GHCR (sha-XXXXXXX)
            └─ job deploy:
                 SSH al servidor
                   └─ git pull (infra repo, para tener el script actualizado)
                        └─ scripts/redeploy-app.sh --service backend --tag sha-XXXXXXX
                             └─ docker compose pull backend
                                  └─ docker compose up -d --no-deps backend
```

---

## Prerrequisitos en el servidor

### 1. Clonar la IaC (si aún no está)

```bash
git clone https://github.com/arquisoft-uco/arquisoft-infra.git /opt/arquisoft-infra
# El .env ya debe existir (generado con ./setup-env.sh o copiado manualmente)
```

### 2. Usuario SSH dedicado para CI

```bash
# Crear usuario sin shell interactiva — solo ejecuta comandos vía SSH
sudo useradd -m -s /usr/sbin/nologin deploy
sudo usermod -aG docker deploy

# Generar par de llaves (en tu máquina, no en el servidor)
ssh-keygen -t ed25519 -C "github-actions-arquisoft" -f ~/.ssh/arquisoft-deploy

# Instalar la pública en el servidor
sudo mkdir -p /home/deploy/.ssh
sudo tee /home/deploy/.ssh/authorized_keys <<< "$(cat ~/.ssh/arquisoft-deploy.pub)"
sudo chmod 700 /home/deploy/.ssh
sudo chmod 600 /home/deploy/.ssh/authorized_keys
sudo chown -R deploy:deploy /home/deploy/.ssh

# Dar acceso al repo de IaC
sudo chown -R deploy:deploy /opt/arquisoft-infra
```

### 3. Autenticación en GHCR (una sola vez)

El usuario `deploy` necesita poder hacer `docker pull` de GHCR:

```bash
# Generar un PAT en GitHub con scope read:packages
# Settings → Developer settings → Personal access tokens

sudo -u deploy docker login ghcr.io -u <tu-usuario-github> -p <PAT>
# Las credenciales quedan en /home/deploy/.docker/config.json
```

---

## GitHub Secrets

En el repo `arquisoft-backend` → **Settings → Secrets and variables → Actions**:

| Secret | Valor |
|--------|-------|
| `DEPLOY_SSH_HOST` | IP o hostname del servidor |
| `DEPLOY_SSH_USER` | `deploy` |
| `DEPLOY_SSH_KEY` | Contenido de `~/.ssh/arquisoft-deploy` (llave privada) |

---

## Workflow de GitHub Actions

El template está en [docs/examples/workflow-deploy-backend.yml](examples/workflow-deploy-backend.yml).
Copiarlo al repo `arquisoft-backend` como `.github/workflows/deploy.yml`.

El script que corre en el servidor es [scripts/redeploy-app.sh](../scripts/redeploy-app.sh):
- Actualiza `BACKEND_TAG` en el `.env` raíz (idempotente para futuros despliegues manuales)
- `docker compose pull backend` — descarga la nueva imagen
- `docker compose up -d --no-deps backend` — recrea solo el backend y Alloy; no toca postgres, redis, ni ningún otro servicio

---

## Migración desde Terraform (si el backend ya estaba gestionado por TF)

Si tienes el backend corriendo actualmente bajo Terraform, hay que sacar sus recursos del
state **antes** de hacer el primer `terraform apply` con el nuevo código. De lo contrario,
Terraform intentará destruir los contenedores al no encontrar el módulo.

```bash
cd terraform
terraform workspace select prod

# Quitar del state sin destruir los contenedores reales
terraform state rm 'module.backend[0].docker_container.backend'
terraform state rm 'module.backend[0].docker_container.alloy'
terraform state rm 'module.backend[0].docker_image.backend'
terraform state rm 'module.backend[0].docker_image.alloy'
terraform state rm 'module.backend[0].docker_volume.alloy_data'

# Verificar que el plan ya no menciona backend
terraform plan -var-file=environments/prod.tfvars
# Resultado esperado: No changes.
```

Los contenedores siguen corriendo — Docker no sabe nada del state de Terraform.
A partir de aquí el redeploy lo hace GitHub Actions.

---

## Rollback manual

```bash
ssh deploy@<servidor>
cd /opt/arquisoft-infra
bash scripts/redeploy-app.sh --service backend --tag sha-<tag-anterior>
```

El script actualiza `.env` y recrea el contenedor con el tag indicado.
