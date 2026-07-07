# Design

## Entry Point

Add a strict repo-level preflight entrypoint:

```bash
python3 scripts/ci/preflight.py
```

Also expose it through:

```bash
make preflight
```

Keep `make test` as the fast per-iteration gate unless the implementer confirms
that changing it will not make ordinary edits too expensive. The new
`preflight` target may depend on `test`, but `test` should not silently expand
into the full v1 gate.

## Command Contract

Recommended options:

- `--bony-bin PATH`: reuse an existing CLI binary.
- `--build-bony-bin PATH`: build the CLI binary to this path before conformance
  checks. Default: a temp path under `/tmp` or a temporary directory.
- `--skip-image`: local-only escape hatch for missing Pillow. Must print `SKIP`
  and must not be used by default.
- `--skip-asset-schema`: local-only escape hatch for
  `schema_validate_assets.py` when jsonschema is unavailable. Must print `SKIP`
  and must not be used by default.
- `--skip-input-script`: local-only escape hatch for `input_script_run.py` when
  jsonschema is unavailable. Must print `SKIP` and must not be used by default.
- `--skip-dart-analyze`: optional local-only escape hatch if Flutter analyze is
  too expensive or unavailable. Do not skip Flutter tests by default.
- `--fail-on-dependency-skip`: default behavior for the full v1 gate.
  Dependency-gated skipped gates are failures unless the skip was explicitly
  requested and the command is running in local relaxed mode.
- `--relaxed-local`: optional convenience mode that permits explicit dependency
  skips while still printing a clear summary and a nonzero count of skipped
  gates.

Avoid environment-variable-only behavior. Flags are easier for future agents to
read in logs.

## Execution Order

The default strict preflight should run:

1. `python3 scripts/ci/license_provenance_check.py`
2. `python3 codegen/generate.py --check`
3. `python3 -m unittest discover -s codegen -p 'test_*.py'`
4. `python3 scripts/ci/schema_validate_assets.py`
5. Nim compile and runtime tests without Dart:
   - Preferred: add a `make nim-test` or similarly named target containing the
     existing generated-code-independent Nim checks and raw `nim c -r` test
     commands, then call it here.
   - Acceptable fallback: keep calling `make test` only if the preflight also
     runs the explicit Dart machine-readable gate in step 8 and documents that
     Dart is duplicated.
6. Build the CLI binary if `--bony-bin` was not supplied:
   - From repo root, first try `~/git/bddy/src` when it exists, matching CI.
   - Otherwise resolve `../../bddy/src` relative to `runtime-nim`, matching
     `runtime-nim/nim.cfg` for the normal sibling checkout layout.
   - If neither exists, fail with a message naming both expected paths and the
     pinned CI checkout behavior.
7. Conformance suite through `scripts/ci/suite_run.py` in a strict mode. The
   strict suite may internally call the individual runners, but the public
   preflight should exercise the master suite path so it cannot remain a weaker
   "full suite" command.
8. Dart runtime tests through `cd runtime-dart && flutter test --machine`, parsed
   to prove at least one test started.
9. `cd runtime-dart && flutter analyze`

## Skip Policy

Strict default:

- Missing Pillow is a failed setup error, not a skipped success.
- Missing jsonschema is a failed setup error, not a skipped success.
- Explicit skip flags are visible in output and cause a final failure unless
  `--relaxed-local` is also supplied.
- Expected per-asset skips from child runners, such as assets with no committed
  image PNG, remain visible but are not failures if the gate still checked at
  least one case and the skip was not caused by a missing dependency.

Local relaxed mode:

- Allows explicit dependency-gated skips for development machines.
- Still fails on vacuous coverage unrelated to the skipped dependency.
- Summary must list each skipped gate and the flag that caused it.

## Non-Vacuity

Do not rely only on subprocess exit code. The full preflight should require:

- Numeric conformance reports at least one pass/fail and zero unexpected skips.
- Image conformance reports at least one checked PNG by default. Per-asset
  missing PNG skips are acceptable only when at least one image case passed and
  Pillow was available.
- Input-script conformance reports at least one checked sample. Missing
  committed goldens must not be accepted as a dependency skip.
- Round-trip reports both directions ran at least one check.
- Flutter test output indicates tests actually ran. A robust implementation can
  use `flutter test --machine` and count events with successful test starts.

The individual conformance runners already enforce some non-vacuity. The full
preflight should preserve those checks and add stricter skip handling at the
orchestration layer.

## Output Shape

Use a consistent per-gate summary:

```text
PASS codegen-freshness
PASS codegen-tests
PASS nim-and-fast-runtime-tests
PASS asset-schema
PASS conformance:numeric
PASS conformance:image
PASS conformance:input-script
PASS conformance:round-trip
PASS dart:flutter-test
PASS dart:analyze

Full preflight PASS: 10 passed, expected per-case skips visible, 0 failed
```

On failure, preserve child process output and exit nonzero.

## Documentation

Update:

- `README.md`: quick command list for `make test` and `make preflight`.
- `docs/README.md`: link the v1 preflight docs.
- `conformance/README.md`: distinguish conformance-only `suite_run.py` from the
  repo-level full v1 preflight.

Document prerequisites:

- Nim toolchain and Nim dependencies.
- Flutter.
- Python packages `Pillow>=10.0.0,<12` and `jsonschema>=4.18.0,<5`.
- Local `bddy` sibling or equivalent path expected by Nim commands.
