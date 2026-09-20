# SPEC-docker.md — how an app is packaged and deployed

## Scope

The container contract of the family: multi-stage, Mix release, an entrypoint
that migrates before serving, an honest healthcheck and correctly wired ports.
The canonical artifacts are the ones in this repo's `skeleton/overlay/`
(`Dockerfile`, `docker/entrypoint.sh`, `config/*.exs`).

## Hard rules

1. **`mix deps.get --only prod` before `mix compile`** — the other way around, a
   stale `mix.lock` aborts with `lock outdated`.
2. **`mix release` with no name** (it uses the `:app` from `mix.exs`) and the
   `bin/migrate` / `bin/server` / `bin/setup` overlays present.
3. **The entrypoint migrates before serving**; if the migration fails the boot
   aborts and the deploy is rolled back.
4. **Non-root** (`useradd app`, `USER app`) and `HOME=/app`.
5. **No secrets in `ARG`/`ENV`** — they get baked into the layers. There is only
   **one** legitimate build arg: `DISABLE_FORCE_SSL`.
6. **`force_ssl` is compile-time**: it is turned off with a build arg, not at
   runtime. The **skeleton ships with HTTPS on** (`DISABLE_FORCE_SSL=""`); an app
   that lives behind a VPN may ship with plain HTTP (`"1"`), but that is a
   decision per app, never an inherited default.
7. **The healthcheck points at `/health`, never at `/`**: `/` answers 302 and a
   proxy that expects 200 reads the container as down.
8. **`PORT` (listen) == the port the proxy exposes**; `PHX_PORT` is only the one
   used in generated URLs. `EXPOSE` does not change the listen — that is why it
   is not used.
9. **Never Alpine** at runtime (distributed Erlang DNS breaks with musl).

## Build stage

| What | Detail |
|---|---|
| Pinned base image + runtime from the same Debian slug | avoids glibc drift between builder and runner |
| `build-essential git curl ca-certificates` | the tailwind/esbuild wrappers download their own binaries; Node only if `assets/package.json` requires it |
| `mix local.hex` / `local.rebar`, `MIX_ENV=prod` | |
| `DISABLE_FORCE_SSL` as `ARG` **and** `ENV` | so the deploy platform shows it in its UI |
| Only `mix.exs`/`mix.lock`/`config` before `deps.get` | keeps the dependency layer cached |
| OOM guard for small build containers | `ERL_AFLAGS="+S 1:1"` in a previous `deps.compile` |
| `COPY lib priv assets rel` → `mix compile` → `mix assets.deploy` | colocated assets are generated while compiling, so this order is mandatory |
| `mix release` | produces the release with its `rel/overlays` bins |

## Runtime stage

| What | Detail |
|---|---|
| `libstdc++6 openssl libncurses6 locales ca-certificates curl` | `curl` is for the proxy's healthcheck — the slim image does not ship it |
| UTF-8 locale (`LANG`/`LC_ALL`) | Elixir expects it at runtime |
| `COPY --from=build --chown=app:app /app/_build/prod/rel/<app> ./` | the release only |
| `COPY docker/entrypoint.sh` + `chmod +x` | |
| `ENV HOME=/app MIX_ENV=prod PHX_SERVER=true PORT=4000` | |
| `HEALTHCHECK … curl -fsS http://127.0.0.1:${PORT}/health` | start-period 60s, 5 retries |
| `ENTRYPOINT ["/app/entrypoint.sh"]` | |

### The `/health` endpoint

Public, unauthenticated, and **not touching the database**: it answers 200 as
soon as the listener is up. That is deliberate — the probe runs while the boot
seeds catalogs and partitions, and a probe that queries the database can time a
healthy container out.

**Rule for an app that already has a DB-touching `/health`** (`SELECT 1`, 503 on
failure): make it DB-free **before** giving it the canonical `HEALTHCHECK`, or
the container reports itself down during startup. If an app needs a DB-backed
readiness, it goes on **another** route (`/ready`), and that is the one the proxy
watches.

The portable layer ships the probe **with its test**
(`test/<app>_web/controllers/health_controller_test.exs`). That test runs
without a sandbox owner, so a `/health` that queries the database answers 503
there and the suite goes red: the regression the rule above is about, caught in
`mix precommit` instead of in production.

## Entrypoint

Canonical shape:

```sh
set -e
if [ "$SKIP_MIGRATIONS" = "1" ]; then echo "skipping"; else bin/<app> eval "<App>.Release.setup"; fi
exec bin/<app> start
```

