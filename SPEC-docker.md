# SPEC-docker.md — cómo se empaqueta y se despliega una app

## Alcance

El contrato de contenedor de la familia: multi-stage, release de Mix, entrypoint
que migra antes de servir, healthcheck honesto y puertos bien cableados.
Referencia canónica: **`tokengate/Dockerfile`** (117 líneas) +
`tokengate/docker/entrypoint.sh`.

## Reglas duras

1. **`mix deps.get --only prod` antes de `mix compile`** — al revés, una
   `mix.lock` desactualizada aborta con `lock outdated` (`tokengate/Dockerfile:42-45`).
2. **`mix release` sin nombre** (usa el `:app` de `mix.exs`) y los overlays
   `bin/migrate` / `bin/server` presentes (`tokengate/Dockerfile:67`).
3. **El entrypoint migra antes de servir**; si la migración falla, el boot
   aborta y el deploy se revierte (`tokengate/docker/entrypoint.sh:21-31`).
4. **Non-root** (`useradd app`, `USER app`) y `HOME=/app`
   (`tokengate/Dockerfile:86-87`, `:97-99`).
5. **Sin secretos en `ARG`/`ENV`** — se hornean en las capas. Sólo hay **un**
   build arg legítimo: `DISABLE_FORCE_SSL` (`tokengate/Dockerfile:34-35`).
6. **`force_ssl` es compile-time**: se apaga con build arg, no con runtime
   (`tokengate/config/prod.exs:14-20`). El **esqueleto sale con HTTPS por
   default** (`DISABLE_FORCE_SSL=""`); TokenGate sale HTTP-plano (`"1"`) porque
   vive detrás de VPN — el default de una app nueva no se hereda de ahí sin
   decidirlo.
7. **El healthcheck apunta a `/health`, nunca a `/`**: `/` responde 302 y un
   proxy que espera 200 marca el contenedor como caído (`tokengate/Dockerfile:114-115`).
8. **`PORT` (escucha) == puerto que el proxy expone**; `PHX_PORT` es sólo el de
   las URLs generadas. `EXPOSE` no cambia el listen — por eso no se usa.
9. **Nunca Alpine** en runtime (DNS de Erlang distribuido se rompe con musl).

## Etapa build

| Qué | Referencia |
|---|---|
| Imagen base pinneada + runtime del mismo slug Debian (evita drift de glibc) | `tokengate/Dockerfile:11-12` |
| `build-essential git curl ca-certificates` (los wrappers tailwind/esbuild bajan sus binarios; Node sólo si `assets/package.json` lo exige) | `tokengate/Dockerfile:19-21` |
| `mix local.hex` / `local.rebar`, `MIX_ENV=prod` | `tokengate/Dockerfile:25-27` |
| `DISABLE_FORCE_SSL` como `ARG` **y** `ENV` (Coolify lo ve en la UI) | `tokengate/Dockerfile:34-35` |
| Sólo `mix.exs`/`mix.lock`/`config` antes de `deps.get` (cache de capa) | `tokengate/Dockerfile:42-45` |
| Guard de OOM para rebar3 en contenedores chicos: `ERL_AFLAGS="+S 1:1"` en un `deps.compile` previo | `tokengate/Dockerfile:51-52` |
| `COPY lib priv assets rel` → `mix compile` → `mix assets.deploy` | `tokengate/Dockerfile:55-61` |
| `mix release` | `tokengate/Dockerfile:67` |

## Etapa runtime

| Qué | Referencia |
|---|---|
| `libstdc++6 openssl libncurses6 locales ca-certificates curl` (curl es para el healthcheck del proxy) | `tokengate/Dockerfile:75-77` |
| Locale UTF-8 (`LANG`/`LC_ALL`) | `tokengate/Dockerfile:80-81` |
| `COPY --from=build --chown=app:app /app/_build/prod/rel/<app> ./` | `tokengate/Dockerfile:87` |
| `COPY docker/entrypoint.sh` + `chmod +x` | `tokengate/Dockerfile:94-95` |
| `ENV HOME=/app MIX_ENV=prod PHX_SERVER=true PORT=4000` | `tokengate/Dockerfile:99` |
| `HEALTHCHECK … curl -fsS http://127.0.0.1:${PORT}/health` (start-period 60s, 5 retries) | `tokengate/Dockerfile:114-115` |
| `ENTRYPOINT ["/app/entrypoint.sh"]` | `tokengate/Dockerfile:117` |

### El endpoint `/health`

Público, sin auth, y **sin tocar la base**: responde 200 en cuanto el listener
está arriba (`tokengate/lib/tokengate_web/controllers/health_controller.ex:1-27`).
Es deliberado: el probe corre mientras el boot siembra catálogo y particiones, y
un probe que consulte la base puede tumbar un contenedor sano.

Dran todavía tiene un `/health` que consulta la base
(`dran/lib/dran_web/controllers/health_controller.ex:6`, `SELECT 1`) y devuelve
503 si no contesta: **antes** de ponerle el `HEALTHCHECK` canónico hay que
volverlo DB-free, o el contenedor se reporta caído durante el arranque. Si una
app necesita un readiness con base, va en **otra** ruta.

