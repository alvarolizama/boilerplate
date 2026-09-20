# VERSIONS.md — versiones pinneadas de la familia

Lo que se fija al nacer una app. Se cambia **aquí** y, si aplica, se porta a las
apps vivas.

## Toolchain

| Pieza | Versión | Dónde se fija |
|---|---|---|
| Elixir | **1.20.1-otp-29** | `.tool-versions` (asdf/mise) |
| Erlang/OTP | **29.0.2** | `.tool-versions` |
| `mix.exs` `elixir:` | `~> 1.15` | el rango declarado, no el pin real |
| Imagen de build | `hexpm/elixir:1.20.2-erlang-29.0.3-debian-bookworm-20260713-slim` | `skeleton/overlay/Dockerfile` (ARG `ELIXIR_IMAGE`) |
| Imagen de runtime | `debian:bookworm-20260713-slim` | `skeleton/overlay/Dockerfile` (ARG `DEBIAN_RUNTIME`) |
| Node (sólo si hay JS propios) | 22.x | bloque opcional del Dockerfile |

> **Drift conocido**: el toolchain local está en `1.20.1 / OTP 29.0.2` y la
> imagen en `1.20.2 / OTP 29.0.3`. Los parches son compatibles, pero el pin de la
> imagen se elige contra la
> [lista real de tags](https://hub.docker.com/r/hexpm/elixir/tags) y el slug
> Debian del runtime **debe** coincidir con el del builder (glibc).

## Dependencias base (lo que toda app de la familia trae)

| Dep | Versión | Para qué |
|---|---|---|
| `phoenix` | `~> 1.8.8` | framework |
| `phoenix_live_view` | `~> 1.2.0` | UI reactiva |
| `phoenix_html` | `~> 4.1` | HEEx |
| `ecto_sql` / `postgrex` / `phoenix_ecto` | `~> 3.13` / `>= 0.0.0` / `~> 4.5` | datos |
| `bandit` | `~> 1.5` | servidor HTTP |
| `swoosh` + `req` | `~> 1.16` / `~> 0.5` | correo y HTTP cliente (`Swoosh.ApiClient.Req`) |
| `jason` / `gettext` | `~> 1.2` / `~> 1.0` | JSON e i18n |
| `dns_cluster` | `~> 0.2.0` | clustering (opcional en runtime) |
| `telemetry_metrics` / `telemetry_poller` | `~> 1.0` | métricas |
| `bcrypt_elixir` | `~> 3.0` | hashing de contraseñas |
| `tailwind` / `esbuild` | `~> 0.3` / `~> 0.10` | assets (bajan sus binarios) |
| `phoenix_live_dashboard` | `~> 0.8.3` | panel de dev/prod |
| `mix_audit` / `sobelow` | dev/test | auditoría (Dran usa `sobelow`) |
| `heroicons` | git pin | iconos (`tag: v2.2.0` en TokenGate, `ref:` en Dran) |

> Los deps de git se resuelven por `ref`/`tag`/`branch` — **exactamente uno** y en
> el mismo orden de opciones que el lock, o prod aborta con `lock outdated`
> aunque `mix.exs` y `mix.lock` "coincidan".

## Propias de cada app (no van al esqueleto)

| App | Deps extra | Por qué no es base |
|---|---|---|
| TokenGate | `oban ~> 2.19`, `finch ~> 0.19`, `tz ~> 0.28` | jobs, streaming del proxy, zonas horarias |
| Dran | `mdex ~> 0.13.1`, `pgvector ~> 0.3`, `quantum ~> 3.5` | markdown, embeddings, crons |

## Base de datos

| Requisito | Detalle |
|---|---|
| PostgreSQL | **14+** |
| Extensiones | `pgvector` sólo si la app la usa (Dran); TokenGate no la necesita |
| Particiones | sólo si la app particiona tablas: `CREATE INDEX` **no** puede ser `CONCURRENTLY` en una tabla particionada (Postgres) — migrar en ventana de mantenimiento |
| PKs | `binary_id` (uuid) en toda la familia |
| Timestamps | `utc_datetime_usec` — se escriben **explícitos en cada `create table`**: el `generators: [binary_id: true]` sólo aplica a lo que generan `mix phx.gen.*` |

## Cómo se verifica una versión nueva

```bash
cd <app>
mix deps.get && mix deps.unlock --unused
mix compile --warnings-as-errors
mix precommit
rm -rf _build/prod && MIX_ENV=prod mix deps.get --only prod && MIX_ENV=prod mix release
```

Si el release falla y `mix precommit` pasa, el problema es de `:prod`
(config provider) — ver `SPEC-docker.md` §Verificación.