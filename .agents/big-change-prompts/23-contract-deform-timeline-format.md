# /big-change prompt - contract + format (M4 deform/FFD animation timeline, format only)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 4** of the M4 deform-timeline milestone. Must
> land before `24-runtime-nim-deform-timeline.md` (the runtime wiring reads the
> loaded record and the contract this prompt defines). Prompts 25 (conformance)
> and 26 (Dart parity) follow.
> **Candidate category:** frontier.

---

/big-change Introduce a first-class, project-owned "deform timeline" (an animated per-vertex mesh-offset / FFD timeline owned by an animation clip) as a binding format contract plus the registry keys, canonical JSON + wire schema, and regenerated codec artifacts for a clip-owned `deformTimeline` record - contract + schema/registry/codegen only. Runtime load/round-trip wiring and all clip/mixer/draw-batch behavior land in prompt 24.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony` has a fully-built but **entirely non-serialized** deform-timeline runtime.
The types `MeshDelta`, `DeformKeyframe`, `DeformTimeline` and the sampler/apply
procs `sampleDeformDeltas*`, `applyDeformDeltas*`, `applyDeformTimeline*`,
`deformTimeline*`, `deformKeyframe*`, `validateDeformTimeline*`
(`runtime-nim/src/bony/mesh/deform.nim:8-166`) all exist, but **no loader ever
constructs a DeformTimeline and no clip owns one**: grep confirms
`DeformTimeline`/`sampleDeformDeltas` appear nowhere in `jsonio.nim`,
`anim/`, `binary/`, `model.nim`, or `asset.nim` (only inside `mesh/deform.nim`).
There is no deform-timeline type key in the registry, no `$defs` entry in either
schema, and no `deformTimelines` field on `AnimationClip`
(`runtime-nim/src/bony/anim/timelines.nim:137-142` has only
`boneTimelines`/`slotTimelines`/`eventTimelines`).

Meanwhile the registry M4 band `3000..3999` is scoped
"Meshes, weights, skins, **deform timelines**, clipping"
(`registry/wire.yml:60-63`, `registry/key-ranges.md:22`); mesh + clipping have
spent typeKeys `3000`/`3001` and propertyKeys `3000..3005`, so **deform
timelines are the last unspent M4-band feature**. This milestone finally wires
the pre-existing project-owned deform runtime into the serialized format.

This prompt writes the deform timeline's **binding contract** and mints its
**wire format** (registry keys + regenerated JSON/wire schema + generated
codecs), so the next slice (prompt 24) can add the runtime load path, sample it,
and apply it to skinned mesh vertices. **No clip wiring, no `jsonio`/`semantic`/
`timelines` code, no mixer or `buildDrawBatches` change in this prompt** - after
it, the `deformTimeline` record exists in the registry and both schemas and the
animation-clip JSON `$defs` gains an optional `deformTimelines` array, but no
runtime loads, validates, or round-trips it yet (that is prompt 24). It is
de-risked by the pre-existing project-owned Nim deform math (`mesh/deform.nim`),
which this milestone finally serializes.

**Project-owned deform-timeline model to define (decide and document these).**
"An animated per-vertex mesh offset (a.k.a. FFD / deform / free-form deform
animation)" is a generic capability category; the specific record below is
`bony`-owned and mirrors the **already-existing** project type in
`mesh/deform.nim`. It must not be derived from any third-party runtime's fields,
wire layout, or naming.

1. A deform timeline is a **clip-owned timeline**, a third timeline family
   alongside `boneTimelines` and `slotTimelines` (it is authored under a new
   `deformTimelines` array on each animation clip). It targets a specific mesh
   attachment on a specific slot and animates that mesh's per-vertex offsets over
   time. Its serialized shape mirrors `DeformTimeline`
   (`mesh/deform.nim:18-23`): `skin`, `slot`, `attachment`, `vertexCount`, and a
   list of keyframes.
2. Each keyframe mirrors `DeformKeyframe` (`mesh/deform.nim:12-16`): `time`
   (f32-quantized, non-negative, strictly increasing across the timeline), a
   sparse-window `offset` (uint) into the vertex list, a `deltas` list of
   `(x, y)` `MeshDelta` pairs (`mesh/deform.nim:8-10`), and a `curve` (reuse the
   existing `TimelineCurveKind`/`TimelineCurve` linear/stepped/bezier machinery -
   `timelines.nim:8-14` - and the shared `timelineKeys` curve encoding).
3. The affected mesh's skinned vertices will (in prompt 24, not here) be offset
   by the sampled deltas before draw-batch emission via `applyDeformDeltas`
   (`mesh/deform.nim:140-153`).

**The `skin` field decision (load-bearing - decide this explicitly).**
`validateDeformTimeline*` (`mesh/deform.nim:66-68`) currently **requires a
non-empty `skin`**, but `bony` has **no skin construct yet** (grep: no `skin`
authoring anywhere; skins are a separate reserved M4 capability not built in this
milestone). Resolve this without inventing a skin subsystem: adopt a **reserved
default-skin identity** - the literal string `"default"` is the only accepted
`skin` value in v1, documented as forward-compatible with a future skin
milestone that will generalize it. Pin this in the contract: the loader accepts
`skin == "default"` and rejects any other value (so a future skin milestone can
widen the accepted set without breaking v1 files). Do **not** relax the
validator to allow empty - keep the field populated and meaningful.

**Registry-key decision (M4 band `3000..3999` only).** Next-free M4 typeKey is
`3002`; next-free M4 propertyKey is `3006` (mesh/clipping used `3000..3005` -
confirmed `registry/wire.yml`). The deform timeline is a **child record owned by
the most recent animationClip** (exactly like `boneTimeline`/`slotTimeline`,
`registry/wire.yml` objects block `1231-1246` and semantic decode flush boundary
`binary/semantic.nim:1791-1833`). Allocate:
- typeKey `deformTimeline` = `3002` (mirror the `slotTimeline` typeKey entry at
  `registry/wire.yml:319-324`).
- Reuse the generic timeline property keys where they fit: `slotIndex` (`2002`)
  for the target slot, and `timelineKeys` (`2004`, `backingType: bytes`) for the
  packed keyframe payload - both are already generic timeline keys
  (`registry/wire.yml:900-934`).
- New M4 property keys for the deform-specific fields:
  `deformSkin` = `3006` (`backingType: varuint`, a string-table index),
  `deformAttachment` = `3007` (`backingType: varuint`, a string-table index into
  the mesh-attachment name), and `deformVertexCount` = `3008`
  (`backingType: varuint`). The `deformSkin`/`deformAttachment` string-table
  index mechanism is the same one `bones` (key `4014`) and the attachment
  timelines use.
- Add a `deformTimeline` entry to the `objects:` list (`registry/wire.yml:1231+`,
  mirror `slotTimeline` at `1241-1246`) with ordered properties
  `[deformSkin, slotIndex, deformAttachment, deformVertexCount, timelineKeys]`.
- Cite this prompt's owning bead in every new entry's `doc`; use only the M4
  band.

**Packed `timelineKeys` byte layout for deform (pin normatively in the
contract).** The deform keyframe payload is a `bytes` property. Specify it
exactly so prompts 24/26 byte-match: `varuint keyCount`, then per keyframe:
`f32 time`, `varuint offset`, `varuint deltaCount`, `deltaCount * (f32 dx,
f32 dy)`, then the **curve encoding identical to the existing `timelineKeys`
curve tail** used by bone/slot timelines (reuse `writeTimelineKeys`'s curve
serialization, `binary/semantic.nim:787-853`; do not invent a second curve
encoding). Pin the anchor heading so the wire schema `PACKED_BYTES_METADATA`
layout reference points at it.

**Edge cases the contract MUST make normative** (otherwise prompts 24/26
diverge; most already enforced by `validateDeformTimeline*`
`mesh/deform.nim:66-80` and `validateDeformKey` `:53-63`): (a) `skin != "default"`
-> reject; (b) empty `slot`/`attachment`, or `attachment` naming an unknown mesh
on that slot -> reject; (c) `vertexCount <= 0`, or `vertexCount` disagreeing with
the referenced mesh's vertex count -> reject; (d) zero keyframes -> reject;
(e) a keyframe with zero deltas, or `offset + deltas.len > vertexCount` -> reject;
(f) non-strictly-increasing key times, or a negative time -> reject; (g) a deform
timeline on a clip whose slot/attachment pairing does not resolve to a loaded
mesh attachment -> reject. Cross-reference `docs/float-math-contract.md` for the
`1e-4` tolerance and f32 quantization.

Concretely, this prompt builds exactly this - **contract + schema/registry/codegen
only** (no runtime loader):

1. **Contract doc**: create `docs/deform-timeline-contract.md` as a binding
   contract, cross-linked from `docs/README.md` (add a row under a suitable
   section - "Attachment Contracts" or a new "Animation Timeline Contracts"
   heading beside the mesh/clipping rows). Mirror the heading structure of
   `docs/mesh-attachment-contract.md`: Status/owner-bead line;
   cleanroom/provenance paragraph; `## Model`; `## Load-validated invariants`
   with the tolerances tied to `docs/float-math-contract.md`; a normative
   `## Edge cases (normative)` table for (a)-(g); a `## Packed byte layout (.bnb)`
   section with a stable heading anchor referenced from the wire schema; a
   forward-reference `## Deterministic sampling algorithm (implemented in prompt
   24)` section that pins the sampling formula from `sampleDeformDeltas*`
   (`mesh/deform.nim:112-137`: nearest-preceding-key search, stepped
   short-circuit, linear `eased = curve.evaluate(t)` interpolation of expanded
   dense deltas, f32 quantization at the boundary) and the apply order
   (deltas added to skinned vertices via `applyDeformDeltas`, `:140-153`); the
   `skin == "default"` reserved-identity decision; a `## Cross-track mixing`
   section pinning the multi-clip policy - a deform timeline is resolved like an
   **attachment channel** (thresholded / winner-take-by-track-weight, NOT
   weight-blended like scalar channels), so a future multi-clip blend has a
   defined rule and prompt 26's Dart port does not independently guess a weighted
   blend (this is documented-but-unexercised in v1: the m18 rig plays a single
   clip); and `## Related contracts`.

