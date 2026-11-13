defmodule {{App}}.ReleaseTest do
  # The release module is pure filesystem/config work: no Repo, no LiveView.
  use ExUnit.Case, async: true

  alias {{App}}.Release

  describe "seeds_file/0" do
    test "points at the production seed, never the development dataset" do
      path = Release.seeds_file()

      assert Path.basename(path) == "seeds_prod.exs",
             """
             Release.seeds_file/0 resolves to #{inspect(path)}.
             seed/0 evaluates whatever this returns on EVERY deploy: if it is
             `seeds.exs` (the development dataset, users with public passwords from
             the repository) the deploy sows demo data in production.
             """

      assert String.ends_with?(path, "priv/repo/seeds_prod.exs"),
             "Release.seeds_file/0 must end in priv/repo/seeds_prod.exs, got #{inspect(path)}"
    end

    test "is an absolute path inside this app's own priv/, not the cwd" do
      path = Release.seeds_file()

      assert Path.type(path) == :absolute,
             "Release.seeds_file/0 returned a relative path (#{inspect(path)}); " <>
               "a release boots from /app, so `priv/repo/...` would resolve elsewhere"

      assert path == Application.app_dir(:{{app}}, "priv/repo/seeds_prod.exs"),
             """
             Release.seeds_file/0 must resolve through Application.app_dir/2 so the
             release reads the priv/ it ships with:
               got:      #{inspect(path)}
               expected: #{inspect(Application.app_dir(:{{app}}, "priv/repo/seeds_prod.exs"))}
             """

      assert File.exists?(path), "the production seed #{inspect(path)} does not exist"
    end
  end

  describe "priv/repo/seeds_prod.exs" do
    test "carries no credentials from the repository" do
      body = File.read!(Release.seeds_file())

      refute body =~ ~r/password:\s*"/,
             """
             priv/repo/seeds_prod.exs contains a LITERAL password (password: "…").
             The production seed runs on every deploy and the repository is the one
             place a credential must never live: read it from the environment and
             create nothing when it is unset (see the pattern at the top of the file).
             """

      refute body =~ ~r/get_env\([^)]*PASSWORD[^)]*,\s*"/,
             """
             priv/repo/seeds_prod.exs reads its password with a DEFAULT literal
             (System.get_env("…PASSWORD", "…")). A default is a committed credential:
             without the variable the seed must create no account at all, and the
             first user comes in through the first-run screen.
             """
    end
  end
end
