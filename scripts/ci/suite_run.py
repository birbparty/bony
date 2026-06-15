#!/usr/bin/env python3
"""Master conformance suite runner.

Runs all bony CI gates in sequence and reports a single pass/fail summary.
This is a local development convenience tool — in CI each gate runs separately
so failures are attributed precisely.  Use this script to run the complete
cross-runtime conformance contract before pushing.

Gates (in order):
  1. numeric-golden    conformance_run.py        (no extra deps)
  2. image-golden      image_diff_check.py       (requires Pillow)
  3. input-script      input_script_run.py       (requires jsonschema)
  4. round-trip        round_trip_run.py         (no extra deps)

Usage:
  python3 scripts/ci/suite_run.py --bony-bin /path/to/bony

Exit 0 if all runnable gates pass; 1 if any gate fails; 2 on setup error.
"""

import argparse
import os
import subprocess
import sys

# (gate_name, script_path, extra_deps_hint)
GATES = [
    ("numeric-golden", "scripts/ci/conformance_run.py", None),
    ("image-golden",   "scripts/ci/image_diff_check.py", "pip install 'Pillow>=10.0.0,<12'"),
    ("input-script",   "scripts/ci/input_script_run.py", "pip install 'jsonschema>=4.18.0,<5'"),
    ("round-trip",     "scripts/ci/round_trip_run.py", None),
]

# Exit code 2 is "setup error" (missing binary, no assets, etc.).
# image_diff_check.py and input_script_run.py also use 2 for missing deps.
_SETUP_ERROR = 2


def run_gate(gate_name, script_path, bony_bin):
    """Run one gate script and return (exit_code, stdout+stderr text)."""
    result = subprocess.run(
        [sys.executable, script_path, "--bony-bin", bony_bin],
        capture_output=True,
        text=True,
    )
    combined = result.stdout
    if result.stderr:
        combined += result.stderr
    return result.returncode, combined


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument(
        "--skip-image",
        action="store_true",
        help="Skip the image-golden gate (useful when Pillow is not installed)",
    )
    args = parser.parse_args()

    bony_bin = os.path.abspath(args.bony_bin)
    if not os.path.isfile(bony_bin):
        print(f"error: bony binary not found: {bony_bin}", file=sys.stderr)
        sys.exit(_SETUP_ERROR)

    results = []  # (gate_name, status, output)

    for gate_name, script_path, deps_hint in GATES:
        if gate_name == "image-golden" and args.skip_image:
            results.append((gate_name, "SKIP", "(--skip-image)"))
            continue

        if not os.path.isfile(script_path):
            results.append((gate_name, "SKIP", f"script not found: {script_path}"))
            continue

        print(f"\n{'='*60}")
        print(f"  Gate: {gate_name}")
        print(f"{'='*60}")

        rc, output = run_gate(gate_name, script_path, bony_bin)
        if output:
            print(output.rstrip())

        if rc == 0:
            status = "PASS"
        elif rc == _SETUP_ERROR and deps_hint:
            status = "SKIP"
            print(f"  (skipped — missing dependency; install with: {deps_hint})")
        else:
            status = "FAIL"

        results.append((gate_name, status, ""))

    # Summary
    print(f"\n{'='*60}")
    print("  Suite summary")
    print(f"{'='*60}")
    any_fail = False
    for gate_name, status, note in results:
        suffix = f"  {note}" if note else ""
        print(f"  {status:6}  {gate_name}{suffix}")
        if status == "FAIL":
            any_fail = True

    print()
    if any_fail:
        print("FAIL — one or more gates failed")
        sys.exit(1)
    else:
        passed = sum(1 for _, s, _ in results if s == "PASS")
        skipped = sum(1 for _, s, _ in results if s == "SKIP")
        print(f"PASS — {passed} gate(s) passed, {skipped} skipped")


if __name__ == "__main__":
    main()
