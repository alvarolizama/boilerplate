#!/usr/bin/env bash
#
# bootstrap.sh — materializes the family's portable layer into a new app.
#
#   bash skeleton/bootstrap.sh <target> [--app <name>]
#
# What it does:
#   1. gates the phx.new scheme (1.8.x only) and runs `mix phx.new` into a
#      scratch dir (--app <name> --binary-id --no-install)
#   2. materializes the FINAL tree in a staging dir inside the same scratch:
#      scaffold + overlay ({{app}} / {{App}} / {{APP}} replaced) + themes +
#      the /health and /ready routes — the target is not touched yet
#   3. validates the staged tree: no unknown {{token}} left in the overlay
#      files, the compiled theme set in app.css, data-theme in
#      root.html.heex, favicon.svg in static_paths, BOTH probe routes —
#      any structural failure exits nonzero BEFORE a single write lands
#      in the target
#   4. refuses collisions with the target's existing files (only README.md,
#      .gitignore and .git are deliberate exceptions — they are preserved)
#      and then copies once; files identical to the staged tree are not
#      collisions, so a run that died mid-copy is retried as-is. There is
#      no FORCE flag: remove the conflicting files by hand or abort.
#   5. merges the family entries and /.env into .gitignore — the target's
#      own is kept and extended; when the target has none, the scaffold's
#      is restored (it is NOT dropped anymore)
#   6. gates the ignore rules: git check-ignore must ignore .env, deps/<app>
#      and _build/<app>, and must NOT ignore .env.example (it stays tracked)
#
# It does not: `mix deps.get`, create the database, or the first commit. The
# remaining steps are printed at the end. Contract and traps: BOOTSTRAP.md.
#
# Exit codes: 2 usage or bad --app · 3 the target is already an Elixir
# project · 4 a collision with existing files (nothing was written) ·
# 5 structural failure (unsupported phx.new, failed validation or the
# ignore gate) · any other nonzero: a tool itself failed.

set -euo pipefail

OVERLAY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/overlay"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh <target> [--app <name>]

  <target>        the app's directory (created if it does not exist)
  --app <name>    OTP app name (default: the basename of the target)

Exit codes: 2 usage · 3 already an Elixir project · 4 collision with
existing files (nothing written) · 5 structural failure.
EOF
}

die() { # die <code> <message>
  echo "error: $2" >&2
  exit "$1"
}

TARGET=""
APP=""
APP_GIVEN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --app)
      [ $# -ge 2 ] || die 2 "--app requires a value"
      [ "$APP_GIVEN" -eq 0 ] || die 2 "--app given twice ('$APP' and '$2')"
      APP="$2"
      APP_GIVEN=1
      shift 2
      ;;
    --app=*)
      [ "$APP_GIVEN" -eq 0 ] || die 2 "--app given twice"
      APP="${1#*=}"
      APP_GIVEN=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    -*)
      die 2 "unknown option: $1"
      ;;
    *)
      [ -z "$TARGET" ] || die 2 "more than one target given ('$TARGET' and '$1')"
      TARGET="$1"
      shift
      ;;
  esac
done

[ -n "$TARGET" ] || { usage >&2; die 2 "missing <target>"; }

APP="${APP:-$(basename "$TARGET")}"

if ! printf '%s' "$APP" | grep -qE '^[a-z][a-z0-9_]*$'; then
  die 2 "invalid app name: '$APP' (lowercase letters, digits and _ ; must start with a letter)"
fi

CAMEL="$(printf '%s' "$APP" | python3 -c 'import sys; print("".join(p.capitalize() for p in sys.stdin.read().split("_")))')"
UPPER="$(printf '%s' "$APP" | tr '[:lower:]' '[:upper:]')"

[ -d "$OVERLAY" ] || die 2 "cannot find the overlay at $OVERLAY"

if [ -e "$TARGET" ] && [ ! -d "$TARGET" ]; then
  die 2 "$TARGET exists and is not a directory"
fi

if [ -f "$TARGET/mix.exs" ]; then
  echo "error: $TARGET is already an Elixir project (it has a mix.exs) — aborting" >&2
  exit 3
fi

mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
STAGE="$SCRATCH/stage"
mkdir -p "$STAGE"

