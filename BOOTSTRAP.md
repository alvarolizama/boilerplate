# BOOTSTRAP.md — cómo nace una app de la familia

Procedimiento mecánico, con las trampas ya vistas. El orden importa: **primero
los specs, después el código.**

1. `README.md` (índice) → `SPEC-design.md`, `SPEC-config.md`, `SPEC-docker.md`.
2. `VERSIONS.md` — lo que se fija.
3. `bash skeleton/bootstrap.sh <destino>` (esta guía).
4. `mix precommit` + el smoke del release (`SPEC-docker.md` §Verificación).

## Un comando

```bash
bash skeleton/bootstrap.sh ~/Workspace/Repos/alvarolizama/<app>
```

Hace, en orden:

| Paso | Qué |
|---|---|
| 1 | `mix phx.new <scratch> --app <app> --binary-id --no-version-check` |
| 2 | `rsync` del scaffold al destino (conserva el `README.md` y el `.gitignore` del repo) |
| 3 | copia `skeleton/overlay/**` reemplazando `{{app}}` / `{{App}}` / `{{APP}}` y **falla si queda algún placeholder** |
| 4 | mergea en `.gitignore` las entradas de la familia (`.riel/`, `/priv/static/uploads/`, `erl_crash.dump`) |
| 5 | aplica el tema `dim`: `themes: dim --default` en `app.css`, borra los temas/variant del scaffold, pone `data-theme="dim"` en `root.html.heex`, borra el switcher inline, agrega `favicon.svg` a `static_paths` |
| 6 | agrega la ruta `GET /health` al router (scope sin pipeline, fuera de `:browser`) |

**No hace** (lo imprime al final): `mix deps.get`, crear la base, el primer commit.

### Qué trae el overlay (15 archivos)

| Archivo | Qué aporta |
|---|---|
| `Dockerfile` | multi-stage canónico (guard de OOM, healthcheck, non-root, sin `EXPOSE`) |
| `docker/entrypoint.sh` | `Release.setup` → `start`, `SKIP_MIGRATIONS=1` |
| `.dockerignore` | incluye `priv/static/uploads/` (el hueco que tenía Dran) |
| `.env.example` | plantilla completa de variables |
| `config/runtime.exs` | env vars, boot fail-closed, TLS de la base, `CHECK_ORIGINS` |
| `config/prod.exs` | `cache_static_manifest`, gate de `force_ssl`, Swoosh |
| `lib/<app>/release.ex` | `setup/0` · `create/0` · `migrate/0` · `seed/0` idempotentes |
| `lib/<app>_web/endpoint.ex` | bloque de sesión de la familia (`renew: true`, salts distintos) |
| `lib/<app>_web/controllers/health_controller.ex` | `/health` que no toca la base |
| `rel/overlays/bin/{migrate,setup,server}` + `.bat` | bins del release |
| `priv/repo/seeds_prod.exs` | stub documentado del seed de producción (opt-in) |
| `lib/<app>_web/router.ex` | **no es overlay**: el bootstrap inserta la ruta `GET /health` |

## Después del bootstrap

```bash
cd <app>
cp .env.example .env && $EDITOR .env     # SECRET_KEY_BASE, DATABASE_URL, los DOS salts
mix deps.get
mix ecto.create
mix compile --warnings-as-errors
mix precommit
```

Y para la UI: copiá el Commons (`../DESIGN.md`) tal cual + tu sección
`## Custom — <App>` (mecánica en `SPEC-design.md` §Propagación).

## Trampas (todas vistas en real)

- **`mix phx.new` aborta sobre un directorio no vacío y no tiene `--force`.** Por
  eso el scaffold va a un scratch y se copia con `rsync` — y por eso el repo de
  la app conserva su `README.md` (producto, en inglés) y su `.gitignore`.
- **El config de generadores no llega al DDL.** `generators: [binary_id: true]`
  sólo aplica a lo que producen `mix phx.gen.*`: una migración escrita a mano
  con `create table(:users)` igual emite `id bigint`, y los `references(...,
  type: :binary_id)` mueren con "uuid and bigint". Escribí siempre
  `create table(:x, primary_key: false) do add :id, :binary_id, primary_key: true …`
  y `timestamps(type: :utc_datetime_usec)`.
