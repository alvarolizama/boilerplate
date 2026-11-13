# Production seed for {{App}} — evaluated by {{App}}.Release.seed/0 at boot
# (container entrypoint → {{App}}.Release.setup/0). It is NOT the dev dataset
# (priv/repo/seeds.exs): that one creates data with public passwords from the
# repository.
#
# Rules:
#   * IDEMPOTENT: the setup runs on EVERY deploy. Two choices, both fine:
#       - read-then-write: `get_by` + `insert` (one extra round trip);
#       - insert-first: `Repo.insert(changeset, on_conflict: :nothing,
#         conflict_target: :email)` — needs a UNIQUE index on the target and a
#         changeset that can be discarded.
#   * SAFE UNDER CONCURRENCY: `Release.setup/0` holds a Postgres advisory lock
#     around migrate+seed, so overlapping replicas serialize instead of racing.
#     The seed still has to be idempotent: the next deploy runs it again.
#   * OPT-IN for credentials: if the app bootstraps an account, it creates it
#     only when the variable is set; without it the boot creates no users and
#     the first account comes in through the first-run screen. Never a fallback
#     password that lives in the repository.
#   * The file may stay empty: `seed/0` only evaluates it if it exists.
#
# Pattern (uncomment and adapt the names to your context):
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
#
# Insert-first variant of the same block (no read, the unique index decides):
#
#   {:ok, _user} =
#     %{email: email, password: password, role: :admin}
#     |> Accounts.change_user()
#     |> Repo.insert(on_conflict: :nothing, conflict_target: :email)
