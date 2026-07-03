# /big-change prompt - runtime (Nim) deform-timeline sampling + mesh application

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 4** of the M4 deform-timeline milestone. Depends
> on `23-contract-deform-timeline-format.md` (the loadable record + contract).
> Must land before `25-conformance-deform-anim-gate.md` (the conformance gate
> generates goldens from this runtime) and `26-dart-deform-timeline-parity.md`.
> **Candidate category:** frontier.

---

/big-change Wire the already-loadable `deformTimeline` record into the Nim animation clip + mixer so a clip's deform timeline is sampled at a time and its per-vertex offsets are applied to the skinned mesh before draw-batch emission, matching the project-owned `mesh/deform.nim` algorithm - runtime evaluation only, plus the CLI story-path plumbing that lets a state-machine golden observe an animated mesh.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompt 23, the `deformTimeline` **wire contract** exists - registry keys,
JSON + wire schema, and regenerated codecs - but **no runtime loads it**: it is
not a field on `AnimationClip` (`runtime-nim/src/bony/anim/timelines.nim:137-142`),
no loader constructs one, and `buildDrawBatches` never offsets a mesh vertex.
This prompt adds the **full Nim runtime path** - clip ownership, JSON + `.bnb`
load/round-trip (with the round-trip test and edge-case rejections deferred from
prompt 23), mixer sampling, and mesh application. This prompt makes a clip's
deform timeline **animate a mesh**: the clip owns its deform timelines, the mixer
samples them at the track time, and the sampled deltas offset the skinned mesh
vertices via the pre-existing `applyDeformDeltas`/`sampleDeformDeltas`
(`mesh/deform.nim:112-166`) before the mesh `DrawBatch` is emitted.

**Architectural fork #1 - the import cycle (load-bearing; decide explicitly and
verify with `nim check`).** `mesh/deform.nim` imports `anim/timelines`
(`deform.nim:3`, for `TimelineCurve`) and `model`. So making `AnimationClip`
(defined in `timelines.nim`) hold a `seq[DeformTimeline]` (defined in
`deform.nim`) would force `timelines.nim` to import `deform.nim`, which imports
`timelines.nim` - a cycle. Resolve it the same way the mesh milestone resolved
its analogous cycle (prompt 19: mesh record types were relocated into
`model.nim`). Recommended: **relocate the plain-data deform record types**
(`MeshDelta`, `DeformKeyframe`, `DeformTimeline`, `mesh/deform.nim:8-23`) up the
import DAG, keeping the sampler/apply/validator **procs** in `mesh/deform.nim`.
Note `DeformKeyframe` carries a `TimelineCurve`, which lives in `timelines.nim`
(`:8-14`), so the type home must sit **at or below `timelines.nim`** - which
**rules out `model.nim`** (it sits below `timelines.nim` and cannot see
`TimelineCurve`, unlike the mesh precedent that could use `model.nim`; do not try
`model.nim` first here). Viable homes: (a) move the deform record types **into
`timelines.nim`** beside the timeline types - `MeshDelta` is dependency-free,
`DeformKeyframe` needs only the same-module `TimelineCurve`, `DeformTimeline` is
plain - **simplest, no new imports into `timelines.nim`**; or (b) introduce a
small shared low-level module holding `TimelineCurve` + the deform record types
that both `timelines.nim` and `deform.nim` consume. Pick the option that leaves no
cycle; **`nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim`
is the gate**. Do NOT duplicate the type.

**Architectural fork #2 - carrying sampled deltas into `buildDrawBatches`
(load-bearing; pin this and mirror it in prompt 26).** `buildDrawBatches` today
takes only `SkeletonData` and samples static M7 deformers at default parameters;
it has no animation clock and no per-vertex offset input (same shape in Dart).
A deform timeline is a pure function of clip time, so the cleanest cross-runtime
seam is: the mixer's applied pose (`applyPose*`, `mixer.nim:542`) resolves each
active deform timeline into a **per-slot per-attachment dense delta set** carried
on the posed `SkeletonData` (an override table keyed by slot/attachment), and
`buildDrawBatches` applies those deltas to the skinned mesh vertices via
`applyDeformDeltas` (`mesh/deform.nim:140-153`) **immediately after skinning and
before any M7 deformer / clipping stage**. Pin this exact application point and
order in the runtime and reference it from prompt 26 so both runtimes agree.
(Rationale: it needs no new `buildDrawBatches` time parameter and reuses the
existing pose->buildDrawBatches CLI path that physics/IK stories already use.)

