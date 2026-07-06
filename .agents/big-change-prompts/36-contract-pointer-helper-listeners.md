# /big-change prompt - contract + format (pointer helper listeners)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 3**. Must land before the Nim runtime and
> conformance slice because it owns the serialized contract and loader shape.
> **Candidate category:** frontier.

---

/big-change Define project-owned pointer listener records over point and bounding-box helper attachments.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

The repo has no pre-existing implementation issue for this work. Helper geometry
attachments are already loadable `.bony`/`.bnb` records in
`docs/helper-geometry-attachment-contract.md`, `registry/wire.yml`,
`runtime-nim/src/bony/model.nim`, `runtime-nim/src/bony/jsonio.nim`,
`runtime-nim/src/bony/binary/semantic.nim`, `runtime-dart/lib/src/model.dart`,
and `runtime-dart/lib/src/loader.dart`. That contract explicitly defines future
helper-query math but stops before pointer listener dispatch.

Build the contract/format slice for state-machine pointer listeners:

1. Add a binding contract document, suggested path
   `docs/pointer-helper-listener-contract.md`.
2. Define project-owned state-machine listener kinds for `pointerDown`,
   `pointerUp`, `pointerEnter`, `pointerExit`, and `pointerMove`. Keep existing
   `stateEnter`, `stateExit`, and `transition` listener behavior unchanged.
3. Define JSON listener fields for pointer listeners. Use project-owned names
   that identify:
   - the target slot;
   - the target point or bounding-box helper attachment;
   - the state-machine input to mutate;
   - the bool or number value to set when the target input is bool or number.
   Trigger inputs must fire with no value field. Point targets must have an
   explicit finite non-negative hit radius; bounding-box targets use the polygon
   hit-test from `docs/helper-geometry-attachment-contract.md`.
4. Define loader validation:
   - pointer listener slot references must resolve to `SkeletonData.slots`;
   - the target helper attachment must resolve to either
     `SkeletonData.pointAttachments` or `SkeletonData.boundingBoxAttachments`;
  - file loaders must prove the target slot can resolve to that helper either
     through its setup `slot.attachment` value or through a declared skin entry;
     runtime dispatch uses the active-skin resolution rules already documented
     in `docs/skin-attachment-set-contract.md`;
   - the input reference must resolve in the owning state machine;
   - bool listeners require a bool value, number listeners require a finite f32
     numeric value, and trigger listeners reject any value;
   - lifecycle-only fields (`layer`, `fromState`, `toState`) remain invalid for
     pointer listeners unless the new contract explicitly says otherwise.
5. Define binary wire shape using the existing `stateMachineListener` object
   family if it remains compatible. Append any required M8 property keys to
   `registry/wire.yml` using only `registry/key-ranges.md`. Reuse existing
   property keys only when their backing type and documented meaning are
   compatible; otherwise append new project-owned M8 keys. Update
   `spec/defaults.yml` and regenerate generated schema/runtime metadata with
   `python3 codegen/generate.py`.
6. Update Nim load/round-trip shape without adding runtime pointer dispatch:
   - `runtime-nim/src/bony/statemachine/core.nim`
   - `runtime-nim/src/bony/jsonio.nim`
   - `runtime-nim/src/bony/binary/semantic.nim`
   - `runtime-nim/src/bony/generated/wire.nim`
7. Update Dart load/round-trip shape to match Nim, without runtime pointer
   dispatch:
   - `runtime-dart/lib/src/model.dart`
   - `runtime-dart/lib/src/loader.dart`
   - `runtime-dart/lib/src/generated/wire.dart`
8. Update `docs/README.md`, `docs/CLEANROOM.md`, `docs/PROVENANCE.md`,
   `docs/binary-animation-state-machine-contract.md`, and
   `docs/animation-state-machine-validation-ownership.md` so pointer listeners
   are documented as project-owned capability, not comparable-product-derived
   implementation.

Do not implement pointer input scripts, runtime hit testing, event dispatch, or
golden generation in this slice. This is the stable serialized surface that the
next prompt will implement in the Nim reference runtime.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local binding spec: /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md
- Helper geometry contract: docs/helper-geometry-attachment-contract.md
- Skin resolution contract: docs/skin-attachment-set-contract.md
- State-machine binary contract: docs/binary-animation-state-machine-contract.md
- State-machine validation ownership: docs/animation-state-machine-validation-ownership.md
- Registry key bands: registry/key-ranges.md
- Registry/default/schema sources: registry/wire.yml, spec/defaults.yml,
  codegen/generate.py, spec/bony.schema.json, spec/bony-wire.schema.json
- Nim seams: runtime-nim/src/bony/statemachine/core.nim,
  runtime-nim/src/bony/jsonio.nim,
  runtime-nim/src/bony/binary/semantic.nim,
  runtime-nim/src/bony/generated/wire.nim
- Dart seams: runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart,
  runtime-dart/lib/src/generated/wire.dart
- Beads: parent bony-1umq; child bony-g65e

**Success Criteria**
- `docs/pointer-helper-listener-contract.md` exists and defines pointer listener
  kinds, JSON shape, `.bnb` shape, validation rules, active-skin target
  resolution, point-radius hit semantics, bounding-box hit semantics, dispatch
  order for the later runtime slice, and explicit non-goals.
- Existing lifecycle listeners remain backward compatible in JSON, `.bnb`, Nim,
  and Dart.
- `registry/wire.yml` and `spec/defaults.yml` contain append-only M8 changes or
  documented compatible property reuse; generated files are refreshed by
  `python3 codegen/generate.py`, not hand-edited.
- Nim and Dart can load and round-trip pointer listener records through JSON and
  `.bnb`, and reject malformed pointer listener records with existing loader
  error categories.
- Documentation and provenance explain the new serialized names and why the
  design is project-owned.
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
- Keep runtime pointer dispatch and conformance goldens out of this slice.
- Do not add renderer-visible batches for point or bounding-box attachments.
- Use only your allocated range from `registry/key-ranges.md`.
- Keep the slice small enough for one meaningful implementation session.
