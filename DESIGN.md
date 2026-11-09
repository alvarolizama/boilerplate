# DESIGN.md — UI system

The interface standard of the app family that shares **one single visual
language**. This document is the **Commons** — the shared base: theme and
tokens, layout, basic elements, composition, states, conventions and shell.

**How it is used:**

- Every app **copies this file as-is** into the root of its repo as its
  `DESIGN.md` and **appends at the end** its `## Custom — <App>` section with
  what is exclusive to that app.
- The Commons is **not edited** inside an app repo: it changes **here** and
  propagates by copying. If you change something here, change it in every
  `DESIGN.md`.

**Split criterion:** everything that can be shared lives in the **Commons**
(theme and brand, layout and responsive, shell/sidebar/menus, elements and
**buttons by context**, cards, tables, modals, search pickers, charts, states).
Custom is the exception, and each of its blocks says **why** it is not
shareable (mark the real difference, not the taste). If in doubt, it goes to the
Commons.

> **Golden rule of this doc: it reflects the code.** Everything asserted here
> must be pointable at in `lib/<app>_web/…` or `assets/css/app.css`. If the code
> changes, this file changes with it.

---

## C1. Principles

1. **Native daisyUI + Tailwind.** Do not invent components daisyUI already
   ships (`btn`, `card`, `table`, `badge`, `input`, `select`, `alert`, `modal`,
   `dropdown`, `tabs`). Custom CSS only for **global** conventions.
2. **One single live theme per app, chosen at runtime by `THEME`.** The family
   compiles its daisyUI set in `app.css` (`dim --default` plus the rest) and
   `root.html.heex` writes the chosen one into `data-theme`; the default's
   values are in **Appendix A**. No hardcoded hex/oklch in templates: always the
   theme vars.
3. **Reuse before creating.** Look at `*Web.CoreComponents` before writing
   markup by hand: inputs, tables, headers, icons are already there.
4. **Verifiable.** Every interactive control carries a stable `id` for tests
   (`has_element?/2`).

## C2. Theme and tokens

```css
/* assets/css/app.css */
@plugin "../vendor/heroicons";
@plugin "../vendor/daisyui" {
  /* ← the family's set: `dim` is the default, THEME picks any of the rest */
  themes: dim --default, light, dark, cupcake, bumblebee, emerald, corporate,
          synthwave, retro, cyberpunk, valentine, halloween, garden, forest,
          aqua, lofi, pastel, fantasy, wireframe, black, luxury, dracula, cmyk,
          autumn, business, acid, lemonade, night, coffee, winter, nord, sunset,
          caramellatte, abyss, silk;
}
```

```heex
<%!-- lib/<app>_web/components/layouts/root.html.heex --%>
<html data-theme={<App>Web.Theme.current()}>
```

`Theme.current/0` reads `THEME` (default `dim`), validates it against the
compiled set and falls back to `dim` with a warning on an unknown value. The
theme is therefore a **runtime** choice: switching it is a restart with another
`THEME`, never a rebuild.

**Scaffold rule:** if `app.css` came with `themes: false` + `@plugin
"…daisyui-theme"` blocks (the path varies with the `phx.new` version), those
blocks have to be **deleted** (plus the theme switcher's JS in
`root.html.heex`): they re-declare `light`/`dark` — one of them with
`default: true` — and override the family's set.

Semantic colors (ALWAYS use the vars, never hex/oklch by hand):

| Role | daisyUI utility | Var | Use |
|---|---|---|---|
| App background | `bg-base-100` | `--color-base-100` | base surface |
| Surface 2 | `bg-base-200` | `--color-base-200` | panels, row hover |
| Surface 3 | `bg-base-300` | `--color-base-300` | borders, chips |
| Text | `text-base-content` | `--color-base-content` | + `/50` `/40` for secondary |
| Primary | `btn-primary`, `text-primary` | `--color-primary` | main action, links |
| Secondary | `btn-secondary` | `--color-secondary` | brand accent |
| Accent | `btn-accent` | `--color-accent` | "extra" / active but not primary |
| Neutral | `badge-ghost` | `--color-neutral` | global / no state |
| Success | `badge-success` | `--color-success` | ok, active |
| Warning | `badge-warning` | `--color-warning` | warning / notice |
| Error | `badge-error`, `text-error` | `--color-error` | destructive |
| Info | `badge-info` | `--color-info` | informational |

Radii and borders come from the theme (`--radius-box`, `--radius-field`,
`--border`). Do not hardcode them.

**The theme rules.** Every color in the app — including the **theme logo's**
(favicon/icons that follow the theme) and the charts' — comes from the daisyUI
tokens of the theme in use; no view writes hex/oklch. Changing theme = setting
**`THEME`** (a restart, no rebuild) — the views are not touched and `app.css`
does not change. The default's values are in **Appendix A**; the rest are
daisyUI's own. The only exception is the **brand** colors (§C2.1), which do not
follow the theme.

### C2.1 Brand (logo and favicon)

