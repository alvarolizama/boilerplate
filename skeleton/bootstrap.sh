#!/usr/bin/env bash
#
# bootstrap.sh — materializes the family's portable layer into a new app.
#
#   bash skeleton/bootstrap.sh /path/to/<app> [--app <name>]
#
# What it does:
#   1. `mix phx.new` into a scratch dir (--app <name> --binary-id --no-install)
#   2. rsync of the scaffold into the target (keeps the repo's README.md and .gitignore)
#   3. copies `skeleton/overlay/**` replacing {{app}} / {{App}} / {{APP}}
#   4. merges the family entries into .gitignore
#   5. applies the `dim` theme (app.css + data-theme in root.html.heex)
#
# It does not: `mix deps.get`, create the database, or the first commit. The
# remaining steps are printed at the end. Contract and traps: BOOTSTRAP.md.

set -euo pipefail

OVERLAY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/overlay"

usage() {
  cat <<'EOF'
Usage: bootstrap.sh <target> [--app <name>]

  <target>      the app's directory (created if it does not exist)
  --app <name>  OTP app name (default: the basename of the target)
EOF
}

TARGET=""
APP=""

while [ $# -gt 0 ]; do
  case "$1" in
    --app)
      APP="${2:-}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      TARGET="$1"
      shift
      ;;
  esac
done

[ -n "$TARGET" ] || {
  usage
  exit 2
}

APP="${APP:-$(basename "$TARGET")}"

case "$APP" in
  [a-z]*) ;;
  *)
    echo "error: invalid app name: '$APP' (lowercase letters, digits and _ ; must start with a letter)" >&2
    exit 2
    ;;
esac

if ! printf '%s' "$APP" | grep -qE '^[a-z][a-z0-9_]*$'; then
  echo "error: invalid app name: '$APP' (lowercase letters, digits and _ ; must start with a letter)" >&2
  exit 2
fi

CAMEL="$(printf '%s' "$APP" | python3 -c 'import sys; print("".join(p.capitalize() for p in sys.stdin.read().split("_")))')"
UPPER="$(printf '%s' "$APP" | tr '[:lower:]' '[:upper:]')"

[ -d "$OVERLAY" ] || {
  echo "error: cannot find the overlay at $OVERLAY" >&2
  exit 2
}

if [ -f "$TARGET/mix.exs" ]; then
  echo "error: $TARGET is already an Elixir project (it has a mix.exs) — aborting" >&2
  exit 3
fi

mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

echo "[1/6] scaffold: mix phx.new $APP (binary_id, no install)"
# --no-install is explicit on purpose: phx.new PROMPTS to fetch deps and
# install assets, and a non-interactive run that answers "yes" (or a changed
# default) would leave deps/ and assets/node_modules/ in the scratch dir for
# the rsync below to copy into the target. The scaffold must bring code only.
mix phx.new "$SCRATCH/$APP" --app "$APP" --binary-id --no-version-check --no-install < /dev/null > /dev/null

echo "[2/6] copying the scaffold into $TARGET (the repo's README.md and .gitignore are kept)"
rsync -a --exclude .git --exclude README.md --exclude .gitignore "$SCRATCH/$APP/" "$TARGET/"

echo "[3/6] portable overlay ($APP / $CAMEL / $UPPER)"
python3 - "$OVERLAY" "$TARGET" "$APP" "$CAMEL" "$UPPER" <<'PY'
import os
import sys

overlay, target, app, camel, upper = sys.argv[1:6]
subs = [("{{app}}", app), ("{{App}}", camel), ("{{APP}}", upper)]

written = 0
written_paths = []

for root, _dirs, files in os.walk(overlay):
    for name in files:
        src = os.path.join(root, name)
        rel = os.path.relpath(src, overlay)
        for needle, value in subs:
            rel = rel.replace(needle, value)

        dst = os.path.join(target, rel)
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
    sys.exit("error: empty overlay")

print(f"      overlay files: {written}")

# The check looks ONLY at the overlay files: the scaffold's `{{…}}` are
# legitimate HEEx syntax (`:for={{id, msg} <- @streams.messages}`).
leftovers = []
for path in written_paths:
    with open(path, encoding="utf-8") as fh:
        content = fh.read()
    for needle, _value in subs:
        if needle in content:
            leftovers.append(f"{os.path.relpath(path, target)} ({needle})")

if leftovers:
    sys.exit("error: unreplaced placeholders left in: " + ", ".join(sorted(leftovers)))
PY

echo "[4/6] family .gitignore"
python3 - "$TARGET/.gitignore" <<'PY'
import os
import sys

path = sys.argv[1]
entries = [
    ".riel/",
    "/priv/static/uploads/",
    "erl_crash.dump",
]

existing = ""
if os.path.isfile(path):
    with open(path, encoding="utf-8") as fh:
        existing = fh.read()

lines = existing.splitlines()
missing = [e for e in entries if e not in lines]

