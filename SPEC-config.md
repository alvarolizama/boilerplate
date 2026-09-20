# SPEC-config.md — app configuration (env vars + settings)

## Scope

How an app of the family is configured: what the boot **requires**, what is
optional with which default, where each variable is read, and what lives in the
**database** instead of the environment. The canonical files are
`config/runtime.exs` (env vars, boot fail-closed) and
`lib/<app>_web/endpoint.ex` (session cookie).

## Hard rules

1. **The boot fails closed.** If a required variable is missing, `runtime.exs`
   **raises** — never a silent default, never a fallback password.
2. **The required ones are enforced in `runtime.exs`, under
   `config_env() == :prod`**, and the endpoint starts behind the gate
   `if config_env() == :prod or System.get_env("PHX_SERVER")` (so `mix test` and
   `mix precommit` never try to bind the port).
3. **No secret in the build**: secrets enter through the environment at runtime,
   never as `ARG`/`ENV` in the Dockerfile (`SPEC-docker.md` §Hard rules).
4. **The session salts are two and they are different**: `signing_salt` and
   `encryption_salt` never share a value.
5. **Whatever is edited from the UI lives in the database**, not in the
   environment (§Settings in the database).

## Required in production (the boot dies without them)

| Var | What it is | Where it is enforced |
|---|---|---|
| `DATABASE_URL` | Postgres connection | `config/runtime.exs`, `config_env() == :prod` |
| `SECRET_KEY_BASE` | signs/encrypts cookies and secrets | same block |
| `PHX_HOST` | public host, **without** scheme or port | same block |
| `SESSION_SIGNING_SALT` | session signing salt | same block |
| `SESSION_ENCRYPTION_SALT` | session encryption salt | same block |

A variable like `WEBHOOK_SECRET` is required **by the app that has webhooks**,
not by the standard: it is domain, it lives in that app's `runtime.exs`, and it
is never ported into the skeleton.

## Optional commons (default and where it is read)

| Var | Default | What it adjusts |
|---|---|---|
| `PORT` | `4000` | listen port (the proxy must point here) |
| `PHX_SCHEME` | `https` | scheme of generated URLs (`http` behind a VPN) |
| `PHX_PORT` | `443` | external port of generated URLs |
| `POOL_SIZE` | `10` | connection pool |
| `ECTO_SSL` / `ECTO_SSL_VERIFY` | SSL on, verification off | database TLS |
| `ECTO_IPV6` | off | IPv6 socket to the database |
| `CHECK_ORIGINS` | unset | allowed origins for CSRF/WS (dual HTTPS+HTTP) |
| `SESSION_MAX_AGE_SECONDS` | `31536000` | session cookie lifetime |
| `SESSION_COOKIE_SECURE` | unset | forces/clears the `Secure` flag |
| `DNS_CLUSTER_QUERY` | unset | distributed Erlang clustering |
| `DISABLE_FORCE_SSL` | build arg | turns `force_ssl` off (**compile-time**, see `SPEC-docker.md`) |
| `SKIP_MIGRATIONS` | unset | the entrypoint skips setup |
| `GOOGLE_OAUTH_CLIENT_ID` / `_SECRET` / `_ALLOWED_DOMAINS` / `_REDIRECT_URI` | unset | sign-in with Google |

### Database TLS: the shape of the option

`ECTO_SSL` / `ECTO_SSL_VERIFY` land in the Repo options as **`ssl: [ … ]`**, a
keyword list:

```elixir
[ssl: [verify: :verify_none]]                                        # default: encrypted, not verified
[ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]]    # ECTO_SSL_VERIFY=true
```

Postgrex **deprecated the old pair** `ssl: true, ssl_opts: [ … ]`: it still
works, but it logs `":ssl_opts is deprecated, pass opts to :ssl instead"` once
per pool connection, so the deprecated shape fills the boot log of every deploy.

