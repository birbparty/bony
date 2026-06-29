# /big-change prompt - docs/registry/spec (.bnb animation and state-machine contract)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 3**. Contract first; implementation and
> conformance prompts depend on this deciding the project-owned binary surface.
> **Candidate category:** frontier.

---

/big-change Define the project-owned `.bnb` contract for serialized animations and state machines.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Close the format contract gap tracked by `bony-0vw`: `.bony` assets can carry
`animations` and `stateMachines`, and the Nim CLI can execute state-machine
input scripts for `.bony`, but `.bnb` state-machine replay is still rejected
because the binary contract does not serialize the needed animation clips or
state machines.

Define a clean-room, project-owned binary mirror for the existing local JSON
animation and state-machine surface. This slice should be contract and registry
work only: decide the binary object families, canonical ordering, references,
default omission, generated schema/default implications, and validation
ownership before any runtime starts accepting `.bnb` state-machine playback.

**Links to Relevant Documentation**

- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md`
- Local binding spec: `/Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md`
- Binary canonicalization: `docs/binary-canonicalization.md`
- Binary skip rule: `docs/binary-toc-skip-semantics.md`
- JSON canonicalization: `docs/json-canonicalization.md`
- Load validation: `docs/load-validation-contract.md`
- Float contract: `docs/float-math-contract.md`
- Registry overview: `registry/README.md`
- Registry key ranges: `registry/key-ranges.md`
- Wire registry: `registry/wire.yml`
- Defaults source: `spec/defaults.yml`
- Generated JSON schema: `spec/bony.schema.json`
- Code generator: `codegen/generate.py`
- Codegen tests: `codegen/test_generate.py`
- Existing Nim animation types: `runtime-nim/src/bony/anim/timelines.nim`
- Existing Nim state-machine types: `runtime-nim/src/bony/statemachine/core.nim`
- Existing Nim JSON parser for animations/state machines: `runtime-nim/src/bony/jsonio.nim`
- Existing Dart model carrying animations/state machines: `runtime-dart/lib/src/model.dart`
- Existing Dart JSON parser for animations/state machines: `runtime-dart/lib/src/loader.dart`
- Existing M8 asset: `conformance/assets/m8_rig.bony`
- Existing M8 state-machine story: `conformance/scripts/m8_gesture_story.json`
- Existing M9 non-scalar asset: `conformance/assets/m9_non_scalar_rig.bony`
- Beads: `bony-0vw`
- New contract doc to create if the plan chooses a standalone file:
  `docs/binary-animation-state-machine-contract.md`

**Current Local Facts To Preserve**

- `docs/binary-canonicalization.md` already names `animations` and
  `stateMachines` in canonical object-stream order, but `registry/wire.yml`
  has no M3 animation/timeline object keys and no M8 state-machine object keys.
- `registry/key-ranges.md` reserves `2000..2999` for M3 animations/timelines
  and `7000..7999` for M8 state machines/layers/transitions/listeners.
- `runtime-nim/src/bony/binary/semantic.nim` writes and decodes skeleton,
  bone, slot, region, path/pathAttachment, parameter, deformer, warp/rotation,
  keyformBlend, and keyform records only.
- `runtime-nim/src/bony/model.nim` stores setup/deformer skeleton data only.
  Nim animation clips and state machines currently live in
  `runtime-nim/src/bony/anim/timelines.nim` and
  `runtime-nim/src/bony/statemachine/core.nim`, and the CLI reconstructs them
  from JSON through `loadBonyJsonAnimations` and `loadBonyJsonStateMachines`.
- `runtime-dart/lib/src/model.dart` already stores `animations` and
  `stateMachines` on `SkeletonData`; Dart `.bnb` loading in
  `runtime-dart/lib/src/loader.dart` returns binary-decoded data without those
  fields populated.
- `cli/bony_cli.nim` rejects state-machine input scripts for `.bnb` assets in
  `executeStateMachineScript` with the message that `.bnb playback is not
  supported`.
- `cli/README.md` documents that state-machine input scripts currently require
  `.bony` assets until the binary contract includes animation and
  state-machine data.

**Success Criteria**

- Add or update binding docs so the `.bnb` v1 contract explicitly covers the
  existing project-owned `animations` and `stateMachines` JSON surface. If a new
  file is created, link it from `docs/README.md`; otherwise update the existing
  binary and validation docs in place.
- Define canonical object-stream order for animation and state-machine records
  in a way consistent with `docs/binary-canonicalization.md`: animation records
  before state-machine records, child records immediately after their owning
  parent when the contract chooses child records.
- Define reference semantics for binary animation/state-machine records from
  project-owned rules. The contract must state how references resolve to bones,
  slots, animation clips, inputs, layers, states, and listeners after load.
- Define validation rules for timeline kinds already implemented locally:
  bone scalar/vector/inherit timelines, slot attachment/color/two-color/sequence
  timelines, curves, clip state, blend1d state, typed inputs, transitions,
  conditions, and listeners. Do not add new runtime features in this slice.
- Update `registry/wire.yml` with append-only type/property entries using only
  the existing M3 and M8 bands from `registry/key-ranges.md`; do not renumber or
  repurpose any existing key.
- Update `spec/defaults.yml` only where the contract needs generated defaults
  for new records. Keep default omission compatible with
  `docs/json-canonicalization.md` and `docs/binary-canonicalization.md`.
- Regenerate or update generated artifacts through `codegen/generate.py`.
  Generated Nim and Dart wire tables must expose the new registry entries.
- Update `spec/bony.schema.json` only through the established generator path or
  an explicitly documented local generator gap. The schema must still validate
  existing committed conformance assets.
- Document whether Nim should extend `SkeletonData` or introduce a project-owned
  loaded-asset aggregate for animations and state machines. The decision must
  explain how `.bony -> .bnb -> .bony` preserves animation/state-machine data.
- Add focused codegen/generator tests proving the new registry/default/schema
  surface is append-only and generated consistently.
- Verification commands should include at minimum:

```bash
python3 codegen/generate.py --check
python3 -m unittest discover -s codegen -p 'test_*.py'
python3 scripts/ci/schema_validate_assets.py
```

**Constraints**

- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- This slice defines a project-owned binary mirror for already-local
  animation/state-machine features. Do not add 2D blend states, data binding,
  audio playback, editor interaction, skins/avatar reuse, text/vector/layout,
  new importer work, or any third-party compatibility target.
- Use only allocated ranges from `registry/key-ranges.md`.
- Keep contract changes small enough that step 2 can implement them in one
  runtime/CLI-focused session.
