# Componente: minio (Object Storage S3)

Almacenamiento S3-compatible con el fork comunitario activo **pgsty/minio** (AGPL).
MinIO oficial fue archivado; este fork es drop-in y mantiene consola + API.

## Endpoints (prod)
- Consola web: `https://minio.${DOMAIN}`
- API S3:      `https://s3.${DOMAIN}` (requerido para presigned URLs del backend)

Dev: `http://127.0.0.1:9001` (consola) y `http://127.0.0.1:9000` (API).

## Buckets e inicialización
`minio-init` crea `artefactos`, `avatars`, `backups` y `repositorio-artefactos`, **todos privados**
(ninguno admite acceso anónimo), y la **cuenta de servicio del backend**: access-key
`MINIO_ACCESS_KEY` (= `arquisoft-backend`, en `.tfvars`) + secret `MINIO_SECRET_KEY`
(`secrets.minio_secret_key`). El root `minioadmin` es solo para la consola; el backend usa
**siempre** la cuenta de servicio, nunca el root.

Ningún archivo se publica con una URL fija: el acceso a un objeto lo concede el backend tras
autorizar a quien lo pide. `avatars` fue público (`anonymous set download`); `minio-init` ahora
ejecuta `anonymous set none` en cada despliegue. Borrar la línea no habría bastado, porque la
política anónima queda guardada en el bucket.

### Política de la cuenta del backend (mínimo privilegio)
La cuenta no tiene `readwrite` (que es `s3:*` sobre **todos** los buckets, `backups` incluido),
sino la política `arquisoft-backend` de
[`config/politica-arquisoft-backend.json`](config/politica-arquisoft-backend.json). Solo cubre
`repositorio-artefactos`, el único bucket que el backend usa hoy:

| Acción | Para qué |
|---|---|
| `s3:PutObject` | El POST del navegador (va firmado con esta cuenta) y el destino de la copia a `versiones/` |
| `s3:GetObject` | `statObject`, la lectura de validación y el origen de la copia |
| `s3:DeleteObject` | Borrar el pendiente tras una subida aceptada |
| `s3:GetBucketLocation` | El SDK Java consulta la región del bucket antes de operar |

Sin `s3:ListBucket` (no puede listar el bucket), sin creación de buckets, sin administración y sin
acceso a `artefactos`, `avatars` ni `backups`. A diferencia de AWS, MinIO responde 404 `NoSuchKey`
a un HEAD/GET de un objeto ausente aunque falte `s3:ListBucket`, y el backend depende de ese 404
para saber que una carga no existe. Si una actualización de MinIO cambiara ese comportamiento, el
síntoma sería 503 en lugar de 422 al confirmar una carga inexistente.
**Cuando una HU haga que el backend use otro bucket** (p. ej. `artefactos`, HU043), agrega sus dos
`Statement` al JSON en el mismo PR. Si no, esa HU responde 503 en la nube aunque funcione en local
con root. `minio-init` hace `policy create` en cada despliegue (reemplaza el contenido), adjunta la
política y desadjunta `readwrite`.

> ⚠️ El access-key NO debe coincidir con `minio_root_user` (`minioadmin`): colisionaría con el
> nombre del root y la cuenta de servicio no se crearía.

### Ciclo de vida de `repositorio-artefactos`
El navegador sube cada plantilla directo a MinIO bajo `pendientes/{carga}` con un formulario
firmado por el backend; al confirmar, el backend la valida y la copia a `versiones/{versionId}`.
Lo que queda en `pendientes/` (cargas abandonadas o rechazadas) lo borra la regla de
[`config/ciclo-vida-repositorio-artefactos.json`](config/ciclo-vida-repositorio-artefactos.json)
al día siguiente. `versiones/` no expira: su ciclo de vida lo gobierna el backend.

`minio-init` la aplica con `mcli ilm rule import`, que **reemplaza** la configuración completa del
bucket: reejecutarlo no duplica reglas. Por lo mismo, toda regla nueva del bucket se agrega a ese
JSON, nunca con `mcli ilm rule add` a mano (el siguiente `minio-init` la borraría).

```bash
docker exec arquisoft-minio sh -c 'mcli alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mcli ilm rule ls local/repositorio-artefactos'
```

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
- CORS: el POST del navegador al bucket es *cross-origin*. MinIO lo permite por defecto
  (`MINIO_API_CORS_ALLOW_ORIGIN` vale `*`). Restringirlo a `https://${DOMAIN}` es un endurecimiento
  pendiente: cambiar el `env` del contenedor obliga a recrearlo (corte breve).