**The override MUST be a transient, non-serialized field** set on the posed
`SkeletonData` after construction (or a companion structure returned alongside
it) - it MUST be **excluded** from `validateSkeletonData*`, the round-trip getter
list, and JSON/`.bnb` emission. (Contrast prompt 19, which had to thread
`meshAttachments` through *both* validate paths and the round-trip getters; the
deform override is the opposite - it must NOT be threaded there, or it will break
round-trip / over-validate.) It MUST also survive **both** pose-rebuilding
stages: the CLI story path chains `data.applyPose(pose).applySequencePose(pose)`
(`cli/bony_cli.nim:1415`; `applySequencePose` def `:1377`) and then calls
`buildDrawBatches(sample.posedData, sample.worlds)` (`:1934`), so
`applySequencePose` (which rebuilds `SkeletonData` again) must **carry the
override forward** or it is silently dropped before the draw path. The
setup-pose path calls the unposed `buildDrawBatches(data)` (`:1944`) with an
**empty** override, which guarantees existing (deform-free) goldens stay
byte-identical.

**Normative apply order (pin; the v1 conformance rig avoids exercising the
combination, but document it):** for a mesh, apply in this order - (1) linear-blend
/ FK skinning (`skinMeshVertices`), (2) deform-timeline deltas
(`applyDeformDeltas`), (3) M7 parametric deformers (`effectiveDeformers` /
`applyDeformers`), (4) per-triangle clipping. The prompt-25 rig MUST NOT combine
a deform timeline with an M7 deformer on the same mesh (keep step 3 empty for the
conformance mesh), so the deform-vs-M7 ordering stays documented-but-unexercised
in v1; do not silently reorder the existing stages.

Concretely, this prompt builds exactly this - **runtime eval only**:

