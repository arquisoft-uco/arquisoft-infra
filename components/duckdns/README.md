# duckdns — DNS dinámico (servicio auxiliar aislado)

Mantiene un subdominio de [DuckDNS](https://www.duckdns.org) (p. ej.
`unyai.duckdns.org`) apuntando a la **IP pública actual** del servidor. Útil
cuando el servidor no tiene IP fija (conexión doméstica, VPS con IP variable).

> **Independiente del resto de la infra.** No forma parte de `deploy.sh` ni del
> `.env` de la raíz, no usa la red `arquisoft-network` ni expone puertos. Es una
> configuración auxiliar que se levanta y gestiona por su cuenta.

La imagen `lscr.io/linuxserver/duckdns` ejecuta un bucle que llama al endpoint de
actualización de DuckDNS **cada 5 minutos**.

## Uso

```bash
cd components/duckdns
cp .env.example .env       # y rellenar DUCKDNS_TOKEN
docker compose up -d       # levantar
docker compose ps          # estado
docker compose logs -f     # ver actualizaciones
docker compose down        # detener
```

`docker compose` lee automáticamente el `.env` de esta carpeta.

## Configuración (`.env` local)

```env
DUCKDNS_SUBDOMAINS=unyai   # sin el sufijo .duckdns.org
DUCKDNS_TOKEN=<token>      # https://www.duckdns.org tras iniciar sesión
DUCKDNS_UPDATE_IP=ipv4     # ipv4 | ipv6 | both
```

El token se obtiene iniciando sesión en https://www.duckdns.org (aparece arriba
de la página). Es el mismo para todos los dominios de esa cuenta.

## Verificar

```bash
# Resultado de la última actualización (debe decir OK)
docker exec arquisoft-duckdns cat /config/duck.log

# Comprobar que el DNS resuelve a tu IP pública
dig +short unyai.duckdns.org
curl -s https://api.ipify.org        # tu IP pública real (deben coincidir)
```

Una respuesta `KO` en el log suele indicar token o subdominio incorrectos.
