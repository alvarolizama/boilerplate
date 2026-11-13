# VERSIONS.md — the family's pinned versions

What gets pinned when an app is born. It changes **here**, and where it applies
it is ported into live apps.

## Toolchain

| Piece | Version | Where it is pinned |
|---|---|---|
| Elixir | **1.20.1-otp-29** | `.tool-versions` (asdf/mise) — carried by `skeleton/overlay/` and copied into the app by the bootstrap |
| Erlang/OTP | **29.0.2** | `.tool-versions` (same file, same origin) |
| `mix.exs` `elixir:` | `~> 1.17` | what `phx_new` 1.8.16 generates — the declared range, not the real pin |
| OTP setup tools | Hex **2.7.0** / rebar3 **3.28.0** (OTP 29 artifact + SHA-512) | `skeleton/overlay/Dockerfile` |
| Build image | `hexpm/elixir:1.20.2-erlang-29.0.3-debian-bookworm-20260713-slim` | `skeleton/overlay/Dockerfile` (ARG `ELIXIR_IMAGE`) |
| Runtime image | `debian:bookworm-20260713-slim` | `skeleton/overlay/Dockerfile` (ARG `DEBIAN_RUNTIME`) |
| Node (only with its own JS) | 22.x | the optional block of the Dockerfile |

> **Known drift**: the local toolchain sits at `1.20.1 / OTP 29.0.2` while the
> image is `1.20.2 / OTP 29.0.3`. The patches are compatible, but the image pin
> is chosen against the
> [real tag list](https://hub.docker.com/r/hexpm/elixir/tags) and the runtime's
> Debian slug **must** match the builder's (glibc).

## Base dependencies (what `phx_new` 1.8.16 + the bootstrap put in every app)

Verified against a fresh `mix phx.new 1.8.16` generation (2026-11): these are the
direct deps of the born `mix.exs`. Keep this table in sync by regenerating an
app and diffing — not by memory.

| Dep | Version | For what |
|---|---|---|
| `phoenix` | `~> 1.8.16` | framework |
| `phoenix_live_view` | `~> 1.2.0` | reactive UI |
| `phoenix_html` | `~> 4.1` | HEEx |
| `phoenix_ecto` / `ecto_sql` / `postgrex` | `~> 4.5` / `~> 3.13` / `>= 0.0.0` | data |
| `bandit` | `~> 1.5` | HTTP server |
| `swoosh` + `req` | `~> 1.16` / `~> 0.5` | mail and HTTP client (`Swoosh.ApiClient.Req`) |
| `jason` / `gettext` | `~> 1.2` / `~> 1.0` | JSON and i18n |
| `dns_cluster` | `~> 0.2.0` | clustering (optional at runtime) |
| `telemetry_metrics` / `telemetry_poller` | `~> 1.0` | metrics |
| `phoenix_live_dashboard` | `~> 0.8.3` | dev/prod panel |
| `tailwind` / `esbuild` | `~> 0.5` / `~> 0.10` | assets (they download their binaries) |
| `daisyui` | git `tag: "v5.5.20"` (sparse `packages/bundle`) | UI kit, compiled from `assets/css/app.css` |
| `heroicons` | git `tag: "v2.2.0"` (sparse `optimized`) | icons |

> Git deps are resolved by `ref`/`tag`/`branch` — **exactly one**, and in the
> same option order as the lock, or prod aborts with `lock outdated` even when
> `mix.exs` and `mix.lock` "match". Both base git deps above use `tag:` — keep
> it that way.

## Opt-in dependencies (installed by an explicit step, not at birth)

The bootstrap does **not** add these: an app that has not taken the
capability must not carry the dep. Add them when the capability lands, with a
test/exercise in the same change.

| Dep | Version | Added when |
|---|---|---|
| `bcrypt_elixir` | `~> 3.0` | the app takes auth **Mode 1** (username + password) — the first `users` migration (`SPEC-auth.md` §Mode 1) |
| `mix_audit` | latest | the app adopts the dependency-audit gate |
| `sobelow` | latest | the app adopts the security-audit gate |

## App-specific (they do not go into the skeleton)

Typical extra deps, by capability — add them only if the app has that
capability:

| Capability | Deps |
|---|---|
| Background jobs / queues | `oban` |
| Streaming HTTP (a proxy, SSE) | `finch` |
| Time zones | `tz` |
| Markdown | `mdex` |
| Vector search / embeddings | `pgvector` |
| Scheduled jobs (cron) | `quantum` |

## Database

| Requirement | Detail |
|---|---|
| PostgreSQL | **14+** |
| Extensions | `pgvector` only if the app uses it |
| Partitions | only if the app partitions tables: `CREATE INDEX` **cannot** be `CONCURRENTLY` on a partitioned table (Postgres) — migrate inside a maintenance window |
| PKs | `binary_id` (uuid) across the family |
| Timestamps | `utc_datetime_usec` — written **explicitly in every `create table`**: `generators: [binary_id: true]` only applies to what `mix phx.gen.*` generates |

## How a new version is verified

```bash
cd <app>
mix deps.get && mix deps.unlock --unused
mix compile --warnings-as-errors
mix precommit
rm -rf _build/prod && MIX_ENV=prod mix deps.get --only prod && MIX_ENV=prod mix release
```

If the release fails while `mix precommit` passes, the problem is in `:prod`
(the config provider) — see `SPEC-docker.md` §Verification before pushing.
