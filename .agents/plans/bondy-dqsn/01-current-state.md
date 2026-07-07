# Current State

## Existing Gates

`Makefile`

- `test` runs:
  - `python3 codegen/generate.py --check`
  - Python codegen unit tests
  - `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim`
  - many raw `nim c -r` runtime tests
  - `$(MAKE) dart-test`
- `dart-test` runs `cd runtime-dart && flutter test`.
- The Makefile intentionally avoids `nimble test` because earlier history found
  that Nimble swallowed failing task exit codes.

`.github/workflows/ci.yml`

- Runs `python3 scripts/ci/license_provenance_check.py`.
- Installs Nim, Flutter, system libraries, Nim dependencies, and a pinned local
  `bddy` test dependency.
- Runs Nim checks/tests, codegen checks, asset schema validation, Flutter tests,
  Flutter analyze, builds `/tmp/bony_bin`, then runs the conformance scripts.
- CI has more gates than `make test`; local preflight currently has no single
  strict equivalent.

`scripts/ci/suite_run.py`

- Runs numeric, image, input-script, and round-trip conformance in order.
- Accepts `--skip-image`.
- Treats missing Pillow/jsonschema import errors as `SKIP` for dependency-gated
  scripts, then exits success if no gate failed.
- Also inherits expected per-case skips from child runners. For example,
  `image_diff_check.py` prints `SKIP <rig>: no committed golden` for assets that
  intentionally have no PNG golden today. A full preflight should not treat
  those expected per-asset skips as dependency skips.
- Does not run codegen, Nim tests, Dart tests, schema validation, Flutter
  analyze, or license/provenance.

Individual conformance runners

- `conformance_run.py` requires at least one checked golden through
  `GateTally.assert_not_vacuous("goldens")`.
- `image_diff_check.py` requires at least one checked image golden and rejects
  all-transparent committed goldens.
- `input_script_run.py` requires at least one checked sample and validates each
  input script against `spec/bony-input-script.schema.json`.
- `round_trip_run.py` separately fails if either json-to-bnb or bnb-to-json-to-bnb
  direction ran zero checks.
- `schema_validate_assets.py` validates `.bony` assets against
  `spec/bony.schema.json`; it does not take `--bony-bin`.

`runtime-dart`

- Uses Flutter SDK dependencies.
- `runtime-dart/dart_test.yaml` explicitly says to use `flutter test` because
  plain `dart test` fails dependency resolution for Flutter-backed surfaces.
- `make test` already runs Flutter tests through `dart-test`, so using
  `make test` inside the full preflight conflates Dart with the earlier
  Nim/fast-runtime phase and makes Dart non-vacuity harder to prove.

## Affected Files

Likely implementation surfaces:

- `scripts/ci/preflight.py` or equivalent new full-gate script.
- `scripts/ci/suite_run.py` for strict skip policy, if the new script delegates
  to it.
- `scripts/ci/_common.py` if common tally/summary behavior needs reusable
  non-vacuous helpers.
- `Makefile` for a discoverable `preflight` target while preserving `test` and
  `dart-test`.
- `.github/workflows/ci.yml` only if the new preflight should replace duplicated
  CI command lists after parity is proven. This can be deferred; do not churn CI
  without a clear reason.
- `README.md`, `docs/README.md`, and `conformance/README.md` for documentation.
- `scripts/ci/license_provenance_check.py` is already locally runnable and should
  be invoked by the full preflight, not modified unless a concrete issue appears.

## Main Gaps

- There is no single documented local command for the full v1 preflight.
- `suite_run.py` can exit success with dependency-gated skips, which is useful
  locally but too weak for a default v1 completion gate.
- `suite_run.py` does not cover codegen, Nim, Dart, schema validation, Flutter
  analyze, or license/provenance.
- Documentation still points users at conformance-only suite commands rather
  than a repo-level v1 completion gate.
- The full gate needs explicit coverage assertions for Dart test execution. A
  `flutter test` command that runs zero tests would be vacuous in the same way a
  conformance script with zero checked cases is vacuous.
- CI currently includes setup/checks not present in `make test`: `flutter pub
  get`, `nimble check`, Nim source vet for `src/bony.nim`,
  `tests/test_smoke.nim`, and `../cli/bony_cli.nim`, plus pinned `bddy` checkout
  setup. Do not replace CI with the new preflight until those are preserved or
  intentionally justified.
