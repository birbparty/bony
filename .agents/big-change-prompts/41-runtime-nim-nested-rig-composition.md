# /big-change prompt - runtime-nim (nested rig draw-batch composition)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 3**. Depends on
> `40-contract-nested-rig-runtime-composition.md`; must land before
> `42-runtime-dart-nested-rig-composition.md`.
> **Candidate category:** frontier.

---

/big-change Add opt-in host-resolved nested rig draw-batch composition to the Nim reference runtime.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Implement the Nim reference runtime side of the nested rig runtime composition
contract from prompt 40. Keep existing `buildDrawBatches` overloads unchanged:
they must continue to treat nested rig attachments as non-rendering so current
tests such as the nested rig format round-trip case keep passing.

Add a new exported opt-in API in `runtime-nim/src/bony/transform.nim` that accepts
host-supplied child skeletons keyed by the nested attachment's `skeleton` string.
The exact symbol name can be chosen in the implementation, but it must be
documented and exported through `runtime-nim/src/bony.nim`. The implementation
should:

- Resolve the host slot attachment through `resolveSkinAttachmentTarget` exactly
  like `buildDrawBatches(data, worlds, activeSkin)` already does.
- When the resolved attachment names a `NestedRigAttachmentData`, find the child
  `SkeletonData` in the supplied map.
- Use `nested.skin` when non-empty, otherwise `"default"`, and reject unknown
  child skins.
- Build the child setup-pose batches with the child active skin.
- Compose every child batch vertex and batch `world` through the host slot bone
  world affine, preserving deterministic float ordering.
- Insert the composed child batches at the host slot's draw-order position.
- Keep parent clipping effective for child batches by associating composed
  batches with the host slot index before the existing clip pass runs.
- Apply child-internal clipping before parent-affine composition.
- Detect recursive nested references in the supplied child map and raise
  `cycleDetected` rather than recurring indefinitely.

Do not add automatic file loading, nested animation playback, state-machine
playback, physics state advancement, importer mapping, or CLI multi-asset input
in this slice.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Runtime composition contract: docs/nested-rig-runtime-composition-contract.md
  (created by prompt 40)
- Existing nested format contract: docs/nested-rig-attachment-contract.md
- Nim model: runtime-nim/src/bony/model.nim
- Nim draw batches/world transforms: runtime-nim/src/bony/transform.nim
- Nim package root exports: runtime-nim/src/bony.nim
- Existing Nim nested tests: runtime-nim/tests/test_smoke.nim
- Existing Dart parity reference for later: runtime-dart/test/nested_rig_attachment_test.dart
- Beads: bony-xmo6, bony-xmo6.2

**Success Criteria**
- A new exported Nim nested-composition draw-batch API exists and is documented
  in code or contract prose.
- Existing `buildDrawBatches` overloads remain backward compatible: a loaded
  nested rig attachment still emits zero batches unless the new opt-in API is
  used.
- Nim unit tests cover:
  - host skeleton with a nested slot and a child skeleton with one region;
  - parent transform composition changes child vertices by more than `1e-4`;
  - child active skin defaults to `"default"` and honors non-empty `nested.skin`;
  - missing child skeleton and recursive nested reference failure paths;
  - parent clipping applies to composed nested child geometry when the host slot
    is inside a clip range.
- Existing conformance fixture count comments stay accurate unless new fixtures
  are intentionally added; this slice should not add conformance assets.
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
- Do not change serialized format keys, schemas, defaults, or generated wire
  files.
- Do not add nested asset file resolution, CLI multi-file loading, nested
  animation/state-machine playback, nested physics state, or importer behavior.
- Keep Dart changes out of this prompt except for reading existing files as
  parity context.
