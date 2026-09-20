# Production seed for {{App}} — evaluated by {{App}}.Release.seed/0 at boot
# (container entrypoint → {{App}}.Release.setup/0). It is NOT the dev dataset
# (priv/repo/seeds.exs): that one creates data with public passwords from the
# repository.
#
# Rules:
#   * IDEMPOTENT: `get_by` and then `insert` (or `on_conflict`). The setup runs
#     on EVERY deploy.
#   * OPT-IN for credentials: if the app bootstraps an account, it creates it
#     only when the variable is set; without it the boot creates no users and
#     the first account comes in through the first-run screen. Never a fallback
#     password that lives in the repository.
#   * The file may stay empty: `seed/0` only evaluates it if it exists.
#
# Pattern (uncomment and adapt):
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