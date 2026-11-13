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
   proxy that expects 200 reads the container as down. Readiness (a DB check) is
   a **different** route, `/ready`, and it is the only one a load balancer may
   watch.
8. **`PORT` (listen) == the port the proxy exposes**; `PHX_PORT` is only the one
   used in generated URLs. `EXPOSE` does not change the listen — that is why it
   is not used.
9. **Never Alpine** at runtime (distributed Erlang DNS breaks with musl).
10. **The entrypoint is `set -eu` and bounded**: a failed or timed-out setup
    aborts the boot (`SETUP_TIMEOUT_SECONDS`, default 120) instead of leaving a
    half-configured container serving. It runs from `/app` (`cd /app`), never
    from whatever directory the platform happened to choose.
11. **Hex and rebar3 are pinned** (`mix local.hex <version>`, rebar3 by artifact
    URL + SHA-512) and every `apt-get install` uses `--no-install-recommends`:
    a rebuild must not silently pull a newer toolchain or a larger surface.
12. **`HOME` is writable** (`chown app:app /app`): distributed Erlang writes
    `/app/.erlang.cookie` when `DNS_CLUSTER_QUERY` is set, and a root-owned
    `/app` makes clustering fail with `eacces` while the container still serves.
13. **Session cookie options are runtime** (`config/runtime.exs` → the endpoint's
    `session_options/0` reader), and in prod both salts are required and distinct.
    Compile-time session configuration is inert in an image.

## Build stage

| What | Detail |
|---|---|
| Pinned base image + runtime from the same Debian slug | avoids glibc drift between builder and runner |
| `build-essential git curl ca-certificates` | the tailwind/esbuild wrappers download their own binaries; Node only if `assets/package.json` requires it. Always `--no-install-recommends` |
| `mix local.hex <version>` / rebar3 by URL + `--sha512`, `MIX_ENV=prod` | pinned: `mix local.rebar` takes no version, so the artifact and its checksum from `repo.hex.pm/installs/rebar.csv` are pinned instead |
| `DISABLE_FORCE_SSL` as `ARG` **and** `ENV` | so the deploy platform shows it in its UI |
| Only `mix.exs`/`mix.lock`/`config` before `deps.get` | keeps the dependency layer cached |
| OOM guard for small build containers | `ERL_AFLAGS="+S 1:1"` in a previous `deps.compile` |
| `COPY lib priv assets rel` → `mix compile` → `mix assets.deploy` | colocated assets are generated while compiling, so this order is mandatory |
| `mix release` | produces the release with its `rel/overlays` bins |

## Runtime stage

| What | Detail |
|---|---|
| `libstdc++6 openssl libncurses6 locales ca-certificates curl` | `--no-install-recommends`; `curl` is for the proxy's healthcheck — the slim image does not ship it |
| UTF-8 locale (`LANG`/`LC_ALL`) | Elixir expects it at runtime |
| `COPY --from=build --chown=app:app /app/_build/prod/rel/<app> ./` | the release only |
| `COPY docker/entrypoint.sh` + `chmod +x` | |
| `RUN chown app:app /app` | `WORKDIR` created `/app` as root; Erlang's cookie (clustering) and crash dumps need it writable |
| `ENV HOME=/app MIX_ENV=prod PHX_SERVER=true PORT=4000` | |
| `HEALTHCHECK … curl -fsS http://127.0.0.1:${PORT}/health` | liveness-only exception in `Plug.SSL` is **path-based** (`/health`), never Host-based; start-period 60s, 5 retries |
| `ENTRYPOINT ["/app/entrypoint.sh"]` | |

### The probes: `/health` and `/ready`

**`/health` is liveness.** Public, unauthenticated, and **not touching the
database**: it answers 200 as soon as the listener is up. That is deliberate —
the probe runs while the boot seeds catalogs and partitions, and a probe that
queries the database can time a healthy container out. It belongs on the
container `HEALTHCHECK`.

**`/ready` is readiness.** `SELECT 1` against every repo, with a short bounded
timeout (1 s reaches the pool checkout *and* the statement), `200` when it
answers and `503` (`{"status":"unavailable"}`) when it does not. The body never
carries the reason — a probe is public; the reason goes to the log. It is a
**different route** on purpose: a proxy or load balancer that must stop sending
traffic to a container whose database vanished watches `/ready`, while the image
healthcheck keeps watching `/health` so a slow boot does not restart a healthy
app.

**Rule for an app that already has a DB-touching `/health`** (`SELECT 1`, 503 on
failure): make it DB-free **before** giving it the canonical `HEALTHCHECK`, or
the container reports itself down during startup. Move the DB check to `/ready`.

The portable layer ships both probes **with their test**
(`test/<app>_web/controllers/health_controller_test.exs`). That test runs
without a sandbox owner, so a `/health` that queries the database raises
`DBConnection.OwnershipError` instead of returning its contract's 200, and the
suite goes red — the regression the rule above is about, caught in
`mix precommit` instead of in production. The same missing owner is what makes
the `/ready` test honest: it asserts the 503 branch and that neither probe sets
a cookie.

## Proxy trust

`TRUST_PROXY=1` (runtime, `config/runtime.exs`) makes the endpoint apply
`Plug.RewriteOn` before everything else: the client IP, the scheme, the host and
the port come from `X-Forwarded-For` / `-Proto` / `-Host` / `-Port`.

- **Only** enable it when the container is unreachable except through the proxy.
- The proxy must **strip** those headers from incoming requests; otherwise any
  client claims whatever origin, IP or host it likes (spoofed `check_origin`,
  spoofed rate-limit buckets, spoofed logs).
- With TLS terminated at the proxy, `PHX_SCHEME=https` and `PHX_PORT=443`
  describe the **external** URL; `README.md` of the app states them.
