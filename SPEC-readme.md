# SPEC-readme.md — the README artifact (index and product)

Status: draft v1 · boilerplate — spec-first
Applies to the family's **two** READMEs: this repo's `README.md` (the **index**)
and the `README.md` of every app born from `skeleton/` (the **product README**).

The **index** says where each thing lives; the **product README** says what that
app is, how it runs locally and how it is deployed. Each one hands off what it
does not own: the index does not duplicate the production guide, the product
README does not restate the standard.

## Role and location

| README | Lives in | Written by | Answers | Never |
|---|---|---|---|---|
| Index | this repo, root `README.md` | hand, here | what the standard is, the reading order, the rule, the map | teaches the deployment step by step: it points at the spec that owns each piece |
| Product | each app, root `README.md` | `skeleton/bootstrap.sh`, from `skeleton/overlay/README.md` | what the app is, how to run it, how to configure it, how to deploy it | restates the Commons or the container contract: it cites the spec section |

Both are **tracked files in their own repo** — unlike `.riel/`, which is local
state (`README.md` is a deliverable, the ledger is not).

## Hard rules (both)

1. **The doc reflects the artifact** — the golden rule of
   `SPEC-design.md` §Hard rules, applied to prose: every assertion can be
   pointed at (a file, a command, a spec section). A README that explains a
   mechanism no longer in the code is drift, not documentation.
2. **An index is never a copy.** What the README answers with a table *what
   you need → where it lives*, it never answers by pasting the content: two
   live versions of the same guide is the failure this repo exists to avoid.
3. **English.** The family's docs are English (commits are Spanish); the
   author's name is the only exception left with accents.
4. **Whitelabel in this repo.** The index and every spec name **no app of the
   family** — the IdP (Umbral) is the single product named, because it is the
   other side of a contract. The **product README names its own app**: that is
   its subject, not a leak.
5. **No `file:line` citations into another repo** — they break on the next
   commit of that repo. A cross-reference names a file plus a section
   (`SPEC-docker.md` §Ports), which is stable.
6. **The standard is edited here; an app's README is edited in that app.** The
   template changes here and reaches the next app born from `skeleton/`; a live
   app's README is its own and is never re-synced (`BOOTSTRAP.md` §When the
   standard changes).

## The index README (`README.md`) — the sections, in order

The subjects the index carries, in the order they are read:

```text
# boilerplate
  the repo in two pieces (DESIGN.md = the Commons · specs + skeleton = the portable layer)
## Reading order
## The rule: this repo is the source, a running app is never the template
## Two different cycles — do not confuse them
## Repo map
## Starting an app (summary)
## How to use DESIGN.md
## Going to production (where each piece lives)
## The theme
## Verifying an implementation
## Standard index
## Working on these projects — Riel
## Authorship
```

| Section | What it must state | Truth it points at |
|---|---|---|
| Reading order | one row per document in the root, in the order an agent reads them | the files that exist (`SPEC-*.md`, `VERSIONS.md`, `BOOTSTRAP.md`) |
| The rule | this repo is the single source; a running app is frozen as read-only reference; the portable/domain split | `SPEC-docker.md` §Known gaps |
| Two different cycles | Commons (copied byte-exact, evolves often) vs skeleton (used at birth, changes rarely) | `SPEC-design.md` §Propagation · `BOOTSTRAP.md` |
| Repo map | the directory tree with one comment per file | the tree itself |
| How to use `DESIGN.md` | adoption, propagation, split criterion, golden rule — as mechanics, not as the rules | `SPEC-design.md` |
| Going to production | the table *what you need → in which spec it lives*, with verified anchors | `SPEC-config.md` · `SPEC-docker.md` · `VERSIONS.md` |
| Standard index | the `C1..C12` + appendices map | `DESIGN.md` |
| Riel | how the family's tasks are driven (`.riel/` is local, never committed) | the `riel-*` skills |

The index **opens the reading order it lists**: it is row 1 of its own table.

## The product README — the sections, in order

```text
# <App>
  one sentence: what it is and who runs it
## What it is
## Stack
## Local development
## Configuration
## The UI standard
## Production
## Tests and gates
## Documentation          (optional — only when there is somewhere to send the reader)
```

The literal text is **`skeleton/overlay/README.md`** — one live version, not two:
this spec fixes the sections and what each owes, the template carries the prose.

| Section | What it must state | Truth it points at |
|---|---|---|
| What it is | the problem it solves, for whom, the workflow that matters | the app's own product docs |
| Stack | toolchain, Phoenix/LiveView, Postgres, the single `dim` theme, the release container | `.tool-versions` · `mix.exs` · `Dockerfile` |
| Local development | the copy-get-create-serve sequence, and `GET /health` as the probe | `BOOTSTRAP.md` §After the bootstrap |
| Configuration | the **five required vars** by name, the optional commons, and that `.env.example` is the complete template; the app's own variables live next to them | `SPEC-config.md` §Required in production · §Optional commons |
| The UI standard | `DESIGN.md` is the Commons copied as-is plus `## Custom — <App>`; the Commons is edited in the boilerplate repo, never in the app | `SPEC-design.md` |
| Production | **mandatory** — `PORT` vs **Ports Exposes**, the `/health` healthcheck (never `/`), migrations on every deploy (`Release.setup`), the first account and its first-run window, the HTTPS decision, the uploads volume when the app stores uploads | `SPEC-docker.md` §Ports · §Entrypoint · §Known gaps |
| Tests and gates | the command that closes the loop | `mix precommit` |
| Documentation | where the rest lives (product docs, API, MCP) — or the section is deleted | the app's own `docs/` |

**The production section is the one this spec exists for.** A README that stops
at "install and run" leaves the deployer with three known traps: the healthcheck
pointing at `/`, `PORT` disagreeing with the platform's **Ports Exposes**, and
the open first-run window (`SPEC-docker.md` §Known gaps).

## Where the product README comes from

- `skeleton/bootstrap.sh` materializes `skeleton/overlay/README.md` into the
  app, replacing `{{app}}` / `{{App}}` / `{{APP}}` like any other overlay file,
  and fails if a placeholder survives (same gate as the rest of the overlay).
- **An existing `README.md` is kept.** The scaffold's own README is excluded by
  the `rsync`, and the overlay writes the template only when the app has none:
  a repo that already has a product README is never clobbered.
- The template is a **starting point, not a standard to preserve**: the app
  keeps the sections that are still true and deletes the rest.

## Validation

```bash
# the app's README: the sections exist, in order, and none is left as a skeleton
grep -n '^## ' README.md                 # What it is · Stack · Local development ·
                                         # Configuration · The UI standard ·
                                         # Production · Tests and gates
grep -n 'Ports Exposes\|/health' README.md   # the production section is real, not a heading
grep -rn '{{' README.md                  # 0 — the bootstrap's placeholder gate

# the index: nothing in the root is orphaned
for f in DESIGN.md SPEC-*.md VERSIONS.md BOOTSTRAP.md; do
  grep -q "$f" README.md || echo "orphaned (no row in the index): $f"
done

# a cross-reference names a section that exists in the cited file
for s in Ports Entrypoint 'Known gaps'; do
  grep -q "^## $s" SPEC-docker.md || echo "broken anchor: SPEC-docker.md §$s"
done
```

## Cross-references

- `SPEC-config.md` §Required in production — the five variables the README names
- `SPEC-docker.md` §Ports · §Entrypoint · §Known gaps — the production section
- `SPEC-design.md` — the Commons and its propagation (the UI section)
- `BOOTSTRAP.md` §What the overlay brings — the template's place in the bootstrap
- `VERSIONS.md` — the versions the stack section does not repeat