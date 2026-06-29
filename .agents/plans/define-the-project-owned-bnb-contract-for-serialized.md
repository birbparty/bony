# Big Change Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown for
a change to an existing codebase. This task graph will be executed by AI agents
working in parallel, coordinated through Beads.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary analysis,
preparation, implementation, testing, and documentation tasks. Go beyond the
basics: consider edge cases, error handling, backwards compatibility, clean-room
constraints, generated artifacts, and integration points. Each task should be
specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

<critical_constraint>
You must NOT implement any of the changes yourself. Your ONLY output is a bash
shell script containing `bd create` and `bd dep add` commands. Do NOT use
`bd add` - the correct command is `bd create`. Do not write code. Do not create
files other than the shell script. Read and analyze the codebase, then produce
the script.

The script MUST create a single parent epic first (`bd create -t epic`) and
parent every task bead to it via `--parent "$EPIC"`, so the whole change is one
trackable rollup. The epic is an organizational rollup only - never make it a
blocking dependency. Do NOT `bd dep add` to or from the epic; `bd dep add` is for
real ordering edges between task beads, and a blocking edge on an epic both
excludes it wrongly and inverts `bd dep tree`. Membership is the `--parent`
relationship, nothing else.
</critical_constraint>

## Change Information

### Change Type

NEW_FEATURE

This adds a new project-owned `.bnb` contract and registry/default/schema surface
for already-local animation and state-machine semantics. The codebase has local
JSON/runtime implementations, but the binary registry currently has no M3
animation/timeline object keys and no M8 state-machine object keys.

### Description

Define the project-owned `.bnb` contract for serialized animations and state
machines.

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

Current local facts to preserve:

- `docs/binary-canonicalization.md` already names `animations` and
  `stateMachines` in canonical object-stream order, but `registry/wire.yml` has
  no M3 animation/timeline object keys and no M8 state-machine object keys.
- `registry/key-ranges.md` reserves `2000..2999` for M3 animations/timelines and
  `7000..7999` for M8 state machines/layers/transitions/listeners.
- `runtime-nim/src/bony/binary/semantic.nim` writes and decodes skeleton, bone,
  slot, region, path/pathAttachment, parameter, deformer, warp/rotation,
  keyformBlend, and keyform records only.
- `runtime-nim/src/bony/model.nim` stores setup/deformer skeleton data only. Nim
  animation clips and state machines currently live in
  `runtime-nim/src/bony/anim/timelines.nim` and
  `runtime-nim/src/bony/statemachine/core.nim`, and the CLI reconstructs them
  from JSON through `loadBonyJsonAnimations` and
  `loadBonyJsonStateMachines`.
- `runtime-dart/lib/src/model.dart` already stores `animations` and
  `stateMachines` on `SkeletonData`; Dart `.bnb` loading in
  `runtime-dart/lib/src/loader.dart` returns binary-decoded data without those
  fields populated.
- `cli/bony_cli.nim` rejects state-machine input scripts for `.bnb` assets in
  `executeStateMachineScript` with the message that `.bnb playback is not
  supported`.
- `cli/README.md` documents that state-machine input scripts currently require
  `.bony` assets until the binary contract includes animation and state-machine
  data.

### Links to Relevant Documentation

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
- Existing Nim JSON parser for animations/state machines:
  `runtime-nim/src/bony/jsonio.nim`
- Existing Dart model carrying animations/state machines:
  `runtime-dart/lib/src/model.dart`
- Existing Dart JSON parser for animations/state machines:
  `runtime-dart/lib/src/loader.dart`
- Existing M8 asset: `conformance/assets/m8_rig.bony`
- Existing M8 state-machine story:
  `conformance/scripts/m8_gesture_story.json`
- Existing M9 non-scalar asset: `conformance/assets/m9_non_scalar_rig.bony`
- Beads: `bony-0vw`, especially `bony-0vw.1`
- New contract doc to create if the task graph chooses a standalone file:
  `docs/binary-animation-state-machine-contract.md`

