# Big Change Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown for a change to an existing codebase. This task graph will be executed by AI agents working in parallel, coordinated through MCP Agent Mail with file reservations to prevent conflicts.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary analysis, preparation, implementation, testing, and documentation tasks. Go beyond the basics — consider edge cases, error handling, security considerations, backwards compatibility, and integration points. Each task should be specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

<critical_constraint>
You must NOT implement any of the changes yourself. Your ONLY output is a bash shell script containing `bd create` and `bd dep add` commands. Do NOT use `bd add` — the correct command is `bd create`. Do not write code. Do not create files other than the shell script. Do not modify existing files. Read and analyze the codebase, then produce the script.

The script MUST create a single parent **epic** first (`bd create -t epic`) and parent **every** task bead to it via `--parent "$EPIC"`, so the whole change is one trackable rollup. The epic is an organizational rollup only — never make it a blocking dependency (do NOT `bd dep add` to or from the epic; `bd dep add` is for real ordering edges between task beads, and a blocking edge on an epic both excludes it wrongly and inverts `bd dep tree`). Membership is the `--parent` relationship, nothing else.
</critical_constraint>

## Change Information

### Change Type
NEW_FEATURE — mints a new serialized format record (`eventTimeline`) and its wire/JSON schema + codegen artifacts. The Nim runtime types (`EventData`, `EventKeyframe`, `EventTimeline`, `AnimationClip.eventTimelines`, mixer dispatch path) already exist but are **entirely non-serialized and unreachable from any asset**; this slice adds the binding contract, registry keys, schema, and regenerated codecs so a later slice (prompt 28) can wire the loader. Direct analog of the landed M4 deform-timeline format slice (prompt 23).

### Description
Introduce the animation-clip "event timeline" (a clip-owned timeline of keyframed, application-facing events that fire when playback crosses a keyframe time) as a **binding format contract** plus the **registry keys, canonical JSON + wire schema, and regenerated codec artifacts** for a clip-owned `eventTimeline` record — **contract + schema/registry/codegen only**. Runtime load/round-trip wiring, mixer dispatch surfacing, and the conformance golden land in prompts 28–30 and are explicitly out of scope here.

This is **step 1 of 4** of the M3 event-timeline milestone (candidate category: comparable-gap). It must land before `28-runtime-nim-event-timeline.md` (which reads the loaded record and the contract this slice defines); prompts 29 (conformance) and 30 (Dart parity) follow.

**Do not confuse this with state-machine listener events.** `bony` has a *separate*, already-shipped M8 feature — `StateMachineListenerEvent` (`runtime-nim/src/bony/statemachine/core.nim:63`), serialized as the numeric golden's top-level `events` array by `stateMachineEventsJson` (`cli/bony_cli.nim:1693,1742`). That is a state-machine transition/enter/exit listener, **not** a clip-owned keyframe event. This milestone is the *other* event concept: per-clip, keyframed, value-carrying events dispatched during animation playback. Its golden output channel MUST use a distinct key (`animationEvents`) so it never collides with the M8 listener `events` array.

**Project-owned event model to define (decide and document normatively):**
1. An event timeline is a **clip-owned timeline**, a fourth timeline family alongside `boneTimelines`, `slotTimelines`, `deformTimelines` (authored under a new `eventTimelines` array on each clip). Unlike bone/slot timelines it has **no bone/slot target** — it is clip-global. Serialized shape mirrors `EventTimeline` (`timelines.nim:112-113`): an ordered list of keyframes.
2. Each keyframe mirrors `EventKeyframe` (`timelines.nim:108-110`): a `time` (f32-quantized, non-negative) and an `EventData` payload (`timelines.nim:99-106`): `name` (non-empty string), `intValue` (i32), `floatValue` (f64/f32-quantized), `stringValue` (string, may be empty), `audioPath` (string, may be empty), `volume` (f32), `balance` (f32).
3. **Ordering rule (normative):** event keyframe times are **non-decreasing** (NOT strictly increasing) — two events may fire at the same time. Mirrors `ensureEventSorted` (`timelines.nim:245-248`, uses `>` not `>=`), deliberately different from the strictly-increasing rule bone/slot/deform use (`ensureSorted`, `timelines.nim:239-242`). Pin this difference so prompts 28/30 do not apply the strict rule.
4. **Audio is metadata only (normative non-goal):** `audioPath`, `volume`, `balance` are carried as application-facing data — the runtime never opens, decodes, or plays audio. Matches the `docs/comparable-feature-set.md` "Events and audio" planning note.

