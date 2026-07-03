# Clipping Attachment Contract

Status: **binding**. Owner bead: `bony-jkt` (M4 clipping-attachment milestone).

This contract defines the `bony`-owned **clipping attachment**: a slot-bound
convex-polygon mask that clips a contiguous range of the draw order. This slice
(prompt 15) specifies the format, the load-time validation, and — normatively,
for a later slice to implement — the deterministic clip algorithm. **No geometry
is clipped in this slice**: `DrawBatch.clipId` is not populated and no runtime
reads the clip. Prompt 16 evaluates it, prompt 17 adds the conformance golden,
and prompt 18 brings the Dart runtime to parity.

The clipping model, field names, range semantics, wire layout, and algorithm are
**project-owned** and were chosen from generic geometry terminology, not derived
from any third-party runtime (see `docs/PROVENANCE.md` and `docs/CLEANROOM.md`).

## Model

A clipping attachment is a **slot-bound attachment class**, authored exactly like
a region attachment:

- A skeleton-level array `clippingAttachments` holds the clip records.
- A slot references a clip **by name** through the existing `slot.attachment`
  field — the same field that references region attachments. The load-time
  slot→attachment check accepts either a region name or a clipping-attachment
  name.
- A clip record has exactly three fields and no others:
  - `name` (string, required) — stable unique identifier referenced by
    `slot.attachment`.
  - `vertices` (required) — the convex polygon as a flat list
    `[x0, y0, x1, y1, ...]` (minimum 3 points ⇒ 6 numbers), expressed in the
    owning slot's **bone-local space**.
  - `untilSlot` (string, optional, default `""`) — the slot at which the clip's
    range stops, **inclusive**. Empty means "to the end of the draw order".

No per-vertex weights, softness/feather, texture references, mesh attachments,
skins, or `skinRequired` gate exist in v1.

### The clip's "own slot"

A clip's range is anchored by the slot that references it via `slot.attachment`.
That slot is the clip's **own slot**. Two slots may reference the same clip name;
each reference is an **independent clip instance** with its own range anchored at
its own slot (see edge cases). A clip present in `clippingAttachments` but
referenced by zero slots is **allowed and inert** — it clips nothing.

## Convex-polygon invariants (load-validated)

A clip's `vertices` are rejected at load unless all hold (these restate
`validateConvexClip*` in `runtime-nim/src/bony/mesh/clipping.nim`):

1. **At least three points** — `vertices.len` is even and ≥ 6.
2. **Non-zero signed area** — `|signed area| > 1e-9`.
3. **Convex** — the turn direction (cross product of consecutive edge vectors) is
   uniform in sign around the polygon; a turn opposing the polygon's winding by
   more than `1e-9` is rejected.

All vertex components must be finite and are quantized to `f32` on load per
`docs/float-math-contract.md`.

## Range semantics (`untilSlot`, inclusive)

Given a clip instance whose own slot is at draw-order index `own`:

- Let `end = index(untilSlot)` when `untilSlot` is non-empty, else `end =`
  index of the **last** slot in draw order.
- The clip **governs** every draw batch from the slot **after** `own`
  (`own + 1`) through `end` **inclusive**. The clip's own slot draw batch is not
  clipped by its own clip.

`untilSlot`, when non-empty, must name a **known slot strictly after** the clip's
own slot in draw order.

## No-overlap rule

Clip ranges may **not** overlap or nest. Walking slots in draw order, a clip may
not **begin while another clip's range is still active**. A clip instance is
active over `[own, end]` inclusive. Concretely: sort clip instances by `own`
(draw order already provides this); reject if any instance's `own` is `≤` the
previous active instance's `end`.

## Range edge cases (normative)

| Case | Rule |
|---|---|
| `untilSlot` earlier than **or equal to** the clip's own slot | **Reject** at load — degenerate/empty range (`schemaViolation`). |
| Clip's own slot is the **last** slot (with `untilSlot` omitted) | **Reject** — empty range (`schemaViolation`). |
| `untilSlot` names an unknown slot | **Reject** — `unknownRequiredReference`. |
| Clip in `clippingAttachments` referenced by **zero** slots | **Allowed**, inert. Its `untilSlot`, if set, must still name a known slot. |
| **Two** slots reference the **same** clip name | **Allowed** — each is an independent clip instance with its own range. |
| Second clip whose own slot **equals** the first clip's `untilSlot` | **Overlap → reject.** The active interval is inclusive of `untilSlot`. |

## Packed `vertices` byte layout (`.bnb`)

The `vertices` property uses `backingType: bytes` (registry key `3000`). The
payload byte layout is **frozen**:

```
varuint  pointCount
f32      x0   (little-endian IEEE-754)
f32      y0
f32      x1
f32      y1
...                       (2 × pointCount f32 values total)
```

`pointCount = vertices.len div 2`. This is structurally an **f32-pair** array and
is distinct from the `ikConstraint.bones` bytes layout (registry key `4014`),
which packs varuint string-table indices; the shared mechanism is only the
`backingType: bytes` property encoding. Any trailing bytes after `2 × pointCount`
f32 values are a load error.

## Deterministic clip algorithm (forward reference — implemented in prompt 16)

The clip that a later slice applies to each governed `DrawBatch` is **normative
here** so both runtimes match within the `1e-4` tolerance of
`docs/float-math-contract.md`:

- **Algorithm**: Sutherland–Hodgman convex-polygon clipping of each governed
  `DrawBatch` quad against the clip polygon (both in a common space).
- **Interpolation at edge intersections**: linearly interpolate **both** the
  `u`/`v` texture coordinates **and** the `r`/`g`/`b`/`a` vertex color at the
  parametric intersection point. (At a `t = 0` setup pose, region draw batches
  carry uniform color `(1, 1, 1, 1)` and `SlotData` has no color field, so the
  color interpolation is correct-but-unobservable via a rig; it is specified for
  correctness, and the conformance golden's non-vacuity rests on geometry + u/v.)
- **Re-triangulation**: the clipped convex polygon is re-triangulated as a
  **triangle fan pivoting on clipped-polygon vertex 0** (matching
  `clipTrianglesToConvexPolygon`), so both runtimes emit an identical index
  order.
- **Quantization**: intersection coordinates and interpolated attributes are
  quantized to `f32` at the output boundary per `docs/float-math-contract.md`.

## Related contracts

- `docs/float-math-contract.md` — `quantizeF32`, `1e-4` cross-runtime tolerance.
- `docs/load-validation-contract.md` — the shared JSON/binary load-validation pass.
- `docs/binary-canonicalization.md` — canonical `.bnb` byte emission.
- `registry/key-ranges.md` — the M4 band (`3000..3999`, "clipping").
- `docs/mesh-attachment-contract.md` — sibling slot-bound attachment class.
  **Mesh attachments are not clipped in v1**: `buildDrawBatches`'s clip pass skips
  mesh batches (this convex-ring clip would destroy a triangle soup's topology);
  per-triangle mesh clipping is a follow-on milestone.
