# /big-change prompt - Dart runtime deform-timeline parity

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 4 of 4** of the M4 deform-timeline milestone. Depends
> on `24-runtime-nim-deform-timeline.md` (the runtime seam it mirrors) and
> `25-conformance-deform-anim-gate.md` (the committed `m18` goldens it consumes).
> Can run once those two have landed.
> **Candidate category:** frontier.

---

/big-change Port the deform (FFD) animation timeline to the Dart runtime - load it from `.bony` JSON and `.bnb`, sample it in the mixer, apply the per-vertex deltas to skinned mesh vertices in buildDrawBatches, and prove parity against the committed m18 state-machine deform-story goldens within 1e-4.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompts 23-25 the Nim reference runtime animates a mesh via a clip-owned
deform timeline and the `m18_deform_story_{rest,mid,end}.json` goldens are
committed. The Dart runtime has **no** deform-timeline support: `AnimationClip`
(`runtime-dart/lib/src/model.dart:638`) carries only `boneTimelines`/
`slotTimelines`, and `buildDrawBatches(SkeletonData)`
(`runtime-dart/lib/src/transform.dart:1162`) takes **no time argument** and never
offsets a mesh vertex. This prompt brings Dart to parity, matching the Nim
algorithm and the pinned cross-runtime seam from prompt 24 (sampled deltas are
carried through the posed `SkeletonData` and applied in `buildDrawBatches` right
after skinning - **not** via a new `buildDrawBatches` time parameter).

The Nim algorithm to port exactly (the parity reference, project-owned):
`runtime-nim/src/bony/mesh/deform.nim` - `sampleDeformDeltas` (`:112-137`:
nearest-preceding-key search, stepped short-circuit, `eased = curve.evaluate(t)`
linear interpolation of dense/expanded per-vertex deltas, f32 quantization at the
boundary) and `applyDeformDeltas` (`:140-153`: `x = quantizeF32(vertex.x +
delta.x)` after skinning). Match within `1e-4` per `docs/float-math-contract.md`.

Concretely, this prompt builds exactly this - **Dart runtime only**:

1. **Model** (`runtime-dart/lib/src/model.dart`): add a `DeformTimeline` class
   (fields `skin`, `slot`, `attachment`, `vertexCount`, and keys of `(time,
   offset, deltas[(x,y)], curve)`) mirroring the relocated Nim record; add a
   `deformTimelines` list to `AnimationClip` (`:638-648`). Reuse the existing
   `TimelineCurve`/`TimelineCurveKind` (`:452-475`) and add a `MeshDelta`/deform
   keyframe type beside the other keyframe classes (`:527-593`). Note the model
   keys the mesh by `name` (`:285-294`); a deform timeline's `attachment` is the
   mesh name.

2. **JSON loader** (`runtime-dart/lib/src/loader.dart`): in `_parseAnimations`
   (`:421`), parse `anim['deformTimelines']` (a block beside the boneTimelines
   loop `:433` and slotTimelines loop `:481`), reusing `_parseCurve` (`:270`) and
   `_ensureStrictlyIncreasing`, and `quantizeF32` from `deform.dart` (`:7`) at the
   load boundary. Enforce the same edge cases the Nim loader / contract enforce
   (skin `"default"` only, strictly increasing times, offset+deltas within
   vertexCount, attachment resolves to a mesh).

3. **BNB loader** (`runtime-dart/lib/src/loader.dart`): add the generated wire
   `deformTimeline` type (regenerated into
   `runtime-dart/lib/src/generated/wire.dart` by prompt 23's codegen - do NOT
   hand-edit; if a run is needed, re-run `python3 codegen/generate.py`), a
   `_bDeformTimelineKeys(...)` decode helper next to `_bBoneTimelineKeys`
   (`:1829`)/`_bSlotTimelineKeys` (`:1880`), and a `case` in the clip-object
   dispatch next to `_bnbBoneTimeline` (`:2424`)/`_bnbSlotTimeline` (`:2445`) that
   pulls the `timelineKeys` payload and the deform property keys.

