# M4 Mesh Slice — Seam Grounding Confirmation

**Bead:** `bony-lzj.1.1` (Analysis) · **Epic:** `bony-lzj` (M4 mesh attachment + weighted skinning)
**Purpose:** Confirm the clipping-attachment slice (`bony-jkt`) seams that the mesh
slice mirrors, so every downstream bead is grounded against real source. No code.

All anchors in the bead description were verified against the current tree
(branch `ralph/iteration-172`). Result: **all seams exist and are usable**; three
line-number corrections and one clarification are recorded below so downstream
beads cite accurate anchors.

## Verified anchors (CONFIRMED as-cited)

### `registry/wire.yml`
- `clippingAttachment` typeKey block @ **229-234**, `key: 3000` @ 230.
- Clipping props @ **502-515**: `vertices` `key: 3000` (backingType `bytes`), `untilSlot` `key: 3001` (backingType `string`).
- `bones` packed key `4014` @ **614-615**.
- `clippingAttachment` objects entry @ **1083-1088**.

### `registry/key-ranges.md`
- M4 band `3000..3999` — table row @ 22.

### `codegen/generate.py`
- `PACKED_BYTES_METADATA` starts @ 26; `vertices` entry @ **39-44** (this is the ONLY entry — see correction #3).
- Coverage (`covered`/`overlap`) check @ **313-318** (preceded by requiredProperties validation @ 305-311).
- `canonical_json_overrides()` @ **571**.
- `root_collection_overrides` @ **480-483**.

### `spec/defaults.yml`
- Clipping `objectDefaults` @ **170-176**.
- `requiredProperties` clipping entries (name + vertices) @ **468-475**.

### `runtime-nim/src/bony/model.nim`
- `ClipAttachmentData` @ **88-91**; `SkeletonData.clippingAttachments` field @ **254**.
- Getters @ **569-571**; `clippingAttachments*(data)` accessor @ **694**.
- Single positional `skeletonData*` ctor @ **1059-1088** (clip param @ 1071, assign @ 1082).
- `validateSkeletonData*(openArray...)` @ **750** (clip param `= []` @ 762); `SkeletonData` wrapper @ **1091**.
- Clip name/edge checks inlined @ **805-815** (slot→attachment accept vs allRegionNames/allClipNames @ 853-854).

### `runtime-nim/src/bony/mesh/attachments.nim`
- Const @ 7, mesh `type` block (MeshUv..MeshAttachment) @ **9-37**.
- `meshAttachment` ctor @ **134-161** (calls `validateMeshAttachment` @ 161).
- `validateMeshAttachment*` @ **79**.

### `runtime-nim/src/bony/mesh/skinning.nim`
- `skinMeshVertices*` @ **35-93** (weighted-blend core @ 61-65, unweighted branch @ 66-69).

### `runtime-nim/src/bony/jsonio.nim`
- Root allowlist (`validateKnownKeys`) @ **324**.
- Clip load logic @ **443-463**.
- `skeletonData(...)` assembly @ **695**.

### `runtime-nim/src/bony/binary/semantic.nim`
- `clippingAttachmentTypeKey = 3000'u64` @ **19**.
- Clip encode loop @ **943-948**.
- `of clippingAttachmentTypeKey:` decode case @ **1433-1441**.
- `skeletonData(...)` assembly @ **1618**.

### `runtime-nim/tests/test_smoke.nim`
- Key counts @ **102-105**: `bonyTypeKeys=27`, `bonyPropertyKeys=97`, `bonyPropertyDefaults=54`, `bonyRequiredProperties=70`.

## Corrections / clarifications for downstream beads

1. **Next-free keys are a derivation, not literal text.** `registry/key-ranges.md`
   contains no "next-free" notation. The M4 band `3000..3999` is authoritative;
   the next-free values are derived from current wire.yml allocations:
   highest M4 typeKey in use = 3000 (clipping) → **next-free typeKey 3001**;
   highest M4 propertyKey in use = 3001 (clipping `untilSlot`) → **next-free propertyKey 3002**.
   **Mesh-slice allocation** (per `bony-lzj.1.3` = "typeKey 3001 + 4 props"): one new
   typeKey (**3001**) plus four new property keys (**3002-3005**), of which **three are
   `bytes`-backed** (`meshVertices`, `meshUvs`, `meshTriangles` per the contract plan's
   three packed-byte sections) and one is non-`bytes`. After this slice the next-free
   values become **typeKey 3002, propertyKey 3006**. The registry bead allocates from
   these and cites its own bead.

2. **`codegen/generate.py` dup-key error line drifted:** duplicate `propertyKey`
   error is @ **254** (duplicate `typeKey` @ 234), not 253.

3. **Packed-byte metadata is per-property AND doc-slug-coupled — three entries needed
   (trickiest seam in the slice).** `schema_for_property` (`generate.py` @ **912-913**)
   emits `x-bony-packedBytes` **only** for `bytes` props that have a
   `PACKED_BYTES_METADATA` entry. Clipping has exactly **one** entry (`vertices` @ 39-44).
   The mesh slice's **three** `bytes` props each need their own metadata entry (bead
   `bony-lzj.1.5`), and each entry's `layout` value is a `docs/<file>.md#<heading-slug>`
   reference whose slug must match a real heading in `docs/mesh-attachment-contract.md`
   **verbatim** (GitHub-slugified) — a mismatch fails `python3 codegen/generate.py --check`.
   This couples the contract-doc bead (`bony-lzj.1.2`, which must pin three sibling
   packed-byte headings) to the metadata bead (`bony-lzj.1.5`); allocate the three
   headings and three metadata entries in lockstep.

4. **Write-block anchor is correct as-cited — no correction.** The four `write_or_check`
   calls in `codegen/generate.py` are at **1305-1308**, exactly as the bead cited
   (1303 = `validate_sources`, 1304 = `changed` init). Do not shift them. *(An earlier
   draft of this note wrongly "corrected" these to 1303-1306; that draft was wrong.)*

5. **`skinMeshVertices` formula lines:** weighted-blend core is @ **61-65**, unweighted
   branch @ **66-69** (bead description said 55-69). Overloads run to 93 as stated.

6. **Positional-caller counts are approximate:** `skeletonData(` appears **46×** in
   `test_smoke.nim` (desc "~50") and **63×** repo-wide (desc "~60"). The single-ctor
   fan-out to update when the mesh param is added is real; use the live counts.

## Conclusion

Every seam the mesh slice mirrors exists and is grounded. Downstream beads
(`bony-lzj.1.2` contract doc, `.1.3` registry keys, `.1.5` packed-byte metadata,
`.1.7` model relocation, and the JSON/BNB round-trip beads) can proceed against these
anchors, applying the six corrections above. The doc↔codegen slug coupling in
correction #3 is the seam most likely to break `--check`, so beads `.1.2` and `.1.5`
must land consistent heading slugs.
