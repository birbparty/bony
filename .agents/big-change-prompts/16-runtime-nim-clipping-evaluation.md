# /big-change prompt - runtime evaluation (M4 clipping attachment, Nim)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 4** of the M4 clipping-attachment milestone.
> Depends on `15-contract-clipping-attachment-format.md` (the clipping record
> must load and the contract doc must exist). Must land before
> `17-conformance-clipping-rig-golden.md`. Prompt 18 (Dart parity) follows.
> **Candidate category:** frontier.

---

/big-change Evaluate loaded clipping attachments in the Nim runtime: populate `DrawBatch.clipId` and deterministically clip the covered draw batches against the convex clip polygon, per the clipping-attachment contract.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Prompt 15 made a clipping attachment a first-class, loadable, validated record
(`ClipAttachmentData` on `SkeletonData`) and wrote
`docs/clipping-attachment-contract.md`. But `buildDrawBatches` still ignores it:
`clipId` is hardcoded to `""` (`runtime-nim/src/bony/transform.nim:833`) and no
draw batch is clipped. This prompt implements the runtime behavior the contract
specifies. **Nim only** — Dart parity is prompt 18.

Already in place:
- `runtime-nim/src/bony/transform.nim` `buildDrawBatches*(data, worlds)` (signature
  `:800`, region-only slot loop `819-841`, `clipId: ""` at `:833`, world-space
  quad emission `827-841`). Today it builds exactly one `DrawBatch` per slot whose
  `attachment` names a region.
- `runtime-nim/src/bony/mesh/clipping.nim`: a working Sutherland–Hodgman convex
  clip — `inside`/`intersection` (71-93), `clipPolygon` (96-115),
  `validateConvexClip*` (54-68), `clipTrianglesToConvexPolygon*` (118-122). It
  clips `SkinnedMeshVertex` triangles (x/y/u/v, **no color**) and re-triangulates
  as a fan, quantizing via `quantizeF32`. This is the reusable primitive; its math
  is the contract for the clip geometry.
- `DrawBatch` (`model.nim:232-241`) carries `clipId` and a `vertices:
  seq[DrawVertex]` where `DrawVertex` has x/y/u/v **and r/g/b/a**.

Build exactly this:

0. **CRITICAL — guard the region lookup first (crash fix).** The slot loop does
   `let region = regions[slot.attachment]` **unconditionally** for any non-empty
   attachment (`transform.nim:822`). In Nim a `Table[]` miss **raises KeyError**,
   so the instant a slot's `attachment` names a clip (exactly what prompt 15
   introduced), `buildDrawBatches` crashes rather than skipping. Before the
   `regions[...]` lookup, add a guard that **skips** slots whose `attachment`
   resolves to a `ClipAttachmentData` (they produce no draw batch). The Dart side
   already guards this (`transform.dart:1127` `if (region == null) continue`) — this
   is a Nim-only asymmetry that must be closed or every clip rig crashes.

1. **Populate `clipId`.** In `buildDrawBatches`, after resolving draw batches in
   draw order, for each clipping attachment (a slot whose `attachment` names a
   `ClipAttachmentData`), walk the covered draw-order range — from the batch after
   the clip's own slot through the `untilSlot` slot inclusive (to the end when
   `untilSlot` is empty) — and set each covered batch's `clipId` to the clip
   attachment's `name`. The clip's own slot produces no draw batch (it has no
   region), so it does not appear in `result`; handle that (resolve the clip's
   draw-order position by slot index, not by batch index — the loop iterates
   `for slot in data.slots`, so draw order == slot order and batches are a
   subsequence, one per region slot). Honor the load-time no-overlap invariant —
   at most one clip is active over any batch.

2. **Clip the covered batches.** For each covered `DrawBatch`, intersect its
   world-space polygon against the clip polygon transformed to world space by the
   clip's owning slot's bone world transform (same world transform the batch
   vertices use — via `worlds`/`transformPoint`, mirroring the region quad path at
   `transform.nim:786-797`). Use the Sutherland–Hodgman convex-clip primitive from
   `clipping.nim`. Because `DrawBatch` vertices carry **color** that
   `SkinnedMeshVertex` lacks, you must interpolate **r/g/b/a in addition to u/v**
   at every clip-edge intersection. **Preferred: (b) add a `DrawVertex`-specific
   convex clip** that reuses the `inside`/`intersection` geometry from
   `clipping.nim`. Do **NOT** add rgba fields to the shared `SkinnedMeshVertex`
   type (it is shared with `skinning.nim`/`deform.nim`/`deformers.nim`) and do NOT
   change the public signature of `clipTrianglesToConvexPolygon` (depended on by
   `runtime-nim/tests/test_smoke.nim:3725+`). If you instead generalize the shared
   routines, do it with a generic vertex type so neither `SkinnedMeshVertex` nor
   the existing public signature changes. Re-triangulate the clipped polygon as
   a fan and rebuild the batch's `vertices`/`indices`. Apply `quantizeF32` at the
   output boundary exactly as `clipping.nim` does, so the result is deterministic
   and matches the contract within `1e-4`. A batch fully outside the clip polygon
   becomes empty (0 vertices / 0 indices) but retains its `clipId` and metadata; a
   batch fully inside is unchanged except for `clipId`.

