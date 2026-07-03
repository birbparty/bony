# Deform Timeline Contract

Status: **binding**. Owner bead: `bony-68lj` (M4 deform-timeline milestone, prompt 23).

This contract defines the `bony`-owned **deform timeline**: a clip-owned animation
track that drives per-vertex mesh offsets (a *deform*) of one slot's mesh
attachment over time. Each keyframe carries a sparse run of per-vertex `(x, y)`
deltas plus a curve; sampling interpolates between keyframes and the result is
added to the skinned mesh vertices. This slice specifies the **format**, the
**load-time validation**, and — normatively, for prompt 24 to implement — the
**deterministic sampling algorithm** and the loader wiring into `AnimationClip`.
The runtime types (`DeformTimeline`, `DeformKeyframe`, `MeshDelta`) and the
sampling/apply procedures already exist standalone in
`runtime-nim/src/bony/mesh/deform.nim`; prompt 24 wires them into the clip/mixer
and the `.bnb` decode path. No deform loader, `AnimationClip.deformTimelines`
field, conformance rig, or Dart runtime logic is part of this slice.

The deform-timeline model, field names, packed byte layout, and sampling algorithm
are **project-owned** and were chosen from generic animation/geometry terminology,
not derived from any third-party runtime (see `docs/PROVENANCE.md` and
`docs/CLEANROOM.md`). The curve encoding is **reused verbatim** from the existing
bone/slot timeline curve tail (see "Packed `deformTimeline` byte layout").

## Model

A deform timeline is a **clip-owned child record**, authored alongside bone and
slot timelines:

- An animation clip owns an array of deform timelines. In v1 the runtime
  `AnimationClip` carries `boneTimelines`, `slotTimelines`, and `eventTimelines`
  only; a `deformTimelines` collection (and the owning wire record following the
  parent `animationClip`) is added by prompt 24. This contract pins the record
  shape that collection will hold.
- A deform timeline binds to a mesh attachment **by (skin, slot, attachment)
  identity** — the slot names the draw slot, the attachment names the mesh
  attachment on that slot, and the skin selects the skin the mesh belongs to.
- A deform timeline record's canonical-JSON form has exactly these fields:
  - `skin` (string, required) — the reserved skin identity `"default"` (see
    "Reserved skin identity" below). Non-empty.
  - `slot` (string, required) — the name of the slot whose attachment is deformed.
    Non-empty.
  - `attachment` (string, required) — the name of the mesh attachment (the mesh's
    `deformAttachment` key, which equals the mesh `name`; see
    `docs/mesh-attachment-contract.md`). Non-empty.
  - `vertexCount` (integer, required) — the mesh vertex count the deltas index
    against; must be `> 0` and must equal the referenced mesh attachment's vertex
    count. Serialized as a `varuint`.
  - `keyframes` (array, required, `minItems: 1`) — the keyframe list. **Note the
    name change across the boundary:** the runtime field is `DeformTimeline.keys`
    (`runtime-nim/src/bony/mesh/deform.nim`), and the human-readable canonical JSON
    exposes it as `keyframes`. Each keyframe has:
    - `time` (number, required) — keyframe time in seconds; non-negative and
      `f32`-quantized. Keyframe times are **strictly increasing** within a
      timeline.
    - `offset` (integer, optional, default `0`) — the first mesh-vertex index the
      delta run applies to. Serialized as a `varuint`.
    - `deltas` (array, required, `minItems: 1`) — a contiguous run of per-vertex
      offsets `[{ "x": <number>, "y": <number> }, ...]` starting at `offset`;
      `offset + deltas.length ≤ vertexCount`. Vertices outside the run have a zero
      delta.
    - `curve` (optional, default linear) — the interpolation curve to the **next**
      keyframe, encoded as the shared timeline curve tail (linear / stepped /
      bezier); see the byte layout. Defaulted to `linear`.

No multi-skin model, additive/blend deform modes, `inheritDeform` chaining, or
attachment-swap-through-deform are settable in v1. A deform timeline animates only
the per-vertex offsets of a single already-resolved mesh attachment.

### Reserved skin identity

v1 has no first-class skin system: every mesh belongs to the implicit **`"default"`**
skin. A deform timeline's `skin` field is therefore the reserved identity
`"default"`, and a conforming v1 asset MUST set it to exactly `"default"`. The
standalone runtime validator `validateDeformTimeline` currently enforces only that
`skin` is **non-empty** (it is deliberately **not** relaxed to allow empty); the
prompt-24 loader tightens acceptance to the exact reserved value `"default"` and
rejects any other skin as an unresolved reference. This contract pins `"default"`
as the sole valid v1 value so downstream asset validation and the prompt-24 loader
agree; the validator is not loosened to accept empty at any point.

