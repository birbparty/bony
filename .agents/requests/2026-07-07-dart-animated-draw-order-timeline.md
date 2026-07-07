# Request: Animated draw-order timeline in the Dart runtime model + I/O

- **Requested by:** `flashy` planning in `~/git/flashy` (big-change prompt
  `.agents/big-change-prompts/09-slot-animated-draw-order.md`, "model animated
  draw order + slot blend modes" product-decision row; step 2 of 2 after the
  slot blend-mode work in `08-slot-blend-modes.md`)
- **Date:** 2026-07-07
- **Priority:** Medium — **non-blocking**. Flashy will ship animated draw order
  now via a Flashy-local `FlashyEditorEnvelope` field keyed by clip name (the
  same editor-only-bridge workaround it uses for IK and slot blend modes).
  This request is the upstream *home* that lets that workaround be retired, not
  a gate on the Flashy feature landing.
- **Target repo:** `~/git/bony` (`runtime-dart`)
- **Consumer:** `~/git/flashy` (Flutter editor; local path dependency on
  `runtime-dart`, currently pinned at `239d091`)
- **Sibling request:** the slot blend-mode wire property already flagged as
  out-of-scope in `2026-07-07-dart-canonical-bony-writer.md`. Draw order is the
  same class of gap (an editor-authored animation channel with no bony home)
  and could be delivered alongside it.

## Background

Flashy is adding **animated (keyed) slot draw order** — a clip can re-stack
slots over time (e.g. an arm crossing in front of a torso), authored in the
timeline, evaluated with hold/step semantics, rendered, and persisted. This is
a first-class animation channel that belongs in the skeleton's animation data.

At bony `239d091`, `runtime-dart` has **no draw-order representation**, animated
or static:

- `SlotTimelineKind`
  (`runtime-dart/lib/src/model/animation_model.dart:46`) is
  `{ attachment, rgba, rgb, alpha, rgba2, sequence }` — no draw-order member.
- `AnimationClip` (`:273`, fields `:284-285` plus deform/event) carries only
  `boneTimelines`, `slotTimelines`, `deformTimelines`, and `eventTimelines` —
  there is no draw-order/zOrder timeline.
- The loader
  (`runtime-dart/lib/src/loader_animation_parsers.dart:253/301/358/438`) reads
  `boneTimelines`, `slotTimelines`, `deformTimelines`, `eventTimelines` and
  nothing else at the animation level; there is no `drawOrder` key.
- The animation applier
  (`runtime-dart/lib/src/anim.dart:1159/1178`) iterates only bone and slot
  timelines, so even if data existed nothing would re-order draw batches.

Because bony has no home for this data, Flashy's plan currently rides draw-order
timelines in `FlashyEditorEnvelope` keyed by clip name
(`~/git/flashy/lib/model/envelope.dart`, mirroring the existing
`ikTimelinesByClip` field). This is the same drift-prone hand-maintained
workaround that the canonical-writer request
(`2026-07-07-dart-canonical-bony-writer.md`) exists to eliminate: an
editor-authored animation channel that the shared runtime cannot round-trip, so
Flashy must serialize and re-parse it itself and chase every schema change by
hand. Precedent is good — the previous `BoneData.copyWith` ask (bead
`flashy-pobr`) landed and was adopted.

## Model note (offset-based, like Spine — do not conflate with a static field)