### Affected Areas

1. Documentation contracts:
   `docs/binary-canonicalization.md`,
   `docs/binary-toc-skip-semantics.md`,
   `docs/load-validation-contract.md`,
   `docs/json-canonicalization.md`, `docs/README.md`, and a likely new
   `docs/binary-animation-state-machine-contract.md`. There are no
   `docs/specs/` or `docs/adr/` directories in the current tree.
2. Clean-room and provenance context: `docs/CLEANROOM.md`,
   `docs/PROVENANCE.md`, `docs/comparable-feature-set.md`, and the local binding
   spec. The task graph must keep third-party runtime/importer source out of
   scope.
3. Binary registry and key governance: `registry/README.md`,
   `registry/key-ranges.md`, and `registry/wire.yml`. The relevant unused bands
   are M3 `2000..2999` and M8 `7000..7999`; existing M1/M2/M5/M7 entries must
   remain append-only.
4. Defaults and generated schema: `spec/defaults.yml`,
   `spec/bony.schema.json`, `spec/DEFAULTS.md`, and `spec/README.md`. Any schema
   changes should flow through `codegen/generate.py` unless the task graph
   creates an explicit generator-gap bead.
5. Code generation and generated runtime metadata: `codegen/generate.py`,
   `codegen/test_generate.py`,
   `runtime-nim/src/bony/generated/wire.nim`, and
   `runtime-dart/lib/src/generated/wire.dart`.
6. Nim animation/state-machine source of truth:
   `runtime-nim/src/bony/anim/timelines.nim`,
   `runtime-nim/src/bony/statemachine/core.nim`,
   `runtime-nim/src/bony/jsonio.nim`, and `runtime-nim/src/bony/model.nim`.
   The plan must document whether Nim extends `SkeletonData` or introduces a
   loaded-asset aggregate that preserves animation/state-machine data through
   `.bony -> .bnb -> .bony`.
7. Existing Nim binary surface:
   `runtime-nim/src/bony/binary/semantic.nim` and
   `runtime-nim/src/bony/binary/framing.nim`. This slice should define the
   contract and generated registry surface, not enable `.bnb` state-machine
   playback.
8. Dart model and loader surface:
   `runtime-dart/lib/src/model.dart`, `runtime-dart/lib/src/loader.dart`,
   `runtime-dart/lib/src/anim.dart`, and
   `runtime-dart/lib/src/statemachine.dart`. Dart already carries animations
   and state machines on `SkeletonData`; the binary loader currently leaves
   those fields empty.
9. CLI and user-facing gate docs: `cli/bony_cli.nim` and `cli/README.md`.
   Existing `.bnb` state-machine rejection should remain until the runtime
   implementation slice explicitly removes it.
10. Conformance assets, schemas, and harnesses:
    `conformance/assets/m8_rig.bony`,
    `conformance/scripts/m8_gesture_story.json`,
    `conformance/assets/m9_non_scalar_rig.bony`,
    `scripts/ci/schema_validate_assets.py`,
    `scripts/ci/round_trip_run.py`, and related M6/M8/M9 fixture tests.
11. Recent project history: recent commits added state-machine input script
    execution and the binary state-machine milestone prompts. This plan is step
    1 of the binary follow-up chain, before runtime support and conformance.

### Success Criteria

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
- Define validation rules for timeline kinds already implemented locally: bone
  scalar/vector/inherit timelines, slot attachment/color/two-color/sequence
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
- Document whether Nim should extend `SkeletonData` or introduce a
  project-owned loaded-asset aggregate for animations and state machines. The
  decision must explain how `.bony -> .bnb -> .bony` preserves
  animation/state-machine data.
- Add focused codegen/generator tests proving the new registry/default/schema
  surface is append-only and generated consistently.
- Verification commands should include at minimum:

