#!/usr/bin/env python3
"""Image golden gate for the Nim software rasterizer.

Renders each conformance rig that has a committed PNG golden via
``bony play`` and compares the output against the golden pixel-by-pixel.
Metric: max absolute per-channel delta (RGBA, 0-255 range) must be ≤ MAX_DELTA.

These goldens are Nim-only regression artifacts — they test the reference
rasterizer, not any Dart rendering path.

Usage:
  python3 scripts/ci/image_diff_check.py --bony-bin /path/to/bony
  python3 scripts/ci/image_diff_check.py --bony-bin /path/to/bony \\
    --assets conformance/assets --goldens conformance/goldens

Exit 0 if all cases pass; non-zero otherwise.
Requires: pip install 'Pillow>=10.0.0,<12'
"""

import argparse
import glob
import os
import subprocess
import sys
import tempfile

try:
    from PIL import Image, ImageChops
except ImportError:
    print(
        "error: Pillow not installed — run: pip install 'Pillow>=10.0.0,<12'",
        file=sys.stderr,
    )
    sys.exit(2)

# Deterministic rasterizer against its own golden: allow ≤ 1 per channel
# to absorb any platform-level float rounding (sub-pixel edge sampling).
MAX_DELTA = 1


def _find_worst_pixel(actual, golden, w):
    """Slow path: locate the worst pixel when max_delta > MAX_DELTA."""
    act_bytes = actual.tobytes()
    gld_bytes = golden.tobytes()
    max_delta = 0
    worst = (0, 0, 0, 0)  # (x, y, channel, delta)
    for i in range(len(act_bytes)):
        d = abs(int(act_bytes[i]) - int(gld_bytes[i]))
        if d > max_delta:
            max_delta = d
            px = i // 4
            worst = (px % w, px // w, i % 4, d)
    return max_delta, worst


def run_image_check(bony_bin, asset_path, golden_path, actual_path, label, width=256, height=256):
    """Render asset_path and compare against golden_path.

    Returns "pass", "fail", or "skip" (if no committed golden).
    """
    if not os.path.isfile(golden_path):
        print(f"SKIP {label}: no committed golden at {golden_path}")
        return "skip"

    try:
        result = subprocess.run(
            [
                bony_bin, "play", asset_path,
                "--out", actual_path,
                "--width", str(width),
                "--height", str(height),
            ],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            print(f"FAIL {label}: bony play exited {result.returncode}")
            if result.stderr:
                print(result.stderr.rstrip())
            return "fail"

        actual = Image.open(actual_path).convert("RGBA")
        golden = Image.open(golden_path).convert("RGBA")

        if actual.size != golden.size:
            print(
                f"FAIL {label}: size mismatch actual={actual.size} golden={golden.size}"
            )
            return "fail"

        # Fast path: ImageChops.difference runs in C; getextrema() returns
        # (min, max) per channel — we only need the per-channel maxima.
        diff = ImageChops.difference(actual, golden)
        max_delta = max(ch_max for _, ch_max in diff.getextrema())

    except Exception as exc:
        print(f"FAIL {label}: {exc}")
        return "fail"

    if max_delta > MAX_DELTA:
        _, worst = _find_worst_pixel(actual, golden, actual.width)
        ch_name = ["R", "G", "B", "A"][worst[2]]
        print(
            f"FAIL {label}: max per-channel delta {max_delta} > {MAX_DELTA} "
            f"(worst at pixel ({worst[0]},{worst[1]}) channel {ch_name})"
        )
        return "fail"

    print(f"PASS {label}: max delta {max_delta} <= {MAX_DELTA}")
    return "pass"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bony-bin", required=True, help="Path to bony CLI binary")
    parser.add_argument("--assets", default="conformance/assets")
    parser.add_argument("--goldens", default="conformance/goldens")
    parser.add_argument("--width", type=int, default=256)
    parser.add_argument("--height", type=int, default=256)
    args = parser.parse_args()

    bony_bin = os.path.abspath(args.bony_bin)
    if not os.path.isfile(bony_bin):
        print(f"error: bony binary not found: {bony_bin}", file=sys.stderr)
        sys.exit(2)

    asset_files = sorted(glob.glob(os.path.join(args.assets, "*.bony")))
    if not asset_files:
        print(f"error: no .bony assets found in {args.assets}", file=sys.stderr)
        sys.exit(2)

    passed = 0
    failed = 0
    skipped = 0

    with tempfile.TemporaryDirectory() as tmpdir:
        for asset_path in asset_files:
            stem = os.path.splitext(os.path.basename(asset_path))[0]
            golden_path = os.path.join(args.goldens, f"{stem}_play.png")
            actual_path = os.path.join(tmpdir, f"{stem}_actual.png")
            outcome = run_image_check(
                bony_bin, asset_path, golden_path, actual_path, stem,
                width=args.width, height=args.height,
            )
            if outcome == "pass":
                passed += 1
            elif outcome == "fail":
                failed += 1
            else:
                skipped += 1

    print(f"\n{passed} passed, {failed} failed, {skipped} skipped")

    if passed == 0 and failed == 0:
        print("error: no image goldens were checked — gate is vacuously green", file=sys.stderr)
        sys.exit(2)

    if failed:
        sys.exit(1)


if __name__ == "__main__":
    main()
