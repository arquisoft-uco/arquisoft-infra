# Componente: frontend

Despliega la imagen del frontend (construida en el repo `arquisoft-frontend`).
Se expone en la raíz del dominio: `https://${DOMAIN}`.

## Configurar la imagen
En el `.env` raíz: `FRONTEND_IMAGE`, `FRONTEND_TAG` y `FRONTEND_PORT` (puerto interno que
sirve la imagen; nginx=80, vite preview=4173, etc.).

## Uso
```bash
./deploy.sh dev frontend     # http://127.0.0.1:8088
./deploy.sh prod frontend    # https://${DOMAIN}

# Standalone
docker compose --env-file ../../.env up -d
```
