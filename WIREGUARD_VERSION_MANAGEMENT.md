# Gestión de Versiones — WireGuard Docker Image

Este documento explica cómo mantener la versión de la imagen Docker de WireGuard actualizada de forma segura y controlada.

## Versión Actual

- **Imagen:** `linuxserver/wireguard:1.0.20250521-r1-ls116`
- **Fecha:** 2026-07-04
- **Arquitecturas:** amd64, arm64 (multi-arquitectura)
- **Última verificación:** https://hub.docker.com/r/linuxserver/wireguard/tags

## Por qué NO usar `:latest`

```dockerfile
# ❌ EVITAR
image: linuxserver/wireguard:latest

# ✅ USAR
image: linuxserver/wireguard:1.0.20250521-r1-ls116
```

**Riesgos de `:latest`:**
- Cambios inesperados en la infraestructura cuando se redeploya
- Posibles incompatibilidades con configuraciones existentes
- Dificultad para reproducir problemas ("worked yesterday, broken today")
- Auditoría y compliance: no puedes documentar exactamente qué versión ejecutas

## Archivos que Contienen la Versión

1. **Terraform:** `terraform/modules/wireguard/main.tf` (línea ~7-10)
   ```hcl
   name = "linuxserver/wireguard:1.0.20250521-r1-ls116"
   ```

2. **Docker Compose:** `components/wireguard/docker-compose.yml` (línea ~14)
   ```yaml
   image: linuxserver/wireguard:1.0.20250521-r1-ls116
   ```

**Ambos archivos deben estar sincronizados siempre.**

## Cómo Actualizar la Versión

### 1. Verificar Nuevas Versiones

Opción A: Revisar Docker Hub manualmente
```bash
# Abrir en navegador
https://hub.docker.com/r/linuxserver/wireguard/tags
```

Opción B: Usar CLI (docker.com account requerida)
```bash
# Listar últimas 20 versiones
curl -s 'https://hub.docker.com/v2/repositories/linuxserver/wireguard/tags/?page_size=20' | \
  jq '.results[] | {name, last_updated}' | head -20
```

Opción C: Script automatizado
```bash
#!/bin/bash
# ver-wireguard-latest.sh

curl -s 'https://hub.docker.com/v2/repositories/linuxserver/wireguard/tags/?page_size=5' | \
  jq -r '.results[] | "\(.name) (updated: \(.last_updated))"' | \
  grep -v "arm64\|amd64" | head -5
```

### 2. Elegir Nueva Versión

**Criterios de selección:**

| Criterio | Preferencia |
|----------|-------------|
| **Estabilidad** | Versión publicada hace >1 semana (permite que otros la prueben) |
| **Seguridad** | Incluir parches conocidos de WireGuard (revisar changelogs) |
| **Mantenimiento** | linuxserver/wireguard debe estar activo (ver fecha last_updated) |
| **Multi-arquitectura** | Debe tener tags para `amd64` y `arm64` |
| **Número de pulls** | Más pulls = más pruebas por otros usuarios |

**Versiones recomendadas en orden:**

1. Última versión estable publicada hace >1 semana
2. Versión anterior (fallback si hay problemas)
3. Nunca usar versión del mismo día

### 3. Actualizar Archivos

#### En `terraform/modules/wireguard/main.tf`

```bash
# 1. Reemplazar la versión
OLD_VERSION="1.0.20250521-r1-ls116"
NEW_VERSION="1.0.20250521-r1-ls117"  # ejemplo

sed -i "s/${OLD_VERSION}/${NEW_VERSION}/g" terraform/modules/wireguard/main.tf
```

O editar manualmente:
```hcl
name = "linuxserver/wireguard:1.0.20250521-r1-ls117"
```

#### En `components/wireguard/docker-compose.yml`

```bash
sed -i "s/${OLD_VERSION}/${NEW_VERSION}/g" components/wireguard/docker-compose.yml
```

O editar manualmente:
```yaml
image: linuxserver/wireguard:1.0.20250521-r1-ls117
```

### 4. Validar Cambios

