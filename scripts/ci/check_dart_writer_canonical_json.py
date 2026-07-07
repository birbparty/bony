#!/usr/bin/env python3
"""Check Nim canonical JSON fixtures for the Dart writer parity tests."""

from __future__ import annotations

import argparse
import filecmp
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
JSON_ASSET_DIR = REPO_ROOT / "conformance" / "assets"
BNB_ASSET_DIR = JSON_ASSET_DIR / "bnb"
FIXTURE_ROOT = REPO_ROOT / "conformance" / "goldens" / "canonical-json"
SKIP_BNB = {"forward_compat.bnb"}


def run(cmd: list[str]) -> None:
    subprocess.run(cmd, cwd=REPO_ROOT, check=True)


def build_cli(work_dir: Path) -> Path:
    cli = work_dir / "bony"
    run(
        [
            "nim",
            "c",
            "--hints:off",
            "-d:release",
            "--path:runtime-nim/src",
            f"-o:{cli}",
            "cli/bony_cli.nim",
        ]
    )
    return cli


def canonicalize_json_asset(cli: Path, source: Path, work_dir: Path) -> bytes:
    bnb_path = work_dir / f"{source.stem}.bnb"
    json_path = work_dir / source.name
    run([str(cli), "json-to-bnb", str(source), str(bnb_path)])
    run([str(cli), "bnb-to-json", str(bnb_path), str(json_path)])
    return json_path.read_bytes()


def canonicalize_bnb_asset(cli: Path, source: Path, work_dir: Path) -> bytes:
    json_path = work_dir / f"{source.stem}.bony"
    run([str(cli), "bnb-to-json", str(source), str(json_path)])
    return json_path.read_bytes()


def write_if_changed(path: Path, content: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_bytes() == content:
        return
    path.write_bytes(content)


def check_fixture(path: Path, content: bytes, update: bool) -> bool:
    if update:
        write_if_changed(path, content)
        return True
    if not path.exists():
        print(f"MISSING {path.relative_to(REPO_ROOT)}")
        return False
    with tempfile.NamedTemporaryFile() as generated:
        generated.write(content)
        generated.flush()
        if filecmp.cmp(path, generated.name, shallow=False):
            return True
    print(f"STALE {path.relative_to(REPO_ROOT)}")
    return False


def fixture_pairs(cli: Path, work_dir: Path) -> list[tuple[Path, bytes]]:
    pairs: list[tuple[Path, bytes]] = []
    for source in sorted(JSON_ASSET_DIR.glob("*.bony")):
        target = FIXTURE_ROOT / "json" / source.name
        pairs.append((target, canonicalize_json_asset(cli, source, work_dir)))
    for source in sorted(BNB_ASSET_DIR.glob("*.bnb")):
        if source.name in SKIP_BNB:
            continue
        target = FIXTURE_ROOT / "bnb" / f"{source.stem}.bony"
        pairs.append((target, canonicalize_bnb_asset(cli, source, work_dir)))
    return pairs


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Regenerate Nim canonical JSON fixtures for Dart writer parity and "
            "fail when committed fixtures are missing or stale."
        )
    )
    parser.add_argument(
        "--update",
        action="store_true",
        help="write missing or stale fixtures instead of failing",
    )
    parser.add_argument(
        "--bony-bin",
        type=Path,
        help="reuse an existing bony CLI binary instead of compiling one",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    with tempfile.TemporaryDirectory(prefix="bony-canonical-json-") as tmp:
        work_dir = Path(tmp)
        cli = args.bony_bin.resolve() if args.bony_bin else build_cli(work_dir)
        if not cli.exists():
            print(f"missing bony CLI binary: {cli}", file=sys.stderr)
            return 2
        pairs = fixture_pairs(cli, work_dir)
        if not pairs:
            print("no canonical JSON fixtures were generated", file=sys.stderr)
            return 2
        ok = True
        expected_paths = {target for target, _ in pairs}
        for target, content in pairs:
            ok = check_fixture(target, content, args.update) and ok
        extra = sorted(FIXTURE_ROOT.glob("*/*.bony"))
        for path in extra:
            if path not in expected_paths:
                if args.update:
                    path.unlink()
                else:
                    print(f"EXTRA {path.relative_to(REPO_ROOT)}")
                    ok = False
        if args.update:
            print(f"Updated {len(pairs)} canonical JSON fixtures")
            return 0
        if ok:
            print(f"Checked {len(pairs)} canonical JSON fixtures")
            return 0
        print("Run scripts/ci/check_dart_writer_canonical_json.py --update")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
