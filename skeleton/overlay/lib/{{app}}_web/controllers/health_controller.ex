defmodule {{App}}Web.HealthController do
  @moduledoc """
  Liveness probe del contenedor y del proxy.

  Responde `200` en cuanto el endpoint está escuchando y **no toca nada más**:
  ni sesión, ni cookie, ni base de datos. Eso es deliberado — el probe corre
  mientras la app se está calentando, que es justo cuando el pool está más
  ocupado (el boot siembra catálogo, particiones, lo que sea), así que un probe
  que consulte la base puede tumbar por timeout un contenedor sano.

  Apuntá el healthcheck a `/health`, NUNCA a `/`: `/` redirige a `/login` (302)
  y un proxy configurado para esperar 200 lo lee como "caído" y devuelve 502 con
  un contenedor que está sirviendo bien.
  """

  use {{App}}Web, :controller

  @body ~s({"status":"ok"})

  @doc "GET /health — siempre 200 mientras el endpoint esté arriba."
  def show(conn, _params) do
    conn
    |> put_resp_content_type("application/json")
    |> put_resp_header("cache-control", "no-store")
    |> send_resp(200, @body)
  end
end