2. **Registry** (`registry/wire.yml`, M4 band only): add the `deformTimeline`
   typeKey (`3002`), the three new property keys (`deformSkin` `3006`,
   `deformAttachment` `3007`, `deformVertexCount` `3008`), and the `deformTimeline`
   `objects:` entry; reuse `slotIndex`/`timelineKeys`; no key collides; all new
   keys in `3000..3999`.

3. **Codegen packed-bytes + canonical JSON + defaults**:
   - Add a `PACKED_BYTES_METADATA` entry (`codegen/generate.py:26-45`) for the
     deform `timelineKeys` usage if a distinct layout anchor is needed, OR reuse
     the existing `timelineKeys` metadata if the generator keys packed layouts by
     property id - decide by reading how `timelineKeys` is currently declared and
     whether a per-record layout override is required; document the choice.
   - Add a `canonical_json_overrides()` entry (`generate.py:571+`) for
     `deformTimeline` producing the readable JSON shape: `skin` (string, const
     `"default"`), `slot` (string), `attachment` (string), and a `keyframes`
     array of `{ "t": number, "offset": integer, "deltas": [ { "x": number,
     "y": number } ], "curve"?: ... }`. (`vertexCount` is derived from the mesh
     at load, not authored - decide whether to serialize it at all in JSON, or
     only in `.bnb`; recommend deriving it in JSON and storing it in `.bnb`.)
   - Add `spec/defaults.yml` entries covering every serialized `deformTimeline`
     property exactly once across `objectDefaults` + `requiredProperties`
     (coverage rule `generate.py:307-315`), each `requiredProperties` entry
     carrying `reason` + `ownerBead` (mirror mesh at `defaults.yml:468-475`).

