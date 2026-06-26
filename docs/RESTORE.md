# Restauración — Arquisoft IaC

Restaura un backup generado con `backup.sh`. El tipo se detecta por el nombre del archivo.

> ⚠️ **Operación destructiva.** Sobrescribe los datos existentes. El script pide confirmación
> (escribir `si`).

> ⚠️ **El script falla si los contenedores dependientes están corriendo.** Detenerlos es
> obligatorio antes de ejecutar la restauración (ver procedimiento abajo).

## Uso
```bash
./restore.sh backups/postgres_20260623_020000.sql.gz   # PostgreSQL app
./restore.sh backups/keycloak_20260623_020000.sql.gz   # BD de Keycloak
./restore.sh backups/minio_20260623_020000.tar.gz      # Objetos de MinIO
```

## Procedimiento — PostgreSQL app

```bash
# 1. Detener el backend para evitar escrituras durante la restauración
docker stop arquisoft-backend

# 2. Restaurar
./restore.sh backups/postgres_<ts>.sql.gz

# 3. Volver a levantar el backend
docker start arquisoft-backend
```

## Procedimiento — Keycloak DB

```bash
# 1. Detener Keycloak
docker stop arquisoft-keycloak

# 2. Restaurar
./restore.sh backups/keycloak_<ts>.sql.gz

# 3. Volver a levantar Keycloak
docker start arquisoft-keycloak
```

## Procedimiento — MinIO

```bash
# 1. Detener MinIO
docker stop arquisoft-minio

# 2. Restaurar (sobreescribe el volumen completo)
./restore.sh backups/minio_<ts>.tar.gz

# 3. Volver a levantar MinIO
docker start arquisoft-minio
```

## Restauración en servidor nuevo

Si restauras en un servidor nuevo, primero despliega la infraestructura base para que
existan los contenedores y volúmenes:

```bash
terraform apply -target=module.postgres -target=module.keycloak -target=module.minio
```

Luego detén los contenedores dependientes y ejecuta la restauración como se indica arriba.

## Notas
- `postgres_*.sql.gz` se genera con `pg_dumpall`: incluye las 7 BDs y los roles; se restaura
  conectándose a la BD `postgres` del contenedor `arquisoft-postgres`.
- `keycloak_*.sql.gz` restaura la BD `keycloak` en el contenedor `arquisoft-keycloak-db`.
- Los comandos `docker stop` / `docker start` no generan drift en el estado de Terraform
  porque Terraform gestiona la configuración del contenedor, no su estado de ejecución puntual.
