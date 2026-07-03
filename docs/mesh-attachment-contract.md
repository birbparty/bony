# Mesh Attachment Contract

Status: **binding**. Owner bead: `bony-lzj.1` (M4 mesh-attachment milestone).

This contract defines the `bony`-owned **mesh attachment**: a slot-bound
deformable triangle mesh with per-vertex texture coordinates and either flat
bone-local vertex positions or per-vertex weighted bone influences (skinning).
This slice specifies the format and the load-time validation, and — normatively,
for a later slice to implement — the deterministic linear-blend skinning
algorithm. The record was made loadable and validated in prompt 19; prompt 20
wired `skinMeshVertices` into `buildDrawBatches`, so a mesh-referencing slot now
emits a skinned `DrawBatch` (see "DrawBatch metadata defaults" below). Mesh
geometry is still **never clipped** in v1 (see "Clipping a mesh attachment is a v1
non-goal").

The mesh model, field names, packed byte layouts, and skinning algorithm are
**project-owned** and were chosen from generic geometry/skinning terminology, not
derived from any third-party runtime (see `docs/PROVENANCE.md` and
`docs/CLEANROOM.md`).

## Model

A mesh attachment is a **slot-bound attachment class**, authored alongside region
and clipping attachments:

- A skeleton-level array `meshAttachments` holds the mesh records.
- A slot references a mesh **by name** through the existing `slot.attachment`
  field — the same field that references region and clipping attachments.
- A mesh record's canonical-JSON form has exactly these fields:
  - `name` (string, required) — stable unique identifier referenced by
    `slot.attachment`.
  - `weighted` (bool, optional, default `false`, omitted when default) — whether
    vertices carry per-vertex bone influences (skinning) rather than flat
    bone-local positions.
  - `vertices` (required) — an array of vertex objects, one per mesh vertex.
    Each vertex is **either** unweighted `{ "x": <number>, "y": <number> }`
    (bone-local position in the owning slot's bone space) **or** weighted
    `{ "influences": [ { "bone": <name>, "bindX": <number>, "bindY": <number>,
    "weight": <number> }, ... ] }`. Every vertex's shape must agree with the
    mesh's `weighted` flag.
  - `uvs` (required) — texture coordinates as a flat list
    `[u0, v0, u1, v1, ...]`; length is even and equals `2 × vertexCount`.
  - `triangles` (required) — a flat list of vertex indices; length is a positive
    multiple of `3`, each triple naming one triangle.

No softness/feather, skins, `skinRequired` gate, linked-mesh parents, or deform
timelines are settable in v1. (`hull`, `edges`, `parentMesh`, `inheritDeform`,
and `deformAttachment` exist on the in-memory record as reserved fields defaulted
to empty/inert; they are not part of the v1 serialized form and linked-mesh
parents are rejected at load.)

### DrawBatch metadata defaults

Prompt 20 (`buildDrawBatches`, `runtime-nim/src/bony/transform.nim`) now emits
**one `DrawBatch` per mesh-referencing slot**, in that slot's draw-order position.
Its metadata fields are pinned to the **same deterministic values the region path
derives for the same slot**, so a region and a mesh on the same slot are
indistinguishable in those fields — a Dart port (prompt 22) must reproduce them
byte-for-byte:

- `texturePage = ""` — the v1 mesh record carries no texture page; matches the
  region path's literal `""`.
- `blendMode = "normal"` — the v1 mesh record carries no blend mode; matches the
  region path's literal `"normal"` (the current setup-pose surface). When a future
  slice threads a real slot blend mode, region and mesh batches must continue to
  share it.
- `clipId = ""` at emit, and it **stays** empty: meshes are not clipped in v1 (see
  below).
- `bone = slot.bone`, `attachment = <mesh name>`, and `world = worlds[slot.bone]`
  exactly as the region path sets them.

Per-vertex color is uniform `r=g=b=a=1` (the v1 mesh record has no per-vertex
color); the seam does **not** read a slot color. Vertex positions are the
world-space output of `skinMeshVertices(data, worlds, slot.bone, mesh)` (already
`f32`-quantized in the solver); `indices` are the mesh `triangles` verbatim; `u,v`
are the mesh `uvs`.

### Clipping a mesh attachment is a v1 non-goal

Only **region** batches are clipped. `buildDrawBatches`'s clip pass **skips any
batch whose attachment names a mesh**, leaving its `clipId == ""` and its full
triangle set untouched, even when the mesh slot falls inside a clip's covered
range. Rationale: `clipDrawBatchPolygon`
(`runtime-nim/src/bony/mesh/drawbatch_clipping.nim`) treats a batch's `vertices`
as a **single convex polygon in boundary order** and fan-triangulates from vertex
0, ignoring the batch's `indices`. A skinned mesh is a triangle *soup* with an
explicit triangle list and shared/interior vertices, so routing it through that
path would reinterpret its vertex list as one convex ring and destroy its
topology. Correct per-triangle mesh clipping is a deliberate follow-on milestone
(tracked as a follow-up bead), not part of v1.

### Deforming a mesh attachment (normative)

Warp and rotation deformers **do** apply to mesh batches, identically to region
batches. Deformers act on the **resolved draw-batch vertex positions** — i.e.
**after** skinning (`skinMeshVertices`) for a mesh, and after the region-quad
build for a region — over **every** base batch, not just region quads. Both
runtimes apply the same operation, at different layers:

- **Dart**: inside the runtime `buildDrawBatches`
  (`runtime-dart/lib/src/transform.dart`), which maps every base batch through
  `applyDeformers`.
- **Nim**: in the golden/render layer via `applyDeformersToDrawBatches`
  (`cli/bony_cli.nim`), which iterates every batch. The Nim runtime library
  `buildDrawBatches` (`runtime-nim/src/bony/transform.nim`) itself returns
  **undeformed** batches for meshes *and* regions alike — deformer application is
  a golden/render-layer concern in Nim, applied uniformly to both attachment
  kinds, so the two runtimes agree on the deformed output the goldens encode.

`applyDeformers` is **vertex-count-agnostic**: it iterates the batch's vertices
regardless of count and makes **no region-quad (4-vertex) assumption**, so an
arbitrary mesh vertex count is handled without crashing. Per the deformer model:

- A **warp** deformer self-scopes via its setup bounds — a mesh vertex whose
  setup-pose `(x, y)` falls outside the lattice's `[minX, maxX] × [minY, maxY]`
  box (i.e. normalized `u` or `v` outside `0..1`) is left **unchanged**.
- A **rotation** deformer applies **unconditionally** to every vertex.

In both cases `u`/`v` texcoords, vertex color, and the batch's `indices` are
**preserved**; only the vertex `x`/`y` positions change. Two fixtures pin this,
each a **5-vertex** (deliberately non-quad) weighted mesh whose committed golden
proves Nim and Dart produce the same deformed positions within the `1e-4`
tolerance:

- `conformance/assets/m13_mesh_deform_rig` — a **rotation** deformer (applies to
  every vertex); golden `conformance/goldens/m13_mesh_deform_rig_t0.json`.
- `conformance/assets/m14_mesh_warp_rig` — a **warp** deformer whose lattice box
  covers only two of the five mesh vertices, proving self-scoping: the two
  in-bounds vertices are warped while the three out-of-bounds vertices are left
  unchanged; golden `conformance/goldens/m14_mesh_warp_rig_t0.json`.

Deform **timelines** (animating deformer control points over time) and
`inheritDeform` remain v1 non-goals (reserved-but-inert); only static, default-
parameter deformer evaluation is pinned here.

## Load-validated invariants

A mesh is rejected at load unless all hold (these restate `validateMeshAttachment`
in `runtime-nim/src/bony/model.nim`, the single shared impl used by both the load
path and the `meshAttachment` constructor):

1. **Named** — `name` is non-empty.
2. **At least one vertex** — `vertices.len ≥ 1`.
3. **UV/vertex agreement** — `uvs.len == vertices.len` (one `MeshUv` per vertex).
4. **UV range** — every `u` and `v`, after `f32` quantization, is in `0..1`
   inclusive (`quantizeUnit`); an out-of-range coordinate is rejected.
5. **Triangle triplets** — `triangles.len` is non-zero and a multiple of `3`.
6. **In-range indices** — every triangle (and reserved `edges`) index is
   `< vertices.len`.
7. **Weighted-flag agreement** — every vertex's `weighted` matches the mesh's
   `weighted` flag; an unweighted vertex carries no influences.
8. **Weighted influences** — each weighted vertex has ≥ 1 influence; each
   influence names a **known bone** with a **non-negative weight**; the influence
   weights **sum to `1`** within the mesh weight-sum tolerance.

All positional components (`x`, `y`, `bindX`, `bindY`, `weight`) are finite and
quantized to `f32` on load, and `u`/`v` are quantized per
`docs/float-math-contract.md` (the same `1e-4` cross-runtime tolerance governs
skinning agreement below).

## Load edge cases (normative)

The lettered cases below are the canonical rejection enumeration; each maps to a
check in `validateMeshAttachment`.

| Case | Rule |
|---|---|
| (a) empty `name` | **Reject** — `schemaViolation`. |
| (b) zero vertices | **Reject** — a mesh must contain at least one vertex (`schemaViolation`). |
| (c) `uvs.len != vertices.len`, or any `u`/`v` outside `0..1` after `f32` quantization (`quantizeUnit`) | **Reject** — UV count must match vertex count and each coordinate must be unit-range (`schemaViolation`). |
| (d) `triangles` empty or `len mod 3 != 0` | **Reject** — triangles must be index triplets (`schemaViolation`). |
| (e) triangle index `≥ vertices.len` | **Reject** — `unknownRequiredReference`. |
| (f) vertex `weighted` disagrees with mesh `weighted` (incl. unweighted vertex carrying influences) | **Reject** — `schemaViolation`. |
| (g) weighted vertex with no influences, an unknown/empty influence bone, a negative weight, or influences not summing to `1` | **Reject** — `schemaViolation` (unknown bone ⇒ `unknownRequiredReference`). |

## Packed `meshVertices` byte layout (`.bnb`)

The `meshVertices` property uses `backingType: bytes` (registry key `3003`). The
payload byte layout is **frozen** and branches on the mesh's `meshWeighted` flag:

```
varuint  vertexCount

# unweighted (meshWeighted = false): vertexCount * (
f32      x     (little-endian IEEE-754)
f32      y
# )

# weighted (meshWeighted = true): vertexCount * (
varuint  influenceCount
#   influenceCount * (
varuint  boneStringIndex   (index into the skeleton string table)
f32      bindX
f32      bindY
f32      weight
#   )
# )
```

The weighted branch stores each influence's bone as a **varuint string-table
index**, not an inline name; the canonical-JSON `bone` field is the resolved
name. Any trailing bytes after the declared `vertexCount` (and, when weighted,
each vertex's declared `influenceCount`) are a load error.

## Packed `meshUvs` byte layout (`.bnb`)

The `meshUvs` property uses `backingType: bytes` (registry key `3004`). The
payload byte layout is **frozen**:

```
varuint  count             (equals vertexCount)
f32      u0    (little-endian IEEE-754)
f32      v0
f32      u1
f32      v1
...                        (2 × count f32 values total)
```

This is structurally an **f32-pair** array. Any trailing bytes after `2 × count`
f32 values are a load error.

## Packed `meshTriangles` byte layout (`.bnb`)

The `meshTriangles` property uses `backingType: bytes` (registry key `3005`). The
payload byte layout is **frozen**:

```
varuint  count             (a multiple of 3)
varuint  vertexIndex0
varuint  vertexIndex1
varuint  vertexIndex2
...                        (count varuint values total, forming triples)
```

Each `vertexIndex` must be `< vertexCount`. Any trailing bytes after `count`
varuint values are a load error.

## Deterministic skinning algorithm (forward reference — implemented in prompt 20)

The skinning a later slice applies to a mesh is **normative here** so both
runtimes match within the `1e-4` tolerance of `docs/float-math-contract.md`
(restates `skinMeshVertices` in `runtime-nim/src/bony/mesh/skinning.nim:55-69`):

- **Method**: linear blend skinning. A weighted vertex's world position is

  ```
  worldPos = sum_i weight_i * (boneWorld_i * (bindX_i, bindY_i))
  ```

  where `boneWorld_i` is the world transform of influence `i`'s bone and the
  influences are combined in **stored order**. An unweighted vertex is
  transformed by the owning slot's bone world transform:
  `worldPos = slotBoneWorld * (x, y)`.
- **Determinism**: the influence summation follows the vertex's stored influence
  order; no reordering or reweighting occurs at evaluation.
- **Quantization**: each output component is quantized to `f32` at the output
  boundary via `quantizeF32` (`runtime-nim/src/bony/model.nim`), so both runtimes
  agree within `1e-4`.
- **Reserved hook**: `dualQuaternionSkinning` is a reserved method value and is
  rejected in v1; only `linearBlendSkinning` is implemented.

## Related contracts

- `docs/float-math-contract.md` — `quantizeF32`, `1e-4` cross-runtime tolerance.
- `docs/clipping-attachment-contract.md` — sibling slot-bound attachment class;
  meshes are **not** clipped in v1.
- `docs/load-validation-contract.md` — the shared JSON/binary load-validation pass.
- `docs/binary-canonicalization.md` — canonical `.bnb` byte emission.
- `registry/key-ranges.md` — the M4 band (`3000..3999`).
