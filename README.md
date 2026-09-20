# boilerplate

The app-family standard, in two pieces:

- **`DESIGN.md`** — the **Commons**: the complete UI standard (theme and tokens,
  layout and responsive, elements and buttons by context, cards, tables, modals,
  search pickers, charts, states, conventions and shell). Sections `## C1..C12`
  plus Appendices A/B.
- **The specs + `skeleton/`** — the portable layer of a Phoenix app: env vars,
  Dockerfile, entrypoint, healthcheck, `mix` aliases, and the skeleton ready to
  be materialized.

This repo is **spec-first**: the documents are read first, and only then does
code get touched. Any agent landing on an app of the family starts here.

## Reading order

| # | File | What it settles |
|---|---|---|
| 1 | `README.md` (this) | what the repo is, the rule, the map |
| 2 | `SPEC-design.md` | how the Commons lands in code and how it is verified |
| 3 | `SPEC-config.md` | env vars, session/cookies, DB-backed settings |
| 4 | `SPEC-docker.md` | Dockerfile, entrypoint, healthcheck, ports |
| 5 | `SPEC-auth.md` | how people get in: password, Google, SSO — all optional — plus profiles |
| 6 | `SPEC-identity.md` | the SSO mode with the family IdP (Umbral), in detail |
| 7 | `VERSIONS.md` | pinned versions (toolchain, images, deps) |
| 8 | `BOOTSTRAP.md` | how an app is born, step by step |
| 9 | `skeleton/` | the portable layer already materialized, with placeholders |

Every spec is **self-contained**: the contract and the snippets that matter are
quoted where they belong, so nothing here depends on reading a file outside this
repo.

## The rule: this repo is the source, a running app is never the template

**This repo is the single source of truth for the standard.** Its first version
was distilled from a production app of the family; from then on that app stays
**frozen as a read-only reference** and is never modified to serve as a
template. When the standard changes, it changes **here** and is ported outward.

The reason is concrete: a running app drags domain that a skeleton must not
inherit. Copying it wholesale leaves a new app that **does not boot** (a
domain-required variable is a `raise` in its `runtime.exs`) and that ships
partitioned tables it does not need.

| Layer | What it holds | Where it goes |
|---|---|---|
| **Portable** | domain-free Dockerfile, `docker/entrypoint.sh`, `config/*.exs`, the endpoint session block, `release.ex`, DB-free `/health`, `.dockerignore`, `.env.example`, `mix` aliases | `skeleton/` → a new app |
| **App domain** | proxy + gzip, webhooks, partitioned tables, notifications, budgets, provider catalog, Oban crons, vector search/inference, upload pipeline | stays in that app |

## Two different cycles — do not confuse them

| Cycle | What changes | How it propagates |
|---|---|---|
| **Commons** (`DESIGN.md`) | the UI standard, which evolves often | edited here and copied **byte-exact** into each app's `DESIGN.md` (plus `## Custom — <App>`); never edited inside an app repo |
| **Skeleton** (`skeleton/`) | the portable layer, which changes rarely | used **when an app is born** (`BOOTSTRAP.md`); live apps are not re-synced on their own |

**Nothing is ported into an app on its own initiative.** What an app is missing
lives as backlog in `SPEC-docker.md` §Known gaps, with the exact anchor, and is
ported when it is decided — the standard first, the app second.

## Repo map

```text
boilerplate/
├── DESIGN.md          # the Commons (UI standard) — source
├── README.md          # this index
├── SPEC-design.md     # Commons → files → verification → propagation
├── SPEC-config.md     # env vars, session, DB-backed settings
├── SPEC-docker.md     # container, entrypoint, healthcheck, ports
├── SPEC-auth.md       # sign-in modes (password, Google, SSO) + profiles
├── SPEC-identity.md   # the SSO mode with Umbral, in detail
├── VERSIONS.md        # pinned versions
├── BOOTSTRAP.md       # birthing an app (mechanical procedure)
└── skeleton/          # portable layer with <app>/<App>/<APP> placeholders
```

## Starting an app (summary)

```bash
bash skeleton/bootstrap.sh /path/to/<app>
```

`bootstrap.sh` materializes the skeleton, replaces the placeholders and leaves
the app compiling. The detail, the traps and the exact order are in
`BOOTSTRAP.md`.

## How to use `DESIGN.md`

### Adopting it in an app