3. **Interaction with deformers.** `buildDrawBatches` has no deformer re-map in
   the Nim path today (unlike Dart) — but if the slot loop is refactored, keep the
   existing region/quad output identical for unclipped slots. Clipping must be a
   post-step that does not perturb batches with empty `clipId`.

Do NOT change the render adapter (`naylib_adapter.nim`) or `usesStencil` in this
prompt — clipping here is geometric (CPU polygon intersection producing final
vertices), which is what the numeric golden gate checks. The stencil/render path
stays a passive `clipId` passthrough.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Clipping contract (binding; the algorithm spec): docs/clipping-attachment-contract.md
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4 tolerance,
  float ordering)
- Convex clipper to reuse/generalize: runtime-nim/src/bony/mesh/clipping.nim
  (inside/intersection 71-93, clipPolygon 96-115, validateConvexClip 54-68,
  clipTrianglesToConvexPolygon 118-122)
- Draw-batch builder: runtime-nim/src/bony/transform.nim (vertex helper 786-797,
  buildDrawBatches 800-848, clipId "" at 833, quad emission 827-841)
- Model: runtime-nim/src/bony/model.nim (DrawBatch 232-241, DrawVertex fields,
  ClipAttachmentData + clippingAttachments accessor added in prompt 15)
- Repo gate: Makefile `test` target
- Analogous freshest runtime-eval slice to mirror: the physics runtime-eval slice
  (bead bony-6pd, prompt 12) — how a loaded record became a runtime effect with
  Nim unit tests
- Beads: file under the clipping milestone parent, dependent on the prompt-15 bead

**Success Criteria**
- `buildDrawBatches` sets `clipId` on exactly the covered draw batches (draw-order
  range from after the clip's slot through `untilSlot` inclusive, else to end) and
  leaves all other batches with `clipId == ""`.
- Covered batches are geometrically clipped: a rig where a convex clip polygon
  partially covers a region slot produces a clipped batch whose vertex count
  and/or positions differ from the unclipped quad, with **u/v** correctly
  interpolated at clip-edge intersections; a fully-inside batch is unchanged
  except `clipId`; a fully-outside batch is emptied. (Region batches carry uniform
  color `(1,1,1,1)` and `SlotData` has no color field, so r/g/b/a interpolation is
  correct-but-unobservable through a rig — see the unit-test note below.)
- Output is deterministic and quantized per `docs/float-math-contract.md`; results
  are stable across repeated runs and byte-identical from the `.bony` and the
  `.bnb` load paths.
- NEW Nim unit tests in `runtime-nim/tests/` cover: clipId assignment over the
  covered range; a partial clip with interpolated **u/v** vertices (via a rig or a
  directly-built batch); a fully-inside no-op; a fully-outside empty batch; and
  `untilSlot` bounding (a batch past `untilSlot` is untouched). Because no rig can
  produce a non-uniform-colored quad, cover **r/g/b/a interpolation** with a
  dedicated unit test that constructs a `DrawBatch` whose `DrawVertex` colors
  differ per corner and calls the clip primitive directly (not via
  `buildDrawBatches`), asserting interpolated color at a clip-edge intersection.
- `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim` is
  clean; `make test` passes; existing goldens (m1..m9) are unchanged (no rig
  without a clip attachment gains a non-empty `clipId` or altered vertices).

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source or clip algorithm. The clip algorithm is
  the project-owned Sutherland–Hodgman variant already in `clipping.nim` and
  specified in `docs/clipping-attachment-contract.md`.
- Do NOT introduce nondeterminism: no floating hash iteration order, no unsorted
  set traversal; follow the float-order rules in the float-math contract.
- Do NOT add a conformance rig/golden (prompt 17) or touch the Dart runtime
  (prompt 18) here.
- Do NOT change `naylib_adapter.nim`, `usesStencil`, or the render path.
- Keep the clip strictly convex and single-active per the loaded invariants; do
  not implement nested/stacked clips or non-convex clips.
- Keep the slice to one meaningful implementation session: Nim `buildDrawBatches`
  clip evaluation + unit tests.