**Golden / dispatch output channel (load-bearing):** dispatched events (`AnimationState.events`, `seq[DispatchedEvent]`) will be surfaced in the numeric golden under a **distinct, project-owned** top-level key **`animationEvents`** (the top-level `events` key is already taken by the M8 listener array). Per-event object shape (mirrors `DispatchedEvent` `mixer.nim:54-57` + `EventData`): `{ "name": string, "trackIndex": integer, "time": number, "intValue": integer, "floatValue": number, "stringValue": string, "audioPath": string, "volume": number, "balance": number }`. String and integer fields compare exactly; `time`/`floatValue`/`volume`/`balance` compare within `1e-4`. **Actual emission is prompt 28; this slice only fixes the contract for the channel name and shape.**

**Sampling/stepping model for the channel (load-bearing, cross-runtime parity contract):** `dispatchEvents` is **delta-based** — fires events in the half-open window it is advanced across (`mixer.nim:196-232`, `key.time > fromTime`), and `advancePlaying` early-returns on a zero advance (`mixer.nim:236`). The story runner advances **incrementally** by `sample.time - previousTime` per sample (`cli/bony_cli.nim:1460`). Therefore pin: **`animationEvents` on each golden is the set of events fired in that sample's own inter-sample window** — the per-sample dispatched-event list is **reset between samples**, not accumulated. Consequences prompts 28/29/30 MUST honor identically: (i) a sample at `t=0` advances by `0` and fires **nothing** (exclusive-on-`fromTime` + zero-advance early return); (ii) with samples `{0, 0.5, 1.0}`, an event at `t=0.5` fires in the `(0, 0.5]` window and an event at `t=1.0` fires in the `(0.5, 1.0]` window. Prompt 30's Dart port MUST replay **incrementally** (carry track state across samples, reset the event list per sample) — NOT the fresh-runtime/absolute-time `rt.update(t)` pattern from `m18_deform_story_test.dart`. Cross-reference the physics story's incremental advance (`cli/bony_cli.nim:1456-1474`) as the parity precedent.

### Links to Relevant Documentation
- **Clean room / provenance:** `docs/CLEANROOM.md`; `docs/PROVENANCE.md` (add the event-timeline naming entry)
- **Comparable research (capability justification ONLY — not a design source):** `docs/comparable-feature-set.md` ("Events and audio" / "Animation timelines" rows). Do NOT import any third party's event field set, wire layout, or naming.
- **Float math contract:** `docs/float-math-contract.md` (quantizeF32, 1e-4 tolerance, f32 quantization)
- **Existing (non-serialized) Nim event runtime this milestone wires in:**
  - `runtime-nim/src/bony/anim/timelines.nim` — `EventData:99-106`, `EventKeyframe:108-110`, `EventTimeline:112-113`, `AnimationClip.eventTimelines:162`, `eventTimelines` accessor `:201`, `eventTimeline` ctor `:593`, `animationClip` param+validation `:673-678/714`, `validateEventName:210-212`, `ensureEventSorted:245-248`, `requireKeys:251-253`
  - `runtime-nim/src/bony/anim/mixer.nim` — `DispatchedEvent:54-57`, `AnimationState.events:93`, `AnimationTrack.eventThreshold:88`, `animationTrack` default `:127`, dispatch path `:196-290`
- **M8 listener event to NOT collide with:** `runtime-nim/src/bony/statemachine/core.nim:63` (`StateMachineListenerEvent`), surfaced by `cli/bony_cli.nim` (`stateMachineEventsJson:1693`, `root["events"]:1742`)
- **Freshest end-to-end template (mirror closely):** `.agents/big-change-prompts/23-contract-deform-timeline-format.md` and its landed diff; `docs/deform-timeline-contract.md`
- **Registry key bands:** `registry/key-ranges.md` (M3 = 2000..2999, "Animations, timelines, curves, mixing"; verified next-free typeKey **2003**, next-free propertyKey **2005**)
- **Registry source:** `registry/wire.yml` (animationClip typeKey `2000` `:314`, boneTimeline `2001` `:320`, slotTimeline `2002` `:326`; propertyKeys `2000..2004` `:935-963`; `deformTimeline` id `:241`, `deformKeys` id `:577` / doc anchor `:583`, animationClip objects doc `:1268`, `deformTimeline` objects entry `:1281-1287` as the objects-block template)
- **Codegen:** `codegen/generate.py` (`PACKED_BYTES_METADATA:26`, `timelineKeys:27`, `deformKeys:63`, coverage rule `:307-315`, `canonical_json_overrides:595`, schema packedBytes stamp `:1017-1018`; writes 4 files)
- **Defaults source of truth:** `spec/defaults.yml` (`objectDefaults:99`, `requiredProperties`; `deformTimeline` entry `:366`)
- **Spec:** `spec/bony.schema.json` (animations `:90`, deform sub-object `:1108`), `spec/bony-wire.schema.json`
- **Docs index:** `docs/README.md` (add the new contract row)
- **Asset schema gate:** `scripts/ci/schema_validate_assets.py`
- **Repo gate:** `make test` + `python3 codegen/generate.py --check`
- **Beads:** `bony-0ofc` (this slice; claim with `bd update bony-0ofc --claim`), under epic `bony-p05f`

