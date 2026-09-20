import Config

# config/runtime.exs runs in EVERY environment, releases included (as the
# config provider): it executes after compiling and before starting the system.
# Environment-driven configuration goes here — never compile-time configuration
# (it would not apply).
#
# The complete variable contract: SPEC-config.md.

# The endpoint starts the listener even when the release is invoked by hand
# (`bin/{{app}} start`, the deploy platform, Nixpacks…). The gate stops
# `mix test` and `mix precommit` from trying to bind the port (eaddrinuse with
# a dev server already up).
if config_env() == :prod or System.get_env("PHX_SERVER") do
  config :{{app}}, {{App}}Web.Endpoint, server: true
end

config :{{app}}, {{App}}Web.Endpoint,
  http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  # SSL on by default WITHOUT certificate verification: managed databases use
  # self-signed certificates and `verify_peer` against the system bundle breaks
  # the boot (`bad_certificate selfsigned_peer`, with a misleading "killed"
  # while creating the database). ECTO_SSL=false turns it off;
  # ECTO_SSL_VERIFY=true goes back to strict verification.
  #
  # The TLS options go INSIDE `ssl:` (a keyword list). Postgrex >= 0.22
  # deprecated the old pair `ssl: true, ssl_opts: [...]` and logs
  # ":ssl_opts is deprecated, pass opts to :ssl instead" on every connection,
  # so the deprecated form would print a warning per pool connection at boot.
  maybe_ssl =
    cond do
      System.get_env("ECTO_SSL") in ~w(false 0) ->
        []

      System.get_env("ECTO_SSL_VERIFY") in ~w(true 1) ->
        [ssl: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]]

      true ->
        [ssl: [verify: :verify_none]]
    end

  config :{{app}},
         {{App}}.Repo,
         [
           url: database_url,
           pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
           socket_options: maybe_ipv6
         ] ++ maybe_ssl

  # Signs/encrypts cookies and other secrets. It is required: a default in the
  # repo would make every deploy share the same secret.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Session cookie salts. The endpoint has friendly fallbacks for dev, but in
  # prod they MUST come from the environment: otherwise every app of the family
  # shares the committed salts and session cookies can be forged/decrypted.
  for var <- ["SESSION_SIGNING_SALT", "SESSION_ENCRYPTION_SALT"] do
    System.get_env(var) ||
      raise """
      environment variable #{var} is missing.
      Session cookie salts must not fall back to the repo defaults in prod.
      Generate one with: mix phx.gen.secret 32
      """
  end

  # PHX_HOST is the bare hostname (no scheme, no port). Behind a proxy on a
  # non-standard port, PHX_PORT is the external port used in generated URLs.
  # PHX_SCHEME allows `http` when there is no TLS terminator.
  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      Set it to the public hostname the app is served from, e.g. app.example.com
      """

  scheme = System.get_env("PHX_SCHEME", "https")
  url_port = String.to_integer(System.get_env("PHX_PORT", "443"))

  config :{{app}}, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # CHECK_ORIGINS: allowed origins for the CSRF/WS check, comma-separated
  # (scheme://host:port, no paths). Needed when the app is reachable through
  # more than one scheme/host/port (public HTTPS + HTTP over a VPN): without it
  # the POST to /login dies with a 403 and no controller log.
  # Unset = Phoenix's default behavior (checks against the configured url).
  check_origin_config =
    case System.get_env("CHECK_ORIGINS") do
      nil -> []
      "" -> []
      origins -> [check_origin: String.split(origins, ",", trim: true)]
    end

  # NOTE: force_ssl is compile-time (the endpoint marks it with compile_env), so
  # it cannot live here. It is in config/prod.exs and is turned off only at BUILD
  # time with DISABLE_FORCE_SSL=1.
  config :{{app}},
         {{App}}Web.Endpoint,
         [
           url: [host: host, port: url_port, scheme: scheme],
           http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
           secret_key_base: secret_key_base
         ] ++ check_origin_config

  # Google OAuth (optional — empty = Google sign-in disabled).
  config :{{app}}, :google_oauth,
    client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET"),
    redirect_uri:
      System.get_env("GOOGLE_OAUTH_REDIRECT_URI") ||
        "#{scheme}://#{host}/auth/google/callback"
end

# --- Variables of {{App}} itself --------------------------------------------
# Declare them with an explicit default and read them at runtime, never with
# Application.compile_env (a key read at compile time and set here aborts the
# boot with "has a different value set for key ... during runtime").
#
# Examples:
#   config :{{app}}, :uploads,
#     dir: System.get_env("{{APP}}_UPLOADS_DIR", "priv/static/uploads")
#   config :{{app}}, :inference, {{App}}.Inference.Config.load_from_env()