- **El switcher de tema del scaffold pisa el tema fijo.** Es un `<script>` inline
  que escribe `data-theme` desde `localStorage`: si queda, la app arranca en
  `light`/`dark` según el sistema. `bootstrap.sh` lo borra — verificalo con
  `grep -n 'phx:theme' lib/<app>_web/components/layouts/root.html.heex` → 0.
- **`~p"/favicon.svg"` no compila hasta que la ruta esté en `static_paths/0`**
  (`lib/<app>_web.ex`): el warning
  `no route path for <App>Web.Router matches "/favicon.svg"` parece un bug de
  rutas. Con `--warnings-as-errors` rompe el gate. El bootstrap ya lo agrega.
- **Los `{{…}}` del scaffold son HEEx legítimo**, no placeholders: el chequeo del
  bootstrap sólo mira los archivos del overlay (`:for={{id, msg} <- @streams.messages}`).
- **El seed de producción no existe en el scaffold.** `Release.seed/0` evalúa
  `priv/repo/seeds_prod.exs`: el overlay lo crea como stub y `seed/0` no falla si
  el archivo falta (una app sin primera cuenta tiene que poder arrancar).
- **En `:prod`, `assets.deploy` ANTES de `compile` muere** con
  `Can't resolve 'phoenix-colocated/<app>/colocated.css'` — los assets colocalados
  se generan al compilar. Orden correcto (el del Dockerfile):
  `mix deps.get --only prod` → `mix compile` → `mix assets.deploy` → `mix release`.
- **Postgres local sin TLS necesita `ECTO_SSL=false`.** El default del esqueleto
  es SSL activado (para bases gestionadas); contra un Postgres local el síntoma
  es engañoso: `failed to connect: ** (Postgrex.Error) ssl not available` y
  `failed to create db for <App>.Repo: "killed"` (el `"killed"` es la conexión
  TLS caída, no la base).
- **`Release.setup/0` corre en CADA deploy.** Todo lo que toque la base va
  envuelto en `Ecto.Migrator.with_repo/2` (durante `bin/<app> eval` el árbol de
  supervisión no está arrancado) y `storage_up/1` devuelve `{:error, :already_up}`
  (átomo) o el tuple legacy: hay que matchear ambos.
- **`Application.compile_env` + `runtime.exs` abortan el boot** con "has a
  different value set for key … during runtime". Un key que `runtime.exs` setea
  se lee con `Application.get_env/2` en `start/2`, nunca en un module attribute.
- **No metas dominio en el esqueleto.** Si tu app necesita
  `WEBHOOK_SECRET` u otra variable requerida, va en **su** `runtime.exs` — el
  esqueleto tiene que arrancar con las cinco requeridas de `SPEC-config.md` y
  nada más.

## Gates del bootstrap

| Gate | Comando | Esperado |
|---|---|---|
| Placeholders | (el propio bootstrap) | 0 placeholders en los archivos del overlay |
| Compila | `mix compile --warnings-as-errors` | sin warnings propios |
| Suite | `mix test` | 0 failures |
| Release | `MIX_ENV=prod mix release` + `ls _build/prod/rel/<app>/bin` | existe `<app>`, `migrate`, `server`, `setup` |
| Smoke | `bin/<app> eval "IO.puts(:ok)"` con las 5 requeridas | `:ok` |
| Setup real | `bin/<app> eval "<App>.Release.setup"` contra Postgres | crea la base, migra, seedea |

## Cuando el estándar cambia

- Cambio en el **Commons** (`DESIGN.md`) → se propaga a los `DESIGN.md` de las
  apps (copiando).
- Cambio en el **esqueleto** → se hace acá; las apps vivas **no** se
  re-sincronizan solas: se porta a mano lo que aplique (`SPEC-*.md` dice qué es
  contrato y qué es dominio).