echo "[1/8] scaffold: mix phx.new $APP (binary_id, no install)"
PHX_VERSION="$(mix phx.new --version 2>/dev/null || true)"
PHX_MM="$(printf '%s' "$PHX_VERSION" | sed -nE 's/.*v([0-9]+\.[0-9]+)\.[0-9]+.*/\1/p' || true)"
[ -n "$PHX_MM" ] || die 5 "cannot determine the phx.new installer version ('$PHX_VERSION') — the scaffold's schema cannot be verified"
[ "$PHX_MM" = "1.8" ] || die 5 "unsupported phx.new scheme: $PHX_VERSION (verified: 1.8.x) — update bootstrap.sh before generating"
echo "      installer: $PHX_VERSION (supported scheme: 1.8.x)"

# --no-install is explicit on purpose: phx.new PROMPTS to fetch deps and
# install assets, and a non-interactive run that answers "yes" (or a changed
# default) would leave deps/ and assets/node_modules/ in the scratch dir for
# the staging copy below to carry into the target. The scaffold must bring
# code only.
mix phx.new "$SCRATCH/gen/$APP" --app "$APP" --binary-id --no-version-check --no-install < /dev/null > /dev/null

echo "[2/8] staging the scaffold (nothing is written to $TARGET yet)"
rsync -a --exclude .git --exclude README.md "$SCRATCH/gen/$APP/" "$STAGE/"
# The scaffold's .gitignore is staged too: it lands in the target only when
# the target has none (an existing one is kept and merged into instead).
cp "$SCRATCH/gen/$APP/.gitignore" "$STAGE/.gitignore"

# phx.new writes a RANDOM secret_key_base and signing_salt into config/*.exs
# on every run. Left as-is, a retry would never match the target's copies and
# the collision check would refuse it. They are committed placeholders anyway
# (prod reads the real values from the environment), so the stage pins values
# derived from the app name: deterministic per app, distinct across apps.
python3 - "$STAGE" "$APP" <<'PY'
import hashlib
import os
import re
import sys

stage, app = sys.argv[1:3]
pinned = 0
for name in sorted(os.listdir(os.path.join(stage, "config"))):
    if not name.endswith(".exs"):
        continue
    path = os.path.join(stage, "config", name)
    with open(path, encoding="utf-8") as fh:
        text = fh.read()
    key = hashlib.sha256(f"{app}:{name}:secret_key_base".encode()).hexdigest()
    salt = hashlib.sha256(f"{app}:{name}:signing_salt".encode()).hexdigest()[:8]
    new = re.sub(r'((?:secret_key_base|signing_salt):\s*")[^"]+(")',
                 lambda m: m.group(1) + (key if "secret_key_base" in m.group(1) else salt) + m.group(2),
                 text)
    if new != text:
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(new)
        pinned += 1
print(f"      secrets: pinned deterministic dev values in {pinned} config file(s)")
PY

echo "[3/8] portable overlay ($APP / $CAMEL / $UPPER)"
python3 - "$OVERLAY" "$STAGE" "$TARGET" "$APP" "$CAMEL" "$UPPER" <<'PY'
import os
import re
import sys

overlay, stage, target, app, camel, upper = sys.argv[1:7]
subs = [("{{app}}", app), ("{{App}}", camel), ("{{APP}}", upper)]

# Restrictive: a single bare identifier. The scaffold's legitimate HEEx
# (`:for={{id, msg} <- @streams.messages}`) carries a comma and a `<-`, so it
# never matches; an unknown token like `{{appp}}` does.
unknown_token = re.compile(r"\{\{[A-Za-z_][A-Za-z0-9_]*\}\}")

written = 0
written_paths = []
kept = []
token_hits = []

# The app's repo keeps its own README.md: the scaffold's is already excluded,
# so the overlay's README only lands when the app has none. An app born into
# an existing repo is never clobbered.
keep_readme = os.path.isfile(os.path.join(target, "README.md"))

for root, _dirs, files in os.walk(overlay):
    for name in files:
        src = os.path.join(root, name)
        rel = os.path.relpath(src, overlay)
        for needle, value in subs:
            rel = rel.replace(needle, value)

        if rel == "README.md" and keep_readme:
            kept.append(rel)
            continue

        dst = os.path.join(stage, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)

        with open(src, encoding="utf-8") as fh:
            text = fh.read()
        for needle, value in subs:
            text = text.replace(needle, value)

        with open(dst, "w", encoding="utf-8") as fh:
            fh.write(text)

        os.chmod(dst, 0o755 if os.access(src, os.X_OK) else 0o644)
        written += 1
        written_paths.append(dst)

if written == 0:
    sys.exit(5)

print(f"      overlay files: {written}")
if kept:
    print(f"      kept (already in the target): {', '.join(kept)}")

