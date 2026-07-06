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
import json
import os
import subprocess
import sys
import tempfile

from _golden_compare import TOLERANCE, compare_goldens


def _object_without_duplicate_keys(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON object key: {key}")
        result[key] = value
    return result


def _load_json_without_duplicate_keys(path):
    with open(path) as f:
        return json.load(f, object_pairs_hook=_object_without_duplicate_keys)


def setup_child_scripts(scripts_dir):
    """Return asset basename -> (script_path, sample_selector) for nested setup scripts."""
    result = {}
    for script_path in sorted(glob.glob(os.path.join(scripts_dir, "*.json"))):
        try:
            script = _load_json_without_duplicate_keys(script_path)
        except Exception:
            continue
        if script.get("stateMachine") or not script.get("children"):
            continue
        samples = script.get("samples") or []
        if len(samples) != 1:
            continue
        sample = samples[0]
        selector = sample.get("name") or "0"
        result[script["asset"]] = (script_path, selector)
    return result


def run_golden_check(
    bony_bin,
    asset_path,
    golden_path,
    actual_path,
    label,
    *,
    input_script=None,
    sample_selector=None,
):
    """Run golden-gen on asset_path and compare against golden_path.

    Returns "pass", "fail", or "skip" (if no committed golden).
    Prints a PASS/FAIL/SKIP line.
    """
    if not os.path.exists(golden_path):
        print(f"SKIP {label}: no committed golden at {golden_path}")
        return "skip"

    try:
        cmd = [bony_bin, "golden-gen", asset_path, actual_path]
        if input_script:
            cmd.extend(["--input-script", input_script, "--sample", sample_selector])
        else:
            cmd.extend(["--t", "0.0"])
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"FAIL {label}: golden-gen exited {result.returncode}")
            if result.stderr:
                print(result.stderr.rstrip())
            return "fail"

        with open(actual_path) as f:
            actual = json.load(f)
        with open(golden_path) as f:
            expected = json.load(f)

        errors = compare_goldens(actual, expected)
    except Exception as exc:
        print(f"FAIL {label}: {exc}")
        return "fail"

    if errors:
        print(f"FAIL {label}: {len(errors)} mismatch(es) (tolerance={TOLERANCE:.0e})")
        for e in errors:
            print(e)
        return "fail"

    print(f"PASS {label}")
    return "pass"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument("--assets-dir", default="conformance/assets")
    parser.add_argument("--goldens-dir", default="conformance/goldens")
    parser.add_argument("--scripts-dir", default="conformance/scripts")
    args = parser.parse_args()

    bony_bin = os.path.abspath(args.bony_bin)
    if not os.path.isfile(bony_bin):
        print(f"error: bony binary not found: {bony_bin}", file=sys.stderr)
        sys.exit(2)

    asset_files = sorted(glob.glob(os.path.join(args.assets_dir, "*.bony")))
    if not asset_files:
        print(f"error: no .bony assets found in {args.assets_dir}", file=sys.stderr)
        sys.exit(2)

    passed = 0
    failed = 0
    skipped = 0
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
            outcome = run_golden_check(
                bony_bin, asset_path, golden_path, actual_path, stem, **script_args
            )
            if outcome == "pass":
                passed += 1
            elif outcome == "fail":
                failed += 1
            else:
                skipped += 1

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
                outcome = run_golden_check(
                    bony_bin, asset_path, golden_path, actual_path, label, **script_args
                )
                if outcome == "pass":
                    passed += 1
                elif outcome == "fail":
                    failed += 1
                else:
                    skipped += 1

    print(f"\n{passed} passed, {failed} failed, {skipped} skipped")

    if passed == 0 and failed == 0:
        print("error: no goldens were checked — gate is vacuously green", file=sys.stderr)
        sys.exit(2)

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
