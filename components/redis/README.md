# Componente: redis (caché / rate-limiting)

Redis 7 con persistencia AOF. Lo usa el backend para caché, sesiones y rate limiting.

## Usuarios (modelo admin + app)
- `default` (admin) — `--requirepass`, acceso total.
- `arquisoft_backend` (app) — usuario ACL de privilegio mínimo (`~* &* +@all -@dangerous +info`),
  el que usa el backend. `+info` está permitido porque el health check de Spring Boot usa `INFO`
  (que cae en `@dangerous`); sin él, `FLUSHALL`/`CONFIG`/etc. siguen bloqueados.

Credenciales de app: `terraform output -raw redis_app_password` (admin: `secrets.redis_password`).

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
