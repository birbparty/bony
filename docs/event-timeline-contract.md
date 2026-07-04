# Event Timeline Contract

Status: **binding**. Owner bead: `bony-0ofc` (M3 event-timeline milestone, prompt 27).

This contract defines the `bony`-owned **event timeline**: a clip-owned animation
track of keyframed, application-facing **events** that fire when playback crosses a
keyframe time. Unlike bone, slot, and deform timelines it has **no bone/slot/attachment
target** — it is **clip-global**. Each keyframe carries a `time` and an `EventData`
payload (a named event with optional integer/float/string values and audio metadata).
Events are **not interpolated**: an event either fires or it does not, so — unlike
bone/slot/deform — the packed payload has **no curve tail**.

This slice specifies the **format**, the **load-time validation**, and — normatively,
for prompts 28–30 to implement — the **packed `.bnb` byte layout**, the **`animationEvents`
dispatch output channel**, and the incremental per-sample stepping model. The runtime
types (`EventData`, `EventKeyframe`, `EventTimeline`), the `AnimationClip.eventTimelines`
field, the `eventTimeline` constructor, the validators (`validateEventName`,
`ensureEventSorted`, `validateEventTimeline`), and the entire mixer dispatch path
(`DispatchedEvent`, `dispatchEvents`, `advancePlaying`, `update`) **already exist** in
`runtime-nim/src/bony/anim/timelines.nim` and `runtime-nim/src/bony/anim/mixer.nim`,
but are **entirely non-serialized and unreachable from any asset**. No JSON/`.bnb`
loader, `cli` golden emission, conformance rig, or Dart runtime logic is part of this
slice; those land in prompts 28 (runtime wiring), 29 (conformance gate), and 30 (Dart
parity).

