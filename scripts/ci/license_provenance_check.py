#!/usr/bin/env python3
"""Validate local license/provenance evidence for runtime dependencies."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
LICENSE_SCAN = ROOT / "docs" / "nim-dependency-license-scan.md"
CLEANROOM = ROOT / "docs" / "CLEANROOM.md"
PROVENANCE = ROOT / "docs" / "PROVENANCE.md"
NIMBLE = ROOT / "runtime-nim" / "bony.nimble"
PUBSPEC = ROOT / "runtime-dart" / "pubspec.yaml"
PUBSPEC_LOCK = ROOT / "runtime-dart" / "pubspec.lock"
ROOT_LICENSE = ROOT / "LICENSE"
BDDY_URL = "https://github.com/mattsp1290/bddy"
BDDY_COMMIT = "34287484337fbad6626525062fe27d28fcb0fc58"
BUILD_POLICY_PATHS = [
    ROOT / ".github" / "workflows",
    ROOT / "scripts",
    ROOT / "runtime-nim" / "bony.nimble",
    ROOT / "runtime-dart" / "pubspec.yaml",
    ROOT / "runtime-dart" / "pubspec.lock",
]
PRIOR_ART_RUNTIME_TERMS = [
    "spine",
    "esoteric",
    "live2d",
    "cubism",
    "rive-runtime",
    "rive runtime",
    "dragonbones",
    "dragon bones",
]
NETWORK_FETCH_PATTERN = re.compile(
    r"\b(git\s+(clone|fetch|submodule)|curl|wget|scp|ssh|npm\s+install|"
    r"nimble\s+install|dart\s+pub\s+add|go\s+get|pip\s+install)\b|https?://",
    re.IGNORECASE,
)

DART_LOCK_ALLOWLIST = {
    "_fe_analyzer_shared": ("99.0.0", "a49d6cf99e8d8e7a8e93668d09ced0bbdb954d0b4fccc2f5f9241c6b87fad95c"),
    "analyzer": ("12.1.0", "663efa951fb8a45e06f491223a604c93820598f20e6a99c25617a1576065e8b7"),
    "args": ("2.7.0", "d0481093c50b1da8910eb0bb301626d4d8eb7284aa739614d2b394ee09e3ea04"),
    "async": ("2.13.1", "e2eb0491ba5ddb6177742d2da23904574082139b07c1e33b8503b9f46f3e1a37"),
    "boolean_selector": ("2.1.2", "8aab1771e1243a5063b8b0ff68042d67334e3feab9e95b9490f9a6ebf73b42ea"),
    "cli_config": ("0.2.0", "ac20a183a07002b700f0c25e61b7ee46b23c309d76ab7b7640a028f18e4d99ec"),
    "collection": ("1.19.1", "2f5709ae4d3d59dd8f7cd309b4e023046b57d8a6c82130785d2b0e5868084e76"),
    "convert": ("3.1.2", "b30acd5944035672bc15c6b7a8b47d773e41e2f17de064350988c5d02adb1c68"),
    "coverage": ("1.15.1", "956a3de0725ca232ad353565a8290d3357592bf4250f6f298a185e2d949c5d3d"),
    "crypto": ("3.0.7", "c8ea0233063ba03258fbcf2ca4d6dadfefe14f02fab57702265467a19f27fadf"),
    "file": ("7.0.1", "a3b4f84adafef897088c160faf7dfffb7696046cb13ae90b508c2cbc95d3b8d4"),
    "frontend_server_client": ("4.0.0", "f64a0333a82f30b0cca061bc3d143813a486dc086b574bfb233b7c1372427694"),
    "glob": ("2.1.3", "c3f1ee72c96f8f78935e18aa8cecced9ab132419e8625dc187e1c2408efc20de"),
    "http_multi_server": ("3.2.2", "aa6199f908078bb1c5efb8d8638d4ae191aac11b311132c3ef48ce352fb52ef8"),
    "http_parser": ("4.1.2", "178d74305e7866013777bab2c3d8726205dc5a4dd935297175b19a23a2e66571"),
    "io": ("1.0.5", "dfd5a80599cf0165756e3181807ed3e77daf6dd4137caaad72d0b7931597650b"),
    "logging": ("1.3.0", "c8245ada5f1717ed44271ed1c26b8ce85ca3228fd2ffdb75468ab01979309d61"),
    "matcher": ("0.12.19", "dc0b7dc7651697ea4ff3e69ef44b0407ea32c487a39fff6a4004fa585e901861"),
    "meta": ("1.18.3", "c82594181e3312f3d0695fc95aaaf7758d75b8d4ae2bbecf223b9fd5109a059d"),
    "mime": ("2.0.0", "41a20518f0cb1256669420fdba0cd90d21561e560ac240f26ef8322e45bb7ed6"),
    "node_preamble": ("2.0.2", "6e7eac89047ab8a8d26cf16127b5ed26de65209847630400f9aefd7cd5c730db"),
    "package_config": ("2.2.0", "f096c55ebb7deb7e384101542bfba8c52696c1b56fca2eb62827989ef2353bbc"),
    "path": ("1.9.1", "75cca69d1490965be98c73ceaea117e8a04dd21217b37b292c9ddbec0d955bc5"),
    "pool": ("1.5.2", "978783255c543aa3586a1b3c21f6e9d720eb315376a915872c61ef8b5c20177d"),
    "pub_semver": ("2.2.0", "5bfcf68ca79ef689f8990d1160781b4bad40a3bd5e5218ad4076ddb7f4081585"),
    "shelf": ("1.4.2", "e7dd780a7ffb623c57850b33f43309312fc863fb6aa3d276a754bb299839ef12"),
    "shelf_packages_handler": ("3.0.2", "89f967eca29607c933ba9571d838be31d67f53f6e4ee15147d5dc2934fee1b1e"),
    "shelf_static": ("1.1.3", "c87c3875f91262785dade62d135760c2c69cb217ac759485334c5857ad89f6e3"),
    "shelf_web_socket": ("3.0.0", "3632775c8e90d6c9712f883e633716432a27758216dfb61bd86a8321c0580925"),
    "source_map_stack_trace": ("2.1.2", "c0713a43e323c3302c2abe2a1cc89aa057a387101ebd280371d6a6c9fa68516b"),
    "source_maps": ("0.10.13", "190222579a448b03896e0ca6eca5998fa810fda630c1d65e2f78b3f638f54812"),
    "source_span": ("1.10.2", "56a02f1f4cd1a2d96303c0144c93bd6d909eea6bee6bf5a0e0b685edbd4c47ab"),
    "stack_trace": ("1.12.1", "8b27215b45d22309b5cddda1aa2b19bdfec9df0e765f2de506401c071d38d1b1"),
    "stream_channel": ("2.1.4", "969e04c80b8bcdf826f8f16579c7b14d780458bd97f56d107d3950fdbeef059d"),
    "string_scanner": ("1.4.1", "921cd31725b72fe181906c6a94d987c78e3b98c2e205b397ea399d4054872b43"),
    "term_glyph": ("1.2.2", "7f554798625ea768a7518313e58f83891c7f5024f88e46e7182a4558850a4b8e"),
    "test": ("1.31.0", "8d9ceddbab833f180fbefed08afa76d7c03513dfdba87ffcec2718b02bbcbf20"),
    "test_api": ("0.7.11", "949a932224383300f01be9221c39180316445ecb8e7547f70a41a35bf421fb9e"),
    "test_core": ("0.6.17", "1991d4cfe85d5043241acac92962c3977c8d2f2add1ee73130c7b286417d1d34"),
    "typed_data": ("1.4.0", "f9049c039ebfeb4cf7a7104a675823cd72dba8297f264b6637062516699fa006"),
    "vm_service": ("15.2.0", "0016aef94fc66495ac78af5859181e3f3bf2026bd8eecc72b9565601e19ab360"),
    "watcher": ("1.2.1", "1398c9f081a753f9226febe8900fce8f7d0a67163334e1c94a2438339d79d635"),
    "web": ("1.1.1", "868d88a33d8a87b18ffc05f9f030ba328ffefba92d6c127917a2ba740f9cfe4a"),
    "web_socket": ("1.0.1", "34d64019aa8e36bf9842ac014bb5d2f5586ca73df5e4d9bf5c936975cae6982c"),
    "web_socket_channel": ("3.0.3", "d645757fb0f4773d602444000a8131ff5d48c9e47adfe9772652dd1a4f2d45c8"),
    "webkit_inspection_protocol": ("1.2.1", "87d3f2333bb240704cd3f1c6b5b7acd8a10e7f0bc28c28dcf14e782014f4a572"),
    "yaml": ("3.1.3", "b9da305ac7c39faa3f030eccd175340f968459dae4af175130b3fc47e40d76ce"),
}

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
    for match in re.finditer(r'^requires\s+"([^"]+)"', nimble_text, re.MULTILINE):
        requirement = match.group(1).strip()
        pinned = re.fullmatch(r"([A-Za-z0-9_-]+)\s*==\s*([^<>=~\s]+)", requirement)
        if pinned is None:
            fail(f"Nim dependency must be exactly pinned before license scan: {requirement}")
        deps.append((pinned.group(1), pinned.group(2).strip()))
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


def dart_lock_packages(lock_text: str) -> dict[str, tuple[str, str, str]]:
    packages: dict[str, tuple[str, str, str]] = {}
    current: str | None = None
    source: str | None = None
    sha256: str | None = None
    version: str | None = None

    def flush() -> None:
        if current is None:
            return
        if source != "hosted" or sha256 is None or version is None:
            fail(f"Dart package {current} must be hosted with locked sha256 and version")
        packages[current] = (version, sha256, source)

    for line in lock_text.splitlines():
        package_match = re.match(r"^  ([A-Za-z0-9_]+):$", line)
        if package_match:
            flush()
            current = package_match.group(1)
            source = None
            sha256 = None
            version = None
            continue
        if current is None:
            continue
        stripped = line.strip()
        if stripped.startswith("sha256:"):
            sha256 = stripped.split(":", 1)[1].strip().strip('"')
        elif stripped.startswith("source:"):
            source = stripped.split(":", 1)[1].strip()
        elif stripped.startswith("version:"):
            version = stripped.split(":", 1)[1].strip().strip('"')
    flush()

    if not packages:
        fail("runtime-dart/pubspec.lock contains no package provenance entries")
    return packages


def assert_dart_lock_provenance(lock_text: str) -> None:
    packages = dart_lock_packages(lock_text)
    actual = set(packages)
    expected = set(DART_LOCK_ALLOWLIST)
    if actual != expected:
        missing = ", ".join(sorted(expected - actual))
        extra = ", ".join(sorted(actual - expected))
        fail(f"Dart lockfile package set changed; missing=[{missing}] extra=[{extra}]")
    for name, (version, sha256, source) in packages.items():
        allowed_version, allowed_sha256 = DART_LOCK_ALLOWLIST[name]
        if source != "hosted":
            fail(f"Dart package {name} must remain hosted on pub.dev")
        if version != allowed_version or sha256 != allowed_sha256:
            fail(f"Dart package {name} lock changed; update provenance evidence")


def assert_bddy_provenance(scan_text: str) -> None:
    lower_scan = scan_text.lower()
    if "bddy" not in lower_scan:
        fail("bddy test dependency is not covered by the license/provenance scan")
    if BDDY_URL.lower() not in lower_scan:
        fail("bddy source URL is not covered by the license/provenance scan")
    if BDDY_COMMIT.lower() not in lower_scan:
        fail("bddy pinned commit is not covered by the license/provenance scan")


def assert_cleanroom_docs(cleanroom_text: str, provenance_text: str) -> None:
    cleanroom_lower = cleanroom_text.lower()
    provenance_lower = provenance_text.lower()
    combined = (cleanroom_text + "\n" + provenance_text).lower()
    for required in [
        "clean-room",
        "no-fetch-source build rule",
        "must not fetch",
        "via web tools",
        "spine",
        "live2d",
        "rive",
        "dragonbones",
        "lottie",
        "gltf",
        "creature",
        "capability",
        "public/textbook math",
        "human/legal review",
        "byte-compatibility",
        "disassembled binaries",
        "exact json/binary layouts",
    ]:
        if required not in cleanroom_lower:
            fail(f"clean-room provenance docs must mention {required!r}")

    if not re.search(r"must not fetch,\s+clone,\s+browse,\s+download,\s+inspect", cleanroom_lower):
        fail("CLEANROOM.md must include the explicit no-fetch-source standing instruction")
    if not re.search(r"generated\s+runtime\s+definition\s+files", cleanroom_lower):
        fail("CLEANROOM.md must forbid generated prior-art runtime definition files")
    if "spine importer is blocked for human/legal review" not in cleanroom_lower:
        fail("CLEANROOM.md must preserve the blocked Spine importer rule")

    if not re.search(
        r"no `bony` implementation is intentionally derived from spine,\s+live2d,\s+rive,\s+or\s+dragonbones runtime source",
        provenance_lower,
    ):
        fail("PROVENANCE.md must record current prior-art runtime source status")
    if "docs/nim-dependency-license-scan.md" not in provenance_text:
        fail("PROVENANCE.md must link dependency license evidence")
    if not re.search(r"not eligible merely\s+because it was recorded here", provenance_lower):
        fail("PROVENANCE.md must not allow recorded external sources to become implementation source")


def build_policy_files() -> list[Path]:
    files: list[Path] = []
    for path in BUILD_POLICY_PATHS:
        if path.is_dir():
            files.extend(child for child in path.rglob("*") if child.is_file())
        elif path.exists():
            files.append(path)
    return sorted(files)


def assert_no_forbidden_runtime_fetches() -> None:
    for path in build_policy_files():
        text = path.read_text(encoding="utf-8")
        for line_number, line in enumerate(text.splitlines(), start=1):
            lower_line = line.lower()
            if not NETWORK_FETCH_PATTERN.search(line):
                continue
            for term in PRIOR_ART_RUNTIME_TERMS:
                if term in lower_line:
                    rel = path.relative_to(ROOT)
                    fail(f"forbidden prior-art runtime source fetch in {rel}:{line_number}: {term}")


def main() -> None:
    root_license = read(ROOT_LICENSE)
    if "MIT License" not in root_license:
        fail("repository LICENSE must remain MIT")

    nimble_text = read(NIMBLE)
    pubspec_text = read(PUBSPEC)
    pubspec_lock_text = read(PUBSPEC_LOCK)
    scan_text = read(LICENSE_SCAN)
    cleanroom_text = read(CLEANROOM)
    provenance_text = read(PROVENANCE)

    assert_nim_license_scan(scan_text, nim_dependencies(nimble_text))
    assert_bddy_provenance(scan_text)
    assert_dart_provenance(pubspec_text)
    assert_dart_lock_provenance(pubspec_lock_text)
    assert_cleanroom_docs(cleanroom_text, provenance_text)
    assert_no_forbidden_runtime_fetches()


if __name__ == "__main__":
    main()
