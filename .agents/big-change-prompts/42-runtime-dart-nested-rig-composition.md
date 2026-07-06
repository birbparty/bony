# /big-change prompt - runtime-dart (nested rig draw-batch composition)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 3**. Depends on
> `41-runtime-nim-nested-rig-composition.md`.
> **Candidate category:** frontier.

---

/big-change Port opt-in host-resolved nested rig draw-batch composition to the Dart runtime.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Port the Nim nested-composition behavior from prompt 41 to the Dart runtime.
Keep the existing `buildDrawBatches(SkeletonData data, {String activeSkin =
'default'})` behavior unchanged: the existing Dart nested rig format tests
expect nested rig attachments to remain invisible unless the new opt-in API is
used.

Add a Dart API in `runtime-dart/lib/src/transform.dart`, exported by
`runtime-dart/lib/bony.dart`, that accepts host-supplied child skeletons keyed
by each nested attachment's `skeleton` string. Mirror the Nim reference
semantics:

- Resolve host slot attachments with `SkeletonData.resolveSkinAttachmentTarget`.
- Use `NestedRigAttachment.skin` when non-empty, otherwise `"default"`.
- Reject missing child skeletons, unknown child skins, and recursive nested
  references.
- Build child setup-pose batches with the child active skin.
- Compose child batch vertices and batch `world` through the host slot bone
  world affine in the same numeric order as Nim.
- Insert child batches at the host slot's draw-order position.
- Preserve child-internal clipping and parent clipping behavior from the Nim
  implementation.

Do not add automatic asset loading, Flutter integration, nested animation or
state-machine playback, physics state advancement, importer mapping, or new
serialized fields.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Runtime composition contract: docs/nested-rig-runtime-composition-contract.md
- Nim reference implementation: runtime-nim/src/bony/transform.nim,
  runtime-nim/tests/test_smoke.nim
- Dart model and skin resolution: runtime-dart/lib/src/model.dart
- Dart draw batches/world transforms: runtime-dart/lib/src/transform.dart
- Dart public exports: runtime-dart/lib/bony.dart
- Existing Dart nested tests: runtime-dart/test/nested_rig_attachment_test.dart
- Beads: bony-xmo6, bony-xmo6.3

**Success Criteria**
- A new Dart nested-composition draw-batch API exists and is exported from the
  package root.
- Existing Dart `buildDrawBatches` nested-format behavior remains unchanged.
- Dart tests cover the same visible behavior as the Nim tests:
  - one host nested slot plus one child region skeleton;
  - parent transform composition creates non-vacuous vertex movement above
    `1e-4`;
  - `NestedRigAttachment.skin` chooses the child active skin;
  - missing child skeleton and recursive nested reference failure paths;
  - parent clipping applies to composed nested child geometry.
- Dart numeric expectations match the Nim contract and, where practical, the
  concrete values from the Nim tests rather than loose smoke assertions.
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
- Do not change serialized format keys, schemas, defaults, or generated wire
  files.
- Do not add nested asset file resolution, Flutter-specific rendering behavior,
  nested animation/state-machine playback, nested physics state, importer
  behavior, or conformance assets.