### Affected Areas
- **`docs/`** — new `docs/event-timeline-contract.md` (binding contract, mirrors `deform-timeline-contract.md` structure); `docs/README.md` (add contract row under an "Animation Timeline Contracts" heading beside the deform contract); `docs/PROVENANCE.md` (event-timeline naming entry); `docs/CLEANROOM.md` new-identifier checklist for `eventTimelines`, `animationEvents`, `eventTimeline`, `eventKeys`.
- **`registry/wire.yml`** (M3 band only) — new `eventTimeline` typeKey `2003`, new `eventKeys` bytes propertyKey `2005`, new `eventTimeline` `objects:` entry (only property `eventKeys`; no bone/slot target). `timelineKeys` (`2004`) left untouched.
- **`codegen/generate.py`** — new `PACKED_BYTES_METADATA["eventKeys"]` entry (mirror `deformKeys:63`, layout anchor → `docs/event-timeline-contract.md`); new standalone `eventTimeline` `$def` in `canonical_json_overrides()` **AND** injection of the optional `eventTimelines` array into the existing `animationClip` override block (`:~792`); a `hidden_binary_children` (`:489`) decision for whether `eventTimeline` emits a root-level collection.
- **`spec/defaults.yml`** — `objectDefaults` + `requiredProperties` entries covering every serialized `eventTimeline` property exactly once (coverage rule `generate.py:307-315`); each `requiredProperties` entry carries `reason` + `ownerBead`.
- **Regenerated (NO hand-edits):** `spec/bony.schema.json` (+ optional `eventTimelines` array in animation-clip `$defs`), `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, `runtime-dart/lib/src/generated/wire.dart`.
- **`runtime-nim/tests/test_smoke.nim`** — bump registry change-detector counts to regenerated totals (current: `bonyTypeKeys.len == 29` `:163`, `bonyPropertyKeys.len == 105` `:164`, `bonyPropertyDefaults.len == 55` `:165`, `bonyRequiredProperties.len == 79` `:166`).
- **Explicitly OUT of scope (prompts 28–30):** `jsonio.nim`, `binary/semantic.nim`, `cli/bony_cli.nim`, mixer wiring, conformance rig/golden, Dart runtime logic (beyond the regenerated `generated/wire.dart`).

### Success Criteria
- `docs/event-timeline-contract.md` exists, is listed in `docs/README.md`, and normatively specifies: the model; load-validated invariants + tolerances (tied to `docs/float-math-contract.md`); the edge-case table (a)–(e); the packed `.bnb` byte layout (with a stable heading anchor referenced from the wire schema); the non-decreasing-times rule and how it differs from the strict bone/slot rule; the audio-metadata-only non-goal; and the `animationEvents` dispatch output channel + per-event object shape + incremental per-sample-window stepping model + exclusive-`fromTime` firing semantics.
- `registry/wire.yml` gains an `eventTimeline` type (key `2003`) and a new `eventKeys` bytes property (key `2005`), with an `eventTimeline` objects entry carrying only `eventKeys`; `timelineKeys` (`2004`) is left untouched; no key collides; all new keys in `2000..2999`; every new entry cites owning bead `bony-0ofc` in its `doc`.
- `spec/defaults.yml` covers every serialized `eventTimeline` property exactly once across `objectDefaults` + `requiredProperties`; `python3 codegen/generate.py --check` passes.
- Codegen regenerated (both schemas + `generated/wire.nim` + `generated/wire.dart`) with no hand-edits; the animation-clip JSON `$defs` gains an optional `eventTimelines` array whose items express the readable keyframe/name/value shape — achieved by editing the `animationClip` block inside `canonical_json_overrides()` (`generate.py:~792`), not merely by adding a standalone `eventTimeline` `$def`; `python3 scripts/ci/schema_validate_assets.py` passes for all existing assets (they carry no event timelines, so the array is optional and absent). The `intValue` packed field is encoded as a signed varint (bony's `writeVarint` convention), not a bare fixed `i32`.
- `docs/PROVENANCE.md` gains the event-timeline naming entry; the `docs/CLEANROOM.md` new-identifier checklist is satisfied for `eventTimelines`, `animationEvents`, `eventTimeline`, `eventKeys`.
- `runtime-nim/tests/test_smoke.nim` registry change-detector counts updated to the regenerated totals: `bonyTypeKeys.len` 29→30, `bonyPropertyKeys.len` 105→106, `bonyRequiredProperties.len` 79→80; **`bonyPropertyDefaults.len` stays 55** (eventTimeline's `objectDefaults` is `properties: {}`, contributing zero, like deformTimeline).
- `make test` passes.
- **Deferred to prompt 28 (do NOT attempt here):** the runtime JSON+`.bnb` round-trip test of a clip-carried event timeline, the load-validation rejections (a)–(e), the mixer dispatch surfacing, and the `animationEvents` golden emission — they require the `jsonio`/`semantic`/`cli` wiring this slice intentionally does not touch. Do NOT claim or attempt a runtime round-trip test.

### Constraints
- **Clean-room posture:** do not inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime/importer/generated source, wire layouts, type/property keys, event field names, or copied docs prose. The event-timeline model, field names, and dispatch semantics are project-owned (already in `bony`'s own `anim/timelines.nim` and `anim/mixer.nim`).
- Use `docs/comparable-feature-set.md` only to justify the timeline-event capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for human/legal review.
- Audio is metadata only — no audio decode or playback in the runtime, ever.
- Registry edits: use only the M3 band (`2000..2999`) per `registry/key-ranges.md`; follow that file's shared-surface reservation rule.
- Land the registry entry, `defaults.yml`, canonical-JSON overrides, schema regen, and codegen **together** — `validate_sources()` fails if they drift apart.
- Do **NOT** wire the timeline into `jsonio`/`semantic`/`cli`/mixer, add a conformance rig/golden, or touch Dart runtime logic. Those are prompts 28, 29, 30. This slice ends when the `eventTimeline` record exists in the registry and both schemas, the codegen artifacts are regenerated, and the contract doc is written — but no runtime loads, validates, round-trips, or dispatches it from an asset yet.
- **Wire-decision (load-bearing):** encode each per-keyframe string (`name`, `stringValue`, `audioPath`) **inline** in the packed `eventKeys` payload as `varuint length` + UTF-8 bytes (option (a)), NOT as a string-table index. Rationale: `docs/binary-canonicalization.md` documents that current animation/SM packed payloads use indices and numeric tags, not strings; a string-table-index approach would be the first string-bearing packed payload and would need new interning-traversal code in the canonical writer plus M6-gate coverage. Inline lengths keep the event payload self-contained.
- **Packed `eventKeys` byte layout (pin normatively):** `varuint keyCount`, then per keyframe: `f32 time`, `varuint nameLen` + name UTF-8 bytes, **`svarint intValue`**, `f32 floatValue`, `varuint stringValueLen` + bytes, `varuint audioPathLen` + bytes, `f32 volume`, `f32 balance`. Event keyframes have **no `curve`** (no interpolation between events), so — unlike bone/slot/deform — the event payload has **no curve tail**. Call this out explicitly so an implementer does not reuse `writeTimelineKeys`'s curve serialization (`binary/semantic.nim:787-853`). Pin the anchor heading so the wire schema `PACKED_BYTES_METADATA` layout reference points at it.
- **`intValue` encoding (pin normatively — do NOT leave as bare "i32"):** `intValue` (`EventData.intValue` is `int32`, `timelines.nim:101`) MUST be encoded as a **signed LEB128 varint**, matching bony's existing `writeVarint(int64(value))` convention (`binary/semantic.nim:262-263`, `varint` backing type `registry/wire.yml:100`) rather than a fixed 4-byte little-endian int. Spell this out in the byte-layout section so prompt 28 (Nim) and prompt 30 (Dart) pick the same width/signedness — an unpinned "i32" is exactly the divergence class this contract exists to prevent. (`time`/`floatValue`/`volume`/`balance` are fixed `f32`; only `intValue` is varint.)
- **Do NOT reuse `timelineKeys` (`2004`)** for the event payload. `PACKED_BYTES_METADATA` is keyed by property id (`generate.py:26`) and the schema stamps one `x-bony-packedBytes` layout per property (`generate.py:1017-1018`); a second incompatible layout (no curve tail, inline strings) cannot live on `timelineKeys` — allocate the distinct `eventKeys` = `2005`, mirroring the landed `deformKeys` = `3009` pattern (not prompt 23's superseded reuse prose).
- **Edge cases the contract MUST make normative (verify against code before asserting bounds):** (a) empty `name` → reject (`validateEventName`); (b) negative keyframe `time` → reject; (c) **non-decreasing** (not strict) times — equal adjacent allowed, decreasing pair rejected (`ensureEventSorted`); (d) zero keyframes on an event timeline → reject (mirror `requireKeys` `timelines.nim:251-253`); (e) `volume`/`balance` range — decide and pin, but **confirm against the `EventData`/`eventTimeline`/`animationClip` code first**; do NOT invent a clamp the runtime does not have (if unconstrained, document "carried verbatim").
- **Natural cut line if the slice runs long:** **unit A** = contract doc + registry key + `objects:` entry; **unit B** = codegen (`PACKED_BYTES_METADATA` / `canonical_json_overrides` / `defaults.yml`) + four-file regen with `codegen --check` green + provenance. Do NOT land unit A leaving `codegen --check` red.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/` (there is no `docs/specs/` or `docs/adr/`; architectural decisions live in the per-feature contract docs, e.g. `docs/deform-timeline-contract.md`, and in `docs/binary-canonicalization.md` / `docs/load-validation-contract.md`) for existing decisions.
2. Examine the directory/module structure of the affected areas: `registry/wire.yml`, `codegen/generate.py`, `spec/defaults.yml`, `docs/deform-timeline-contract.md` (the template).
3. Identify key interfaces to preserve: the `PACKED_BYTES_METADATA` shape, the `canonical_json_overrides()` shape, the `objects:` block convention, the defaults coverage rule (`generate.py:307-315`).
4. Note existing test/gate patterns: `python3 codegen/generate.py --check`, `scripts/ci/schema_validate_assets.py`, `runtime-nim/tests/test_smoke.nim` registry-count guard, `make test`.
5. Assess risk areas: the four regenerated files must never be hand-edited; `validate_sources()` fails on registry/defaults/schema drift; the packed layout must not reuse the curve-tailed `timelineKeys` layout; the `animationEvents` key must not collide with the M8 `events` array.

