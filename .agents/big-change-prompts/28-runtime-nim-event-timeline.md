# /big-change prompt - Nim runtime event-timeline load, round-trip, and dispatch surfacing

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 4** of the M3 event-timeline milestone. Depends
> on `27-contract-event-timeline-format.md` (the registry keys, packed byte
> layout, and `animationEvents` golden channel it defines). Must land before
> `29-conformance-event-anim-gate.md` (which needs the golden emission) and
> `30-dart-event-timeline-parity.md` (which mirrors this runtime seam).
> **Candidate category:** comparable-gap.

---

/big-change Wire the pre-existing Nim event-timeline runtime into the serialized format: parse `eventTimelines` from `.bony` JSON into each `AnimationClip`, encode/decode them in `.bnb`, run the existing mixer dispatch during state-machine story evaluation, and surface the dispatched events in the numeric golden's `animationEvents` channel - Nim reference runtime + CLI only.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompt 27 the `eventTimeline` record exists in the registry and both
schemas, and the animation-clip JSON `$defs` carries an optional `eventTimelines`
array - but no Nim loader constructs one, no `.bnb` codec reads/writes one, and
the CLI never emits the dispatched events. The runtime *model* and *dispatch* are
already built (`AnimationClip.eventTimelines` `timelines.nim:162`; the
`animationClip*` ctor already accepts+validates `eventTimelines`
`timelines.nim:673-678, 714`; the mixer path `dispatchEvents` (`mixer.nim:196`) /
`advancePlaying` (`:235`) / `update*` (`:260`) already fills
`AnimationState.events`). This prompt fills the missing seams: **JSON load**,
**binary round-trip**, and **dispatch output** - where "dispatch output" is
**not** a mechanical parameter add (see step 3; it requires bridging the
state-machine story runner to an `AnimationState` mixer, which currently does not
exist along the story path).

Concretely, this prompt builds exactly this - **Nim + CLI only**:

1. **JSON loader** (`runtime-nim/src/bony/jsonio.nim`): in `parseBonyAnimations`
   (`:811`), (a) add `"eventTimelines"` to the `validateKnownKeys(aObj, [...])`
   allow-list (`:821`); (b) add an `eventTimelines` parse block beside the
   `deformTimelines` block (`:976-1017`) that reads the `keyframes` array, builds
   `EventData`/`EventKeyframe` values, and constructs an `EventTimeline` via the
   existing `eventTimeline*` ctor (`timelines.nim:593`); (c) thread the parsed
   `seq[EventTimeline]` into the `animationClip(...)` call (`:1018`, which already
   takes the `eventTimelines` param). Enforce the contract's load-validated
   invariants - most already raise inside `eventTimeline*`/`animationClip*` via
   `validateEventName` (`timelines.nim:210-212`) and `ensureEventSorted`
   (`:245-248`); add JSON-level rejections for anything the ctors do not already
   cover (empty keyframe list, negative time, malformed `EventData`), using
   `newBonyLoadError(schemaViolation, ...)` with the same context-string style as
   the surrounding parser. Match the reserved defaults from prompt 27's canonical
   JSON (optional `intValue`/`floatValue`/`stringValue`/`audioPath`/`volume`/
   `balance` default when absent).

2. **Binary codec** (`runtime-nim/src/bony/binary/semantic.nim`): add
   `eventTimeline` encode + decode mirroring the `boneTimeline`/`slotTimeline`
   child-record handling (bone/slot timeline **encode** is near
   `semantic.nim:1293-1319`; the **decode** cases `of boneTimelineTypeKey`/`of
   slotTimelineTypeKey` are near `:1862`/`:1877` inside `decodeAnimationObjects`;
   confirm exact current line numbers). Encode/decode the packed `eventKeys`
   payload using **exactly** the byte layout prompt 27 pinned in
   `docs/event-timeline-contract.md` (`## Packed byte layout (.bnb)`) - note there
   is **no curve tail** for events (do not call `writeTimelineKeys`'s curve
   serialization `:787-853`; write a dedicated event-payload reader/writer). Honor
   the string encoding decision prompt 27 made (inline `varuint len` + UTF-8, or
   string-table index). The decode path must reconstruct the same `EventTimeline`
   the JSON loader produces so a clip round-trips identically.

