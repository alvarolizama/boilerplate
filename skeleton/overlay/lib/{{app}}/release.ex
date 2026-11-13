defmodule {{App}}.Release do
  @moduledoc """
  Release tasks invoked by `bin/{{app}} eval` (from `rel/overlays`:
  `bin/migrate`, `bin/setup`) and by the container entrypoint.

    * `migrate/0` — runs the pending Ecto migrations.
    * `setup/0`   — idempotent first run: create the database if missing →
      migrate → seed. Safe to invoke on every deploy, and safe when several
      replicas start at the same time.
    * `seed/0`    — evaluates `priv/repo/seeds_prod.exs` (bootstrap of the first
      account). NEVER point it at `priv/repo/seeds.exs`: that is the development
      demo dataset and it creates users with public passwords in the repository.

  ## Concurrency

  `setup/0` takes a PostgreSQL advisory lock before migrating and seeding, and
  holds it for the whole block. Two containers that boot together therefore
  serialize: the second one waits (bounded) instead of racing the first on the
  same migration or on a unique constraint inside the seed — the race that used
  to take a new container down. The lock lives on one checked-out connection, so
  Postgres releases it by itself if the node dies mid-setup.

  Creating the database stays outside the lock, because the lock needs a
  connection to a database that may not exist yet. `storage_up/1` is idempotent
  (already existing is not an error); a role that may not create databases —
  the usual managed/restricted provider — gets `SKIP_DB_CREATE=1` and the
  database provisioned out of band (see SPEC-docker.md).

  The lock is PostgreSQL-specific (`pg_try_advisory_lock`). An app on another
  adapter replaces `with_setup_lock/2` with its own equivalent.

  All migration/seed/rollback work is wrapped in `Ecto.Migrator.with_repo/2` —
  during `bin/{{app}} eval` the supervision tree (Repo included) is not started.
  `create/0` talks straight to the adapter through `storage_up/1` and does not
  need the Repo.
  """

  require Logger

  @app :{{app}}
  @start_timeout 30_000

  # The setup holds one connection for the advisory lock, and Ecto's migrator
  # needs two (one to lock schema_migrations, one to migrate). `with_repo/2`
  # starts the repo with a pool of 2 by default, which would deadlock here.
  @setup_pool_size 5

  # Advisory lock key, stable per app (phash2 is deterministic for the same
  # term) so two apps sharing one Postgres do not block each other, and the
  # migrate/seed window of one deploy does.
  @setup_lock_key :erlang.phash2({@app, :setup}, 2_147_483_647)
  @lock_wait_ms 120_000
  @lock_poll_ms 250

  @doc """
  Idempotent first-run setup: create the database if missing → migrate → seed.
  If the app does not bootstrap an account in its seed, the first one comes in
  through the first-run screen (see SPEC-docker.md).

  Migrate and seed run under a PostgreSQL advisory lock, so replicas that start
  together serialize instead of racing (see the moduledoc). With a role that
  cannot create databases, set `SKIP_DB_CREATE=1` and provision the database out
  of band.
  """
  def setup do
    load_config()
    create()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn repo ->
            with_setup_lock(repo, fn ->
              Ecto.Migrator.run(repo, :up, all: true)
              seed_repo(repo)
            end)
          end,
          pool_size: @setup_pool_size,
          timeout: @start_timeout
        )
    end

    :ok
  end

  @doc """
  Creates the database if it does not exist (idempotent).

  Honours `SKIP_DB_CREATE`: when it is set the task assumes the database is
  already provisioned and does nothing (the postgres role of a managed provider
  often has no CREATEDB privilege).
  """
  def create do
    load_config()

    if skip_db_create?() do
      Logger.info("[release] SKIP_DB_CREATE is set, skipping database creation")
      :ok
    else
      for repo <- repos() do
        case ensure_db_created(repo) do
          :ok -> :ok
          {:error, term} -> raise "failed to create db for #{inspect(repo)}: #{inspect(term)}"
        end
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
  Evaluates `priv/repo/seeds_prod.exs` under the setup lock. It must be
  idempotent (get_by + insert, or `on_conflict`) and must not create anything
  with credentials from the repository.

  If the file does not exist it does nothing and says so: an app without a
  production seed (with no first account to bootstrap) has to be able to boot.
  """
  def seed do
    load_config()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(
          repo,
          fn repo -> with_setup_lock(repo, fn -> seed_repo(repo) end) end,
          pool_size: @setup_pool_size,
          timeout: @start_timeout
        )
    end
  end

  @doc """
  Absolute path of the seed that `seed/0` evaluates.

  Public so a test can assert it points at the production seed and not at the
  development one — that confusion is what sows demo data in production.
  """
  @spec seeds_file() :: String.t()
  def seeds_file, do: Application.app_dir(@app, "priv/repo/seeds_prod.exs")

  ## Setup lock

  # Pins ONE connection (the lock is session-scoped in Postgres) and runs the
  # block on it; the statements inside may borrow other connections from the
  # pool.
  defp with_setup_lock(repo, fun) do
    repo.checkout(
      fn ->
        acquire_setup_lock!(repo)

        try do
          fun.()
        after
          release_setup_lock(repo)
        end
      end,
      timeout: :infinity
    )
  end

  defp acquire_setup_lock!(repo) do
    wait_setup_lock!(repo, System.monotonic_time(:millisecond) + @lock_wait_ms)
  end

  # `try_lock` + bounded wait instead of a blocking `lock`: an instance that
  # cannot get in fails loudly with a useful message instead of hanging the
  # deploy until the platform kills it.
  defp wait_setup_lock!(repo, deadline) do
    case repo.query!("SELECT pg_try_advisory_lock($1)", [@setup_lock_key]) do
      %{rows: [[true]]} ->
        Logger.info("[release] setup lock acquired")
        :ok

      %{rows: [[false]]} ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise """
          could not acquire the setup lock after #{@lock_wait_ms} ms.
          Another instance is still migrating or seeding. If this is a permanent
          condition, run the setup once as a one-off task (bin/setup) and start
          the web containers with SKIP_MIGRATIONS=1.
          """
        else
          Process.sleep(@lock_poll_ms)
          wait_setup_lock!(repo, deadline)
        end
    end
  end

  defp release_setup_lock(repo) do
    repo.query("SELECT pg_advisory_unlock($1)", [@setup_lock_key])
    :ok
  end

  ## Seed

  defp seed_repo(_repo) do
    seeds_file = seeds_file()

    if File.exists?(seeds_file) do
      # Code.eval_file/1 returns {value, bindings}; the value is irrelevant.
      _ = Code.eval_file(seeds_file)
      :ok
    else
      Logger.info("[release] no seed file at #{seeds_file}, nothing to seed")
      :ok
    end
  end

  ## Repo / storage

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

  defp skip_db_create?, do: System.get_env("SKIP_DB_CREATE") in ~w(true 1)

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
