# /big-change prompt - contract + format (M3 animation-clip event timeline, format only)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 4** of the M3 event-timeline milestone. Must
> land before `28-runtime-nim-event-timeline.md` (the runtime wiring reads the
> loaded record and the contract this prompt defines). Prompts 29 (conformance)
> and 30 (Dart parity) follow.
> **Candidate category:** comparable-gap.

---

/big-change Introduce the animation-clip "event timeline" (a clip-owned timeline of keyframed, application-facing events that fire when playback crosses a keyframe time) as a binding format contract plus the registry keys, canonical JSON + wire schema, and regenerated codec artifacts for a clip-owned `eventTimeline` record - contract + schema/registry/codegen only. Runtime load/round-trip wiring, mixer dispatch surfacing, and the conformance golden land in prompts 28-30.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony` already has a fully-built but **entirely non-serialized** event-timeline
runtime. The types `EventData`, `EventKeyframe`, `EventTimeline`, the accessor
`eventTimelines*`, and the constructor `eventTimeline*` all exist
(`runtime-nim/src/bony/anim/timelines.nim:99-113, 201, 593`); `AnimationClip`
**already carries an `eventTimelines` field** (`timelines.nim:162`) and
`animationClip*` **already accepts and validates** an `eventTimelines` parameter
(`timelines.nim:673-678, 714`); and the mixer already dispatches them -
`DispatchedEvent` (`anim/mixer.nim:54-57`), `AnimationState.events`
(`mixer.nim:93`), `AnimationTrack.eventThreshold` (`mixer.nim:88`, default `0.5`),
and the dispatch path `dispatchEvents` (`mixer.nim:196`) /
`advancePlaying` (`:235`) / `update*` (`:260`) are all implemented. **But nothing populates a clip's
event timelines from an asset and nothing surfaces the dispatched events:** grep
confirms `event` appears **nowhere** in `jsonio.nim`, `binary/semantic.nim`,
`binary/generated/wire.nim`, `spec/`, or `registry/wire.yml`. The JSON animation
parser `parseBonyAnimations` (`jsonio.nim:811`) does not even accept an
`eventTimelines` key - its `validateKnownKeys(aObj, ["name", "boneTimelines",
"slotTimelines", "deformTimelines"], ctx)` (`jsonio.nim:821`) would **reject** an
authored `eventTimelines` array, and its `animationClip(...)` call
(`jsonio.nim:1018`) never passes one. So the whole event feature is reserved but
unreachable.

> **Do not confuse this with state-machine listener events.** `bony` has a
> *separate*, already-shipped M8 feature - `StateMachineListenerEvent`
> (`runtime-nim/src/bony/statemachine/core.nim:63`), serialized as the numeric
> golden's top-level `events` array by `stateMachineEventsJson`
> (`cli/bony_cli.nim:1693, 1742`) and exercised by `m8_gesture_story_*` goldens.
> That is a state-machine transition/enter/exit listener, **not** a clip-owned
> keyframe event. This milestone is the *other* event concept: per-clip,
> keyframed, value-carrying events dispatched during animation playback. Its
> golden output channel MUST use a distinct key (see below) so it never collides
> with the M8 listener `events` array.

This is the direct analog of the M4 deform-timeline milestone (prompts 23-26),
which serialized a pre-existing non-serialized Nim runtime. Mirror that milestone
closely: this prompt writes the event timeline's **binding contract** and mints
its **wire format** (registry keys + regenerated JSON/wire schema + generated
codecs), so prompt 28 can add the runtime load/round-trip path and surface the
dispatched events.

**Project-owned event model to define (decide and document these).** "Timeline
events / animation events" is a generic capability category
(`docs/comparable-feature-set.md`, the "Events and audio" and "Animation
timelines" rows - capability context only, **not** an implementation source).
The specific record below is `bony`-owned and mirrors the **already-existing**
project types in `anim/timelines.nim`. It must not be derived from any
third-party runtime's fields, wire layout, or naming.

1. An event timeline is a **clip-owned timeline**, a fourth timeline family
   alongside `boneTimelines`, `slotTimelines`, and `deformTimelines` (authored
   under a new `eventTimelines` array on each animation clip). Unlike bone/slot
   timelines it has **no bone/slot target** - it is clip-global. Its serialized
   shape mirrors `EventTimeline` (`timelines.nim:112-113`): just an ordered list
   of keyframes.
2. Each keyframe mirrors `EventKeyframe` (`timelines.nim:108-110`): a `time`
   (f32-quantized, non-negative) and an `EventData` payload
   (`timelines.nim:99-106`): `name` (non-empty string), `intValue` (i32),
   `floatValue` (f64/f32-quantized), `stringValue` (string, may be empty),
   `audioPath` (string, may be empty), `volume` (f32), `balance` (f32).
3. **Ordering rule (decide explicitly, matches the existing validator).**
   Event keyframe times are **non-decreasing** (NOT strictly increasing) - two
   events may fire at the same time. This mirrors `ensureEventSorted`
   (`timelines.nim:245-248`, which uses `>` not `>=`), and is deliberately
   different from the strictly-increasing rule bone/slot/deform timelines use
   (`ensureSorted`, `timelines.nim:239-242`). Pin this difference normatively so
   prompts 28/30 do not accidentally apply the strict rule.
4. **Audio is metadata only (clean-room + scope decision).** `audioPath`,
   `volume`, and `balance` are carried as **application-facing data** - the
   runtime never opens, decodes, or plays audio. This matches the
   `docs/comparable-feature-set.md` "Events and audio" planning note that audio
   playback stays outside the core runtime. Pin this as a normative non-goal.

**Golden / dispatch output channel (load-bearing - decide this explicitly).**
The dispatched events (`AnimationState.events`, a `seq[DispatchedEvent]`) must be
surfaced in the numeric golden so the conformance gate (prompt 29) and Dart
(prompt 30) can prove parity. The top-level `events` key is **already taken** by
the M8 state-machine listener array (`cli/bony_cli.nim:1742`). Pin a **distinct,
project-owned** top-level key for clip-dispatched events - recommend
`animationEvents` - and specify its per-event object shape normatively so prompt
28 emits it and prompt 30 matches it exactly. Recommended shape (each entry
mirrors `DispatchedEvent` `mixer.nim:54-57` + `EventData`):
`{ "name": string, "trackIndex": integer, "time": number, "intValue": integer,
"floatValue": number, "stringValue": string, "audioPath": string,
"volume": number, "balance": number }`. String and integer fields compare
exactly; `time`/`floatValue`/`volume`/`balance` compare within `1e-4`. (Actual
emission is prompt 28; this prompt only fixes the contract for the channel name
and shape.)

**Sampling/stepping model for the channel (load-bearing - pin this normatively;
it is the cross-runtime parity contract).** `dispatchEvents` is **delta-based**:
it fires events in the half-open window it is advanced across
(`mixer.nim:196-232`, `key.time > fromTime`), and `advancePlaying` early-returns on
a zero advance (`mixer.nim:236`). The state-machine story runner advances
**incrementally** by `sample.time - previousTime` per sample
(`cli/bony_cli.nim:1460`). Therefore pin: **`animationEvents` on each golden is
the set of events fired in that sample's own inter-sample window**, i.e. the
per-sample dispatched-event list is **reset between samples** (exactly how the
physics story resets its per-sample state, not accumulated). Consequences that
prompts 28/29/30 MUST honor identically: (i) a sample at `t=0` advances by `0` and
fires **nothing** - an event authored at `t=0` is **not** observed at a `t=0`
sample (exclusive-on-`fromTime` + zero-advance early return); (ii) with
keyframe-aligned samples `{0, 0.5, 1.0}`, an event at `t=0.5` fires in the
`(0, 0.5]` window (the `mid` sample) and an event at `t=1.0` fires in the
`(0.5, 1.0]` window (the `end` sample). Prompt 30's Dart port MUST replay
**incrementally**, carrying track state across samples and resetting the event
list per sample - it must **NOT** use the fresh-runtime/absolute-time
`rt.update(t)` pattern from `m18_deform_story_test.dart` (that would fire the
cumulative `[0, t]` window and diverge from the Nim goldens). Cross-reference the
physics story's incremental advance (`cli/bony_cli.nim:1456-1474`) as the parity
precedent, not the deform/mesh setup-pose pattern.

**Registry-key decision (M3 band `2000..2999` only).** Event timelines are the
**animation** milestone (M3), not M4 - `registry/key-ranges.md:21` scopes M3 as
"Animations, timelines, curves, mixing." Confirm next-free keys against
`registry/wire.yml` before allocating; **at the time of writing** the M3
typeKeys `2000` (animationClip), `2001` (boneTimeline), `2002` (slotTimeline) are
used (`wire.yml:313-330`) so the next-free M3 **typeKey is `2003`**, and the M3
propertyKeys `2000..2004` are used (`boneIndex` `2000` .. `timelineKeys` `2004`,
`wire.yml:934-968`) so the next-free M3 **propertyKey is `2005`**. Allocate:
- typeKey `eventTimeline` = `2003` (mirror the `slotTimeline` typeKey entry at
  `wire.yml:325-330`). It is a **child record owned by the most recent
  animationClip**, exactly like `boneTimeline`/`slotTimeline` (see the objects
  block and the animationClip "followed by owned ... records" doc at
  `wire.yml:313-330, 1268-1278`).
- **Allocate a new M3 bytes property key `eventKeys` = `2005`** for the packed
  event-keyframe payload, with its **own** `PACKED_BYTES_METADATA` entry and its
  **own** `docs/event-timeline-contract.md#...` layout anchor. **Do NOT reuse
  `timelineKeys` (`2004`).** The generator's `PACKED_BYTES_METADATA` is a dict
  **keyed by property id** (`codegen/generate.py:26`) and the schema stamps one
  `x-bony-packedBytes` layout per property (`generate.py:1017-1018`), so a second,
  incompatible layout (no curve tail, inline strings) cannot live on the
  `timelineKeys` key - it already points at the curve-tailed bone/slot layout
  (`generate.py:27`). This mirrors the **landed** deform milestone, which - despite
  prompt 23's text recommending reuse - allocated a distinct `deformKeys` = `3009`
  (`registry/wire.yml:577`) with its own `PACKED_BYTES_METADATA` entry
  (`generate.py:63`) and its own objects-block reference (`wire.yml:1287`). Follow
  the landed pattern, not prompt 23's superseded prose. The `eventTimeline` object
  has no bone/slot target, so it carries **only** `eventKeys`; do not add
  `slotIndex`/`boneIndex`/`timelineKeys`.
