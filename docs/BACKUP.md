# Backup — Arquisoft IaC

Respalda las bases de datos y el almacenamiento de objetos. Los archivos quedan en `./backups/`
con timestamp y se conservan los últimos `BACKUP_RETENTION_DAYS` días (default 7).

## Qué respalda
| Objetivo | Origen | Archivo |
|----------|--------|---------|
| `postgres` | PostgreSQL app (las 7 BDs por contexto + roles) | `postgres_<ts>.sql.gz` |
| `keycloak` | BD dedicada de Keycloak | `keycloak_<ts>.sql.gz` |
| `minio` | Volumen de objetos de MinIO | `minio_<ts>.tar.gz` |

## Uso
```bash
./backup.sh            # all (postgres + keycloak + minio)
./backup.sh postgres
./backup.sh keycloak
./backup.sh minio
```
Requiere los contenedores corriendo (`arquisoft-postgres`, `arquisoft-keycloak-db`, `minio`).

## Variables opcionales
```bash
BACKUP_DIR=/mnt/backups ./backup.sh        # otro destino
BACKUP_RETENTION_DAYS=30 ./backup.sh       # otra retención
```

## Automatizar (cron diario 02:00)
```cron
0 2 * * *  cd /ruta/arquisoft-infra && ./backup.sh all >> backups/cron.log 2>&1
```

## Recomendaciones
- Copiar los backups fuera del servidor (otro host, bucket S3, etc.).
- Probar la restauración periódicamente (ver [RESTORE.md](RESTORE.md)).
- En multi-servidor, ejecutar `./backup.sh` en el servidor donde corre cada BD.
