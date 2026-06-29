# /big-change prompt - cli/conformance (state-machine input-script execution)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 1**. Can run independently.
> **Candidate category:** frontier.

---

/big-change Add deterministic state-machine input-script execution to the Nim CLI and conformance harness, with an M8 gesture story demo.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Turn the reserved `--state-machine ... --input-script ...` CLI surface into a
working project-owned execution path for `.bony` assets, centered on the
existing M8 `gesture` state machine. The killer demo is a single command that
renders a contact sheet from an input-script story:

```bash
./bony play conformance/assets/m8_rig.bony \
  --state-machine gesture \
  --input-script conformance/scripts/m8_gesture_story.json \
  --out demo/gesture_story.png
```

The same input script should feed a deterministic numeric/event conformance
gate, so this is not just a screenshot. It should prove that `bony` can replay
typed inputs over time, advance state-machine layers, emit listener events, and
render sampled poses from the existing project-owned runtime model.

**Links to Relevant Documentation**

- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md`
- CLI entry point: `cli/bony_cli.nim`
- CLI docs to update: `cli/README.md`
- Input-script schema: `spec/bony-input-script.schema.json`
- Input-script runner: `scripts/ci/input_script_run.py`
- Numeric golden comparator: `scripts/ci/_golden_compare.py`
- Suite runner: `scripts/ci/suite_run.py`
- Conformance docs: `conformance/README.md`
- Existing M8 asset: `conformance/assets/m8_rig.bony`
- Existing M8 sample: `conformance/scripts/m8_sample.json`
- Existing M8 golden: `conformance/goldens/m8_rig_t0.json`
- Existing M8 raster golden: `conformance/goldens/m8_rig_play.png`
- Nim state-machine runtime: `runtime-nim/src/bony/statemachine/core.nim`
- Nim animation mixer: `runtime-nim/src/bony/anim/mixer.nim`
- Nim JSON loader: `runtime-nim/src/bony/jsonio.nim`
- Nim transform/draw batches: `runtime-nim/src/bony/transform.nim`
- Nim smoke tests: `runtime-nim/tests/test_smoke.nim`
- Dart reference for pose application shape: `runtime-dart/lib/src/anim.dart`
- Dart state-machine parity tests: `runtime-dart/test/m8_statemachine_test.dart`
- Beads: `bony-tat` is the closed planning bead; `bony-uff` is the implementation bead to claim before coding.

**Current Local Facts To Preserve**

- `cli/bony_cli.nim` currently parses `--state-machine` and `--input-script`
  for `golden-gen` and `play`, then calls `rejectStateMachineArgs`.
- `requireSetupPoseTime` still rejects nonzero `--t`; do not silently keep
  emitting setup-pose output for animated samples.
- `numericGoldenJson(data, time)` currently computes setup-pose world transforms
  and draw batches only. It does not sample animation clips or state machines.
- `scripts/ci/input_script_run.py` validates `conformance/scripts/*.json`, then
  calls `golden-gen <asset> <actual> --t <t>` and ignores non-empty `inputs`
  with a warning.
- `spec/bony-input-script.schema.json` allows `samples[].inputs` but documents
  it as reserved.
- `runtime-nim/src/bony/statemachine/core.nim` already exposes
  `initStateMachineRuntime`, `setBoolInput`, `setNumberInput`, `fireTrigger`,
  `update`, `evaluate`, and `StateMachineRuntime.events`.
- `runtime-nim/src/bony/jsonio.nim` exposes `loadBonyJsonStateMachines(text)`.
  The Nim `SkeletonData` type does not store animation clips or state machines,
  so CLI state-machine execution must load the `.bony` text and reconstruct the
  machine from that project-owned parser path.
- `runtime-dart/lib/src/anim.dart` has `applyPose` for applying a `MixedPose`
  back to skeleton data before world/draw-batch evaluation. Nim does not appear
  to have an exported equivalent; add a project-owned Nim helper if needed.
- `conformance/assets/m8_rig.bony` contains the `gesture` machine with bool
  input `wave`, number input `speed`, trigger input `jump`, body/face layers,
  blend1d movement, and three listener definitions.

**Success Criteria**

- `spec/bony-input-script.schema.json` is updated backward-compatibly so input
  scripts can name the target state machine and name individual samples. Keep
  existing scripts valid.
- Add `conformance/scripts/m8_gesture_story.json` with an ordered story that
  exercises at least: initial idle, `wave=true` transition to `move`, `speed`
  changing blend output, `jump` trigger, and `wave=false` transition back toward
  idle. Sample names must be stable enough for golden filenames or transcript
  entries.
- `scripts/ci/input_script_run.py` no longer ignores non-empty `inputs`. It
  validates sample names, applies inputs in order, advances by sample deltas or
  documented sample times, and compares committed expected output for every
  checked sample. Preserve the old setup-pose path for scripts without a state
  machine.
- The golden naming scheme cannot collide when multiple samples use the same
  `t` with different inputs. Prefer script/sample names such as
  `m8_gesture_story_<sample>.json`; if a different scheme is chosen, document it
  in `conformance/README.md`.
- `golden-gen` supports state-machine input-script execution for `.bony` assets
  without using any third-party semantics. The CLI shape may be one of:
  `--state-machine <name> --input-script <path> --sample <name-or-index>` for
  per-sample numeric output, or a documented multi-sample transcript JSON. Keep
  the shape small and update `usage()` plus `cli/README.md`.
- Numeric output for state-machine samples includes enough deterministic state
  to verify behavior: sampled `time`, bones, slots, draw batches, active layers
  and states, and listener events emitted by the update that reached the sample.
  If this extends `bony.numeric-golden.v1`, update `scripts/ci/_golden_compare.py`
  to compare the new exact fields. If it creates a separate transcript format,
  document the format and compare it exactly.
- `play --state-machine gesture --input-script ... --out ...` renders a single
  PNG contact sheet with one cell per script sample. The command must use the
  same execution semantics as the numeric gate. Reuse the existing software
  rasterizer path in `renderSetupPose`/`renderSoftware`.
- For state-machine execution, nonzero times are meaningful. Do not route
  state-machine samples through `requireSetupPoseTime`. Preserve the existing
  fail-fast behavior for unsupported nonzero setup-pose `--t` unless you also
  implement and test direct animation sampling as an explicit, documented part
  of this slice.
- `.bnb` setup-pose conformance must keep working. State-machine input scripts
  may reject `.bnb` inputs with a clear error unless the current binary contract
  is verified to contain the needed animation/state-machine data.
- Add or update Nim tests in `runtime-nim/tests/test_smoke.nim` covering:
  state-machine input-script parsing/validation, typed input application,
  trigger consumption, listener event transcript ordering, CLI rejection for
  unsupported argument combinations, and contact-sheet output creation.
- Update `conformance/README.md` and `cli/README.md` so they no longer describe
  state-machine inputs as reserved once this lands. Touch only nearby stale
  docs needed for this feature; do not do a broad M9/docs-alignment sweep.
- Verification commands should include at minimum:

```bash
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim
/tmp/bony_bin golden-gen conformance/assets/m8_rig.bony /tmp/m8_story_sample.json \
  --state-machine gesture \
  --input-script conformance/scripts/m8_gesture_story.json \
  --sample <first-nontrivial-sample>
/tmp/bony_bin play conformance/assets/m8_rig.bony \
  --state-machine gesture \
  --input-script conformance/scripts/m8_gesture_story.json \
  --out /tmp/gesture_story.png
python3 scripts/ci/input_script_run.py --bony-bin /tmp/bony_bin
nim c -r --path:runtime-nim/src runtime-nim/tests/test_smoke.nim
```

**Constraints**

- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories. Rive is
  comparable evidence that interactive state machines matter; it is not a
  source for `bony` execution semantics, event payloads, or file shapes.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Keep this slice focused on executing existing `bony` state machines from
  project-owned `.bony` assets. Do not add a new authoring UI, editor runtime,
  data-binding system, audio playback, skins/avatar model, or external importer.
- Keep state-machine script semantics deterministic and easy to replay in other
  runtimes. Any new schema fields must be project-owned, documented, validated,
  and backward compatible with existing `bony.input-script.v1` files.
- Do not make the contact-sheet PNG the only proof. The numeric/event gate is
  the cross-runtime contract; the PNG is the demo and Nim raster regression aid.
- Keep the slice small enough for one meaningful implementation session. If
  direct non-state-machine animation sampling or `.bnb` state-machine playback
  grows large, file follow-up beads instead of absorbing it here.