- **Decide the string question (this is the load-bearing wire decision).**
  `EventData` carries three per-keyframe strings (`name`, `stringValue`,
  `audioPath`) that vary keyframe to keyframe, so they cannot be hoisted to a
  single object-level string-index property the way `deformAttachment` was.
  Choose ONE and document why: (a) encode each string **inline** in the packed
  `eventKeys` payload as a `varuint length` + UTF-8 bytes run; or (b) encode
  each string as a **varuint string-table index** into the global string table
  (the mechanism `bones`/`deformAttachment` use - confirm from
  `docs/binary-canonicalization.md` whether the string table is reachable from
  inside a packed `bytes` payload during encode/decode, and whether the encoder
  populates it for payload-internal strings). Recommend (a) inline lengths:
  `docs/binary-canonicalization.md` documents that current animation/SM packed
  payloads "use indices and numeric tags, not strings," so option (b) would be the
  first string-bearing packed payload and would need new interning-traversal code
  in the canonical writer plus M6-gate coverage - inline lengths keep the event
  payload self-contained and avoid that. Pin the chosen encoding in the packed
  byte layout below.

**Packed `eventKeys` byte layout for events (pin normatively in the
contract).** Specify it exactly so prompts 28/30 byte-match. Recommended (inline
strings, option (a)): `varuint keyCount`, then per keyframe:
`f32 time`, `varuint nameLen` + name UTF-8 bytes, `i32 intValue`,
`f32 floatValue`, `varuint stringValueLen` + bytes, `varuint audioPathLen` +
bytes, `f32 volume`, `f32 balance`. Event keyframes have **no `curve`** (an event
either fires or does not; there is no interpolation between events), so - unlike
bone/slot/deform - the event payload has **no curve tail**. Call this out
explicitly so an implementer does not try to reuse `writeTimelineKeys`'s curve
serialization (`binary/semantic.nim:787-853`). Pin the anchor heading so the wire
schema `PACKED_BYTES_METADATA` layout reference points at it.

