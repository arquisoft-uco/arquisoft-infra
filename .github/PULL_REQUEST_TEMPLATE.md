## Descripción

<!-- Breve descripción de los cambios realizados -->

## Historia / Incidente Relacionado

- [ ] HT-XXX / INC-XXX: (descripción)

## Tipo de Cambio

- [ ] feat: Nueva funcionalidad
- [ ] fix: Corrección de error
- [ ] refactor: Refactorización sin cambio funcional
- [ ] docs: Cambios en documentación
- [ ] chore: Tareas de mantenimiento
- [ ] ci: Cambios en CI/CD

## Checklist de Revisión

### Convenciones
- [ ] Commits siguen Conventional Commits en español
- [ ] Archivos YAML validados con `docker compose config`

### Seguridad
- [ ] Sin secrets ni credenciales en el código
- [ ] Archivos `.env` NO incluidos en el commit

### Funcional
- [ ] Docker Compose levanta correctamente (`docker compose up -d`)
- [ ] Servicios responden en health checks
- [ ] Sin regresiones en servicios existentes

## Notas para el Reviewer

<!-- Cualquier contexto adicional para facilitar la revisión -->