if missing:
    with open(path, "a", encoding="utf-8") as fh:
        if existing and not existing.endswith("\n"):
            fh.write("\n")
        fh.write("\n# Family (boilerplate)\n")
        for entry in missing:
            fh.write(entry + "\n")

print(f"      added: {', '.join(missing) if missing else 'nothing (already there)'}")
PY

echo "[5/6] dim theme"
python3 - "$TARGET" "$APP" <<'PY'
import os
import re
import sys

target, app = sys.argv[1:3]
warnings = []


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


css_path = os.path.join(target, "assets/css/app.css")
if os.path.isfile(css_path):
    with open(css_path, encoding="utf-8") as fh:
        css = fh.read()
    original = css

    css, n_theme = re.subn(r"themes:\s*false", "themes: dim --default", css, count=1)

    # The scaffold ships its own themes (light + dark) and a dark variant: with a
    # single `dim --default` theme they are surplus and leave dead selectors.
    css = re.sub(r"/\* daisyUI theme plugin\..*?\*/\s*", "", css, flags=re.S)
    css, n_plugin = strip_block(css, '@plugin "../vendor/daisyui-theme"')
    css, n_variant = re.subn(r"@custom-variant dark[^\n]*\n?", "", css)

    if css != original:
        with open(css_path, "w", encoding="utf-8") as fh:
            fh.write(css)
        print(
            "      app.css: dim --default · theme plugins removed: "
            f"{n_plugin} · dark variants removed: {n_variant}"
        )
    if n_theme == 0:
        warnings.append("assets/css/app.css: could not find `themes: false` — apply the theme by hand (§C2)")
else:
    warnings.append("assets/css/app.css does not exist — did the scaffold run correctly?")

root_html = os.path.join(target, f"lib/{app}_web/components/layouts/root.html.heex")
if os.path.isfile(root_html):
    with open(root_html, encoding="utf-8") as fh:
        html = fh.read()
    original = html

    # The inline switcher writes data-theme from localStorage and overrides the
    # family's fixed theme: it is deleted whole.
    html = re.sub(
        r"<script>(?:(?!</script>).)*phx:theme(?:(?!</script>).)*</script>\s*",
        "",
        html,
        flags=re.S,
    )

    # The title carries the app name plain (the family omits the suffix).
    html = html.replace(' suffix=" · Phoenix Framework"', "")

    if 'data-theme="dim"' not in html:
        html, n_html = re.subn(r"<html([^>]*?)>", r'<html\1 data-theme="dim">', html, count=1)
        if n_html == 0:
            warnings.append('root.html.heex: could not find <html> — set data-theme="dim" by hand')

    html = html.replace(' data-theme-source="system"', "").replace(' data-theme-source="user"', "")

    if html != original:
        with open(root_html, "w", encoding="utf-8") as fh:
            fh.write(html)
        print('      root.html.heex: data-theme="dim" · inline switcher removed')
else:
    warnings.append(f"{root_html} does not exist — did the scaffold run correctly?")

web_ex = os.path.join(target, f"lib/{app}_web.ex")
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
            warnings.append("web.ex: could not add favicon.svg to static_paths — do it by hand")

for warning in warnings:
    print(f"      WARNING: {warning}")
PY

echo "[6/6] /health route"
python3 - "$TARGET" "$APP" "$CAMEL" <<'PY'
import os
import sys

target, app, camel = sys.argv[1:4]
router = os.path.join(target, f"lib/{app}_web/router.ex")

if not os.path.isfile(router):
    print(f"      WARNING: {router} does not exist — add `get \"/health\", HealthController, :show` by hand")
    sys.exit(0)

with open(router, encoding="utf-8") as fh:
    text = fh.read()

if '"/health"' in text:
    print("      router.ex: already has /health")
    sys.exit(0)

marker = f'scope "/", {camel}Web do'
idx = text.find(marker)
if idx == -1:
    print(f"      WARNING: could not find {marker!r} in router.ex — add the /health route by hand")
    sys.exit(0)

block = (
    "  # Container/proxy healthcheck: outside :browser (no session, no CSRF,\n"
    "  # no cookie decryption) and without touching the database. See SPEC-docker.md.\n"
    f'  scope "/", {camel}Web do\n'
    '    get "/health", HealthController, :show\n'
    "  end\n\n"
)

text = text[:idx] + block + text[idx:]

with open(router, "w", encoding="utf-8") as fh:
    fh.write(text)

print("      router.ex: /health route added (a scope with no pipeline)")
PY

cat <<EOF

Done. These steps remain (they need network and a database):

  cd $TARGET
  cp .env.example .env && \$EDITOR .env        # SECRET_KEY_BASE, DATABASE_URL, salts
  mix deps.get
  mix ecto.create
  mix compile --warnings-as-errors
  mix precommit                               # the family gate

Before writing UI code: copy the Commons (../DESIGN.md) as-is + your
'## Custom — $CAMEL' section, and follow SPEC-design.md / SPEC-config.md / SPEC-docker.md.
EOF