1. **Copy `DESIGN.md` as-is** into the root of your app's repo.
2. **Append at the end** your own section with what is exclusive to that app:

   ```md
   ## Custom — <App>
   ```

   Every block of your Custom says **why** it is not shareable (mark the real
   difference, not the taste).
3. **Apply what the doc says** in code: the theme in `app.css` (§C2), the
   primitives in `CoreComponents` (§C4), the shell (§C12), etc. — the map to
   files is in `SPEC-design.md`.

### Keeping it current when the Commons changes

- The Commons is edited **here** (a PR in this repo), never inside an app repo.
- On merge, the change propagates by **copying the block** into the apps'
  `DESIGN.md`: there cannot be two live versions of the same Commons.
- If you change the Commons, change it in **every** `DESIGN.md`.

### Split criterion

Everything that can be shared goes to the **Commons**; **Custom** is the
exception. If in doubt, it goes to the Commons — that way the next app inherits
it for free.

### Golden rule

The doc **reflects the code**: everything it asserts can be pointed at in
`lib/<app>_web/…` or `assets/css/app.css`. If the code changes, the doc changes
with it.

## Going to production (where each piece lives)

This repo is an index: the production guide is not duplicated here, it lives in
the spec that owns each piece.

| What you need | Where it is |
|---|---|
| Env vars **required in production** (the boot dies without them) | `SPEC-config.md` §Required in production |
| Optional vars with their defaults | `SPEC-config.md` §Optional commons |
| Ready-to-copy template with every variable and a safe default | `skeleton/overlay/.env.example` (materialized into the app as `.env.example`) |
| Container: build/runtime stages, ports, healthcheck, the `force_ssl` gate | `SPEC-docker.md` §Build stage · §Runtime stage · §Ports |
| First deploy (create DB → migrate → seed) and the first account | `SPEC-docker.md` §Entrypoint · `BOOTSTRAP.md` §After the bootstrap |
| Verifying before pushing (release, smoke, image) | `SPEC-docker.md` §Verification before pushing |
| Pinned versions (toolchain, images, deps) | `VERSIONS.md` |
| Auditing a live app against the standard | `SPEC-docker.md` §Known gaps |

Rule: **the skeleton boots with the five required variables of
`SPEC-config.md` and nothing else**; whatever an app needs beyond that is
declared in its own `runtime.exs` (`SPEC-config.md` §The app's own variables).

## The theme

One line in `app.css` plus `data-theme` in `root.html.heex`. The family runs
daisyUI **`dim --default`** — the reference values are in Appendix A of the doc.
Changing the theme does not touch the views.

## Verifying an implementation

**Appendix B** of `DESIGN.md` carries the verification greps (adapt the paths to
your repo: for example `grep -rn 'table-zebra' lib/` must return 0). In Phoenix
apps, the gate is **`mix precommit`**.

## Standard index

| Section | What it covers |
|---|---|
| C1–C2 | Principles · theme and tokens · brand (logo and favicon) |
| C3 | Base layout and responsive (mobile-first) |
| C4 | Basic elements · **buttons by context** |
| C5–C7 | Cards · tables · modals (simple and two-column) |
| C8 | Search pickers and selects: control matrix + hard rules |
| C9–C11 | Charts · states · conventions |
| C12 | Shell: sidebar, navigation and menus · **hard rules** (drawer row, scroll) |
| Appendices | A: `dim` theme values · B: verification |

## Working on these projects — Riel

Work on the family's projects is driven with **Riel**, the agent-side protocol
that keeps a task's state outside the model and outside the chat:

- **`.riel/contract.md`** — the plan: a verb graph with pre-registered claims
  and the gate that closes each phase.
- **`.riel/ledger.md`** — the state: `Goal`, `Core`, `Verified` (each `✓NN`
  with its verifier and its coverage), `Open`, `Next` — re-read at every **seam**
  (a tool call, a file change, a context compaction, a session gap).
- **`.riel/` is local state**: it is in `.gitignore` and is never committed.
  One workstream = one worktree = one ledger.
- The mechanical helper is **`rielctl`** (`resume`, `seam`, `todo`, `clean`).

The skills that carry the protocol: `riel-protocol` (the entry point),
`riel-contract` (contracts), `riel-ledger` (ledgers), `riel-briefs` /
`riel-delegate` (delegation) and `riel-cli` (the CLI). Tasks are classified
**fast / full / loop**; only loop-mode tasks carry a ledger.

## Authorship

Álvaro Lizama. The Commons is distilled from the family's production standard;
the portable layer, from a production app of the family.