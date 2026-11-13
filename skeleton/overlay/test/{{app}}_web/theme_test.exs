defmodule {{App}}Web.ThemeTest do
  # Touches the app env (THEME lives there), so not async.
  use ExUnit.Case, async: false

  alias {{App}}Web.Theme

  @css_path "assets/css/app.css"

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

  describe "app.css" do
    test "compiles exactly the themes Theme.themes/0 knows" do
      compiled = compiled_themes!()
      expected = Theme.themes()

      assert length(compiled) == length(Enum.uniq(compiled)),
             """
             the daisyUI `themes:` list repeats a name: #{inspect(compiled)}
             A repeat makes daisyUI drop or override the duplicate silently.
             """

      assert compiled -- expected == [],
             """
             app.css compiles themes Theme.themes/0 does not know: #{inspect(compiled -- expected)}
             Either add them to @themes in lib/{{app}}_web/theme.ex, or delete them
             from the daisyUI block in #{@css_path} (§C2).
             """

      assert expected -- compiled == [],
             """
             Theme.themes/0 lists themes app.css does not compile: #{inspect(expected -- compiled)}
             Either add them to the daisyUI `themes:` list in #{@css_path}, or remove them
             from @themes in lib/{{app}}_web/theme.ex — otherwise `THEME=<name>` renders an
             unstyled app.
             """
    end

    test "marks exactly one theme --default, and it is the fallback Theme.current/0 uses" do
      defaults =
        for %{name: name, default?: true} <- parsed_themes!(), do: name

      assert length(defaults) == 1,
             """
             app.css must mark exactly one theme `--default` (found #{inspect(defaults)}).
             daisyUI takes the first marked theme as the app's default; two markers make the
             rendered theme depend on list order.
             """

      Application.delete_env(:{{app}}, :theme)

      assert hd(defaults) == Theme.current(),
             """
             drift between the CSS default and the module default:
               app.css `--default`: #{inspect(hd(defaults))}
               Theme.current/0 without THEME: #{inspect(Theme.current())}
             They must agree, or the app boots in one theme and the fallback lives in another.
             """
    end
  end

  # --- parsing ---------------------------------------------------------------

  defp compiled_themes!, do: Enum.map(parsed_themes!(), & &1.name)

  defp parsed_themes! do
    @css_path
    |> File.read!()
    |> daisyui_block!()
    |> themes_property!()
  end

  # The daisyUI block is the ONE `@plugin "…daisyui…" { … }`: a plain
  # `@plugin "…";` (the heroicons one) has no body. Braces are matched with a
  # scanner instead of a regex because a body may hold comments and strings.
  defp daisyui_block!(css) do
    blocks =
      css
      |> plugin_blocks()
      |> Enum.filter(&String.contains?(&1.path, "daisyui"))

    case blocks do
      [block] ->
        block.body

      [] ->
        flunk("""
        #{@css_path} declares no `@plugin "…daisyui…" { … }` block, so none of §C2's
        themes are compiled. Expected the family's block:

            @plugin "../vendor/daisyui" {
              themes: dim --default, light, dark, …;
            }
        """)

      many ->
        flunk("""
        #{@css_path} declares #{length(many)} daisyUI `@plugin` blocks:
        #{indent(Enum.map_join(many, "\n", & &1.path))}
        §C2 wants exactly one carrying the family's `themes:` list — a scaffold's leftover
        `@plugin "…daisyui-theme"` block re-declares light/dark and overrides it.
        """)
    end
  end

  defp plugin_blocks(css) do
    size = byte_size(css)

    for {at, _length} <- :binary.matches(css, "@plugin"),
        rest = binary_part(css, at, size - at),
        block = plugin_block(rest),
        block != nil,
        do: block
  end

  defp plugin_block("@plugin" <> rest) do
    with {path, rest} <- quoted(rest),
         {:ok, body} <- braces(rest) do
      %{path: path, body: body}
    else
      _ -> nil
    end
  end

  # `"…"` (a plugin path) → `{path, rest}`; `:error` when it is not a string.
  defp quoted(rest) do
    case String.trim_leading(rest) do
      "\"" <> tail ->
        case :binary.split(tail, "\"") do
          [path, rest] -> {path, rest}
          _ -> :error
        end

      _ ->
        :error
    end
  end

  # Skips whitespace, then returns the body of the `{ … }` that follows, with
  # nested braces balanced and comments/strings skipped so their braces do not
  # count. `:error` when there is no block (`@plugin "x";`).
  defp braces(rest) do
    case String.trim_leading(rest) do
      "{" <> tail -> take_block(tail, 1, [])
      _ -> :error
    end
  end

  defp take_block("", _depth, _acc), do: :error

  defp take_block("/*" <> tail, depth, acc) do
    case :binary.split(tail, "*/") do
      [_comment, rest] -> take_block(rest, depth, acc)
      _ -> :error
    end
  end

  defp take_block("\"" <> tail, depth, acc) do
    case :binary.split(tail, "\"") do
      [string, rest] -> take_block(rest, depth, ["\"", string, "\"" | acc])
      _ -> :error
    end
  end

  defp take_block("{" <> tail, depth, acc),
    do: take_block(tail, depth + 1, ["{" | acc])

  defp take_block("}" <> _rest, 1, acc),
    do: {:ok, acc |> Enum.reverse() |> Enum.join() |> String.trim()}

  defp take_block("}" <> tail, depth, acc),
    do: take_block(tail, depth - 1, ["}" | acc])

  defp take_block(<<char::utf8, tail::binary>>, depth, acc),
    do: take_block(tail, depth, [<<char::utf8>> | acc])

  # The `themes:` property may wrap over any number of lines, carry comments
  # between entries, and end its `;` on a line of its own. Comments are blanked
  # first (keeping their newlines), then the property is read up to the `;`.
  defp themes_property!(body) do
    stripped = blank_comments(body)

    case Regex.run(~r/\bthemes\s*:\s*([^;]*?)\s*(?:;|\z)/s, stripped) do
      [_, list] ->
        if String.trim(list) in ["false", "true"] do
          flunk("""
          #{@css_path} sets `themes: #{String.trim(list)}` — daisyUI's themes are switched
          off (the scaffold's leftover `@plugin "…daisyui-theme"` shape). §C2 requires the
          family's `themes:` list with `dim --default`, and those light/dark blocks deleted.
          """)
        end

        entries =
          list
          |> String.split(",")
          |> Enum.map(&String.trim/1)
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&entry!/1)

        if entries == [] do
          flunk("""
          #{@css_path} declares `themes:` with an empty list — the app would render
          with daisyUI's built-in default and no family theme.
          """)
        end

        entries

      nil ->
        flunk("""
        the daisyUI `@plugin` block in #{@css_path} has no `themes: …;` property.
        Block body:
        #{indent(body)}
        """)
    end
  end

  # `name` or `name --default` — anything else is a typo the CSS parser would
  # swallow silently.
  defp entry!(raw) do
    tokens = String.split(raw)

    valid? =
      Regex.match?(~r/^[A-Za-z][A-Za-z0-9-]*(\s+--?[A-Za-z0-9-]+)*$/, raw) and tokens != []

    unless valid? do
      flunk("""
      cannot parse the daisyUI theme entry #{inspect(raw)} in #{@css_path}.
      Expected `name` or `name --default`; entries are comma-separated and may wrap
      across lines. A stray character here silently drops a theme from the build.
      """)
    end

    %{name: hd(tokens), default?: "--default" in tokens}
  end

  # Keeps the newlines so line numbers in flunk messages stay meaningful.
  defp blank_comments(css),
    do: Regex.replace(~r/\/\*.*?\*\//s, css, &String.replace(&1, ~r/[^\n]/, " "))

  defp indent(text) do
    text
    |> String.split("\n")
    |> Enum.map_join("\n", &("      " <> &1))
  end
end
