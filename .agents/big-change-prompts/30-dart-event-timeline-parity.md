# /big-change prompt - Dart runtime event-timeline parity

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 4 of 4** of the M3 event-timeline milestone. Depends
> on `27-contract-event-timeline-format.md` (the wire shape / `animationEvents`
> channel), `28-runtime-nim-event-timeline.md` (the runtime seam it mirrors), and
> `29-conformance-event-anim-gate.md` (the committed `m19` goldens it consumes).
> Can run once those three have landed.
> **Candidate category:** comparable-gap.

---

/big-change Port the animation-clip event timeline to the Dart runtime - load it from `.bony` JSON and `.bnb`, dispatch it in the mixer, and prove parity against the committed m19 event-story goldens (exact string/int fields, `1e-4` on numerics).

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompts 27-29 the Nim reference runtime loads clip event timelines, fires
them through the mixer, and the `m19_event_story_{rest,mid,end}.json` goldens
(with a non-vacuous `animationEvents` channel) are committed. The Dart runtime has
**event dispatch scaffolding but no event data**: `DispatchedEvent`
(`runtime-dart/lib/src/anim.dart:528-533`, carrying only `{trackIndex, name,
time}`) exists, but `AnimationState.events` is "Always empty until event timelines
are ported (planned post-M3)" (`anim.dart:541-542`), `_dispatchEventsForEntry`
(`anim.dart:655`) has nothing to dispatch, and `AnimationClip`
(`runtime-dart/lib/src/model.dart:687`) carries no `eventTimelines`. This prompt brings Dart to parity, mirroring the Nim
seam from prompt 28.

**The Nim behavior to match (parity reference, project-owned):**
`runtime-nim/src/bony/anim/timelines.nim` (`EventData` 99-106, `EventTimeline`
112-113, `ensureEventSorted` non-decreasing 245-248) and
`runtime-nim/src/bony/anim/mixer.nim` (`DispatchedEvent` 54-57, dispatch path
196-290, `eventThreshold` 88). The serialized wire shape and the
`animationEvents` golden channel are fixed by
`docs/event-timeline-contract.md` (prompt 27). Match string/int fields exactly and
numerics within `1e-4` per `docs/float-math-contract.md`.

Concretely, this prompt builds exactly this - **Dart runtime only**:

1. **Model** (`runtime-dart/lib/src/model.dart`): add an `EventData` class
   (`name`, `intValue`, `floatValue`, `stringValue`, `audioPath`, `volume`,
   `balance`), an event keyframe type (`time` + `EventData`), and an
   `EventTimeline` class (a keyframe list), mirroring the Nim records; add an
   `eventTimelines` list to `AnimationClip` (at `runtime-dart/lib/src/model.dart:687`,
   beside `boneTimelines`/`slotTimelines`/`deformTimelines`). Event timelines have
   **no bone/slot target** and **no curve** - do not reuse the curve machinery.
   **Also widen `DispatchedEvent`** (`anim.dart:528-533`): today it carries only
   `{trackIndex, name, time}`, but Nim's `DispatchedEvent` carries a full
   `EventData` (`mixer.nim:54-57`). Add the `intValue`/`floatValue`/`stringValue`/
   `audioPath`/`volume`/`balance` fields (or an `EventData` member) so the Dart
   test can assert the full `animationEvents` object shape prompt 27 pins - filling
   the 3-field record is not enough.

2. **JSON loader** (`runtime-dart/lib/src/loader.dart`): in `_parseAnimations`
   (prompt 26 located it at `loader.dart:421`, with the bone/slot loops near
   `:433`/`:481` and the deform block the closest template), parse
   `anim['eventTimelines']` into `EventTimeline`s, applying the same edge-case
   rejections as Nim / the contract: empty `name`, negative `time`, **decreasing**
   times (equal allowed - non-strict), empty keyframe list, and the
   volume/balance rule prompt 27 pinned. Reuse the loader's existing
   quantize/validation helpers at the load boundary.

3. **BNB loader** (`runtime-dart/lib/src/loader.dart`): decode the generated wire
   `eventTimeline` type (regenerated into `runtime-dart/lib/src/generated/wire.dart`
   by prompt 27's codegen - do NOT hand-edit; re-run `python3 codegen/generate.py`
   if needed). Add an `_bEventTimelineKeys(...)` decode helper next to the bone/
   slot timeline decoders (`_bBoneTimelineKeys`/`_bSlotTimelineKeys` near
   `loader.dart:1910`/`:1961`; confirm current line numbers), reading the packed
   event payload per the contract's byte layout (inline-string or string-table per
   prompt 27's decision; **no curve tail**), and a `case` in the clip-child
   dispatch next to `_bnbBoneTimeline`/`_bnbSlotTimeline` (near `:2556`/`:2577`).

4. **Mixer dispatch** (`runtime-dart/lib/src/anim.dart`): fill the existing
   scaffolding. In `_dispatchEventsForEntry` (`:655`) iterate the entry clip's
   `eventTimelines`, applying the `eventThreshold` gating that Nim uses
   (`mixer.nim:235-257`: dispatch over the crossed `[fromTime, toTime]` window,
   with the mix-in threshold behavior), and append `DispatchedEvent`s (with
   `trackIndex`, `time`, and the `EventData`) to `AnimationState.events`
   (`:541-542`). Match Nim's ordering: events sorted by time then dispatch order
   (`mixer.nim:226-232`). Remove/replace the "always empty until ported" comment.