Every app's mark is **the family's** and does not follow the theme's primary: it
uses the brand colors in a `#9fe88d → #62efbd` gradient (strokes) with
`#9fe88d` / `#62efbd` / `#6fbb5c` nodes and a `#c9f7be` core. They travel
together in the same commit: `priv/static/favicon.svg` (the source), `logo.png`
(512 with alpha) and `favicon.ico` (16/32/48). If the theme changes, the mark is
**not** recolored: the family's green is what makes the app recognizable.

## C3. Base layout

- The main content goes in a `<main>`; the **shell** (sidebar, drawer, rail) is
  family → **§C12** (each app declares only its sections and options).
- **Page header:** `<.header>` — title (`:inner_block`) + `:subtitle` +
  `:actions`.
- **Filters and actions, aligned to the RIGHT** (`:actions` slot or
  `justify-end`). Never to the left.
- **Wide containers** (tables/panels) wrapped in `overflow-x-auto`.

### C3.1 Responsive (mobile-first)

Every new surface is born usable on a phone; the desktop is the improvement, not
the starting point.

| Rule | How |
|---|---|
| **Shell breakpoint** | **`lg` (64rem)**: below it, navigation lives in the **drawer** (overlay + hamburger); above it, it is fixed and collapsible to a **rail** of icons (§C12) |
| **Content padding** | `p-4 pb-16 sm:p-6` — tighter on mobile |
| **Page headers** | `flex flex-wrap items-center justify-between gap-3`: actions wrap to the next line on small screens |
| **Tables** | always `overflow-x-auto` (§C6): they scroll horizontally, they never break the layout |
| **Grids** | mobile-first: `grid-cols-1 sm:grid-cols-2 lg:grid-cols-3`; **never** start at 2+ columns |
| **Widths** | `w-full min-w-0`; `max-w-*` is for modals and text, not for content |
| **Modals** | overlay `p-4` + card `w-full max-w-*`; the metadata columns are `hidden md:flex` (§C7.2) |
| **Text** | no hard truncation outside tables/cells; truncated text carries a `title` |
| **Actions** | `btn-xs`+ (touch target); row actions keep their `title` (§C6) |

## C4. Basic elements

The primitive controls. Everything else (cards, tables, modals, pickers) is
composed from these.

| Element | Standard class |
|---|---|
| Primary button | `btn btn-primary` (or `<.button variant="primary">`) |
| Secondary button | `btn btn-primary btn-soft` (default of `<.button>`) |
| Neutral / cancel button | `btn btn-ghost` |
| Row action | `btn btn-xs btn-ghost` (+ `title=`) |
| Destructive | `btn ... text-error` + `data-confirm="…"` |
| Badge | `badge badge-sm` + semantic (`badge-primary/success/warning/error/info/ghost/outline/accent`) |
| Removable chip | `badge badge-sm` with an inner `<button>` |
| Text input | `<.input field={@form[:x]} />` (never a hand-written `<input>`) |
| Icon | `<.icon name="hero-…" class="size-4" />` (heroicons, NOT a loose SVG) |
| Toast (flash) | `toast toast-top toast-end z-50` + `alert alert-info/alert-error` |

**Everything goes through `CoreComponents`** — do not build the `<input>` or the
flash by hand:

- `flash` · `button` (with `variant="primary" | nil`) · `input` · `header` ·
  `table` · `list` · `icon` · `show`/`hide` · `translate_error`/`translate_errors`.

**Navigation and surface primitives** (also in `CoreComponents`, so that every
LiveView has them through `use <App>Web, :html`, with no imports):

| Component | What it is | Attributes |
|---|---|---|
| `<.nav_link>` | sidebar/rail link: icon + label + badge | `label` · `icon` · `path` · `active` · `badge` |
| `<.nav_group>` | group label + its links | `label` + slot |
| `<.menu_item>` | menu entry (dropdown, user menu) | `href` · `icon` · `label` · `active` |
| `<.section>` | section: box with header (badge + title + caption) | `title` · `icon` · `caption` + slot |
| `<.modal>` | compact modal (C7.1): ✕ / Escape / click-away | `id` · `title` · `on_close` · `max_w` + slot (the caller gates it with `:if`) |
| `<.empty_state>` | the canonical empty state (C6) | `icon` · `title` · `caption` · `class` + CTA slot |

They were born in admin/settings and in the shell, and were promoted to
`CoreComponents` so that no second copy exists: if a screen needs a nav link, a
section, a modal or an empty state, **use the shared component** — do not write
new markup, and no local helper.

### C4.1 Buttons by context

The same `btn` changes shape depending on where it lives; there is no single
"standard button":

