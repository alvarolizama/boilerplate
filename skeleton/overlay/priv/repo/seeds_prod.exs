# Seed de producción de {{App}} — lo evalúa {{App}}.Release.seed/0 en el boot
# (entrypoint del contenedor → {{App}}.Release.setup/0), NO es el dataset de dev
# (priv/repo/seeds.exs): ese crea datos con contraseñas públicas del repositorio.
#
# Reglas:
#   * IDEMPOTENTE: `get_by` y después `insert` (o `on_conflict`). El setup corre
#     en CADA deploy.
#   * OPT-IN para credenciales: si la app bootstrapea una cuenta, la crea sólo
#     cuando la variable está puesta; sin ella el boot no crea usuarios y la
#     primera cuenta entra por la pantalla de primera ejecución. Nunca un
#     password de fallback que viva en el repositorio.
#   * El archivo puede quedarse vacío: `seed/0` sólo lo evalúa si existe.
#
# Patrón (descomentá y adaptá):
#
#   alias {{App}}.Repo
#   alias {{App}}.Accounts
#
#   if password = System.get_env("{{APP}}_ADMIN_PASSWORD") do
#     email = System.get_env("{{APP}}_ADMIN_EMAIL", "admin@{{app}}.local")
#
#     case Accounts.get_user_by_email(email) do
#       nil ->
#         {:ok, _user} =
#           Accounts.create_user(%{email: email, password: password, role: :admin})
#
#         IO.puts("[seed] admin #{email} created")
#
#       _existing ->
#         IO.puts("[seed] admin #{email} already exists, skipping")
#     end
#   else
#     IO.puts("[seed] {{APP}}_ADMIN_PASSWORD not set — first account comes from the UI")
#   end