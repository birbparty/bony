# /big-change prompt - contract (nested rig runtime composition)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 3**. Must land before
> `41-runtime-nim-nested-rig-composition.md`.
> **Candidate category:** frontier.

---

/big-change Define the project-owned runtime composition contract for host-resolved nested rig attachments.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

The nested rig format slice is already implemented: `docs/nested-rig-attachment-contract.md`,
`registry/wire.yml`, `spec/defaults.yml`, Nim model/JSON/BNB loading, and Dart
model/JSON/BNB loading all include `nestedRigAttachments`. The contract
explicitly defers runtime playback and currently says nested rig attachments
emit no `DrawBatch`.

Write the next binding contract only. It should define setup-pose draw-batch
composition for host-resolved nested skeletons:

- A host application supplies already-loaded child `SkeletonData` objects keyed
  by each `NestedRigAttachmentData.skeleton` / Dart `NestedRigAttachment.skeleton`
  string.
- The host slot's bone world affine becomes the parent transform for the child
  skeleton's setup-pose draw batches.
- Child batches are inserted at the host slot's draw-order position.
- The child active skin is `nested.skin` when non-empty, otherwise `"default"`.
- The child default `animation` string remains stored metadata only in this
  slice; no nested animation or state-machine playback is added.
- Existing `buildDrawBatches` behavior remains backward compatible: without the
  new nested-composition API, nested rig attachments still emit no batches.
- Missing child skeletons, unknown child skins, and recursive nested references
  fail loudly through existing load/runtime error categories rather than silently
  dropping visible content.

Create a new contract document, then cross-link it from the existing nested rig
attachment contract and docs index. Do not edit registry keys or schemas in this
slice.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local binding spec: /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md
- Existing nested format contract: docs/nested-rig-attachment-contract.md
- Runtime draw-batch seams: runtime-nim/src/bony/transform.nim,
  runtime-dart/lib/src/transform.dart
- Runtime models: runtime-nim/src/bony/model.nim,
  runtime-dart/lib/src/model.dart
- Error categories: docs/load-validation-contract.md
- Beads: bony-xmo6, bony-xmo6.1

**Success Criteria**
- `docs/nested-rig-runtime-composition-contract.md` is created.
- The new contract defines parent-affine composition, child active-skin choice,
  draw-order insertion, host clipping interaction, child-internal clipping
  behavior, recursion/cycle handling, and missing-child behavior.
- `docs/nested-rig-attachment-contract.md` links to the new runtime composition
  contract while preserving its format/load-only scope.
- `docs/README.md` lists the new contract in the appropriate binding-contract
  section.
- `docs/CLEANROOM.md` and `docs/PROVENANCE.md` need no new serialized-name entry
  unless the implementation introduces new public identifiers; if they are
  touched, they must state that nested-armature/artboard comparisons remain
  capability context only.
- Verification: docs/contract-only slice; run `git diff --check`.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Keep DragonBones and Lottie importer mapping out of this slice.
- Do not add nested skeleton asset loading, automatic file lookup, nested
  animation playback, nested state-machine playback, nested physics state
  advancement, or conformance assets in this contract slice.
- Do not change `registry/wire.yml`, `spec/defaults.yml`, generated schemas, or
  generated wire files.
- Keep the contract small enough to drive one implementation session.