## Load-validated invariants

A deform timeline is rejected at load unless all hold. Invariants 1–8 **restate
`validateDeformTimeline` / `validateDeformKey`** in
`runtime-nim/src/bony/mesh/deform.nim` — the standalone structural validator that
exists today. Invariants 9–11 are the **resolution rules the prompt-24 loader
adds** when the record is decoded in the context of a loaded skeleton (they cannot
be checked by the standalone validator, which sees only the timeline in isolation):

1. **Non-empty skin** — `skin` is non-empty.
2. **Non-empty slot** — `slot` is non-empty.
3. **Non-empty attachment** — `attachment` is non-empty.
4. **Positive vertex count** — `vertexCount > 0`.
5. **At least one keyframe** — `keyframes.len ≥ 1`.
6. **Non-negative, quantized key times** — every keyframe `time`, after `f32`
   quantization, is `≥ 0`.
7. **Strictly increasing times** — `keyframes[i].time > keyframes[i-1].time` for
   every adjacent pair (equal or decreasing times are rejected).
8. **In-range delta runs** — every keyframe has `deltas.len ≥ 1` and
   `offset + deltas.len ≤ vertexCount`.
9. **Reserved skin** *(prompt-24 loader)* — `skin == "default"`.
10. **Resolvable binding** *(prompt-24 loader)* — the `(slot, attachment)` pair
    resolves to a **loaded mesh attachment**: `slot` names a loaded slot and
    `attachment` names a mesh attachment reachable from that slot.
11. **Vertex-count agreement** *(prompt-24 loader)* — `vertexCount` equals the
    referenced mesh attachment's vertex count.

All positional components (keyframe `time`, each delta `x`/`y`) are finite and
quantized to `f32` on load per `docs/float-math-contract.md` (the same `1e-4`
cross-runtime tolerance governs the sampling agreement below). `quantizeF32`
(`runtime-nim/src/bony/model.nim`) is applied to each delta at construction
(`meshDelta`) and to the sample `time`.

## Load edge cases (normative)

The lettered cases below are the canonical rejection enumeration. Cases tied to
`validateDeformTimeline` are checkable by the standalone validator today; cases
requiring skeleton context are pinned normatively for the prompt-24 loader (noted
inline).

| Case | Rule |
|---|---|
| (a) `skin != "default"` | **Reject** — v1 recognizes only the reserved `"default"` skin (`unknownRequiredReference`); *prompt-24 loader*. The standalone validator still rejects an **empty** skin (`schemaViolation`). |
| (b) empty `slot` or `attachment`, or `attachment` naming a mesh not present on the slot | **Reject** — empty is `schemaViolation` (standalone); an attachment that does not resolve to a mesh on the slot is `unknownRequiredReference` (*prompt-24 loader*). |
| (c) `vertexCount ≤ 0`, or `vertexCount` disagreeing with the referenced mesh's vertex count | **Reject** — non-positive is `schemaViolation` (standalone); a mismatch against the resolved mesh is `schemaViolation` (*prompt-24 loader*). |
| (d) zero keyframes | **Reject** — a deform timeline must contain at least one keyframe (`schemaViolation`). |
| (e) a keyframe with zero deltas, or `offset + deltas.len > vertexCount` | **Reject** — each key needs a non-empty delta run that fits the mesh (`schemaViolation`). |
| (f) non-strictly-increasing keyframe times, or a negative key time after `f32` quantization | **Reject** — times must be non-negative and strictly increasing (`schemaViolation`). |
| (g) a `(slot, attachment)` pairing that does not resolve to a loaded mesh attachment | **Reject** — `unknownRequiredReference`; *prompt-24 loader* (the standalone validator cannot see the skeleton). |

## Packed `deformTimeline` byte layout (`.bnb`)

