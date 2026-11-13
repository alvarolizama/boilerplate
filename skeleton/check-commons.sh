#!/usr/bin/env bash
#
# check-commons.sh — is an app's DESIGN.md still carrying the Commons?
#
#   bash skeleton/check-commons.sh /path/to/<app> [/more/apps...]
#
# The Commons is the part of a DESIGN.md that runs **above** its FIRST
# `## Custom — <App>` heading. The standard says it is copied byte-exact from
# this repo and edited only here (SPEC-design.md §Hard rules, §Propagation),
# so any difference means propagation debt — or a Commons edited inside an
# app, which is forbidden.
#
# Read-only: it never writes, in this repo or in the apps.
#
# Exit codes:
#   0  every app carries the Commons byte-exact
#   1  at least one app drifted (a bounded unified diff is printed)
#   2  at least one app has no DESIGN.md (skipped) — a skip is never a pass —
#      and none drifted; also bad usage
#
# The `\n\n---\n\n` separator the standard prescribes between the Commons and the
# Custom section is NOT part of the Commons: the comparison strips it (and any
# trailing whitespace) on both sides.
set -euo pipefail

CANON="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/DESIGN.md"

if [ ! -f "$CANON" ]; then
  echo "error: cannot find the canonical Commons at $CANON" >&2
  exit 2
fi

if [ "$#" -lt 1 ]; then
  echo "usage: check-commons.sh <app-dir> [app-dir...]" >&2
  exit 2
fi

for arg in "$@"; do
  case "$arg" in
    -*) echo "error: unknown option: $arg" >&2; exit 2 ;;
  esac
done

python3 - "$CANON" "$@" <<'PY'
import difflib
import os
import sys

canon_path, apps = sys.argv[1], sys.argv[2:]

MAX_DIFF_LINES = 80


def commons(path):
    """Everything above the FIRST heading that opens a Custom section."""
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    starts = [i for i, line in enumerate(lines) if line.startswith("## Custom —")]
    return "".join(lines[: starts[0]]) if starts else "".join(lines)


def normalize(text):
    """Drops the prescribed `---` separator and trailing whitespace."""
    text = text.rstrip()
    if text.endswith("---"):
        text = text[:-3].rstrip()
    return text


canon = commons(canon_path)
canon_sections = [l.strip() for l in canon.splitlines() if l.startswith("## ") or l.startswith("### ")]
canon_lines = normalize(canon).splitlines(keepends=True)

print(f"canonical Commons: {canon_path} ({len(canon)} chars)")
print()

ok = []
drifted = []
skipped = []

for app in apps:
    doc = os.path.join(app, "DESIGN.md")
    if not os.path.isfile(doc):
        print(f"  {app}: no DESIGN.md — skipped (exit 2)")
        skipped.append(app)
        continue

    body = commons(doc)

    if normalize(body) == normalize(canon):
        ok.append(app)
        print(f"  {app}: OK (byte-exact, {len(body)} chars)")
        continue

    drifted.append(app)
    ratio = difflib.SequenceMatcher(None, canon, body).ratio()
    sections = [l.strip() for l in body.splitlines() if l.startswith("## ") or l.startswith("### ")]
    missing = [s for s in canon_sections if s not in sections]

    print(f"  {app}: DRIFTED (ratio {ratio:.3f}, {len(body)} chars vs {len(canon)})")
    if missing:
        print(f"      sections of the Commons not present: {len(missing)}")
        for section in missing[:10]:
            print(f"        - {section}")
        if len(missing) > 10:
            print(f"        … and {len(missing) - 10} more")

    diff = list(difflib.unified_diff(
        canon_lines,
        normalize(body).splitlines(keepends=True),
        fromfile=f"{canon_path} (canonical Commons)",
        tofile=doc,
    ))
    if diff:
        print(f"      unified diff (first {min(len(diff), MAX_DIFF_LINES)} of {len(diff)} lines):")
        for line in diff[:MAX_DIFF_LINES]:
            print("      " + line.rstrip("\n"))
        if len(diff) > MAX_DIFF_LINES:
            print(f"      … {len(diff) - MAX_DIFF_LINES} more diff lines — run: diff <(sed -n '1,/^## Custom —/p' '{canon_path}') <(sed -n '1,/^## Custom —/p' '{doc}')")

print()
print("summary:")
print(f"  ok: {len(ok)}")
print(f"  drifted: {len(drifted)}" + (f" — {', '.join(drifted)}" if drifted else ""))
print(f"  skipped: {len(skipped)}" + (f" — {', '.join(skipped)}" if skipped else ""))

if drifted:
    print()
    print(f"{len(drifted)} of {len(apps)} app(s) drifted: {', '.join(drifted)}")
    print("The Commons is edited HERE and propagated by copying (SPEC-design.md §Propagation).")
    sys.exit(1)

if skipped:
    print()
    print(f"{len(skipped)} of {len(apps)} app(s) skipped (no DESIGN.md): {', '.join(skipped)}")
    print("A skip is never a pass — create the app's DESIGN.md (Commons byte-exact + Custom).")
    sys.exit(2)

print()
print(f"all {len(apps)} app(s) carry the Commons byte-exact.")
PY
