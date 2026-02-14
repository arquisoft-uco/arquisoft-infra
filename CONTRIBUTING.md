# Guía de Contribución — Arquisoft Infra

## Antes de Contribuir

1. Lee los [Estándares de Código](https://github.com/arquisoft-uco/arquisoft-docs/blob/main/docs/architecture/coding-standards.md)
2. Asegúrate de tener asignada la tarea correspondiente

## Flujo de Trabajo

1. Crea una rama desde `develop` siguiendo la convención: `<prefijo>/<id>-<descripcion_snake_case>`
   - Ejemplo: `feature/HT-001-despliegue_infraestructura_desarrollo`
2. Implementa los cambios siguiendo las convenciones del proyecto
3. Valida con `docker compose config` que los archivos YAML sean correctos
4. Crea un Pull Request hacia `develop` usando el template provisto
5. Espera al menos 1 review aprobado antes de mergear

## Convenciones

- **Commits:** Conventional Commits en español — `feat(infra): descripción`
- **Branching:** GitFlow simplificado
  - Prefijos válidos: `feature/`, `fix/`, `refactor/`, `hotfix/`, `docs/`, `test/`, `chore/`, `spike/`
  - Formato: `<prefijo>/<id>-<descripcion_snake_case>`
- **Secrets:** NUNCA commitear `.env` ni credenciales

## Estructura del PR

Usa el template de PR incluido en `.github/PULL_REQUEST_TEMPLATE.md`.
