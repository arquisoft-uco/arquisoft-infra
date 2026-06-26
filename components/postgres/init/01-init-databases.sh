#!/bin/bash
# =============================================================================
# PostgreSQL (app) — inicialización de bases de datos por bounded context
# =============================================================================
# Se ejecuta UNA sola vez, al crear el volumen de datos.
# Crea el usuario de aplicación y 7 bases de datos (una por contexto del backend).
# La BD de Keycloak NO está aquí: vive en su instancia dedicada (componente keycloak).
# Fuente del modelo: arquisoft-backend/init-db.sql
# =============================================================================
set -euo pipefail

APP_USER="${APP_DB_USER:-arquisoft_user}"
APP_PASS="${APP_DB_PASSWORD:?APP_DB_PASSWORD requerido}"
DBS="usuarios fichas_perfil artefactos repositorio_artefactos proyectos_grado entregables evaluaciones"

echo "==> Creando usuario de aplicación '${APP_USER}'"
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
  DO \$\$
  BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = '${APP_USER}') THEN
      CREATE USER ${APP_USER} WITH PASSWORD '${APP_PASS}';
    END IF;
  END
  \$\$;
EOSQL

for db in $DBS; do
  exists=$(psql -tAc "SELECT 1 FROM pg_database WHERE datname='${db}'" --username "$POSTGRES_USER" --dbname "$POSTGRES_DB")
  if [ "$exists" != "1" ]; then
    echo "==> Creando base de datos '${db}' (owner ${APP_USER})"
    createdb --username "$POSTGRES_USER" --owner "$APP_USER" "$db"
  fi
  # PG15+: el schema public ya no otorga CREATE por defecto — se asigna al app user
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$db" <<-EOSQL
    GRANT ALL ON SCHEMA public TO ${APP_USER};
    ALTER SCHEMA public OWNER TO ${APP_USER};
    CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
    CREATE EXTENSION IF NOT EXISTS "pg_trgm";
EOSQL
done

echo "==> Inicialización completada: ${DBS}"
