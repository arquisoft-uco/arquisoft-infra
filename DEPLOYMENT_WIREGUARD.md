# Guía de Despliegue: WireGuard VPN

Esta guía explica cómo desplegar WireGuard VPN en producción usando Terraform.

## Arquitectura

```
Desarrolladores (remoto)
  ↓ WireGuard client (10.0.0.2-254)
  ↓ UDP 51820 encriptado
  ↓
Oracle/VPS Server (vpn.arquisoft.top:51820)
  ├─ WireGuard (10.0.0.1)
  ├─ Net forwarding habilitado
  └─ Docker network (172.17.0.0/16)

Servicios internos (accesibles desde VPN)
  ├─ PostgreSQL (5432) — en red Docker
  ├─ Redis (6379) — en red Docker
  ├─ RabbitMQ (5672) — en red Docker
  ├─ Grafana (3000) — en red Docker
  └─ Otros servicios...
```

## Prerrequisitos

- ✅ Repo `arquisoft-infra` clonado localmente
- ✅ SSH alias configurado: `ssh oracle` (conecta al servidor remoto)
- ✅ Terraform instalado localmente
- ✅ Docker daemon corriendo en el servidor remoto
- ✅ `.env` de producción ya generado (`./setup-env.sh prod`)

## Pasos de Despliegue

### 1. Verificar Estado Local

```bash
cd /home/brayanesq/projects/arquisoft/arquisoft-infra

# Ver cambios pendientes
git status

# Ver cambios en archivos de Terraform
git diff terraform/

# Revisar estructura del módulo WireGuard
ls -la terraform/modules/wireguard/
```

**Salida esperada:**
```
main.tf, variables.tf, outputs.tf, versions.tf — todos presentes
```

### 2. Validar Configuración de Terraform

```bash
cd terraform

# Validar sintaxis
terraform validate

# Verificar plan (SIN aplicar)
terraform plan -target=module.wireguard -out=wireguard.tfplan

# Revisar el plan antes de aplicar
terraform show wireguard.tfplan
```

**Buscar en el output:**
- `+ docker_image.wireguard` — descargará imagen
- `+ docker_volume.config` y `docker_volume.confs` — volúmenes persistentes
- `+ docker_container.wireguard` — contenedor con port 51820/udp

### 3. Aplicar Cambios Locales (si usa Docker local)

Si trabajas en dev o quieres probar localmente:

```bash
# Desde el directorio raíz
./setup-env.sh dev                          # genera .env para dev
terraform -chdir=terraform apply -target=module.wireguard

# Verificar que está corriendo
docker ps | grep wireguard
docker logs -f arquisoft-wireguard
```

### 4. Actualizar Servidor Remoto (Producción)

#### 4a. Conectar al servidor

```bash
# Usar el alias SSH configurado
ssh oracle

# Verificar que estamos en el servidor correcto
whoami          # debe ser 'ubuntu' o usuario de despliegue
uname -a        # verifica OS
pwd             # verifica home dir
```

#### 4b. Actualizar repositorio en el servidor

```bash
# Navegar al repo en el servidor
cd /opt/arquisoft-infra  # o donde esté clonado

# Actualizar rama main
git fetch origin main
git checkout main
git pull origin main

# Verificar que los cambios llegaron
ls -la terraform/modules/wireguard/
# Debe mostrar: main.tf, variables.tf, outputs.tf, versions.tf
```

#### 4c. Aplicar Terraform en el servidor

```bash
cd terraform

# Plan (revisar qué va a cambiar)
terraform plan -target=module.wireguard -out=wireguard.tfplan

# Show para revisar antes de aplicar
terraform show wireguard.tfplan

# Aplicar (SIN confirmación, si lo hizo en plan)
terraform apply wireguard.tfplan
```

**Monitorear el despliegue:**

```bash
# En otra terminal SSH, ver logs del contenedor
docker logs -f arquisoft-wireguard

# Esperar ~30s a que WireGuard inicialice y genere claves
```

### 5. Verificar Despliegue

En el servidor remoto:

```bash
# Verificar contenedor está corriendo
docker ps | grep wireguard

# Ver estado de WireGuard
docker exec arquisoft-wireguard wg show all

# Ver logs
docker logs arquisoft-wireguard

# Listar clientes generados
docker exec arquisoft-wireguard ls -la /config/peer_confs/

# Verificar que el puerto 51820 está abierto
sudo ss -ulnp | grep 51820
```

### 6. Provisioning de Clientes

Desde el servidor remoto:

```bash
# Usar script de provisioning (si está disponible)
cd /opt/arquisoft-infra/components/wireguard
./provision-clients.sh list

# Extraer config de un cliente
./provision-clients.sh extract dev1

# Exportar todas las configs
./provision-clients.sh export ~/vpn-configs/

# Ver QR de un cliente (en servidor gráfico)
./provision-clients.sh show-qr dev1
```

O manualmente:

