#!/usr/bin/env bash
#
# bootstrap.sh — materializa la capa portátil de la familia en una app nueva.
#
#   bash skeleton/bootstrap.sh ~/Workspace/Repos/alvarolizama/<app> [--app <name>]
#
# Qué hace:
#   1. `mix phx.new` en un scratch (--app <name> --binary-id)
#   2. rsync del scaffold al destino (conserva README.md y .gitignore del repo)
#   3. copia `skeleton/overlay/**` reemplazando {{app}} / {{App}} / {{APP}}
#   4. mergea las entradas de la familia en .gitignore
#   5. aplica el tema `dim` (app.css + data-theme en root.html.heex)
#
# No hace: `mix deps.get`, crear la base, ni el primer commit. Los pasos que
# quedan se imprimen al final. Contrato y trampas: BOOTSTRAP.md.

set -euo pipefail

OVERLAY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/overlay"

usage() {
  cat <<'EOF'
Uso: bootstrap.sh <destino> [--app <nombre>]

  <destino>     directorio de la app (se crea si no existe)
  --app <name>  nombre de la app OTP (default: basename del destino)
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
    echo "error: nombre de app inválido: '$APP' (minúsculas, dígitos y _ ; empieza con letra)" >&2
    exit 2
    ;;
esac

if ! printf '%s' "$APP" | grep -qE '^[a-z][a-z0-9_]*$'; then
  echo "error: nombre de app inválido: '$APP' (minúsculas, dígitos y _ ; empieza con letra)" >&2
  exit 2
fi

CAMEL="$(printf '%s' "$APP" | python3 -c 'import sys; print("".join(p.capitalize() for p in sys.stdin.read().split("_")))')"
UPPER="$(printf '%s' "$APP" | tr '[:lower:]' '[:upper:]')"

[ -d "$OVERLAY" ] || {
  echo "error: no encuentro el overlay en $OVERLAY" >&2
  exit 2
}

if [ -f "$TARGET/mix.exs" ]; then
  echo "error: $TARGET ya es un proyecto Elixir (tiene mix.exs) — abortando" >&2
  exit 3
fi

mkdir -p "$TARGET"
TARGET="$(cd "$TARGET" && pwd)"

SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

echo "[1/6] scaffold: mix phx.new $APP (binary_id)"
mix phx.new "$SCRATCH/$APP" --app "$APP" --binary-id --no-version-check < /dev/null > /dev/null

echo "[2/6] copiando el scaffold a $TARGET (README.md y .gitignore del repo se conservan)"
rsync -a --exclude .git --exclude README.md --exclude .gitignore "$SCRATCH/$APP/" "$TARGET/"

echo "[3/6] overlay portátil ($APP / $CAMEL / $UPPER)"
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
    sys.exit("error: overlay vacío")

print(f"      archivos del overlay: {written}")

# El chequeo mira SOLO los archivos del overlay: los `{{…}}` del scaffold son
# sintaxis HEEx legítima (`:for={{id, msg} <- @streams.messages}`).
leftovers = []
for path in written_paths:
    with open(path, encoding="utf-8") as fh:
        content = fh.read()
    for needle, _value in subs:
        if needle in content:
            leftovers.append(f"{os.path.relpath(path, target)} ({needle})")

if leftovers:
    sys.exit("error: quedaron placeholders sin reemplazar en: " + ", ".join(sorted(leftovers)))
PY

echo "[4/6] .gitignore de la familia"
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
        fh.write("\n# Familia (boilerplate)\n")
        for entry in missing:
            fh.write(entry + "\n")

print(f"      agregadas: {', '.join(missing) if missing else 'nada (ya estaban)'}")
PY

echo "[5/6] tema dim"
python3 - "$TARGET" "$APP" <<'PY'
import os
import re
import sys

target, app = sys.argv[1:3]
warnings = []


def strip_block(text, marker):
    """Borra `marker ... { ... }` con llaves balanceadas. Devuelve (texto, n)."""
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

    # El scaffold trae sus propios temas (light + dark) y un variant dark: con un
    # único tema `dim --default` sobran y dejan selectores muertos.
    css = re.sub(r"/\* daisyUI theme plugin\..*?\*/\s*", "", css, flags=re.S)
    css, n_plugin = strip_block(css, '@plugin "../vendor/daisyui-theme"')
    css, n_variant = re.subn(r"@custom-variant dark[^\n]*\n?", "", css)

    if css != original:
        with open(css_path, "w", encoding="utf-8") as fh:
            fh.write(css)
        print(
            "      app.css: dim --default · plugins de tema removidos: "
            f"{n_plugin} · variants dark removidos: {n_variant}"
        )
    if n_theme == 0:
        warnings.append("assets/css/app.css: no encontré `themes: false` — aplicá el tema a mano (§C2)")
else:
    warnings.append("assets/css/app.css no existe — ¿el scaffold corrió bien?")

root_html = os.path.join(target, f"lib/{app}_web/components/layouts/root.html.heex")
if os.path.isfile(root_html):
    with open(root_html, encoding="utf-8") as fh:
        html = fh.read()
    original = html

    # El switcher inline escribe data-theme desde localStorage y pisa el tema
    # fijo de la familia: se borra entero.
    html = re.sub(
        r"<script>(?:(?!</script>).)*phx:theme(?:(?!</script>).)*</script>\s*",
        "",
        html,
        flags=re.S,
    )

    # El título lleva el nombre de la app a secas (la familia omite el sufijo).
    html = html.replace(' suffix=" · Phoenix Framework"', "")

    if 'data-theme="dim"' not in html:
        html, n_html = re.subn(r"<html([^>]*?)>", r'<html\1 data-theme="dim">', html, count=1)
        if n_html == 0:
            warnings.append('root.html.heex: no encontré <html> — poné data-theme="dim" a mano')

    html = html.replace(' data-theme-source="system"', "").replace(' data-theme-source="user"', "")

    if html != original:
        with open(root_html, "w", encoding="utf-8") as fh:
            fh.write(html)
        print('      root.html.heex: data-theme="dim" · switcher inline removido')
else:
    warnings.append(f"{root_html} no existe — ¿el scaffold corrió bien?")

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
            print("      web.ex: favicon.svg en static_paths")
        else:
            warnings.append("web.ex: no pude agregar favicon.svg a static_paths — hacelo a mano")

for warning in warnings:
    print(f"      AVISO: {warning}")
PY

echo "[6/6] ruta /health"
python3 - "$TARGET" "$APP" "$CAMEL" <<'PY'
import os
import sys

target, app, camel = sys.argv[1:4]
router = os.path.join(target, f"lib/{app}_web/router.ex")

if not os.path.isfile(router):
    print(f"      AVISO: no existe {router} — agregá `get \"/health\", HealthController, :show` a mano")
    sys.exit(0)

with open(router, encoding="utf-8") as fh:
    text = fh.read()

if '"/health"' in text:
    print("      router.ex: ya tiene /health")
    sys.exit(0)

marker = f'scope "/", {camel}Web do'
idx = text.find(marker)
if idx == -1:
    print(f"      AVISO: no encontré {marker!r} en router.ex — agregá la ruta /health a mano")
    sys.exit(0)

block = (
    "  # Healthcheck del contenedor/proxy: fuera de :browser (sin sesión, sin CSRF,\n"
    "  # sin descifrar cookie) y sin tocar la base. Ver SPEC-docker.md.\n"
    f'  scope "/", {camel}Web do\n'
    '    get "/health", HealthController, :show\n'
    "  end\n\n"
)

text = text[:idx] + block + text[idx:]

with open(router, "w", encoding="utf-8") as fh:
    fh.write(text)

print("      router.ex: ruta /health agregada (scope sin pipeline)")
PY

cat <<EOF

Listo. Quedan estos pasos (requieren red y base de datos):

  cd $TARGET
  cp .env.example .env && \$EDITOR .env        # SECRET_KEY_BASE, DATABASE_URL, salts
  mix deps.get
  mix ecto.create
  mix compile --warnings-as-errors
  mix precommit                               # el gate de la familia

Antes de codear UI: copiá el Commons (../DESIGN.md) tal cual + tu sección
'## Custom — $CAMEL', y seguí SPEC-design.md / SPEC-config.md / SPEC-docker.md.
EOF