3. **Dispatch surfacing in the CLI golden** (`cli/bony_cli.nim`): the numeric
   golden is produced by `numericGoldenJson` (`:1705`). The M8 state-machine
   listener events already surface as `root["events"]` via
   `stateMachineEventsJson` (`:1693, 1742`). Add a **distinct**
   `root["animationEvents"]` channel (the key prompt 27 pinned) carrying the
   clip-dispatched events (`AnimationState.events`, `seq[DispatchedEvent]`
   `mixer.nim:54-57, 93`), each serialized to the object shape prompt 27 pinned
   (`name`, `trackIndex`, `time`, `intValue`, `floatValue`, `stringValue`,
   `audioPath`, `volume`, `balance`). Thread the dispatched-event list into
   `numericGoldenJson` (add a parameter, e.g. `animationEvents:
   seq[DispatchedEvent] = @[]`) the way the story runner threads `physicsWorlds`
   (`:1709, 1712-1722`), **but do not mistake this for a mechanical parameter
   add.** The real work is producing that list:
   - **The mixer is never run along the story path today.** The story runner
     `executeStateMachineScript` (`cli/bony_cli.nim:~1424-1476`) steps
     `runtime.update(sample.time - previousTime)` (`:1460`) and samples the pose
     directly; `StateMachineRuntime.update` (`statemachine/core.nim:~676-683`) only
     advances layer time + applies transitions. `AnimationState`/`update*`/
     `dispatchEvents` live entirely in `anim/mixer.nim` and are **not** invoked.
     So `AnimationState.events` is never populated on this path - you must build a
     **state-machine-layer -> `AnimationState` bridge**: for the layer's active
     clip, drive an `AnimationState`/`AnimationTrack` (track 0, the layer's clip +
     loop flag), advance it by the **same per-sample delta** the SM is advanced by,
     and collect `state.events`.
   - **Advance incrementally, reset per sample** (the parity contract prompt 27
     pins). Each sample advances the bridge by `sample.time - previousTime`
     (mirror the physics story's incremental advance, `:1456-1474`), and the
     collected event list is the events fired in **that** window only - reset it
     between samples like the per-sample physics state. Do **not** advance from
     `0` to absolute time each sample. This is what makes the Dart port (prompt 30)
     able to reproduce the goldens.
   - Setup-pose (`--t`) callers pass no events and the channel is **omitted** when
     empty (mirror how `stateMachine`/`inputs`/`layers`/`events` are only emitted
     when `state.present`, `:1737-1742`).
   Because this bridge is the milestone's single biggest unknown, treat step 3 as
   the prompt's **unit B** (see the cut line below) and land unit A (load +
   round-trip) first.

4. **Round-trip + validation tests** (Nim): add a unit test proving a clip that
   owns an event timeline survives `json -> bnb -> json` byte-losslessly (mirror
   the deform round-trip coverage the M6 gate and
   `runtime-nim/tests/test_json_bnb_json_idempotency.nim` provide), and negative
   tests for the contract's edge cases (a)-(e) (empty name, negative time,
   decreasing times, empty keyframe list, and the volume/balance rule prompt 27
   pinned). Follow the existing `runtime-nim/tests/` style and register any new
   test in `runtime-nim/bony.nimble` if the suite enumerates tests there.

Do NOT change the format, the registry, either schema, or `generated/wire.nim`
(those are prompt 27's outputs - if a regen is needed, re-run
`python3 codegen/generate.py`, do not hand-edit). Do NOT add a conformance rig or
golden (prompt 29). Do NOT touch the Dart runtime (prompt 30).

