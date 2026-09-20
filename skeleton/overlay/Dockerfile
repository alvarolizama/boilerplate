# syntax=docker/dockerfile:1
#
# Esqueleto de la familia — ver SPEC-docker.md (contrato) y
# tokengate/Dockerfile (referencia canónica, read-only).
#
# Los placeholders {{app}} / {{App}} / {{APP}} los reemplaza
# skeleton/bootstrap.sh.

# ---------------------------------------------------------------------------
# Build stage — imagen Elixir/OTP prebuilt (sin mise, sin kerl, sin compilar
# Erlang desde fuentes)
# ---------------------------------------------------------------------------
# Pinneá la imagen al toolchain local (VERSIONS.md) y mantené el slug Debian
# del runtime alineado con el del builder para no arrastrar drift de glibc.
ARG ELIXIR_IMAGE=hexpm/elixir:1.20.2-erlang-29.0.3-debian-bookworm-20260713-slim
ARG DEBIAN_RUNTIME=debian:bookworm-20260713-slim

FROM ${ELIXIR_IMAGE} AS build

# build-essential para NIFs, git para deps de GitHub, curl/ca-certificates para
# descargas. Los wrappers de tailwind y esbuild bajan sus propios binarios: NO
# hace falta Node. Si tu app trae JS propios (assets/package.json), descomentá
# el bloque de Node más abajo.
RUN apt-get update -y \
  && apt-get install -y build-essential git curl ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

RUN mix local.hex --force && mix local.rebar --force

ENV MIX_ENV=prod

# force_ssl es compile-time (config/prod.exs). Default del esqueleto: HTTPS
# activado. Para desplegar por HTTP plano (VPN/LAN sin terminador TLS),
# construí con  --build-arg DISABLE_FORCE_SSL=1  y poné PHX_SCHEME=http.
# (TokenGate, que vive detrás de VPN, trae "1" por default; acá el default es
# seguro para una app pública.)
ARG DISABLE_FORCE_SSL=""
ENV DISABLE_FORCE_SSL=${DISABLE_FORCE_SSL}

# --- Dependencias (capa cacheada hasta que cambie mix.exs/mix.lock) --------
# `mix deps.get` SIEMPRE antes de `mix compile`: con el lock viejo, prod
# aborta con "lock outdated" (dev lo tolera).
COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod

# Guard de OOM: los contenedores de build de Coolify suelen tener 512 MB–1 GB y
# la VM de Erlang arranca un scheduler por core. +S 1:1 lo limita a uno.
RUN ERL_AFLAGS="+S 1:1" mix deps.compile

# --- JS propios (opcional) --------------------------------------------------
# Solo si assets/package.json existe (p. ej. un editor TipTap/three.js):
# RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
#   && apt-get install -y nodejs && apt-get clean && rm -rf /var/lib/apt/lists/*
# RUN cd assets && npm ci

# --- Aplicación + assets ----------------------------------------------------
COPY lib lib
COPY priv priv
COPY assets assets
COPY rel rel

RUN mix compile
RUN mix assets.deploy

# --- Release ----------------------------------------------------------------
# `mix release` sin nombre usa el :app de mix.exs. Los bins migrate/server/setup
# salen de rel/overlays (mix phx.gen.release).
RUN mix release

# ---------------------------------------------------------------------------
# Runtime stage — Debian slim con lo mínimo
# ---------------------------------------------------------------------------
FROM ${DEBIAN_RUNTIME} AS app

# curl lo usa el healthcheck del proxy (la imagen slim no lo trae).
RUN apt-get update -y \
  && apt-get install -y libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Locale UTF-8 — Elixir lo espera en runtime.
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app

# Non-root.
RUN useradd --create-home app
COPY --from=build --chown=app:app /app/_build/prod/rel/{{app}} ./

# El entrypoint aplica migraciones (Release.setup) antes de arrancar el
# release, así la app nunca sirve contra un esquema sin migrar. Una migración
# fallida aborta el boot y el deploy se revierte. SKIP_MIGRATIONS=1 lo saltea.
COPY --chown=app:app docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

USER app

ENV HOME=/app MIX_ENV=prod PHX_SERVER=true PORT=4000

# Nota: DISABLE_FORCE_SSL en runtime es sólo documentación para el operador
# (Coolify lo muestra). Lo que realmente apaga Plug.SSL es el valor del BUILD.
ARG DISABLE_FORCE_SSL=""
ENV DISABLE_FORCE_SSL=${DISABLE_FORCE_SSL}

# Liveness probe. curl falla sólo con status >= 400, así que /health (200 puro,
# sin tocar la base) es un probe honesto mientras el pool se calienta.
# NUNCA apuntes el healthcheck a `/`: redirige a /login (302) y un proxy que
# espera 200 lee un contenedor sano como caído (502).
HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-4000}/health" || exit 1

# EXPOSE no se usa a propósito: no fija el puerto de escucha (eso lo hace PORT)
# y una metadata desalineada confunde al proxy.
ENTRYPOINT ["/app/entrypoint.sh"]