# /big-change prompt - runtime-nim (skinRequired activation)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 4**. Depends on
> `44-format-skin-required-surface.md`; must land before
> `46-conformance-skin-required-gate.md`.
> **Candidate category:** frontier.

---

/big-change Implement skinRequired activation in the Nim reference runtime.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Implement the Nim reference runtime behavior from
`docs/skin-required-activation-contract.md`, using the format/load metadata
introduced by prompt 44. This is the reference behavior slice for active-skin
membership. Dart parity and conformance assets come later.

The runtime must compute active membership from `"default"` plus the requested
active skin, derive effectively active bones/constraints, and apply the
contract's inactive behavior:

- Inactive required bones make their child bones, bound slots, helpers,
  attachments, clipping masks, path helpers, and nested-rig host slots
  unavailable for that pose.
- `buildDrawBatches` / `buildNestedDrawBatches` must not emit batches for
  inactive slots or content depending on inactive bones.
- IK, transform, and path constraints keep their canonical cache positions but
  no-op when inactive.
- Physics constraints do not accumulate `dt`, process substeps, or mutate state
  while inactive.
- A required physics constraint that transitions from inactive to active resets
  according to `docs/physics-integrator-contract.md`.

Keep this slice focused on Nim runtime and unit coverage. Do not add shared
conformance assets or Dart changes here.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Binding contract: docs/skin-required-activation-contract.md
- Skin lookup: docs/skin-attachment-set-contract.md
- Constraint ordering: docs/constraint-total-order.md
- Physics integration: docs/physics-integrator-contract.md
- Transform hierarchy: docs/transform-composition-contract.md
- Nim model/load metadata from prompt 44: runtime-nim/src/bony/model.nim,
  runtime-nim/src/bony/jsonio.nim, runtime-nim/src/bony/binary/semantic.nim
- Nim runtime seams: runtime-nim/src/bony/transform.nim,
  runtime-nim/src/bony.nim
- Existing Nim tests: runtime-nim/tests/test_skin_resolution.nim,
  runtime-nim/tests/test_smoke.nim, runtime-nim/tests/test_physics_eval.nim,
  runtime-nim/tests/test_ik_current_pivot.nim
- Beads: bony-i4x6, bony-i4x6.2

**Success Criteria**
- Nim exposes a deterministic active-membership helper or equivalent internal
  path that derives effectively active bones and constraints from a
  `SkeletonData` plus active skin.
- `computeWorldTransforms(data)` remains backward compatible for default
  assets with no skin-required metadata.
- A Nim active-skin runtime path exists for world transforms, physics advance,
  and draw-batch construction. Existing `buildDrawBatches(data, activeSkin)`
  and nested composition paths honor inactive required slots/content.
- Runtime constraint dispatch retains canonical order from
  `docs/constraint-total-order.md`; inactive required constraints no-op at their
  canonical cache position without moving later constraints.
- `advancePhysics` skips inactive required physics constraints without
  advancing accumulators or mutating offset/velocity/previous-target state, and
  resets a required physics constraint when it becomes active after inactivity.
- Nim tests cover inactive required bone draw suppression, helper/path
  unavailability, inactive IK/transform/path no-op ordering, inactive physics
  state preservation, and reactivation reset.
- Existing conformance fixture count assertions remain accurate unless this
  slice intentionally adjusts only Nim unit fixtures.
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
- Do not edit registry keys, generated schemas, generated wire files, Dart
  runtime code, or shared conformance assets in this slice unless prompt 44 left
  a narrowly documented metadata bug that blocks runtime work.
- Do not add new serialized fields or change membership semantics beyond
  `docs/skin-required-activation-contract.md`.
- Keep Dart parity for prompt 47 and shared conformance assets for prompt 46.
