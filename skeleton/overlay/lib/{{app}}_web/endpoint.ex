defmodule {{App}}Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :{{app}}

  # La sesión vive en una cookie cifrada (el cliente no puede leerla ni
  # modificarla). Salts y vida son configurables por entorno.
  # SESSION_COOKIE_SECURE=true fuerza el flag Secure (cookie sólo por HTTPS);
  # sin la variable decide Plug (Secure sólo si el request es HTTPS, así un
  # deploy HTTP sigue funcionando). Ver SPEC-config.md.
  session_secure =
    case System.get_env("SESSION_COOKIE_SECURE") do
      v when v in ["true", "1"] -> [secure: true]
      v when v in ["false", "0"] -> [secure: false]
      _ -> []
    end

  # Los fallbacks de dev son DOS valores distintos y no se usan en prod:
  # runtime.exs exige los salts del entorno cuando config_env() == :prod.
  @session_options [
                     store: :cookie,
                     key: "_{{app}}_key",
                     signing_salt: System.get_env("SESSION_SIGNING_SALT", "{{app}}-dev-signing-salt"),
                     encryption_salt:
                       System.get_env("SESSION_ENCRYPTION_SALT", "{{app}}-dev-encryption-salt"),
                     same_site: "Lax",
                     http_only: true,
                     # Renovación deslizante: la cookie se re-emite con max_age
                     # fresco en cada request autenticado, así una persona activa
                     # sigue dentro y un navegador ocioso expira.
                     renew: true,
                     max_age:
                       String.to_integer(System.get_env("SESSION_MAX_AGE_SECONDS", "31536000"))
                   ] ++ session_secure

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options, peer_data: true, user_agent: true]],
    longpoll: [connect_info: [session: @session_options, peer_data: true, user_agent: true]]

  # Sirve en "/" los estáticos de priv/static. Con recarga de código apagada
  # (producción) se activa gzip para servir los estáticos ya digeridos por
  # `phx.digest`.
  plug Plug.Static,
    at: "/",
    from: :{{app}},
    gzip: not code_reloading?,
    only: {{App}}Web.static_paths(),
    raise_on_missing_only: code_reloading?

  # Recarga de código (config :code_reloader).
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
    plug Phoenix.Ecto.CheckRepoStatus, otp_app: :{{app}}
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Topes de body explícitos: los requests por encima del tope se rechazan con
  # 413 antes de bufferear todo.
  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 10_000_000,
    read_length: 1_000_000

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  plug {{App}}Web.Router
end