4. **Codegen regen**: run `python3 codegen/generate.py` to regenerate
   `spec/bony.schema.json`, `spec/bony-wire.schema.json`,
   `runtime-nim/src/bony/generated/wire.nim`, and
   `runtime-dart/lib/src/generated/wire.dart` (do NOT hand-edit these four).
   `python3 codegen/generate.py --check` must pass. Ensure the animation-clip
   JSON `$defs` gains an optional `deformTimelines` array.

5. **Provenance/cleanroom**: add a `docs/PROVENANCE.md` entry recording that the
   deform-timeline schema/field names were taken from `bony`'s own pre-existing
   `mesh/deform.nim` runtime types (not derived from any surveyed product), and
   run the `docs/CLEANROOM.md` new-identifier checklist for the net-new
   serialized names (`deformTimelines`, `deformSkin`, `deformAttachment`,
   `deformVertexCount`).

Keep the record **minimal**: serialized fields are exactly `skin`, `slot`,
`attachment`, (`vertexCount` in `.bnb`), and the keyframe payload. Do NOT wire it
into `AnimationClip`, the mixer, or `buildDrawBatches`; do NOT add a conformance
rig; do NOT touch the Dart runtime beyond the regenerated `generated/wire.dart`.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md (add the deform-timeline naming entry)
- Comparable research: docs/comparable-feature-set.md ("Mesh and deformation" /
  "Animation timelines" are named comparable capabilities only - NOT an
  implementation source; do not import any third party's deform field set, wire
  layout, or naming)
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4 tolerance)
- Existing (non-serialized) Nim deform runtime this milestone wires in:
  runtime-nim/src/bony/mesh/deform.nim (MeshDelta 8-10, DeformKeyframe 12-16,
  DeformTimeline 18-23, deformTimeline ctor 83-95, validateDeformTimeline 66-80,
  sampleDeformDeltas 112-137, applyDeformDeltas 140-153, applyDeformTimeline
  156-166) and its mesh dependency runtime-nim/src/bony/mesh/attachments.nim
  (deformAttachment field) + model.nim (MeshAttachment.deformAttachment 120)
- Freshest end-to-end template (mirror closely): the mesh format/load slice -
  .agents/big-change-prompts/19-contract-mesh-attachment-format.md and its landed
  diff. Diff that as the template for "add a new loadable record end to end."