1. **Clip ownership** (`anim/timelines.nim`): add `deformTimelines:
   seq[DeformTimeline]` to `AnimationClip` (`:137-142`), a `deformTimelines*`
   accessor beside `boneTimelines*`/`slotTimelines*` (`:178-180`), a
   `deformTimelines` parameter + validation + duration accumulation in the
   `animationClip*` constructor (`:578-623`; the duration loops at `:599/:604/:613`
   must fold in each deform key's `time`). Validate that each deform timeline's
   `slot`/`attachment` resolves to a loaded mesh (parallel to how attachment
   timelines validate against `regionNames` at `:608-611`, but resolving against
   `meshAttachments` names + the `"default"` skin).

2. **JSON load/emit wiring** (`runtime-nim/src/bony/jsonio.nim`): in
   `parseBonyAnimations` (`:811`), add `"deformTimelines"` to the clip-level
   allowed-keys (`:818`) and parse the array (a block mirroring the slot-timeline
   loop at `:893-972`) into `DeformTimeline`s via the `deformTimeline*`/
   `deformKeyframe*` constructors, then pass them into the `animationClip(...)`
   assembly (`:973`). In `appendAnimationsJson` (`:1250`), add a `deformTimelines`
   emission block (after `:1403`) reusing `appendCurveFields` (`:1312`) for key
   curves. **Ordering caveat:** the `deformTimeline*` constructor takes a
   `MeshAttachment` and validates against it, so deform timelines must be
   constructed **after meshes are parsed/assembled** - pin this ordering (the
   round-trip test catches a wrong order).

3. **BNB read/write** (`runtime-nim/src/bony/binary/semantic.nim`): add a
   `deformTimelineTypeKey = 3002` constant (`:27-29` block), a
   `writeTimelineKeys(DeformTimeline)` payload writer (mirror the bone/slot
   writers at `:787/:813` and reuse the shared curve serialization), a
   `for timeline in clip.deformTimelines` encode block in `buildObjectRecords`
   (`:1252-1267`, emitting one `deformTimelineTypeKey` record with the
   `deformSkin`/`slotIndex`/`deformAttachment`/`deformVertexCount`/`timelineKeys`
   properties per the registry `objects` order), a `currentDeformTimelines`
   accumulator + a `of deformTimelineTypeKey:` decode arm in
   `decodeAnimationObjects` (`:1781-1833`, mirroring the `slotTimelineTypeKey` arm
   at `:1818` and resolving slot/attachment/skin string indices), and thread it
   into the `flushAnimation` `animationClip(...)` call (`:1796`).

4. **Mixer sampling** (`runtime-nim/src/bony/anim/mixer.nim`): add a
   `MixedDeform` object (near `MixedAttachment` at `:25`) and a `deforms` field on
   `MixedPose` (`:51-58`); in `applyEntry` (`:436-475`) add a
   `for timeline in entry.clip.deformTimelines` loop (gated by
   `finalWeight >= track.mixAttachmentThreshold` like attachments at `:462`)
   that samples via `sampleDeformDeltas(timeline, sampleTime)`
   (`mesh/deform.nim:112`); in `sample*` (`:504-539`) allocate the deforms table,
   drain + deterministically sort it into `MixedPose.deforms` (add a `deformOrder`
   comparator like `:490`); in `applyPose*` (`:542`) resolve the mixed deform set
   into the per-slot/attachment dense-delta override carried on the posed
   `SkeletonData` (reach the mesh via `state.data` as `applyPose` already reaches
   `data.deformers` at `:625`).

5. **Draw-batch application**: at the mesh skinning site in `buildDrawBatches`
   (the exported `bony.nim` draw path / the CLI's `numericGoldenJson`
   `cli/bony_cli.nim:1699`), after `skinMeshVertices` and before the M7 deformer
   stage, apply the posed deform override for that slot/attachment via
   `applyDeformDeltas` (`mesh/deform.nim:140-153`). Reuse the exported deform
   draw-batch module from iteration 187 where it fits
   (`runtime-nim/src/bony/deform/drawbatch_deform.nim`), but note that module
   applies **M7 parametric deformers**, not deform-timeline deltas - the two are
   distinct stages; keep them separate per the normative order above.

6. **CLI story path** (`cli/bony_cli.nim`): a deform timeline is stateless in time
   (unlike physics, which needs the `advancePhysics` stateful seam
   `runtime-nim/src/bony/transform.nim` carried across samples), so the existing
   state-machine story path (`executeStateMachineScript` ->
   `writeNumericGolden` `:1799`) needs only to ensure the sampled pose's deform
   override reaches `buildDrawBatches`/`numericGoldenJson` (`:1699`). Verify a
   state-machine story that plays a clip with a deform timeline produces
   time-varying mesh vertices in the golden JSON's `drawBatches[].vertices`.

7. **Nim unit tests**: (a) a clip with a deform timeline sampled at three times
   produces the expected interpolated per-vertex offsets (assert against
   `sampleDeformDeltas` directly and through the full mixer->buildDrawBatches
   path); (b) a stepped-curve deform key holds until the next key; (c) a deform
   override for slot A does not leak onto slot B's mesh; (d) a clip with no deform
   timeline is byte-identical to today (no regression in existing goldens).

Keep the slice to **evaluation + application only**: do NOT add the conformance
rig/goldens (prompt 25) or touch Dart (prompt 26). Do NOT add skins, linked
meshes, or per-vertex color. Do NOT change any existing committed golden - all
existing `.bony`/`.bnb` conformance vectors must remain byte-identical (a clip
without a deform timeline must behave exactly as before).

**Links to Relevant Documentation**
- Binding contract from prompt 23: docs/deform-timeline-contract.md (sampling
  formula + apply order + edge cases + `skin == "default"`)
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4 tolerance,
  f32 at output boundary)
- Deform runtime (procs to wire in): runtime-nim/src/bony/mesh/deform.nim
  (sampleDeformDeltas 112-137, applyDeformDeltas 140-153, applyDeformTimeline
  156-166, deformTimeline ctor 83-95)
