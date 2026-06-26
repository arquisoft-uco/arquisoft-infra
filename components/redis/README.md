# Componente: redis (caché / rate-limiting)

Redis 7 con persistencia AOF y contraseña obligatoria (`--requirepass`). Lo usa el backend
para caché, sesiones y rate limiting.

## Acceso
Solo red interna. No se expone a Internet. Dev: `127.0.0.1:6379`.

## Uso
```bash
./deploy.sh dev redis
./deploy.sh prod redis

# Standalone
docker compose --env-file ../../.env up -d
```

## Multi-servidor
Abrir el puerto 6379 solo a la IP privada del servidor de aplicación (firewall).
