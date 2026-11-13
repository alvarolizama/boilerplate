# BOOTSTRAP.md — how an app of the family is born

A mechanical procedure, with the traps already seen. The order matters: **the
specs first, the code after.**

1. `README.md` (index) → `SPEC-design.md`, `SPEC-config.md`, `SPEC-docker.md`.
2. `VERSIONS.md` — what gets pinned.
3. `bash skeleton/bootstrap.sh <target>` (this guide).
4. `mix precommit` + the release smoke test (`SPEC-docker.md` §Verification
   before pushing).

## One command

```bash
bash skeleton/bootstrap.sh /path/to/<app>
```

The arguments are strict: `--app` requires a value, an unknown option and a
second positional are refused — always message + `usage`, always exit 2.
Exit codes: `0` ok · `2` usage · `3` the target is already an Elixir project ·
`4` a collision with existing files (nothing was written) · `5` structural
failure (unsupported `phx.new` scheme, failed validation or the ignore gate).

In order, it:

| Step | What |
|---|---|
| 1 | scheme gate (installer must be 1.8.x, else exit 5) + `mix phx.new <scratch> --app <app> --binary-id --no-install --no-version-check`; the generated dev `secret_key_base` / `signing_salt` are re-pinned to values derived from the app name (see traps) |
| 2 | the final tree is materialized in a STAGING dir inside the same scratch: scaffold (incl. its `.gitignore`) — **the target is not touched yet** |
| 3 | copies `skeleton/overlay/**` replacing `{{app}}` / `{{App}}` / `{{APP}}` and **fails (exit 5) if any placeholder or any unknown `{{token}}` is left** in an overlay file (an existing `README.md` is kept, never clobbered) |
| 4 | applies the family's themes: `themes: <the 35 built-ins, dim --default>` in `app.css`, deletes the scaffold's themes/variant, sets `data-theme={Theme.current()}` in `root.html.heex` (reads `THEME`), deletes the inline switcher, adds `favicon.svg` to `static_paths` |
| 5 | adds the probe routes — `GET /health` **and** `GET /ready` in one pipeline-free scope. A recognized legacy probe is MOVED OUT of `:browser` into that scope; an unknown probe action/options fails closed |
| 6 | validates the staged tree (theme set, `data-theme`, favicon, BOTH routes): any structural failure is exit 5 **before a single write lands in the target** |
| 7 | refuses collisions with the target's existing files (exit 4, nothing written) and then copies once — `mix.exs` last, as the commit marker |
| 8 | merges the family entries + `/.env` into `.gitignore` (kept and extended; restored from the scaffold when the target has none) and runs the ignore gate |

**It does not** (it prints this at the end): `mix deps.get`, create the
database, the first commit.

### What the overlay brings

| File | What it contributes |
|---|---|
| `README.md` | the product README skeleton (what it is, local run, configuration, production) — written only when the app has none |
| `.envrc` | the dev loader (direnv) so a copied `.env` actually loads in the scaffold |
| `Dockerfile` | the canonical multi-stage build (OOM guard, healthcheck, non-root, no `EXPOSE`) |
| `docker/entrypoint.sh` | `Release.setup` → `start`, `SKIP_MIGRATIONS=1` |
| `.dockerignore` | includes `priv/static/uploads/` (an audit finding in a live app) |
| `.env.example` | the complete variable template |
| `.tool-versions` | the toolchain pin (`elixir`, `erlang`) — `VERSIONS.md` §Toolchain |
| `config/runtime.exs` | env vars, fail-closed boot, database TLS, `CHECK_ORIGINS` |
| `config/prod.exs` | `cache_static_manifest`, the `force_ssl` gate, Swoosh |
| `lib/<app>/release.ex` | idempotent `setup/0` · `create/0` · `migrate/0` · `seed/0` |
| `lib/<app>_web/endpoint.ex` | the family session block (`renew: true`, distinct salts) |
| `lib/<app>_web/theme.ex` | `Theme.current/0`: validates `THEME` against the compiled set, falls back to `dim` |
| `lib/<app>_web/controllers/health_controller.ex` | DB-free `/health` liveness; `/ready` readiness with a bounded `SELECT 1` |
| `test/<app>_web/controllers/health_controller_test.exs` | pins liveness (200, no cookie) and readiness failure (503) without hiding DB access behind a sandbox owner |
| `test/<app>_web/theme_test.exs` | pins default `dim`, fallback and exact parity with the multiline CSS theme list |
| `test/<app>_web/endpoint_test.exs` | pins runtime session options and explicit proxy trust |
| `test/<app>/release_test.exs` | pins the production seed path and rejects committed seed credentials |
| `rel/overlays/bin/{migrate,setup,server}` + `.bat` | the release bins |
| `priv/repo/seeds_prod.exs` | documented stub for the production seed (opt-in) |
| `lib/<app>_web/router.ex` | **not an overlay**: the bootstrap inserts `GET /health` + `GET /ready` (one pipeline-free scope) |

