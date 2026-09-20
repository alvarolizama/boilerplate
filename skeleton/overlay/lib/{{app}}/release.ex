defmodule {{App}}.Release do
  @moduledoc """
  Tareas de release que invocan `bin/{{app}} eval` (desde `rel/overlays`:
  `bin/migrate`, `bin/setup`) y el entrypoint del contenedor.

    * `migrate/0` — corre las migraciones pendientes de Ecto.
    * `setup/0`   — primera ejecución idempotente: crear la base si falta →
      migrar → seed. Seguro de invocar en cada deploy.
    * `seed/0`    — evalúa `priv/repo/seeds_prod.exs` (bootstrap de la primera
      cuenta). NUNCA apuntar a `priv/repo/seeds.exs`: ese es el dataset demo de
      desarrollo y crea usuarios con contraseña pública en el repositorio.

  Todo el trabajo de migración/seed/rollback va envuelto en
  `Ecto.Migrator.with_repo/2` — durante `bin/{{app}} eval` el árbol de
  supervisión (Repo incluido) no está arrancado. `create/0` habla directo con el
  adapter vía `storage_up/1` y no necesita el Repo.
  """

  require Logger

  @app :{{app}}
  @start_timeout 30_000

  @doc """
  Setup idempotente de primera ejecución: crear la base si falta → migrar →
  seed. Si la app no bootstrapea una cuenta en su seed, la primera entra desde
  la pantalla de primera ejecución (ver SPEC-docker.md).

  Sólo una instancia a la vez: con 2+ réplicas compitiendo en `storage_up`,
  cambiá el entrypoint a `bin/migrate` y creá la base una vez fuera de banda.
  """
  def setup do
    load_config()
    create()
    migrate()
    seed()
    :ok
  end

  @doc "Crea la base si no existe (idempotente)."
  def create do
    load_config()

    for repo <- repos() do
      case ensure_db_created(repo) do
        :ok -> :ok
        {:error, term} -> raise "failed to create db for #{inspect(repo)}: #{inspect(term)}"
      end
    end
  end

  @doc "Corre las migraciones pendientes."
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
  Evalúa `priv/repo/seeds_prod.exs`. Debe ser idempotente (get_by + insert) y no
  crear nada con credenciales del repositorio.

  Si el archivo no existe, no hace nada y lo deja dicho: una app sin seed de
  producción (sin primera cuenta que bootstrapear) tiene que poder arrancar.
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
  Path absoluto del seed que evalúa `seed/0`.

  Público para que un test pueda afirmar que apunta al seed de producción y no
  al de desarrollo — esa confusión es la que siembra datos demo en producción.
  """
  @spec seeds_file() :: String.t()
  def seeds_file, do: Application.app_dir(@app, "priv/repo/seeds_prod.exs")

  defp ensure_db_created(repo) do
    case repo.__adapter__().storage_up(repo.config()) do
      :ok ->
        Logger.info("[release] created database for #{inspect(repo)}")
        :ok

      # storage_up/1 devuelve {:error, :already_up} (átomo, ecto_sql 3.14+) o el
      # tuple legacy de versiones anteriores: hay que matchear AMBOS o el
      # segundo deploy crashea con un engañoso "failed to create db".
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

  # Fuerza la evaluación de config/runtime.exs (el config provider) para que
  # repo.config() resuelva DATABASE_URL y compañía. Un repo configurado afuera
  # de with_repo/2 falla con "could not lookup Ecto repo".
  defp load_config do
    Application.ensure_all_started(:ssl)
    Application.ensure_loaded(@app)
    _ = Application.get_all_env(@app)
    :ok
  end
end