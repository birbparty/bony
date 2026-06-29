# /big-change prompt - runtime/cli (.bnb animation and state-machine implementation)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 3**. Depends on step 1 defining and generating
> the M3/M8 binary contract. Step 3 depends on this enabling `.bnb`
> state-machine replay.
> **Candidate category:** frontier.

---

/big-change Implement `.bnb` animation and state-machine serialization, loading, and CLI playback.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Implement the contract from step 1 across the Nim reference runtime, Dart
runtime, and CLI. The target behavior is simple to state: a `.bnb` emitted from
`conformance/assets/m8_rig.bony` must preserve the animation clips and
`gesture` state machine well enough for `golden-gen` and `play` to execute the
existing `conformance/scripts/m8_gesture_story.json` input script directly from
the `.bnb` asset.

This is not an importer task and not a new authoring feature. It is the binary
mirror for already-local project-owned animation and state-machine behavior.

**Links to Relevant Documentation**

- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md`
- Contract from step 1: `docs/binary-animation-state-machine-contract.md`
  if created; otherwise the updated binary/validation docs from step 1
- Binary canonicalization: `docs/binary-canonicalization.md`
- Binary skip rule: `docs/binary-toc-skip-semantics.md`
- Load validation: `docs/load-validation-contract.md`
- Registry: `registry/wire.yml`
- Defaults: `spec/defaults.yml`
- Generated Nim wire table: `runtime-nim/src/bony/generated/wire.nim`
- Generated Dart wire table: `runtime-dart/lib/src/generated/wire.dart`
- Nim model: `runtime-nim/src/bony/model.nim`
- Nim binary semantic encoder/decoder: `runtime-nim/src/bony/binary/semantic.nim`
- Nim binary framing: `runtime-nim/src/bony/binary/framing.nim`
- Nim JSON loader/serializer: `runtime-nim/src/bony/jsonio.nim`
- Nim animation timelines: `runtime-nim/src/bony/anim/timelines.nim`
- Nim animation mixer: `runtime-nim/src/bony/anim/mixer.nim`
- Nim state-machine runtime: `runtime-nim/src/bony/statemachine/core.nim`
- Nim CLI: `cli/bony_cli.nim`
- CLI docs: `cli/README.md`
- Nim smoke tests: `runtime-nim/tests/test_smoke.nim`
- Dart model: `runtime-dart/lib/src/model.dart`
- Dart loader: `runtime-dart/lib/src/loader.dart`
- Dart animation runtime: `runtime-dart/lib/src/anim.dart`
- Dart state-machine runtime: `runtime-dart/lib/src/statemachine.dart`
- Dart M6 binary tests: `runtime-dart/test/m6_bnb_loader_test.dart`
- Dart M8 state-machine tests: `runtime-dart/test/m8_statemachine_test.dart`
- Existing M8 asset and script: `conformance/assets/m8_rig.bony`,
  `conformance/scripts/m8_gesture_story.json`
- Beads: `bony-0vw`

**Current Local Facts To Preserve**

- `toBonyJson` in `runtime-nim/src/bony/jsonio.nim` currently serializes setup,
  path, parameter, and deformer data, but not animations or state machines.
- `loadBonyJson` in `runtime-nim/src/bony/jsonio.nim` validates
  `animations` and `stateMachines`, but returns `SkeletonData` without storing
  them. The helper exports `loadBonyJsonAnimations` and
  `loadBonyJsonStateMachines` for JSON-side playback.
- `buildObjectRecords`, `writeBonyBnb`, and `decodeSkeletonObjects` in
  `runtime-nim/src/bony/binary/semantic.nim` are the current semantic binary
  encoder/decoder surface.
- `loadKnownBonyBnb` rejects unknown binary content for `bnb-to-json` because
  JSON conversion has no preservation bucket.
- `runtime-dart/lib/src/loader.dart` has a JSON parser for animations and
  state machines, plus a binary loader that currently decodes only the
  registered setup/path/deformer records into `SkeletonData`.
- `executeStateMachineScript` in `cli/bony_cli.nim` currently rejects `.bnb`
  assets before parsing the input script.

**Success Criteria**

- Implement the step 1 model decision in Nim: either extend `SkeletonData` or
  add the documented loaded-asset aggregate, then update JSON, binary, CLI, and
  tests consistently. `.bony -> .bnb -> .bony` must preserve local
  animation/state-machine data for known-model assets.
- Implement canonical `.bnb` writing and decoding for all animation and
  state-machine records defined in step 1 in
  `runtime-nim/src/bony/binary/semantic.nim`.
- Keep forward-compatible binary skipping behavior unchanged in
  `runtime-nim/src/bony/binary/framing.nim`. Known property decoders must still
  consume exactly their declared payload length.
- Update `toBonyJson` so `bnb-to-json` can emit canonical `.bony` with
  `animations` and `stateMachines` when they are present.
- Update `cli/bony_cli.nim` so state-machine input scripts work for `.bnb`
  assets that contain the required serialized data. Retain a clear error when a
  `.bnb` asset lacks the requested animation or state machine.
- Ensure `golden-gen` and `play` use the same replay semantics for `.bony` and
  `.bnb` state-machine input scripts.
- Update Dart `.bnb` loading in `runtime-dart/lib/src/loader.dart` so decoded
  `SkeletonData.animations` and `SkeletonData.stateMachines` match the JSON
  loader for committed fixtures.
- Add Nim tests in `runtime-nim/tests/test_smoke.nim` for binary round-trip of
  animation clips, state machines, listener definitions, typed inputs, blend1d
  states, transitions, and `.bnb` CLI state-machine replay.
- Add Dart tests in `runtime-dart/test/m6_bnb_loader_test.dart` or
  `runtime-dart/test/m8_statemachine_test.dart` proving `.bnb`-decoded M8 data
  has the same animation/state-machine surface as JSON-decoded M8 data.
- Update `cli/README.md` to remove the stale `.bony`-only limitation after the
  implementation is verified.
- Verification commands should include at minimum:

```bash
python3 codegen/generate.py --check
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim
/tmp/bony_bin json-to-bnb conformance/assets/m8_rig.bony /tmp/m8_rig.bnb
/tmp/bony_bin bnb-to-json /tmp/m8_rig.bnb /tmp/m8_roundtrip.bony
/tmp/bony_bin golden-gen /tmp/m8_rig.bnb /tmp/m8_speed_mid.json \
  --state-machine gesture \
  --input-script conformance/scripts/m8_gesture_story.json \
  --sample speed_mid
/tmp/bony_bin play /tmp/m8_rig.bnb \
  --state-machine gesture \
  --input-script conformance/scripts/m8_gesture_story.json \
  --out /tmp/m8_story_bnb.png
nim c -r --path:runtime-nim/src runtime-nim/tests/test_smoke.nim
cd runtime-dart && dart test
```

**Constraints**

- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not add new animation or state-machine feature kinds beyond the local
  kinds already parsed and tested by Nim/Dart.
- Do not weaken existing M6 forward-compatibility, byte-stability, or unknown
  object/property behavior.
- Keep image golden regeneration out of scope unless the implementation changes
  rendered setup/state-machine output and a failing image gate proves it.
