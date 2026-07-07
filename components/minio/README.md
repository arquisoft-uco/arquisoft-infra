# Componente: minio (Object Storage S3)

Almacenamiento S3-compatible con el fork comunitario activo **pgsty/minio** (AGPL).
MinIO oficial fue archivado; este fork es drop-in y mantiene consola + API.

## Endpoints (prod)
- Consola web: `https://minio.${DOMAIN}`
- API S3:      `https://s3.${DOMAIN}` (requerido para presigned URLs del backend)

Dev: `http://127.0.0.1:9001` (consola) y `http://127.0.0.1:9000` (API).

## Buckets e inicialización
`minio-init` crea `artefactos`, `avatars` (descarga pública), `backups`, y la **cuenta de servicio
`readwrite` del backend**: access-key `MINIO_ACCESS_KEY` (= `arquisoft-backend`, en `.tfvars`) +
secret `MINIO_SECRET_KEY` (`secrets.minio_secret_key`). El root `minioadmin` es solo para la
consola; el backend usa **siempre** la cuenta de servicio, nunca el root.

> ⚠️ El access-key NO debe coincidir con `minio_root_user` (`minioadmin`): colisionaría con el
> nombre del root y la cuenta de servicio no se crearía.

## Uso
```bash
./deploy.sh dev minio
./deploy.sh prod minio

# Standalone
docker compose --env-file ../../.env up -d
```

## Notas
- Para presigned URLs con el API expuesto, el registro DNS `s3.${DOMAIN}` y su certificado
  deben existir antes del primer login (esperar 2-3 min tras el primer deploy).
- Multi-servidor: el backend accede al API por `s3.${DOMAIN}` (HTTPS) o por IP privada `:9000`.
