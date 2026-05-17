# Despliegue — Grafana Alloy (Coolify)

> Guía paso a paso para desplegar Alloy junto al backend.
> Prerequisito: el stack de observabilidad (Loki, Prometheus, Grafana) debe estar
> activo. Ver [OBSERVABILIDAD_COOLIFY.md](OBSERVABILIDAD_COOLIFY.md).

---

## Escenarios de despliegue

Alloy necesita saber dónde están Loki y Prometheus. Esto depende de si el backend
comparte servidor con el stack de observabilidad o no.

### Escenario A — mismo servidor

El backend y el stack de observabilidad corren en el mismo host Coolify. Alloy
puede alcanzar Loki y Prometheus por su nombre de contenedor dentro de la red
Docker `coolify`, sin exponer puertos al exterior.

| Variable | Valor |
|---|---|
| `LOKI_URL` | `http://loki:3100/loki/api/v1/push` |
| `PROMETHEUS_URL` | `http://prometheus:9090/api/v1/write` |

### Escenario B — servidores separados (red privada)

El backend está en **Server 1** y el stack de observabilidad en **Server 2**,
ambos dentro de la misma red privada del proveedor. Alloy usa la IP privada de
Server 2 para alcanzar los puertos expuestos.

| Variable | Valor ejemplo |
|---|---|
| `LOKI_URL` | `http://10.0.0.2:3100/loki/api/v1/push` |
| `PROMETHEUS_URL` | `http://10.0.0.2:9090/api/v1/write` |

> Reemplazar `10.0.0.2` con la IP privada real de Server 2. El firewall de Server 2
> debe permitir conexiones entrantes desde la IP de Server 1 en los puertos `3100` y `9090`.

---

## 1. Label en el backend

- En Coolify → app del backend → **Configuration → Labels (Custom Labels)**, agregar:
  ```
  monitoring=arquisoft-backend
  ```
  Si el campo no es editable, asegurarse de que **Readonly labels** esté desmarcado.
- Hacer **Redeploy** del backend para que el label quede aplicado. Sin este paso Alloy no capturará ningún log.

## 2. Copiar `config.alloy` al servidor

Alloy lee la configuración desde una ruta fija del host. Debe copiarse antes del primer deploy y cada vez que el archivo cambie.

```bash
ssh root@<SERVER1_IP> 'mkdir -p /opt/alloy'
scp infra/coolify/config.alloy root@<SERVER1_IP>:/opt/alloy/config.alloy
```

## 3. Crear el recurso en Coolify

- Buscar y seleccionar el recurso **Docker Compose Empty**.
- En la vista **Create a new Service**, copiar y pegar el contenido de [`docker-compose-alloy.yml`](../infra/coolify/docker-compose-alloy.yml). En este paso también se pueden editar las variables de entorno directamente en el compose.
- En **Configuration → General**, usar el nombre personalizado `alloy` y guardar.
- En **Configuration → Environment Variables**, configurar las variables según el escenario si no se hizo en el paso anterior (ver tabla al inicio del documento).

## 4. Desplegar

- Clic en **Deploy**, esperar y confirmar que el estado sea `Running (healthy)`.
- Después del despliegue se pueden asignar límites de recursos y configurar tuning personalizado para producción.

## 5. Verificar
Se puede verificar los logs del contenedor en la vista `Logs` del recurso de coolify.

Confirmar en Grafana con la query:
```logql
{container="arquisoft-backend", job="backend-java-coolify"}
```