The keyframe payload is carried by the `deformKeys` property, which uses
`backingType: bytes` (registry key `3009`, minted by `bony-68lj.7` under the M4
band). The property's `x-bony-packedBytes` `layout` reference in the generated wire
schema points at this section's anchor
(`docs/deform-timeline-contract.md#packed-deformtimeline-byte-layout-bnb`), set in
`PACKED_BYTES_METADATA` by `bony-68lj.12`. The curve tail embedded per keyframe is
the **same encoding** used by bone/slot timelines (a `varuint` tag `0`=linear /
`1`=stepped / `2`=bezier, and for bezier four little-endian IEEE-754 `f32` control
points `c1x, c1y, c2x, c2y`), reused verbatim from `writeCurve`/`readCurve` in
`runtime-nim/src/bony/binary/semantic.nim` — no second curve encoding is minted.

> **Normative byte layout pinned by `bony-68lj.6`.** The frozen field-by-field
> `.bnb` layout of the `deformKeys` payload (leading `varuint` keyframe count,
> per-key `time`/`offset`/delta-run, and the reused curve tail) is filled into this
> section by its owning bead; the stable heading anchor above is fixed here so the
> registry `layout` pointer and this contract stay in sync.

## Deterministic sampling algorithm (forward reference — implemented in prompt 24)

The sampling a deform timeline applies is **normative here** so both runtimes match
within the `1e-4` tolerance of `docs/float-math-contract.md` (restates
`sampleDeformDeltas` and `applyDeformDeltas` in
`runtime-nim/src/bony/mesh/deform.nim`):

- **Keyframe search** — find the **nearest-preceding key**: the last keyframe whose
  `time ≤` the (f32-quantized) sample time, by forward scan. The sample time is
  quantized to `f32` before the search.
- **Clamping** — at or before the first key, the first key's deltas are held; at or
  after the last key, the last key's deltas are held. No extrapolation past either
  end.
- **Stepped short-circuit** — if the current key's curve is `stepped`, the current
  key's deltas are held (no interpolation) until the next key's time is reached.
- **Interpolation** — otherwise compute the linear fraction
  `t = (time - current.time) / (next.time - current.time)`, ease it through the
  **current key's** curve (`curve.evaluate(t)`; linear returns `t`, bezier solves
  the cubic in `x` and returns the `y` value), then interpolate per vertex:
  `out = a + (b - a) * eased`, where `a`/`b` are the **densified** delta arrays of
  the current and next keys.
- **Sparse → dense** — each key's sparse `(offset, deltas)` run is expanded into a
  full `vertexCount`-length array, zero outside the run, before interpolation.
- **Quantization** — every delta is `f32`-quantized when the key is expanded
  (`meshDelta`), and each interpolated output component is re-quantized to `f32` at
  the output boundary.
- **Apply order** (`applyDeformDeltas`) — the sampled deltas are **added** to the
  already-skinned mesh vertices: `deformed.x = quantizeF32(vertex.x + delta.x)`,
  `deformed.y = quantizeF32(vertex.y + delta.y)`; `u`/`v` are copied through
  unchanged. The delta count must equal the skinned-vertex count. Deform is applied
  **after** skinning (`skinMeshVertices`), on the resolved draw-batch vertex
  positions — consistent with the deformer stage in
  `docs/mesh-attachment-contract.md`.

## Cross-track mixing

A deform timeline resolves on the mixer like an **attachment channel**, not like a
numeric (bone/slot-color) channel: it is **thresholded / winner-take-by-track-weight**,
**not** weight-blended across tracks. When two animation tracks both drive the same
`(skin, slot, attachment)` deform, the track with the greater effective weight wins
outright and its sampled deltas are applied; the offsets from the two tracks are
**not** linearly blended. This matches how an attachment-swap timeline resolves (a
discrete winner) rather than how a translate timeline resolves (a weighted sum),
because a partial blend of two independent sparse delta runs over different vertex
subsets has no well-defined meaning. This mixing rule is **documented-but-unexercised
in v1**: v1 pins single-track deform sampling; multi-track deform arbitration is
specified here so prompt 24's mixer and any later multi-track slice agree, but no v1
conformance rig exercises it.

## Related contracts

- `docs/float-math-contract.md` — `quantizeF32`, `1e-4` cross-runtime tolerance.
- `docs/mesh-attachment-contract.md` — the mesh attachment a deform timeline
  animates; the `deformAttachment` key, vertex count, and the skinning stage deform
  is applied after.
- `docs/binary-animation-state-machine-object-families.md` — the clip/timeline
  child-record family a deform timeline joins; the shared keyframe-payload curve
  tail.
- `docs/load-validation-contract.md` — the shared JSON/binary load-validation pass.
- `docs/binary-canonicalization.md` — canonical `.bnb` byte emission.
- `registry/key-ranges.md` — the M4 band (`3000..3999`).
