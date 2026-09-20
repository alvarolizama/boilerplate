#!/usr/bin/env bash
#
# check-commons.sh — is an app's DESIGN.md still carrying the Commons?
#
#   bash skeleton/check-commons.sh /path/to/<app> [/more/apps...]
#
# The Commons is the part of a DESIGN.md that runs **above** its own
# `## Custom — <App>` heading. The standard says it is copied byte-exact from
# this repo and edited only here (SPEC-design.md §Hard rules, §Propagation), so
# any difference means propagation debt — or a Commons edited inside an app,
# which is forbidden.
#
# Read-only: it never writes, in this repo or in the apps. Exit code 0 when
# every app matches, 1 when one drifted.
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

python3 - "$CANON" "$@" <<'PY'
import difflib
import os
import sys

canon_path, apps = sys.argv[1], sys.argv[2:]


def commons(path):
    """Everything above the LAST heading that opens a Custom section."""
    with open(path, encoding="utf-8") as fh:
        lines = fh.readlines()
    starts = [i for i, line in enumerate(lines) if line.startswith("## Custom —")]
    return "".join(lines[: starts[-1]]) if starts else "".join(lines)


def normalize(text):
    """Drops the prescribed `---` separator and trailing whitespace."""
    text = text.rstrip()
    if text.endswith("---"):
        text = text[:-3].rstrip()
    return text


canon = commons(canon_path)
canon_sections = [l.strip() for l in canon.splitlines() if l.startswith("## ") or l.startswith("### ")]

print(f"canonical Commons: {canon_path} ({len(canon)} chars)")
print()

drifted = []
for app in apps:
    doc = os.path.join(app, "DESIGN.md")
    if not os.path.isfile(doc):
        print(f"  {app}: no DESIGN.md — skipped")
        continue

    body = commons(doc)
    ratio = difflib.SequenceMatcher(None, canon, body).ratio()
    same = normalize(body) == normalize(canon)

    if same:
        print(f"  {app}: OK (byte-exact, {len(body)} chars)")
        continue

    drifted.append(app)
    sections = [l.strip() for l in body.splitlines() if l.startswith("## ") or l.startswith("### ")]
    missing = [s for s in canon_sections if s not in sections]

    print(f"  {app}: DRIFTED (ratio {ratio:.3f}, {len(body)} chars vs {len(canon)})")
    if missing:
        print(f"      sections of the Commons not present: {len(missing)}")
        for section in missing[:10]:
            print(f"        - {section}")
        if len(missing) > 10:
            print(f"        … and {len(missing) - 10} more")

print()
if drifted:
    print(f"{len(drifted)} of {len(apps)} app(s) drifted: {', '.join(drifted)}")
    print("The Commons is edited HERE and propagated by copying (SPEC-design.md §Propagation).")
    sys.exit(1)

print(f"all {len(apps)} app(s) carry the Commons byte-exact.")
PY