| Context | Shape |
|---|---|
| **Page CTA (create)** | `<.button phx-click="new_x" id="new-x-btn">` + `hero-plus` icon (default = `btn-primary btn-soft`); the kebab id `new-*-btn` is the test anchor |
| **Form submit** | `<button type="submit" class="btn btn-primary btn-sm">` (solid: there the solid is the form's CTA) |
| **Cancel / close** | `btn btn-ghost btn-sm` |
| **Row action** | `btn btn-xs btn-ghost` + `title` (§C6) |
| **Destructive** | `btn … text-error` + `data-confirm="…? This action cannot be undone."` |
| **Filter / period toggle** | `btn-ghost`; active `btn-primary` |
| **Another path** (social sign-in) | `btn btn-outline` |
| **Navigation** | `<.nav_link>` (§C12.3) |

**`btn-outline` is legitimate for "another path"** — the same hierarchy as the
primary one, an alternative route (e.g. "Continue with Google"), not a color
variant.

## C5. Cards

One single shape for a "box" across the family.

```heex
<div class="card bg-base-100 border border-base-300 shadow-sm">
  <div class="card-body p-4">
    <h2 class="card-title text-base">
      <.icon name="hero-…" class="size-5 text-base-content/60" />
      Title
    </h2>
    …
  </div>
</div>
```

- **Base:** `card bg-base-100 border border-base-300 shadow-sm` + `card-body`.
- **`card-body` density** (choose according to the content): `p-4` (dense: lists,
  KPIs) · `p-5` (medium) · `p-6` (forms) · `p-8` (hero).
- **Title:** `card-title text-base` + icon `size-5 text-base-content/60`.
- **Interactive card (clickable):** `hover:shadow-md transition-shadow`.
- **Section card with header** (icon badge + title + caption): each app defines
  its own section box in **Custom**.
- **Modal card:** `shadow-xl` instead of `shadow-sm` (see C7).
- Shadows and radii from the theme (`--radius-box`, `shadow-sm/md/xl`); not by
  hand.

**The same card depending on where it is:**

| Place | Shape |
|---|---|
| Page / section with header | each app's section box (icon badge + title + caption; see **Custom**) |
| Table container | `card` + `overflow-x-auto` (§C6) |
| List / rows | dense `card-body p-4`, row hover, no zebra |
| KPI / stat | `card-body p-4`, number `text-2xl font-semibold`, secondary label |
| Modal | `shadow-xl` + `card-body p-6` (§C7) |
| Empty state | centered `card` with `<.empty_state>` (§C10) |

## C6. Tables

Canonical structure (one single shape across the family):

```heex
<div class="overflow-x-auto card bg-base-100 border border-base-300 shadow-sm">
  <table class="table table-sm">
    <thead>
      <tr>
        <th>…</th>
        <th class="text-right">Actions</th>
      </tr>
    </thead>
    <tbody id="things" phx-update="stream">
      <tr :for={{id, t} <- @streams.things} id={id}>
        <td>…</td>
        <td class="text-right">
          <button phx-click="edit" phx-value-id={t.id} class="btn btn-xs btn-ghost" title="Edit">
            <.icon name="hero-pencil" class="size-3.5" />
          </button>
        </td>
      </tr>
    </tbody>
  </table>
</div>
```

Rules:

- **`table table-sm` always.** Wrapped in `overflow-x-auto` + card. Fixed-width
  columns: `table table-sm table-fixed w-full`.
- **Row hover, no zebra** — a global rule, once per app:
  ```css
  .table tbody tr { transition: background-color 150ms ease; }
  .table tbody tr:hover { background-color: color-mix(in oklab, var(--color-base-200) 60%, transparent); }
  ```
- **Collections with `stream` + `phx-update="stream"`** (never large assigned
  lists). Each row's `id` is the item's.
- **Actions column** at the end, `btn-xs btn-ghost` with `title`.
- **Empty state** (outside the table):
  ```heex
  <div :if={@things_empty?} class="text-center py-12 text-base-content/40">
    <.icon name="hero-…" class="size-10 mx-auto mb-2 opacity-40" />
    <p>No … yet.</p>
  </div>
  ```
- **Raw data never on screen:** own formatters (dates, prices), never a raw
  `Decimal`.

## C7. Modals

The standard pattern = an overlay `div`, **not `<dialog>`**. Closing = flipping
the assign back.

### C7.1 Simple modal (one column)

```heex
<div :if={@show_modal?} class="fixed inset-0 z-50 flex items-center justify-center p-4" id="thing-modal">
  <div class="absolute inset-0 bg-black/50" phx-click="cancel_form" />

  <div class="relative card bg-base-100 border border-base-300 shadow-xl w-full max-w-2xl">
    <div class="card-body p-6">
      <h2 class="text-lg font-semibold mb-4">New …</h2>
      <.form for={@form} id="thing-form" phx-submit="save">
        …
        <div class="flex gap-2 mt-6 justify-end">
          <button type="button" phx-click="cancel_form" class="btn btn-ghost btn-sm">Cancel</button>
          <button type="submit" class="btn btn-primary btn-sm" id="save-thing">Save</button>
        </div>
      </.form>
    </div>
  </div>
</div>
```

### C7.2 Two-column modal (content + metadata sidebar)

For large forms (creating/editing a resource): header (pill + title + ✕),
**two-column body** — main content + a metadata `<aside>` (`w-80 lg:w-96`,
`hidden md:flex`, its own scroll) — and footer. Almost full-screen.

```heex
<div :if={@show_modal?} id="thing-modal-overlay"
     class="fixed inset-0 z-50 flex items-center justify-center bg-black/60 p-4 sm:p-6"
     phx-window-keydown="cancel_form" phx-key="Escape">
  <div id="thing-modal" role="dialog" aria-modal="true" phx-click-away="cancel_form"
       class="card bg-base-100 border border-base-300 shadow-2xl w-full flex flex-col overflow-hidden
              h-[calc(100vh-3rem)] sm:h-[calc(100vh-4rem)] max-w-5xl">
    <%!-- Header --%>
    <div class="flex items-center justify-between px-5 py-3.5 border-b border-base-300 shrink-0">
      <div class="flex items-center gap-2.5 min-w-0">
        <span class="text-[11px] font-semibold px-2 py-0.5 rounded-full shrink-0 bg-primary/10 text-primary">Resource</span>
        <h3 class="text-base font-semibold truncate">New …</h3>
      </div>
      <button type="button" phx-click="cancel_form" class="btn btn-ghost btn-xs btn-circle" aria-label="Close">
        <.icon name="hero-x-mark" class="size-4" />
      </button>
    </div>

    <%!-- Body: content + sidebar --%>
    <div class="flex-1 min-h-0 flex overflow-hidden">
      <div class="flex-1 min-w-0 overflow-y-auto p-6">
        <.form for={@form} id="thing-form" phx-submit="save">…</.form>
      </div>
      <aside class="hidden md:flex md:flex-col w-80 lg:w-96 shrink-0 border-l border-base-300 bg-base-200/40 overflow-y-auto p-5 gap-4">
        <h4 class="text-xs font-semibold uppercase tracking-wider text-base-content/50">Details</h4>
        …
      </aside>
    </div>

    <%!-- Footer --%>
    <div class="flex items-center justify-between px-5 py-3 border-t border-base-300 shrink-0">
      <div class="flex items-center gap-2">{render_slot(@left)}</div>
      <div class="flex items-center gap-2">
        <button type="button" phx-click="cancel_form" class="btn btn-ghost btn-sm">Cancel</button>
        <button type="submit" form="thing-form" class="btn btn-primary btn-sm">Save</button>
      </div>
    </div>
  </div>
</div>
```

- The **Save button lives OUTSIDE the `<form>`** (in the footer) and points at it
  with the HTML attribute `form="thing-form"` → the `id` must match the
  `<.form>`'s.
- The **metadata sidebar** is `hidden md:flex` (hidden on mobile) and scrolls
  independently (`overflow-y-auto`).

Rules (both):

- **Visible only when the assign exists** (`:if={@form != nil}` /
  `@show_modal?`).
- **Close by backdrop `phx-click` + Escape**
  (`phx-window-keydown` + `phx-key="Escape"`).
- **Widths:** `max-w-md` (confirmations) · `max-w-lg` · `max-w-2xl` (forms) ·
  `max-w-5xl` (two-column modals).
- **Destructive confirmations:** `data-confirm="…? This action cannot be
  undone."` on the button.
- **The verb says what the button does, not the color:** a close ("Cancel",
  "← Back") does not travel in the CTA row, and joining a resource is not
  labeled "Create". The primary/secondary pair expresses hierarchy; the label,
  the action.

## C8. Search pickers and selects

Choose the control with the matrix: how many values? × is the list large (does
it need search)?

| | **1 value** | **N values** |
|---|---|---|
| **Few** (≤ ~10, no scroll) | **C8.1 select** | **C8.5 toggleable badges** |
| **Many** (search) | **C8.3 single combobox** | **C8.4 multi combobox** |

For free text with suggestions (a long catalog, a custom value): **C8.2
datalist**.

### C8.1 Plain select (1 value, no search)

`<.input type="select" options={…} prompt="…" />` — the native `<select>`
(`w-full select`). For a standalone select outside a form:
`<select class="select select-bordered select-sm w-full">`.

```heex
<.input field={@form[:owner_id]} type="select" prompt="Pick…" options={@owner_options} />
```

### C8.2 Datalist (free text + suggestions)

`<.input type="datalist" options={…} />` — a text input with a `<datalist>`: the
person picks from the list **or** types any value.

```heex
<.input field={@form[:model]} type="datalist" label="Model" options={@catalog} />
```

### C8.3 Single combobox (1 value, with search)

The reference implementation is Sebka's timezone picker (`OnboardingLive` +
`SebkaWeb.Timezones`). Assigns: `<kind>_query` (typed text), `<kind>_open`
(bool), `<kind>_active` (keyboard cursor), `selected_<kind>` (chosen value).