```bash
# Extraer una configuración
docker exec arquisoft-wireguard cat /config/peer_confs/dev1/dev1.conf > /tmp/dev1.conf

# Transferir a tu máquina local
# (desde local, en otra terminal)
scp oracle:/tmp/dev1.conf ~/Downloads/

# Ver contenido
cat ~/Downloads/dev1.conf
```

### 7. Configurar Cliente en Desarrollador

#### Linux/macOS

```bash
# 1. Instalar WireGuard
# Ubuntu: sudo apt install wireguard wireguard-tools
# macOS: brew install wireguard-tools

# 2. Copiar config a /etc/wireguard/
sudo cp dev1.conf /etc/wireguard/
sudo chmod 600 /etc/wireguard/dev1.conf

# 3. Conectar
sudo wg-quick up dev1

# 4. Verificar
sudo wg show dev1
ip addr show dev1      # debe mostrar 10.0.0.x

# 5. Probar conectividad
ping 10.0.0.1          # ping al gateway
sudo wg-quick down dev1 # desconectar
```

#### Windows

1. Descargar WireGuard: https://www.wireguard.com/install/
2. Abrir WireGuard
3. Import Tunnel → selecciona `dev1.conf`
4. Activate
5. Verificar: `wg show` en PowerShell Admin

#### iOS/Android

1. Descargar app WireGuard desde AppStore/PlayStore
2. En servidor: `./provision-clients.sh show-qr dev1`
3. En app: Crear tunnel → Escanear QR
4. Activar

### 8. Pruebas de Conectividad

Desde cliente VPN conectado:

```bash
# Probar acceso a servicios internos
# (asumiendo que están en 10.0.0.x)

# PostgreSQL
psql -h 10.0.0.254 -U postgres -d usuarios

# Redis
redis-cli -h 10.0.0.254 ping

# Grafana (si expone puerto en red interna)
curl http://10.0.0.254:3000

# RabbitMQ
curl http://10.0.0.254:15672  # admin panel
```

### 9. Seguridad & Firewall

En el servidor, aplicar firewall para limitar acceso a servicios internos:

```bash
sudo ufw status

# Solo permitir VPN desde internet
sudo ufw allow 51820/udp

# Bloquear acceso directo a servicios internos desde internet
sudo ufw deny 5432     # PostgreSQL
sudo ufw deny 6379     # Redis
sudo ufw deny 3000     # Grafana (acceso via Traefik)
sudo ufw deny 5672     # RabbitMQ
```

### 10. Monitoreo Continuo

```bash
# Ver conexiones activas
docker exec arquisoft-wireguard wg show all

# Logs en tiempo real
docker logs -f arquisoft-wireguard

# Healthcheck
docker exec arquisoft-wireguard healthcheck  # o comando del healthcheck

# Stats de recursos
docker stats arquisoft-wireguard
```

## Rollback (si algo falla)

Si necesitas revertir los cambios:

```bash
# En el servidor
cd /opt/arquisoft-infra/terraform

# Destruir módulo WireGuard solamente
terraform destroy -target=module.wireguard

# O revertir commit en git
git revert HEAD
git pull origin main
terraform apply

# O volver a rama anterior
git checkout main~1
terraform apply
```

## Troubleshooting

### "WireGuard container no inicia"

```bash
# Ver logs detallados
docker logs arquisoft-wireguard

# Verificar permisos del volumen
docker exec arquisoft-wireguard ls -la /config/

# Reintentar
docker restart arquisoft-wireguard
```

### "Clientes no pueden conectarse"

```bash
# Verificar puerto abierto desde internet
nc -zv vpn.arquisoft.top 51820

# En servidor, ver conexiones
sudo netstat -ulnp | grep 51820

# Revisar reglas firewall
sudo ufw status numbered
```

### "No alcanza servicios internos desde cliente"

```bash
# En servidor: verificar IP forwarding
cat /proc/sys/net/ipv4/ip_forward  # debe ser 1

# En cliente: listar rutas
ip route

# Ping de diagnóstico
ping -c 4 10.0.0.1  # gateway
ping -c 4 10.0.0.254  # host servidor
```

## Variables de Configuración

Para personalizar, editar `terraform/prod.tfvars`:

```hcl
# Personalizar peers/clientes
wireguard_peers = ["dev1", "dev2", "dev3", "mobile1", "mobile2"]

# Cambiar subnet (default 10.0.0.0/24)
wireguard_subnet = "10.1.0.0/24"

# Cambiar puerto (default 51820)
wireguard_port = 51820

# Máximo de clientes simultáneos
wireguard_max_clients = 50
```

Luego reaplica:

```bash
terraform apply -target=module.wireguard
```

## Referencias

- [WireGuard Official](https://www.wireguard.com/)
- [linuxserver/wireguard Docs](https://docs.linuxserver.io/images/docker-wireguard/)
- [WireGuard Quickstart](https://www.wireguard.com/quickstart/)
- [Curve25519 Cryptography](https://www.wireguard.com/protocol/)

---

**Última actualización:** 2026-07-04
**Mantenedor:** brayan.sepulveda4302@soyuco.edu.co
