# bony-dqsn Plan: M10 Full Conformance Preflight Gate

## Source

This plan implements bead `bony-dqsn` using the scope in
`.agents/big-change-prompts/51-ci-v1-full-conformance-preflight.md`.

## Goal

Promote repo verification into one documented v1 preflight path that cannot pass
vacuously. The full gate must run, in deterministic order:

1. License/provenance check, if locally runnable.
2. Generated-code freshness and Python codegen tests.
3. Nim compile and raw Nim runtime tests from `Makefile`.
4. Asset/schema checks and conformance runners:
   `scripts/ci/suite_run.py` in a strict mode that covers
   `conformance_run.py`, `image_diff_check.py`, `input_script_run.py`, and
   `round_trip_run.py`.
5. Dart runtime checks through an explicit Flutter test gate, not plain
   `dart test`, because
   `runtime-dart/dart_test.yaml` documents that Flutter SDK dependencies require
   `flutter test`.

## Deliverables

- One strict full preflight entrypoint, preferably `scripts/ci/preflight.py`
  plus a `Makefile` target such as `preflight`.
- Existing fast developer gates remain available. `make test` should not become
  the full preflight unless the docs say so explicitly.
- README/docs updates that name the full v1 gate and distinguish it from fast
  local gates.
- Non-vacuity checks that fail when numeric goldens, image goldens,
  input-script samples, round-trip directions, or Dart tests are not actually
  exercised. Expected per-asset skips, such as rigs without committed image
  goldens, remain visible but are not failures by themselves.

## Plan Files

- `01-current-state.md` records the repo surfaces and gaps found before
  implementation.
- `02-design.md` defines the preflight behavior and CLI contract.
- `03-task-breakdown.md` gives Beads-sized implementation tasks and dependencies.
- `04-verification.md` lists exact acceptance gates and handoff expectations.

## Constraints

- Preserve clean-room posture. Do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Do not add new runtime or format features.
- Keep the gate Linux-friendly and non-interactive.
- Optional dependency behavior must be explicit. The default v1 full preflight
  should fail, not silently skip, if Pillow or jsonschema-backed gates cannot
  run.
