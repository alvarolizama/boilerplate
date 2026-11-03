defmodule {{App}}Web.Theme do
  @moduledoc """
  The daisyUI theme the app renders with (`DESIGN.md` §C2).

  The theme is chosen at **runtime** with the `THEME` environment variable:
  `assets/css/app.css` compiles the family's set of themes and
  `root.html.heex` writes the chosen one into `data-theme`. Switching themes
  therefore needs no rebuild — only a restart with another `THEME`.

  An unknown value falls back to `dim` (the family's default) and logs a
  warning: a typo never leaves the app unstyled.
  """

  require Logger

  # Keep in sync with the `themes:` list that `skeleton/bootstrap.sh` writes
  # into `assets/css/app.css`. `dim` is the family's default.
  @themes ~w(dim light dark cupcake bumblebee emerald corporate synthwave retro
             cyberpunk valentine halloween garden forest aqua lofi pastel fantasy
             wireframe black luxury dracula cmyk autumn business acid lemonade
             night coffee winter nord sunset caramellatte abyss silk)

  @default "dim"

  @doc "The themes compiled into the CSS."
  def themes, do: @themes

  @doc "The theme in use, validated against the compiled set."
  def current do
    case configured() do
      "" -> @default
      theme when theme in @themes -> theme
      other -> fallback(other)
    end
  end

  defp configured do
    :{{app}}
    |> Application.get_env(:theme, @default)
    |> to_string()
    |> String.trim()
  end

  defp fallback(other) do
    # Once per boot: `current/0` runs on every layout render, and a bad THEME
    # must not flood the log with one warning per request.
    unless :persistent_term.get({__MODULE__, :warned}, false) do
      :persistent_term.put({__MODULE__, :warned}, true)

      Logger.warning(
        "THEME=#{inspect(other)} is not a compiled theme; falling back to " <>
          "#{@default}. Compiled: #{Enum.join(@themes, ", ")}"
      )
    end

    @default
  end
end