# Two checks over exactly the overlay files: the family's own placeholders
# must be gone, and no UNKNOWN {{token}} may survive either.
leftovers = []
for path in written_paths:
    with open(path, encoding="utf-8") as fh:
        content = fh.read()
    rel = os.path.relpath(path, stage)
    for needle, _value in subs:
        if needle in content:
            leftovers.append(f"{rel} ({needle})")
    for token in sorted(set(unknown_token.findall(content))):
        token_hits.append(f"{rel} ({token})")

problems = []
if leftovers:
    problems.append("unreplaced placeholders left in: " + ", ".join(sorted(leftovers)))
if token_hits:
    problems.append("unknown {{tokens}} left in: " + ", ".join(token_hits))
if problems:
    for problem in problems:
        print(f"      STRUCTURE: {problem}")
    sys.exit(5)
PY

echo "[4/8] themes (THEME, default dim)"
python3 - "$STAGE" "$APP" "$CAMEL" <<'PY'
import os
import re
import sys

stage, app, camel = sys.argv[1:4]
errors = []

# The family's compiled set: `dim` is the default and the rest are selectable at
# runtime with THEME (Theme.current/0 validates against the same list).
THEMES = [
    "dim", "light", "dark", "cupcake", "bumblebee", "emerald", "corporate",
    "synthwave", "retro", "cyberpunk", "valentine", "halloween", "garden",
    "forest", "aqua", "lofi", "pastel", "fantasy", "wireframe", "black",
    "luxury", "dracula", "cmyk", "autumn", "business", "acid", "lemonade",
    "night", "coffee", "winter", "nord", "sunset", "caramellatte", "abyss",
    "silk",
]
THEME_LIST = ", ".join([THEMES[0] + " --default"] + THEMES[1:])


def strip_block(text, marker):
    """Removes `marker ... { ... }` with balanced braces. Returns (text, n)."""
    removed = 0
    while True:
        idx = text.find(marker)
        if idx == -1:
            return text, removed
        brace = text.find("{", idx)
        line_end = text.find("\n", idx)
        if brace == -1 or (line_end != -1 and line_end < brace):
            text = text[:idx] + text[line_end + 1 :]
            removed += 1
            continue
        depth = 0
        i = brace
        while i < len(text):
            if text[i] == "{":
                depth += 1
            elif text[i] == "}":
                depth -= 1
                if depth == 0:
                    break
            i += 1
        text = text[:idx] + text[i + 1 :]
        removed += 1


css_path = os.path.join(stage, "assets/css/app.css")
if os.path.isfile(css_path):
    with open(css_path, encoding="utf-8") as fh:
        css = fh.read()
    original = css

    css, n_theme = re.subn(r"themes:\s*false", "themes: " + THEME_LIST, css, count=1)

    # The scaffold ships its own themes (light + dark) and a dark variant: the
    # family compiles its own set (THEME_LIST) and the `dark:` variant would only
    # follow one of them, so both are surplus and leave dead selectors.
    css = re.sub(r"/\* daisyUI theme plugin\..*?\*/\s*", "", css, flags=re.S)

    # The plugin path depends on the phx.new version: `../vendor/daisyui-theme`
    # in the older scaffold, `daisyui/packages/bundle/daisyui-theme` when it
    # comes from the git dep. Both blocks re-declare `light`/`dark` (the light
    # one with `default: true`), so leaving either one overrides the family's
    # set — strip by name, not by path.
    n_plugin = 0
    while True:
        match = re.search(r'@plugin\s+"[^"]*daisyui-theme"', css)
        if match is None:
            break
        css, removed = strip_block(css, match.group(0))
        n_plugin += removed
    css, n_variant = re.subn(r"@custom-variant dark[^\n]*\n?", "", css)
    # The comment that headed the removed variant is now misleading.
    css = re.sub(r"/\* Use the data attribute for dark mode\s*\*/\s*\n?", "", css)
    # Collapse the blank runs left by the removed blocks.
    css = re.sub(r"\n{3,}", "\n\n", css)

    if css != original:
        with open(css_path, "w", encoding="utf-8") as fh:
            fh.write(css)
        print(
            "      app.css: "
            f"{len(THEMES)} themes (dim --default) · theme plugins removed: "
            f"{n_plugin} · dark variants removed: {n_variant}"
        )
    if n_theme == 0:
        errors.append("assets/css/app.css: could not find `themes: false` — the phx.new schema changed; update bootstrap.sh (§C2)")
else:
    errors.append("assets/css/app.css does not exist — did the scaffold run correctly?")

