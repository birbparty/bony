"""Generate bony runtime metadata and schema from registry/default sources."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from .emit import generate_dart, generate_nim
from .paths import DART_WIRE_PATH, DEFAULTS_PATH, NIM_WIRE_PATH, REGISTRY_PATH, ROOT, SCHEMA_PATH, WIRE_SCHEMA_PATH
from .schema import generate_schema, generate_wire_schema
from .schema_types import SourceError
from .validate import validate_sources
from .yaml_subset import load_yaml_subset


def write_or_check(path: Path, content: str, check: bool, changed: list[Path]) -> None:
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return
    if check:
        changed.append(path)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="fail if generated outputs are stale")
    args = parser.parse_args()

    try:
        registry = load_yaml_subset(REGISTRY_PATH)
        defaults = load_yaml_subset(DEFAULTS_PATH)
        validate_sources(registry, defaults)
        changed: list[Path] = []
        write_or_check(SCHEMA_PATH, generate_schema(registry, defaults), args.check, changed)
        write_or_check(WIRE_SCHEMA_PATH, generate_wire_schema(registry, defaults), args.check, changed)
        write_or_check(NIM_WIRE_PATH, generate_nim(registry, defaults), args.check, changed)
        write_or_check(DART_WIRE_PATH, generate_dart(registry, defaults), args.check, changed)
    except SourceError as exc:
        print(f"codegen: {exc}", file=sys.stderr)
        return 1

    if changed:
        print("stale generated files:", file=sys.stderr)
        for path in changed:
            print(f"  {path.relative_to(ROOT)}", file=sys.stderr)
        return 1
    return 0