- Registry key bands: registry/key-ranges.md (M4 = 3000..3999, "...deform
  timelines..."; next-free typeKey 3002, next-free propertyKey 3006)
- Registry source: registry/wire.yml (slotTimeline typeKey 319-324; generic
  timeline property keys slotIndex/slotTimelineKind/timelineKeys 900-934; objects
  boneTimeline/slotTimeline entries 1231-1246; bones packed-bytes key 4014 for
  the string-table index mechanism)
- Codegen: codegen/generate.py (PACKED_BYTES_METADATA 26-45, coverage rule
  307-315, canonical_json_overrides 571+, writes 4 files)
- Defaults source of truth: spec/defaults.yml (mesh objectDefaults +
  requiredProperties as the template)
- Docs index: docs/README.md (add the new contract row)
- Repo gate: Makefile `test` + `python3 codegen/generate.py --check`
- Beads: file under the deform-timeline milestone parent before implementing

**Success Criteria**
- `docs/deform-timeline-contract.md` exists, is listed in `docs/README.md`, and
  normatively specifies the model, the load-validated invariants + tolerances,
  the edge-case table (a)-(g), the packed `.bnb` byte layout (with a heading
  anchor), the forward-referenced sampling formula/order, and the
  `skin == "default"` reserved-identity decision.
- `registry/wire.yml` gains a `deformTimeline` type (key `3002`), `deformSkin`
  (`3006`), `deformAttachment` (`3007`), `deformVertexCount` (`3008`), and a
  `deformTimeline` `objects:` entry reusing `slotIndex`/`timelineKeys`; no key
  collides; all new keys in `3000..3999`.
- `spec/defaults.yml` covers every serialized `deformTimeline` property exactly
  once; `python3 codegen/generate.py --check` passes.
- Codegen regenerated (both schemas + `generated/wire.nim` + `generated/wire.dart`)
  with no hand-edits; the animation-clip JSON `$defs` gains an optional
  `deformTimelines` array whose items express the readable
  skin/slot/attachment/keyframes shape;
  `python3 scripts/ci/schema_validate_assets.py` passes for all existing assets.
- The regenerated `spec/bony.schema.json` `$defs/deformTimeline` and the
  animation-clip `deformTimelines` array express the readable
  skin/slot/attachment/keyframes shape (assert by regenerating and diffing the
  schema). The runtime JSON+`.bnb` **round-trip test** of a clip-carried deform
  timeline, and the load-validation rejections (a)-(g), are **deferred to prompt
  24** - they require the `AnimationClip`/`jsonio`/`semantic` loader wiring this
  prompt intentionally does not touch. Do NOT claim or attempt a runtime
  round-trip test here (there is no loader for the record yet).
- `docs/PROVENANCE.md` gains the deform-timeline naming entry; the
  `docs/CLEANROOM.md` new-identifier checklist is satisfied.
- Update any registry change-detector counts in `runtime-nim/tests/test_smoke.nim`
  (`bonyTypeKeys.len` / `bonyPropertyKeys.len` / `bonyPropertyDefaults.len` /
  `bonyRequiredProperties.len`) to the regenerated totals.
- `make test` passes.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source, importer source, generated definitions,
  exact wire layouts, type/property keys, deform/FFD field names, or copied docs
  prose. The deform-timeline model, field names, and sampling formula are
  project-owned (they already exist in `bony`'s own `mesh/deform.nim`).
- Use `docs/comparable-feature-set.md` only to justify the deform-animation
  capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for
  human/legal review.
- Do NOT build a skin subsystem - use only the reserved `"default"` skin
  identity. A general skin model is a separate milestone.
- Registry edits: use only the M4 band (`3000..3999`) per `registry/key-ranges.md`
  and follow that file's shared-surface reservation rule.
- Land the registry entry, `defaults.yml`, canonical-JSON overrides, schema
  regen, and codegen together - `validate_sources()` fails if they drift apart.
- Do **NOT** wire the timeline into `AnimationClip`/mixer/`buildDrawBatches`,
  add a conformance rig/golden, or touch Dart runtime logic in this prompt. Those
  are prompts 24, 25, and 26. This slice ends when the `deformTimeline` record
  exists in the registry and both schemas, the codegen artifacts are
  regenerated, and the contract doc is written - but no runtime loads, validates,
  or round-trips it yet (that is prompt 24).
- Keep the slice to one meaningful implementation session: the contract doc +
  registry keys + codegen/schema regen + provenance, no runtime code. Natural cut
  line if it runs long: **unit A** = contract doc + registry keys + `objects:`
  entry; **unit B** = codegen (`PACKED_BYTES_METADATA` / `canonical_json_overrides`
  / `defaults.yml`) + the four-file regen with `codegen --check` green +
  provenance. Do not land unit A leaving `codegen --check` red.
