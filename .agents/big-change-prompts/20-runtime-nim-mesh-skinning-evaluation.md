# /big-change prompt - Nim runtime evaluation (M4 mesh attachment + skinning)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 4** of the M4 mesh-attachment + skinning
> milestone. Depends on `19` (the loadable record + contract). Must land before
> `21` (the conformance rig/golden pins this runtime's output) and `22` (Dart
> matches this reference). **Candidate category:** frontier.

---

/big-change Make the Nim reference runtime skin loaded mesh attachments into draw batches: in buildDrawBatches, when a slot references a mesh, compute per-vertex world positions (linear-blend skinning for weighted, FK for unweighted) and emit a DrawBatch carrying the mesh triangles and uvs, matching the mesh-attachment contract.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Prompt 19 made a mesh attachment a loadable, validated, round-trippable record
(`SkeletonData.meshAttachments`), and wrote `docs/mesh-attachment-contract.md`
pinning the linear-blend skinning formula. But nothing draws it yet:
`buildDrawBatches` (`runtime-nim/src/bony/transform.nim:801`) only emits region
quads. Its slot loop skips any slot whose attachment is not a region - the guard
at `transform.nim:834` (`not regions.hasKey(slot.attachment)`) currently drops a
mesh-referencing slot silently.

This slice adds the **mesh dispatch** at that seam. The skinning math already
exists and is fully project-owned: `skinMeshVertices*`
(`runtime-nim/src/bony/mesh/skinning.nim:35-93`) takes the loaded worlds and a
`MeshAttachment` and returns `seq[SkinnedMeshVertex]` (`x, y, u, v` -
`skinning.nim:14-18`). This prompt wires it into `buildDrawBatches` and wraps its
output into `DrawVertex`/`DrawBatch`. No format change, no new registry keys, no
Dart, no conformance golden here.

**Import-cycle decision (load-bearing - decide this explicitly).** `skinning.nim`
today does `import bony/transform` (`skinning.nim:7`), used **only** by the two
*convenience* overloads at `skinning.nim:78-93` (they call
`computeWorldTransforms`, `transform.nim:229`). The **explicit-worlds** overload
this prompt calls (`skinning.nim:35-75`) needs nothing from `transform` - it uses
`Affine2` (from `model`) and a local `transformPoint` (`skinning.nim:21`).
Therefore, making `transform.nim` `import bony/mesh/skinning` as-is would create a
`transform <-> skinning` cycle (the same forbidden pattern prompt 19's type-move
avoided). Break it: **relocate the two convenience overloads (`skinning.nim:78-93`)
out of `skinning.nim`** (into `transform.nim`, or a tiny third module that imports
both), so `skinning.nim` imports only `model` + `mesh/attachments`; then
`transform.nim` can import `skinning` with no cycle. This does **not** violate
"do not modify `skinMeshVertices`" below - the explicit-worlds overload the seam
calls is untouched; only the two `computeWorldTransforms` wrappers move. `nim
check` is the gate that this is cycle-free.

**Per-frame re-validation (note, not a blocker).** `skinMeshVertices` calls
`validateMeshAttachment` on entry (`skinning.nim:42`) and raises on any violation.
Called from `buildDrawBatches` this re-validates already-load-validated,
immutable meshes on every build. That is acceptable (the data cannot change after
load); do not "fix" it by weakening validation. If profiling later shows it
matters, factor an internal skinning body that skips re-validation - out of scope
here.

Build exactly this:

