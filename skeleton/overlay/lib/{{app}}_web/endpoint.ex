defmodule {{App}}Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :{{app}}

  # The session cookie is configured at RUNTIME, never at compile time.
  #
  # The options live in `config/runtime.exs` (`config :{{app}}, :session`) and
  # are resolved by `session_options/0` on every request; the LiveView sockets
  # get the same function as an MFA in `connect_info`. Reading them with
  # `System.get_env/2` inside a module attribute — the shape this file used to
  # have — froze the salts, the lifetime and the `Secure` flag into the BEAM
  # when the image was built, so rotating them or changing them per environment
  # did nothing until a rebuild. See SPEC-config.md §Session and cookies.
  @session_options_mfa {__MODULE__, :session_options, []}

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [
      connect_info: [session: @session_options_mfa, peer_data: true, user_agent: true]
    ],
    longpoll: [
      connect_info: [session: @session_options_mfa, peer_data: true, user_agent: true]
    ]

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

  # Proxy trust is OPT-IN and decided per request: with TRUST_PROXY=1 the peer,
  # the scheme, the host and the port come from the X-Forwarded-* headers.
  # Enable it ONLY when the container is unreachable except through the proxy,
  # and only if the proxy strips those headers from incoming requests — without
  # that, any client can claim whatever IP/scheme/host it wants (spoofed origin
  # checks, spoofed rate-limit buckets, spoofed logs). See SPEC-docker.md
  # §Proxy trust. Unset (the default) rewrites nothing.
  plug Plug.RewriteOn, {__MODULE__, :rewrite_on, []}

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
  plug :session

  plug {{App}}Web.Router

  ## Runtime readers
  #
  # Public on purpose: they are handed to Phoenix as MFAs (`@session_options_mfa`
  # and `Plug.RewriteOn`), so they must be callable from outside the module.

  @doc """
  Session cookie options, resolved on **every** call.

  The environment-dependent part (both salts, `max_age` and, optionally,
  `secure`) comes from `config :{{app}}, :session`, written by
  `config/runtime.exs`; this function adds the parts that are code and not
  environment: the store, the cookie name and the cookie policy.
  """
  @spec session_options() :: keyword()
  def session_options do
    runtime =
      Application.get_env(:{{app}}, :session) ||
        raise """
        the session is not configured for :{{app}}.
        config/runtime.exs must set `config :{{app}}, :session, ...`
        (see SPEC-config.md §Session and cookies).
        """

    Keyword.merge(
      [
        store: :cookie,
        key: "_{{app}}_key",
        same_site: "Lax",
        http_only: true,
        # Sliding renewal: the cookie is re-issued with a fresh max_age on every
        # authenticated request, so an active person stays in and an idle
        # browser expires.
        renew: true
      ],
      runtime
    )
  end

  @doc """
  Headers `Plug.RewriteOn` is allowed to trust; empty unless `TRUST_PROXY` is set.
  """
  @spec rewrite_on() :: [atom()]
  def rewrite_on do
    if Application.get_env(:{{app}}, :trust_proxy, false) do
      [:x_forwarded_for, :x_forwarded_proto, :x_forwarded_host, :x_forwarded_port]
    else
      []
    end
  end

  # `Plug.Session.init/1` only accepts a keyword list — it runs at compile time
  # and has no MFA clause — so the plug is this local function: it initializes
  # the store on every request from `session_options/0`.
  defp session(conn, _opts) do
    Plug.Session.call(conn, Plug.Session.init(session_options()))
  end
end