- `force_ssl` keeps its own compile-time `rewrite_on: [:x_forwarded_proto]`
  (Plug.SSL runs before the endpoint's plugs); that one only feeds the redirect
  decision and does not trust the peer.

## Entrypoint

Canonical shape:

```sh
set -eu
cd /app
if [ "${SKIP_MIGRATIONS:-0}" = "1" ]; then echo "skipping"
else timeout "${SETUP_TIMEOUT_SECONDS:-120}" bin/<app> eval "<App>.Release.setup" || exit 1; fi
exec bin/<app> start
```

- `Release.setup/0` is idempotent: create the database → migrate → seed. It is
  safe on every deploy.
- **Concurrency**: `setup/0` takes a PostgreSQL advisory lock before migrating
  and seeding and holds it for both, so replicas that boot together serialize
  instead of racing on a migration or on a unique constraint inside the seed.
  The lock lives on a checked-out connection: if the node dies, Postgres
  releases it. Database **creation** stays outside the lock (the lock needs a
  database that may not exist yet) and relies on `storage_up/1` being
  idempotent.
- **`SKIP_DB_CREATE=1`**: the database is preprovisioned, or the role has no
  `CREATEDB` privilege (the usual managed provider). Setup then only migrates
  and seeds. This is the recommended mode for multi-replica deploys: create the
  database once, out of band.
- **`SETUP_TIMEOUT_SECONDS`** (default 120) bounds create+migrate+seed; on
  timeout the container fails instead of hanging until the platform kills it.
- The first account: without `*_ADMIN_PASSWORD` the boot creates no user and the
  app sends whoever arrives first to the first-run screen — the window in which
  the first visitor takes over the instance. Close it with that variable or by
  deploying behind a network boundary. A seed that bootstraps an account must be
  idempotent (`get_by` + insert, or `insert` with `on_conflict`), because it
  runs on every deploy.
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
#    SECRET_KEY_BASE must be >= 64 bytes: runtime.exs refuses a shorter one at
#    boot time (release start AND `eval`), because Plug.Session.COOKIE cannot
#    write a cookie with it.
DATABASE_URL=ecto://nope:nope@127.0.0.1:1/nope \
  SECRET_KEY_BASE=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa \
  PHX_HOST=localhost SESSION_SIGNING_SALT=a SESSION_ENCRYPTION_SALT=b \
  _build/prod/rel/<app>/bin/<app> eval "IO.puts(:ok)"     # -> :ok

# 2b. the session is runtime, not compile-time: the endpoint BEAM must NOT
#     carry the dev fallback salts (they live in runtime.exs, read at boot)
! strings _build/prod/rel/<app>/lib/<app>-*/ebin/Elixir.<App>Web.Endpoint.beam \
  | grep -q -- "-dev-signing-salt"

# 3. the image builds and the healthcheck answers
docker build -t <app> . && docker run --rm -p 4000:4000 --env-file .env <app>
curl -fsS http://127.0.0.1:4000/health
curl -fsS http://127.0.0.1:4000/ready      # 503 until the DB answers; 200 after
```

> `mix assets.deploy` **before** `mix compile` in `:prod` fails with
> `Can't resolve 'phoenix-colocated/<app>/colocated.css'`: colocated assets are
> generated while compiling. The Dockerfile already respects that order.
>
> `SECRET_KEY_BASE` must be **at least 64 bytes**: with a short one, every
> request that writes the session cookie dies with
> `cookie store expects conn.secret_key_base to be at least 64 bytes`
> (`Plug.Session.COOKIE`), while `/health` keeps reporting the container as up.
> `config/runtime.exs` therefore refuses a shorter one **at boot** (release start
> and `eval`), so the smoke test above needs a valid-length value.
> `mix phx.gen.secret` already emits one.
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
| `/health` queries the database and returns 503 | make it DB-free **before** adding the canonical `HEALTHCHECK`; move the check to `/ready` |
| The image has no `HEALTHCHECK` | the runtime already installs `curl` for the proxy's check |
| Session options read with `System.get_env/2` in a module attribute | frozen into the BEAM at build time: salts and `secure` stop obeying the environment — move them to `config/runtime.exs` (see hard rule 13) |
| `setup/0` without a lock, or a seed with read-then-insert only | replicas booting together race a migration or a unique constraint and the new container dies |
| `HOME=/app` with `/app` owned by root | distributed Erlang cannot write `.erlang.cookie`: clustering silently stays single-node |
| `mix local.hex` / `local.rebar` unpinned | a rebuild pulls whatever Hex/CDN serves that day |
| `deps.compile` without the OOM guard | build containers of 512 MB–1 GB die with `exit 255` |
| `.dockerignore` missing the uploads directory | uploads get baked by `COPY priv priv` (one audit: 93 files / 72 MB) |
| `DISABLE_FORCE_SSL` left at `"1"` | HTTPS is a per-app deploy decision, not an inherited default |
| Session without `renew: true` and/or equal salts | absolute cookie lifetime, or signing/encryption sharing one derivation domain — see `SPEC-config.md` |
| README with no production/container section | healthcheck, `PORT` vs Ports Exposes, first run, uploads volume — the section that README owes: `SPEC-readme.md` |

## Anti-patterns

- A healthcheck pointing at `/` (302 → the proxy reads it as down → 502).
- A healthcheck pointing at `/ready` (a DB blip restarts a healthy app).
- Migrating in a post-deploy step: the migration goes **before** traffic moves.
- `EXPOSE` as if it fixed the port.
- Compiling without the scheduler guard in 512 MB–1 GB containers (`exit 255`).
- Switching the runtime image to Alpine.
- An `ARG` holding a password.
