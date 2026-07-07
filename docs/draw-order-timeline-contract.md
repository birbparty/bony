# Draw-Order Timeline Contract

Status: **binding**. Owner bead: `bony-s4ll.1` (Dart animated draw-order
timeline).

This contract defines the `bony`-owned **draw-order timeline**: a clip-owned,
clip-global animation track that restacks slots over time. The setup `slots[]`
order remains the baseline draw order. A sampled draw-order key produces the
slot order that renderers consume through `DrawBatch` emission: index `0` is
drawn first and is therefore backmost; larger indices draw later and are
frontmost subject to blending and clipping.

The model, serialized names, packed byte layout, validation rules, and sampling
semantics are project-owned. They are derived from the existing `bony` slot,
animation, clipping, canonicalization, and binary contracts plus generic
animation terminology. They are not derived from any third-party runtime source,
generated schema, wire keys, or documentation prose. Comparable products justify
only the capability category.

## Model

An animation clip owns at most one draw-order timeline:

- `AnimationClip.drawOrderTimeline` is optional.
- The timeline is clip-global. It has no bone, slot, skin, attachment, or event
  target.
- The timeline contains one or more keyframes.
- Each keyframe contains a non-negative time and zero or more slot offsets.

The Dart model names are:

```dart
class DrawOrderOffset {
  const DrawOrderOffset({required this.slot, required this.offset});
  final String slot;
  final int offset;
}

class DrawOrderKeyframe {
  const DrawOrderKeyframe({required this.time, this.offsets = const []});
  final double time;
  final List<DrawOrderOffset> offsets;
}

class DrawOrderTimeline {
  const DrawOrderTimeline({required this.keys});
  final List<DrawOrderKeyframe> keys;
}
```

The same semantic model applies to Nim. Runtime type names may follow local
language style, but the serialized surface and validation rules are shared.

This is not a static slot stacking field. `SlotData` setup order remains the
only static baseline order, and this contract does not add a persistent
per-slot z-index.

## Keyframe Semantics

Draw order is stepped:

- Before the first keyframe, the setup `slots[]` order is used.
- At a keyframe time, that keyframe's order applies.
- Between keyframes, the last keyframe whose `time <= sampleTime` is held.
- After the last keyframe, the last keyframe is held.
- There is no interpolation and no curve field.

Each keyframe stores offsets relative to setup order:

- Each offset entry is `{slot, offset}`.
- `slot` names a declared setup slot.
- `offset` is signed.
- `targetIndex = setupIndex(slot) + offset`.
- Slots absent from a keyframe have implicit offset `0`.
- After explicit and implicit offsets are combined, target indices must be
  exactly the complete integer set `0..slotCount-1`.
- The sampled order is the slots sorted by target index.

This complete-permutation rule intentionally rejects ambiguous data. For
example, moving one slot onto another slot's setup index is invalid unless the
displaced slot is also explicitly offset so the final target indices remain a
complete permutation.

Explicit zero offsets are reader-tolerant but not canonical:

- Loaders accept `offset == 0`.
- Validators normalize zero-offset entries away before duplicate and
  permutation checks.
- Canonical writers omit zero-offset entries.
- A keyframe whose offsets all normalize away is equivalent to `offsets: []`
  and restores setup order.

## JSON Shape

Each animation clip may include a singular `drawOrderTimeline` object:

```json
{
  "name": "wave",
  "drawOrderTimeline": {
    "keyframes": [
      {
        "t": 0.25,
        "offsets": [
          {"slot": "front_arm", "offset": 1},
          {"slot": "torso", "offset": -1}
        ]
      },
      {"t": 0.75, "offsets": []}
    ]
  }
}
```

Canonical JSON rules:

- Omit `drawOrderTimeline` when absent.
- Do not emit an empty declared timeline.
- If `drawOrderTimeline` is present, `keyframes` is required and must contain at
  least one keyframe.
- Keyframe time is serialized as `t`, quantized as f32, non-negative, and
  strictly increasing.
- `offsets` is optional per keyframe and defaults to `[]`.
- Offset entries are canonicalized in setup slot order, not lexical slot-name
  order.
- Offset entries whose normalized offset is `0` are omitted by canonical
  writers.

Animation clip canonical field order is:

1. `name`
2. `boneTimelines`
3. `slotTimelines`
4. `drawOrderTimeline`
5. `deformTimelines`
6. `eventTimelines`

Empty omission preserves legacy clips that do not contain draw-order animation.

## Packed `drawOrderTimeline` Byte Layout (`.bnb`)

