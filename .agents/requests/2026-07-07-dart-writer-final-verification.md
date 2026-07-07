# Dart Writer Final Verification

Verified on 2026-07-07 against bony commit
`77cd0fec69e117926a0d28f211e3c5a21479103a`.

## Commands

- `python3 codegen/generate.py --check`
  - Passed.
- `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - Passed: 33 tests.
- `cd runtime-dart && flutter test`
  - Passed: 694 tests.
- `make test`
  - Passed.
  - Includes `python3 scripts/ci/check_dart_writer_canonical_json.py`.
  - Canonical writer fixture check passed: 54 canonical JSON fixtures.

