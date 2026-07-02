# /big-change prompt - contract + format (M4 mesh attachment + skinning, Nim load path)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 4** of the M4 mesh-attachment + skinning
> milestone. Must land before `20-runtime-nim-mesh-skinning-evaluation.md` (the
> runtime eval reads the loaded record and the contract this prompt defines).
> Prompts 21 (conformance) and 22 (Dart parity) follow.
> **Candidate category:** frontier.

---

/big-change Introduce a first-class, project-owned "mesh attachment" (weighted or unweighted, with per-vertex uvs and a triangle list) as a loadable, validated, round-trippable `.bony`/`.bnb` format record plus a binding contract document - format and load only, no draw-batch emission or skinning eval yet.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony` has a fully-built but **entirely non-serialized** mesh runtime. The types
`MeshAttachment`, `MeshVertex`, `MeshUv`, `MeshInfluence`
(`runtime-nim/src/bony/mesh/attachments.nim:10-37`), the linear-blend skinning
solver `skinMeshVertices*` (`runtime-nim/src/bony/mesh/skinning.nim:35-93`), and
the validator `validateMeshAttachment*`
(`runtime-nim/src/bony/mesh/attachments.nim:79`) all exist, but **no loader ever
constructs a mesh**: grep confirms `MeshAttachment`/`"meshAttachments"` appear
nowhere in `jsonio.nim`, `model.nim`, `transform.nim`, or `binary/`. There is no
mesh type key in the registry, no `$defs/meshAttachment` in either schema, no
`meshAttachments` field on `SkeletonData`, and the conformance `m4_rig.bony`
(the "Meshes..." milestone rig) carries **only region attachments** (confirmed:
no `mesh`/`vertices` in the file). Meanwhile the registry M4 band `3000..3999`
is scoped "Meshes, weights, skins, deform timelines, clipping"
(`registry/wire.yml:60-63`); only clipping has been spent from it so far
(typeKey `3000`, propertyKeys `3000`/`3001`).

This prompt makes the mesh attachment a first-class **format record** and writes
its **binding contract**, so the next slice (prompt 20) can skin it into draw
batches. **No draw-batch emission, no `buildDrawBatches` change, no skinning eval
in this prompt** - a mesh loads, validates, and round-trips through JSON and
`.bnb`, and nothing yet draws it.

This milestone is the direct continuation of the region -> path -> clipping
attachment-class progression and the natural next M4 increment. It is de-risked
by the pre-existing project-owned Nim mesh math, which this milestone finally
wires into the serialized format.

**Project-owned mesh model to define (decide and document these here).**
"A textured, triangulated, optionally bone-weighted deformable attachment" is a
generic capability category; the specific record below is `bony`-owned and mirrors
the **already-existing** project types in `mesh/attachments.nim`. It must not be
derived from any third-party runtime's fields, wire layout, or naming.

1. A mesh attachment is a **slot-bound attachment class**, authored like a region
   attachment: a new skeleton-level array `meshAttachments`, whose members a slot
   references by name through the existing `slot.attachment` field. (Today
   `slot.attachment` is validated against region names + clipping-attachment names;
   this prompt must widen that accepted set to also accept mesh-attachment names -
   the single structural coupling change, exactly like clipping widened it.)
2. Geometry mirrors the existing Nim `MeshAttachment`
   (`mesh/attachments.nim:26-37`) - keep the serialized record **minimal** to what
   the runtime needs to skin and draw:
   - `name` (string, reuse the global `name` property key).
   - `weighted` (bool) - mirrors `MeshAttachment.weighted`; selects the vertex
     encoding.
   - `vertices` - the setup geometry. When `weighted == false`, each vertex is a
     bone-local `(x, y)` in the owning slot's bone space
     (`MeshVertex` unweighted form, `attachments.nim:20-24`/`64`). When
     `weighted == true`, each vertex is a list of influences
     `(bone, bindX, bindY, weight)` (`MeshInfluence`, `attachments.nim:14-18`);
     the world position is `sum(weight_i * boneWorld_i * (bindX_i, bindY_i))`, and
     per-vertex weights must sum to 1 within `weightSumTolerance = 1e-4`
     (`attachments.nim:7`, checked at `:128`).
   - `uvs` - one `(u, v)` per vertex (`MeshUv`, `attachments.nim:10-12`);
     `uvs.len == vertices.len` (validated, `attachments.nim:84`).
   - `triangles` - a flat vertex-index list; `len mod 3 == 0`
     (validated, `attachments.nim:89`), every index `< vertexCount`.
   - **Explicitly OUT of scope for v1** (do NOT serialize; they belong to linked
     meshes / deform timelines / sequences, which are later milestones): the
     `MeshAttachment` fields `path`, `hull`, `edges`, `parentMesh`,
     `inheritDeform`, `deformAttachment`. If keeping them on the runtime type is
     convenient, load them to their defaults; do not add registry keys or schema
     for them here.
3. The affected slot will (in prompt 20, not here) get a skinned `DrawBatch`
   emitted from this record.

**Import-cycle / type-home decision (load-bearing - decide this explicitly).**
`mesh/attachments.nim` imports `model` (its validator takes `SkeletonData`), so
`model.nim` cannot import `mesh/*` to reference `MeshAttachment` - that is a
cycle. Resolve it the same way clipping did (the record type `ClipAttachmentData`
lives in `model.nim` while the clip algorithm lives under `mesh/`): **move the
four mesh record type definitions** (`MeshAttachment`, `MeshVertex`, `MeshUv`,
`MeshInfluence`, `attachments.nim:10-37`) **into `runtime-nim/src/bony/model.nim`**
beside `ClipAttachmentData` (`model.nim:88-91`), and update `mesh/attachments.nim`
and `mesh/skinning.nim` to consume them from `model`. Do **not** duplicate the
type. Keep the constructor/validator/skinning **procs** where they are. Verify no
new import cycle results (`nim check` is the gate).

**Naming provenance (clean-room).** The field names `meshAttachments`, `weighted`,
`vertices`, `uvs`, `triangles`, and the influence tuple `(bone, bindX, bindY,
weight)` are the project's own existing runtime identifiers
(`mesh/attachments.nim`), chosen from generic geometry/skinning terminology. Do
NOT adopt any third-party runtime's mesh field names or vertex/weight encoding. As
an explicit deliverable, add a `docs/PROVENANCE.md` entry recording that the mesh
attachment's schema/field names were taken from `bony`'s own pre-existing mesh
runtime types (not derived from any surveyed product), and run the
`docs/CLEANROOM.md` new-identifier checklist for any net-new serialized names.

**Edge cases the contract MUST make normative** (otherwise prompts 20/22 will
diverge): (a) `uvs.len != vertices.len` -> reject at load; (b)
`triangles.len mod 3 != 0`, or any index `>= vertexCount` -> reject at load;
(c) a weighted vertex whose influence weights do not sum to 1 within `1e-4`, or
with zero influences -> reject at load; (d) a weighted influence naming an unknown
bone -> reject at load; (e) an empty mesh (zero vertices or zero triangles) -
decide and document (recommend: reject, a mesh must have >= 1 triangle);
(f) a mesh in `meshAttachments` referenced by zero slots - allowed, inert;
(g) `weighted == false` with a non-empty `influences` payload, or `weighted ==
true` with unweighted `(x,y)` payload - reject as a malformed encoding.

Concretely, this prompt builds exactly this - **format/load only**:

1. **Contract doc**: create `docs/mesh-attachment-contract.md` as a binding
   contract, cross-linked from `docs/README.md` under the existing "Attachment
   Contracts" section (beside `clipping-attachment-contract.md`). Mirror the
   heading structure of `docs/clipping-attachment-contract.md` (Status/owner-bead
   line; cleanroom/provenance paragraph; `## Model`; `## Load-validated
   invariants` with the tolerances above tied to `docs/float-math-contract.md`;
   a normative `## Edge cases (normative)` markdown table for (a)-(g); a
   `## Packed byte layout (.bnb)` section; a forward-reference
   `## Deterministic skinning algorithm (implemented in prompt 20)` section; and
   `## Related contracts`). Two things MUST be pinned normatively because prompt
   22 must byte/behavior-match them in Dart:
   (i) the **packed `.bnb` byte layouts** for each `bytes` property, specified
   exactly (see step 2), with a stable heading anchor referenced from the wire
   schema; and (ii) the **skinning formula and evaluation order** (linear blend:
   `worldPos = sum_i weight_i * (boneWorld_i * (bindX_i, bindY_i))`, influences
   accumulated in stored order, f32 quantization at the output boundary per
   `docs/float-math-contract.md`), matching `skinMeshVertices`
   (`skinning.nim:55-69`), so both runtimes agree within `1e-4`. Also pin, for
   prompts 20/22, (iii) the **mesh `DrawBatch` metadata defaults** the golden
   compares exactly - `texturePage` and `blendMode` come from the slot/defaults,
   not the mesh record (the v1 record has neither), so state the exact values a
   mesh batch carries (recommend `texturePage = ""` and the slot's blend mode,
   identical to what the region path derives for the same slot); and (iv) the
   **v1 non-goal that mesh attachments are not clipped** (only region batches are
   clipped in v1 - see prompt 20 for why the current convex-boundary clipper would
   destroy a mesh's triangle topology).

2. **Registry** (`registry/wire.yml`, M4 band `3000..3999` only; next-free typeKey
   `3001`, next-free propertyKey `3002`): add a `meshAttachment` **type** key =
   `3001` (mirror the `clippingAttachment` typeKey at `wire.yml:229-234`). Add M4
   **property** keys (mirror the `clippingAttachment` property block at
   `wire.yml:502-515`):
   - `meshWeighted` = `3002`, `backingType: bool`.
   - `meshVertices` = `3003`, `backingType: bytes` - packed setup geometry. Pin
     the layout normatively in the contract: `varuint vertexCount`, then, when
     unweighted, `vertexCount * (f32 x, f32 y)`; when weighted, per vertex
     `varuint influenceCount` then `influenceCount * (varuint boneStringIndex,
     f32 bindX, f32 bindY, f32 weight)`. The `boneStringIndex` is a string-table
     index (same mechanism as the `bones` key `4014`, `wire.yml:614-620`).
   - `meshUvs` = `3004`, `backingType: bytes` - `varuint count` then
     `count * (f32 u, f32 v)` (structurally like `warpControlPoints` key `6026`).
   - `meshTriangles` = `3005`, `backingType: bytes` - `varuint count` then
     `count * (varuint vertexIndex)`.
   **Reuse** the global `name` property key (do not allocate a new one). Add a
   `meshAttachment` entry to the `objects:` list (`wire.yml:1049+`, mirror
   `clippingAttachment` at `1083-1088`) with ordered properties
   `[name, meshWeighted, meshVertices, meshUvs, meshTriangles]`. Cite this
   prompt's owning bead in every new entry's `doc`; use only the M4 band.

3. **Codegen packed-bytes + defaults**:
   - Add `PACKED_BYTES_METADATA` entries (`codegen/generate.py:26-45`, mirror the
     `vertices` entry at `39-44`) for `meshVertices`, `meshUvs`, and
     `meshTriangles`, each with a `layout` anchor pointing into
     `docs/mesh-attachment-contract.md#<packed-...>` (the anchor strings MUST match
     the contract headings). This produces the `x-bony-packedBytes` wire-schema
     blocks.
   - Decide the **canonical JSON shape** via `canonical_json_overrides()`
     (`generate.py:571+`). Note this override **replaces the whole `$defs`
     object** for the type (as the `clippingAttachment` override supplies
     `name`/`vertices`/`untilSlot` together), so you hand-author the entire
     `meshAttachment` canonical schema - `name`, `weighted`, and the three packed
     fields - not just the three. The pipeline already emits complex nested
     shapes here (e.g. `warpLattice.controlPoints` array-of-`$ref`), so a
     structured/`oneOf` vertex array is fully supported. Recommended, readable, and
     1:1 with the Nim types: `uvs` -> numeric array (`minItems 2`, even length);
     `triangles` -> integer array (`minItems 3`, length `mod 3 == 0`);
     `vertices` -> an **array of vertex objects** whose items are
     `{ "oneOf": [ {unweighted}, {weighted} ] }` - an unweighted vertex
     `{ "x": number, "y": number }`; a weighted vertex `{ "influences": [ { "bone":
     string, "bindX": number, "bindY": number, "weight": number } ] }`. The schema
     types **both** vertex shapes; the loader trusts the top-level `weighted` flag
     to pick which one every vertex must be. This is materially more involved than
     clipping's single numeric-array override - budget for it.
   - **Naming note (do not trip on this):** the canonical JSON field names are the
     readable `weighted`/`vertices`/`uvs`/`triangles`, but the **registry property
     ids** are `meshWeighted`/`meshVertices`/`meshUvs`/`meshTriangles` (the plain
     `vertices` id is already taken by clipping - reusing it hits the duplicate-key
     error at `generate.py:253`). The `canonical_json_overrides` entry fully
     replaces the `$defs`, so this divergence is fine, but the hand-written JSON
     loaders must map each JSON field to its property key (`vertices` -> `3003`,
     etc.) rather than assuming field-name == property-id (clipping's 1:1 pattern
     does not hold here).
   - Add `spec/defaults.yml` entries (clipping's are at `defaults.yml:170-176`
     objectDefaults / `468-475` requiredProperties): one `objectDefaults` entry for
     `meshAttachment` with `meshWeighted` -> `{value: false, omitWhenDefault: true,
     applyOnLoad: true}`; `requiredProperties` entries for `name`, `meshVertices`,
     `meshUvs`, `meshTriangles`, **each carrying a `reason` and `ownerBead`**
     (mirror clipping at `defaults.yml:468-475`; `generate_nim`/`generate_dart`
     read `entry["reason"]` with no fallback - omitting it raises `KeyError`). The
     coverage rule (`generate.py:307-315`) requires every registry property to
     appear **exactly once** across `objectDefaults` + `requiredProperties`
     (here: defaulted `{meshWeighted}` + required `{name, meshVertices, meshUvs,
     meshTriangles}` = all five, disjoint - satisfied).

4. **Nim model** (`runtime-nim/src/bony/model.nim`): after the import-cycle move
   above (mesh record types now live here), add a
   `meshAttachments: seq[MeshAttachment]` field to `SkeletonData` (`248-260`, next
   to `clippingAttachments` at `:254`), a `meshAttachments*` accessor (mirror
   `clippingAttachments*` at `:694`), and thread a `meshAttachments` param through
   the `skeletonData*` constructor (`params 754-762`, assignment `1080-1082`;
   **append** the new param at the end so positional call sites don't rebind) and
   through the `skeletonData` overload (`1063-1074`, round-trip getter list
   `1093-1095`) and **both** `validateSkeletonData*` paths. Update every positional
   caller of the constructor to pass the new argument.

5. **Nim load-time validation**: the existing `validateMeshAttachment*`
   (`mesh/attachments.nim:79`, invariants at `82-131`) **already enforces most of
   the edge-case table** - `uvs.len == vertices.len` (`:84`), `triangles.len mod 3
   == 0` (`:89`), every triangle index `< vertexCount` (`:104-106`), weighted
   influences name known bones (`:125-126`), the `weighted`/payload-shape
   consistency rule (g) (`:110-131`), the weight-sum tolerance (`:128-129`), and
   the empty-mesh rule (e) (`:82`/`:89`). Note the `meshAttachment(data, ...)`
   constructor (`attachments.nim:134-161`) **calls `validateMeshAttachment`
   internally at `:161`**, so simply constructing a mesh runs these checks. The
   only genuinely **net-new** checks to add in the `SkeletonData` path are:
   cross-collection **unique non-empty mesh names**, and **widening the
   slot->attachment accepted-name set** (currently region names + clipping names)
   to include mesh-attachment names so a slot referencing a mesh does not fail as
   an unknown reference. The slot-widening is the single structural coupling
   change. (Do not re-implement the checks the validator already does.)

6. **JSON loader** (`runtime-nim/src/bony/jsonio.nim`): add `"meshAttachments"` to
   the root key allowlist (`:324`); parse the array into the mesh record via the
   existing `meshAttachment(...)` constructor (`attachments.nim:134-161`); thread it
   into the `skeletonData(...)` assembly. Add the writer branch (mirror clipping's
   serialize path) so the record round-trips JSON->JSON.
   **Loader-ordering caveat (do not miss this):** unlike clipping's data-free
   `clipAttachmentData(...)`, the mesh constructor takes a `SkeletonData` and
   validates against it immediately (`attachments.nim:161`), which for a **weighted**
   mesh resolves influence bone names against `data.bones`
   (`attachments.nim:125-126`). So meshes must be constructed **after bones are
   parsed/assembled**, not in the naive "mirror the clipping block" order where
   attachments are built before the skeleton exists. Either build meshes against a
   `SkeletonData` (or bone table) that already holds the bones, or defer mesh
   construction/validation until after bone assembly. Pin the chosen ordering; the
   weighted round-trip test will catch a wrong order.

7. **BNB binary loader** (`runtime-nim/src/bony/binary/semantic.nim`): add a
   `meshAttachmentTypeKey = 3001` constant (mirror `clippingAttachmentTypeKey =
   3000` at `:19`); add the write branch (mirror clipping encode at `943-948`) and
   a `var meshes` accumulator + a decode `of meshAttachmentTypeKey:` case (mirror
   clipping decode at `1433-1441`) in the `case record.typeKey` dispatch; thread
   into the `skeletonData(...)` assembly. The three packed `bytes` payloads must
   encode/decode exactly per the contract's byte layout, including the
   string-table indices for weighted influence bone names (same string-table
   mechanism the `bones` key uses).

8. **Codegen regen**: run `python3 codegen/generate.py` to regenerate
   `spec/bony.schema.json`, `spec/bony-wire.schema.json`,
   `runtime-nim/src/bony/generated/wire.nim`, and
   `runtime-dart/lib/src/generated/wire.dart` (do NOT hand-edit these four - they
   are generated). Note the top-level collection auto-names to `meshAttachments`
   (object id + "s"); do **not** add a `root_collection_overrides` entry - keep the
   name `meshAttachments`, consistent with `clippingAttachments`/`pathAttachments`.
   `python3 codegen/generate.py --check` must pass.

Keep the record **minimal**: serialized fields are exactly `name`, `weighted`,
`vertices`, `uvs`, `triangles`. Do NOT add deform timelines, linked/parent meshes,
sequences, edges/hull, per-vertex color, or a `skinRequired` gate in this slice.
Do NOT emit or clip any draw batch, and do NOT touch the Dart runtime here.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md (add the mesh naming entry)
- Comparable research: docs/comparable-feature-set.md (mesh/deformation is a named
  comparable "Mesh and deformation" capability only - NOT an implementation
  source; do not import any third party's mesh field set, weight encoding, wire
  layout, or naming)
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4 tolerance)
- Existing (non-serialized) Nim mesh runtime this milestone wires in:
  runtime-nim/src/bony/mesh/attachments.nim (MeshAttachment 26-37, MeshVertex
  20-24, MeshUv 10-12, MeshInfluence 14-18, meshAttachment ctor 134-161,
  validateMeshAttachment 79, weightSumTolerance 7), and
  runtime-nim/src/bony/mesh/skinning.nim (skinMeshVertices 35-93, formula 55-69)
- Freshest end-to-end template (mirror closely): the clipping format/load slice -
  prompt .agents/big-change-prompts/15-contract-clipping-attachment-format.md, and
  its landed diff (bead bony-jkt). Diff that as the template for "add a new
  loadable attachment record end to end."
- Registry key bands: registry/key-ranges.md (M4 = 3000..3999, "Meshes, weights,
  skins, ..."; next-free typeKey 3001, next-free propertyKey 3002)
- Registry source: registry/wire.yml (clippingAttachment typeKey 229-234; clipping
  property block 502-515; bones packed-bytes key 4014 at 614-620; warpControlPoints
  packed pairs 6026 at 789-795; objects clippingAttachment entry 1083-1088)
- Defaults source of truth: spec/defaults.yml (clipping objectDefaults 170-176,
  requiredProperties 468-475; coverage rule)
- Codegen: codegen/generate.py (PACKED_BYTES_METADATA 26-45, validate_sources /
  coverage 307-315, canonical_json_overrides 571+, wire schema 505-568,
  root_collection_overrides 480-483, writes 4 files 1285-1292)
- Nim model: runtime-nim/src/bony/model.nim (ClipAttachmentData 88-91,
  SkeletonData collections 248-260, clippingAttachments accessor 694, skeletonData
  ctor params 754-762 + assign 1080-1082, overload 1063-1074, round-trip getters
  1093-1095)
- Nim JSON loader: runtime-nim/src/bony/jsonio.nim (root allowlist 324, clipping
  load 443-463)
- Nim BNB loader: runtime-nim/src/bony/binary/semantic.nim (type-key constants
  18-21, clipping encode 943-948, decode dispatch case 1413-1457 with clipping
  case 1433-1441)
- Docs index: docs/README.md (Attachment Contracts section - add the new row)
- Repo gate: Makefile `test` + `python3 codegen/generate.py --check`
- Beads: file under the mesh-attachment milestone parent before implementing

**Success Criteria**
- `docs/mesh-attachment-contract.md` exists, is listed in `docs/README.md`, and
  normatively specifies the model, the load-validated invariants + tolerances, the
  edge-case table (a)-(g), the packed `.bnb` byte layouts (with heading anchors),
  and the forward-referenced skinning formula/order.
- `registry/wire.yml` gains a `meshAttachment` type (key `3001`), `meshWeighted`
  (`3002`, bool), `meshVertices` (`3003`, bytes), `meshUvs` (`3004`, bytes),
  `meshTriangles` (`3005`, bytes), and an `objects:` entry; `name` is reused; no
  key collides; all new keys are in `3000..3999`.
- `spec/defaults.yml` covers every `meshAttachment` property exactly once across
  objectDefaults + requiredProperties; `python3 codegen/generate.py --check`
  passes.
- Codegen regenerated (both schemas + `generated/wire.nim` + `generated/wire.dart`)
  with no hand-edits; the canonical JSON `$defs/meshAttachment` expresses the
  structured vertex/uv/triangle shape; `python3 scripts/ci/schema_validate_assets.py`
  passes for all existing assets.
- The four mesh record types live in `model.nim` (moved from `mesh/attachments.nim`
  with no duplication and no new import cycle); `SkeletonData` gains
  `meshAttachments`; `nim check --hints:off --path:runtime-nim/src
  runtime-nim/src/bony.nim` is clean.
- A NEW Nim round-trip unit test loads BOTH an unweighted and a weighted mesh from
  a `.bony` JSON fixture AND its `.bnb`, and asserts the parsed mesh (name,
  weighted, vertices incl. influences, uvs, triangles) matches across JSON and
  binary loaders. Load-validation tests cover rejections for: mismatched
  `uvs`/`vertices` length; `triangles.len mod 3 != 0`; an out-of-range triangle
  index; a weighted vertex whose weights do not sum to 1; a weighted influence
  naming an unknown bone; an empty mesh; a `weighted`/payload-shape mismatch; and
  acceptance of a slot whose `attachment` names a mesh.
- `docs/PROVENANCE.md` gains the mesh-naming entry; the `docs/CLEANROOM.md`
  new-identifier checklist is satisfied for the net-new serialized names.
- Update any registry change-detector counts in `runtime-nim/tests/test_smoke.nim`
  (the `bonyTypeKeys.len` / `bonyPropertyKeys.len` / `bonyPropertyDefaults.len` /
  `bonyRequiredProperties.len` assertions) to the regenerated totals - adding one
  type key and four property keys WILL break these; set them to the exact values
  the failing assertion prints.
- `make test` passes.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source, importer source, generated definitions,
  exact wire layouts, type/property keys, mesh/weight field names, or copied docs
  prose. The mesh model, field names, weight encoding, and skinning formula are
  project-owned (they already exist in `bony`'s own `mesh/` runtime).
- Use `docs/comparable-feature-set.md` only to justify the mesh capability
  category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for
  human/legal review.
- Registry edits: use only the M4 band (`3000..3999`) per `registry/key-ranges.md`,
  and follow that file's shared-surface reservation rule.
- Land the registry entry, `defaults.yml` entries, `PACKED_BYTES_METADATA`,
  canonical-JSON overrides, schema regen, and codegen together -
  `validate_sources()` fails if they drift apart.
- Do **NOT** emit a draw batch, change `buildDrawBatches`, apply skinning, add a
  conformance rig/golden, or touch the Dart runtime in this prompt. Those are
  prompts 20, 21, and 22. This slice ends when a mesh attachment loads, validates,
  and round-trips through JSON and `.bnb` - but nothing draws it yet.
- Keep the slice to one meaningful implementation session: one new loadable
  attachment record + its contract doc + the model-type relocation, Nim load path
  only. This is the heaviest of the four slices (type relocation + 5 registry keys
  + structured-object canonical JSON + defaults + JSON/BNB read+write incl. the
  weighted string-table encoding + validation widening + contract + tests). If the
  session runs long, the natural cut line is: **unit A** = contract doc + registry
  + `PACKED_BYTES_METADATA` + `canonical_json_overrides` + `defaults.yml` + schema
  regen (all four generated files) landing together with `--check` green; **unit
  B** = the Nim model relocation + JSON/BNB loaders + validation widening + tests.
  Do not land unit A without unit B in a way that leaves `make test` red.
