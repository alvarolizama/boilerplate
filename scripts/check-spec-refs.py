#!/usr/bin/env python3
"""Verifica que cada referencia `archivo:línea` de los specs resuelva.

Gate de `P1` del contrato: un spec que cita `path:line` inventado es peor que un
spec sin citas. Este script extrae las referencias de los documentos del repo,
las resuelve contra el repo y contra la raíz de la familia
(`~/Workspace/Repos/alvarolizama/`), y falla si alguna no existe o si la línea
citada está fuera del archivo.

Uso:
    python3 scripts/check-spec-refs.py [--root .] [--family ~/Workspace/Repos/alvarolizama]

Salida: una línea por referencia rota (archivo del spec, referencia, motivo) y un
resumen con el total verificado. Exit 0 si no hay rotas; 1 si hay alguna.
"""

from __future__ import annotations

import argparse
import os
import re
import sys

DOCS = [
    "README.md",
    "SPEC-design.md",
    "SPEC-config.md",
    "SPEC-docker.md",
    "BOOTSTRAP.md",
    "VERSIONS.md",
]

KNOWN_BARE = {
    "Dockerfile",
    ".dockerignore",
    ".env.example",
    ".tool-versions",
    "DESIGN.md",
    "README.md",
    "VERSIONS.md",
    "BOOTSTRAP.md",
}

KNOWN_EXT = {
    "ex", "exs", "md", "sh", "css", "heex", "js", "json", "txt",
    "sql", "pot", "yml", "yaml", "toml", "bat",
}

REF_RE = re.compile(r"([A-Za-z0-9_][A-Za-z0-9_./<>-]*?):(\d+)(?:-(\d+))?")


def looks_like_path(token: str) -> bool:
    if token.startswith("/") or "//" in token:
        return False
    base = token.rsplit("/", 1)[-1]
    if base in KNOWN_BARE:
        return True
    return "/" in token and "." in base and base.rsplit(".", 1)[-1] in KNOWN_EXT


def resolve(token: str, repo_root: str, family_root: str) -> str | None:
    for root in (repo_root, family_root):
        candidate = os.path.join(root, token)
        if os.path.isfile(candidate):
            return candidate
    return None


def line_count(path: str) -> int:
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        return sum(1 for _ in fh)


def line_text(path: str, number: int) -> str:
    """Contenido de la línea citada — para que el drift semántico sea visible.

    Existir no es apuntar bien: `path:123` puede resolver y estar citando otra
    cosa (le pasó a `dran/.env.example` cuando el archivo creció dos líneas).
    """
    with open(path, "r", encoding="utf-8", errors="ignore") as fh:
        for index, line in enumerate(fh, start=1):
            if index == number:
                return line.strip()
    return ""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", default=".")
    parser.add_argument(
        "--family",
        default=os.path.expanduser("~/Workspace/Repos/alvarolizama"),
    )
    parser.add_argument(
        "--show",
        action="store_true",
        help="imprime cada referencia con la línea citada (para ver drift semántico)",
    )
    args = parser.parse_args()

    repo_root = os.path.abspath(args.root)
    family_root = os.path.abspath(os.path.expanduser(args.family))

    checked = 0
    broken: list[tuple[str, str, str]] = []

    for doc in DOCS:
        doc_path = os.path.join(repo_root, doc)
        if not os.path.isfile(doc_path):
            broken.append((doc, "(documento)", "no existe"))
            continue

        with open(doc_path, "r", encoding="utf-8") as fh:
            text = fh.read()

        for match in REF_RE.finditer(text):
            token, first, last = match.group(1), int(match.group(2)), match.group(3)
            if not looks_like_path(token):
                continue
            ref = f"{token}:{first}" + (f"-{last}" if last else "")
            checked += 1

            target = resolve(token, repo_root, family_root)
            if target is None:
                broken.append((doc, ref, "archivo inexistente"))
                continue

            total = line_count(target)
            highest = int(last) if last else first
            if highest > total:
                broken.append((doc, ref, f"el archivo tiene {total} líneas"))
            elif last and int(last) < first:
                broken.append((doc, ref, "rango invertido"))
            elif args.show:
                preview = line_text(target, first)
                if len(preview) > 72:
                    preview = preview[:69] + "..."
                print(f"ok    {ref:58} {preview}")

    for doc, ref, why in broken:
        print(f"ROTA  {doc}: {ref} — {why}")

    print(f"referencias verificadas: {checked} · rotas: {len(broken)}")
    return 1 if broken else 0


if __name__ == "__main__":
    sys.exit(main())