```bash
python3 codegen/generate.py --check
python3 -m unittest discover -s codegen -p 'test_*.py'
python3 scripts/ci/schema_validate_assets.py
```

### Constraints

- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source, importer source, generated
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
- Do not remove the current `.bnb` state-machine playback rejection in
  `cli/bony_cli.nim` in this contract slice; runtime acceptance belongs to the
  follow-up implementation slice.
- Treat generated files as outputs of `codegen/generate.py`, not independent
  hand-maintained sources.

---

## Your Task

Analyze this codebase change and create a comprehensive Beads task graph using
the `bd` CLI. Beads provides dependency-aware task management for multi-agent
execution.

Before creating the task graph, you MUST first analyze the affected areas of the
codebase:

1. Check whether `docs/specs/` and `docs/adr/` exist. In the current tree they
   do not; record that absence rather than inventing ADR context.
2. Examine the directory/module structure of the affected areas listed above.
3. Identify key interfaces, APIs, and integration points that must be preserved.
4. Note existing test patterns and coverage in the affected areas.
5. Assess risk areas where changes could break existing functionality.

Use your analysis to make each bead specific. Reference actual file paths,
module names, and patterns you observed.

Then generate a shell script that creates the complete task graph.

IMPORTANT: Your ONLY deliverable is a bash shell script with `bd create` and
`bd dep add` commands. Not an implementation plan. Not a design document. Not a
code review. A runnable `.sh` script.

---

## Output Format

Generate a shell script that creates the full task graph. The script should:

1. Initialize Beads if needed.
2. Create one parent epic (`bd create -t epic`) representing the whole change,
   capturing its ID into `$EPIC`.
3. Create all task beads with appropriate priorities, each parented to the epic
   via `--parent "$EPIC"`.
4. Establish dependencies between task beads as ordering edges only. Never add a
   dependency to or from the epic.
5. Add labels for phase grouping.

### Example Output

```bash
#!/bin/bash
# Project: bony
# Change: Define project-owned .bnb contract for serialized animations and state machines
# Generated: 2026-06-29

set -e

if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating change beads..."

EPIC=$(bd create "Epic: Define .bnb animation and state-machine contract" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress

# Replace the example below with the real task graph.
ANALYZE=$(bd create "Analyze existing local animation/state-machine JSON surfaces and document the binary contract boundaries" -p 0 --label analysis --parent "$EPIC" --silent)
DOC_CONTRACT=$(bd create "Write docs/binary-animation-state-machine-contract.md covering canonical order, references, defaults, and validation ownership" -p 0 --label docs --parent "$EPIC" --silent)
bd dep add "$DOC_CONTRACT" "$ANALYZE"

echo ""
echo "Bead graph created! View with:"
echo "  bd show $EPIC"
echo "  bd children $EPIC"
echo "  bd ready"
```

---

## Bead Creation Guidelines

### Epic / Hierarchy

- Create exactly one parent epic for the whole change:
  `EPIC=$(bd create "Epic: <change summary>" -t epic -p 0 --label epic --silent)`.
- Parent every task bead to it with `--parent "$EPIC"`.
- Mark the epic in progress immediately with
  `bd update "$EPIC" --status in_progress` so it does not appear as ready work.
- Never add a blocking dependency to or from the epic. Use `--parent` for
  membership and `bd dep add CHILD PARENT` only for ordering between task beads.
- The epic must have at least two children.

### Priority Levels

- `-p 0` = Critical: early analysis, contract decisions, shared registry
  ownership, or high-risk gates.
- `-p 1` = High: core docs/registry/default/schema work.
- `-p 2` = Medium: focused tests and documentation polish.
- `-p 3` = Low: cleanup and optional follow-up filing.

### Labels

Use `--label` to group beads by phase:

- `analysis`
- `contract`
- `registry`
- `codegen`
- `testing`
- `docs`
- `cleanup`

### Dependency Rules

