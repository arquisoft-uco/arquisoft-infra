# Despliegue con Terraform — Arquisoft IaC

Capa Terraform **nativa y modular** que despliega el mismo stack que `deploy.sh`/compose,
usando el provider [`kreuzwerker/docker`](https://registry.terraform.io/providers/kreuzwerker/docker).
Sirve para **servidor propio** o una **VM en cloud** (Oracle/AWS/Azure/GCP) cambiando una sola
variable (`docker_host`). No se hardcodean IPs; los servicios se descubren por **alias de red**.

## Qué aporta frente a los scripts bash
- **Estado e idempotencia**: `terraform plan` muestra el diff y detecta *drift*; `apply` converge.
- **Portabilidad**: mismo código en local, VPS propio o cualquier cloud (solo cambia `docker_host`).
- **Modularidad**: un módulo por componente → reusable y sustituible (p.ej. migrar a un servicio
  gestionado de cloud = reemplazar un módulo).
- **Secretos gestionados**: generados con `random_password` (en el state, rotables), con interfaz
  lista para Key Vault (`var.provided_secrets`).
- **Configs en el grafo**: `templatefile()`/`upload` rinden y entregan la config dentro de los
  contenedores (idéntico en local y remoto, sin `envsubst`).

## Estructura
```
terraform/
├── versions.tf / providers.tf / variables.tf / main.tf / outputs.tf
├── environments/{dev,prod}.tfvars.example
└── modules/
    ├── network/  secrets/  server_prep/
    ├── proxy/  postgres/  keycloak/  rabbitmq/  redis/  minio/
    └── observability/  backend/  frontend/
```

## Requisitos
- Terraform >= 1.6.
- Para destino remoto (`docker_host = ssh://…`): cliente `ssh` local y que el usuario remoto
  pertenezca al grupo `docker` en el host.

## Uso
```bash
cd terraform
terraform init

# --- DEV (Docker local) ---
cp environments/dev.tfvars.example environments/dev.tfvars   # editar dominio/imágenes
terraform workspace new dev          # (o: terraform workspace select dev)
terraform apply -var-file=environments/dev.tfvars

# --- PROD (VPS propio o VM cloud por SSH) ---
cp environments/prod.tfvars.example environments/prod.tfvars # editar docker_host/dominio/imágenes
terraform workspace new prod         # (o: terraform workspace select prod)
terraform apply -var-file=environments/prod.tfvars
```

> Los **workspaces** aíslan el estado por entorno. "dev" es el mismo stack de prod desplegado en
> otro entorno (otro `docker_host`/dominio), no una configuración distinta.

## Secretos
Se generan automáticamente. Para consultarlos:
```bash
terraform output -raw grafana_admin_password
terraform output -raw keycloak_admin_password
terraform output -raw admin_auth_password
```
Migración a **Key Vault**: alimentar `var.provided_secrets` (mapa nombre→secreto) desde data
sources (`vault_generic_secret` / `azurerm_key_vault_secret` / `aws_secretsmanager_secret_version`).
El módulo `secrets` usa esos valores en vez de generarlos, sin tocar a los consumidores.

## Estado remoto (cloud)
`versions.tf` trae el bloque `backend` (S3/GCS/Azure) **comentado**. Al migrar a cloud, descomentar
uno, crear el bucket/locking y re-`terraform init` para migrar el estado.

## Preservar certificados Let's Encrypt existentes
Si el host ya tiene el volumen de certificados (de un despliegue previo con compose), impórtalo para
no re-emitir certificados (evita el rate-limit de LE):
```bash
terraform import 'module.proxy.docker_volume.letsencrypt' arquisoft-traefik-letsencrypt
```
(Equivalente para `docker_volume.logs` y cualquier `*-data` que se quiera conservar.)

## Firewall del host (opcional)
`enable_server_prep = true` (+ `ssh_*`) aplica `firewall.sh` por SSH al rol indicado
(`--public` por defecto). En cloud, sustituir el módulo `server_prep` por security groups nativos.

## Verificación
```bash
terraform plan                 # sin cambios tras apply = idempotente
docker ps                      # contenedores arquisoft-* healthy (en el docker_host destino)
curl -fsS https://api.<domain>/api/actuator/health   # {"status":"UP"} (vía Traefik + LE)
```

## Relación con deploy.sh / compose
Durante la transición, `deploy.sh` + los `components/*/docker-compose.yml` se conservan como
**referencia** y para validar paridad. Esta capa Terraform reutiliza directamente los
`components/*/config/*` (templates y configs) como fuente, garantizando el mismo resultado.

## Destruir
```bash
terraform destroy -var-file=environments/<env>.tfvars
```