1. **Mesh dispatch in `buildDrawBatches`** (`runtime-nim/src/bony/transform.nim`):
   the proc is `buildDrawBatches*(data: SkeletonData; worlds: seq[Affine2]):
   seq[DrawBatch]` (`:801`), with a private `vertex(world; x,y,u,v): DrawVertex`
   helper at `787-798` (hardcodes `r=g=b=a=1.0`). Build a mesh lookup alongside the
   region map (mirror how regions are keyed), e.g.
   `meshByName = {mesh.name: mesh}` over `data.meshAttachments`. In the slot loop
   (region emit at `831-860`): the non-region guard at `transform.nim:834`
   (`if not regions.hasKey(slot.attachment): continue`) currently drops a
   mesh-referencing slot silently, and the region lookup just after it would
   `KeyError` on a mesh name - so the mesh dispatch MUST sit **before** line `834`.
   If the attachment names a mesh:
   - Skin it: `let skinned = skinMeshVertices(data, worlds, slot.bone, mesh)`
     (the overload at `skinning.nim:35-41` that takes explicit `worlds` ordered
     like `data.bones` - `buildDrawBatches` already has `worlds`; do NOT recompute
     via the convenience overloads at `78-93`).
   - Wrap each `SkinnedMeshVertex` into a `DrawVertex` with `r=g=b=a=1.0` (meshes
     carry no per-vertex color in v1; use the same uniform color the region path
     uses - do not invent a slot-color read here). Reuse or mirror the `vertex()`
     helper; note `SkinnedMeshVertex` already carries `u,v` from the mesh's uvs.
   - Set `DrawBatch.indices` to the mesh's `triangles` (already a flat
     `seq[uint16]` on the record; convert to the `DrawBatch.indices` element type
     if needed - `DrawBatch.indices` is `seq[uint16]`, `model.nim:245`).
   - Populate the rest of the `DrawBatch` (Nim fields `model.nim:237-246`):
     `slot`, `bone` (= `slot.bone`), `attachment` (= mesh name), and the slot's
     `world` matrix exactly as the region path sets them. For the metadata fields
     the golden compares exactly (`texturePage`, `blendMode`), set them to the
     **same deterministic values the region path derives for the same slot** so a
     region and a mesh on the same slot are indistinguishable in those fields (the
     v1 mesh record carries neither `texturePage` nor `blendMode`, so they come
     from the slot/defaults, not the attachment; pin whatever the region path uses
     - `texturePage = ""` and the slot's blend mode - and record the chosen values
     in `docs/mesh-attachment-contract.md` so prompt 22's Dart port matches
     byte-for-byte). Set `clipId = ""` (meshes are not clipped in v1 - see item 2).
     Record `batchSlotIndex.add slotIdx` exactly like the region path (`:860`).
   - Emit in the same draw-order position a region would occupy (one batch per
     slot), so draw order is unchanged.
2. **Meshes are NOT clipped in v1 (scope this OUT - important)**: the existing clip
   pass calls `clipDrawBatchPolygon` (`mesh/drawbatch_clipping.nim:125`), which
   treats a batch's `vertices` as a **single convex polygon in boundary order** and
   **fan-triangulates from vertex 0, ignoring the batch's input `indices`**
   (`drawbatch_clipping.nim:127-145`). A skinned mesh is a triangle *soup* with an
   explicit triangle list and shared/interior vertices - feeding it through that
   path would reinterpret its vertex list as one convex ring and destroy its
   topology. So do NOT route mesh batches through the clip pass in v1. Concretely:
   in the clip pass (`transform.nim:867-897`), **skip any batch whose attachment is
   a mesh** when applying `clipDrawBatchPolygon` (leave its `clipId == ""` and
   vertices untouched), and document "clipping a mesh attachment is a v1 non-goal;
   only region batches are clipped" in `docs/mesh-attachment-contract.md` (and note
   it in `docs/clipping-attachment-contract.md`'s related-work list). Correct
   per-triangle mesh clipping is a deliberate follow-on milestone, not this slice.
   File a follow-up bead for it.
3. **Unit tests** (`runtime-nim/tests/`, e.g. extend `test_smoke.nim` or a new
   test): given a small rig with (a) an unweighted mesh bound to one bone and
   (b) a weighted mesh whose vertices are shared across two bones with a non-rest
   pose, assert `buildDrawBatches` emits a `DrawBatch` for the mesh slot whose
   `vertices` world positions equal the hand-computed `skinMeshVertices` result
   within `1e-4`, whose `indices` equal the mesh triangles, and whose `u,v` equal
   the mesh uvs. Include one assertion that a **weighted** vertex lands at a
   position strictly different from any single bone's FK transform of its bind
   (i.e. the blend is observable), so the test is non-vacuous. Add one assertion
   that a mesh slot inside a clip range keeps `clipId == ""` and its full,
   un-fan-collapsed triangle set (i.e. the clip pass skipped it), pinning the
   "meshes not clipped in v1" decision from item 2.

