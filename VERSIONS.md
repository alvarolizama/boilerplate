# VERSIONS.md — the family's pinned versions

What gets pinned when an app is born. It changes **here**, and where it applies
it is ported into live apps.

## Toolchain

| Piece | Version | Where it is pinned |
|---|---|---|
| Elixir | **1.20.1-otp-29** | `.tool-versions` (asdf/mise) |
| Erlang/OTP | **29.0.2** | `.tool-versions` |
| `mix.exs` `elixir:` | `~> 1.15` | the declared range, not the real pin |
| Build image | `hexpm/elixir:1.20.2-erlang-29.0.3-debian-bookworm-20260713-slim` | `skeleton/overlay/Dockerfile` (ARG `ELIXIR_IMAGE`) |
| Runtime image | `debian:bookworm-20260713-slim` | `skeleton/overlay/Dockerfile` (ARG `DEBIAN_RUNTIME`) |
| Node (only with its own JS) | 22.x | the optional block of the Dockerfile |

> **Known drift**: the local toolchain sits at `1.20.1 / OTP 29.0.2` while the
> image is `1.20.2 / OTP 29.0.3`. The patches are compatible, but the image pin
> is chosen against the
> [real tag list](https://hub.docker.com/r/hexpm/elixir/tags) and the runtime's
> Debian slug **must** match the builder's (glibc).

## Base dependencies (what every app of the family carries)

| Dep | Version | For what |
|---|---|---|
| `phoenix` | `~> 1.8.8` | framework |
| `phoenix_live_view` | `~> 1.2.0` | reactive UI |
| `phoenix_html` | `~> 4.1` | HEEx |
| `ecto_sql` / `postgrex` / `phoenix_ecto` | `~> 3.13` / `>= 0.0.0` / `~> 4.5` | data |
| `bandit` | `~> 1.5` | HTTP server |
| `swoosh` + `req` | `~> 1.16` / `~> 0.5` | mail and HTTP client (`Swoosh.ApiClient.Req`) |
| `jason` / `gettext` | `~> 1.2` / `~> 1.0` | JSON and i18n |
| `dns_cluster` | `~> 0.2.0` | clustering (optional at runtime) |
| `telemetry_metrics` / `telemetry_poller` | `~> 1.0` | metrics |
| `bcrypt_elixir` | `~> 3.0` | password hashing |
| `tailwind` / `esbuild` | `~> 0.3` / `~> 0.10` | assets (they download their binaries) |
| `phoenix_live_dashboard` | `~> 0.8.3` | dev/prod panel |
| `mix_audit` / `sobelow` | dev/test | auditing (`sobelow` is opt-in per app) |
| `heroicons` | git pin | icons (`tag:` or `ref:` — keep it consistent with the lock) |

> Git deps are resolved by `ref`/`tag`/`branch` — **exactly one**, and in the
> same option order as the lock, or prod aborts with `lock outdated` even when
> `mix.exs` and `mix.lock` "match".

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