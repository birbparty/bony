# /big-change prompt - conformance (nested rig composition gate)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 4**. Can run independently; the final preflight
> prompt depends on this gate existing.
> **Candidate category:** frontier.

---

/big-change Add a nested rig composition conformance gate that exercises the existing host-resolved nested draw-batch API through the CLI and shared goldens.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Nested rig attachment format/load and host-resolved setup-pose runtime
composition already exist in both runtimes:
`docs/nested-rig-attachment-contract.md`,
`docs/nested-rig-runtime-composition-contract.md`,
`runtime-nim/src/bony/transform.nim`, and
`runtime-dart/lib/src/transform.dart`. The remaining gap is that conformance
goldens still load a single asset and call the legacy draw-batch path, so nested
composition is covered only by unit tests.

Extend the conformance-facing harness in the smallest project-owned way:

- Add a child-skeleton resolver surface to `spec/bony-input-script.schema.json`
  and `cli/bony_cli.nim` for setup-pose scripts only.
- Load child `.bony` and `.bnb` assets from explicit script entries, not from
  automatic filesystem discovery.
- When a script supplies nested children, have `numericGoldenJson` or an
  adjacent helper build batches with `buildNestedDrawBatches`; keep legacy
  scripts byte-identical.
- Add `m23_nested_rig` conformance assets/scripts/goldens that prove child
  draw-order insertion, parent affine composition, active child skin selection,
  and host clipping.
- Add matching Dart conformance coverage that uses `buildNestedDrawBatches`
  against the same golden.

Do not add nested animation playback, state-machine playback, physics state
advancement inside children, automatic asset loading, or importer mapping.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Nested format contract: docs/nested-rig-attachment-contract.md
- Nested runtime contract: docs/nested-rig-runtime-composition-contract.md
- Input script schema: spec/bony-input-script.schema.json
- CLI script parser and golden output: cli/bony_cli.nim
- Nim nested API: runtime-nim/src/bony/transform.nim
- Dart nested API: runtime-dart/lib/src/transform.dart
- Current nested tests: runtime-nim/tests/test_smoke.nim,
  runtime-dart/test/nested_rig_attachment_test.dart
- Conformance docs and fixtures: conformance/README.md, conformance/assets/,
  conformance/scripts/, conformance/goldens/
- CI runners: scripts/ci/conformance_run.py, scripts/ci/input_script_run.py
- Beads: bony-ohs0

**Success Criteria**
- `spec/bony-input-script.schema.json` documents an explicit child asset map for
  setup-pose nested composition scripts; existing scripts remain valid.
- `cli/bony_cli.nim` rejects child-script misuse with deterministic
  `schemaViolation` or `unknownRequiredReference` errors and never searches for
  nested assets implicitly.
- New fixture files exist under `conformance/assets/`,
  `conformance/scripts/`, and `conformance/goldens/` for `m23_nested_rig`.
- The golden is non-vacuous: at least one child batch vertex changes by more
  than `1e-4` under the host affine, a child skin changes visible geometry, and
  a host clip cuts composed child geometry.
- `conformance/README.md` documents the M23 nested composition row and explains
  why the legacy draw-batch API still emits no nested batches.
- Dart tests compare the M23 nested golden within `1e-4` from the same source
  data.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`
  - `cd runtime-dart && dart test`

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not add nested animation playback, nested state-machine playback, nested
  physics state advancement, nested asset manifests, or automatic child asset
  lookup.
- Do not change serialized `nestedRigAttachment` keys or fields.
- Keep the slice focused on conformance harnessing and golden coverage.