The flow: **closed until focus; filter per keystroke; arrows navigate; Enter or
click picks; the pick completes the box and CLOSES; Escape and click-away
close.**

```heex
<div class="relative">
  <input type="text" id="<kind>-search" name="<kind>_query" role="combobox"
    aria-controls="<kind>-list" aria-expanded={to_string(@<kind>_open)}
    value={@<kind>_query} placeholder="Search…"
    phx-focus="open_<kind>" phx-keyup="<kind>_search" phx-keydown="<kind>_key"
    phx-hook=".<Kind>Autocomplete" autocomplete="off"
    class="input input-sm w-full" />
  <script :type={Phoenix.LiveView.ColocatedHook} name=".<Kind>Autocomplete">
    export default {
      mounted() {
        // LiveView never patches the value of a typed-into input: the server
        // echoes the pick and the hook completes the box.
        this.handleEvent("<kind>-selected", ({ value }) => { this.el.value = value; });
      },
    };
  </script>

  <%= if @<kind>_open do %>
    <%!-- Click-away catcher (the drawer-overlay pattern). --%>
    <div class="fixed inset-0 z-20" phx-click="close_<kind>" aria-hidden="true"></div>

    <ul id="<kind>-list" role="listbox" aria-label="Options"
        class="absolute z-30 mt-1 w-full menu menu-sm bg-base-100 border border-base-300
               rounded-box shadow-lg max-h-48 overflow-y-auto">
      <li :for={{item, i} <- @<kind>_visible} role="option"
          aria-selected={to_string(item.id == @selected)}
          class={i == @<kind>_active && "bg-base-200"}>
        <button type="button" phx-click="pick_<kind>" phx-value-id={item.id}>
          <.icon name={item.id == @selected && "hero-check" || "hero-map-pin"}
                 class="size-4 opacity-60" />
          {item.label}
        </button>
      </li>
    </ul>
  <% end %>
</div>
```

