#!/usr/bin/env python3
"""Numeric golden conformance runner.

Generates fresh goldens from conformance/assets/*.bony using the bony CLI,
then compares each against the committed golden in conformance/goldens/.
All numeric values are compared with absolute tolerance 1e-4 (the Dart gate).

Usage:
  python3 scripts/ci/conformance_run.py --bony-bin /path/to/bony
  python3 scripts/ci/conformance_run.py --bony-bin /tmp/bony_bin --t 0.0

Exit 0 if all committed goldens pass; non-zero otherwise.
"""

import argparse
import glob
import json
import os
import subprocess
import sys
import tempfile

TOLERANCE = 1e-4


def _check_float(actual, expected, path, errors):
    diff = abs(actual - expected)
    if diff > TOLERANCE:
        errors.append(
            f"  {path}: actual={actual:.10g}, expected={expected:.10g}, diff={diff:.3e} > {TOLERANCE:.0e}"
        )


def _check_matrix(actual, expected, path, errors):
    for key in ("a", "b", "c", "d", "tx", "ty"):
        _check_float(actual.get(key, 0.0), expected.get(key, 0.0), f"{path}.{key}", errors)


def compare_goldens(actual, expected):
    """Return list of error strings; empty list means PASS."""
    errors = []

    for field in ("format", "skeleton", "version"):
        if actual.get(field) != expected.get(field):
            errors.append(
                f"  {field}: actual={actual.get(field)!r}, expected={expected.get(field)!r}"
            )

    _check_float(actual.get("time", 0.0), expected.get("time", 0.0), "time", errors)

    # Bones (keyed by name)
    actual_bones = {b["name"]: b for b in actual.get("bones", [])}
    expected_bones = {b["name"]: b for b in expected.get("bones", [])}
    for name, eb in expected_bones.items():
        if name not in actual_bones:
            errors.append(f"  bones: missing '{name}'")
            continue
        _check_matrix(actual_bones[name]["world"], eb["world"], f"bones[{name}].world", errors)
    for name in actual_bones:
        if name not in expected_bones:
            errors.append(f"  bones: unexpected extra bone '{name}'")

    # Slots (keyed by name)
    actual_slots = {s["name"]: s for s in actual.get("slots", [])}
    expected_slots = {s["name"]: s for s in expected.get("slots", [])}
    for name, es in expected_slots.items():
        if name not in actual_slots:
            errors.append(f"  slots: missing '{name}'")
            continue
        for key in ("r", "g", "b", "a"):
            _check_float(
                actual_slots[name].get(key, 0.0),
                es.get(key, 0.0),
                f"slots[{name}].{key}",
                errors,
            )

    # DrawBatches (keyed by slot name)
    actual_batches = {b["slot"]: b for b in actual.get("drawBatches", [])}
    expected_batches = {b["slot"]: b for b in expected.get("drawBatches", [])}
    for slot_name, eb in expected_batches.items():
        if slot_name not in actual_batches:
            errors.append(f"  drawBatches: missing batch for slot '{slot_name}'")
            continue
        ab = actual_batches[slot_name]
        _check_matrix(ab["world"], eb["world"], f"drawBatches[{slot_name}].world", errors)
        av_verts = ab.get("vertices", [])
        ev_verts = eb.get("vertices", [])
        if len(av_verts) != len(ev_verts):
            errors.append(
                f"  drawBatches[{slot_name}].vertices: count {len(av_verts)} != expected {len(ev_verts)}"
            )
        else:
            for i, (av, ev) in enumerate(zip(av_verts, ev_verts)):
                for key in ("x", "y", "u", "v", "r", "g", "b", "a"):
                    _check_float(
                        av.get(key, 0.0),
                        ev.get(key, 0.0),
                        f"drawBatches[{slot_name}].vertices[{i}].{key}",
                        errors,
                    )

    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument("--assets-dir", default="conformance/assets")
    parser.add_argument("--goldens-dir", default="conformance/goldens")
    parser.add_argument("--t", default="0.0", help="Time value for golden-gen (default: 0.0)")
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

    with tempfile.TemporaryDirectory() as tmpdir:
        for asset_path in asset_files:
            stem = os.path.splitext(os.path.basename(asset_path))[0]
            suffix = f"_t{args.t.replace('.', '_').rstrip('0').rstrip('_')}"
            if suffix == "_t":
                suffix = "_t0"
            golden_path = os.path.join(args.goldens_dir, f"{stem}_t0.json")

            if not os.path.exists(golden_path):
                print(f"SKIP {stem}: no committed golden at {golden_path}")
                skipped += 1
                continue

            actual_path = os.path.join(tmpdir, f"{stem}_actual.json")
            result = subprocess.run(
                [bony_bin, "golden-gen", asset_path, actual_path, "--t", args.t],
                capture_output=True,
                text=True,
            )
            if result.returncode != 0:
                print(f"FAIL {stem}: golden-gen exited {result.returncode}")
                if result.stderr:
                    print(result.stderr.rstrip())
                failed += 1
                continue

            with open(actual_path) as f:
                actual = json.load(f)
            with open(golden_path) as f:
                expected = json.load(f)

            errors = compare_goldens(actual, expected)
            if errors:
                print(f"FAIL {stem}: {len(errors)} mismatch(es) (tolerance={TOLERANCE:.0e})")
                for e in errors:
                    print(e)
                failed += 1
            else:
                print(f"PASS {stem}")
                passed += 1

    print(f"\n{passed} passed, {failed} failed, {skipped} skipped")
    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