**Edge cases the contract MUST make normative** (otherwise prompts 28/30
diverge; most already enforced by `validateEventName` `timelines.nim:210-212`,
`ensureEventSorted` `:245-248`, and the `animationClip` event validation at
`:714`): (a) empty `name` -> reject (`validateEventName`); (b) a negative
keyframe `time` -> reject; (c) **non-decreasing** (not strict) times - equal
adjacent times allowed, a *decreasing* pair rejected (`ensureEventSorted`);
(d) zero keyframes on an event timeline -> reject (a declared-but-empty timeline
is a schema violation, mirror `requireKeys` `timelines.nim:251-253`);
(e) `volume`/`balance` out of any documented range -> decide and pin (recommend
`volume >= 0`, `balance` in `-1..1`, or explicitly "unconstrained, carried
verbatim" if the existing runtime does not clamp - **confirm against the
`EventData`/`eventTimeline`/`animationClip` code before asserting a bound**;
do not invent a clamp the runtime does not have). Cross-reference
`docs/float-math-contract.md` for the `1e-4` tolerance and f32 quantization.

Concretely, this prompt builds exactly this - **contract + schema/registry/codegen
only** (no runtime loader, no cli output, no conformance rig):

1. **Contract doc**: create `docs/event-timeline-contract.md` as a binding
   contract, cross-linked from `docs/README.md` (add a row beside the deform
   contract - reuse or create an "Animation Timeline Contracts" heading next to
   `deform-timeline-contract.md`). Mirror the heading structure of
   `docs/deform-timeline-contract.md`: Status/owner-bead line;
   cleanroom/provenance paragraph; `## Model`; `## Load-validated invariants`
   with tolerances tied to `docs/float-math-contract.md`; a normative
   `## Edge cases (normative)` table for (a)-(e); a `## Packed byte layout (.bnb)`
   section with a stable heading anchor referenced from the wire schema; the
   non-decreasing-times decision and how it differs from the strict bone/slot
   rule; the **audio-metadata-only** non-goal; a
   `## Dispatch output channel` section pinning the `animationEvents` golden key,
   the per-event object shape, AND the incremental per-sample-window stepping
   model + exclusive-`fromTime` firing semantics above (implemented in prompt 28);
   a forward-reference `## Deterministic dispatch (implemented across the runtime)`
   section that points at the already-existing `dispatchEvents` (`mixer.nim:196`) /
   `advancePlaying` (`:235`) / `update*` (`:260`) path and the `eventThreshold`
   semantics (`mixer.nim:88, 235`); and `## Related contracts`.
