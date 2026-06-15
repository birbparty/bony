#!/usr/bin/env python3
"""Input-script conformance consumer.

Reads every conformance/scripts/*.json file, validates each against the
bony.input-script.v1 schema (spec/bony-input-script.schema.json), then
drives the golden-gen CLI for every sample and compares the output against
committed numeric goldens in conformance/goldens/.

Asset resolution: 'asset' field is a basename resolved to conformance/assets/.
Golden resolution: {stem}_t{t_formatted}.json — e.g. m2_rig.bony + t=0.0 -> m2_rig_t0.json.
  t_formatted: '0' if t == 0.0, otherwise str(t) with trailing zeros stripped.

This script is the canonical consumer of bony.input-script.v1. It validates
the format before running any CLI commands.

Usage:
  python3 scripts/ci/input_script_run.py --bony-bin /path/to/bony
  python3 scripts/ci/input_script_run.py --bony-bin /path/to/bony \\
    --scripts conformance/scripts --assets conformance/assets \\
    --goldens conformance/goldens --schema spec/bony-input-script.schema.json

Exit 0 if all samples pass; non-zero otherwise.
Requires: pip install 'jsonschema>=4.18.0,<5'
"""

import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile

try:
    import jsonschema
except ImportError:
    print(
        "error: jsonschema not installed — run: pip install 'jsonschema>=4.18.0,<5'",
        file=sys.stderr,
    )
    sys.exit(2)

from _golden_compare import compare_goldens


def _format_t(t):
    """Format a time value to the golden filename suffix.

    0.0 -> '0', 0.5 -> '0.5', 1.0 -> '1', 1.25 -> '1.25'.
    """
    if t == int(t):
        return str(int(t))
    s = f"{t:.10g}"
    return s.rstrip("0").rstrip(".")


def run_sample(bony_bin, asset_path, t, golden_path, actual_path, label):
    """Run golden-gen for one sample and compare against golden.

    Returns "pass", "fail", or "skip" (no committed golden).
    """
    if not os.path.exists(golden_path):
        print(f"SKIP {label}: no committed golden at {golden_path}")
        return "skip"

    try:
        result = subprocess.run(
            [bony_bin, "golden-gen", asset_path, actual_path, "--t", str(t)],
            capture_output=True,
            text=True,
        )
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
        print(f"FAIL {label}: {len(errors)} mismatch(es)")
        for e in errors:
            print(e)
        return "fail"

    print(f"PASS {label}")
    return "pass"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument("--scripts", default="conformance/scripts")
    parser.add_argument("--assets", default="conformance/assets")
    parser.add_argument("--goldens", default="conformance/goldens")
    parser.add_argument("--schema", default="spec/bony-input-script.schema.json")
    args = parser.parse_args()

    bony_bin = os.path.abspath(args.bony_bin)
    if not os.path.isfile(bony_bin):
        print(f"error: bony binary not found: {bony_bin}", file=sys.stderr)
        sys.exit(2)

    schema_path = args.schema
    if not os.path.isfile(schema_path):
        print(f"error: schema not found: {schema_path}", file=sys.stderr)
        sys.exit(2)

    with open(schema_path) as f:
        schema = json.load(f)

    script_files = sorted(glob.glob(os.path.join(args.scripts, "*.json")))
    if not script_files:
        print(f"error: no input scripts found in {args.scripts}", file=sys.stderr)
        sys.exit(2)

    passed = 0
    failed = 0
    skipped = 0

    with tempfile.TemporaryDirectory() as tmpdir:
        for script_path in script_files:
            script_name = os.path.basename(script_path)
            with open(script_path) as f:
                script = json.load(f)

            # Validate schema
            try:
                jsonschema.validate(instance=script, schema=schema)
            except jsonschema.ValidationError as exc:
                print(f"FAIL {script_name}: schema validation: {exc.message}")
                failed += 1
                continue

            asset_stem = os.path.splitext(script["asset"])[0]
            asset_path = os.path.join(args.assets, script["asset"])
            if not os.path.isfile(asset_path):
                print(f"FAIL {script_name}: asset not found: {asset_path}")
                failed += 1
                continue

            for i, sample in enumerate(script["samples"]):
                t = sample["t"]
                inputs = sample.get("inputs") or {}
                if inputs:
                    print(
                        f"warning: {script_name}[{i}]: non-empty inputs are reserved "
                        f"(state-machine support not yet available); inputs will be ignored"
                    )
                t_suffix = _format_t(t)
                golden_path = os.path.join(args.goldens, f"{asset_stem}_t{t_suffix}.json")
                actual_path = os.path.join(tmpdir, f"{asset_stem}_sample{i}_actual.json")
                label = f"{script_name}[{i}] t={t}"

                outcome = run_sample(bony_bin, asset_path, t, golden_path, actual_path, label)
                if outcome == "pass":
                    passed += 1
                elif outcome == "fail":
                    failed += 1
                else:
                    skipped += 1

    print(f"\n{passed} passed, {failed} failed, {skipped} skipped")

    if passed == 0 and failed == 0:
        print("error: no samples were checked — gate is vacuously green", file=sys.stderr)
        sys.exit(2)

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