The `.bnb` object stream adds a `drawOrderTimeline` child record immediately
under its owning `animationClip`. The child record carries one required packed
bytes property, `drawOrderKeys`.

The canonical animation child order is:

1. all `boneTimeline` records in loaded order
2. all `slotTimeline` records in loaded order
3. the optional `drawOrderTimeline` record
4. all `deformTimeline` records in loaded order
5. all `eventTimeline` records in loaded order

The packed payload is frozen:

```text
varuint keyCount              (>= 1)
repeat keyCount:
  f32     time                (little-endian IEEE-754; f32-quantized,
                              non-negative, strictly increasing)
  varuint offsetCount
  repeat offsetCount:
    varuint slotIndex         (setup slot index)
    svarint offset            (zig-zag signed varint)
```

Canonical writer rules:

- Offset entries are sorted by `slotIndex`.
- Duplicate `slotIndex` values are rejected.
- Entries with `offset == 0` are omitted.
- `offsetCount == 0` is valid and restores setup order.
- `slotIndex` resolves against setup `slots[]` order.
- The decoded keyframe must pass the same permutation validation as JSON.
- The payload must have no trailing bytes after the declared keyframes.

The `drawOrderTimeline` type key and `drawOrderKeys` property key are allocated
from the animation timeline family in the M3 registry range. The broad M2 range
mentions draw order because setup slot order and renderer draw batches first
landed there; this animated timeline is an M3 animation child record.

## Load-Validated Invariants

A declared draw-order timeline is rejected unless all rules hold:

1. The timeline object exists only as an animation clip child and at most once
   per clip.
2. `keyframes` contains at least one key.
3. Key times are f32-quantized, finite, non-negative, and strictly increasing.
4. Every referenced slot exists.
5. Within one keyframe, a slot may appear at most once after zero-offset
   normalization.
6. Every target index is in range `0..slotCount-1`.
7. Explicit and implicit offsets produce every target index exactly once.
8. Missing `offsets` is equivalent to `offsets: []`.
9. Explicit zero offsets are accepted and normalized away.
10. Dynamic clipping ranges remain valid for every declared keyframe.

Diagnostics should follow the existing loader family and include enough path
context to identify the failing animation, keyframe, and offset. Unknown slot
diagnostics should include `drawOrderTimeline` and `unknown slot`.

### Clipping Validity

Clipping attachments define contiguous ranges in draw order. Draw-order
animation changes that order, so validation must conservatively prove that every
declared draw-order key keeps active clip ranges valid:

- A clipping slot must remain before its inclusive `untilSlot` when `untilSlot`
  is non-empty.
- A clipping slot with empty `untilSlot` clips through the end of the sampled
  order.
- Active clipping ranges must not overlap or nest in the sampled order.

If the implementation cannot prove validity because attachment timelines make
clip activation time-dependent, it must reject the ambiguous combination or
split a follow-up design bead. It must not silently let clipping disappear,
reverse, or use setup order while draw batches use sampled order.

## Runtime Sampling And Mixing

The pure sampler takes a timeline, setup slots, and sample time, and returns
slot names in sampled order:

```dart
List<String> sampleDrawOrderTimeline(
  DrawOrderTimeline timeline,
  List<SlotData> setupSlots,
  double time,
)
```

The sampler implements the stepped rules in this contract. It must not mutate
the skeleton or slot data.

Mixer behavior:

- Draw order is a thresholded, non-interpolated channel like attachment and
  deform channels.
- `track.mixAttachmentThreshold` controls whether a track contributes sampled
  draw order.
- When multiple tracks contribute draw order, the last winning entry in track
  application order wins, matching existing map-overwrite behavior for
  attachment and deform channels.

Pose application:

- Attachment overrides are resolved by slot name before any slot list reorder.
- When a draw order is sampled, the posed `SkeletonData.slots` list follows the
  sampled order.
- Every other `SkeletonData` field is preserved, including constraints, skins,
  animations, state machines, nested rigs, and deform overrides.
- `buildDrawBatches` does not perform a second sort; it consumes the posed slot
  order.

## Non-Goals

- No static `SlotData.zOrder`, per-slot setup stacking override, or editor-only
  row/z-index model.
- No Flashy envelope, importer degradation behavior, UI concept, or downstream
  persistence workaround in the `bony` API.
- No blend-mode support.
- No new interpolation curve for draw order.
- No `.bnb` conformance fixture before Nim canonical JSON and `.bnb` conversion
  can preserve draw-order timelines.