## After the bootstrap

```bash
cd <app>
cp .env.example .env && $EDITOR .env     # SECRET_KEY_BASE, DATABASE_URL, BOTH salts
direnv allow
mix deps.get
mix ecto.create
mix compile --warnings-as-errors
mix precommit
```

And for the UI: copy the Commons (`../DESIGN.md`) as-is + your
`## Custom — <App>` section (mechanics in `SPEC-design.md` §Propagation).

## Traps (all seen for real)

- **`mix phx.new` PROMPTS to fetch deps and install assets.** The bootstrap
  passes `--no-install`, so the scaffold brings code only: an answer of "yes"
  (or a changed default) would leave `deps/` and `assets/node_modules/` in the
  scratch dir, and the staging copy — which excludes only `.git` and
  `README.md` — would carry them into the app.
- **`mix phx.new` aborts over a non-empty directory and has no `--force`.** That
  is why the scaffold goes to a scratch and the final tree is staged there
  before anything is copied — and why the app's repo keeps its own `README.md`
  (product, in English) and its `.gitignore`.
- **`mix phx.new` writes a RANDOM `secret_key_base` and `signing_salt` on every
  run.** Left alone, a retry would never match the target's copies and the
  collision check would refuse it. The stage pins values derived from the app
  name (sha256, distinct per app and per file). They are committed dev
  placeholders anyway — prod reads the real values from the environment, and
  `mix phx.gen.secret` remains the way to produce them.
- **A run that dies mid-copy is retried as-is, without cleaning up.** Nothing
  is written until the staged tree has passed validation; the copy refuses any
  existing file whose content differs (exit 4, with the list, BEFORE writing)
  and treats already-identical files as retry noise; `mix.exs` is written last
  as the commit marker, so a dead run never leaves a tree that looks finished.
  There is no FORCE flag: differing files are preserved or removed by hand.
- **The overlay's `README.md` only lands when the app has none.** Same rule as
  the trap above, extended to the template: `bootstrap.sh` skips it when
  `$TARGET/README.md` already exists (it prints `kept (already in the target)`),
  so bootstrapping into a repo with its own product README never clobbers it.
  The sections that README must carry: `SPEC-readme.md`.
- **Generator config does not reach the DDL.** `generators: [binary_id: true]`
  only applies to what `mix phx.gen.*` produces: a migration written by hand
  with `create table(:users)` still emits `id bigint`, and the
  `references(..., type: :binary_id)` die with "uuid and bigint". Always write
  `create table(:x, primary_key: false) do add :id, :binary_id, primary_key: true …`
  and `timestamps(type: :utc_datetime_usec)`.
- **The scaffold's theme switcher overrides the selected theme.** It is an inline
  `<script>` that writes `data-theme` from `localStorage`: if it stays, the app
  boots in `light`/`dark` depending on the system. `bootstrap.sh` deletes it —
  verify with
  `grep -n 'phx:theme' lib/<app>_web/components/layouts/root.html.heex` → 0.
  The theme is `THEME` at runtime (`Theme.current/0`), never `localStorage`.
- **`THEME` only picks among the COMPILED themes.** daisyUI resolves themes at
  build time: a name missing from the `themes:` list in `app.css` (or from
  `@themes` in `lib/<app>_web/theme.ex`) falls back to `dim` and logs a warning.
  Adding a theme = both lists, then rebuild the assets.
- **`~p"/favicon.svg"` does not compile until the route is in `static_paths/0`**
  (`lib/<app>_web.ex`): the warning
  `no route path for <App>Web.Router matches "/favicon.svg"` looks like a
  routing bug. With `--warnings-as-errors` it breaks the gate. The bootstrap
  already adds it.
