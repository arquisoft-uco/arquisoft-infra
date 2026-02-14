-- ==============================================================================
-- Arquisoft - PostgreSQL Initial Schema
-- ==============================================================================
-- Script de inicialización ejecutado al crear el contenedor por primera vez
-- ==============================================================================

-- Crear esquemas por contexto (Bounded Context separation)
CREATE SCHEMA IF NOT EXISTS usuarios;
CREATE SCHEMA IF NOT EXISTS fichas_perfil;
CREATE SCHEMA IF NOT EXISTS proyectos_grado;
CREATE SCHEMA IF NOT EXISTS artefactos;
CREATE SCHEMA IF NOT EXISTS evaluaciones;
CREATE SCHEMA IF NOT EXISTS mapa_ruta;
CREATE SCHEMA IF NOT EXISTS notificaciones;
CREATE SCHEMA IF NOT EXISTS solicitudes;
CREATE SCHEMA IF NOT EXISTS biblioteca;
CREATE SCHEMA IF NOT EXISTS entregables;

-- Esquema para Keycloak (si comparte BD)
CREATE SCHEMA IF NOT EXISTS keycloak;

-- Extensiones útiles
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";  -- Para búsqueda fuzzy

-- Tabla de auditoría global
CREATE TABLE IF NOT EXISTS audit_log (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    schema_name VARCHAR(50) NOT NULL,
    table_name VARCHAR(100) NOT NULL,
    operation VARCHAR(10) NOT NULL,
    old_data JSONB,
    new_data JSONB,
    user_id UUID,
    user_email VARCHAR(255),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    correlation_id UUID
);

CREATE INDEX idx_audit_log_created_at ON audit_log(created_at DESC);
CREATE INDEX idx_audit_log_table ON audit_log(schema_name, table_name);
CREATE INDEX idx_audit_log_user ON audit_log(user_id);

-- Función para trigger de auditoría
CREATE OR REPLACE FUNCTION audit_trigger_function()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (schema_name, table_name, operation, old_data, new_data, user_id, user_email)
    VALUES (
        TG_TABLE_SCHEMA,
        TG_TABLE_NAME,
        TG_OP,
        CASE WHEN TG_OP = 'DELETE' OR TG_OP = 'UPDATE' THEN row_to_json(OLD) ELSE NULL END,
        CASE WHEN TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN row_to_json(NEW) ELSE NULL END,
        NULLIF(current_setting('app.current_user_id', true), '')::UUID,
        current_setting('app.current_user_email', true)
    );
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

-- Mensaje de confirmación
DO $$
BEGIN
    RAISE NOTICE 'Arquisoft database initialized successfully';
    RAISE NOTICE 'Schemas created: usuarios, fichas_perfil, proyectos_grado, artefactos, evaluaciones, mapa_ruta, notificaciones, solicitudes, biblioteca, entregables';
END $$;
