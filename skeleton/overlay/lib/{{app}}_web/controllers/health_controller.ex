defmodule {{App}}Web.HealthController do
  @moduledoc """
  The two probes, and the difference between them.

    * `GET /health` — **liveness**. Answers `200` as soon as the endpoint is
      listening and touches nothing else: no session, no cookie, no database.
      That is deliberate — the probe runs while the app is warming up, which is
      exactly when the pool is busiest (the boot seeds a catalog, partitions,
      whatever), so a probe that queries the database can time a healthy
      container out.
    * `GET /ready` — **readiness**. Confirms the database answers `SELECT 1`,
      with a short bounded timeout, and answers `503` when it does not. Point a
      proxy/load balancer at `/ready` if it needs to stop sending traffic to a
      container whose database went away; keep the container healthcheck on
      `/health`, never on `/ready`, or a slow boot restarts a healthy app.

  Point the healthcheck at `/health`, NEVER at `/`: `/` redirects to `/login`
  (302) and a proxy configured to expect 200 reads it as "down" and returns 502
  over a container that is serving fine.

  Neither action requires a session, so neither sets a cookie.
  """

  require Logger

  use {{App}}Web, :controller

  # Bounded on purpose: the probe must answer inside the proxy's own timeout.
  # `:timeout` reaches DBConnection, so it covers the pool checkout *and* the
  # statement — a saturated pool fails the check instead of queueing forever.
  @ready_timeout_ms 1_000

  @ok_body ~s({"status":"ok"})
  @unready_body ~s({"status":"unavailable"})

  @doc "GET /health — always 200 while the endpoint is up."
  def show(conn, _params) do
    reply(conn, 200, @ok_body)
  end

  @doc """
  GET /ready — 200 when every repo answers `SELECT 1`, 503 when one does not.

  The failure body carries no detail (a probe is public); the reason goes to the
  log, truncated.
  """
  def ready(conn, _params) do
    case check_database() do
      :ok ->
        reply(conn, 200, @ok_body)

      {:error, reason} ->
        Logger.warning("[ready] database check failed: #{inspect(reason, limit: 5)}")
        reply(conn, 503, @unready_body)
    end
  end

  defp reply(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(status, body)
  end

  defp check_database do
    repos = Application.fetch_env!(:{{app}}, :ecto_repos)

    Enum.reduce_while(repos, :ok, fn repo, :ok ->
      case probe(repo) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, {repo, reason}}}
      end
    end)
  end

  defp probe(repo) do
    case repo.query("SELECT 1", [], timeout: @ready_timeout_ms) do
      {:ok, _result} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    # A repo that is not started, a pool with no owner (sandbox) or any other
    # adapter exception is still "not ready", not a crash of the probe.
    error -> {:error, error}
  end
end
