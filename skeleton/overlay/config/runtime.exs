import Config

# config/runtime.exs corre en TODOS los entornos, incluidos los releases (como
# config provider): se ejecuta después de compilar y antes de arrancar el
# sistema. Acá va la configuración que lee el entorno — nunca configuración de
# compile-time (no se aplicaría).
#
# Contrato completo de variables: SPEC-config.md.

# El endpoint arranca el listener aunque el release se invoque a mano
# (`bin/{{app}} start`, Coolify, Nixpacks…). El gate evita que `mix test` y
# `mix precommit` intenten bindear el puerto (eaddrinuse con un server de dev
# arriba).
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

  # SSL activado por default SIN verificar certificado: las bases gestionadas
  # usan self-signed y `verify_peer` contra el bundle del sistema rompe el boot
  # (`bad_certificate selfsigned_peer`, con un engañoso "killed" al crear la
  # base). ECTO_SSL=false lo apaga; ECTO_SSL_VERIFY=true vuelve a verificación
  # estricta.
  maybe_ssl =
    cond do
      System.get_env("ECTO_SSL") in ~w(false 0) ->
        []

      System.get_env("ECTO_SSL_VERIFY") in ~w(true 1) ->
        [ssl: true, ssl_opts: [verify: :verify_peer, cacerts: :public_key.cacerts_get()]]

      true ->
        [ssl: true, ssl_opts: [verify: :verify_none]]
    end

  config :{{app}},
         {{App}}.Repo,
         [
           url: database_url,
           pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
           socket_options: maybe_ipv6
         ] ++ maybe_ssl

  # Firma/cifra cookies y otros secretos. Se exige: un default en el repo haría
  # que todos los deploys compartan el mismo secreto.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  # Salts de la cookie de sesión. El endpoint tiene fallbacks amigables para dev,
  # pero en prod DEBEN venir del entorno: si no, toda la familia comparte los
  # salts commiteados y las cookies de sesión se pueden forjar/descifrar.
  for var <- ["SESSION_SIGNING_SALT", "SESSION_ENCRYPTION_SALT"] do
    System.get_env(var) ||
      raise """
      environment variable #{var} is missing.
      Session cookie salts must not fall back to the repo defaults in prod.
      Generate one with: mix phx.gen.secret 32
      """
  end

  # PHX_HOST es el hostname pelado (sin esquema ni puerto). Detrás de un proxy
  # con puerto no estándar, PHX_PORT es el puerto externo para las URLs
  # generadas. PHX_SCHEME permite `http` cuando no hay terminador TLS.
  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      Set it to the public hostname the app is served from, e.g. app.example.com
      """

  scheme = System.get_env("PHX_SCHEME", "https")
  url_port = String.to_integer(System.get_env("PHX_PORT", "443"))

  config :{{app}}, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  # CHECK_ORIGINS: origins permitidos para el chequeo CSRF/WS, separados por
  # comas (scheme://host:puerto, sin paths). Hace falta cuando la app se ve por
  # más de un esquema/host/puerto (HTTPS público + HTTP por VPN): sin esto el
  # POST de /login muere en 403 sin log de controlador.
  # Unset = comportamiento default de Phoenix (chequea contra la url configurada).
  check_origin_config =
    case System.get_env("CHECK_ORIGINS") do
      nil -> []
      "" -> []
      origins -> [check_origin: String.split(origins, ",", trim: true)]
    end

  # OJO: force_ssl es compile-time (lo marca el endpoint con compile_env), así
  # que NO puede vivir acá. Está en config/prod.exs y se apaga sólo en BUILD con
  # DISABLE_FORCE_SSL=1.
  config :{{app}},
         {{App}}Web.Endpoint,
         [
           url: [host: host, port: url_port, scheme: scheme],
           http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}],
           secret_key_base: secret_key_base
         ] ++ check_origin_config

  # Google OAuth (opcional — vacío = login con Google deshabilitado).
  config :{{app}}, :google_oauth,
    client_id: System.get_env("GOOGLE_OAUTH_CLIENT_ID"),
    client_secret: System.get_env("GOOGLE_OAUTH_CLIENT_SECRET"),
    redirect_uri:
      System.get_env("GOOGLE_OAUTH_REDIRECT_URI") ||
        "#{scheme}://#{host}/auth/google/callback"
end

# --- Variables propias de {{App}} ------------------------------------------
# Declaralas con default explícito y leelas en runtime, nunca con
# Application.compile_env (un key leído en compile-time y seteado acá aborta el
# boot con "has a different value set for key ... during runtime").
#
# Ejemplos de la familia:
#   config :{{app}}, :uploads,
#     dir: System.get_env("{{APP}}_UPLOADS_DIR", "priv/static/uploads")
#   config :{{app}}, :inference, {{App}}.Inference.Config.load_from_env()