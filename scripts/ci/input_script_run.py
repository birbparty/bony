#!/usr/bin/env python3
"""Input-script conformance consumer.

Reads every conformance/scripts/*.json file, validates each against the
bony.input-script.v1 schema (spec/bony-input-script.schema.json), then
drives the golden-gen CLI for every sample and compares the output against
committed numeric goldens in conformance/goldens/.

Asset resolution: 'asset' field is a basename resolved to conformance/assets/.
Setup golden resolution: {stem}_t{t_formatted}.json — e.g. m2_rig.bony + t=0.0 -> m2_rig_t0.json.
State-machine golden resolution: {script_stem}_{sample_name}.json. State-machine
scripts are replayed against the source .bony asset and, when present, the
matching conformance/assets/bnb/<asset-stem>.bnb fixture using the same golden.
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
import re
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


SAMPLE_NAME_RE = re.compile(r"^(?=.*[^0-9])[A-Za-z0-9_.-]+$")


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


def _format_t(t):
    """Format a time value to the golden filename suffix.

    0.0 -> '0', 0.5 -> '0.5', 1.0 -> '1', 1.25 -> '1.25'.
    """
    if t == int(t):
        return str(int(t))
    s = f"{t:.10g}"
    return s.rstrip("0").rstrip(".")


def run_sample(
    bony_bin,
    asset_path,
    t,
    golden_path,
    actual_path,
    label,
    *,
    state_machine=None,
    input_script=None,
    sample_selector=None,
):
    """Run golden-gen for one sample and compare against golden.

    Returns "pass", "fail", or "skip" (no committed golden).
    """
    if not os.path.exists(golden_path):
        print(f"SKIP {label}: no committed golden at {golden_path}")
        return "skip"

    try:
        cmd = [bony_bin, "golden-gen", asset_path, actual_path]
        if state_machine:
            cmd.extend(
                [
                    "--state-machine",
                    state_machine,
                    "--input-script",
                    input_script,
                    "--sample",
                    sample_selector,
                ]
            )
        else:
            cmd.extend(["--t", str(t)])
        result = subprocess.run(
            cmd,
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

    schema = _load_json_without_duplicate_keys(schema_path)

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
            try:
                script = _load_json_without_duplicate_keys(script_path)
            except ValueError as exc:
                print(f"FAIL {script_name}: JSON validation: {exc}")
                failed += 1
                continue

            # Validate schema
            try:
                jsonschema.validate(instance=script, schema=schema)
            except jsonschema.ValidationError as exc:
                print(f"FAIL {script_name}: schema validation: {exc.message}")
                failed += 1
                continue

            asset_stem = os.path.splitext(script["asset"])[0]
            asset_ext = os.path.splitext(script["asset"])[1]
            script_stem = os.path.splitext(script_name)[0]
            asset_path = os.path.join(args.assets, script["asset"])
            if not os.path.isfile(asset_path):
                print(f"FAIL {script_name}: asset not found: {asset_path}")
                failed += 1
                continue

            state_machine = script.get("stateMachine")
            if state_machine:
                seen_names = set()
                previous_t = 0.0
                script_valid = True
                for i, sample in enumerate(script["samples"]):
                    sample_name = sample.get("name")
                    if not sample_name:
                        print(f"FAIL {script_name}[{i}]: state-machine samples require name")
                        failed += 1
                        script_valid = False
                        continue
                    if not SAMPLE_NAME_RE.match(sample_name):
                        print(f"FAIL {script_name}[{i}]: invalid or numeric-only sample name: {sample_name!r}")
                        failed += 1
                        script_valid = False
                        continue
                    if sample_name in seen_names:
                        print(f"FAIL {script_name}[{i}]: duplicate sample name: {sample_name}")
                        failed += 1
                        script_valid = False
                        continue
                    seen_names.add(sample_name)
                    t = sample["t"]
                    if i > 0 and t < previous_t:
                        print(f"FAIL {script_name}[{i}]: sample times must be non-decreasing")
                        failed += 1
                        script_valid = False
                    previous_t = t
                if not script_valid:
                    continue

            for i, sample in enumerate(script["samples"]):
                t = sample["t"]
                inputs = sample.get("inputs") or {}
                if state_machine:
                    sample_name = sample["name"]
                    golden_path = os.path.join(args.goldens, f"{script_stem}_{sample_name}.json")
                    replay_assets = [(asset_ext or ".bony", asset_path)]
                    bnb_path = os.path.join(args.assets, "bnb", f"{asset_stem}.bnb")
                    if not os.path.isfile(bnb_path):
                        print(f"FAIL {script_name}[.bnb][{sample_name}]: asset not found: {bnb_path}")
                        failed += 1
                    else:
                        replay_assets.append((".bnb", bnb_path))
                    for replay_ext, replay_asset_path in replay_assets:
                        actual_path = os.path.join(
                            tmpdir,
                            f"{script_stem}_{sample_name}_{replay_ext.lstrip('.')}_actual.json",
                        )
                        label = f"{script_name}[{replay_ext}][{sample_name}] t={t}"
                        outcome = run_sample(
                            bony_bin,
                            replay_asset_path,
                            t,
                            golden_path,
                            actual_path,
                            label,
                            state_machine=state_machine,
                            input_script=script_path,
                            sample_selector=sample_name,
                        )
                        if outcome == "pass":
                            passed += 1
                        elif outcome == "fail":
                            failed += 1
                        else:
                            skipped += 1
                    continue
                else:
                    if inputs:
                        print(f"FAIL {script_name}[{i}]: inputs require stateMachine")
                        failed += 1
                        continue
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
