# Restauración — Arquisoft IaC

Restaura un backup generado con `backup.sh`. El tipo se detecta por el nombre del archivo.

> ⚠️ **Operación destructiva.** Sobrescribe los datos existentes. El script pide confirmación
> (escribir `si`).

## Uso
```bash
./restore.sh backups/postgres_20260623_020000.sql.gz   # PostgreSQL app
./restore.sh backups/keycloak_20260623_020000.sql.gz   # BD de Keycloak
./restore.sh backups/minio_20260623_020000.tar.gz      # Objetos de MinIO
```

## Procedimiento recomendado
1. Detener el servicio que usa la BD para evitar escrituras durante la restauración:
   ```bash
   ./deploy.sh prod down backend
   ```
2. Restaurar:
   ```bash
   ./restore.sh backups/postgres_<ts>.sql.gz
   ```
3. Para MinIO, reiniciar el contenedor tras restaurar el volumen:
   ```bash
   ./deploy.sh prod down minio && ./deploy.sh prod up minio
   ```
4. Volver a levantar la aplicación:
   ```bash
   ./deploy.sh prod up backend
   ```

## Notas
- `postgres_*.sql.gz` se genera con `pg_dumpall`: incluye las 7 BDs y los roles; se restaura
  conectándose a la BD `postgres` del contenedor `arquisoft-postgres`.
- `keycloak_*.sql.gz` restaura la BD `keycloak` en el contenedor `arquisoft-keycloak-db`.
- Si restauras en un servidor nuevo, primero crea la infraestructura base
  (`./deploy.sh prod up postgres keycloak minio`) y luego restaura.
