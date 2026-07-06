# /big-change prompt - runtime + conformance (pointer helper listeners)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 3**. Depends on step 1
> (`36-contract-pointer-helper-listeners.md`) and bead `bony-g65e`.
> **Candidate category:** frontier.

---

/big-change Implement Nim pointer listener dispatch over helper geometry and add the M21 conformance gate.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After the pointer listener contract and wire format exist, implement the Nim
reference runtime behavior and conformance assets. This slice must derive from
`docs/pointer-helper-listener-contract.md`, `docs/helper-geometry-attachment-contract.md`,
and public geometry math only.

Build exactly this milestone:

1. Add Nim helper-query APIs for point and bounding-box attachments, using the
   world-transform math already exposed by `runtime-nim/src/bony/transform.nim`
   and the helper geometry contract:
   - world point pose for a `pointAttachment`;
   - world polygon for a `boundingBoxAttachment`;
   - point-in-polygon test with boundary tolerance from
     `docs/float-math-contract.md`;
   - point-target radius test for pointer listeners as defined by
     `docs/pointer-helper-listener-contract.md`.
2. Extend the Nim state-machine runtime in
   `runtime-nim/src/bony/statemachine/core.nim` so pointer listener dispatch can
   mutate bool, number, and trigger inputs before transition evaluation for a
   sample. Preserve existing state-enter/state-exit/transition listener order.
3. Extend the CLI input-script surface in `spec/bony-input-script.schema.json`
   and `cli/bony_cli.nim` with pointer sample input as defined by the contract.
   State-machine script execution must apply direct `inputs`, then pointer
   listener effects, then advance/update the state machine so transitions can
   react in the same sample.
4. Emit pointer listener events in the numeric golden's existing `events`
   channel without conflating them with `animationEvents`. Include enough
   project-owned fields to identify the listener, kind, target slot, target
   helper attachment, input mutation, and sample pointer location.
5. Add an M21 conformance asset, input script, and goldens:
   - `conformance/assets/m21_pointer_listener_rig.bony`
   - `conformance/assets/bnb/m21_pointer_listener_rig.bnb`
   - `conformance/scripts/m21_pointer_listener_story.json`
   - `conformance/goldens/m21_pointer_listener_<sample>.json`
   The rig must exercise at least one bounding-box target and one point target.
   The samples must show enter/down/move/up/exit behavior, a bool or trigger
   input mutation, a state transition caused by a pointer listener, and a
   non-vacuous world transform or state-machine event difference.
6. Update `conformance/README.md` with the M21 row and explanation.
7. Add focused Nim tests in existing test files or new files under
   `runtime-nim/tests/` for helper hit testing, pointer listener validation,
   input-script parsing, event ordering, JSON/BNB parity, and the M21 goldens.
8. Keep Dart changes out of this slice except generated schema files if codegen
   requires them. Dart runtime parity is step 3.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Pointer listener contract: docs/pointer-helper-listener-contract.md
- Helper geometry contract: docs/helper-geometry-attachment-contract.md
- Float math/tolerance: docs/float-math-contract.md
- State-machine validation ownership: docs/animation-state-machine-validation-ownership.md
- Input-script schema: spec/bony-input-script.schema.json
- CLI harness docs: cli/README.md
- Existing state-machine conformance: conformance/assets/m8_rig.bony,
  conformance/scripts/m8_gesture_story.json, conformance/README.md
- Nim seams: runtime-nim/src/bony/statemachine/core.nim,
  runtime-nim/src/bony/transform.nim,
  runtime-nim/src/bony/model.nim,
  runtime-nim/src/bony/jsonio.nim,
  runtime-nim/src/bony/binary/semantic.nim,
  cli/bony_cli.nim,
  runtime-nim/tests/test_smoke.nim
- Beads: parent bony-1umq; child bony-3moo; depends on bony-g65e

**Success Criteria**
- Nim exposes deterministic helper hit testing for point and bounding-box
  helper attachments and uses it for pointer listener dispatch.
- State-machine script execution applies pointer listener input mutations before
  per-sample transition evaluation and preserves existing direct input behavior.
- The numeric golden output includes pointer listener events separately from
  `animationEvents` and preserves existing lifecycle listener output.
- M21 `.bony` and `.bnb` conformance assets produce matching Nim goldens.
- `conformance/README.md` documents the M21 pointer listener behavior and why it
  is non-vacuous.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not change the pointer listener serialized contract from step 1 unless
  the contract, registry, defaults, generated schema, Nim loader, and Dart
  loader are updated together.
- Do not implement Dart runtime dispatch in this slice.
- Do not add visible debug rendering for helper attachments.
- Keep the slice small enough for one meaningful implementation session.