**Links to Relevant Documentation**
- Binding contract: docs/event-timeline-contract.md (prompt 27 - the byte layout,
  edge cases, non-decreasing rule, and the `animationEvents` channel shape)
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4)
- Model + mixer already built (do not re-add): runtime-nim/src/bony/anim/
  timelines.nim (EventData 99-106, EventKeyframe 108-110, EventTimeline 112-113,
  AnimationClip.eventTimelines 162, eventTimeline ctor 593, animationClip
  param+validation 673-678/714, validateEventName 210, ensureEventSorted 245-248)
  and runtime-nim/src/bony/anim/mixer.nim (DispatchedEvent 54-57,
  AnimationState.events 93, eventThreshold 88, dispatch path 196-290)
- JSON loader seam: runtime-nim/src/bony/jsonio.nim (parseBonyAnimations 811,
  validateKnownKeys allow-list 821, boneTimelines block 828, slotTimelines block
  896, deformTimelines block 976-1017 - the closest template, animationClip call
  1018)
- Binary seam: runtime-nim/src/bony/binary/semantic.nim (boneTimeline/slotTimeline
  encode ~1293-1319; decode cases in decodeAnimationObjects ~1862/1877;
  writeTimelineKeys curve serialization 787-853 - which events do NOT use; confirm
  current line numbers)
- CLI golden seam: cli/bony_cli.nim (numericGoldenJson 1705, physicsWorlds
  threading 1709/1712-1722, stateMachineEventsJson 1693, root["events"] 1742,
  conditional state emission 1737-1742)
- State-machine story runner (the bridge site): cli/bony_cli.nim
  (executeStateMachineScript ~1424-1476, incremental advance runtime.update at
  1460) and runtime-nim/src/bony/statemachine/core.nim (StateMachineRuntime.update
  ~676-683); the mixer to bridge to: runtime-nim/src/bony/anim/mixer.nim
  (AnimationState/AnimationTrack, setAnimation, update* 260, events 93)
- Template: the Nim deform-timeline runtime slice
  .agents/big-change-prompts/24-runtime-nim-deform-timeline.md and its landed diff
- Repo gate: Makefile `test`; round-trip gate
  `python3 scripts/ci/round_trip_run.py --bony-bin /tmp/bony_bin`
- Beads: bony-5yt9 (this slice; blocked until bony-0ofc closes), under epic bony-p05f

**Success Criteria**
- `parseBonyAnimations` accepts and parses `eventTimelines`, constructing
  `EventTimeline`s on each `AnimationClip`; the contract's load rejections
  (a)-(e) all fire with `schemaViolation` errors.
- `binary/semantic.nim` encodes and decodes the `eventTimeline` child record using
  the exact packed byte layout from `docs/event-timeline-contract.md`; a clip that
  owns an event timeline round-trips `json -> bnb -> json` byte-losslessly.
- `numericGoldenJson` emits `root["animationEvents"]` (distinct from the M8
  listener `events` array) with the per-event object shape prompt 27 pinned, fed
  from the mixer's `AnimationState.events` along the state-machine story path;
  setup-pose goldens omit the channel.
- New Nim round-trip + negative unit tests pass; existing suites unaffected.
- `make test` and the round-trip gate pass; no format/registry/schema/generated
  file changed by hand; no conformance rig, no Dart change.

**Constraints**
- Preserve clean-room posture: match `bony`'s own `anim/timelines.nim` +
  `anim/mixer.nim`; do not derive event dispatch from any third-party runtime.
- Keep Rive importer out of scope; keep Spine importer blocked.
- Audio stays metadata only - carry `audioPath`/`volume`/`balance` verbatim; never
  decode or play audio.
- Nim-only: do NOT change the format, registry, either schema, `generated/wire.nim`
  (prompt 27), add a conformance rig (prompt 29), or touch Dart (prompt 30).
- Match the `animationEvents` channel name and per-event shape from prompt 27
  exactly - prompt 30's Dart port and prompt 29's goldens depend on byte-for-byte
  and field-name agreement (use ASCII field names only).
- Keep the slice to one meaningful implementation session: JSON load + binary
  codec + CLI dispatch surfacing + round-trip/negative tests. Natural cut line:
  **unit A** = JSON load + binary round-trip + tests; **unit B** = CLI
  `animationEvents` surfacing. Do not land unit A leaving the round-trip gate red.
