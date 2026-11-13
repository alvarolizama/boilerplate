defmodule {{App}}Web.HealthControllerTest do
  @moduledoc """
  The probe contract: `/health` is 200 with no session and **no database**;
  `/ready` is 503 when the database cannot answer.

  This test deliberately does not use `{{App}}Web.ConnCase`. That helper takes
  a sandbox owner, which hands the test a working connection and would hide a
  `/health` that queries the database. Running without an owner, any query dies
  with `DBConnection.OwnershipError` — so a green 200 on `/health` here is
  structural proof that the probe touches nothing (see the controller's
  moduledoc and `SPEC-docker.md` §The probes).

  The same missing owner is what makes the `/ready` case honest: with no
  connection to hand out, the readiness probe must answer 503, quickly, and that
  is exactly the branch a proxy relies on.

  The paths are plain strings on purpose: `~p` comes from
  `Phoenix.VerifiedRoutes`, which ConnCase sets up, and using ConnCase is
  exactly what this test must not do.
  """

  use ExUnit.Case, async: true

  import Plug.Conn
  import Phoenix.ConnTest

  @endpoint {{App}}Web.Endpoint

  # The real cookie is `_<app>_key`; looking for the word "session" in
  # Set-Cookie would never fail. Neither probe may set ANY cookie.
  defp assert_no_cookie(conn) do
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "GET /health answers 200 without a session and without a database" do
    conn = get(build_conn(), "/health")

    assert conn.status == 200
    assert response(conn, 200) == ~s({"status":"ok"})
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert_no_cookie(conn)
  end

  test "GET /ready answers 503 when the database is not reachable" do
    started = System.monotonic_time(:millisecond)
    conn = get(build_conn(), "/ready")
    elapsed = System.monotonic_time(:millisecond) - started

    assert conn.status == 503
    assert response(conn, 503) == ~s({"status":"unavailable"})
    assert get_resp_header(conn, "cache-control") == ["no-store"]
    assert_no_cookie(conn)

    # Bounded: the 1s cap of the controller is a real cap, not a wish.
    assert elapsed < 5_000
  end
end