5. **Conformance test** (`runtime-dart/test/m19_event_story_test.dart`): use the
   animated-story precedents `m18_deform_story_test.dart` / `m5_ik_story_test.dart`
   for structure, **but NOT their stepping model.** Those tests drive a *fresh*
   runtime to *absolute* time each sample (`rt.update(t)` from `0`), which for
   delta-based event dispatch would fire the cumulative `[0, t]` window and produce
   `end = [hit, land]` - diverging from the Nim goldens (`end = [land]`). Instead,
   replay **incrementally on a single carried runtime**: advance by
   `sample.time - previousSampleTime` per sample (mirroring the incremental
   stepping the contract pins in prompt 27, i.e. the physics-story pattern, not the
   deform/mesh pattern), and read the events fired **in that sample's window**,
   resetting the collected list per sample. For each sample `{rest:0.0, mid:0.5,
   end:1.0}` assert `animationEvents` equals the committed
   `conformance/goldens/m19_event_story_<name>.json` array (`rest` empty, `mid` =
   `[hit]`, `end` = `[land]`) - `name`/`intValue`/`stringValue` exactly,
   `time`/`floatValue`/`volume`/`balance` within `1e-4`. Add a `.bony`-vs-`.bnb`
   parity assertion for at least one sample (mirror `m17_mesh_clip_bnb_test.dart:17-20`):
   load the event clip from both `../conformance/assets/m19_event_rig.bony` and
   `../conformance/assets/bnb/m19_event_rig.bnb` and assert identical dispatched
   events.

6. **Docs**: update the `### M19 event rig` cross-runtime status note in
   `conformance/README.md` to record that the `m19_event_story_*` goldens are
   honored by **both** the Nim reference and the Dart runtime (mirror the M18/M5
   cross-runtime status paragraphs).

Keep it Dart-only: do NOT change the format, the registry, the Nim runtime, or any
committed golden. The goldens are the fixed cross-runtime contract; Dart must
reproduce them, not regenerate them.

**Links to Relevant Documentation**
- Binding contract: docs/event-timeline-contract.md (prompt 27)
- Float math contract: docs/float-math-contract.md (quantizeF32, 1e-4)
- Nim parity reference (behavior to match): runtime-nim/src/bony/anim/timelines.nim
  (EventData 99-106, EventTimeline 112-113, ensureEventSorted 245-248) and
  runtime-nim/src/bony/anim/mixer.nim (DispatchedEvent 54-57, dispatch 196-290,
  eventThreshold 88); the Nim runtime slice .agents/big-change-prompts/
  28-runtime-nim-event-timeline.md
- Committed goldens to reproduce: conformance/goldens/m19_event_story_{rest,mid,
  end}.json; assets conformance/assets/m19_event_rig.bony +
  conformance/assets/bnb/m19_event_rig.bnb
- Dart event scaffolding to fill: runtime-dart/lib/src/anim.dart (DispatchedEvent
  528-529, AnimationState.events "always empty" 541-542, _dispatchEventsForEntry
  655, eventThreshold 516)
- Dart model/loader seams (confirm current line numbers): runtime-dart/lib/src/
  model.dart (AnimationClip 687) and runtime-dart/lib/src/loader.dart
  (_parseAnimations 421, bone/slot loops 433/481, BNB timeline decoders
  _bBoneTimelineKeys/_bSlotTimelineKeys 1910/1961, clip-child dispatch
  _bnbBoneTimeline/_bnbSlotTimeline 2556/2577)
- Dart wire schema (generated - do not hand-edit): runtime-dart/lib/src/generated/
  wire.dart (regenerated by prompt 27)
- Dart test precedents: runtime-dart/test/m18_deform_story_test.dart (animated
  story shape), m5_ik_story_test.dart, m17_mesh_clip_bnb_test.dart (.bony-vs-.bnb
  parity), m10_conformance_test.dart (_checkGolden full-golden shape)
- Template: the Dart deform-timeline parity slice
  .agents/big-change-prompts/26-dart-deform-timeline-parity.md and its landed diff
- Repo gate: `cd runtime-dart && dart test`
- Beads: bony-7axu (this slice; blocked until bony-ggpl closes), under epic bony-p05f

**Success Criteria**
- Dart `AnimationClip` carries `eventTimelines`; the JSON and `.bnb` loaders both
  parse them (with the same edge-case rejections as Nim / the contract, including
  the non-strict non-decreasing-times rule).
- The Dart mixer dispatches event timelines into `AnimationState.events` with the
  same `eventThreshold` gating and time/dispatch ordering as Nim; the
  "always empty until ported" scaffolding is removed.
- `runtime-dart/test/m19_event_story_test.dart` reproduces all three
  `m19_event_story_*` goldens' `animationEvents` arrays from the `.bony` (exact
  strings/ints, `1e-4` numerics), and at least one sample additionally from the
  `.bnb`, with identical dispatched events.
- `conformance/README.md` M19 cross-runtime status records Nim+Dart parity.
- `cd runtime-dart && dart test` passes (all suites); no committed golden, format,
  registry, or Nim file changed.

**Constraints**
- Preserve clean-room posture: match `bony`'s own `anim/timelines.nim` +
  `anim/mixer.nim`; do not derive event dispatch from any third-party runtime.
- Keep Rive importer out of scope; keep Spine importer blocked.
- Audio stays metadata only - carry `audioPath`/`volume`/`balance` verbatim; never
  decode or play audio.
- Dart-only: do NOT change the format, registry, Nim runtime, or any committed
  golden. Reproduce the goldens, do not regenerate them.
- Match the `animationEvents` channel shape and firing semantics from prompts
  27/28 exactly.
- Keep the slice to one meaningful implementation session: model + JSON/BNB load +
  mixer dispatch + the m19 parity test.