1. Never create cycles.
2. Analysis and contract decisions should complete before registry/default
   mutation begins.
3. Registry/default changes should complete before generated artifact updates.
4. Generated artifact updates should complete before schema/conformance
   validation.
5. Use `bd dep add CHILD PARENT` where `CHILD` depends on `PARENT`.
6. Keep independent documentation review, generator tests, and validation tasks
   parallel where possible after their true prerequisites are done.

### Contract-Specific Task Coverage

Ensure the graph includes separate beads for:

- Analyzing the local JSON/runtime surface in Nim and Dart.
- Choosing and documenting the binary object family shape: parent records,
  child records, packed `bytes` payloads where appropriate, and why.
- Defining canonical order, child-object adjacency, string table traversal, and
  default omission implications.
- Defining reference semantics after binary load for bones, slots, clips,
  inputs, layers, states, listeners, and attachments.
- Defining validation ownership for all existing timeline/state-machine kinds.
- Deciding whether Nim extends `SkeletonData` or introduces a loaded-asset
  aggregate, including `.bony -> .bnb -> .bony` preservation.
- Appending M3 and M8 registry entries in `registry/wire.yml` only within
  allocated ranges.
- Updating `spec/defaults.yml` only for needed generated defaults.
- Regenerating `runtime-nim/src/bony/generated/wire.nim`,
  `runtime-dart/lib/src/generated/wire.dart`, and `spec/bony.schema.json`
  through `codegen/generate.py`.
- Adding focused generator tests proving append-only registry/default/schema
  behavior and generated consistency.
- Validating existing conformance assets and recording the minimum verification
  commands from the success criteria.
- Filing explicit follow-up beads if implementation or conformance work is
  discovered that belongs to prompt 03 or 04 instead of this contract slice.

### File Reservation Planning

Add reservation notes into bead descriptions for shared file surfaces:

- Registry/default/codegen surface:
  `registry/wire.yml`, `spec/defaults.yml`, `codegen/generate.py`,
  `codegen/test_generate.py`, `spec/bony.schema.json`,
  `runtime-nim/src/bony/generated/wire.nim`,
  `runtime-dart/lib/src/generated/wire.dart`.
- Contract docs:
  `docs/binary-animation-state-machine-contract.md`,
  `docs/binary-canonicalization.md`,
  `docs/load-validation-contract.md`, `docs/README.md`.
- Runtime model references for analysis only in this slice:
  `runtime-nim/src/bony/anim/**`, `runtime-nim/src/bony/statemachine/**`,
  `runtime-nim/src/bony/jsonio.nim`, `runtime-nim/src/bony/model.nim`,
  `runtime-dart/lib/src/model.dart`, `runtime-dart/lib/src/loader.dart`.

---

## Verification Steps

After generating the script:

1. Run it: `chmod +x setup-beads.sh && ./setup-beads.sh`.
2. Check the rollup: `bd children "$EPIC"` should list every task bead.
3. Check ready work: `bd ready` should show initial analysis/prep tasks and not
   the epic.
4. Check no cycles: `bd dep cycles` should report none.

The generated task graph must require final implementation verification with at
least:

```bash
python3 codegen/generate.py --check
python3 -m unittest discover -s codegen -p 'test_*.py'
python3 scripts/ci/schema_validate_assets.py
```

---

## Completeness Checklist

Ensure your task graph includes:

- A single parent epic with every task bead parented to it.
- Analysis of current implementation in affected areas.
- Contract decision beads before registry/default/schema edits.
- Append-only registry/default tasks constrained to M3 and M8 key bands.
- Generated artifact update tasks through `codegen/generate.py`.
- Generator tests and existing asset schema validation.
- Documentation updates and index linkage.
- Clean-room/provenance review.
- Explicit out-of-scope follow-up filing for runtime `.bnb` playback support
  and conformance work that belongs to later prompts.
- Clear dependency chains with no cycles.
