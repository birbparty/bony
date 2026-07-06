# /big-change prompt - runtime-dart (skinRequired activation parity)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 4 of 4**. Depends on
> `46-conformance-skin-required-gate.md`.
> **Candidate category:** frontier.

---

/big-change Port skinRequired activation behavior to the Dart runtime.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Port the skin-required activation behavior to Dart after the Nim runtime and
shared conformance gate exist. The Dart runtime should mirror the Nim reference
semantics from `docs/skin-required-activation-contract.md` and pass the new
goldens introduced by prompt 46.

The Dart work should include:

- Loading and exposing the prompt-44 `skinRequired` and membership metadata if
  any Dart load/model gaps remain.
- Active membership evaluation for `"default"` plus active skin.
- Inactive required bone/slot/helper/nested draw suppression in
  `buildDrawBatches` and `buildNestedDrawBatches`.
- Inactive required IK/transform/path no-ops at canonical dispatch positions.
- Inactive required physics constraints that do not advance state and reset on
  reactivation.
- Dart tests against the new conformance `.bony` and `.bnb` assets.

Keep the implementation aligned with Nim behavior rather than making new policy
choices. If the Nim reference and the contract disagree, stop and file a follow-
up bead rather than inventing Dart-only behavior.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Binding contract: docs/skin-required-activation-contract.md
- Skin lookup: docs/skin-attachment-set-contract.md
- Constraint ordering: docs/constraint-total-order.md
- Physics integration: docs/physics-integrator-contract.md
- Nim reference implementation from prompt 45: runtime-nim/src/bony/transform.nim,
  runtime-nim/src/bony/model.nim
- Shared conformance from prompt 46: conformance/README.md,
  conformance/assets/, conformance/assets/bnb/, conformance/scripts/,
  conformance/goldens/
- Dart model/load/runtime: runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart, runtime-dart/lib/src/transform.dart,
  runtime-dart/lib/src/physics_constraint.dart, runtime-dart/lib/bony.dart
- Existing Dart tests: runtime-dart/test/m10_conformance_test.dart,
  runtime-dart/test/m20_skin_test.dart,
  runtime-dart/test/m5_physics_story_test.dart,
  runtime-dart/test/nested_rig_attachment_test.dart
- Beads: bony-i4x6, bony-i4x6.4

**Success Criteria**
- Dart active membership evaluation matches Nim for `"default"` and non-default
  active skins.
- Dart `buildDrawBatches` and `buildNestedDrawBatches` suppress inactive
  required slots/content and preserve existing behavior for assets without
  skin-required metadata.
- Dart world-transform constraint dispatch preserves canonical order while
  inactive required IK/transform/path constraints no-op at their positions.
- Dart `advancePhysics` skips inactive required physics constraints, preserves
  state while inactive, and resets on inactive-to-active reactivation.
- Dart `.bony` and `.bnb` loaders accept the new valid conformance fixtures and
  reject malformed membership cases covered by Dart unit tests.
- Dart conformance tests match the prompt-46 goldens within the existing
  `1e-4` tolerance.
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
- Do not change registry keys, generated schemas, generated wire files, Nim
  behavior, or shared goldens except to fix a locally verified bug in an earlier
  slice.
- Do not add importer behavior, vector/text/layout features, or new state-
  machine semantics.
- Treat Nim reference behavior and the shared conformance goldens as the parity
  source for Dart.