2. **Registry** (`registry/wire.yml`, M3 band only): add the `eventTimeline`
   typeKey (`2003`), a new `eventKeys` bytes property key (`2005`), and the
   `eventTimeline` `objects:` entry (mirror `slotTimeline`, but with `eventKeys`
   as its only property and no bone/slot target key). No key collides; all new
   keys in `2000..2999`. Cite this prompt's owning bead in every new entry's `doc`.
3. **Codegen packed-bytes + canonical JSON + defaults**:
   - Add a **new** `PACKED_BYTES_METADATA` entry (`codegen/generate.py:26-45`)
     keyed by `eventKeys` for the event byte layout, with its `layout` pointing at
     the `docs/event-timeline-contract.md` packed-bytes anchor. Do **not** reuse or
     mutate the `timelineKeys` entry (`generate.py:27`). Mirror the landed
     `deformKeys` entry (`generate.py:63`).
   - Add a `canonical_json_overrides()` entry (`generate.py:595`) for
     `eventTimeline` producing the readable JSON shape: a `keyframes` array of
     `{ "t": number, "name": string, "intValue"?: integer, "floatValue"?: number,
     "stringValue"?: string, "audioPath"?: string, "volume"?: number,
     "balance"?: number }`, with sensible defaults for the optional fields.
   - Add `spec/defaults.yml` entries covering every serialized `eventTimeline`
     property exactly once across `objectDefaults` + `requiredProperties`
     (coverage rule `generate.py:307-315`), each `requiredProperties` entry
     carrying `reason` + `ownerBead`.