Keep this slice runtime-eval only: no format/registry/schema change, no new
attachment fields, no Dart, no committed conformance golden. Do not modify
`skinMeshVertices` or the mesh record - if the skinning output needs massaging to
fit `DrawVertex`, do it at the `buildDrawBatches` seam.

**Links to Relevant Documentation**
- Mesh contract (the skinning formula/order to honor): docs/mesh-attachment-contract.md
- Float math contract: docs/float-math-contract.md (1e-4, quantizeF32, determinism)
- Skinning solver to call (do not duplicate its math): runtime-nim/src/bony/mesh/skinning.nim
  (skinMeshVertices explicit-worlds overload 35-41, formula 55-69, SkinnedMeshVertex 14-18)
- The exact emit seam: runtime-nim/src/bony/transform.nim (buildDrawBatches 801,
  vertex() helper 787-798, region emit 831-860, non-region guard 834,
  batchSlotIndex 860, clip pass 867-897)
- DrawBatch/DrawVertex shape: runtime-nim/src/bony/model.nim (DrawVertex 219-227,
  DrawBatch 237-246, Affine2 229-235)
- Mesh record (from prompt 19, now in model.nim): MeshAttachment + MeshVertex +
  MeshUv + MeshInfluence, and SkeletonData.meshAttachments
- Freshest template (mirror closely): the Nim clipping runtime-eval slice - prompt
  .agents/big-change-prompts/16-runtime-nim-clipping-evaluation.md and its landed
  diff (it wired a new attachment effect into buildDrawBatches without touching the
  format).
- Repo gate: Makefile `test`
- Beads: file under the mesh-attachment milestone parent, dependent on the
  prompt-19 bead

**Success Criteria**
- `buildDrawBatches` emits exactly one `DrawBatch` per mesh-referencing slot,
  in the slot's draw-order position, with world-space vertices equal to
  `skinMeshVertices(data, worlds, slot.bone, mesh)` within `1e-4`, `indices` equal
  to the mesh triangles, and `u,v` equal to the mesh uvs; `clipId == ""` at emit.
- Unweighted meshes are drawn via FK through the slot's bone; weighted meshes are
  drawn via linear-blend skinning across their influence bones, matching the
  contract formula and evaluation order.
- Region-only rigs are byte-for-byte unchanged (no regression): all existing
  conformance goldens and `make test` still pass.
- Mesh batches are **not** routed through the clip pass in v1: a mesh slot inside
  a clip range keeps `clipId == ""` and its full triangle set (the clip pass skips
  mesh batches), verified by a unit test; this v1 non-goal is documented in
  `docs/mesh-attachment-contract.md`, and a follow-up bead for per-triangle mesh
  clipping is filed.
- New Nim unit tests cover unweighted + weighted mesh emission (positions,
  indices, uvs) with a non-vacuous weighted-blend assertion, plus the
  mesh-skipped-by-clip-pass case.
- `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim` is clean;
  `make test` passes.

**Constraints**
- Preserve clean-room posture: reuse `bony`'s own `skinMeshVertices`; do not
  consult any third-party runtime's mesh/skinning code.
- Determinism: honor `docs/float-math-contract.md` - f32 quantization at the
  output boundary, stable influence accumulation order, results reproducible
  within `1e-4`.
- Do NOT change the format, registry, schema, `defaults.yml`, the mesh record, or
  the **explicit-worlds** `skinMeshVertices` overload's math/output; do NOT add a
  conformance rig/golden (prompt 21) or touch the Dart runtime (prompt 22).
  (Relocating the two `computeWorldTransforms` convenience overloads out of
  `skinning.nim` to break the import cycle, per the Import-cycle decision above, is
  in scope and is not a change to the skinning math.)
- Keep the slice to one meaningful implementation session: the mesh dispatch in
  `buildDrawBatches` plus Nim unit tests.