4. **Mixer sampling** (`runtime-dart/lib/src/anim.dart`): add a deform sampler
   beside `sampleSlotAttachment` (`:107`) that mirrors `sampleDeformDeltas`; add a
   `_MixedDeform` accumulator carried on `MixedPose` (`:217`); in the private
   mixer `_applyEntry` (`~:599`) add a `entry.clip.deformTimelines` loop beside
   the bone loop (`:611`) and slot loop (`:628`); and in `applyPose`
   (`:652`) resolve the mixed deform set into the per-slot/attachment dense-delta
   override carried on the returned `SkeletonData` (the same seam Nim uses - do
   not touch mesh vertices in `applyPose` itself; only stage the override). The
   override is a **transient, non-serialized** field, mirroring the Nim seam:
   keep it out of Dart's `SkeletonData` serialization / round-trip, and ensure it
   survives any subsequent pose-rebuild stage (the Nim reference must carry it
   through `applySequencePose` too - see prompt 24 fork #2).

5. **Draw-batch application** (`runtime-dart/lib/src/transform.dart`): in
   `buildDrawBatches` (`:1162`), at the mesh skinning site `_skinMeshVertices`
   (`:1124`, called at `:1196`), add the posed deform override's `MeshDelta[]` to
   each skinned vertex **after skinning (`:1148-1157`) and before** the static M7
   deformer stage (`effectiveDeformers`/`applyDeformers`, `:1224-1266`) and the
   clipping stage (`_applyClipping`, `:1275`) - the pinned normative order from
   prompt 24. Match `applyDeformDeltas`'s `quantizeF32(vertex.x + delta.x)`
   exactly.

6. **Conformance test** (`runtime-dart/test/m18_deform_story_test.dart`): mirror
   `runtime-dart/test/m5_ik_story_test.dart` (the animated-story precedent): for
   each sample `{rest:0.0, mid:0.5, end:1.0}`, drive the `deform_story` state
   machine / clip `wiggle` to the sample time, `applyPose(base, pose)`
   (`m5_ik_story_test.dart:70`), `computeWorldTransforms`, `buildDrawBatches`, and
   assert each `drawBatches[].vertices` `x/y/u/v` matches the committed
   `conformance/goldens/m18_deform_story_<name>.json` within `1e-4` (the
   `_expectClose`/vertex-loop helpers from `m13_mesh_deform_test.dart:24-110` and
   the full-golden `_checkGolden` shape from `m10_conformance_test.dart:42`).
   Add a `.bony`-vs-`.bnb` parity assertion for at least one sample (mirror
   `m17_mesh_clip_bnb_test.dart:17-20`): load the mesh-deform clip from both
   `../conformance/assets/m18_mesh_deform_anim_rig.bony` and
   `../conformance/assets/bnb/m18_mesh_deform_anim_rig.bnb` and assert identical
   animated vertices.

7. **Docs**: update the `### M18` rig section's "Cross-runtime status" note in
   `conformance/README.md` to record that the `m18_deform_story_*` goldens are
   honored by **both** the Nim reference and the Dart runtime (mirror the
   `### M5 physics rig` cross-runtime status paragraph). While here, fix the stale
   note in the `### M5 IK rig` section claiming the `m5_ik_story_*` goldens
   "remain Nim-only pending the Dart story slice" - `runtime-dart/test/
   m5_ik_story_test.dart` already covers them; correct that sentence.

Keep it Dart-only: do NOT change the format, the registry, the Nim runtime, or
any committed golden. The goldens are the fixed cross-runtime contract; Dart must
reproduce them, not regenerate them.

**Links to Relevant Documentation**
- Binding contract: docs/deform-timeline-contract.md (prompt 23)
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4)
- Nim parity reference (algorithm to match): runtime-nim/src/bony/mesh/deform.nim
  (sampleDeformDeltas 112-137, applyDeformDeltas 140-153) and the pinned
  cross-runtime seam described in
  .agents/big-change-prompts/24-runtime-nim-deform-timeline.md (fork #2 + normative
  order)