root_html = os.path.join(stage, f"lib/{app}_web/components/layouts/root.html.heex")
if os.path.isfile(root_html):
    with open(root_html, encoding="utf-8") as fh:
        html = fh.read()
    original = html

    # The inline switcher writes data-theme from localStorage and overrides the
    # selected theme: it is deleted whole (with its indentation).
    html = re.sub(
        r"[ \t]*<script>(?:(?!</script>).)*phx:theme(?:(?!</script>).)*</script>[ \t]*\n?",
        "",
        html,
        flags=re.S,
    )

    # The title carries the app name plain (the family omits the suffix).
    html = html.replace(' suffix=" · Phoenix Framework"', "")

    # The theme is chosen at RUNTIME: the layout asks Theme.current/0 (which
    # reads THEME) instead of hardcoding a name, so switching themes needs no
    # rebuild.
    theme_attr = "data-theme={" + camel + "Web.Theme.current()}"

    if "data-theme={" not in html:
        html, n_html = re.subn(
            r"<html([^>]*?)>",
            lambda m: "<html" + m.group(1) + " " + theme_attr + ">",
            html,
            count=1,
        )
        if n_html == 0:
            errors.append("root.html.heex: could not find <html> — the phx.new schema changed; update bootstrap.sh")
    elif theme_attr not in html:
        errors.append("root.html.heex: data-theme is not " + theme_attr + " — the phx.new schema changed; update bootstrap.sh")

    html = html.replace(' data-theme-source="system"', "").replace(' data-theme-source="user"', "")

    if html != original:
        with open(root_html, "w", encoding="utf-8") as fh:
            fh.write(html)
        print("      root.html.heex: " + theme_attr + " · inline switcher removed")
else:
    errors.append(f"lib/{app}_web/components/layouts/root.html.heex does not exist — did the scaffold run correctly?")

web_ex = os.path.join(stage, f"lib/{app}_web.ex")
if os.path.isfile(web_ex):
    with open(web_ex, encoding="utf-8") as fh:
        text = fh.read()
    if "favicon.svg" not in text:
        text, _n = re.subn(r"(~w\([^)]*favicon\.ico)\b", r"\1 favicon.svg", text, count=1)
        with open(web_ex, "w", encoding="utf-8") as fh:
            fh.write(text)
    with open(web_ex, encoding="utf-8") as fh:
        if "favicon.svg" in fh.read():
            print("      web.ex: favicon.svg in static_paths")
        else:
            errors.append("web.ex: could not add favicon.svg to static_paths — the phx.new schema changed; update bootstrap.sh")
else:
    errors.append(f"lib/{app}_web.ex does not exist — did the scaffold run correctly?")

if errors:
    for error in errors:
        print(f"      STRUCTURE: {error}")
    sys.exit(5)
PY

echo "[5/8] probe routes (/health + /ready)"
python3 - "$STAGE" "$APP" "$CAMEL" <<'PY'
import os
import sys

stage, app, camel = sys.argv[1:4]
router = os.path.join(stage, f"lib/{app}_web/router.ex")

if not os.path.isfile(router):
    print(f"      STRUCTURE: lib/{app}_web/router.ex does not exist — did the scaffold run correctly?")
    sys.exit(5)

with open(router, encoding="utf-8") as fh:
    text = fh.read()

HEALTH_ROUTE = 'get "/health", HealthController, :show'
READY_ROUTE = 'get "/ready", HealthController, :ready'
has_health = 'get "/health"' in text
has_ready = 'get "/ready"' in text

if has_health or has_ready:
    # A pre-existing probe may be below :browser (cookie/CSRF). Keep NO route
    # in that pipeline: remove recognized legacy lines and recreate BOTH in the
    # family's pipeline-free scope below. An unknown probe shape fails closed.
    lines = text.splitlines(keepends=True)
    probes = (HEALTH_ROUTE, READY_ROUTE)
    rest = []

    for line in lines:
        if any(f'get "{path}"' in line for path in ("/health", "/ready")):
            if line.strip() not in probes:
                print("      STRUCTURE: a probe route has an unexpected action or options; move it by hand")
                sys.exit(5)
        else:
            rest.append(line)

    text = "".join(rest)
    print("      router.ex: legacy probes moved to a dedicated pipeline-free scope")

marker = f'scope "/", {camel}Web do'
idx = text.find(marker)
if idx == -1:
    print(f"      STRUCTURE: could not find {marker!r} in router.ex — the phx.new schema changed; update bootstrap.sh")
    sys.exit(5)

