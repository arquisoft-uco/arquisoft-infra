# mailpit — servidor SMTP de pruebas + bandeja web (servicio auxiliar aislado)

Captura **todo** el correo que emite `arquisoft-backend` y lo muestra en una
bandeja web. **No entrega correo real**: nada sale del servidor, es un buzón de
pruebas para verificar que los correos se emiten y se ven bien.

> **Independiente del resto de la infra.** No forma parte de `deploy.sh` ni del
> `.env` de la raíz: lee su propio `.env` de esta carpeta y se levanta por su
> cuenta. Está pensado para sustituirse más adelante por un proveedor de correo
> real, y por eso no toca ningún archivo compartido del repo.

| | |
|---|---|
| Imagen | `axllent/mailpit:v1.31.1` (versión fijada) |
| SMTP | `mailpit:1025` — **solo dentro de `arquisoft-network`**, nunca publicado al host |
| Bandeja web | `https://mailpit.<DOMAIN>` vía Traefik, con autenticación propia de Mailpit |
| Persistencia | volumen `arquisoft-mailpit-data` (SQLite en `/data/mailpit.db`) |

## Uso

```bash
cd components/mailpit
cp .env.example .env       # y rellenar MAIL_PASSWORD (y DOMAIN si aplica)
./setup.sh                 # genera config/smtp-auth.txt desde el .env
docker compose up -d       # levantar
docker compose ps          # estado
docker compose logs -f     # ver el correo entrante
docker compose down        # detener (conserva los mensajes)
```

`docker compose` lee automáticamente el `.env` de esta carpeta.

Modo local, sin Traefik ni TLS (bandeja en `http://127.0.0.1:8025`, SMTP en `127.0.0.1:1025`):

```bash
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
```

## Requisito previo: DNS

El registro **A de `mailpit.<DOMAIN>` debe resolver a la IP pública del servidor
antes** de levantar el servicio. Traefik usa el desafío HTTP-01 de Let's
Encrypt: si el nombre no resuelve todavía, la emisión del certificado falla.

No hace falta abrir ningún puerto nuevo en el firewall: Traefik ya escucha en
80/443 y la bandeja entra por ahí.

## Acceso a la bandeja

`https://mailpit.<DOMAIN>` pide usuario y contraseña. Las credenciales son
**propias de este componente**: `MAILPIT_UI_USER` / `MAILPIT_UI_PASSWORD` del
`.env` de esta carpeta, escritas por `./setup.sh` en `config/ui-auth.txt`.

La aplica **el propio Mailpit** (`--ui-auth-file`), no el middleware
`admin-auth@file` de Traefik. Así el componente es autónomo — no depende del
`.htpasswd` compartido — y la protección cubre también a quien alcance el
puerto 8025 **desde dentro de `arquisoft-network`**, no solo a quien entra por
el proxy.

La protección no es opcional: la bandeja contiene enlaces de activación,
restablecimiento de contraseña y tokens de todos los usuarios del sistema.

> El router **no** aplica `secure-headers@file`. Ese middleware fuerza
> `X-Frame-Options: DENY` y Mailpit previsualiza cada correo dentro de un
> `<iframe>`, con lo que rompería la bandeja. Es el mismo motivo por el que
> `keycloak` también lo excluye.

## Autenticación SMTP

Mailpit sólo acepta las credenciales SMTP **desde un archivo**, no por variable
de entorno. `./setup.sh` genera `config/smtp-auth.txt` (gitignored) a partir de
`MAIL_USERNAME` / `MAIL_PASSWORD` del `.env` local.

El contenedor arranca además con `--smtp-auth-allow-insecure`: sin ese flag
Mailpit **rechaza** `AUTH PLAIN`/`LOGIN` sobre una conexión sin cifrar, que es
justo el caso del backend (`MAIL_SMTP_STARTTLS=false`). Es aceptable porque el
tráfico SMTP no sale de la red interna de Docker.

Si cambias las credenciales: edita `.env`, vuelve a correr `./setup.sh`, aplica
`docker compose up -d --force-recreate` y actualiza los secretos del backend.

## Variables que espera el backend

En los secretos de GitHub de `arquisoft-backend`:

```env
MAIL_HOST=mailpit
MAIL_PORT=1025
MAIL_USERNAME=<el MAIL_USERNAME de este .env>
MAIL_PASSWORD=<el MAIL_PASSWORD de este .env>
MAIL_SMTP_AUTH=true
MAIL_SMTP_STARTTLS=false
```

`MAIL_HOST=mailpit` funciona porque el backend y Mailpit comparten la red
`arquisoft-network` y Docker resuelve el nombre del servicio.

## Retención

Para que el volumen no crezca sin control, en el `.env`:

- `MAILPIT_MAX_MESSAGES` (por defecto `2000`) — al superarlo, se descartan los
  mensajes más antiguos.
- `MAILPIT_MAX_AGE` (por defecto `168h`, 7 días) — antigüedad máxima.

También puedes vaciar la bandeja a mano desde la UI (*Delete all*) o borrar el
volumen por completo:

```bash
docker compose down -v
```