4. **Codegen regen**: run `python3 codegen/generate.py` to regenerate
   `spec/bony.schema.json`, `spec/bony-wire.schema.json`,
   `runtime-nim/src/bony/generated/wire.nim`, and
   `runtime-dart/lib/src/generated/wire.dart` (do NOT hand-edit these four).
   `python3 codegen/generate.py --check` must pass. Ensure the animation-clip
   JSON `$defs` (`spec/bony.schema.json`, animations at `:90`, deform sub-object
   at `:1108`) gains an optional `eventTimelines` array.
5. **Provenance/cleanroom**: add a `docs/PROVENANCE.md` entry recording that the
   event-timeline schema/field names were taken from `bony`'s own pre-existing
   `anim/timelines.nim`/`anim/mixer.nim` runtime types (not derived from any
   surveyed product), and run the `docs/CLEANROOM.md` new-identifier checklist for
   the net-new serialized names (`eventTimelines`, `animationEvents`, and any new
   registry id).

Keep the record **minimal**: serialized fields are exactly the event keyframe
list (time + `EventData` fields) packed into `eventKeys`. Do NOT touch
`jsonio`/`semantic`/`timelines`/mixer/cli code; do NOT add a conformance rig; do
NOT touch the Dart runtime beyond the regenerated `generated/wire.dart`. The
`eventTimelines` field already exists on `AnimationClip` - do not re-add it.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md (add the event-timeline naming entry)
- Comparable research: docs/comparable-feature-set.md ("Events and audio" /
  "Animation timelines" are named comparable capabilities only - NOT an
  implementation source; do not import any third party's event field set, wire
  layout, or naming)
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4 tolerance)
- Existing (non-serialized) Nim event runtime this milestone wires in:
  runtime-nim/src/bony/anim/timelines.nim (EventData 99-106, EventKeyframe
  108-110, EventTimeline 112-113, AnimationClip.eventTimelines 162, eventTimelines
  accessor 201, eventTimeline ctor 593, animationClip param+validation 673-678/714,
  validateEventName 210, ensureEventSorted 245-248) and
  runtime-nim/src/bony/anim/mixer.nim (DispatchedEvent 54-57, AnimationState.events
  93, AnimationTrack.eventThreshold 88, animationTrack default 127, dispatch path
  196-290)
- The M8 listener event to NOT collide with: runtime-nim/src/bony/statemachine/
  core.nim (StateMachineListenerEvent 63) surfaced by cli/bony_cli.nim
  (stateMachineEventsJson 1693, root["events"] 1742)
- Freshest end-to-end template (mirror closely): the deform format/contract slice
  .agents/big-change-prompts/23-contract-deform-timeline-format.md and its landed
  diff. Diff that as the template for "serialize a pre-existing non-serialized
  clip timeline end to end."
