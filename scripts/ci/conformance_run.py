#!/usr/bin/env python3
"""Numeric golden conformance runner.

Generates fresh goldens from conformance/assets/*.bony using the bony CLI,
then compares each against the committed golden in conformance/goldens/.
Also runs golden-gen on conformance/assets/bnb/*.bnb and verifies the output
matches the same committed goldens (M6 gate: .bnb-decoded poses must match
.bony-decoded poses within tolerance).
All numeric values are compared with absolute tolerance 1e-4 (the Dart gate).
String/integer fields (indices, names, blend modes) are compared exactly.

Usage:
  python3 scripts/ci/conformance_run.py --bony-bin /path/to/bony

Exit 0 if all committed goldens pass; non-zero otherwise.
"""

import argparse
import glob
import os
import sys
import tempfile

from _common import (
    GateTally,
    load_json_without_duplicate_keys,
    require_glob,
    resolve_bony_bin,
)
from _golden_compare import run_golden_gen_check


def setup_child_scripts(scripts_dir):
    """Return asset basename -> (script_path, sample_selector) for nested setup scripts."""
    result = {}
    for script_path in sorted(glob.glob(os.path.join(scripts_dir, "*.json"))):
        try:
            script = load_json_without_duplicate_keys(script_path)
        except Exception:
            continue
        if script.get("stateMachine") or not script.get("children"):
            continue
        samples = script.get("samples") or []
        if len(samples) != 1:
            print(
                f"WARN {os.path.basename(script_path)}: expected exactly one setup sample "
                f"for conformance child script lookup, found {len(samples)}; ignoring",
                file=sys.stderr,
            )
            continue
        sample = samples[0]
        selector = sample.get("name") or "0"
        result[script["asset"]] = (script_path, selector)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument("--assets-dir", default="conformance/assets")
    parser.add_argument("--goldens-dir", default="conformance/goldens")
    parser.add_argument("--scripts-dir", default="conformance/scripts")
    args = parser.parse_args()

    bony_bin = resolve_bony_bin(args)
    asset_files = require_glob(
        os.path.join(args.assets_dir, "*.bony"),
        f".bony assets in {args.assets_dir}",
    )

    tally = GateTally()
    child_scripts = setup_child_scripts(args.scripts_dir)

    with tempfile.TemporaryDirectory() as tmpdir:
        # --- .bony gate ---
        print("=== .bony assets ===")
        for asset_path in asset_files:
            stem = os.path.splitext(os.path.basename(asset_path))[0]
            golden_path = os.path.join(args.goldens_dir, f"{stem}_t0.json")
            actual_path = os.path.join(tmpdir, f"{stem}_actual.json")
            script_entry = child_scripts.get(os.path.basename(asset_path))
            script_args = {}
            if script_entry:
                script_args = {
                    "input_script": script_entry[0],
                    "sample_selector": script_entry[1],
                }
            outcome = run_golden_gen_check(
                bony_bin, asset_path, golden_path, actual_path, stem, **script_args
            )
            tally.record(outcome)

        # --- .bnb gate (M6): decoded-from-.bnb poses must match .bony-decoded goldens ---
        bnb_dir = os.path.join(args.assets_dir, "bnb")
        bnb_files = sorted(glob.glob(os.path.join(bnb_dir, "*.bnb")))
        if bnb_files:
            print("\n=== .bnb assets (M6 gate) ===")
            for asset_path in bnb_files:
                stem = os.path.splitext(os.path.basename(asset_path))[0]
                golden_path = os.path.join(args.goldens_dir, f"{stem}_t0.json")
                # _bnb_ infix avoids tmpdir collision with same-stem .bony output
                actual_path = os.path.join(tmpdir, f"{stem}_bnb_actual.json")
                label = f"{stem}.bnb"
                script_entry = child_scripts.get(f"{stem}.bony")
                script_args = {}
                if script_entry:
                    script_args = {
                        "input_script": script_entry[0],
                        "sample_selector": script_entry[1],
                    }
                outcome = run_golden_gen_check(
                    bony_bin, asset_path, golden_path, actual_path, label, **script_args
                )
                tally.record(outcome)

    print(f"\n{tally.summary_line()}")

    tally.assert_not_vacuous("goldens")
    sys.exit(tally.exit_code())


if __name__ == "__main__":
    main()
