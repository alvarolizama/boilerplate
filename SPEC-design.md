# SPEC-design.md — how the Commons lands in code

## Scope

`DESIGN.md` in this repo **is** the standard: ~34 KB, sections `## C1..C12`
plus `## Appendix A` (values of the `dim` theme) and `## Appendix B`
(verification). This spec does not repeat its rules: it says **which file
implements each rule**, how it is verified, and how it propagates into an app.

An agent about to touch UI reads, in this order: `DESIGN.md` (the section that
applies), this spec (the map to files), and the UI code of the reference
implementation (frozen, read-only).

## Hard rules

1. **The Commons is byte-exact.** An app's `DESIGN.md` starts with the Commons
   copied as-is, and only then comes `## Custom — <App>`.
2. **One single live version.** The Commons is edited **here**; never inside an
   app repo. If an app needs something different, that is a change to the
   Commons.
3. **The doc reflects the code** (golden rule): every assertion in the Commons
   can be pointed at in `lib/<app>_web/…` or `assets/css/app.css`.
4. **Custom declares exceptions, not taste**, and every block says *why* it is
   not shareable. It does not duplicate Commons tables (`dim` palette, buttons
   by context): it points at §C2.1 / Appendix A.
5. **One single theme `dim --default`**, no `@apply` in CSS, no `table-zebra`.

## Rule → file map

The paths are app-side (the scaffold's plus the ones the Commons prescribes);
the portable layer in `skeleton/` does not carry UI components.

| Rule | Where it must exist |
|---|---|
| §C2 Theme and tokens | `assets/css/app.css`: `@plugin "../vendor/daisyui" { themes: dim --default; }` — and `data-theme="dim"` on `<html>` in `lib/<app>_web/components/layouts/root.html.heex` |
| §C2 Icons | `assets/css/app.css`: `@plugin "../vendor/heroicons"` |
| §C2.1 Brand | `<.live_title>` in `root.html.heex`; static routes in `lib/<app>_web.ex` (`static_paths`, `favicon.svg` included) |
| §C4 Primitives | `lib/<app>_web/components/core_components.ex`: `flash`, `button`, `input` (styled per the Commons, not the scaffold's defaults) |
| §C6 Tables | `core_components.ex`: `table` |
| §C7.1 Simple modal | `core_components.ex`: `modal` — overlay + card, close by ✕, Escape (`phx-window-keydown`) and click-away — **pure LiveView, no `<dialog>`**, no internal state |
| §C12 Shell | `lib/<app>_web/components/layouts.ex`: `app/1`, root `drawer lg:drawer-open`, `drawer-side`, `user_footer` |
| §C12.5 Shell hard rules | the comments that explain the rule live next to the code (`layouts.ex`, in `app/1`) |

For the §C8 combinations (search pickers and selects) the LiveView mechanics
come from the `liveview-ui-wiring` skill; the Commons fixes the control matrix
and the hard rules (`DESIGN.md` §C8, §Combobox hard rules).

## Verification

Appendix B of `DESIGN.md` carries the greps; adapt the paths to your repo. The
three that break most often:

```bash
grep -n 'data-theme' lib/<app>_web/components/layouts/root.html.heex   # the declared theme (§C2)
grep -n 'themes:' assets/css/app.css                                   # a single --default theme (§C2)
grep -rn 'table-zebra\|@apply' lib/ assets/css/                        # 0 (§C2, §C6)
```

## Propagation into an app

1. Split the reference `DESIGN.md` at the `## Custom —` heading (the Commons
   runs up to there) and paste the block above into the app's `DESIGN.md`.
2. Fix the sentences inside the Commons that name an app (paths in
   `root.html.heex`, which theme each app runs): they are corrected, not
   annotated.
3. Write `## Custom — <App>` with what is exclusive (its own shell, the role of
   its tokens, its brand, screens no other app has).
4. Verify the Commons came out identical: the app's `DESIGN.md` must start with
   the Commons as-is — mechanically, with
   `bash skeleton/check-commons.sh <app-dir> [<app-dir>…]`: it compares the
   Commons above `## Custom —` against this repo's `DESIGN.md`, ignores the
   prescribed `---` separator, and exits 1 when an app drifted. Read-only.
5. Atomic commits, separating UI from docs.

## Anti-patterns

- **A Custom that contradicts the Commons** (e.g. prescribing a topbar when
  §C12 requires sidebar + drawer). The Commons wins.
- **Duplicating the `dim` table** in Custom: that creates two live versions.
- **Citing §Custom from the Commons**: the Commons' numbers do not change when
  it is copied; the references are §C12, §C12.3, §S4…
- **Editing the Commons inside an app repo**: the change is lost at the next
  propagation.