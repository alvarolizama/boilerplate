defmodule {{App}}Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :{{app}}

  # The session lives in an encrypted cookie (the client cannot read or modify
  # it). Salts and lifetime are configurable through the environment.
  # SESSION_COOKIE_SECURE=true forces the Secure flag (cookie only over HTTPS);
  # without the variable Plug decides (Secure only when the request is HTTPS, so
  # an HTTP deploy keeps working). See SPEC-config.md.
  session_secure =
    case System.get_env("SESSION_COOKIE_SECURE") do
      v when v in ["true", "1"] -> [secure: true]
      v when v in ["false", "0"] -> [secure: false]
      _ -> []
    end

  # The dev fallbacks are TWO different values and are not used in prod:
  # runtime.exs requires the salts from the environment when config_env() == :prod.
  @session_options [
                     store: :cookie,
                     key: "_{{app}}_key",
                     signing_salt: System.get_env("SESSION_SIGNING_SALT", "{{app}}-dev-signing-salt"),
                     encryption_salt:
                       System.get_env("SESSION_ENCRYPTION_SALT", "{{app}}-dev-encryption-salt"),
                     same_site: "Lax",
                     http_only: true,
                     # Sliding renewal: the cookie is re-issued with a fresh
                     # max_age on every authenticated request, so an active
                     # person stays in and an idle browser expires.
                     renew: true,
                     max_age:
                       String.to_integer(System.get_env("SESSION_MAX_AGE_SECONDS", "31536000"))
                   ] ++ session_secure

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options, peer_data: true, user_agent: true]],
    longpoll: [connect_info: [session: @session_options, peer_data: true, user_agent: true]]

  # Serves the static files from priv/static at "/". With code reloading off
  # (production) gzip is enabled to serve the assets already digested by
  # `phx.digest`.
  plug Plug.Static,
    at: "/",
    from: :{{app}},
    gzip: not code_reloading?,
    only: {{App}}Web.static_paths(),
    raise_on_missing_only: code_reloading?

  # Code reloading (config :code_reloader).
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

  # Explicit body caps: requests above the cap are rejected with 413 before
  # everything is buffered.
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