Ready-to-copy template: **`skeleton/overlay/.env.example`** — every core
variable with its comment and its safe default, grouped in core / session /
optional.

## The app's own variables

The standard does not fix them: each app declares its own in its `runtime.exs`
with an explicit default, and reads them at runtime (`System.get_env/1`) —
never with `Application.compile_env/3`, because a key set in `runtime.exs` and
read at compile time aborts the boot with *"has a different value set for key …
during runtime"*.

Typical patterns:

| Pattern | Var (example) | What to watch out for |
|---|---|---|
| Upload directory | `UPLOADS_DIR` | requires a persistent volume mounted at that path |
| Inference endpoint (OpenAI-compatible) | `*_INFERENCE_API_URL` / `_API_KEY` | used by embeddings, chat and background workers |
| Destructive reset flag | `*_RESET` | **destructive**: drops the schema on every boot while it is set — keep it out of production |
| First-admin bootstrap | `*_ADMIN_PASSWORD` / `_ADMIN_EMAIL` | opt-in only: without it the boot creates nobody and the first account comes from the first-run screen |
| Proxy/gateway tuning | circuit breaker, receive timeout, slow-routing thresholds | only meaningful for an app that proxies traffic |

## Session and cookies (the canonical block)

Reference: `lib/<app>_web/endpoint.ex`.

| Piece | Canonical value | Note |
|---|---|---|
| `key` | `_<app>_key` | one cookie per app |
| `signing_salt` / `encryption_salt` | from env, **two different ones** | in prod they are required; dev fallbacks are distinct values |
| `same_site` / `http_only` | `Lax` / `true` | |
| `renew: true` | sliding: the cookie is re-issued on every authenticated request | without it the lifetime is absolute |
| `max_age` | `SESSION_MAX_AGE_SECONDS` (1 year) | |
| `secure` | per `SESSION_COOKIE_SECURE` | unset = Plug decides per request |
| socket `connect_info` | `session` + `peer_data: true` + `user_agent: true` | on **both** the websocket and the longpoll entry |

**Symptoms to check in a live app** (diagnosis, do not port blind): the same
value in `signing_salt` and `encryption_salt`; no `renew: true` (an absolute
cookie); a `.env.example` that documents a session lifetime the endpoint does
not implement.

## Settings in the database (not env)

Whatever is edited from the UI does **not** go into the environment. Two
patterns:

| Pattern | Shape |
|---|---|
| Singleton with columns | a one-row settings table (id 1) with a column per knob — for a small, fixed set of global values |
| Key/value + ETS cache | `get/1` caches in ETS and falls back to the `settings` table; `put/2` writes with `on_conflict` — for settings that grow |

Rule: if the value is a secret edited from the UI (an API token, a bot token),
it is stored **encrypted** in the database (a dedicated `SecretBox`-style
module), never in plaintext and never in the environment.

## Install checklist

1. `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`, both salts: present and
   different from each other.
2. `PORT` == the port the proxy exposes; `PHX_SCHEME`/`PHX_PORT` == how the app
   looks from outside.
3. Database with SSL: leave `ECTO_SSL_VERIFY` off unless you have a valid CA.
4. If there is plain HTTP (VPN/LAN): build with `DISABLE_FORCE_SSL=1` **and**
   `PHX_SCHEME=http` at runtime.
5. If the app is reachable from two origins: `CHECK_ORIGINS` with the full list
   (`scheme://host:port`, no paths).
6. If the app stores uploads: a persistent volume mounted at its upload
   directory.

## Anti-patterns

- A silent default for a required variable
  (`System.get_env("SECRET_KEY_BASE", "something")`).
- The same value for `signing_salt` and `encryption_salt`.
- `secure: true` hardcoded in the cookie: over HTTP the browser drops it and
  login returns 403 with no controller log.
- Asking the boot for a domain variable (the `WEBHOOK_SECRET` case): a new app
  inheriting that does not start.
- Reading a runtime-set variable with `Application.compile_env/3`.
