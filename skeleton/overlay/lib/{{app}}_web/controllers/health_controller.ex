defmodule {{App}}Web.HealthController do
  @moduledoc """
  Liveness probe for the container and the proxy.

  It answers `200` as soon as the endpoint is listening and **touches nothing
  else**: no session, no cookie, no database. That is deliberate — the probe
  runs while the app is warming up, which is exactly when the pool is busiest
  (the boot seeds a catalog, partitions, whatever), so a probe that queries the
  database can time a healthy container out.

  Point the healthcheck at `/health`, NEVER at `/`: `/` redirects to `/login`
  (302) and a proxy configured to expect 200 reads it as "down" and returns 502
  over a container that is serving fine.
  """

  use {{App}}Web, :controller

  @body ~s({"status":"ok"})

  @doc "GET /health — always 200 while the endpoint is up."
  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, @body)
  end
end