- Registry key bands: registry/key-ranges.md (M3 = 2000..2999, "Animations,
  timelines, curves, mixing"; next-free typeKey 2003, next-free propertyKey 2005)
- Registry source: registry/wire.yml (animationClip 313-318, boneTimeline
  319-324, slotTimeline 325-330; generic property keys boneIndex/.../timelineKeys
  934-968; deformTimeline objects entry near 1268-1278 as the objects-block
  template)
- Codegen: codegen/generate.py (PACKED_BYTES_METADATA 26-45, coverage rule
  307-315, canonical_json_overrides 595, writes 4 files)
- Defaults source of truth: spec/defaults.yml
- Spec animation object: spec/bony.schema.json (animations 90, deformTimelines
  sub-object 1108)
- Docs index: docs/README.md (add the new contract row)
- Repo gate: Makefile `test` + `python3 codegen/generate.py --check`
- Beads: bony-0ofc (this slice; claim with `bd update bony-0ofc --claim`), under
  epic bony-p05f

**Success Criteria**
- `docs/event-timeline-contract.md` exists, is listed in `docs/README.md`, and
  normatively specifies the model, load-validated invariants + tolerances, the
  edge-case table (a)-(e), the packed `.bnb` byte layout (with a heading anchor),
  the non-decreasing-times rule (and its difference from the strict bone/slot
  rule), the audio-metadata-only non-goal, and the `animationEvents` dispatch
  output channel + per-event object shape.
- `registry/wire.yml` gains an `eventTimeline` type (key `2003`) and a new
  `eventKeys` bytes property (key `2005`), with an `eventTimeline` objects entry
  carrying only `eventKeys`; `timelineKeys` (`2004`) is left untouched; no key
  collides; all new keys in `2000..2999`.
- `spec/defaults.yml` covers every serialized `eventTimeline` property exactly
  once; `python3 codegen/generate.py --check` passes.
- Codegen regenerated (both schemas + `generated/wire.nim` + `generated/wire.dart`)
  with no hand-edits; the animation-clip JSON `$defs` gains an optional
  `eventTimelines` array whose items express the readable keyframe/name/value
  shape; `python3 scripts/ci/schema_validate_assets.py` passes for all existing
  assets (they carry no event timelines, so the array is optional and absent).
- The runtime JSON+`.bnb` **round-trip test** of a clip-carried event timeline,
  the load-validation rejections (a)-(e), the mixer dispatch surfacing, and the
  `animationEvents` golden emission are **deferred to prompt 28** - they require
  the `jsonio`/`semantic`/`cli` wiring this prompt intentionally does not touch.
  Do NOT claim or attempt a runtime round-trip test here.
- `docs/PROVENANCE.md` gains the event-timeline naming entry; the
  `docs/CLEANROOM.md` new-identifier checklist is satisfied.
- Update any registry change-detector counts in `runtime-nim/tests/test_smoke.nim`
  (`bonyTypeKeys.len` / `bonyPropertyKeys.len` / `bonyPropertyDefaults.len` /
  `bonyRequiredProperties.len`) to the regenerated totals.
- `make test` passes.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source, importer source, generated definitions,
  exact wire layouts, type/property keys, event field names, or copied docs prose.
  The event-timeline model, field names, and dispatch semantics are project-owned
  (they already exist in `bony`'s own `anim/timelines.nim` and `anim/mixer.nim`).
- Use `docs/comparable-feature-set.md` only to justify the timeline-event
  capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for
  human/legal review.
- Audio is metadata only - no audio decode or playback in the runtime, ever.
- Registry edits: use only the M3 band (`2000..2999`) per `registry/key-ranges.md`
  and follow that file's shared-surface reservation rule.
- Land the registry entry, `defaults.yml`, canonical-JSON overrides, schema
  regen, and codegen together - `validate_sources()` fails if they drift apart.
- Do **NOT** wire the timeline into `jsonio`/`semantic`/`cli`/mixer, add a
  conformance rig/golden, or touch Dart runtime logic in this prompt. Those are
  prompts 28, 29, and 30. This slice ends when the `eventTimeline` record exists
  in the registry and both schemas, the codegen artifacts are regenerated, and the
  contract doc is written - but no runtime loads, validates, round-trips, or
  dispatches it from an asset yet (that is prompt 28).
- Keep the slice to one meaningful implementation session: contract doc +
  registry key(s) + codegen/schema regen + provenance, no runtime code. Natural
  cut line if it runs long: **unit A** = contract doc + registry key + `objects:`
  entry; **unit B** = codegen (`PACKED_BYTES_METADATA`/`canonical_json_overrides`/
  `defaults.yml`) + four-file regen with `codegen --check` green + provenance.
  Do not land unit A leaving `codegen --check` red.
