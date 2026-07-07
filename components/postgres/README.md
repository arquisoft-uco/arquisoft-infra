# Componente: postgres (base de datos de la aplicación)

PostgreSQL 18 con **7 bases de datos por bounded context** (una por DataSource del backend).
La BD de Keycloak **no** está aquí — vive en el componente `keycloak` (instancia dedicada).

## Bases de datos creadas (owner `arquisoft_user`)
`usuarios`, `fichas_perfil`, `artefactos`, `repositorio_artefactos`,
`proyectos_grado`, `entregables`, `evaluaciones`

Cada una con extensiones `uuid-ossp` y `pg_trgm`, y `public` owner del usuario de app.

## Usuarios (modelo admin + app)
El superusuario es `postgres`; `arquisoft_user` es el usuario de **aplicación** con privilegio
mínimo (`NOSUPERUSER NOCREATEROLE NOCREATEDB`). Lo fija el init script en volúmenes nuevos y, sobre
volúmenes ya existentes, `null_resource.postgres_app_least_privilege` lo reaplica en cada `apply`.
El backend se conecta **siempre** como `arquisoft_user`, nunca como `postgres`.

## Inicialización
`init/01-init-databases.sh` corre **una sola vez** al crear el volumen. Toma la contraseña
del usuario de app desde `APP_DB_PASSWORD`. Para reinicializar: eliminar el volumen
`arquisoft-postgres-data` y volver a desplegar (¡destruye datos!).

## Uso
```bash
./deploy.sh dev postgres        # con puerto 127.0.0.1:5432 expuesto
./deploy.sh prod postgres       # solo red interna

# Standalone
docker compose --env-file ../../.env -f docker-compose.yml up -d
```

## Seguridad / red
No se expone a Internet. En multi-servidor, abrir el puerto 5432 solo a la IP privada
del servidor de aplicación (backend) mediante firewall.
