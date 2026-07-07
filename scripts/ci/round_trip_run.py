#!/usr/bin/env python3
"""Round-trip conformance runner — both directions.

Direction 1 (json→bnb idempotency): For each conformance/assets/*.bony that
has a matching conformance/assets/bnb/{stem}.bnb, converts the .bony to .bnb
via `bony json-to-bnb` and compares the bytes against the committed golden
.bnb file.  Byte-identical output proves canonical serialization is stable.

Direction 2 (bnb→json→bnb byte-stability): For each conformance/assets/bnb/
*_rig.bnb, converts to JSON via `bony bnb-to-json`, converts that JSON back to
.bnb via `bony json-to-bnb`, and compares the resulting bytes against the
original .bnb file.  Byte-identical output proves the round-trip is lossless.

Usage:
  python3 scripts/ci/round_trip_run.py --bony-bin /path/to/bony

Exit 0 if all checks pass; non-zero otherwise.
"""

import argparse
import glob
import os
import subprocess
import sys
import tempfile

from _common import GateTally, require_glob, resolve_bony_bin


ONE_WAY_BNB_FIXTURES = {
    "forward_compat.bnb",
}


def run_json_to_bnb(bony_bin, src_bony, dst_bnb):
    """Run json-to-bnb, return (returncode, stderr)."""
    result = subprocess.run(
        [bony_bin, "json-to-bnb", src_bony, dst_bnb],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stderr


def run_bnb_to_json(bony_bin, src_bnb, dst_bony):
    """Run bnb-to-json, return (returncode, stderr)."""
    result = subprocess.run(
        [bony_bin, "bnb-to-json", src_bnb, dst_bony],
        capture_output=True,
        text=True,
    )
    return result.returncode, result.stderr


def bytes_equal(path_a, path_b):
    """Return True if the two files have identical byte content."""
    with open(path_a, "rb") as f:
        a = f.read()
    with open(path_b, "rb") as f:
        b = f.read()
    return a == b, len(a), len(b)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument("--assets-dir", default="conformance/assets")
    args = parser.parse_args()

    bony_bin = resolve_bony_bin(args)

    bnb_dir = os.path.join(args.assets_dir, "bnb")
    bony_files = require_glob(
        os.path.join(args.assets_dir, "*.bony"),
        f".bony assets in {args.assets_dir}",
    )
    bnb_files = [
        path
        for path in sorted(glob.glob(os.path.join(bnb_dir, "*.bnb")))
        if os.path.basename(path) not in ONE_WAY_BNB_FIXTURES
    ]

    tally = GateTally()
    dir1_ran = 0
    dir2_ran = 0

    with tempfile.TemporaryDirectory() as tmpdir:

        # --- Direction 1: json→bnb idempotency ---
        print("=== json→bnb idempotency (.bony → .bnb bytes match golden) ===")
        for bony_path in bony_files:
            stem = os.path.splitext(os.path.basename(bony_path))[0]
            golden_bnb = os.path.join(bnb_dir, f"{stem}.bnb")
            label = stem

            if not os.path.exists(golden_bnb):
                print(f"SKIP {label}: no committed golden at {golden_bnb}")
                tally.skipped += 1
                continue

            dir1_ran += 1
            out_bnb = os.path.join(tmpdir, f"{stem}_from_json.bnb")
            try:
                rc, stderr = run_json_to_bnb(bony_bin, bony_path, out_bnb)
                if rc != 0:
                    print(f"FAIL {label}: json-to-bnb exited {rc}")
                    if stderr:
                        print(stderr.rstrip())
                    tally.failed += 1
                    continue

                match, actual_len, _ = bytes_equal(out_bnb, golden_bnb)
                if match:
                    print(f"PASS {label} ({actual_len} bytes)")
                    tally.passed += 1
                else:
                    print(f"FAIL {label}: byte mismatch ({actual_len} bytes vs golden)")
                    tally.failed += 1
            except Exception as exc:
                print(f"FAIL {label}: {exc}")
                tally.failed += 1

        # --- Direction 2: bnb→json→bnb byte-stability ---
        print("\n=== bnb→json→bnb byte-stability (.bnb round-trip is lossless) ===")
        if not bnb_files:
            print(f"  (no *_rig.bnb files found in {bnb_dir})")
        for bnb_path in bnb_files:
            stem = os.path.splitext(os.path.basename(bnb_path))[0]
            label = f"{stem}.bnb"

            dir2_ran += 1
            mid_bony = os.path.join(tmpdir, f"{stem}_mid.bony")
            out_bnb = os.path.join(tmpdir, f"{stem}_roundtrip.bnb")
            try:
                rc, stderr = run_bnb_to_json(bony_bin, bnb_path, mid_bony)
                if rc != 0:
                    print(f"FAIL {label}: bnb-to-json exited {rc}")
                    if stderr:
                        print(stderr.rstrip())
                    tally.failed += 1
                    continue

                rc, stderr = run_json_to_bnb(bony_bin, mid_bony, out_bnb)
                if rc != 0:
                    print(f"FAIL {label}: json-to-bnb exited {rc}")
                    if stderr:
                        print(stderr.rstrip())
                    tally.failed += 1
                    continue

                match, actual_len, _ = bytes_equal(out_bnb, bnb_path)
                if match:
                    print(f"PASS {label} ({actual_len} bytes)")
                    tally.passed += 1
                else:
                    print(
                        f"FAIL {label}: byte mismatch after round-trip "
                        f"({actual_len} bytes vs original)"
                    )
                    tally.failed += 1
            except Exception as exc:
                print(f"FAIL {label}: {exc}")
                tally.failed += 1

    print(f"\n{tally.summary_line()}")

    if dir1_ran == 0:
        print(
            "error: Direction 1 (json→bnb) ran no checks — gate is vacuously green",
            file=sys.stderr,
        )
        sys.exit(2)
    if dir2_ran == 0:
        print(
            "error: Direction 2 (bnb→json→bnb) ran no checks — gate is vacuously green",
            file=sys.stderr,
        )
        sys.exit(2)

    sys.exit(tally.exit_code())


if __name__ == "__main__":
    main()
