#!/usr/bin/env python3
"""JSON Schema validation gate for conformance assets.

Validates every .bony file in conformance/assets/ against the generated
spec/bony.schema.json. Requires: pip install 'jsonschema>=4.18.0,<5'

Usage:
  python3 scripts/ci/schema_validate_assets.py [--schema spec/bony.schema.json] [--assets conformance/assets]

Exit 0 if all assets pass; non-zero otherwise.
"""

import argparse
import glob
import json
import os
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--schema", default="spec/bony.schema.json")
    parser.add_argument("--assets", default="conformance/assets")
    args = parser.parse_args()

    try:
        import jsonschema
    except ImportError:
        print("error: jsonschema not installed. Run: pip install jsonschema", file=sys.stderr)
        sys.exit(2)

    schema_path = os.path.abspath(args.schema)
    if not os.path.isfile(schema_path):
        print(f"error: schema not found: {schema_path}", file=sys.stderr)
        sys.exit(2)

    with open(schema_path) as f:
        schema = json.load(f)

    asset_files = sorted(glob.glob(os.path.join(args.assets, "*.bony")))
    if not asset_files:
        print(f"error: no .bony assets found in {args.assets}", file=sys.stderr)
        sys.exit(2)

    passed = 0
    failed = 0

    for asset_path in asset_files:
        name = os.path.basename(asset_path)
        try:
            with open(asset_path) as f:
                asset = json.load(f)
            jsonschema.validate(instance=asset, schema=schema)
            print(f"PASS {name}")
            passed += 1
        except jsonschema.ValidationError as exc:
            print(f"FAIL {name}: {exc.message}")
            print(f"  path: {list(exc.absolute_path)}")
            failed += 1
        except Exception as exc:
            print(f"FAIL {name}: {exc}")
            failed += 1

    print(f"\n{passed} passed, {failed} failed")

    if failed:
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