Use your analysis to make each bead specific — reference actual file paths, module names, and patterns you observed.

Then generate a shell script that creates the complete task graph.

**IMPORTANT: Your ONLY deliverable is a bash shell script with `bd create` commands. Not an implementation plan. Not a design document. Not a code review. A runnable `.sh` script.**

---

## Output Format

Generate a shell script that creates the full task graph. The script should:

1. **Initialize Beads** (if not already initialized)
2. **Create one parent epic** (`bd create -t epic`) representing the whole change, capturing its ID into `$EPIC`
3. **Create all task beads** with appropriate priorities, each parented to the epic via `--parent "$EPIC"`
4. **Establish dependencies** between task beads (ordering edges only — never to or from the epic)
5. **Add labels** for phase grouping (child beads inherit the epic's labels unless `--no-inherit-labels`)

### Example Output

```bash
#!/bin/bash
# Project: bony
# Change: Animation-clip event-timeline format contract (M3, contract + schema/registry/codegen only)
# Generated: 2026-07-04

set -e

# Initialize beads if needed
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating change beads..."

# ========================================
# Parent epic — every task below is parented to it (--parent "$EPIC").
# The epic is an organizational rollup: it is NEVER given a blocking dep
# (no `bd dep add` to or from it) and is never dispatched as work itself.
# ========================================

EPIC=$(bd create "Epic: Animation-clip event-timeline format contract (M3 slice 1/4)" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work — keep it out of `bd ready`

# ========================================
# Phase 1: Analysis & Grounding
# ========================================

CONFIRM_KEYS=$(bd create "Confirm next-free M3 keys, volume/balance bounds, intValue encoding, and \$defs injection path before authoring" -d "Grounding pass. (1) Re-verify against registry/wire.yml that next-free M3 typeKey is 2003 and propertyKey is 2005 (typeKeys 2000-2002 :314-326; propertyKeys 2000-2004 :935-963). (2) Confirm from timelines.nim (validateEventData :256-260, animationClip event validation :714) and mixer.nim whether volume/balance are clamped or carried verbatim — verified: they are quantizeF32'd but NOT range-clamped, so edge-case (e) documents 'carried verbatim' and invents no clamp. (3) Confirm the intValue encoding convention: EventData.intValue is int32 (timelines.nim:101); bony writes signed ints as LEB128 varint (writeVarint(int64) semantic.nim:262-263), so the packed layout pins intValue=svarint, NOT fixed i32. (4) Trace how deformTimelines reaches the animationClip JSON \$defs: it is added by editing the 'animationClip' block inside canonical_json_overrides() (generate.py ~:792-816, alongside boneTimelines/deformTimelines, additionalProperties:False :794) — NOT by the standalone per-record \$def; the new eventTimelines array MUST be added there too. (5) Decide whether eventTimeline goes in hidden_binary_children (generate.py :489): boneTimeline/slotTimeline are hidden, deformTimeline is NOT (so it auto-emits a root-level collection via object_id+'s' :516). Pick and document one." -p 0 --label analysis --parent "$EPIC" --silent)

# ========================================
# Phase 2: Contract doc + registry (unit A)
# ========================================

CONTRACT_DOC=$(bd create "Write docs/event-timeline-contract.md (binding contract)" -d "Mirror docs/deform-timeline-contract.md structure: Status/owner-bead line (bony-0ofc); cleanroom/provenance paragraph; ## Model; ## Load-validated invariants (tolerances tied to docs/float-math-contract.md, 1e-4); ## Edge cases (normative) table for (a) empty name reject, (b) negative time reject, (c) non-decreasing (not strict) times, (d) zero keyframes reject, (e) volume/balance per confirmed runtime behavior (carried verbatim, no clamp); ## Packed byte layout (.bnb) with a stable heading anchor referenced from the wire schema (varuint keyCount; per key: f32 time, varuint nameLen+bytes, SIGNED-VARINT intValue [svarint per writeVarint convention, NOT fixed i32], f32 floatValue, varuint stringValueLen+bytes, varuint audioPathLen+bytes, f32 volume, f32 balance; NO curve tail); the non-decreasing-vs-strict distinction; the audio-metadata-only non-goal; ## Dispatch output channel pinning the animationEvents golden key + per-event object shape + incremental per-sample-window stepping + exclusive-fromTime firing — tag these dispatch clauses explicitly as 'normative; first EMITTED/VERIFIED in prompts 28-29' so they are not mistaken for settled-and-tested in this slice; ## Deterministic dispatch forward-ref to mixer.nim:196/235/260 + eventThreshold; ## Related contracts. Cross-link from docs/README.md: the deform contract is a plain table row at README.md:75 with NO 'Animation Timeline Contracts' heading — either add a matching plain row for the event contract, or create the grouping heading and move both rows under it (do not assume the heading already exists)." -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CONTRACT_DOC $CONFIRM_KEYS

REGISTRY=$(bd create "Add eventTimeline type 2003 + eventKeys property 2005 + objects entry to registry/wire.yml" -d "M3 band only. Add typeKey eventTimeline=2003 (mirror slotTimeline typeKey :326). Add bytes propertyKey eventKeys=2005 (mirror deformKeys id :577; doc anchor -> docs/event-timeline-contract.md packed-bytes heading). Add eventTimeline objects: entry (mirror deformTimeline :1281-1287) carrying ONLY eventKeys — no boneIndex/slotIndex/timelineKeys. Leave timelineKeys=2004 untouched. ALSO update the animationClip parent-record child ordering: the animationClip objects doc currently reads 'followed immediately by owned boneTimeline, slotTimeline, and deformTimeline records' (wire.yml:1268; the typeKey doc :314 is staler) — extend it to include eventTimeline and pin WHERE event records sit in the emitted child sequence relative to deform, since 28/30 need identical parse order. Cite owning bead bony-0ofc in every new entry's doc. No key collides; all in 2000..2999." -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGISTRY $CONFIRM_KEYS
bd dep add $REGISTRY $CONTRACT_DOC

# ========================================
# Phase 3: Codegen inputs + regen (unit B)
# ========================================

PACKED_META=$(bd create "Add PACKED_BYTES_METADATA[eventKeys] to codegen/generate.py" -d "New entry keyed by eventKeys (mirror the landed deformKeys entry at generate.py:63), layout pointing at the docs/event-timeline-contract.md packed-bytes anchor. Do NOT reuse or mutate the timelineKeys entry (generate.py:27) — its curve-tailed layout is incompatible with the event payload (inline strings, no curve tail)." -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $PACKED_META $REGISTRY

CANONICAL_JSON=$(bd create "Add canonical_json_overrides() eventTimeline \$def AND inject eventTimelines array into the animationClip override" -d "TWO edits in codegen/generate.py canonical_json_overrides() (~:595). (1) Add a standalone eventTimeline \$def producing the readable shape: a keyframes array of { t: number, name: string, intValue?: integer, floatValue?: number, stringValue?: string, audioPath?: string, volume?: number, balance?: number } with sensible defaults for optional fields. (2) CRITICAL — edit the existing 'animationClip' override block (~:792-816, which already lists boneTimelines/slotTimelines/deformTimelines and is additionalProperties:False :794) to add an optional 'eventTimelines': {type:array, items:{\$ref:'#/\$defs/eventTimeline'}, default:[]}. schema['\$defs'].update(canonical_json_overrides()) at :485 is the SOLE source of the animation-clip \$def, so without edit (2) the required optional eventTimelines array never appears and the asset gate/success criterion silently fails. Also apply the hidden_binary_children decision from CONFIRM_KEYS (add eventTimeline to hidden_binary_children :489 to suppress a root-level collection, or leave it out to mirror deform's root collection) and note which was chosen." -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CANONICAL_JSON $REGISTRY

DEFAULTS=$(bd create "Add spec/defaults.yml entries covering the eventTimeline registry property (eventKeys) once" -d "Coverage rule (generate.py:307-315) operates ONLY on the registry OBJECTS-block property list, which for eventTimeline is exactly [eventKeys] — the seven inner fields (name/intValue/floatValue/stringValue/audioPath/volume/balance) live INSIDE the packed eventKeys bytes blob and are NOT registry properties; do NOT add objectDefaults/requiredProperties for them (--check rejects unknown properties). Pin: objectDefaults eventTimeline -> properties: {} (like deformTimeline :366-367), plus a SINGLE requiredProperties entry for property: eventKeys (mirror deformKeys at defaults.yml:703) carrying reason + ownerBead (bony-0ofc)." -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $DEFAULTS $REGISTRY

REGEN=$(bd create "Run python3 codegen/generate.py and verify --check passes" -d "Regenerate spec/bony.schema.json, spec/bony-wire.schema.json, runtime-nim/src/bony/generated/wire.nim, runtime-dart/lib/src/generated/wire.dart (NO hand-edits). Ensure the animation-clip JSON \$defs (spec/bony.schema.json animations :90, deform sub-object :1108) gains an optional eventTimelines array expressing the readable keyframe/name/value shape. python3 codegen/generate.py --check MUST pass." -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGEN $PACKED_META
bd dep add $REGEN $CANONICAL_JSON
bd dep add $REGEN $DEFAULTS

# ========================================
# Phase 4: Provenance + gates
# ========================================

PROVENANCE=$(bd create "Add event-timeline naming entry to docs/PROVENANCE.md + run CLEANROOM checklist" -d "Record that event-timeline schema/field names were taken from bony's own pre-existing anim/timelines.nim / anim/mixer.nim runtime types (not derived from any surveyed product). Run the docs/CLEANROOM.md new-identifier checklist for the net-new serialized names: eventTimelines, animationEvents, eventTimeline, eventKeys." -p 1 --label docs --parent "$EPIC" --silent)
bd dep add $PROVENANCE $REGEN

SMOKE_COUNTS=$(bd create "Update registry change-detector counts in runtime-nim/tests/test_smoke.nim" -d "Bump ONLY three counts: bonyTypeKeys.len 29->30 (:163), bonyPropertyKeys.len 105->106 (:164), bonyRequiredProperties.len 79->80 (:166). bonyPropertyDefaults.len STAYS 55 (:165) — it flattens objectDefaults property entries, and eventTimeline's objectDefaults is properties:{} (contributes 0), exactly like deformTimeline. Do NOT bump the propertyDefaults count blindly or make test breaks. Confirm all four against the actual regenerated generated/wire.nim before editing." -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $SMOKE_COUNTS $REGEN

ASSET_GATE=$(bd create "Verify scripts/ci/schema_validate_assets.py passes on all existing assets" -d "Existing assets carry no event timelines; the eventTimelines array is optional and absent, so all assets must still validate against the regenerated spec/bony.schema.json." -p 1 --label testing --parent "$EPIC" --silent)
bd dep add $ASSET_GATE $REGEN

MAKE_TEST=$(bd create "Run make test as the final gate" -d "Full repo gate: make test + python3 codegen/generate.py --check must be green. Do NOT attempt any runtime round-trip / dispatch / golden test — those are deferred to prompt 28." -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $MAKE_TEST $SMOKE_COUNTS
bd dep add $MAKE_TEST $ASSET_GATE
bd dep add $MAKE_TEST $PROVENANCE

# ========================================
# Review gate
# ========================================

REVIEW=$(bd create "Dual-agent review of the format slice before commit" -d "Verify: no runtime wiring leaked in (jsonio/semantic/cli/mixer untouched); the four regenerated files are not hand-edited; animationEvents does not collide with the M8 events array; the packed layout has no curve tail; timelineKeys 2004 untouched; every new registry entry cites bony-0ofc; clean-room posture preserved." -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $REVIEW $MAKE_TEST

echo ""
echo "Bead graph created! View with:"
echo "  bd show $EPIC          # The parent epic and its rollup"
echo "  bd children $EPIC      # All task beads under the epic"
echo "  bd ready              # List unblocked tasks (the epic itself is not work)"
```

---

## Bead Creation Guidelines

### Epic / Hierarchy (REQUIRED)
- Create exactly **one parent epic** for the whole change: `EPIC=$(bd create "Epic: <change summary>" -t epic -p 0 --label epic --silent)`.
- Parent **every** task bead to it: add `--parent "$EPIC"` to every `bd create` (children inherit the epic's labels unless you pass `--no-inherit-labels`).
- The epic is a **rollup, not work**: never `bd dep add` to or from it. Membership is `--parent`; `bd dep add` is reserved for real ordering edges *between task beads*. A blocking edge on an epic wrongly keeps it out of (or drops it into) `bd ready` and inverts `bd dep tree`.
- **Keep the epic out of `bd ready`** by marking it active right after creation: `bd update "$EPIC" --status in_progress`. `bd ready` excludes `in_progress`/`blocked`/`deferred`/`hooked`. Do **not** rely on `--exclude-type epic` — that flag is ineffective on some `bd`/`bn` builds, whereas status-based exclusion works everywhere.
- An epic must have **≥ 2 children** to be meaningful — a one-task change does not need this skill.
- For very large changes you MAY use phase sub-epics (each `--parent "$EPIC"`, each with its own children), but a single top-level epic is the default and is sufficient for most changes.

### Priority Levels
- `-p 0` = Critical (blocking other work, or high-risk changes needing early validation)
- `-p 1` = High (important implementation work)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (cleanup, nice-to-haves)

### Labels (Phase Grouping)
Use `--label` to group beads by phase:
- `analysis` - Understanding current state
- `prep` - Preparation work (characterization tests, feature flags, scaffolding)
- `impl` - Core implementation
- `testing` - Test coverage
- `migration` - Data/code migration
- `docs` - Documentation updates
- `cleanup` - Post-rollout cleanup

### Dependency Rules
1. Never create cycles
2. Analysis tasks should complete before implementation begins
3. Characterization tests should exist before changing code
4. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
5. Parallel work should share a common ancestor, not depend on each other
6. `bd dep add` is for ordering edges **between task beads only** — never use it to attach a task to the epic (that is `--parent`), and never add a blocking edge to or from the epic

### Task Granularity
- Each bead should be completable in **under 750 lines of code changed**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area

---

## Change-Specific Considerations

### For New Features
- Start with analysis of similar existing features (here: the landed M4 deform-timeline slice — `docs/deform-timeline-contract.md`, `deformKeys` in `wire.yml`/`generate.py`)
- Consider feature flag for gradual rollout (N/A — the `eventTimelines` JSON array is optional and absent from all current assets, so the format addition is inert until prompt 28 wires the loader)
- Plan for A/B testing if relevant (N/A)
- Include documentation and changelog updates (the contract doc + PROVENANCE/CLEANROOM entries)

### For Refactors
- Add characterization tests first (capture current behavior)
- Consider strangler fig pattern for large changes
- Plan incremental migration path
- Ensure no behavior changes unless intentional

### For Migrations
- Create rollback plan as an explicit task
- Plan data validation checkpoints
- Consider dual-write period if applicable
- Include monitoring/alerting tasks

### For Performance Changes
- Add benchmarks before and after
- Include load testing tasks
- Plan gradual rollout with monitoring
- Have rollback criteria defined

---

## File Reservation Planning

```bash
# Reservation notes for this slice:
# Registry/codegen inputs (edit): registry/wire.yml, codegen/generate.py, spec/defaults.yml — high contention, all feed validate_sources(); edit + regen as one coordinated unit.
# Regenerated (NEVER hand-edit): spec/bony.schema.json, spec/bony-wire.schema.json, runtime-nim/src/bony/generated/wire.nim, runtime-dart/lib/src/generated/wire.dart
# Docs (edit): docs/event-timeline-contract.md (new), docs/README.md, docs/PROVENANCE.md, docs/CLEANROOM.md
# Test guard (edit): runtime-nim/tests/test_smoke.nim
# DO NOT TOUCH (out of scope, prompts 28-30): runtime-nim/src/bony/anim/jsonio.nim, binary/semantic.nim, cli/bony_cli.nim, anim/mixer.nim, anim/timelines.nim, runtime-dart logic
```

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check the rollup**: `bd children "$EPIC"` should list every task bead, and `bd dep tree` should show them under the epic with no orphan (un-parented) tasks
3. **Check ready work**: `bd ready` should show the initial analysis/grounding task and **not** the epic.
4. **Check no cycles**: `bd dep cycles` should report none

---

## Completeness Checklist

- [ ] A single parent epic (`-t epic`); every task bead parented to it via `--parent "$EPIC"`, with no orphan tasks and no blocking dep to/from the epic
- [ ] Analysis/grounding of next-free keys and volume/balance runtime behavior before authoring
- [ ] Contract doc mirroring the deform template, with the packed-bytes anchor, edge-case table, non-decreasing rule, audio non-goal, and animationEvents channel
- [ ] Registry keys (type 2003, property 2005) + objects entry; timelineKeys untouched
- [ ] Codegen inputs (PACKED_BYTES_METADATA, canonical_json_overrides, defaults.yml) + four-file regen with `codegen --check` green
- [ ] Optional `eventTimelines` array in the animation-clip JSON `$defs`
- [ ] test_smoke.nim registry-count bumps
- [ ] Asset-schema gate + `make test` green
- [ ] PROVENANCE + CLEANROOM entries
- [ ] Final review gate confirming no runtime wiring leaked in and clean-room posture preserved
- [ ] Clear dependency chains with no cycles
