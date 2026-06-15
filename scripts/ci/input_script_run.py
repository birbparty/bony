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

TOLERANCE = 1e-4


def _format_t(t):
    """Format a time value to the golden filename suffix.

    0.0 -> '0', 0.5 -> '0.5', 1.0 -> '1', 1.25 -> '1.25'.
    """
    if t == int(t):
        return str(int(t))
    s = f"{t:.10g}"
    return s.rstrip("0").rstrip(".")


def _check_float(actual, expected, path, errors):
    diff = abs(actual - expected)
    if diff > TOLERANCE:
        errors.append(
            f"  {path}: actual={actual:.10g}, expected={expected:.10g}, diff={diff:.3e}"
        )


def _check_exact(actual, expected, path, errors):
    if actual != expected:
        errors.append(f"  {path}: actual={actual!r}, expected={expected!r}")


def _check_matrix(actual, expected, path, errors):
    for key in ("a", "b", "c", "d", "tx", "ty"):
        _check_float(actual.get(key, 0.0), expected.get(key, 0.0), f"{path}.{key}", errors)


def compare_goldens(actual, expected):
    errors = []

    for field in ("format", "skeleton", "version"):
        _check_exact(actual.get(field), expected.get(field), field, errors)

    _check_float(actual.get("time", 0.0), expected.get("time", 0.0), "time", errors)

    actual_bones = {b["name"]: b for b in actual.get("bones", [])}
    expected_bones = {b["name"]: b for b in expected.get("bones", [])}
    for name, eb in expected_bones.items():
        if name not in actual_bones:
            errors.append(f"  bones: missing '{name}'")
            continue
        ab = actual_bones[name]
        _check_exact(ab.get("parent", ""), eb.get("parent", ""), f"bones[{name}].parent", errors)
        _check_matrix(ab["world"], eb["world"], f"bones[{name}].world", errors)
    for name in actual_bones:
        if name not in expected_bones:
            errors.append(f"  bones: unexpected extra bone '{name}'")

    actual_slots = {s["name"]: s for s in actual.get("slots", [])}
    expected_slots = {s["name"]: s for s in expected.get("slots", [])}
    for name, es in expected_slots.items():
        if name not in actual_slots:
            errors.append(f"  slots: missing '{name}'")
            continue
        as_ = actual_slots[name]
        _check_exact(as_.get("bone"), es.get("bone"), f"slots[{name}].bone", errors)
        _check_exact(as_.get("attachment"), es.get("attachment"), f"slots[{name}].attachment", errors)
        for key in ("r", "g", "b", "a"):
            _check_float(as_.get(key, 0.0), es.get(key, 0.0), f"slots[{name}].{key}", errors)
    for name in actual_slots:
        if name not in expected_slots:
            errors.append(f"  slots: unexpected extra slot '{name}'")

    av_batches = actual.get("drawBatches", [])
    ev_batches = expected.get("drawBatches", [])
    if len(av_batches) != len(ev_batches):
        errors.append(
            f"  drawBatches: count {len(av_batches)} != expected {len(ev_batches)}"
        )
    else:
        for i, (ab, eb) in enumerate(zip(av_batches, ev_batches)):
            prefix = f"drawBatches[{i}]"
            for field in ("slot", "bone", "attachment", "blendMode"):
                _check_exact(ab.get(field), eb.get(field), f"{prefix}.{field}", errors)
            _check_matrix(ab["world"], eb["world"], f"{prefix}.world", errors)
            _check_exact(ab.get("indices"), eb.get("indices"), f"{prefix}.indices", errors)
            av_verts = ab.get("vertices", [])
            ev_verts = eb.get("vertices", [])
            if len(av_verts) != len(ev_verts):
                errors.append(
                    f"  {prefix}.vertices: count {len(av_verts)} != expected {len(ev_verts)}"
                )
            else:
                for j, (av, ev) in enumerate(zip(av_verts, ev_verts)):
                    for key in ("x", "y", "u", "v", "r", "g", "b", "a"):
                        _check_float(
                            av.get(key, 0.0),
                            ev.get(key, 0.0),
                            f"{prefix}.vertices[{j}].{key}",
                            errors,
                        )

    return errors


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
