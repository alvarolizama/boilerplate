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

# THEME: the daisyUI theme the app renders with (DESIGN.md §C2). It is chosen at
# RUNTIME — app.css compiles the family's set and root.html.heex writes this
# value into `data-theme` — so switching it needs no rebuild. An unknown value
# falls back to `dim` ({{App}}Web.Theme.current/0).
config :{{app}}, :theme, System.get_env("THEME", "dim")

# --- Session cookie (runtime) -----------------------------------------------
# These options are read on EVERY request: `{{App}}Web.Endpoint.session_options/0`
# supplies both the HTTP session plug and the LiveView `connect_info` MFAs, so
# nothing here is frozen into the BEAM by a compile. Rotating a salt, changing
# the lifetime or flipping `secure` takes effect on restart, with no rebuild.
#
# In prod the two salts MUST come from the environment and MUST differ: a
# committed fallback would be shared by every app of the family. Outside prod
# the fallbacks are two distinct values, so local development needs no setup.
# The rest of the cookie (store, key, same_site, http_only, renew) is code and
# lives in the endpoint. See SPEC-config.md §Session and cookies.
# An explicit SESSION_COOKIE_SECURE wins. Otherwise production HTTPS gets a
# secure cookie by default; local HTTP and intentional prod HTTP do not.
default_session_secure =
  if config_env() == :prod and System.get_env("PHX_SCHEME", "https") == "https",
    do: [secure: true],
    else: []

session_secure =
  case System.get_env("SESSION_COOKIE_SECURE") do
    v when v in ["true", "1"] -> [secure: true]
    v when v in ["false", "0"] -> [secure: false]
    _ -> default_session_secure
  end

session_max_age =
  case Integer.parse(System.get_env("SESSION_MAX_AGE_SECONDS") || "31536000") do
    {seconds, ""} when seconds > 0 ->
      seconds

    _ ->
      raise """
      environment variable SESSION_MAX_AGE_SECONDS must be a positive integer
      number of seconds, e.g. 31536000 (one year).
      """
  end

session_salts =
  if config_env() == :prod do
    Enum.each(["SESSION_SIGNING_SALT", "SESSION_ENCRYPTION_SALT"], fn var ->
      System.get_env(var) ||
        raise """
        environment variable #{var} is missing.
        Session cookie salts must not fall back to the repo defaults in prod.
        Generate one with: mix phx.gen.secret 32
        """
    end)

    signing = System.fetch_env!("SESSION_SIGNING_SALT")
    encryption = System.fetch_env!("SESSION_ENCRYPTION_SALT")

    if signing == encryption do
      raise """
      SESSION_SIGNING_SALT and SESSION_ENCRYPTION_SALT must be two DIFFERENT values.
      Distinct salts separate the signing and encryption key domains.
      Generate each one with: mix phx.gen.secret 32
      """
    end

    [signing_salt: signing, encryption_salt: encryption]
  else
    [
      signing_salt: System.get_env("SESSION_SIGNING_SALT", "{{app}}-dev-signing-salt"),
      encryption_salt: System.get_env("SESSION_ENCRYPTION_SALT", "{{app}}-dev-encryption-salt")
    ]
  end

config :{{app}}, :session, session_salts ++ [max_age: session_max_age] ++ session_secure

# Proxy trust (false unless TRUST_PROXY=1). Read per request by the endpoint's
# `Plug.RewriteOn` MFA: it rewrites peer/scheme/host/port from the X-Forwarded-*
# headers. Only enable it when the container is unreachable except through the
# proxy AND the proxy strips those headers — otherwise any client spoofs them.
config :{{app}}, :trust_proxy, System.get_env("TRUST_PROXY") in ~w(true 1)

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

  # Early failure instead of a broken deploy: Plug.Session.COOKIE refuses to
  # write a cookie with a shorter base ("conn.secret_key_base to be at least 64
  # bytes"), so every request that touches the session would 500 while a
  # liveness probe still reported the container as up.
  if byte_size(secret_key_base) < 64 do
    raise """
    SECRET_KEY_BASE is #{byte_size(secret_key_base)} bytes; it must be at least 64.
    Generate a valid one with: mix phx.gen.secret
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
  #
  # GOOGLE_OAUTH_ALLOWED_DOMAINS restricts self-registration with Google:
  # comma-separated bare domains of the verified email (`example.com,corp.example`).
  # Empty/unset = only existing users can sign in. Splitting WITHOUT trim:true
  # and trimming each item means a blank item or trailing comma is rejected:
  # a malformed allowlist must fail closed, never become a partial allowlist.
  allowed_domains =
    case System.get_env("GOOGLE_OAUTH_ALLOWED_DOMAINS") do
      value when value in [nil, ""] ->
        []

      domains ->
        domains
        |> String.split(",", trim: false)
        |> Enum.map(fn domain ->
          domain = domain |> String.trim() |> String.downcase()

          unless Regex.match?(
                   ~r/\A[a-z0-9](?:[a-z0-9.-]*[a-z0-9])?\z/,
                   domain
                 ) and String.contains?(domain, ".") and
                   not String.contains?(domain, "..") do
            raise "GOOGLE_OAUTH_ALLOWED_DOMAINS contains an invalid or blank domain: #{inspect(domain)}"
          end

          domain
        end)
    end

  config :{{app}}, :google_oauth,
    client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET"),
    redirect_uri:
      System.get_env("GOOGLE_OAUTH_REDIRECT_URI") ||
        "#{scheme}://#{host}/auth/google/callback",
    allowed_domains: allowed_domains
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