block = (
    "  # Container/proxy probes: outside :browser (no session, no CSRF,\n"
    "  # no cookie decryption) and without touching the database. /ready is\n"
    "  # the readiness sibling (HealthController.ready). See SPEC-docker.md.\n"
    f'  scope "/", {camel}Web do\n'
    f"    {HEALTH_ROUTE}\n"
    f"    {READY_ROUTE}\n"
    "  end\n\n"
)

text = text[:idx] + block + text[idx:]

with open(router, "w", encoding="utf-8") as fh:
    fh.write(text)

print("      router.ex: /health + /ready added (a scope with no pipeline)")
PY

echo "[6/8] validating the staged tree"
python3 - "$STAGE" "$APP" <<'PY'
import os
import re
import sys

stage, app = sys.argv[1:3]
errors = []


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


# Theme set (§C2): `dim --default` must be in the compiled `themes:` line and
# no scaffold theme plugin may survive next to it.
css_path = os.path.join(stage, "assets/css/app.css")
if os.path.isfile(css_path):
    css = read(css_path)
    if not re.search(r"themes:[^\n]*\bdim --default\b", css):
        errors.append("app.css: the compiled `themes:` line does not start with `dim --default`")
    if re.search(r'@plugin\s+"[^"]*daisyui-theme"', css):
        errors.append("app.css: a scaffold daisyUI theme plugin survived — it would override the family's set")
else:
    errors.append("app.css missing from the staged tree")

root_html = os.path.join(stage, f"lib/{app}_web/components/layouts/root.html.heex")
if os.path.isfile(root_html):
    html = read(root_html)
    if "data-theme={" not in html:
        errors.append("root.html.heex: no `data-theme={...}` on <html>")
    if "phx:theme" in html:
        errors.append("root.html.heex: the inline theme switcher (phx:theme) survived")
else:
    errors.append("root.html.heex missing from the staged tree")

web_ex = os.path.join(stage, f"lib/{app}_web.ex")
if os.path.isfile(web_ex):
    if "favicon.svg" not in read(web_ex):
        errors.append("web.ex: favicon.svg missing from static_paths")
else:
    errors.append(f"lib/{app}_web.ex missing from the staged tree")

router = os.path.join(stage, f"lib/{app}_web/router.ex")
if os.path.isfile(router):
    routes = read(router)
    if 'get "/health", HealthController, :show' not in routes:
        errors.append('router.ex: the `get "/health", HealthController, :show` route is missing')
    if 'get "/ready", HealthController, :ready' not in routes:
        errors.append('router.ex: the `get "/ready", HealthController, :ready` route is missing')
else:
    errors.append("router.ex missing from the staged tree")

if errors:
    for error in errors:
        print(f"      STRUCTURE: {error}")
    print("      nothing was written to the target — the run failed before the copy")
    sys.exit(5)

print("      theme · root layout · favicon · /health · /ready: all present")
PY

echo "[7/8] copying into $TARGET (collisions refused, mix.exs last)"
python3 - "$STAGE" "$TARGET" "$APP" <<'PY'
import os
import shutil
import sys

stage, target, app = sys.argv[1:4]

FAMILY_ENTRIES = [
    ".riel/",
    "/priv/static/uploads/",
    "erl_crash.dump",
    "/.env",
]

has_gitignore = os.path.isfile(os.path.join(target, ".gitignore"))
has_readme = os.path.isfile(os.path.join(target, "README.md"))

# When the target has its own .gitignore it is kept and merged into: the
# staged (scaffold) one must not take part in the copy. When it has none, the
# scaffold's is restored and the family entries (plus /.env) are merged in
# here, so the copy brings the final file.
staged_gitignore = os.path.join(stage, ".gitignore")
if has_gitignore:
    if os.path.isfile(staged_gitignore):
        os.remove(staged_gitignore)
else:
    if not os.path.isfile(staged_gitignore):
        print("      STRUCTURE: the scaffold has no .gitignore to restore")
        sys.exit(5)
    with open(staged_gitignore, encoding="utf-8") as fh:
        text = fh.read()
    lines = text.splitlines()
    missing = [e for e in FAMILY_ENTRIES if e not in lines]
    if missing:
        with open(staged_gitignore, "a", encoding="utf-8") as fh:
            if text and not text.endswith("\n"):
                fh.write("\n")
            fh.write("\n# Family (boilerplate)\n")
            for entry in missing:
                fh.write(entry + "\n")
    print("      .gitignore: scaffold restored + " + (", ".join(missing) if missing else "family entries (already there)"))