- **The scaffold's `{{…}}` are legitimate HEEx**, not placeholders: the
  bootstrap's check only looks at the overlay files, and its pattern is
  restrictive — a bare `{{identifier}}` (`{{appp}}` fails the run; the HEEx
  `{{id, msg} <- @streams.messages}` never matches).
- **The scaffold's `.gitignore` is restored when the target has none** — it is
  NOT dropped. When the target has its own, it is kept and extended. Either
  way `/.env` joins the family entries (`.riel/`, `/priv/static/uploads/`,
  `erl_crash.dump`), and the ignore gate enforces the result:
  `git check-ignore` must ignore `.env`, `deps/<app>` and `_build/<app>` and
  must NOT ignore `.env.example` (a foreign `.gitignore` without `/deps/` and
  `/_build/` fails the gate — extend it by hand).
- **Both probe routes are inserted, never just one.** `GET /health` (liveness)
  and `GET /ready` (readiness, `HealthController.ready`) live in the same
  pipeline-free scope; validation fails the run if either route is missing
  from the staged router. The `ready/2` action comes from the overlay's
  `health_controller.ex` — the compile gate catches a mismatch.
- **The production seed does not exist in the scaffold.** `Release.seed/0`
  evaluates `priv/repo/seeds_prod.exs`: the overlay creates it as a stub and
  `seed/0` does not fail when the file is missing (an app with no first account
  must still boot).
- **In `:prod`, `assets.deploy` BEFORE `compile` dies** with
  `Can't resolve 'phoenix-colocated/<app>/colocated.css'` — colocated assets are
  generated while compiling. Correct order (the Dockerfile's):
  `mix deps.get --only prod` → `mix compile` → `mix assets.deploy` → `mix release`.
- **A local Postgres without TLS needs `ECTO_SSL=false`.** The skeleton's default
  is SSL on (for managed databases); against a local Postgres the symptom is
  misleading: `failed to connect: ** (Postgrex.Error) ssl not available` and
  `failed to create db for <App>.Repo: "killed"` (the `"killed"` is the dropped
  TLS connection, not the database).
- **`Release.setup/0` runs on EVERY deploy.** Anything touching the database goes
  wrapped in `Ecto.Migrator.with_repo/2` (during `bin/<app> eval` the supervision
  tree is not started) and `storage_up/1` returns `{:error, :already_up}` (an
  atom) or the legacy tuple: both have to be matched.
- **`Application.compile_env` + `runtime.exs` abort the boot** with "has a
  different value set for key … during runtime". A key that `runtime.exs` sets
  is read with `Application.get_env/2` in `start/2`, never in a module attribute.
- **Do not put domain in the skeleton.** If your app needs `WEBHOOK_SECRET` or
  another required variable, it goes in **its own** `runtime.exs` — the skeleton
  must boot with the five required variables of `SPEC-config.md` and nothing
  else.

## Bootstrap gates

| Gate | Command | Expected |
|---|---|---|
| phx.new scheme | (the bootstrap itself) | installer is 1.8.x — anything else exits 5 |
| Placeholders | (the bootstrap itself) | 0 placeholders AND 0 unknown `{{tokens}}` in the overlay files |
| Structure | (the bootstrap itself) | theme set (`dim --default`), `data-theme`, favicon.svg and BOTH probe routes present in the staged tree |
| Collisions | (the bootstrap itself) | 0 differing files — exit 4 lists them and nothing is written |
| Ignores | `git -C <app> check-ignore -- .env deps/<app> _build/<app>` | all ignored; `.env.example` NOT ignored (else exit 5) |
| Compiles | `mix compile --warnings-as-errors` | no warnings of its own |
| Suite | `mix test` | 0 failures |
| Release | `MIX_ENV=prod mix release` + `ls _build/prod/rel/<app>/bin` | `<app>`, `migrate`, `server`, `setup` exist |
| Smoke | `bin/<app> eval "IO.puts(:ok)"` with the 5 required vars | `:ok` |
| Real setup | `bin/<app> eval "<App>.Release.setup"` against Postgres | creates the database, migrates, seeds |

## When the standard changes

- A change in the **Commons** (`DESIGN.md`) → it propagates into the apps'
  `DESIGN.md` (by copying).
- A change in the **skeleton** → it is made here; live apps are **not**
  re-synced on their own: what applies is ported by hand (the `SPEC-*.md` files
  say what is contract and what is domain).
