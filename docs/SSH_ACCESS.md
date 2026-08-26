# Acceso SSH al servidor — Arquisoft IaC

Guía para conectarse al servidor (Oracle Cloud) por SSH y para dar acceso a un nuevo
miembro del equipo. Autenticación **solo por llave pública** (sin contraseña).

## Conexión actual (alias `oracle`)

El alias vive en `~/.ssh/config` de cada máquina cliente, no en este repo:

```
Host oracle
    HostName <ip_publica_servidor>
    User ubuntu
    IdentityFile ~/ruta/a/tu-clave-privada.key
    IdentitiesOnly yes
```

Con eso configurado, conectarse es:

```bash
ssh oracle
```

> `User ubuntu` es el usuario del sistema operativo (la imagen base de Oracle Cloud).
> No confundir con los usuarios de aplicación (`arquisoft_user`, `arquisoft_backend`, …)
> descritos en el [README](../README.md) — esos son credenciales de los servicios
> Docker, no del host.

## Dar acceso a un nuevo compañero

**Nunca compartir la llave privada existente** (por chat, email o repo). Cada persona
debe tener su propio par de llaves; el servidor solo necesita la parte **pública**.

1. El compañero genera su propio par (en su máquina):
   ```bash
   ssh-keygen -t ed25519 -C "compañero@arquisoft"
   ```
   Esto crea `~/.ssh/id_ed25519` (privada, se queda en su máquina) y
   `~/.ssh/id_ed25519.pub` (pública, la que comparte).

2. Te pasa el contenido de `id_ed25519.pub` (un solo renglón, empieza con `ssh-ed25519`).

3. Tú la agregas al `authorized_keys` del usuario `ubuntu` en el servidor:
   ```bash
   ssh oracle 'echo "<contenido-de-la-pubkey>" >> ~/.ssh/authorized_keys'
   ```

4. El compañero configura su propio `~/.ssh/config`:
   ```
   Host oracle
       HostName <ip_publica_servidor>
       User ubuntu
       IdentityFile ~/.ssh/id_ed25519
       IdentitiesOnly yes
   ```

5. Verifica: `ssh oracle` desde su máquina.

## Revocar acceso

Editar `~/.ssh/authorized_keys` en el servidor y borrar la línea de la llave pública
correspondiente:

```bash
ssh oracle
nano ~/.ssh/authorized_keys   # eliminar la línea de la llave a revocar
```

No hay forma de "invalidar" una llave privada de forma remota: revocar es simplemente
quitar su pública de `authorized_keys`.

## Nota de seguridad

Todo el equipo comparte hoy el mismo usuario de sistema (`ubuntu`), solo con llaves
distintas. Esto da autenticación individual pero **no trazabilidad por comando** (los
logs de auditoría del host no distinguen quién ejecutó qué). Si se necesita
trazabilidad, la alternativa es crear un usuario Linux por persona
(`sudo adduser <nombre>` + agregarlo a `docker`/`sudo` según necesite) en vez de
compartir `ubuntu`.