```bash
# Verificar que ambos archivos tienen la misma versión
grep -n "1.0.20250521-r1-ls117" terraform/modules/wireguard/main.tf
grep -n "1.0.20250521-r1-ls117" components/wireguard/docker-compose.yml

# Deben ser exactamente iguales
```

### 5. Test en Entorno de Desarrollo

```bash
cd /path/to/arquisoft-infra

# Test local (si tienes Docker)
export TZ="America/Bogota"
export WIREGUARD_HOST="localhost"
export WIREGUARD_PORT="51820"
export PEERS="test1,test2"

docker compose -f components/wireguard/docker-compose.yml up -d

# Esperar ~30s
sleep 30

# Verificar que inicia correctamente
docker logs arquisoft-wireguard | tail -20

# Probar healthcheck
docker exec arquisoft-wireguard wg show all

# Cleanup
docker compose -f components/wireguard/docker-compose.yml down
```

### 6. Aplicar en Producción

```bash
# 1. Crear rama de actualización
git checkout -b chore/wireguard-version-update-1.0.20250521-r1-ls117

# 2. Commit de cambios
git add terraform/modules/wireguard/main.tf components/wireguard/docker-compose.yml
git commit -m "chore(wireguard): actualizar a version 1.0.20250521-r1-ls117

- Actualización de seguridad/estabilidad
- Ambas imagenes (Terraform + Docker Compose) sincronizadas
- Verificado en docker.com: multi-arquitectura (amd64, arm64)

Refs: https://hub.docker.com/r/linuxserver/wireguard/tags
"

# 3. Push a remote
git push origin chore/wireguard-version-update-1.0.20250521-r1-ls117

# 4. Crear Pull Request
gh pr create \
  --title "chore(wireguard): actualizar a version 1.0.20250521-r1-ls117" \
  --body "Actualización de seguridad/estabilidad de WireGuard"
```

En servidor remoto:
```bash
ssh oracle

cd /opt/arquisoft-infra

# 1. Obtener cambios
git fetch origin
git checkout chore/wireguard-version-update-...
git pull origin ...

# 2. Aplicar Terraform (descargará nueva imagen automáticamente)
cd terraform
terraform plan -target=module.wireguard

# Revisar cambios (solo la imagen debe cambiar)

terraform apply -target=module.wireguard

# 3. Monitorear reemplazo del contenedor
docker logs -f arquisoft-wireguard
```

## Monitoreo Post-Actualización

```bash
# Verificar que WireGuard inició correctamente
docker ps | grep wireguard

# Ver logs
docker logs arquisoft-wireguard

# Verificar interfaz
docker exec arquisoft-wireguard wg show all

# Ver versión de WireGuard dentro del contenedor
docker exec arquisoft-wireguard wg --version

# Prueba de conectividad desde cliente
# (en cliente VPN conectado)
ping 10.0.0.1
```

## Rollback de Versión

Si la nueva versión causa problemas:

```bash
# 1. Revertir a versión anterior
git revert HEAD

# 2. Aplicar
cd terraform
terraform apply -target=module.wireguard

# 3. Monitorear
docker logs -f arquisoft-wireguard
```

## Calendario de Revisión

- **Mensual:** Revisar https://hub.docker.com/r/linuxserver/wireguard/tags
- **Crítico:** Si hay CVE en WireGuard (aplicar inmediatamente)
- **Rutina:** Cuando haya 3+ versiones nuevas disponibles

## Referencias

- [Docker Hub - linuxserver/wireguard](https://hub.docker.com/r/linuxserver/wireguard)
- [linuxserver Documentation](https://docs.linuxserver.io/images/docker-wireguard/)
- [WireGuard Security Advisories](https://www.wireguard.com/)
- [WireGuard CVE Tracker](https://www.cvedetails.com/cve/wireguard/)

## Notas Importantes

1. **SIEMPRE sincronizar** `terraform/modules/wireguard/main.tf` y `components/wireguard/docker-compose.yml`
2. **NUNCA usar** tags `latest`, `main`, o sin versión
3. **Testear en dev** antes de aplicar en producción
4. **Documentar** en git commit la razón del cambio (seguridad, bug fix, etc)
5. **Avisar a desarrolladores** si hay cambios que afecten sus configs VPN
