# /big-change prompt - conformance gate (m19 animation-event story rig + goldens)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 4** of the M3 event-timeline milestone. Depends
> on `28-runtime-nim-event-timeline.md` (the JSON/`.bnb` load path and the
> `animationEvents` golden channel it emits). Must land before
> `30-dart-event-timeline-parity.md` (which reproduces these goldens).
> **Candidate category:** comparable-gap.

---

/big-change Add the first animation-event conformance rig `m19_event_rig`: an unweighted single-slot skeleton whose animation clip owns an `eventTimeline` firing distinct value-carrying events at keyframe times, driven through a single-layer state-machine story, with committed `.bony`/`.bnb` assets, an input script, and numeric goldens whose `animationEvents` channel is non-vacuous at nonzero time.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompt 28 the Nim reference runtime loads `eventTimelines` from `.bony` and
`.bnb`, dispatches them through the mixer along the state-machine story path, and
surfaces the fired events in the numeric golden's `animationEvents` channel - but
no committed conformance rig exercises it. This prompt adds `m19_event_rig`, the
first rig whose golden's non-vacuity rests on **dispatched events**, following the
exact shape of the M18 deform-story rig (the newest story-driven, nonzero-time
rig: `m18_mesh_deform_anim_rig`, `conformance/README.md` "M18" section, assets
`conformance/assets/m18_mesh_deform_anim_rig.bony` +
`conformance/assets/bnb/m18_mesh_deform_anim_rig.bnb`, goldens
`conformance/goldens/m18_deform_story_{rest,mid,end}.json`, script
`conformance/scripts/m18_deform_story.json`). The milestone token `M19` only
names the asset; the registry key band stays **M3** (events are M3 - prompt 27).

**Rig design (project-owned, deliberately single-purpose).** Mirror the M18
single-layer "SM-plays-one-clip" precedent (which itself mirrors `m9_non_scalar`):
- One identity `root` bone and one draw-order slot `panel_slot` with a simple
  region attachment (geometry is incidental - the golden's signal is the event
  channel, not vertices; keep a static region so the bones/slots/drawBatches stay
  trivially stable across samples).
- One animation clip `pulse` owning a single `eventTimeline`. **Firing semantics
  to design around (from the contract / prompt 27):** dispatch is delta-based and
  exclusive on `fromTime`, and a `t=0` sample advances by `0` and fires **nothing**
  (`mixer.nim:219-224, 236`). So an event authored **at `t=0` is never observed**
  at the `rest` sample - do NOT rely on a `t=0` event for coverage. Place the
  observable, value-carrying events at `t > 0` so each fires in its own
  inter-sample window. Recommended events (each carries distinct int/float/string,
  incl. one **empty** `stringValue` to exercise that case in a *fired* event):

  | key | `t` | `name` | `intValue` | `floatValue` | `stringValue` | fires in sample |
  |-----|----:|--------|-----------:|-------------:|---------------|-----------------|
  | 0 | `0.5` | `hit`  | `7` | `1.5`  | `"left"` | `mid`  (window `(0, 0.5]`) |
  | 1 | `1.0` | `land` | `-3`| `0.25` | `""`     | `end`  (window `(0.5, 1.0]`) |

  So `rest` (t=0) golden has an **empty/omitted** `animationEvents`, `mid` fires
  exactly `[hit]`, `end` fires exactly `[land]` (per-sample window reset, NOT
  cumulative - the incremental stepping the contract pins). Keep `audioPath` empty
  and `volume`/`balance` at their reserved defaults - audio fields are carried but
  not exercised, per the metadata-only non-goal. Optionally add a third event at
  the **same time** as `hit` (e.g. `hit2`@`0.5`) to exercise the
  non-decreasing-times rule and multi-event ordering within one window, if it does
  not complicate the golden. (No extra timeline is needed to give `pulse` a
  duration: `animationClip` derives its duration from the event timeline's last
  key time, `timelines.nim:~714`, so duration = `1.0` and `land`@`1.0` fires.)
- One state machine `event_story` with a single layer playing `pulse` (the
  simplest SM-plays-one-clip machine, mirroring `m9_non_scalar` / `m18`
  `deform_story`).

**Input script + goldens.** Add `conformance/scripts/m19_event_story.json`
(`bony.input-script.v1`, `stateMachine: event_story`) with samples `rest` (t=0),
`mid` (t=0.5), `end` (t=1.0) - keyframe-aligned so each sample lands exactly on an
event time. Generate goldens `conformance/goldens/m19_event_story_{rest,mid,end}
.json` via the state-machine golden path. The **non-vacuity anchor** is the
top-level `animationEvents` array, per the incremental per-sample windows above:
`rest` empty/omitted, `mid` = `[hit]`, `end` = `[land]`, each with exact
`name`/`intValue`/`floatValue`/`stringValue` - a runtime that ignores event
timelines emits no `animationEvents` and fails at `mid` and `end`. If the
generated goldens do **not** match this expectation (e.g. `end` shows `[hit,land]`
cumulatively, or `mid` is empty), the incremental-reset stepping from prompt 28 is
not wired correctly - fix prompt 28's bridge, do not hand-adjust the golden.
**Document in the `conformance/README.md` "M19" section** exactly which events fire
in which sample window and why (mirror the M18 section's per-sample table and its
"a runtime that ignores the timeline fails at mid/end" argument).

