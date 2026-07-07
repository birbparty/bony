# Task Breakdown

These are Beads-sized tasks for the implementing agent. Each task should become
or map to a bead under `bony-dqsn` if the implementer creates a task graph.

## 1. Analyze Gate Parity

Priority: P0  
Label: `analysis`

Reserve:

- `Makefile`
- `.github/workflows/ci.yml`
- `scripts/ci/*.py`
- `runtime-dart/dart_test.yaml`

Work:

- Confirm the exact command set in `Makefile`, `.github/workflows/ci.yml`, and
  `scripts/ci/suite_run.py`.
- Decide whether to add a Nim-only Make target so the full preflight can run Nim
  before conformance and Dart after conformance, as requested by the prompt.
- Confirm how to build the CLI locally with a deterministic `bddy` include path:
  `~/git/bddy/src` from repo root when available, or `../../bddy/src` relative
  to `runtime-nim` for the normal sibling checkout layout.
- Record that CI should stay expanded unless the implementation preserves CI's
  setup/check steps: `flutter pub get`, `nimble check`, Nim source vet, and
  pinned `bddy` checkout.

Acceptance:

- A short implementation note exists in the bead notes or commit message naming
  the chosen orchestration strategy.
- No code behavior changed yet.

## 2. Add Strict Preflight Orchestrator

Priority: P0  
Label: `impl`

Depends on: Task 1

Reserve:

- `scripts/ci/preflight.py`
- `scripts/ci/_common.py` if shared helpers are needed

Work:

- Add `scripts/ci/preflight.py`.
- Run child commands with non-interactive subprocess calls, preserving output.
- Fail fast or continue-to-summary is implementer choice, but failures must be
  clear and final exit code must be nonzero.
- Support `--bony-bin` and default CLI build behavior.
- Add strict default dependency-skip policy and optional relaxed local flags.
- Invoke `license_provenance_check.py` by default.

Acceptance:

- Running `python3 scripts/ci/preflight.py --help` documents all flags.
- Missing dependency behavior is explicit and does not silently pass in default
  mode. Expected per-asset skips remain visible but do not fail the gate when
  coverage is non-vacuous.
- Child command failures propagate as preflight failures.

## 3. Harden Conformance Suite Skip Semantics

Priority: P1  
Label: `impl`

Depends on: Task 2

Reserve:

- `scripts/ci/suite_run.py`
- `scripts/ci/_common.py`
- individual conformance runners only if needed

Work:

- Either add strict flags to `suite_run.py` or keep it unchanged and enforce
  strictness in `preflight.py`. Prefer adding a strict mode to `suite_run.py`
  because the source prompt names `suite_run.py` as the conformance path.
- Ensure image and input-script dependency skips cannot make the default full
  preflight green.
- Keep expected per-asset skips, especially image assets without committed PNGs,
  visible but non-fatal when at least one image case actually ran.
- Preserve local development convenience for explicit skip flags.
- Avoid weakening the existing runner-level non-vacuity checks.

Acceptance:

- Default full preflight fails when Pillow/jsonschema-backed gates cannot run.
- Relaxed local mode visibly reports skipped gates.
- Existing direct runner commands still work as documented unless docs are
  updated at the same time.

## 4. Add Dart Non-Vacuity Guard

Priority: P1  
Label: `testing`

Depends on: Task 2

Reserve:

- `scripts/ci/preflight.py`
- `runtime-dart/dart_test.yaml` only if documentation comments need adjustment

Work:

- Ensure the full preflight verifies Flutter tests actually executed.
- Run `cd runtime-dart && flutter test --machine` explicitly and parse the JSON
  event stream to count started tests. Do not rely on `make test` output for this
  non-vacuity proof.
- Keep `flutter test`, not `dart test`.
- Run `flutter analyze` as part of full preflight unless explicitly skipped in a
  relaxed local mode.

Acceptance:

- A zero-test Dart run cannot satisfy the full preflight.
- Flutter test failure or analyze failure makes the full preflight fail.

## 5. Add Makefile Targets

Priority: P1  
Label: `impl`

Depends on: Task 2

Reserve:

- `Makefile`

Work:

- Add `.PHONY: preflight`.
- Add a Nim-only target, such as `nim-test`, by extracting the existing raw Nim
  check/test commands from `test` while leaving `dart-test` separate.
- Wire `preflight` to `python3 scripts/ci/preflight.py`.
- Preserve `test` and `dart-test` behavior.

Acceptance:

- `make preflight` is the documented full v1 gate.
- `make test` remains the faster existing gate.
- The full preflight can run Nim checks before conformance and the explicit Dart
  machine-readable gate after conformance.

## 6. Documentation Pass

Priority: P2  
Label: `docs`

Depends on: Tasks 2, 3, 5

Reserve:

- `README.md`
- `docs/README.md`
- `conformance/README.md`

Work:

- Document `make preflight` and `python3 scripts/ci/preflight.py`.
- Document `make test` as the fast gate.
- In `conformance/README.md`, keep `suite_run.py` framed as conformance-only
  and point to the repo-level full preflight for v1 completion.
- List required local dependencies and any relaxed local skip flags.

Acceptance:

- A new agent can find the full preflight command from the root README.
- Conformance docs no longer imply `suite_run.py` is the whole repo gate.

## 7. CI Parity Decision

Priority: P2  
Label: `cleanup`

Depends on: Tasks 2, 3, 4, 5

Reserve:

- `.github/workflows/ci.yml`

Work:

- Decide whether to replace duplicated CI steps with `make preflight` or leave CI
  expanded for better failure attribution.
- Default recommendation: leave CI expanded in this slice. The local preflight is
  a developer completion gate; CI already has explicit setup and attribution.
- If replacing anyway, preserve dependency setup, `flutter pub get`,
  `nimble check`, Nim source vet, Flutter setup, Nim setup, and the pinned
  `bddy` checkout.
- If not replacing, add a short comment or documentation note explaining that CI
  and local preflight intentionally cover the same gate through different
  command layouts.

Acceptance:

- No loss of CI coverage.
- CI remains Linux-friendly and non-interactive.

## 8. End-to-End Verification

Priority: P0  
Label: `testing`

Depends on: Tasks 3, 4, 5, 6, 7

Reserve:

- No exclusive file reservation unless fixes are discovered.

Work:

- Run:
  - `python3 scripts/ci/preflight.py`
  - `make preflight`
  - `make test`
- If local dependencies are unavailable, run the documented relaxed command and
  record exactly which dependency was unavailable.
- Confirm `git diff --check`.

Acceptance:

- Strict preflight passes, or the final handoff records the exact unavailable
  local dependency and the relaxed command used.
- No vacuous pass is accepted for numeric, image, input-script, round-trip, or
  Dart tests.
- Expected per-asset skips are reviewed separately from dependency-gated skips.
