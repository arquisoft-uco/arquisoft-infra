# Despliegue Infraestructura en Coolify v4.0.0

## 1. Instalación
Instalación de coolify: https://coolify.io/docs/get-started/installation

## 2. Creación Proyecto
En el menú izquierdo ir a la sección de `Projects` y agregar un nuevo proyecto llamado `arquisoft-project`. Este crea por defecto un `environment` para despliegues en `production`.

Se puede crear nuevos `environment` como por ejemplo `development` para desplegar infraestructura compartida por el equipo y hacer pruebas. En esta sección solo abarcaremos el despliegue de la infraestructura necesaria para el ambiente de producción, pero esta guía puede ser usada de referencia para sus propios despligues en otros ambientes.

# Creación Recursos
Para crear un recurso debemos estar ubicados en el proyecto `arquisoft-proyect` de la sección `Projects`, este nos mostrará la vista de `Resources` donde podremos agregar recursos al `environment` seleccionado.

Para agregar un recursos damos clic en el botón para agregar recursos el cual nos redirigirá a la vista de `New Resource`, cada que seleccionamos un recurso si existen varios servidores vinculados a coolify, se le solicitará seleccionar el servidor donde se desplegará el recurso, para continuar.

## 3. Postgresql
- Buscar y seleccionar el recurso `PostgreSQL`, luego seleccionamos el tipo que nos interesa desplegar de este recurso, para nuestro caso usaremos `PostgreSQL 18 (default)`.
- En la vista de `Configuration` en la sección de `General` usamos el siguiente nombre personalizado `postgresql` y guardamos.
- Damos clic en `Start`, esperamos y confirmamos que el estado del recurso sea `Running (healthy)`.
- Para conectarse a la DB se recomienda usar una conexión a través de un tunel ssh.
- Después del despliegue se pueden asignar limites de recursos y configurar un tuning personalizado para producción en el archivo `postgresql.conf`.

## 4. Keycloak
- Buscar y seleccionar el recurso `Keycloak With Postgres`.
- En la vista de `Configuration` en la sección de `General` usamos el siguiente nombre personalizado `keycloak-with-postgres` y guardamos.
- Ahora configuramos el sub-dominio `keycloak` desde nuestro proveedor de dominios, en este caso lo configuramos para el domino `arquisoft.top` previamente adquirido.
- En la misma vista, ubicamos el apartado de `Services`, damos clic en `Settings` del servicio de `Keycloak` y modificamos el campo `Domains` por el sub-dominio que hayamos configurado, en este caso usaremos el dominio `https://keycloak.arquisoft.top`. Luego damos clic en guardar (si aparece un mensaje de alerta, dile que de todas formas continúe) y regresamos a la vista anterior.
- Damos clic en `Deploy`, esperamos y confirmamos que el estado del recurso sea `Running (healthy)`.
- Ingresamos a keycloak a través del dominio e iniciamos sesión con el usuario y clave proporcionado por coolify, dicho usuario es temporal así que se debe crear un nuevo usuario con el role `admin` para el realm de `master`.
- Después del despliegue se pueden asignar limites de recursos y configurar un tuning personalizado para producción.