- Committed goldens to reproduce: conformance/goldens/m18_deform_story_{rest,mid,
  end}.json; assets conformance/assets/m18_mesh_deform_anim_rig.bony +
  conformance/assets/bnb/m18_mesh_deform_anim_rig.bnb
- Dart model: runtime-dart/lib/src/model.dart (TimelineCurve 452-475, keyframe
  types 527-593, BoneTimeline 606, SlotTimeline 621, AnimationClip 638-648, mesh
  types 241-294)
- Dart loader: runtime-dart/lib/src/loader.dart (_parseAnimations 421, bone loop
  433, slot loop 481, _parseCurve 270, _parseMeshAttachment 72; BNB
  _bBoneTimelineKeys 1829, _bSlotTimelineKeys 1880, _bnbBoneTimeline 2424,
  _bnbSlotTimeline 2445)
- Dart wire schema (generated - do not hand-edit): runtime-dart/lib/src/generated/
  wire.dart (animationClip/boneTimeline/slotTimeline 89-91, timeline props
  178-181, object specs 222-224)
- Dart anim/mixer: runtime-dart/lib/src/anim.dart (samplers 76-151, MixedPose 217,
  AnimationState 408, sample 533, _applyEntry ~599 bone loop 611 slot loop 628,
  applyPose 652)
- Dart draw path: runtime-dart/lib/src/transform.dart (_skinMeshVertices 1124,
  buildDrawBatches 1162, mesh build 1185-1199, static deformer stage 1224-1266,
  clipping 1275, computeWorldTransforms 861) and runtime-dart/lib/src/deform.dart
  (effectiveDeformers 314, applyDeformers 356, quantizeF32)
- Dart test precedents: runtime-dart/test/m5_ik_story_test.dart (animated story
  shape), m13_mesh_deform_test.dart (mesh vertex compare helpers),
  m10_conformance_test.dart (_checkGolden full-golden shape),
  m17_mesh_clip_bnb_test.dart (.bony-vs-.bnb parity)
- Template: the Dart mesh-skinning parity slice
  .agents/big-change-prompts/22-dart-mesh-skinning-parity.md and its landed diff
- Repo gate: `cd runtime-dart && dart test`
- Beads: file under the deform-timeline milestone parent

**Success Criteria**
- Dart `AnimationClip` carries `deformTimelines`; the JSON and `.bnb` loaders
  both parse them (with the same edge-case rejections as Nim / the contract).
- The Dart mixer samples deform timelines and `applyPose` stages a per-slot/
  attachment dense-delta override; `buildDrawBatches` applies it to skinned mesh
  vertices after skinning and before the M7/clipping stages, matching
  `applyDeformDeltas` exactly.
- `runtime-dart/test/m18_deform_story_test.dart` reproduces all three
  `m18_deform_story_*` goldens within `1e-4` from the `.bony`, and at least one
  sample additionally from the `.bnb`, with identical animated vertices.
- `conformance/README.md` M18 cross-runtime status records Nim+Dart parity; the
  stale M5-IK "Nim-only" sentence is corrected.
- `cd runtime-dart && dart test` passes (all suites); no committed golden,
  format, registry, or Nim file changed.

**Constraints**
- Preserve clean-room posture: match `bony`'s own `mesh/deform.nim`; do not derive
  the deform algorithm from any third-party runtime.
- Keep Rive importer out of scope; keep Spine importer blocked.
- Dart-only: do NOT change the format, registry, Nim runtime, or any committed
  golden. Reproduce the goldens, do not regenerate them.
- Match the pinned cross-runtime seam: carry deltas through the posed
  `SkeletonData`; do NOT add a `buildDrawBatches` time parameter.
- Keep the slice to one meaningful implementation session: model + JSON/BNB load +
  mixer sampling + draw-batch application + the m18 parity test.