Server side — filter rides `phx-keyup` (the payload carries the input's
`value` per keystroke), nav keys ride `phx-keydown`, and the pick is merged
**server-side** into the submit params:

```elixir
def handle_event("<kind>_search", %{"value" => query}, socket), do: …   # filter + reset cursor
def handle_event("<kind>_key", %{"key" => "Enter"}, socket), do: …      # pick active, close
def handle_event("pick_<kind>", %{"id" => id}, socket), do: …           # same, from a click

def handle_event("submit", %{"thing" => params}, socket) do
  # merge the picked value from socket assigns — never from the DOM
  params = Map.put(params, "owner_id", socket.assigns.selected_owner_id)
  …
end
```

### Combobox hard rules (they come from real bugs)

1. **`phx-change` never fires on a standalone (form-less) input — with or
   without `name`.** The suite stays green anyway (`render_change` injects the
   event straight into the server, skipping the DOM): the arbiter is the
   **server log** — a live websocket with no `HANDLE EVENT` line means the
   binding never fires. For type-to-filter bind **`phx-keyup`** (its payload
   carries the input's `value` per keystroke); nav keys ride
   **`phx-keydown`**. Inside a real `<form>`, `phx-change` +
   `phx-debounce` (200 search · 300 autocomplete) remains the pattern.
2. **LiveView never patches the `value` of an input the user typed into —
   including hidden inputs.** A pick stored in socket assigns must be merged
   into the submit params server-side, and any visible box that must
   "complete" after a server pick needs `push_event` + the colocated hook
   (`handleEvent` sets `this.el.value`).
3. **Single pick = mirror the label + close.** **Multi pick = accumulate + stay
   open** (C8.4).
4. **Click-away = a fixed full-screen overlay catcher** behind the dropdown
   (`fixed inset-0 z-20` + `phx-click="close_…"`, list at `z-30`) — the
   drawer-overlay pattern. Core LiveView has **no `phx-click-away`**.
5. **Escape closes and clears the query without touching the picked value.**
6. Cap the rendered rows (~60) with a "N more — refine the search" hint, and
   default the keyboard cursor (highlighted row) to the first suggestion.

### C8.4 Multi combobox (N values, with search)

Same as the single one, but the pick does **NOT** close and it **accumulates**
ids (`current_<kind>_ids`); the chosen ones are shown as **chips** below the
input (each chip with its own `<button>`/remove icon) and a `✓` on the active
row.

```heex
<div :if={@current_owner_ids != []} class="flex flex-wrap gap-1 mt-2">
  <span :for={id <- @current_owner_ids}
    class="badge badge-sm badge-primary gap-1 cursor-pointer"
    phx-click="toggle_owner" phx-value-id={id}>
    {label_for(id)} <.icon name="hero-x-mark" class="size-3" />
  </span>
</div>
```

### C8.5 Toggleable badges (N values, no search)

For short lists (permissions): `badge` buttons that toggle. State: selected =
`badge-primary` (`badge-accent` for "extra"); free = `badge-outline` + hover.

```heex
<button :for={m <- @models} type="button"
  phx-click="toggle_model" phx-value-id={m.id}
  class={["badge badge-sm transition-all",
          m.id in @granted_ids && "badge-primary",
          m.id not in @granted_ids && "badge-outline cursor-pointer hover:badge-primary/50"]}>
  {m.name}
</button>
```

## C9. Charts

**There is no charting library.** In the family charts are **hand-written SVG in
HEEx** (or bars with `style="height: …%"`); the data is **preprocessed in
Elixir** and the scales are computed on the **server**.

```heex
<%!-- Canonical bar chart: card + svg --%>
<div id="usage-chart" class="card bg-base-100 border border-base-300 shadow-sm">
  <div class="card-body">
    <h2 class="card-title text-base">
      <.icon name="hero-chart-bar" class="size-5 text-base-content/60" /> Usage
    </h2>
    <div :if={@series == []} class="h-40 flex items-center justify-center text-base-content/40 text-sm">
      No data
    </div>
    <div :else class="flex">
      <div class="flex flex-col justify-between text-[10px] text-base-content/50 pr-1 h-40 text-right w-8">
        <span :for={l <- @y_labels}>{l}</span>
      </div>
      <svg viewBox="0 0 400 150" class="flex-1 h-40" preserveAspectRatio="none">
        <rect :for={{row, i} <- Enum.with_index(@series)} x={10 + i * (@bar_width + 4)}
              y={140 - max(row.value / @max_value * 120, 1)} width={@bar_width}
              height={max(row.value / @max_value * 120, 1)} rx="2" class="fill-primary transition-colors">
          <title>{row.label} — {row.tooltip}</title>
        </rect>
        <line x1="10" y1="140" x2="390" y2="140" class="stroke-base-300" stroke-width="1" />
      </svg>
    </div>
  </div>
</div>
```

Rules:

- **No JS charting dependencies** (no apexcharts/echarts/chart.js/d3).
- **Scales on the server:** Elixir helpers (e.g. a `sqrt` scale with a 4% floor
  for bars; a linear scale for the sparkline). The template only paints.
- **Container:** SVG with `viewBox` + `preserveAspectRatio="none"` and a fixed
  height (`h-40`, `h-8`); or bars with `style="height: …%"` inside a fixed
  height.
- **Series color:** from a **named** palette defined in the app (a map of named
  constants, never the hex repeated at the call site). If the color identifies a
  kind of data, it travels in the kind's data — not in a per-slug case table.
- **Axes and labels:** `text-[10px]`/`text-xs`, `text-base-content/40-50`,
  `tabular-nums` on the values.
- **Tooltip:** `<title>` inside the SVG node (or `title=` on the bar).
- **Empty state:** a container of the same height with centered text
  (`text-base-content/40`).
- **Sparkline:** `<svg viewBox="0 0 200 30">` + `<polyline points=… fill="none"
  stroke="currentColor" class="text-primary/40" stroke-width="1.5">`.
- **Hover:** subtle highlight (`group-hover:brightness-110`), no re-render.

## C10. States

| State | Standard |
|---|---|
| Loading | `.skeleton` (shimmer) or `loading loading-spinner` |
| Empty | icon + centered text (`text-base-content/40`) |
| Error | inline `text-error`, or `alert alert-error` |
| Success | flash `alert-info` (toast top-end) |

## C11. Conventions

- **Stable `id`** on every key control (forms, buttons, rows) → `has_element?/2`.
  Form: `id="thing-form"`; row: `id={id}` (from the stream). **The `id` is the
  family's primary convention.**
- **`data-testid` only where there is no natural id:** containers and states
  with no `<form>`/row/stream behind them. `kebab-case`, the variable part last
  after a hyphen, and never as a replacement for an `id` that already exists.
  **Every new testid is born with its consumer in `test/`**: a testid no test
  reads is noise.
- **Assigns per picker:** `<kind>_search` / `<kind>_open` / `current_<kind>_id(s)`.
- **Filters** aligned to the **right** of the header, always.
- **Modals** = an overlay div; closed through an assign.
- **Raw data never on screen:** formatters.
- **Theme:** theme vars only; zero hardcoded hex/oklch (in HEEx and in the JS
  hooks: use `cssColor("--color-…", fallback)`, never a fixed hex).
- **i18n:** `Gettext`.
- An app's gate is **`mix precommit`** (an alias in `mix.exs`).

## C12. Shell (sidebar, navigation and menus)

The family's shell is **sidebar + content bar** (no desktop topbar). Every app
declares its sections and options in **Custom**; the mechanics are these.

### C12.1 Structure

- Root `h-screen` + **daisyUI `drawer lg:drawer-open lg:grid-rows-1 h-full`**.
  **Both** `lg:` classes are structural: the row one has its own hard rule in
  **§C12.5** (without it the whole shell scrolls).
- **The content bar (`h-14`), always visible: it is the ONLY place for the
  navigation toggle.** Below `< lg` it is the hamburger
  (`label for="app-drawer"`) that opens the drawer; at `≥ lg`, the same button
  in the same position collapses/expands the sidebar
  (`label for="sidebar-collapse"`). **Never two controls**: the sidebar carries
  no chevron of its own. Below `< lg` the bar is **`sticky top-0 z-30
  lg:static`**: there the document scrolls, and a static bar takes the only
  toggle off screen with long content — the hamburger must stay reachable
  (§C12.5.4).
- **Mobile (`< lg`):** the sidebar lives in the drawer (`drawer-side` +
  `drawer-overlay`); closing = overlay or navigating. The drawer is not
  persisted.
- **Desktop (`≥ lg`):** fixed sidebar, **collapsible to an icon rail** (4rem)
  with the `#sidebar-collapse` checkbox (a sibling of `.drawer`): it narrows,
  the texts with `.shell-hide` disappear (brand, selector, search, link and
  group labels, badges, name/email) and **logo + icons** remain, centered, with
  `title` (tooltip). The sidebar is **not** hidden and no floating button is
  used: a `fixed` one covers the page title. In the rail the user menu opens to
  the right and `.drawer-side` loses its clipping (`overflow: visible`) — the
  scroll is carried by the aside's inner `<nav>`.
- Sidebar `w-60 shrink-0 border-r border-base-300 bg-base-200 lg:bg-base-200/50
  flex flex-col` — **opaque below `lg`** (§C12.5.4), translucent only where the
  aside is sticky over the `base-100` root.
  Density: header `p-3`, search `p-3`, nav `flex-1 overflow-y-auto p-2 flex
  flex-col gap-4`, footer `p-3 border-t` with
  `max-lg:pb-[calc(0.75rem+env(safe-area-inset-bottom))]` (§C12.5.4).

### C12.2 Sidebar anatomy

| Zone | Content |
|---|---|
| header | logo + wordmark · context selector (`select select-xs`) |
| search | the context's GET form with a `⌘K` hint |
| nav | always-visible entries + groups (`<.nav_group>`) |
| footer | `<.user_footer>`: avatar + name/email + menu |

### C12.3 Navigation and menus

- **`<.nav_link>`**: `btn lg:btn-sm w-full justify-between font-normal`
  (40px tap targets below `lg` — the drawer is the primary navigation there;
  32px `btn-sm` intact in the desktop rail); inactive
  `btn-ghost text-base-content/80`; **active `bg-primary/15 text-primary
  font-medium hover:bg-primary/20` + `aria-current="page"`**. Do **not** use
  `btn-primary btn-soft` for the active one: it mixes only 8% of the color with
  `base-100` and the pill reads gray. Badge `badge badge-sm` (ghost; primary when
  active). `title` with the label — it is the rail's tooltip.
- **`<.nav_group>`**: label `text-xs font-semibold uppercase tracking-wider
  text-base-content/70`, `px-3 pt-1 pb-1`; groups with `gap-4`, links with
  `gap-1`.
- **User menu** (`#user-menu`, `<.menu_item>`), anchored bottom-left:
  **Workspaces** (→ `/`, always: it is the way back to the listing from any
  URL) · Profile · API keys · *(divider, only with a context)* the context's
  entries · *(divider)* Log out. The active entry: `aria-current="page"` +
  `text-primary`.
- **No duplicated navigation:** if the sidebar already leads to a section, the
  page does not repeat it inside; context actions go in the user menu, not in
  the nav. A page's identity is given by its `<h1>` + caption.

### C12.4 Content padding

The layout sets it: `p-4 pb-16 sm:p-6`. The `pb-16` is the closing air of the
scroll (the last card never sticks to the edge). Never leave content without
padding.

### C12.5 Shell hard rules (they come from real bugs)

1. **The `.drawer` row is bounded: `lg:grid-rows-1`.** daisyUI's `drawer` is a
   grid and declares **only `grid-auto-columns`**: the row stays **implicit** and
   its height is decided by `grid-auto-rows` (default `auto`), so **it inflates
   with the page content**. With long content the WHOLE shell scrolls — the
   content bar and the sidebar go with the wheel, and `main` is left without its
   own scroll — instead of the content scrolling inside while the sidebar stays
   fixed. There are **two equivalent levers** and the family uses both: the
   utility in the markup (`lg:grid-rows-1`, which works because daisyUI already
   ships `grid-row-start: 1` on both children) or the rule in `app.css`
   (`grid-auto-rows: minmax(0, 1fr)` on `.drawer`, which is the general one — it
   also holds if the row were truly implicit, with auto-placed items).
   **One of the two, never neither.** `repeat(1, minmax(0, 1fr))` bounds the row
   to the viewport: the `minmax(0, …)` is what allows shrinking below the
   content. **`lg` scope**, not negotiable: below `< lg` the `.drawer-side` is a
   `position: fixed` overlay and there is no column to bound (mobile behaves the
   same with and without the class).
2. **Do not cover it with `overflow: hidden` on `.drawer`.** The row would keep
   growing (clipping does not bound the size) and it would kill the rail's user
   menu, which opens to the right and needs `overflow: visible` on
   `.drawer-side` (§C12.1).
3. **The one that scrolls is `main`** (`flex-1 min-h-0 overflow-y-auto`), not the
   document. The content bar (`h-14 shrink-0`) and the sidebar stay fixed.
4. **The drawer panel is OPAQUE below `lg`: `bg-base-200 lg:bg-base-200/50`.**
   Below `lg` the `.drawer-side` is a `position: fixed` overlay — nothing
   opaque sits behind the aside, so an alpha-only background composites with
   the page content and the text reads through (measured with the compiled
   `dim` theme at 390px: ΔL ≈ 11 against the panel; at `≥ lg` the aside is
   sticky over the `base-100` root and the same `…/50` composites to ΔL ≈ 1.4 —
   invisible). The opaque stop and the sticky stop share the `lg` breakpoint on
   purpose: that is exactly where the panel stops floating. Verify by computed
   style, not by eye — at 390px
   `getComputedStyle(aside).backgroundColor` carries NO alpha; at 1280px it
   keeps `/ 0.5`. A markup test asserts the tokens (`bg-base-200` present,
   bare `bg-base-200/50` absent); it is a lock on the markup, not on the
   cascade.

How it is verified (it is measured, not looked at) — with the **compiled** CSS
and long content, at 1440×900 and 1280×800, expanded and in rail mode:

- `documentElement.scrollHeight == innerHeight` (the document does not scroll);
- `main.scrollHeight > main.clientHeight` (the scroll lives inside `main`);
- with the **window** scrolled 400px, the sidebar's `getBoundingClientRect().top`
  is still `0` and so is the content bar's.

Measurement of the real case (2968px of content, 900px window): **without** the
class, drawer row `3024px`, document `3024`, `main` `2968/2968` (no inner scroll)
and sidebar `top: -400` with the window scrolled; **with** the class, row `900`,
document `900`, `main` `844/2968` with inner scroll, and sidebar `top: 0` /
bottom `900`. The same in rail mode (sidebar 240 → 64px) and no differences on
mobile 500×800.

---

## Appendix A — the `dim` theme (default, reference values)

`dim` is the family's default (`THEME` unset). The other compiled themes are
daisyUI's built-ins: their values are not copied here.

Source of truth: the `oklch()` values the plugin emits in
`priv/static/assets/css/app.css`. The hex values are an approximate conversion
(no gamut mapping), only to read the table. Contrast = WCAG for the pair with
its `*-content`.

| Token | oklch | ≈hex | Role · contrast |
|---|---|---|---|
| `--color-base-100` | `oklch(30.857% 0.023 264.149)` | `#2a303c` | app background |
| `--color-base-200` | `oklch(28.036% 0.019 264.182)` | `#242933` | panels / row hover |
| `--color-base-300` | `oklch(26.346% 0.018 262.177)` | `#20252e` | chips, borders |
| `--color-base-content` | `oklch(82.901% 0.031 222.959)` | `#b2ccd6` | main text · text 7.9:1 vs base-100 |
| `--color-primary` | `oklch(86.133% 0.141 139.549)` | `#9fe88d` | **main action** (default button) · 13.0:1 |
| `--color-secondary` | `oklch(73.375% 0.165 35.353)` | `#ff7d5d` | brand accent · 7.9:1 |
| `--color-accent` | `oklch(74.229% 0.133 311.379)` | `#c792e9` | "extra" accent · 8.2:1 |
| `--color-neutral` | `oklch(24.731% 0.02 264.094)` | `#1c212b` | dark panels/chips · 9.6:1 |
| `--color-success` | `oklch(86.171% 0.142 166.534)` | `#62efbd` | ok, active · 13.2:1 |
| `--color-warning` | `oklch(86.163% 0.142 94.818)` | `#efd057` | notice · 12.5:1 |
| `--color-error` | `oklch(82.418% 0.099 33.756)` | `#ffae9b` | destructive · 10.8:1 |
| `--color-info` | `oklch(86.078% 0.142 206.182)` | `#28ebff` | informational · 13.0:1 |

`*-content` pairs: `primary-content` `oklch(17.226% 0.028 139.549)` ·
`secondary-content` `oklch(14.675% 0.033 35.353)` · `accent-content`
`oklch(14.845% 0.026 311.379)` · the rest of the semantics carry their pair too.

Theme shape: `color-scheme: dark` · radii `box 1rem` / `field 0.5rem` /
`selector 1rem` · `--border 1px` · `--depth 0` · `--noise 0`.

> **The primary paints every default button.** `CoreComponents.button/1` without
> `variant` emits `btn-primary btn-soft`, so the primary's color is the expected
> one, not a CSS bug. For another color use the explicit utility
> (`btn-secondary`, `btn-accent`) — do **not** redefine the theme's primary.

## Appendix B — verifying an implementation

Adapt the paths to your repo. Every grep corresponds to a rule in the doc:

```bash
grep -n 'data-theme' lib/<app>_web/components/layouts/root.html.heex    # Theme.current() (§C2)
grep -n 'themes:' assets/css/app.css                                    # the compiled set, `dim --default` (§C2)
grep -n 'THEME' config/runtime.exs                                      # the runtime knob (§C2)
grep -rn '@apply' assets/css/                                           # 0
grep -rn 'table-zebra' lib/                                             # 0 (no zebra, §C6)
grep -rn 'overflow-x-auto' lib/                                         # wide tables/panels wrapped (§C3)
grep -c 'for="sidebar-collapse"' lib/<app>_web/components/layouts.ex    # 1 (single toggle, §C12.1)
grep -c 'class="drawer lg:drawer-open[^"]*lg:grid-rows-1' lib/<app>_web/components/layouts.ex  # 1 (drawer row bounded, §C12.5)
grep -c 'grid-auto-rows: minmax(0, 1fr)' assets/css/app.css             # 1 if the lever is CSS (§C12.5)
grep -c 'aside[^>]*label for="sidebar' lib/<app>_web/components/layouts.ex  # 0 (the sidebar carries no toggle of its own)
grep -rn 'p-4 sm:p-6\|p-4 pb-16 sm:p-6' lib/                            # mobile-first padding (§C3.1)
grep -rnE '#[0-9a-fA-F]{3,6}\b' lib/ assets/css/app.css                 # 0 outside brand (§C2.1) and named palettes (§C9)
mix tailwind <app> && grep -c 'data-theme=dim' priv/static/assets/css/app.css  # ≥1: dim is compiled (§C2)
```
