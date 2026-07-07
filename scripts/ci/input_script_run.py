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
import os
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

from _common import (
    GateTally,
    load_json_without_duplicate_keys,
    require_glob,
    resolve_bony_bin,
)
from _golden_compare import run_golden_gen_check


def _format_t(t):
    """Format a time value to the golden filename suffix.

    0.0 -> '0', 0.5 -> '0.5', 1.0 -> '1', 1.25 -> '1.25'.
    """
    if t == int(t):
        return str(int(t))
    s = f"{t:.10g}"
    return s.rstrip("0").rstrip(".")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument("--scripts", default="conformance/scripts")
    parser.add_argument("--assets", default="conformance/assets")
    parser.add_argument("--goldens", default="conformance/goldens")
    parser.add_argument("--schema", default="spec/bony-input-script.schema.json")
    args = parser.parse_args()

    bony_bin = resolve_bony_bin(args.bony_bin)

    schema_path = args.schema
    if not os.path.isfile(schema_path):
        print(f"error: schema not found: {schema_path}", file=sys.stderr)
        sys.exit(2)

    schema = load_json_without_duplicate_keys(schema_path)

    script_files = require_glob(
        os.path.join(args.scripts, "*.json"),
        f"input scripts in {args.scripts}",
    )

    tally = GateTally()

    with tempfile.TemporaryDirectory() as tmpdir:
        for script_path in script_files:
            script_name = os.path.basename(script_path)
            try:
                script = load_json_without_duplicate_keys(script_path)
            except ValueError as exc:
                print(f"FAIL {script_name}: JSON validation: {exc}")
                tally.failed += 1
                continue

            # Validate schema
            try:
                jsonschema.validate(instance=script, schema=schema)
            except jsonschema.ValidationError as exc:
                print(f"FAIL {script_name}: schema validation: {exc.message}")
                tally.failed += 1
                continue

            asset_stem = os.path.splitext(script["asset"])[0]
            asset_ext = os.path.splitext(script["asset"])[1]
            script_stem = os.path.splitext(script_name)[0]
            asset_path = os.path.join(args.assets, script["asset"])
            if not os.path.isfile(asset_path):
                print(f"FAIL {script_name}: asset not found: {asset_path}")
                tally.failed += 1
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
                        tally.failed += 1
                        script_valid = False
                        continue
                    if sample_name in seen_names:
                        print(f"FAIL {script_name}[{i}]: duplicate sample name: {sample_name}")
                        tally.failed += 1
                        script_valid = False
                        continue
                    seen_names.add(sample_name)
                    t = sample["t"]
                    if i > 0 and t < previous_t:
                        print(f"FAIL {script_name}[{i}]: sample times must be non-decreasing")
                        tally.failed += 1
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
                        print(
                            f"FAIL {script_name}[.bnb][{sample_name}]: "
                            f"asset not found: {bnb_path}"
                        )
                        tally.failed += 1
                    else:
                        replay_assets.append((".bnb", bnb_path))
                    for replay_ext, replay_asset_path in replay_assets:
                        actual_path = os.path.join(
                            tmpdir,
                            f"{script_stem}_{sample_name}_{replay_ext.lstrip('.')}_actual.json",
                        )
                        label = f"{script_name}[{replay_ext}][{sample_name}] t={t}"
                        outcome = run_golden_gen_check(
                            bony_bin,
                            replay_asset_path,
                            golden_path,
                            actual_path,
                            label,
                            t=t,
                            state_machine=state_machine,
                            input_script=script_path,
                            sample_selector=sample_name,
                        )
                        tally.record(outcome)
                    continue
                else:
                    if inputs:
                        print(f"FAIL {script_name}[{i}]: inputs require stateMachine")
                        tally.failed += 1
                        continue
                    t_suffix = _format_t(t)
                    golden_path = os.path.join(args.goldens, f"{asset_stem}_t{t_suffix}.json")
                    if script.get("children"):
                        sample_selector = sample.get("name") or str(i)
                        replay_assets = [(asset_ext or ".bony", asset_path)]
                        bnb_path = os.path.join(args.assets, "bnb", f"{asset_stem}.bnb")
                        if not os.path.isfile(bnb_path):
                            print(
                                f"FAIL {script_name}[.bnb][{sample_selector}]: "
                                f"asset not found: {bnb_path}"
                            )
                            tally.failed += 1
                        else:
                            replay_assets.append((".bnb", bnb_path))
                        for replay_ext, replay_asset_path in replay_assets:
                            actual_path = os.path.join(
                                tmpdir,
                                f"{asset_stem}_sample{i}_{replay_ext.lstrip('.')}_actual.json",
                            )
                            label = f"{script_name}[{replay_ext}][{sample_selector}] t={t}"
                            outcome = run_golden_gen_check(
                                bony_bin,
                                replay_asset_path,
                                golden_path,
                                actual_path,
                                label,
                                t=t,
                                input_script=script_path,
                                sample_selector=sample_selector,
                            )
                            tally.record(outcome)
                        continue
                    actual_path = os.path.join(tmpdir, f"{asset_stem}_sample{i}_actual.json")
                    label = f"{script_name}[{i}] t={t}"
                    outcome = run_golden_gen_check(
                        bony_bin, asset_path, golden_path, actual_path, label, t=t
                    )
                tally.record(outcome)

    print(f"\n{tally.summary_line()}")

    tally.assert_not_vacuous("samples")
    sys.exit(tally.exit_code())


if __name__ == "__main__":
    main()
