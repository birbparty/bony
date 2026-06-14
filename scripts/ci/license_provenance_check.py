#!/usr/bin/env python3
"""Validate local license/provenance evidence for runtime dependencies."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LICENSE_SCAN = ROOT / "docs" / "nim-dependency-license-scan.md"
NIMBLE = ROOT / "runtime-nim" / "bony.nimble"
PUBSPEC = ROOT / "runtime-dart" / "pubspec.yaml"
ROOT_LICENSE = ROOT / "LICENSE"

FORBIDDEN_LICENSE_TERMS = [
    "gpl",
    "agpl",
    "lgpl",
    "creative commons",
    "proprietary",
    "source-available",
]


def fail(message: str) -> None:
    print(f"license/provenance check failed: {message}", file=sys.stderr)
    raise SystemExit(1)


def read(path: Path) -> str:
    if not path.exists():
        fail(f"missing required evidence file: {path.relative_to(ROOT)}")
    return path.read_text(encoding="utf-8")


def nim_dependencies(nimble_text: str) -> list[tuple[str, str]]:
    deps: list[tuple[str, str]] = []
    for match in re.finditer(r'^requires\s+"([A-Za-z0-9_-]+)\s*==\s*([^"]+)"', nimble_text, re.MULTILINE):
        deps.append((match.group(1), match.group(2).strip()))
    if not deps:
        fail("runtime-nim/bony.nimble declares no pinned dependencies")
    return deps


def assert_nim_license_scan(scan_text: str, deps: list[tuple[str, str]]) -> None:
    lower_scan = scan_text.lower()
    if "scan date:" not in lower_scan:
        fail("Nim dependency scan must include a scan date")
    if "primary source urls checked" not in lower_scan:
        fail("Nim dependency scan must include primary source URL evidence")
    has_update_rule = (
        "bumping either package or adding a new nim dependency requires updating this scan" in lower_scan
        or "before adding any new nim dependency or upgrading an existing dependency" in lower_scan
    )
    if not has_update_rule:
        fail("Nim dependency scan must state the dependency update rule")
    if "no gpl, creative commons, proprietary, or source-available-only license" not in lower_scan:
        fail("Nim dependency scan must record the forbidden-license decision")

    for dep, version in deps:
        if dep.lower() not in lower_scan:
            fail(f"Nim dependency {dep} is not covered by the license scan")
        if version.lower() not in lower_scan:
            fail(f"Nim dependency {dep} version {version} is not covered by the license scan")

    for term in FORBIDDEN_LICENSE_TERMS:
        if f"| {term}" in lower_scan or f"license = \"{term}" in lower_scan:
            fail(f"forbidden license term appears as accepted evidence: {term}")


def assert_dart_provenance(pubspec_text: str) -> None:
    if "publish_to: none" not in pubspec_text:
        fail("runtime-dart/pubspec.yaml must remain unpublished until package provenance is formalized")
    if not re.search(r"^\s*test:\s*\^", pubspec_text, re.MULTILINE):
        fail("runtime-dart/pubspec.yaml must keep the test dev dependency visible for provenance review")


def main() -> None:
    root_license = read(ROOT_LICENSE)
    if "MIT License" not in root_license:
        fail("repository LICENSE must remain MIT")

    nimble_text = read(NIMBLE)
    pubspec_text = read(PUBSPEC)
    scan_text = read(LICENSE_SCAN)

    assert_nim_license_scan(scan_text, nim_dependencies(nimble_text))
    assert_dart_provenance(pubspec_text)


if __name__ == "__main__":
    main()