def same_file(a, b):
    if os.path.getsize(a) != os.path.getsize(b):
        return False
    with open(a, "rb") as fa, open(b, "rb") as fb:
        return fa.read() == fb.read()


collisions = []
to_write = []
identical = 0
for root, dirs, _files in os.walk(stage):
    for name in dirs:
        rel = os.path.relpath(os.path.join(root, name), stage)
        dst = os.path.join(target, rel)
        if os.path.exists(dst) and not os.path.isdir(dst):
            collisions.append(f"{rel} (a file is in the way of a directory)")
    for name in _files:
        src = os.path.join(root, name)
        rel = os.path.relpath(src, stage)
        if rel == "README.md" and has_readme:
            continue
        if rel == ".gitignore" and has_gitignore:
            continue
        dst = os.path.join(target, rel)
        if os.path.exists(dst):
            if os.path.isdir(dst):
                collisions.append(f"{rel} (a directory is in the way of a file)")
            elif same_file(src, dst):
                # A previous run died mid-copy and left the same content:
                # not a collision, the retry just completes the tree.
                identical += 1
            else:
                collisions.append(rel)
        else:
            to_write.append((src, dst, rel))

if collisions:
    print(f"      COLLISION: {len(collisions)} file(s) already exist in the target with different content:")
    for rel in sorted(collisions):
        print(f"        - {rel}")
    print("      nothing was written. bootstrap.sh has no FORCE: preserve or remove")
    print("      those files by hand (README.md, .gitignore and .git are the only")
    print("      deliberate exceptions — they are kept, never clobbered).")
    sys.exit(4)

# mix.exs is the commit marker: it is written LAST, so a run that dies
# mid-copy leaves no mix.exs and the retry re-enters cleanly instead of
# aborting with "already an Elixir project".
to_write.sort(key=lambda item: item[2] == "mix.exs")

for src, dst, rel in to_write:
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)
    shutil.copystat(src, dst)

if has_gitignore:
    with open(os.path.join(target, ".gitignore"), encoding="utf-8") as fh:
        text = fh.read()
    lines = text.splitlines()
    missing = [e for e in FAMILY_ENTRIES if e not in lines]
    if missing:
        with open(os.path.join(target, ".gitignore"), "a", encoding="utf-8") as fh:
            if text and not text.endswith("\n"):
                fh.write("\n")
            fh.write("\n# Family (boilerplate)\n")
            for entry in missing:
                fh.write(entry + "\n")
    print("      .gitignore: kept the target's own + " + (", ".join(missing) if missing else "family entries (already there)"))

print(f"      copied {len(to_write)} file(s)"
      + (f" · {identical} already identical (retry-safe)" if identical else ""))
PY

echo "[8/8] ignore gate (git check-ignore)"
if git -C "$TARGET" rev-parse --show-toplevel > /dev/null 2>&1; then
  GATE_FAIL=""
  for path in .env "deps/$APP" "_build/$APP"; do
    if ! git -C "$TARGET" check-ignore -q -- "$path"; then
      GATE_FAIL="$GATE_FAIL $path"
    fi
  done
  if git -C "$TARGET" check-ignore -q -- .env.example; then
    GATE_FAIL="$GATE_FAIL .env.example (must stay tracked)"
  fi
  if [ -n "$GATE_FAIL" ]; then
    echo "error: the ignore gate failed —$GATE_FAIL not handled by .gitignore as required" >&2
    echo "       fix .gitignore (it must ignore .env, deps/ and _build/, and keep .env.example tracked) and re-check with:" >&2
    echo "         git -C $TARGET check-ignore -- .env deps/$APP _build/$APP .env.example" >&2
    exit 5
  fi
  echo "      .env, deps/$APP, _build/$APP ignored · .env.example tracked"
else
  echo "      not a git repo (yet) — gate skipped; .gitignore already carries the rules"
fi

cat <<EOF

Done. These steps remain (they need network and a database):

  cd "$TARGET"
  cp .env.example .env && \$EDITOR .env        # SECRET_KEY_BASE, DATABASE_URL, salts (THEME optional)
  direnv allow
  mix deps.get
  mix ecto.create
  mix compile --warnings-as-errors
  mix precommit                               # the family gate

Before writing UI code: copy the Commons (../DESIGN.md) as-is + your
'## Custom — $CAMEL' section, and follow SPEC-design.md / SPEC-config.md / SPEC-docker.md.
EOF