Spine (and DragonBones) model **animated** draw order as a **clip-global
timeline of keyframes**, each keyframe carrying a set of *slot offsets from the
setup/list order* (a permutation delta), not per-slot absolute z-indexes baked
into `SlotData`. This is distinct from any *static* per-slot stacking field.
`eventTimelines` (`animation_model.dart:264` — "clip-owned, clip-global … no
target") is the right structural precedent: one timeline per clip, no per-slot
target, an ordered keyframe list.

Flashy models its editor-side authoring as per-slot z-index keyframes for
timeline-row ergonomics, but resolves them to a concrete slot render order per
frame, so it can emit whatever wire shape bony chooses. Flashy defers to bony
on the canonical wire representation — offset-based keyframes are expected.

## Blocking asks

*(None — this request does not block the Flashy feature. The items below are the
work needed for Flashy to drop its envelope workaround.)*

## Asks

### 1. Draw-order timeline in the animation model

Add a clip-global draw-order timeline to `AnimationClip`
(`runtime-dart/lib/src/model/animation_model.dart:273`), modeled on the
`eventTimelines` clip-global precedent: an ordered list of keyframes, each
keyframe holding the slot-order offsets that apply from that time forward
(step/hold semantics — draw order does not interpolate). Name and exact shape
are bony's call; document it in the model the way other timelines are.

### 2. Loader parse + validation

Parse the new animation-level key in
`runtime-dart/lib/src/loader_animation_parsers.dart` alongside the existing
`boneTimelines`/`slotTimelines`/`deformTimelines`/`eventTimelines` (`:253` ff),
and validate referenced slots exist (reuse the slot-existence checks in
`loader_validation.dart`, e.g. the `unknown slot` diagnostics near `:863`).

### 3. Apply / evaluation in the runtime

Apply the timeline in the animation mixer (`runtime-dart/lib/src/anim.dart`,
alongside the bone/slot application at `:1159`/`:1178`) so draw batches are
re-ordered per frame with step/hold semantics and a defined tie-break for slots
absent from the timeline (setup/list order).

### 4. Canonicalization (writer path)

Include the new timeline in the canonical-emission contracts
(`docs/json-canonicalization.md`, and `docs/binary-canonicalization.md` if the
`.bnb` writer covers it) — total key order, default omission (omit when empty so
legacy clips are byte-identical), and any offset normalization — so it round-
trips through the requested `writeBonyJson`/`.bnb` writer and stays Dart↔Nim
byte-parity. This ask depends on the canonical-writer request landing first.

## Out of scope

- **Static** per-slot stacking overrides (DragonBones `DbSlot.zOrder`) — a
  separate, non-animated concern Flashy handles on the DragonBones import side;
  not this timeline.
- Flashy's editor-side authoring UI, timeline row, and DragonBones `zOrder`
  export/degradation — those stay in Flashy regardless of this request.
- Nim runtime parity work beyond what Dart↔Nim conformance requires.

## Acceptance

- `AnimationClip` exposes a draw-order timeline; `loadBonyJson` parses it and
  rejects references to unknown slots with a documented diagnostic.
- The runtime applies it so a loaded clip visibly re-stacks slots over time with
  step/hold semantics.
- Once the canonical writer exists, the timeline round-trips
  (`loadBonyJson(writeBonyJson(d))` value-equal to `d`) and is omitted when
  empty so legacy clips are byte-identical; Dart↔Nim byte-parity holds over the
  conformance assets.
- A commit SHA is recorded in the response for Flashy to re-pin; on adoption
  Flashy deletes the `FlashyEditorEnvelope` draw-order field and routes `.bnr`
  draw order through the bony timeline directly.

## References

- Flashy plan: `~/git/flashy/.agents/big-change-prompts/09-slot-animated-draw-order.md`
- Flashy envelope workaround precedent (IK): `~/git/flashy/lib/model/envelope.dart`
  (`ikTimelinesByClip`)
- Sibling / prior request: `~/git/bony/.agents/requests/2026-07-07-dart-canonical-bony-writer.md`
  (see its "Out of scope" blend-mode note)
- Bony model: `runtime-dart/lib/src/model/animation_model.dart:46` (SlotTimelineKind),
  `:264` (eventTimelines clip-global precedent), `:273` (AnimationClip)
- Bony loader: `runtime-dart/lib/src/loader_animation_parsers.dart:253/301/358/438`
- Bony apply: `runtime-dart/lib/src/anim.dart:1159/1178`
- Bony contracts: `docs/json-canonicalization.md`, `docs/binary-canonicalization.md`,
  `docs/load-validation-contract.md`
