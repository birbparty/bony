# Design

## Model

Add a clip-global timeline to Dart:

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

Add to `AnimationClip`:

```dart
final DrawOrderTimeline? drawOrderTimeline;
```

Use a singular field because there is exactly one draw-order channel per clip.
It is clip-global like `EventTimeline`, but unlike `eventTimelines` there is no
reason to support multiple target-less draw-order timelines whose results would
need conflict resolution.

Constructor compatibility:

- Add `this.drawOrderTimeline` as an optional named argument after
  `slotTimelines` and before `deformTimelines`.
- Update every `AnimationClip(...)` construction in Dart tests and loaders only
  where needed; existing call sites should compile unchanged.

## Keyframe Semantics

The setup slot order is `SkeletonData.slots`.

Index direction is visual and binding:

- index `0` is drawn first and is therefore backmost;
- increasing indices draw later and therefore appear in front of lower indices,
  subject to renderer blending/clipping behavior.

Each keyframe is stepped/held:

- sample the last keyframe whose `time <= sampleTime`;
- before the first keyframe, use setup slot order. This lets clips carry a
  later first draw-order key without changing rest/setup samples;
- after the last keyframe, hold the last keyframe;
- no interpolation and no curve field.

Each keyframe stores slot offsets relative to setup/list order:

- Every named offset is `{slot, offset}`.
- `offset` is signed and means `targetIndex = setupIndex(slot) + offset`.
- Slots absent from the keyframe have an implicit offset `0`.
- After combining explicit and implicit offsets, target indices must be exactly
  the integer set `0..slotCount-1`. Duplicates, gaps, negative indices, and
  indices `>= slotCount` are invalid.
- The sampled order is the slots sorted by target index.
- A restore-to-setup keyframe is valid with `offsets: []`.

This makes the JSON readable, compact for small changes, and deterministic for
all permutations. It also prevents ambiguous "move one slot onto another slot's
setup position" data; the displaced slots must carry offsets too.

Explicit zero offsets are reader-tolerant but not canonical:

- JSON and `.bnb` loaders accept `offset == 0` when the rest of the keyframe is
  valid.
- Validators normalize zero-offset entries away before duplicate/permutation
  checks.
- Canonical writers omit zero-offset entries.
- A keyframe whose offsets all normalize away is equivalent to `offsets: []`.

## JSON Shape

Add an optional `drawOrderTimeline` object to each animation clip:

```json
{
  "name": "wave",
  "drawOrderTimeline": {
    "keyframes": [
      {
        "t": 0.0,
        "offsets": [
          {"slot": "front_arm", "offset": 1},
          {"slot": "torso", "offset": -1}
        ]
      },
      {"t": 0.5, "offsets": []}
    ]
  }
}
```

Canonical rules:

- Omit `drawOrderTimeline` when absent.
- Do not emit an empty declared timeline; loaders reject it.
- `keyframes` is required when the object exists and must contain at least one
  keyframe.
- Key times are `t`, f32-quantized, non-negative, and strictly increasing.
- `offsets` is optional per keyframe and defaults to `[]`.
- Inside one keyframe, offsets are canonicalized by setup slot order, not
  lexical slot name, so canonical JSON is stable under slot names and matches
  the permutation basis.
- Offset entries with `offset == 0` are accepted by loaders and normalized away;
  canonical writers omit them.

Update canonical animation clip field order to:

1. `name`
2. `boneTimelines`
3. `slotTimelines`
4. `drawOrderTimeline`
5. `deformTimelines`
6. `eventTimelines`

Empty omission keeps legacy clips byte-identical even though the conceptual
order gains a new optional field.

## `.bnb` Shape

Add one child object family under `animationClip`:

- type id: `drawOrderTimeline`
- parent: most recent `animationClip`
- property: `drawOrderKeys` bytes

Registry guidance:

- Allocate the next unused M3 timeline-family type key and property key after
  checking `registry/wire.yml` at implementation time.
- Document the M3 allocation as "animated timeline record" even though
  `registry/key-ranges.md` mentions broad draw-order capability in M2. Do not
  allocate a static draw-order field in M2 for this change.
- Update `animationClip` docs to say child records are emitted in
  bone, slot, draw-order, deform, event order.

Packed `drawOrderKeys` layout:

```text
varuint keyCount
repeat keyCount:
  f32 time
  varuint offsetCount
  repeat offsetCount:
    varuint slotIndex
    svarint offset
```

Constraints:

- `slotIndex` resolves against loaded setup slot order.
- Key times are strictly increasing.
- Offset entries within one keyframe are sorted by `slotIndex` in canonical
  emission and must not duplicate a `slotIndex`.
- The decoded keyframe must pass the same permutation validation as JSON.
- A keyframe with `offsetCount == 0` restores setup order.

## Loader Validation

JSON parser responsibilities in `loader_animation_parsers.dart`:

- Parse `drawOrderTimeline` beside existing animation-level timelines.
- Reject non-object `drawOrderTimeline`.
- Reject empty `keyframes`.
- Parse `t` through `quantizeF32`.
- Reject negative time.
- Parse optional `offsets`, defaulting to `[]`.
- Reject unknown slots with a diagnostic shaped like existing unknown slot
  errors: `animations[$i](name).drawOrderTimeline.keyframes[$k].offsets[$j]:
  unknown slot: <slot>`.
- Reject duplicate slots within one keyframe.
- Reject out-of-range target indices.
- Reject duplicate or missing target indices after implicit zero offsets.
- Include draw-order keys in animation duration calculation.
- Normalize zero-offset entries away before duplicate/permutation validation.

Validation responsibilities in `loader_validation.dart`:

- Revalidate model-constructed `DrawOrderTimeline` instances, not only JSON
  parse-time data, so `.bnb` and direct constructors share the same checks.
- Keep the same diagnostics family as bone/slot timeline validation.

## Runtime Evaluation

Add sampler:

```dart
List<String> sampleDrawOrderTimeline(
  DrawOrderTimeline timeline,
  List<SlotData> setupSlots,
  double time,
)
```

The sampler returns slot names in sampled order. It should be pure and tested
without the full mixer.

Add draw order to mixed pose:

- Add `drawOrder: List<String>?` or a small `_MixedDrawOrder` record to
  `MixedPose`.
- Treat draw order like attachment/deform channels:
  - thresholded by `track.mixAttachmentThreshold`;
  - stepped and non-interpolated;
  - last winning entry in track application order wins, matching existing
    map-overwrite behavior for attachments/deforms.

Update `applyPose`:

- Build attachment updates by slot name before reordering slots.
- If a sampled draw order exists, construct `animSlots` in sampled order while
  preserving each slot's `name` and `bone`, and applying any attachment override
  for that slot.
- Rebuild `SkeletonData` through `copyWith` or an exhaustive constructor call
  that preserves every field, including constraints, attachments, skins,
  animations, state machines, and `deformOverrides`.
- If only draw order changed, avoid unnecessary bone rebuild but still return a
  skeleton with reordered `slots`.

Draw batches:

- No new sort should be added to `buildDrawBatches`; it already iterates
  `data.slots`.
- Tests must prove that `applyPose` followed by `buildDrawBatches` yields batch
  slot order matching the sampled timeline.
- Tests must also cover clipping because `_applyClipping` uses slot order to
  compute covered ranges.

Clipping interaction:

- Clipping ranges are evaluated against the sampled slot order after
  draw-order animation and attachment animation have been applied.
- Any sampled draw-order keyframe is invalid if it can place a clipping
  attachment's owning slot at or after its `untilSlot`, or if two active
  clipping ranges overlap in that sampled order.
- The shared validator should check this conservatively from declared
  draw-order keyframes and known clipping attachments. If the implementation
  cannot prove a clip range remains valid because attachment timelines make
  activation time-dependent, it must reject the combination or split a follow-up
  design bead; it must not silently let clipping disappear or reverse at runtime.

## Nim and Cross-Runtime Scope

The request targets Dart adoption, but this is a bony format feature. Final
format/conformance completion requires Nim support in the same implementation
track:

- Nim model/timeline types and validation.
- Nim JSON load and canonical JSON write.
- Nim `.bnb` semantic encode/decode for `drawOrderTimeline` child records.
- Nim mixer/evaluator behavior matching the Dart semantics above.
- CLI conversion paths that preserve draw-order timelines through
  `json-to-bnb` / `bnb-to-json`.

Dart `.bnb` writing may remain out of scope until the Dart canonical writer
exists, but new `.bnb` fixtures must not be committed until Nim canonical
conversion can generate and verify them. Do not claim Dart↔Nim byte parity until
both runtimes can read/write the same canonical assets through the applicable
writer paths.

## Flashy Adoption Handoff

The only Flashy-facing deliverable in bony is a short handoff note:

- resulting bony commit SHA;
- supported JSON shape and Dart API field names;
- statement that Flashy can delete its draw-order envelope field after repin.

No Flashy files should be edited by this bony implementation task graph.