- Clip/timeline model: runtime-nim/src/bony/anim/timelines.nim (SlotTimelineKind
  33-39, BoneTimeline 122, SlotTimeline 129, AnimationClip 137-142, accessors
  178-180, animationClip ctor 578-623, attachment validation 608-611)
- Mixer: runtime-nim/src/bony/anim/mixer.nim (MixedAttachment ~25, MixedPose
  51-58, applyEntry 436-475 incl. attachment branch 465 + threshold 462, sample
  504-539 incl. order cmp 490, applyPose 542 + deformer reach 625)
- Binary: runtime-nim/src/bony/binary/semantic.nim (type-key consts 27-29,
  property-key consts 90-94, writeTimelineKeys 787/813, buildObjectRecords encode
  1252-1267, decodeAnimationObjects 1781-1833 incl. slotTimeline arm 1818 +
  flushAnimation 1791-1796)
- JSON io: runtime-nim/src/bony/jsonio.nim (parseBonyAnimations 811, clip
  allowed-keys 818, slot-timeline loop 893-972, appendAnimationsJson 1250,
  appendCurveFields 1312, emission tail 1403)
- CLI: cli/bony_cli.nim (numericGoldenJson 1699, writeNumericGolden 1799,
  requireSetupPoseTime 175-180, executeStateMachineScript path 1833-1843,
  physics advance analog for the stateful-vs-stateless contrast)
- Exported M7 deform draw-batch module (distinct stage - do not conflate):
  runtime-nim/src/bony/deform/drawbatch_deform.nim
- Template: the mesh runtime-eval slice
  .agents/big-change-prompts/20-runtime-nim-mesh-skinning-evaluation.md and its
  landed diff (how skinning was wired into buildDrawBatches)
- Repo gate: Makefile `test`; nim check per docs/nim.md conventions

**Success Criteria**
- The import cycle is resolved (deform record types relocated with no
  duplication); `nim check --hints:off --path:runtime-nim/src
  runtime-nim/src/bony.nim` is clean.
- `AnimationClip` owns `deformTimelines`; the mixer samples them and `applyPose`
  carries a per-slot/attachment dense-delta override; `buildDrawBatches` offsets
  the skinned mesh vertices via `applyDeformDeltas` immediately after skinning and
  before the M7/clipping stages, matching `mesh/deform.nim` within `1e-4`.
- JSON and `.bnb` both load, sample, and reproduce a clip's deform timeline
  identically (a Nim test drives a deform clip from both loaders and asserts equal
  time-sampled mesh vertices).
- A state-machine story that plays a deform clip yields time-varying
  `drawBatches[].vertices` in `bony golden-gen --state-machine ... --sample ...`
  output (verified by a Nim test or a scratch CLI run against a temp rig).
- Nim unit tests (a)-(d) above pass.
- Every existing committed conformance golden (`.bony` and `.bnb`) remains
  byte-identical; all four CI gates pass on the existing suite; `make test`
  passes.

**Constraints**
- Preserve clean-room posture: the sampling/apply algorithm is the project's own
  `mesh/deform.nim`; do not derive it from any third-party runtime.
- Keep Rive importer out of scope; keep Spine importer blocked.
- Do NOT add a conformance rig/golden (prompt 25) or touch the Dart runtime
  (prompt 26) in this prompt.
- Do NOT change existing goldens or reorder existing skinning/deformer/clipping
  stages except to insert the new deform-delta stage at the pinned point.
- Do NOT introduce a `buildDrawBatches` time parameter - carry the sampled deltas
  through the posed `SkeletonData`, so the seam matches Dart in prompt 26.
- Keep the slice to one meaningful implementation session: clip ownership + JSON/
  BNB read+write + mixer sampling + draw-batch application + Nim tests. If long,
  the natural cut line is: **unit A** = import-cycle relocation + clip ownership +
  JSON/BNB read+write + round-trip test (no draw change yet); **unit B** = mixer
  sampling + `applyPose` override + `buildDrawBatches` application + eval tests.
  Do not land unit A in a way that leaves `make test` red.
