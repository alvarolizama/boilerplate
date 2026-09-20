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

In order, it:

| Step | What |
|---|---|
| 1 | `mix phx.new <scratch> --app <app> --binary-id --no-install --no-version-check` |
| 2 | `rsync` of the scaffold into the target (keeps the repo's `README.md` and `.gitignore`) |
| 3 | copies `skeleton/overlay/**` replacing `{{app}}` / `{{App}}` / `{{APP}}` and **fails if any placeholder is left** |
| 4 | merges the family entries into `.gitignore` (`.riel/`, `/priv/static/uploads/`, `erl_crash.dump`) |
| 5 | applies the `dim` theme: `themes: dim --default` in `app.css`, deletes the scaffold's themes/variant, sets `data-theme="dim"` in `root.html.heex`, deletes the inline switcher, adds `favicon.svg` to `static_paths` |
| 6 | adds the `GET /health` route to the router (a scope with no pipeline, outside `:browser`) |

**It does not** (it prints this at the end): `mix deps.get`, create the
database, the first commit.

### What the overlay brings (18 files)

| File | What it contributes |
|---|---|
| `Dockerfile` | the canonical multi-stage build (OOM guard, healthcheck, non-root, no `EXPOSE`) |
| `docker/entrypoint.sh` | `Release.setup` → `start`, `SKIP_MIGRATIONS=1` |
| `.dockerignore` | includes `priv/static/uploads/` (an audit finding in a live app) |
| `.env.example` | the complete variable template |
| `.tool-versions` | the toolchain pin (`elixir`, `erlang`) — `VERSIONS.md` §Toolchain |
| `config/runtime.exs` | env vars, fail-closed boot, database TLS, `CHECK_ORIGINS` |
| `config/prod.exs` | `cache_static_manifest`, the `force_ssl` gate, Swoosh |
| `lib/<app>/release.ex` | idempotent `setup/0` · `create/0` · `migrate/0` · `seed/0` |
| `lib/<app>_web/endpoint.ex` | the family session block (`renew: true`, distinct salts) |
| `lib/<app>_web/controllers/health_controller.ex` | `/health` that does not touch the database |
| `test/<app>_web/controllers/health_controller_test.exs` | pins the probe (200, no session) and goes red if `/health` queries the DB |
| `rel/overlays/bin/{migrate,setup,server}` + `.bat` | the release bins |
| `priv/repo/seeds_prod.exs` | documented stub for the production seed (opt-in) |
| `lib/<app>_web/router.ex` | **not an overlay**: the bootstrap inserts the `GET /health` route |

## After the bootstrap

```bash
cd <app>
cp .env.example .env && $EDITOR .env     # SECRET_KEY_BASE, DATABASE_URL, BOTH salts
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
  scratch dir, and the `rsync` — which excludes only `.git`, `README.md` and
  `.gitignore` — would copy them into the app.
- **`mix phx.new` aborts over a non-empty directory and has no `--force`.** That
  is why the scaffold goes to a scratch and is copied with `rsync` — and why the
  app's repo keeps its own `README.md` (product, in English) and its
  `.gitignore`.
- **Generator config does not reach the DDL.** `generators: [binary_id: true]`
  only applies to what `mix phx.gen.*` produces: a migration written by hand
  with `create table(:users)` still emits `id bigint`, and the
  `references(..., type: :binary_id)` die with "uuid and bigint". Always write
  `create table(:x, primary_key: false) do add :id, :binary_id, primary_key: true …`
  and `timestamps(type: :utc_datetime_usec)`.
- **The scaffold's theme switcher overrides the fixed theme.** It is an inline
  `<script>` that writes `data-theme` from `localStorage`: if it stays, the app
  boots in `light`/`dark` depending on the system. `bootstrap.sh` deletes it —
  verify with
  `grep -n 'phx:theme' lib/<app>_web/components/layouts/root.html.heex` → 0.
- **`~p"/favicon.svg"` does not compile until the route is in `static_paths/0`**
  (`lib/<app>_web.ex`): the warning
  `no route path for <App>Web.Router matches "/favicon.svg"` looks like a
  routing bug. With `--warnings-as-errors` it breaks the gate. The bootstrap
  already adds it.
- **The scaffold's `{{…}}` are legitimate HEEx**, not placeholders: the
  bootstrap's check only looks at the overlay files
  (`:for={{id, msg} <- @streams.messages}`).
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
| Placeholders | (the bootstrap itself) | 0 placeholders in the overlay files |
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