**Assets + gates.**
- `conformance/assets/m19_event_rig.bony` (JSON source).
- `conformance/assets/bnb/m19_event_rig.bnb` via
  `bony json-to-bnb conformance/assets/m19_event_rig.bony
  conformance/assets/bnb/m19_event_rig.bnb`.
- Confirm all four CI gates pass with the new rig: numeric-golden
  (`scripts/ci/conformance_run.py`), input-script
  (`scripts/ci/input_script_run.py`, which also replays the matching `.bnb`
  fixture against the same goldens - keeping binary event playback in the
  cross-runtime contract), and round-trip (`scripts/ci/round_trip_run.py`). No
  image golden is required (`m19` "pending" like the other recent story rigs).
- Add the `### M19 event rig` section to `conformance/README.md` and the
  `| M19 | m19_event_rig | ... |` row to the milestone coverage table; note that
  cross-runtime status is **Nim-only pending prompt 30** (Dart parity), mirroring
  how M18's status line was staged before its Dart slice landed.

Regenerate goldens with the CLI built per `conformance/README.md`
("Running the full suite locally"); do NOT hand-author golden numbers. Commit the
rig, the `.bnb`, the input script, and all three goldens together.

Do NOT change the format, registry, schema, or runtime code (prompts 27/28); this
is a conformance-asset-only slice. Do NOT touch the Dart runtime (prompt 30).

**Links to Relevant Documentation**
- Binding contract: docs/event-timeline-contract.md (prompt 27 - dispatch channel
  + firing semantics)
- Runtime that produces the golden: prompt 28's `animationEvents` emission in
  cli/bony_cli.nim (numericGoldenJson) and the mixer dispatch
  runtime-nim/src/bony/anim/mixer.nim (eventThreshold 88, dispatchEvents 196-234,
  advancePlaying 235)
- Newest story-rig template (mirror closely): conformance/README.md "### M18
  mesh-deform-anim rig" section; assets conformance/assets/
  m18_mesh_deform_anim_rig.bony + bnb/m18_mesh_deform_anim_rig.bnb; goldens
  conformance/goldens/m18_deform_story_{rest,mid,end}.json; script
  conformance/scripts/m18_deform_story.json
- Single-layer SM-plays-one-clip precedent: m9_non_scalar (asset
  conformance/assets/m9_non_scalar_rig.bony, script
  conformance/scripts/m9_non_scalar_story.json)
- Conformance format + how to add a milestone: conformance/README.md (numeric
  golden format, input-script format, "Adding a new milestone", CI gates)
- Input-script schema: spec/bony-input-script.schema.json
- Suite runner: scripts/ci/suite_run.py; individual gates
  scripts/ci/{conformance_run,input_script_run,round_trip_run}.py
- Template prompt: .agents/big-change-prompts/25-conformance-deform-anim-gate.md
  and its landed diff
- Repo gate: build CLI then `python3 scripts/ci/suite_run.py --bony-bin
  /tmp/bony_bin`
- Beads: bony-ggpl (this slice; blocked until bony-5yt9 closes), under epic bony-p05f

**Success Criteria**
- `conformance/assets/m19_event_rig.bony` + `conformance/assets/bnb/
  m19_event_rig.bnb` + `conformance/scripts/m19_event_story.json` +
  `conformance/goldens/m19_event_story_{rest,mid,end}.json` are committed and
  regenerate byte-identically from the CLI.
- The goldens' `animationEvents` channel is non-vacuous: distinct events fire with
  exact `name`/`intValue`/`floatValue`/`stringValue` at the intended samples; a
  static/no-event render fails at `mid` and/or `end`. The `.bnb` fixture replays
  to the same goldens (binary event playback in the cross-runtime contract).
- All four CI gates pass (`python3 scripts/ci/suite_run.py --bony-bin ...`).
- `conformance/README.md` gains the `M19` coverage row and a `### M19 event rig`
  section documenting the per-sample firing table, the non-vacuity argument, and a
  "Nim-only pending prompt 30" cross-runtime status line.
- No format/registry/schema/runtime change; no Dart change.

**Constraints**
- Preserve clean-room posture: the rig is a project-owned bony asset; do not
  derive event names, values, or timing from any third-party sample data.
- Keep Rive importer out of scope; keep Spine importer blocked.
- Conformance-only: do NOT change the format, registry, schema, Nim runtime
  (prompts 27/28), or the Dart runtime (prompt 30).
- Keep the rig single-purpose: one clip, one event timeline, one SM layer, a
  static region slot - no meshes, deform, clipping, constraints, or multi-layer
  overlay. The golden's signal is the event channel only.
- Regenerate goldens from the CLI; never hand-edit golden numbers.
- Keep the slice to one meaningful implementation session: rig + `.bnb` + script +
  three goldens + README section.