The event-timeline model, field names, packed byte layout, and dispatch semantics are
**project-owned** — they mirror `bony`'s own pre-existing runtime types in
`anim/timelines.nim` / `anim/mixer.nim`, chosen from generic animation terminology and
not derived from any third-party runtime (see `docs/PROVENANCE.md` and
`docs/CLEANROOM.md`). `docs/comparable-feature-set.md` ("Events and audio" / "Animation
timelines") justifies the capability category only, **not** the design.

> **Not to be confused with state-machine listener events.** `bony` has a separate,
> already-shipped M8 feature — `StateMachineListenerEvent`
> (`runtime-nim/src/bony/statemachine/core.nim:63`), surfaced as the numeric golden's
> top-level **`events`** array by `stateMachineEventsJson` (`cli/bony_cli.nim:1693,1742`).
> That is a state-machine transition/enter/exit listener. This contract is the *other*
> event concept: per-clip, keyframed, value-carrying events dispatched during animation
> playback. Its golden channel therefore uses the distinct key **`animationEvents`** (see
> "Dispatch output channel") so it never collides with the M8 listener `events` array.

## Model

An event timeline is a **clip-owned child record**, a fourth timeline family authored
alongside bone, slot, and deform timelines:

- An animation clip owns an array of event timelines. The runtime `AnimationClip`
  **already carries** an `eventTimelines` field (`timelines.nim:162`), and `animationClip`
  already accepts and validates an `eventTimelines` parameter (`timelines.nim:673–678,
  714`). This contract pins the serialized record shape that field holds. The owning wire
  record (an `eventTimeline` typeKey following the parent `animationClip`) and the
  root-level `eventTimelines` collection are added by the registry/codegen slices
  (`bony-0ofc.3`+); the JSON loader that populates the field is prompt 28.
- An event timeline mirrors `EventTimeline` (`timelines.nim:112–113`): just an ordered
  list of keyframes. It has **no target** — no `bone`, `slot`, `attachment`, or `skin`.
- Each keyframe mirrors `EventKeyframe` (`timelines.nim:108–110`): a `time` and an
  `EventData` payload. `EventData` (`timelines.nim:99–106`) has exactly these fields:
  - `name` (string, required) — the event name. Non-empty (`validateEventName`).
  - `intValue` (integer) — an application-facing signed 32-bit integer
    (`int32`). Default `0`.
  - `floatValue` (number) — an application-facing float. Declared `float64` in the
    runtime but **`f32`-quantized** on construction (`docs/float-math-contract.md`).
    Default `0.0`.
  - `stringValue` (string) — an application-facing string. **May be empty.** Default `""`.
  - `audioPath` (string) — an audio-asset path (metadata only; see the non-goal below).
    **May be empty.** Default `""`.
  - `volume` (number) — audio-playback volume metadata. Declared `float64`,
    `f32`-quantized. Default `1.0`. **Carried verbatim — not range-clamped** (see edge
    case (e)).
  - `balance` (number) — audio-playback stereo-balance metadata. Declared `float64`,
    `f32`-quantized. Default `0.0`. **Carried verbatim — not range-clamped.**

- **Canonical-JSON form.** Each animation clip gains an optional `eventTimelines` array
  (absent/empty when a clip has no events). Each event timeline is an object with a
  `keyframes` array (`minItems: 1`). Each keyframe mirrors the readable timeline-keyframe
  convention used by bone/slot/deform (`spec/bony.schema.json`: keyframes key their time
  as **`t`**, not `time`):

  ```json
  {
    "t": <number>,
    "name": <string>,
    "intValue":    <integer, optional, default 0>,
    "floatValue":  <number,  optional, default 0.0>,
    "stringValue": <string,  optional, default "">,
    "audioPath":   <string,  optional, default "">,
    "volume":      <number,  optional, default 1.0>,
    "balance":     <number,  optional, default 0.0>
  }
  ```

  Only `t` and `name` are required per keyframe; the remaining `EventData` fields default
  to the `eventData` constructor defaults above (`timelines.nim:462–479`). The exact
  optional/required partition and defaults are minted by the codegen slice
  (`canonical_json_overrides` / `spec/defaults.yml`).

**No top-level scalar properties.** Unlike the deform timeline (which hoists `skin`/`slot`/
`attachment`/`vertexCount` to registry properties), the `eventTimeline` record has **no
bone/slot target and no object-level scalars**. The **entire** keyframe list — `time` and
every `EventData` field — is encoded inside a single packed bytes property, **`eventKeys`**
(M3 propertyKey `2005`). The `eventTimeline` objects entry therefore carries **only**
`eventKeys`; it does **not** reuse `timelineKeys` (`2004`), `slotIndex`, or `boneIndex`.
See "Packed `eventKeys` byte layout".

### Ordering rule — non-decreasing (NOT strictly increasing)

Event keyframe times are **non-decreasing**: two events **may fire at the same time**.
This mirrors `ensureEventSorted` (`timelines.nim:245–248`), which rejects only a
*decreasing* adjacent pair (`keys[i-1].time > keys[i].time`) — equal adjacent times are
accepted. This is **deliberately different** from the **strictly-increasing** rule that
bone, slot, and deform timelines use (`ensureSorted`, `timelines.nim:239–242`, which
rejects `>=`, i.e. equal times too). Prompts 28/30 MUST apply the non-decreasing rule to
event timelines and MUST NOT accidentally apply the strict rule.

### Audio is metadata only (normative non-goal)

`audioPath`, `volume`, and `balance` are carried as **application-facing data**. The
`bony` runtime **never** opens, decodes, mixes, or plays audio — not now and not in any
future slice of this milestone. These fields are pure passthrough metadata for a host
application to act on. This matches the `docs/comparable-feature-set.md` "Events and
audio" note that audio playback stays outside the core runtime.

## Load-validated invariants

An event timeline is rejected at load unless all hold. These invariants **restate** the
existing standalone validators `validateEventName` (`timelines.nim:210–212`),
`quantizeTime` (`:215–218`), `ensureEventSorted` (`:245–248`), `requireKeys`
(`:251–253`), `validateEventData` (`:256–260`), and `validateEventTimeline`
(`:263–267`), plus the clip-level event validation loop (`animationClip`,
`timelines.nim:714`). The prompt-28 loader reuses these same procedures via the
`eventTimeline` constructor (`:593–597`); it adds no event-specific resolution rules
(an event timeline has no target to resolve).

1. **At least one keyframe** — `keyframes.len ≥ 1` (`requireKeys`; a declared-but-empty
   event timeline is a schema violation).
2. **Non-negative, quantized key times** — every keyframe `time`, after `f32`
   quantization, is `≥ 0` (`quantizeTime` raises on a negative result).
3. **Non-decreasing times** — `keyframes[i].time ≥ keyframes[i-1].time` for every
   adjacent pair; a strictly *decreasing* pair is rejected, but **equal times are
   allowed** (`ensureEventSorted`).
4. **Non-empty event name** — every keyframe's `event.name` is non-empty
   (`validateEventName`).
5. **Quantizable value floats** — every keyframe's `floatValue`, `volume`, and `balance`
   are `f32`-quantized (`validateEventData` re-quantizes them as a round-trip check,
   per `quantizeF32`/`docs/float-math-contract.md`). They are **not** range-checked
   (see edge case (e)).

All float components (`time`, `floatValue`, `volume`, `balance`) are quantized to `f32`
on construction per `docs/float-math-contract.md`; the same `1e-4` cross-runtime
tolerance governs the dispatch-channel comparison below. `quantizeF32`
(`runtime-nim/src/bony/model.nim`) is applied to each value at construction
(`eventData`, `timelines.nim:462–479`) and `quantizeTime` to each keyframe `time`
(`eventKeyframe`, `:495`).

## Load edge cases (normative)

The lettered cases below are the canonical rejection enumeration; each is checkable by
the standalone validators today (an event timeline needs no skeleton context to
validate).

| Case | Rule |
|---|---|
| (a) empty `name` on any keyframe | **Reject** — an event must be named (`schemaViolation`, `validateEventName`). |
| (b) a negative keyframe `time` after `f32` quantization | **Reject** — key times must be non-negative (`schemaViolation`, `quantizeTime`). |
| (c) a strictly *decreasing* adjacent time pair | **Reject** — times must be **non-decreasing** (`schemaViolation`, `ensureEventSorted`). **Equal adjacent times are accepted** (two events at the same time), unlike the strict bone/slot/deform rule. |
| (d) zero keyframes on a declared event timeline | **Reject** — an event timeline must contain at least one keyframe (`schemaViolation`, `requireKeys`). |
| (e) `volume` / `balance` outside any particular range | **Accepted, carried verbatim.** The runtime imposes **no** `0..1` / `-1..1` (or any) clamp on `volume`/`balance`/`floatValue`: `eventData` only `f32`-quantizes them (`timelines.nim:474,477–478`) and the mixer copies the event through unchanged (`mixer.nim:217,224`). `quantizeChannel`'s `0..1` clamp (`timelines.nim:221–224`) applies to **colors only**, never events, and the mixer's `clamp01` (`mixer.nim:95`) applies to track alpha/weights, never event fields. This contract invents **no** clamp the runtime does not have. |

## Packed `eventTimeline` byte layout (`.bnb`)

The keyframe payload is carried by the **`eventKeys`** property (M3 propertyKey `2005`,
`backingType: bytes`), minted by the registry/codegen slices. The property's
`x-bony-packedBytes` `layout` reference in the generated wire schema points at this
section's stable anchor
(`docs/event-timeline-contract.md#packed-eventtimeline-byte-layout-bnb`), set in
`PACKED_BYTES_METADATA` (`codegen/generate.py`) keyed by `eventKeys` — a **new** entry,
**not** a reuse of `timelineKeys` (`2004`), which already points at the curve-tailed
bone/slot layout. (The anchor is named after the **record** — `eventTimeline` — mirroring
the deform contract's `#packed-deformtimeline-byte-layout-bnb`, even though the carrying
property is `eventKeys`.)

**Strings intern into the global string table (`varuint` index, NOT inline bytes).**
Each of the three per-keyframe strings (`name`, `stringValue`, `audioPath`) is encoded in
the payload as a **`varuint` string-table index** — the same global-string-table mechanism
that packed payloads already use for their internal strings — **not** as an inline
`length` + UTF-8 run. This is **required** by the binding canonicalization contract, not a
free choice: `docs/binary-canonicalization.md` §String Table mandates that the canonical
writer "visit every string encoded anywhere inside emitted payloads, including strings
nested inside future composite payloads" (`binary-canonicalization.md:117–118`) and, for
this animation/state-machine slice specifically, that "if a future … packed payload
includes strings, those strings **must be interned** at the point they are visited by that
payload's explicitly declared packed field order" (`:215–218`); the M6 byte-stability gate
checks exactly this (`:298–299`). So an inline encoding of `eventKeys` strings is **not** a
conformant option. (This supersedes prompt 27's provisional "inline lengths"
recommendation, which prompt 27 explicitly gated on this very confirmation against
`docs/binary-canonicalization.md`.)

`eventKeys` is **not** new machinery: string-bearing packed payloads already exist and
already intern into the global table — deformer `blendAxes`
(`writeBlendAxesPayload`/`readBlendAxesPayload`, `binary/semantic.nim:460–480`) and IK
constraint `bones` (`writeBonesPayload`/`readBonesPayload`, `:508–525`) — so prompt 28
**reuses** the existing `intern`/`stringAt` mechanism (`binary/framing.nim`) rather than
adding a first-of-its-kind traversal. (Prompt 27's premise that this would be "the first
string-bearing packed payload" is inaccurate; the precedent proves feasibility on both
encode and decode.) The `deformAttachment` string, by contrast, is an **object-level**
property, not a packed-payload-internal string — the packed-payload precedents to follow
are `blendAxes` and IK `bones`.

**Interning traversal order (row-major — pin for byte parity).** The canonical writer
visits keyframes by **ascending key index** (`binary-canonicalization.md:210`, and
array-like payloads "by ascending element index" `:121`), and within each keyframe the
three strings in field order `name`, `stringValue`, `audioPath`. The full traversal is
therefore `key0.name, key0.stringValue, key0.audioPath, key1.name, …` (row-major, **not**
column-major). Prompt 28 MUST intern in this order so the emitted string-table indices —
and thus the bytes — match across runtimes.

Empty strings still intern: `stringValue`/`audioPath` may be empty, and the empty string
interns as an ordinary **first-seen** table entry the index points at (it is **not** a
reserved index `0`; `intern("")` succeeds via `framing.nim`); `name` is non-empty (edge
case (a)). The string table is emitted as a top-level section
(`binary-canonicalization.md` header `bit1`, `:270`) parsed **before** the object stream
(section order `:45–56`), so it is fully populated and resolvable when an `eventKeys`
payload is decoded — exactly as `blendAxes`/`bones` resolve their indices via
`table.stringAt(index)` today.

**`intValue` is a signed varint (svarint), NOT a fixed 4-byte i32.** `bony` encodes
every signed integer on the wire as a zigzag LEB128 varint via `writeVarint`
(`binary/framing.nim:103–105`: `(value << 1) xor (value >> 63)`), read back by
`readVarint`. This is the type `docs/binary-canonicalization.md:66–67` calls **`varint`**;
this contract writes **`svarint`** as a reminder it is the *signed* zigzag form, but it is
the same encoding — no new wire type is minted. `eventKeys` follows that established
convention rather than a fixed-width i32. (This supersedes prompt 27's provisional "i32
intValue" prose, corrected during grounding — see
`.agents/plans/event-timeline-grounding-findings.md` §3. `EventData.intValue` remains an
`int32` in memory; only its wire encoding is pinned as `svarint`/`varint`.)

**The three value floats are 4-byte `f32`.** `floatValue`, `volume`, and `balance` each
pack as a **4-byte little-endian IEEE-754 `f32`**, NOT 8-byte `f64` — the runtime
`float64` declaration is in-memory only, and every value is `f32`-quantized on
construction, so `f32` on the wire is lossless. This mirrors every other timeline float
payload (`writeF32To` → `writeF32Payload`, `binary/semantic.nim`).

**No curve tail.** Events are not interpolated, so — unlike bone/slot/deform keyframes —
an event keyframe has **no `curve`** field and the payload carries **no curve tail**. An
implementer MUST NOT reuse `writeTimelineKeys`' curve serialization
(`binary/semantic.nim`) for `eventKeys`.

The payload byte layout is **frozen**:

```
varuint  keyCount              (≥ 1; a zero count is a load error)

# keyCount * (
f32      time                  (little-endian IEEE-754; f32-quantized, non-negative,
                               non-decreasing across keys)
varuint  nameIndex             (global string-table index of the UTF-8 name; the
                                name is non-empty, so it interns a non-empty entry)
svarint  intValue              (zigzag LEB128 signed varint, per writeVarint;
                                NOT a fixed 4-byte i32)
f32      floatValue            (little-endian IEEE-754; f32-quantized)
varuint  stringValueIndex      (global string-table index of the UTF-8 stringValue;
                                MAY reference the empty-string entry)
varuint  audioPathIndex        (global string-table index of the UTF-8 audioPath;
                                MAY reference the empty-string entry)
f32      volume                (little-endian IEEE-754; f32-quantized; carried verbatim)
f32      balance               (little-endian IEEE-754; f32-quantized; carried verbatim)
# )
```

The leading `varuint keyCount` mirrors the count prefix used by other packed timeline
payloads; the reader rejects `keyCount == 0`. Each string field is a `varuint` index into
the global string table (see "Strings intern…" above); the three strings per keyframe are
interned in the field order `name`, `stringValue`, `audioPath`. All `f32` fields are
quantized via `quantizeF32` on load. Every string index must resolve to an existing
string-table entry; an out-of-range index, or any trailing bytes after the declared
`keyCount` keyframes, is a load error.

## Dispatch output channel

> **Normative here; first EMITTED in prompt 28 and VERIFIED in prompt 29.** This slice
> fixes the channel name and per-event shape and the stepping model; no runtime emits or
> tests it yet. Prompt 30 (Dart) must match this exactly.

Dispatched events (`AnimationState.events`, a `seq[DispatchedEvent]`,
`mixer.nim:93`) are surfaced in the numeric golden under a **distinct, project-owned**
top-level key **`animationEvents`** — chosen because the top-level `events` key is already
taken by the M8 state-machine listener array (`cli/bony_cli.nim:1742`). Each entry
flattens `DispatchedEvent` (`mixer.nim:54–57`) + its `EventData`:

```json
{
  "name":        <string>,
  "trackIndex":  <integer>,
  "time":        <number>,
  "intValue":    <integer>,
  "floatValue":  <number>,
  "stringValue": <string>,
  "audioPath":   <string>,
  "volume":      <number>,
  "balance":     <number>
}
```

Comparison rule: `name`/`stringValue`/`audioPath`/`trackIndex`/`intValue` compare
**exactly**; `time`/`floatValue`/`volume`/`balance` compare within the `1e-4` tolerance of
`docs/float-math-contract.md`.

### Incremental per-sample-window stepping (cross-runtime parity contract)

`dispatchEvents` (`mixer.nim:196–232`) is **delta-based**: it fires the events whose
keyframe time falls in the **half-open window** it is advanced across —
`key.time > fromTime and key.time ≤ toTime` (`mixer.nim:223`) — and `advancePlaying`
**early-returns on a zero advance** (`amount <= 0`, `mixer.nim:236`). (In the non-looping
branch the window end is clamped to `min(toTime, clip.duration)`, `mixer.nim:220`, so an
event authored past `clip.duration` never fires; the normative `{0, 0.5, 1.0}` examples all
sit within `duration`.) `update` **resets**
the dispatched-event list at the start of every call (`state.events.setLen(0)`,
`mixer.nim:264`). The story runner advances **incrementally** by `sample.time -
previousTime` per sample (the physics-story precedent, `cli/bony_cli.nim:1456–1474`).

Therefore, normatively: **`animationEvents` on each golden sample is the set of events
fired in that sample's own inter-sample window** — the per-sample list is **reset between
samples**, not accumulated. Consequences prompts 28/29/30 MUST honor identically:

1. **A sample at `t=0` advances by `0` and fires nothing.** An event authored at `t=0` is
   **not** observed at a `t=0` sample (exclusive-on-`fromTime` firing + the zero-advance
   early return).
2. **With keyframe-aligned samples `{0, 0.5, 1.0}`**, an event at `t=0.5` fires in the
   `(0, 0.5]` window (the mid sample) and an event at `t=1.0` fires in the `(0.5, 1.0]`
   window (the end sample).

Prompt 30's Dart port MUST replay **incrementally** — carry track state across samples
and reset the event list per sample — and MUST NOT use the fresh-runtime / absolute-time
`rt.update(t)` pattern (that would fire the cumulative `[0, t]` window and diverge from the
Nim goldens). Cross-reference the physics story's incremental advance
(`cli/bony_cli.nim:1456–1474`) as the parity precedent, not the deform/mesh setup-pose
pattern.

## Deterministic dispatch (implemented across the runtime)

The dispatch path is **already implemented** and unchanged by this milestone; this
section forward-references it so prompt 28 wires the loader without re-inventing dispatch:

- **`dispatchEvents`** (`mixer.nim:196`) — collects events in the advanced window
  (loop-aware: for a looping clip it walks each crossed cycle, `mixer.nim:207–218`),
  then **stable-sorts** the fired events by `(time, insertion order)` (`mixer.nim:226–230`)
  so co-timed events preserve authoring order.
- **`advancePlaying`** (`mixer.nim:235`) — advances a track by `amount`, early-returning on
  `amount <= 0`. During a mix it withholds dispatch until the track's `mixTime` crosses
  `mixDuration * eventThreshold`, then dispatches from the crossing point
  (`mixer.nim:248–255`).
- **`update`** (`mixer.nim:260`) — the per-frame entry point: quantizes `dt`, rejects a
  negative `dt`, resets `state.events`, and advances every track.
- **`AnimationTrack.eventThreshold`** (`mixer.nim:88`, default `0.5` via `animationTrack`,
  `mixer.nim:127`) — the mix fraction below which a newly-mixed-in track's events are
  suppressed, so a barely-blended-in animation does not fire its events.

## Related contracts

- `docs/float-math-contract.md` — `quantizeF32`, `1e-4` cross-runtime tolerance, `f32`
  quantization.
- `docs/deform-timeline-contract.md` — the sibling clip-owned timeline family this
  contract mirrors structurally; the freshest landed serialize-a-non-serialized-timeline
  template.
- `docs/binary-animation-state-machine-object-families.md` — the clip/timeline
  child-record family an event timeline joins.
- `docs/binary-canonicalization.md` — canonical `.bnb` byte emission and the **binding**
  String Table rule (`:116–118`, `:215–218`, `:298–299`) that requires `eventKeys` strings
  to intern into the global string table rather than encode inline.
- `docs/load-validation-contract.md` — the shared JSON/binary load-validation pass.
- `registry/key-ranges.md` — the M3 band (`2000..2999`, "Animations, timelines, curves,
  mixing"); `eventTimeline` typeKey `2003`, `eventKeys` propertyKey `2005`.
- `.agents/plans/event-timeline-grounding-findings.md` — the grounding pass (`bony-0ofc.1`)
  that pinned the svarint/`f32`/no-clamp decisions above against source.
