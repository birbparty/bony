# /big-change prompt - contract + format (M4 clipping attachment, Nim load path)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 4** of the M4 clipping-attachment milestone.
> Must land before `16-runtime-nim-clipping-evaluation.md` (runtime eval reads
> the format record and the contract doc this prompt defines). Prompts 17
> (conformance) and 18 (Dart parity) follow.
> **Candidate category:** frontier.

---

/big-change Introduce a first-class, project-owned "clipping attachment" as a loadable, validated, round-trippable `.bony`/`.bnb` format record plus a binding contract document — format and load only, no runtime clipping yet.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony` has a half-built clipping seam. The `DrawBatch` record already carries a
`clipId: string` field (`runtime-nim/src/bony/model.nim:238`,
`runtime-dart/lib/src/model.dart:618`), but it is **hardcoded to `""`** in both
runtimes (`runtime-nim/src/bony/transform.nim:833`,
`runtime-dart/lib/src/transform.dart:1138`) and is only passed through to the
render adapter as a passive label (`naylib_adapter.nim:134,259`, with
`usesStencil` hardcoded `false` at `:261`). Nothing authors a clip region and
nothing reads `clipId` to actually clip geometry. Separately, a convex-polygon
clipper exists (`runtime-nim/src/bony/mesh/clipping.nim`,
`clipTrianglesToConvexPolygon*` at lines 118-122, `validateConvexClip*` at
54-68) but it operates on `SkinnedMeshVertex` triangles and is **not wired** to
`clipId` or to `DrawBatch` quads. Finally, the registry already reserves the M4
band `3000..3999` with scope "Meshes, weights, skins, deform timelines,
**clipping**" (`registry/key-ranges.md:22`, `registry/wire.yml:60-63`), and that
**entire band is currently empty** — no type key or property key in `3000..3999`
is used yet.

This prompt makes clipping a first-class **format record** and writes its
**binding contract**, so a later slice can evaluate it. No evaluation, no
`clipId` population, no geometry clipping in this prompt.

**Project-owned clipping model to define (decide and document these here).**
The concept "clip a range of the draw order against a mask polygon" is a generic
capability category; the specific model below is `bony`-owned and must not be
derived from any third-party runtime's fields, wire layout, or naming:

1. A clipping attachment is a **slot-bound attachment class**, authored exactly
   like a region attachment: a new skeleton-level array
   `clippingAttachments`, whose members a slot references by name through the
   existing `slot.attachment` field. (Today `slot.attachment` is validated
   against region names only — `model.nim:787-788` — so this prompt must widen
   that check to accept clip-attachment names too.)
2. Geometry: a **convex polygon** stored as a flat vertex list
   `vertices: [x0, y0, x1, y1, ...]` (minimum 3 vertices ⇒ 6 numbers), expressed
   in the owning slot's bone-local space. Convexity and non-zero area are load
   validated (reuse the existing `validateConvexClip*` invariants from
   `clipping.nim:54-68`; if reuse forces an awkward dependency, restate the same
   three invariants — ≥3 vertices, non-zero signed area, convex turn direction).
3. Range: an optional `untilSlot` field naming the slot at which clipping stops,
   **inclusive**. Semantics (documented, but NOT executed in this prompt): the
   clip governs every draw batch from the slot *after* the clip's own slot in
   draw order through the `untilSlot` slot inclusive; when `untilSlot` is omitted, to
   the end of the draw order. Overlapping/nested clip ranges are **rejected at
   load** (a clip range may not start while another is active) — a project-owned
   simplifying invariant for v1.
4. The affected draw batches will (in prompt 16, not here) get their `clipId` set
   to the clip attachment's `name`.

**Naming provenance (clean-room).** The field names `clippingAttachments`,
`vertices`, and `untilSlot` are independently chosen project-owned descriptors
(the word "clipping" already appears in `registry/key-ranges.md:22`). Do NOT
adopt any third-party runtime's clip field names. As an explicit deliverable of
this prompt, add a `docs/PROVENANCE.md` entry recording that the clipping
attachment's schema/field names were chosen from generic geometry terminology,
not derived from any surveyed product, and run the `docs/CLEANROOM.md` new-
identifier checklist (line 74) for these names.

**Range edge cases the contract MUST make normative** (otherwise prompts 16/18
will diverge): (a) `untilSlot` naming a slot that is *earlier than or equal to*
the clip's own slot in draw order — **reject at load** as a degenerate/empty
range; (b) a clip in `clippingAttachments` referenced by zero slots — allowed,
inert (clips nothing); (c) two slots referencing the same clip name — decide and
document (recommend: allowed, each is an independent clip instance); (d) a clip
whose own slot is the last slot — empty range, reject at load like (a). Pin the
no-overlap "active" boundary precisely (e.g. a second clip whose slot equals the
first clip's `untilSlot` — is that an overlap? recommend: yes, reject).

Concretely, this prompt builds exactly this — **format/load only**:

1. **Contract doc**: create `docs/clipping-attachment-contract.md` as a binding
   contract, cross-linked from `docs/README.md` (add a row under "Renderer
   Contracts" or a new "Attachment Contracts" section, mirroring how
   `drawbatch-raylib-contract.md` is listed). It must pin: the model above; the
   convex-polygon invariants; the `untilSlot`-inclusive range semantics; the
   no-overlap rule; and a forward reference that the deterministic clip
   *algorithm* (Sutherland–Hodgman convex clip over `DrawBatch` quads, u/v AND
   r/g/b/a interpolation at intersections, fan re-triangulation, f32 quantization
   at the output boundary per `docs/float-math-contract.md`) is specified here
   and implemented in prompt 16. Keep the algorithm section normative so both
   runtimes match within `1e-4`. Two things MUST be pinned normatively because
   prompt 18 must byte-match/behavior-match them in Dart: (i) the packed
   `vertices` **byte layout** — specify exactly, e.g. `varuint pointCount`
   followed by `2 × pointCount` little-endian IEEE-754 `f32` — do NOT leave it to
   "encode deterministically" (note this layout is f32-pairs, structurally
   different from the `ikConstraint.bones` bytes which pack varuint string
   indices; the precedent is the `backingType: bytes` mechanism only); and (ii)
   the **fan-triangulation pivot** (e.g. fan from clipped-polygon vertex 0, as
   `clipTrianglesToConvexPolygon` does), so Dart produces identical index order.
   Note: at a t=0 setup pose region draw batches carry uniform color
   `(1,1,1,1)` (`transform.nim:793-796`) and `SlotData` has no color field, so the
   r/g/b/a interpolation is correct-but-unobservable via a rig; keep it specified
   for correctness, but the conformance golden's non-vacuity rests on geometry +
   u/v (see prompt 17).

2. **Registry** (`registry/wire.yml`, M4 band `3000..3999` only): add a
   `clippingAttachment` **type** key = `3000` (mirror the `region` typeKey entry
   at `wire.yml:223-228`: `id`, `key`, `status: active`, `milestone: M4`,
   `ownerBead`, `doc`). Add M4 **property** keys from `3000+` for the net-new
   fields: `vertices` (a variable-length packed `f32` pair array — use
   `backingType: bytes`, following the `ikConstraint.bones` packed-array
   precedent at `wire.yml` key `4014`) and `untilSlot` (a slot-name string
   reference — use the same `backingType` the existing name/reference string
   properties use; confirm the exact token from an existing string property in
   `wire.yml` before assigning). **Reuse** the existing global `name` property
   key (do not allocate a new one) — physics/transform records reuse shared keys
   the same way. Add a `clippingAttachment` entry to the `objects:` list
   (`wire.yml:1029+`, mirror `region` at `1057-1062`) listing exactly its
   properties (`name`, `vertices`, `untilSlot`). Each new entry cites its owning
   bead in `doc` and uses only the M4 band.

3. **Defaults** (`spec/defaults.yml`, the source of truth): add one
   `objectDefaults` entry for `clippingAttachment` (region's own entry at
   `defaults.yml:167-169` has `properties: {}` — an all-required structural
   template only; the defaulted-value shape you want comes from `slot.attachment`
   at `160-166`); `untilSlot` is the one defaultable property →
   `{value: "", omitWhenDefault: true, applyOnLoad: true}` like `slot.attachment`
   at `160-166`; `name` and `vertices` are required so they carry no default) and
   `requiredProperties` entries for `name` and `vertices` (mirror the region
   `requiredProperties` block at `449-460`, one entry per property with `reason`
   + `ownerBead`). The coverage rule (`generate.py:307-315`) requires every
   registry property of the object to appear **exactly once** across
   `objectDefaults` + `requiredProperties`.

4. **Nim model** (`runtime-nim/src/bony/model.nim`): add a `ClipAttachmentData`
   type (mirror `RegionAttachment` at `72-75` / `PathAttachmentData` at `77-86`)
   with fields `name: string`, `vertices: seq[float64]` (flat x,y pairs), and
   `untilSlot: string`; add a `clippingAttachments: seq[ClipAttachmentData]` field
   to `SkeletonData` (`243-254`, next to `pathAttachments` at `:248`); add a
   `clippingAttachments*` accessor (mirror `pathAttachments*` at `:670`) and
   field accessors (mirror `533-550`); add a `clipAttachmentData*` constructor
   (mirror `regionAttachment*` at `320-325`, quantizing vertices via
   `quantizeF32` per the float-math contract). Thread a `clippingAttachments`
   param through the `skeletonData*` constructor (`953-980`; **append** the new
   param at the end of the parameter list rather than inserting it beside
   `pathAttachments`, so the positional call sites don't rebind — add a
   `result.clippingAttachments = @clippingAttachments` assignment beside
   `result.pathAttachments = @pathAttachments` at `:974`) and through **both**
   `validateSkeletonData*` overloads (raw-fields `726-738`, `SkeletonData`
   delegation `983-988`). Update every positional caller of the constructor —
   `jsonio.nim:672` and `semantic.nim:1570` — to pass the new argument.

5. **Nim load-time validation** (in the raw `validateSkeletonData*` overload,
   near the region block `769-777` and the pathAttachment block `791-806`):
   unique non-empty clip names; each clip's `vertices` has ≥3 points (even
   length ≥6) and satisfies the convex/non-zero-area invariants; `untilSlot`, when
   non-empty, references a known slot name **that is strictly after the clip's own
   slot in draw order** (reject an `untilSlot` at-or-before the clip's own slot,
   and reject a clip whose own slot is the last slot — both are degenerate empty
   ranges per the edge-case rules above); and the no-overlap rule — walking slots
   in draw order, a clip may not begin while another clip's range is still active.
   **Also widen the slot→attachment check** at `787-788`: a
   `slot.attachment` may now name either a region OR a clipping attachment (add
   clip names to the accepted set). This is the single structural coupling
   change — do not let a slot that references a clip name fail as
   `unknownRequiredReference`.

6. **JSON loader** (`runtime-nim/src/bony/jsonio.nim`): add `"clippingAttachments"`
   to the root key allowlist (`:323`); parse the array (mirror regions at
   `410-421` / pathAttachments at `423-440`) into `clipAttachmentData(...)`;
   thread it into the `skeletonData(...)` assembly at `:672`. Add the writer
   branch (mirror regions serialize at `1535-1546` / pathAttachments at
   `1681-1699`) so the record round-trips.

7. **BNB binary loader** (`runtime-nim/src/bony/binary/semantic.nim`): add a
   `clippingAttachmentTypeKey = 3000` constant (mirror `regionTypeKey = 1001` at
   `:18`, `pathAttachmentTypeKey = 4001` at `:20`); add the write branch (mirror
   regions `892-897` / pathAttachments `899-910`); add a `var clips` accumulator
   (beside `1272-1273`) and a decode `of clippingAttachmentTypeKey:` case (mirror
   regions `1374-1380` / pathAttachments `1381-1393`); thread into the
   `skeletonData(...)` assembly at `:1570`. The packed `vertices` bytes must
   encode/decode f32 pairs deterministically per the registry `backingType:
   bytes`.

8. **Codegen regen**: run `python3 codegen/generate.py` to regenerate
   `spec/bony.schema.json`, `spec/bony-wire.schema.json`,
   `runtime-nim/src/bony/generated/wire.nim`, and
   `runtime-dart/lib/src/generated/wire.dart` (do NOT hand-edit any of these
   four — they are generated from `wire.yml` + `defaults.yml`;
   `codegen/generate.py:1289-1292`). `validate_sources()` runs unconditionally
   (`generate.py:200,1287`) and fails if registry/defaults/coverage drift apart,
   so the registry entry, defaults entries, and regen must all land together.

Keep the record **minimal**: fields are exactly `name`, `vertices`, `untilSlot`.
Do NOT add per-vertex weights, clip softness/feather, texture references, mesh
attachments, skins, or a `skinRequired` gate in this slice.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md (clipping is a named
  comparable "visual attachment class" capability only — NOT an implementation
  source; do not import any third party's clip field set, end-slot semantics,
  wire layout, or naming)
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4 tolerance)
- Existing convex clipper (invariants to reuse, math not to duplicate):
  runtime-nim/src/bony/mesh/clipping.nim (validateConvexClip* 54-68)
- Registry key bands: registry/key-ranges.md (M4 = 3000..3999, "clipping"; band
  currently EMPTY — next free type key 3000, next free property key 3000)
- Registry source: registry/wire.yml (region typeKey 1001 at 223-228; region
  width propertyKey shape 482-488; ikConstraint `bones` packed bytes key 4014;
  objects: list region entry 1057-1062)
- Defaults source of truth: spec/defaults.yml (region objectDefaults 167-169;
  slot.attachment default 160-166; region requiredProperties 449-460; coverage
  rule 59-66)
- Codegen: codegen/generate.py (validate_sources 200/1287; coverage 307-315;
  --check mode; writes 4 files 1289-1292)
- Nim model: runtime-nim/src/bony/model.nim (RegionAttachment 72-75,
  PathAttachmentData 77-86, DrawBatch.clipId 238, SkeletonData 243-254,
  regionAttachment* 320-325, accessors 664-670 + 533-550, validate raw overload
  726-738 with region block 769-777 / slot block 779-789 / slot.attachment check
  787-788 / pathAttachment block 791-806, SkeletonData overload 983-988,
  skeletonData* constructor 953-980)
- Nim JSON loader: runtime-nim/src/bony/jsonio.nim (root allowlist 323, regions
  410-421, pathAttachments 423-440, assemble 672, serialize 1535-1546 /
  1681-1699)
- Nim BNB loader: runtime-nim/src/bony/binary/semantic.nim (regionTypeKey 18,
  pathAttachmentTypeKey 20, write 892-910, accumulators 1272-1273, decode
  1374-1393, assemble 1570)
- Docs index: docs/README.md (add the new contract row)
- Analogous freshest record to mirror: the physics-constraint format/load slice
  (bead bony-1pp, prompt 11) and the transform-constraint slice (bead bony-8i1)
  — diff those as the templates for "add a new loadable record end to end"
- Repo gate: Makefile `test` target
- Beads: file under the clipping milestone parent before implementing

**Success Criteria**
- `docs/clipping-attachment-contract.md` exists, is listed in `docs/README.md`,
  and normatively specifies the model, convex invariants, `untilSlot`-inclusive
  range, no-overlap rule, and the (forward-referenced) deterministic clip
  algorithm.
- `registry/wire.yml` gains a `clippingAttachment` type (key `3000`, milestone
  `M4`, owner bead cited), new M4 property keys for `vertices` and `untilSlot`
  (from `3000+`, `name` reused), and an `objects:` entry; no key collides with an
  existing entry; all new keys are in `3000..3999`.
- `spec/defaults.yml` covers every `clippingAttachment` property exactly once
  across objectDefaults + requiredProperties; `python3 codegen/generate.py
  --check` passes.
- Codegen regenerated (both schemas + `generated/wire.nim` + `generated/wire.dart`)
  with no hand-edits; `python3 scripts/ci/schema_validate_assets.py` passes for
  all existing assets.
- `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim` is
  clean; a NEW Nim round-trip unit test loads a clipping attachment from a
  `.bony` JSON fixture AND its `.bnb`, and asserts the parsed
  `ClipAttachmentData` (name, vertices, untilSlot) matches across JSON and binary
  loaders; load-validation tests cover: rejection of a non-convex polygon, a
  `<3`-vertex polygon, an `untilSlot` naming an unknown slot, an `untilSlot`
  at-or-before the clip's own slot in draw order (degenerate range), a clip whose
  own slot is last, and overlapping clip ranges; and acceptance of a slot whose
  `attachment` names a clip.
- `docs/PROVENANCE.md` gains an entry recording the clipping attachment's
  field/type names (`clippingAttachments`, `vertices`, `untilSlot`) as
  independently-chosen generic descriptors, and the `docs/CLEANROOM.md`
  new-identifier checklist is satisfied for them.
- `docs/clipping-attachment-contract.md` normatively pins the packed-`vertices`
  byte layout (count framing + endianness) and the fan-triangulation pivot, and
  states the range edge-case rules (degenerate/backward `untilSlot`, unreferenced
  clip, duplicate slot→clip, no-overlap boundary).
- Update the registry change-detector counts in
  `runtime-nim/tests/test_smoke.nim:102-105` (currently `bonyTypeKeys.len == 26`,
  `bonyPropertyKeys.len == 95`, `bonyPropertyDefaults.len == 53`,
  `bonyRequiredProperties.len == 68`) to the regenerated totals — adding one type
  key and the new property keys WILL break these; set them to the exact values
  the failing assertion prints.
- `make test` passes.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, clip/end-slot field names,
  or copied docs prose. The clipping model, field names, range semantics, and
  algorithm are project-owned.
- Use `docs/comparable-feature-set.md` only to justify the clipping-attachment
  capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for
  human/legal review.
- Registry edits: use only the M4 band (`3000..3999`) per
  `registry/key-ranges.md`, and follow that file's shared-surface reservation
  rule.
- Land the registry entry, `defaults.yml` entries, schema regen, and codegen
  together — `validate_sources()` fails if they drift apart.
- Do **NOT** populate `clipId`, apply any geometric clipping, add a conformance
  rig/golden, or touch the Dart runtime in this prompt. Those are prompts 16, 17,
  and 18. This slice ends when a clipping attachment loads, validates, and
  round-trips through JSON and `.bnb` — but no draw batch is yet clipped.
- Keep the slice to one meaningful implementation session: one new loadable
  attachment record + its contract doc, Nim load path only.
