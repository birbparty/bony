#!/usr/bin/env python3
"""Numeric golden conformance runner.

Generates fresh goldens from conformance/assets/*.bony using the bony CLI,
then compares each against the committed golden in conformance/goldens/.
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

TOLERANCE = 1e-4


def _check_float(actual, expected, path, errors):
    diff = abs(actual - expected)
    if diff > TOLERANCE:
        errors.append(
            f"  {path}: actual={actual:.10g}, expected={expected:.10g}, diff={diff:.3e} > {TOLERANCE:.0e}"
        )


def _check_exact(actual, expected, path, errors):
    if actual != expected:
        errors.append(f"  {path}: actual={actual!r}, expected={expected!r}")


def _check_matrix(actual, expected, path, errors):
    for key in ("a", "b", "c", "d", "tx", "ty"):
        _check_float(actual.get(key, 0.0), expected.get(key, 0.0), f"{path}.{key}", errors)


def compare_goldens(actual, expected):
    """Return list of error strings; empty list means PASS."""
    errors = []

    for field in ("format", "skeleton", "version"):
        _check_exact(actual.get(field), expected.get(field), field, errors)

    _check_float(actual.get("time", 0.0), expected.get("time", 0.0), "time", errors)

    # Bones (keyed by name; order is defined, but name is the natural key)
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

    # Slots (keyed by name)
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

    # DrawBatches: compared positionally to catch draw-order regressions
    # and handle rigs where the same slot appears in multiple batches.
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
            # Indices compared exactly (winding and topology must be bit-identical)
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


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument("--assets-dir", default="conformance/assets")
    parser.add_argument("--goldens-dir", default="conformance/goldens")
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
            golden_path = os.path.join(args.goldens_dir, f"{stem}_t0.json")

            if not os.path.exists(golden_path):
                print(f"SKIP {stem}: no committed golden at {golden_path}")
                skipped += 1
                continue

            actual_path = os.path.join(tmpdir, f"{stem}_actual.json")

            try:
                result = subprocess.run(
                    [bony_bin, "golden-gen", asset_path, actual_path, "--t", "0.0"],
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
            except Exception as exc:
                print(f"FAIL {stem}: {exc}")
                failed += 1
                continue

            if errors:
                print(f"FAIL {stem}: {len(errors)} mismatch(es) (tolerance={TOLERANCE:.0e})")
                for e in errors:
                    print(e)
                failed += 1
            else:
                print(f"PASS {stem}")
                passed += 1

    print(f"\n{passed} passed, {failed} failed, {skipped} skipped")

    if passed == 0 and failed == 0:
        print("error: no goldens were checked — gate is vacuously green", file=sys.stderr)
        sys.exit(2)

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
