# Verification and Handoff

## Required Verification

The implementing agent should run the strict gate:

```bash
python3 scripts/ci/preflight.py
make preflight
make test
git diff --check
```

If the strict gate cannot run locally because of missing external dependencies,
the agent may run a documented relaxed command, but the handoff must include:

- the exact command;
- the exact skipped gates;
- why the dependency was unavailable;
- confirmation that skipped gates are not skipped by default.

## Expected Full Preflight Coverage

The strict full preflight is not complete unless it covers:

- `python3 scripts/ci/license_provenance_check.py`
- `python3 codegen/generate.py --check`
- `python3 -m unittest discover -s codegen -p 'test_*.py'`
- `python3 scripts/ci/schema_validate_assets.py`
- raw Nim compile/test coverage equivalent to current `make test`
- CLI build for conformance runners
- `scripts/ci/suite_run.py` in strict mode, covering numeric conformance, image
  conformance, input-script conformance, and round-trip conformance
- explicit `flutter test --machine` with at least one started test
- Flutter analyze

## Non-Vacuity Checklist

- Numeric conformance checked at least one golden.
- Image conformance checked at least one PNG and did not pass due only to
  dependency skips. Expected per-asset "no committed golden" skips are acceptable
  when coverage is non-vacuous.
- Input-script conformance checked at least one sample and did not mask missing
  goldens as acceptable dependency skips.
- Round-trip conformance checked both json-to-bnb and bnb-to-json-to-bnb
  directions.
- Dart test execution checked at least one test.
- Any dependency-gated skip in strict mode fails the full preflight.

## Beads Closeout

When implementation is complete:

1. Update or close `bony-dqsn` with the final command output summary.
2. File follow-up beads for anything intentionally deferred, such as CI
   deduplication if local preflight lands first.
3. Run the repository session close workflow from `bd prime`, including
   `bd dolt push`, `git push`, and a final clean status check.

## Risk Notes

- Plain `dart test` is not the right Dart command in the current repo. Use
  Flutter.
- `schema_validate_assets.py` has no `--bony-bin` argument.
- `suite_run.py --skip-image` exists today; do not let that local convenience
  become the default v1 completion behavior.
- `suite_run.py` also prints expected per-asset skips for missing committed
  image goldens. Do not confuse those with missing-dependency skips.
- CI currently installs dependencies before running gates. A local preflight
  should fail clearly when prerequisites are absent rather than trying to
  install packages silently.