## Entrypoint

Canónico (`tokengate/docker/entrypoint.sh:21-31`):

```sh
set -e
if [ "$SKIP_MIGRATIONS" = "1" ]; then echo "skipping"; else bin/<app> eval "<App>.Release.setup"; fi
exec bin/<app> start
```

- `Release.setup/0` es idempotente: crear base → migrar → seed
  (`tokengate/lib/tokengate/release.ex:33`, `:42`, `:54`, `:77`).
- La primera cuenta: sin `*_ADMIN_PASSWORD` el boot no crea usuario y la app
  manda a la pantalla de primera ejecución — la ventana en que el primero que
  llegue se apropia de la instancia. Se cierra con la variable o desplegando
  detrás de la frontera de red.
- Variantes de dominio (no del esqueleto): Dran añade `DRAN_RESET=1`, destructivo
  y activo en **cada** arranque mientras esté puesto
  (`dran/docker/entrypoint.sh:29-37`).

## `.dockerignore`

Canónico: `_build`, `deps`, `node_modules`, assets generados, `.git`, `.env*`,
test/docs/tmp, basura de editor.

Regla dura que costó un audit: **cualquier directorio de subidas va ignorado**.
Dran no ignora `priv/static/uploads`, así que `COPY priv priv` hornea las subidas
locales (93 archivos / 72 MB en el working tree al momento del audit). Estar en
`.gitignore` no alcanza — el contexto de build es otra cosa.

## Puertos

| Variable | Qué es | Regla |
|---|---|---|
| `PORT` | puerto real de escucha (runtime) | debe coincidir con **Ports Exposes** del recurso en Coolify |
| `PHX_PORT` | puerto de las URLs generadas | el externo (443 con TLS, 4000/5000 tras VPN) |
| `EXPOSE` | metadata de la imagen | **no** cambia el listen: por eso los Dockerfiles de la familia no lo llevan |

## Verificación antes de pushear

```bash
# 1. el release existe y trae sus bins
rm -rf _build/prod && MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile --warnings-as-errors   # los colocalados se generan acá
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
ls _build/prod/rel/<app>/bin/          # <app>, migrate, server, setup

# 2. arranca con config de mentira (falla si runtime.exs está roto)
DATABASE_URL=ecto://nope:nope@127.0.0.1:1/nope SECRET_KEY_BASE=test \
  PHX_HOST=localhost SESSION_SIGNING_SALT=a SESSION_ENCRYPTION_SALT=b \
  _build/prod/rel/<app>/bin/<app> eval "IO.puts(:ok)"     # -> :ok

# 3. la imagen se construye y el healthcheck responde
docker build -t <app> . && docker run --rm -p 4000:4000 --env-file .env <app>
curl -fsS http://127.0.0.1:4000/health
```

> `mix assets.deploy` **antes** de `mix compile` en `:prod` falla con
> `Can't resolve 'phoenix-colocated/<app>/colocated.css'`: los assets colocalados
> se generan al compilar. El Dockerfile ya respeta ese orden.
>
> Contra un Postgres local sin TLS hay que pasar `ECTO_SSL=false`: el default es
> SSL activado y el síntoma es engañoso (`ssl not available` +
> `failed to create db … "killed"`).

## Pendientes conocidos por app

Detectado al auditar cada app contra estos specs. **No se porta nada a una app
sin decidirlo**: queda acá como backlog, con el ancla exacta (el gate
`scripts/check-spec-refs.py` la verifica).

### Dran

| Pendiente | Ancla | Nota |
|---|---|---|
| `/health` consulta la base y devuelve 503 | `dran/lib/dran_web/controllers/health_controller.ex:6` | volverlo DB-free **antes** de ponerle el `HEALTHCHECK` |
| Imagen sin `HEALTHCHECK` | `dran/Dockerfile` | el runtime ya instala `curl` para el check del proxy |
| `deps.compile` sin guard de OOM | `dran/Dockerfile:48` | `ERL_AFLAGS="+S 1:1"` para build containers de 512 MB–1 GB |
| `.dockerignore` sin las subidas | `dran/.dockerignore` | 93 archivos / 72 MB horneados por `COPY priv priv` |
| `DISABLE_FORCE_SSL` en `""` (HTTPS) | `dran/Dockerfile:36` | decisión de deploy: **no** se hereda el `"1"` de TokenGate |
| Sesión sin `renew` y salts iguales | `dran/lib/dran_web/endpoint.ex:19-20` | ver `SPEC-config.md` §Pendiente en Dran |
| README §Production sin guía de contenedor | `dran/README.md:261` | healthcheck, PORT vs Ports Exposes, primera ejecución, volumen de uploads |

## Anti-patrones

- Healthcheck apuntando a `/` (302 → el proxy lo lee como caído → 502).
- Migrar en post-deploy: la migración va **antes** de mover tráfico.
- `EXPOSE` como si fijara el puerto.
- Compilar sin guard de schedulers en contenedores de 512 MB–1 GB (`exit 255`).
- Cambiar la imagen runtime a Alpine.
- Un `ARG` con una contraseña.