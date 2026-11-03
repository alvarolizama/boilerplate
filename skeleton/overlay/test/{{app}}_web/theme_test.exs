defmodule {{App}}Web.ThemeTest do
  # Touches the app env (THEME lives there), so not async.
  use ExUnit.Case, async: false

  alias {{App}}Web.Theme

  setup do
    previous = Application.fetch_env(:{{app}}, :theme)

    on_exit(fn ->
      case previous do
        {:ok, value} -> Application.put_env(:{{app}}, :theme, value)
        :error -> Application.delete_env(:{{app}}, :theme)
      end
    end)
  end

  test "defaults to dim when THEME is unset" do
    Application.delete_env(:{{app}}, :theme)
    assert Theme.current() == "dim"
  end

  test "honors a compiled theme" do
    Application.put_env(:{{app}}, :theme, "synthwave")
    assert Theme.current() == "synthwave"
  end

  test "an unknown theme falls back to dim instead of leaving the app unstyled" do
    Application.put_env(:{{app}}, :theme, "not-a-theme")
    assert Theme.current() == "dim"
  end

  test "an empty THEME is the default" do
    Application.put_env(:{{app}}, :theme, "")
    assert Theme.current() == "dim"
  end

  test "the compiled set in app.css matches Theme.themes/0" do
    css = File.read!("assets/css/app.css")

    line =
      css
      |> String.split("\n")
      |> Enum.find(&String.contains?(&1, "themes:"))

    assert line, "app.css carries no `themes:` line"

    names =
      line
      |> String.split("themes:", parts: 2)
      |> List.last()
      |> String.trim_trailing(";")
      |> String.split(",", trim: true)
      |> Enum.map(fn name -> name |> String.split() |> List.first() end)

    assert Enum.sort(names) == Enum.sort(Theme.themes())
  end
end