- `Release.setup/0` is idempotent: create the database → migrate → seed. It is
  safe on every deploy.
- The first account: without `*_ADMIN_PASSWORD` the boot creates no user and the
  app sends whoever arrives first to the first-run screen — the window in which
  the first visitor takes over the instance. Close it with that variable or by
  deploying behind a network boundary.
- Domain variants (not the skeleton): a destructive reset flag that drops the
  schema on **every** boot while it is set.

## `.dockerignore`

Canonical: `_build`, `deps`, `node_modules`, generated assets, `.git`, `.env*`,
test/docs/tmp, editor junk.

A hard rule that cost an audit: **any upload directory must be ignored**. Being
in `.gitignore` is not enough — the build context is a different thing, and
`COPY priv priv` bakes local uploads into the image (one audit found 93 files /
72 MB of uploads in the build context).

## Ports

| Variable | What it is | Rule |
|---|---|---|
| `PORT` | the real listen port (runtime) | must match the deploy platform's **Ports Exposes** |
| `PHX_PORT` | port of generated URLs | the external one (443 with TLS, 4000/5000 behind a VPN) |
| `EXPOSE` | image metadata | does **not** change the listen: that is why the family's Dockerfiles do not carry it |

## Verification before pushing

```bash
# 1. the release exists and brings its bins
rm -rf _build/prod && MIX_ENV=prod mix deps.get --only prod
MIX_ENV=prod mix compile --warnings-as-errors   # colocated assets are generated here
MIX_ENV=prod mix assets.deploy
MIX_ENV=prod mix release
ls _build/prod/rel/<app>/bin/          # <app>, migrate, server, setup

# 2. it boots with fake config (fails if runtime.exs is broken)
#    (any value works for `eval`; to actually SERVE, SECRET_KEY_BASE needs >= 64
#     bytes — see the notes below)
DATABASE_URL=ecto://nope:nope@127.0.0.1:1/nope SECRET_KEY_BASE=test \
  PHX_HOST=localhost SESSION_SIGNING_SALT=a SESSION_ENCRYPTION_SALT=b \
  _build/prod/rel/<app>/bin/<app> eval "IO.puts(:ok)"     # -> :ok

# 3. the image builds and the healthcheck answers
docker build -t <app> . && docker run --rm -p 4000:4000 --env-file .env <app>
curl -fsS http://127.0.0.1:4000/health
```

> `mix assets.deploy` **before** `mix compile` in `:prod` fails with
> `Can't resolve 'phoenix-colocated/<app>/colocated.css'`: colocated assets are
> generated while compiling. The Dockerfile already respects that order.
>
> `SECRET_KEY_BASE` must be **at least 64 bytes** to actually serve: with a
> short one, every request that writes the session cookie dies with
> `cookie store expects conn.secret_key_base to be at least 64 bytes`
> (`Plug.Session.COOKIE`). The `eval` smoke above tolerates any value; a real
> boot does not. `mix phx.gen.secret` already emits a valid one.
>
> Against a local Postgres without TLS you must pass `ECTO_SSL=false`: the
> default is SSL on and the symptom is misleading (`ssl not available` +
> `failed to create db … "killed"`).

## Known gaps — audit checklist for a live app

What to look for when an app is audited against these specs. **Nothing is
ported into an app without deciding it**: this is the backlog, and the app is
updated when it is decided.

| Symptom | Why it matters |
|---|---|
| `/health` queries the database and returns 503 | make it DB-free **before** adding the canonical `HEALTHCHECK` |
| The image has no `HEALTHCHECK` | the runtime already installs `curl` for the proxy's check |
| `deps.compile` without the OOM guard | build containers of 512 MB–1 GB die with `exit 255` |
| `.dockerignore` missing the uploads directory | uploads get baked by `COPY priv priv` (one audit: 93 files / 72 MB) |
| `DISABLE_FORCE_SSL` left at `"1"` | HTTPS is a per-app deploy decision, not an inherited default |
| Session without `renew: true` and/or equal salts | absolute cookie lifetime, forgeable sessions — see `SPEC-config.md` |
| README with no production/container section | healthcheck, `PORT` vs Ports Exposes, first run, uploads volume — the section that README owes: `SPEC-readme.md` |

## Anti-patterns

- A healthcheck pointing at `/` (302 → the proxy reads it as down → 502).
- Migrating in a post-deploy step: the migration goes **before** traffic moves.
- `EXPOSE` as if it fixed the port.
- Compiling without the scheduler guard in 512 MB–1 GB containers (`exit 255`).
- Switching the runtime image to Alpine.
- An `ARG` holding a password.