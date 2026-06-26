# Componente: rabbitmq (Message Broker)

RabbitMQ 4.2 con plugin de gestión. Carga colas/exchanges desde
`config/definitions.json` (renderizado del template por `deploy.sh`).

## Acceso
- AMQP `:5672` — solo red interna/privada (lo consume el backend).
- Consola `https://rabbitmq.${DOMAIN}` — BasicAuth vía Traefik (prod).
- Dev: `http://127.0.0.1:15672`.

## Uso
```bash
./deploy.sh dev rabbitmq
./deploy.sh prod rabbitmq

# Standalone
docker compose --env-file ../../.env up -d
```

## Multi-servidor
AMQP (5672) abierto solo a la IP privada del servidor de aplicación. La consola se expone
por HTTPS desde el Traefik del servidor de datos.
