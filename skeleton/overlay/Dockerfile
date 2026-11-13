# syntax=docker/dockerfile:1
#
# The family skeleton — see SPEC-docker.md (the contract).
#
# The {{app}} / {{App}} / {{APP}} placeholders are replaced by
# skeleton/bootstrap.sh.

# ---------------------------------------------------------------------------
# Build stage — prebuilt Elixir/OTP image (no mise, no kerl, no compiling
# Erlang from sources)
# ---------------------------------------------------------------------------
# Pin the image to the local toolchain (VERSIONS.md) and keep the runtime's
# Debian slug aligned with the builder's so no glibc drift creeps in.
ARG ELIXIR_IMAGE=hexpm/elixir:1.20.2-erlang-29.0.3-debian-bookworm-20260713-slim
ARG DEBIAN_RUNTIME=debian:bookworm-20260713-slim

FROM ${ELIXIR_IMAGE} AS build

# build-essential for NIFs, git for GitHub deps, curl/ca-certificates for
# downloads. The tailwind and esbuild wrappers download their own binaries:
# you do NOT need Node. If your app ships its own JS (assets/package.json),
# uncomment the Node block below.
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends build-essential git curl ca-certificates \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Pinned toolchain. `mix local.hex <version>` takes the version directly; rebar3
# is pinned by artifact URL + SHA-512 because `mix local.rebar` only accepts a
# version-less install: 3.28.0 is the build published for this OTP release
# (1.18.4 is the newest Elixir directory Hex ships precompiled artifacts for,
# which is the same fallback `mix local.rebar` resolves on its own). The
# checksum comes from https://repo.hex.pm/installs/rebar.csv.
RUN mix local.hex 2.7.0 --force \
  && mix local.rebar rebar3 "https://builds.hex.pm/installs/1.18.4/rebar3-3.28.0-otp-29" \
    --sha512 b51946058fbe4aa823185bfe27204be59be439982ac3a3e1dbd9f8260b9af046fcfdfbd9066283c3fbba5a2a45dc3570550c12a9a548daf223b80cac222a6d0f \
    --force

ENV MIX_ENV=prod

# force_ssl is compile-time (config/prod.exs). Skeleton default: HTTPS on. To
# deploy over plain HTTP (VPN/LAN with no TLS terminator), build with
# --build-arg DISABLE_FORCE_SSL=1 and set PHX_SCHEME=http.
# (An app behind a VPN may default to "1" in its own Dockerfile; the default
# here is the safe one for a public app.)
ARG DISABLE_FORCE_SSL=""
ENV DISABLE_FORCE_SSL=${DISABLE_FORCE_SSL}

# --- Dependencies (layer cached until mix.exs/mix.lock changes) -------------
# `mix deps.get` ALWAYS before `mix compile`: with a stale lock, prod aborts
# with "lock outdated" (dev tolerates it).
COPY mix.exs mix.lock ./
COPY config config

RUN mix deps.get --only prod

# OOM guard: build containers (Coolify and friends) usually have 512 MB–1 GB
# and the Erlang VM starts one scheduler per core. +S 1:1 limits it to one.
RUN ERL_AFLAGS="+S 1:1" mix deps.compile

# --- Its own JS (optional) --------------------------------------------------
# Only if assets/package.json exists (e.g. a TipTap/three.js editor):
# RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
#   && apt-get install -y nodejs && apt-get clean && rm -rf /var/lib/apt/lists/*
# RUN cd assets && npm ci

# --- Application + assets ---------------------------------------------------
COPY lib lib
COPY priv priv
COPY assets assets
COPY rel rel

RUN mix compile
RUN mix assets.deploy

# --- Release ----------------------------------------------------------------
# `mix release` with no name uses the :app from mix.exs. The migrate/server/setup
# bins come from rel/overlays (mix phx.gen.release).
RUN mix release

# ---------------------------------------------------------------------------
# Runtime stage — Debian slim with the minimum
# ---------------------------------------------------------------------------
FROM ${DEBIAN_RUNTIME} AS app

# curl is used by the proxy's healthcheck (the slim image does not ship it).
RUN apt-get update -y \
  && apt-get install -y --no-install-recommends \
       libstdc++6 openssl libncurses6 locales ca-certificates curl \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# UTF-8 locale — Elixir expects it at runtime.
RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen
ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_ALL=en_US.UTF-8

WORKDIR /app

# Non-root.
RUN useradd --create-home app
COPY --from=build --chown=app:app /app/_build/prod/rel/{{app}} ./

# The entrypoint applies migrations (Release.setup) before starting the
# release, so the app never serves against an unmigrated schema. A failed
# migration aborts the boot and the deploy is rolled back. SKIP_MIGRATIONS=1
# skips it.
COPY --chown=app:app docker/entrypoint.sh /app/entrypoint.sh
RUN chmod +x /app/entrypoint.sh

# HOME must be WRITABLE. Distributed Erlang writes its cookie to $HOME
# (/app/.erlang.cookie) as soon as DNS_CLUSTER_QUERY is set, and a read-only
# /app makes clustering fail with `eacces` in the logs while the container still
# serves — alone. WORKDIR created /app as root, so the directory itself (its
# contents already belong to app) is handed over here.
RUN chown app:app /app

USER app

ENV HOME=/app MIX_ENV=prod PHX_SERVER=true PORT=4000

# Note: DISABLE_FORCE_SSL at runtime is only documentation for the operator
# (the deploy platform shows it). What really turns Plug.SSL off is the value
# at BUILD time.
ARG DISABLE_FORCE_SSL=""
ENV DISABLE_FORCE_SSL=${DISABLE_FORCE_SSL}

# Liveness probe. curl only fails on status >= 400, so /health (a plain 200,
# without touching the database) is an honest probe while the pool warms up.
# NEVER point the healthcheck at `/`: it redirects to /login (302) and a proxy
# expecting 200 reads a healthy container as down (502).
HEALTHCHECK --interval=15s --timeout=3s --start-period=60s --retries=5 \
  CMD curl -fsS "http://127.0.0.1:${PORT:-4000}/health" || exit 1

# EXPOSE is deliberately not used: it does not set the listen port (PORT does)
# and misaligned metadata confuses the proxy.
ENTRYPOINT ["/app/entrypoint.sh"]
