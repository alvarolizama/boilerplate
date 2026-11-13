# {{App}}

<one sentence: what {{App}} is and who runs it>

Born from the family's portable layer: Phoenix with Postgres, a daisyUI theme
chosen at runtime by `THEME`, and a container that migrates before it serves.
The sections below are what the skeleton already brings — replace the ones that
stop being true as {{App}} grows, and delete this paragraph once they are all
{{App}}'s own.

## What it is

<the problem it solves, for whom, and the workflow that matters>

## Stack

| Piece | Version |
|---|---|
| Elixir / Erlang OTP | `.tool-versions` |
| Phoenix / LiveView | `mix.exs` |
| Postgres (Ecto, UUID primary keys) | `mix.exs` |
| UI | daisyUI, theme chosen with `THEME` (default `dim`; `DESIGN.md` §C2) |
| Runtime | Mix release in Docker (`Dockerfile`) |

## Local development

```bash
cp .env.example .env        # SECRET_KEY_BASE, DATABASE_URL and BOTH salts
direnv allow                # the .envrc loads .env — never export secrets by hand
mix deps.get
mix ecto.create
mix phx.server              # http://localhost:4000
```

`GET /health` answers 200 without touching the database: it is the container's
probe, not a readiness check.

## Configuration

Every variable with its comment and its safe default is in `.env.example`.
Two blocks matter:

- **Required in production** — `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`,
  `SESSION_SIGNING_SALT`, `SESSION_ENCRYPTION_SALT`: the boot raises without
  them, by design.
- **Optional commons** — `PORT`, `PHX_SCHEME`, `PHX_PORT`, `THEME`, `ECTO_SSL`,
  `SESSION_MAX_AGE_SECONDS` and the rest, documented in the same file.

The session, proxy and readiness knobs are **runtime** configuration — restart,
no rebuild:

| Concern | Variables | The rule |
|---|---|---|
| Session | `SESSION_SIGNING_SALT`, `SESSION_ENCRYPTION_SALT` (two, different), `SESSION_MAX_AGE_SECONDS`, `SESSION_COOKIE_SECURE` | the salts are mandatory in prod; both salts and the cookie flags obey the environment |
| Proxy / URLs | `PORT` (listen), `PHX_SCHEME` + `PHX_PORT` (generated URLs), `CHECK_ORIGINS` (extra origins behind a second scheme/host), `TRUST_PROXY` (sanitized `X-Forwarded-*` only behind an isolated proxy) | `PORT` is what the proxy points at; `PHX_SCHEME=https` enables the default `Secure` cookie in prod; the rest is how the app looks from outside |
| Readiness | — | `/health` is **liveness only** (no database); `/ready` checks `SELECT 1` with a bounded timeout and returns 503 when the database is unavailable. Point the proxy at `/ready`, keep Docker on `/health` |

The full contract — defaults, parsing, fail-closed rules — is `SPEC-config.md`;
the container contract (ports, entrypoint, healthcheck) is `SPEC-docker.md`.

<{{App}}'s own variables are declared in `config/runtime.exs` (read at runtime
with `System.get_env/1`) and documented in `.env.example` next to the others.>

## The UI standard

`DESIGN.md` is the family's Commons, copied as-is, plus `## Custom — {{App}}`
with what is exclusive to {{App}}. The Commons is edited in the family's
boilerplate repo and propagates by copying — never edited here.

## Production

```bash
docker build -t {{app}} .
docker run --rm -p 4000:4000 --env-file .env {{app}}
```

| Piece | What to respect |
|---|---|
| Ports | `PORT` (the listen) must match the platform's **Ports Exposes**; `PHX_PORT` is only the port used in generated URLs |
| Healthcheck | the probe is `GET /health`, never `/` — and it must stay database-free |
| Migrations | the entrypoint runs `{{App}}.Release.setup/0` (create → migrate → seed) on every deploy, before serving |
| First account | Default: `/onboarding`, closed after the first person and serialized by an advisory lock. Optional: set `{{APP}}_ADMIN_PASSWORD` (optionally `{{APP}}_ADMIN_EMAIL`) on the first deploy; the opt-in seed is idempotent under the setup advisory lock. Never use an open sign-up or committed password |
| HTTPS | `force_ssl` is compile-time: behind a VPN build with `DISABLE_FORCE_SSL=1` and run with `PHX_SCHEME=http` |
| Uploads | <when {{App}} stores uploads: a persistent volume at the upload directory, and that directory in `.dockerignore`> |

## Tests and gates

```bash
mix precommit    # format, compile --warnings-as-errors, tests
```

## Documentation

<where the rest lives — product docs, API, MCP — or delete this section>
