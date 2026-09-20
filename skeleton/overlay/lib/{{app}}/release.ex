defmodule {{App}}.Release do
  @moduledoc """
  Release tasks invoked by `bin/{{app}} eval` (from `rel/overlays`:
  `bin/migrate`, `bin/setup`) and by the container entrypoint.

    * `migrate/0` — runs the pending Ecto migrations.
    * `setup/0`   — idempotent first run: create the database if missing →
      migrate → seed. Safe to invoke on every deploy.
    * `seed/0`    — evaluates `priv/repo/seeds_prod.exs` (bootstrap of the first
      account). NEVER point it at `priv/repo/seeds.exs`: that is the development
      demo dataset and it creates users with public passwords in the repository.

  All migration/seed/rollback work is wrapped in `Ecto.Migrator.with_repo/2` —
  during `bin/{{app}} eval` the supervision tree (Repo included) is not started.
  `create/0` talks straight to the adapter through `storage_up/1` and does not
  need the Repo.
  """

  require Logger

  @app :{{app}}
  @start_timeout 30_000

  @doc """
  Idempotent first-run setup: create the database if missing → migrate → seed.
  If the app does not bootstrap an account in its seed, the first one comes in
  through the first-run screen (see SPEC-docker.md).

  Only one instance at a time: with 2+ replicas racing on `storage_up`, switch
  the entrypoint to `bin/migrate` and create the database once, out of band.
  """
  def setup do
    load_config()
    create()
    migrate()
    seed()
    :ok
  end

  @doc "Creates the database if it does not exist (idempotent)."
  def create do
    load_config()

    for repo <- repos() do
      case ensure_db_created(repo) do
        :ok -> :ok
        {:error, term} -> raise "failed to create db for #{inspect(repo)}: #{inspect(term)}"
      end
    end
  end

  @doc "Runs the pending migrations."
  def migrate do
    load_config()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_config()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  @doc """
  Evaluates `priv/repo/seeds_prod.exs`. It must be idempotent (get_by + insert)
  and must not create anything with credentials from the repository.

  If the file does not exist it does nothing and says so: an app without a
  production seed (with no first account to bootstrap) has to be able to boot.
  """
  def seed do
    load_config()
    seeds_file = seeds_file()

    if File.exists?(seeds_file) do
      for repo <- repos() do
        {:ok, _, _} =
          Ecto.Migrator.with_repo(
            repo,
            fn _repo -> Code.eval_file(seeds_file) end,
            timeout: @start_timeout
          )
      end
    else
      Logger.info("[release] no seed file at #{seeds_file}, nothing to seed")
      :ok
    end
  end

  @doc """
  Absolute path of the seed that `seed/0` evaluates.

  Public so a test can assert it points at the production seed and not at the
  development one — that confusion is what sows demo data in production.
  """
  @spec seeds_file() :: String.t()
  def seeds_file, do: Application.app_dir(@app, "priv/repo/seeds_prod.exs")

  defp ensure_db_created(repo) do
    case repo.__adapter__().storage_up(repo.config()) do
      :ok ->
        Logger.info("[release] created database for #{inspect(repo)}")
        :ok

      # storage_up/1 returns {:error, :already_up} (an atom, ecto_sql 3.14+) or
      # the legacy tuple of earlier versions: BOTH have to be matched or the
      # second deploy crashes with a misleading "failed to create db".
      {:error, :already_up} ->
        Logger.info("[release] database already exists for #{inspect(repo)}, skipping create")
        :ok

      {:error, {:already_up, _}} ->
        Logger.info("[release] database already exists for #{inspect(repo)}, skipping create")
        :ok

      {:error, term} ->
        {:error, term}
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  # Forces the evaluation of config/runtime.exs (the config provider) so that
  # repo.config() resolves DATABASE_URL and friends. A repo configured outside
  # with_repo/2 fails with "could not lookup Ecto repo".
  defp load_config do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
    _ = Application.get_all_env(@app)
    :ok
  end
end
