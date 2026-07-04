# Requisito de red del host (Docker) para el esquema VPN

> Contexto: los servicios se despliegan en la red Docker `arquisoft-network` con
> subnet **`172.16.1.0/24`** (definida por `docker_subnet` en `terraform.tfvars`),
> para que sean alcanzables por VPN. Este documento explica el **único** requisito
> a nivel del host y cómo verificarlo/arreglarlo.

## TL;DR

- **Servidor Docker limpio:** no hay que hacer nada. El bridge por defecto
  (`docker0`) arranca en `172.17.0.1/16` y **no** colisiona con `172.16.1.0/24`.
  `terraform apply` crea `arquisoft-network` directamente.
- **Servidor con `daemon.json` custom** que fije `docker0` o el pool en `172.16.x`:
  hay que moverlo fuera de `172.16.0.0/16` **antes** de aplicar (ver más abajo).

## El requisito

Dos redes Docker no pueden tener subnets solapadas. Nuestro esquema reserva
`172.16.0.0/16` para VPN + servicios:

| Subnet | Uso |
|---|---|
| `172.16.0.0/24` | Clientes VPN (WireGuard `wg0`) |
| `172.16.1.0/24` | `arquisoft-network` (servicios: postgres, keycloak, ...) |
| `172.16.2.0/24`+ | Futuros nodos |

Por lo tanto, **`docker0` (bridge default) y el `default-address-pool` de Docker
NO deben caer dentro de `172.16.0.0/16`.**

### Por qué en un servidor limpio "simplemente funciona"

El default de fábrica de Docker es:
- `docker0` → `172.17.0.1/16`
- Redes de usuario → `172.18.0.0/16`, `172.19.0.0/16`, … (espacio `172.16.0.0/12`
  a partir de `172.17`).

Nada de eso pisa `172.16.1.0/24`. Además, como Terraform crea `arquisoft-network`
con **subnet explícita** (`ipam_config`), no depende del pool automático.

> El rango `10.x` que puede aparecer en algunos hosts **no** es default de Docker:
> viene de un `default-address-pool` custom en `daemon.json`.

## Verificación

```bash
# ¿docker0 pisa 172.16.x?
ip -4 addr show docker0 | grep inet
# OK si es 172.17.x (o cualquier cosa fuera de 172.16.0.0/16)

# ¿el daemon.json fija bip o pool en 172.16.x?
sudo cat /etc/docker/daemon.json 2>/dev/null
```

## Arreglo (solo si docker0/pool cae en 172.16.x)

En este repo se resolvió así en el servidor Oracle (config heredada de experimentos
previos que fijaba `docker0` en `172.16.1.0/24`):

1. Dejar `/etc/docker/daemon.json` con `bip` fuera de `172.16.x` (el default de
   Docker sirve). Ejemplo mínimo:

   ```json
   {
     "bip": "172.17.0.1/16",
     "log-driver": "json-file",
     "log-opts": { "max-size": "10m", "max-file": "3" }
   }
   ```

   > `172.17.0.1/16` es justamente el default de Docker. En un host nuevo podrías
   > omitir `bip` por completo.

2. Forzar que Docker recree el bridge con el rango nuevo (quitar solo el `bip` NO
   basta: la red `bridge` persiste su subnet en `/var/lib/docker/network`):

   ```bash
   sudo systemctl stop docker
   sudo ip link del docker0        # docker0 no tiene contenedores propios → inofensivo
   sudo systemctl start docker
   ```

3. Verificar:

   ```bash
   ip -4 addr show docker0 | grep inet                                   # → 172.17.x
   docker network inspect bridge --format '{{range .IPAM.Config}}{{.Subnet}}{{end}}'  # → 172.17.0.0/16
   ```

Con `172.16.1.0/24` libre, `terraform apply` crea/renumera `arquisoft-network` sin
conflicto.

## Deuda técnica conocida

Este ajuste de `daemon.json` es **configuración del host, fuera de Terraform**. Si se
reconstruye el servidor desde cero:
- Con Docker por defecto: no se necesita (ver TL;DR).
- Si se reintroduce un `daemon.json` custom con pools en `172.16.x`: reaplicar este
  documento.

Para automatizarlo del todo, se podría añadir un `host-setup.sh` que garantice el
`daemon.json` correcto como parte del aprovisionamiento del host (fuera del ciclo de
Terraform, que gestiona contenedores, no el daemon).