## 5. RabbitMQ
- Buscar y seleccionar el recurso `Rabbitmq`.
- En la vista de `Configuration` en la sección de `General` usamos el siguiente nombre personalizado `rabbitmq` y guardamos.
- Ahora configuramos el sub-dominio `rabbitmq` desde nuestro proveedor de dominios, en este caso lo configuramos para el domino `arquisoft.top` previamente adquirido.
- En la misma vista, ubicamos el apartado de `Services`, damos clic en `Settings` del servicio de `Rabbitmq` y modificamos el campo `Domains` por el sub-dominio que hayamos configurado, en este caso usaremos el dominio `https://rabbitmq.arquisoft.top`. Luego damos clic en guardar (si aparece un mensaje de alerta, dile que de todas formas continúe) y regresamos a la vista anterior.
- Tener presente que si no se desea las credenciales generadas por coolify, se deben modificar en la sección de `Environment Variables`, específicamente las variables de `SERVICE_USER_RABBITMQ` y `SERVICE_PASSWORD_RABBITMQ`. Este pasó es importante tenerlo en cuenta ya que después de desplegar ya no se podrá modificar estas credenciales a través de las variables de entorno. Para nuestro caso usaremos las generadas por coolify.
- Editamos el docker compose del recurso, primero agregamos un nuevo puerto en el parámetro `services.rabbitmq.ports` con el valor de `'15672:15672'`, luego agregamos el siguienite parámetro al mismo nivel que el anterior y guardamos:
```yml
    labels:
      - coolify.managed=true
      - traefik.http.services.rabbitmq-db-server.loadbalancer.server.port=15672
```
- Damos clic en `Deploy`, esperamos y confirmamos que el estado del recurso sea `Running (healthy)`.
- Ingresamos a rabbitmq a través del dominio e iniciamos sesión con el usuario y clave proporcionado por coolify. Con este usuario se puede crear un nuevo usuario con permisos limitados para ser utilizado en nuestro backend por ejemplo.
- Después del despliegue se pueden asignar límites de recursos y configurar un tuning personalizado para producción.

## 6. Observability
- Buscar y seleccionar el recurso `Docker Compose Empty`.
- En la vista de `Create a new Service` copiamos y pegamos el contenido del docker compose.
- Editamos el docker compose del recurso agregando o modificando el parametro `services.grafana.labels` el item `coolify.proxy.port=3000`; al parámetro `services.grafana.environment`, el item `GF_SERVER_ROOT_URL=https://grafana.arquisoft.top`; luego de esto guardamos.
- En la vista de `Configuration` en la sección de `General` usamos el siguiente nombre personalizado `observability` y guardamos.
- Ahora configuramos el sub-dominio `grafana` desde nuestro proveedor de dominios, en este caso lo configuramos para el domino `arquisoft.top` previamente adquirido.
- En la misma vista, ubicamos el apartado de `Services`, damos clic en `Settings` del servicio de `Grafana` y modificamos el campo `Domains` por el sub-dominio que hayamos configurado, en este caso usaremos el dominio `https://grafana.arquisoft.top` usado en la variable de entorno del docker compose para el servicio de grafana. Luego damos clic en guardar (si aparece un mensaje de alerta, dile que de todas formas continúe) y regresamos a la vista anterior.
- Damos clic en `Deploy`, esperamos y confirmamos que el estado del recurso sea `Running (healthy)`.
- Ingresamos a grafana a través del dominio e iniciamos sesión con el usuario y clave proporcionado por coolify, por defecto el usuario y clave es `admin` así que debemos iniciar sesión inmediatemente para que grafana nos solicite la nueva clave del usuario.
- En grafana vamos a la sección de `Connections >> Add new connection`, buscamos `Loki` y lo seleccionamos, damos clic en `Add new data source`, en el campo `URL` asignamos la url donde está desplegado nuestro servicio de loki internamente en el servidor `http://loki:3100` y guardamos.
- En grafana vamos a la sección de `Connections >> Add new connection`, buscamos `Prometheus` y lo seleccionamos, damos clic en `Add new data source`, en el campo `URL` asignamos la url donde está desplegado nuestro servicio de prometheus internamente en el servidor `http://prometheus:9090` y guardamos.
- En grafana vamos a la sección de `Connections >> Data sources`, allí podremos ver las dos conexiones previamente configuradas.
- Después del despliegue se pueden asignar limites de recursos y configurar un tuning personalizado para producción.

## 7. Redis
- Buscar y seleccionar el recurso `Redis`.
- En la vista de `Configuration` en la sección de `General` usamos el siguiente nombre personalizado `redis-cache` y guardamos.
- Damos clic en `Start`, esperamos y confirmamos que el estado del recurso sea `Running (healthy)`.
- Para conectarse a la cache se recomienda usar una conexión a través de un tunel ssh.
- Después del despliegue se pueden asignar limites de recursos y configurar un tuning personalizado para producción.

## 8. MinIO