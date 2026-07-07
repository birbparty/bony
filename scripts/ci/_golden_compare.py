"""Shared numeric golden comparison and golden-gen runner helpers for CI scripts.

Canonical source for compare_goldens() — import from here, do not duplicate.
"""

import json
import os
import subprocess

from _common import Outcome


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


def _check_json(actual, expected, path, errors):
    if isinstance(expected, bool) or isinstance(actual, bool):
        _check_exact(actual, expected, path, errors)
    elif isinstance(expected, (int, float)) or isinstance(actual, (int, float)):
        if not isinstance(actual, (int, float)) or not isinstance(expected, (int, float)):
            errors.append(f"  {path}: actual={actual!r}, expected={expected!r}")
        else:
            _check_float(actual, expected, path, errors)
    elif isinstance(expected, str) or isinstance(actual, str) or expected is None or actual is None:
        _check_exact(actual, expected, path, errors)
    elif isinstance(expected, list) and isinstance(actual, list):
        if len(actual) != len(expected):
            errors.append(f"  {path}: count {len(actual)} != expected {len(expected)}")
            return
        for index, (actual_item, expected_item) in enumerate(zip(actual, expected)):
            _check_json(actual_item, expected_item, f"{path}[{index}]", errors)
    elif isinstance(expected, dict) and isinstance(actual, dict):
        actual_keys = set(actual)
        expected_keys = set(expected)
        for key in sorted(expected_keys - actual_keys):
            errors.append(f"  {path}: missing key {key!r}")
        for key in sorted(actual_keys - expected_keys):
            errors.append(f"  {path}: unexpected key {key!r}")
        for key in sorted(actual_keys & expected_keys):
            _check_json(actual[key], expected[key], f"{path}.{key}", errors)
    else:
        _check_exact(actual, expected, path, errors)


def compare_goldens(actual, expected):
    """Return list of error strings; empty list means PASS."""
    errors = []

    for field in ("format", "skeleton", "version", "stateMachine", "sample"):
        _check_exact(actual.get(field), expected.get(field), field, errors)

    _check_float(actual.get("time", 0.0), expected.get("time", 0.0), "time", errors)

    state_machine_golden = (
        actual.get("stateMachine") is not None
        or expected.get("stateMachine") is not None
        or actual.get("sample") is not None
        or expected.get("sample") is not None
    )
    for field in ("inputs", "layers", "events"):
        if state_machine_golden:
            if field not in actual:
                errors.append(f"  {field}: missing from actual state-machine golden")
            if field not in expected:
                errors.append(f"  {field}: missing from expected state-machine golden")
            if field in actual and field in expected:
                _check_json(actual[field], expected[field], field, errors)
        elif field in actual or field in expected:
            _check_json(actual.get(field), expected.get(field), field, errors)

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
        for key in ("darkR", "darkG", "darkB", "sequenceDelay"):
            if key in as_ or key in es:
                if key not in as_:
                    errors.append(f"  slots[{name}].{key}: missing from actual")
                elif key not in es:
                    errors.append(f"  slots[{name}].{key}: unexpected in actual")
                else:
                    _check_float(as_[key], es[key], f"slots[{name}].{key}", errors)
        for key in ("sequenceIndex", "sequenceMode"):
            if key in as_ or key in es:
                if key not in as_:
                    errors.append(f"  slots[{name}].{key}: missing from actual")
                elif key not in es:
                    errors.append(f"  slots[{name}].{key}: unexpected in actual")
                else:
                    _check_exact(as_[key], es[key], f"slots[{name}].{key}", errors)
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


def run_golden_gen_check(
    bony_bin,
    asset_path,
    golden_path,
    actual_path,
    label,
    *,
    t=None,
    state_machine=None,
    input_script=None,
    sample_selector=None,
):
    """Run golden-gen for one asset/sample and compare against golden_path."""
    if state_machine and (not input_script or not sample_selector):
        raise ValueError("state-machine golden checks require input_script and sample_selector")
    if input_script and not sample_selector:
        raise ValueError("input-script golden checks require sample_selector")

    if not os.path.exists(golden_path):
        print(f"SKIP {label}: no committed golden at {golden_path}")
        return Outcome.SKIP

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
        elif input_script:
            cmd.extend(["--input-script", input_script, "--sample", sample_selector])
        else:
            cmd.extend(["--t", str(t if t is not None else 0.0)])
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            print(f"FAIL {label}: golden-gen exited {result.returncode}")
            if result.stderr:
                print(result.stderr.rstrip())
            return Outcome.FAIL

        with open(actual_path) as f:
            actual = json.load(f)
        with open(golden_path) as f:
            expected = json.load(f)

        errors = compare_goldens(actual, expected)
    except Exception as exc:
        print(f"FAIL {label}: {exc}")
        return Outcome.FAIL

    if errors:
        print(f"FAIL {label}: {len(errors)} mismatch(es) (tolerance={TOLERANCE:.0e})")
        for e in errors:
            print(e)
        return Outcome.FAIL

    print(f"PASS {label}")
    return Outcome.PASS
