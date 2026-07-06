# Big Change Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown for a change to an existing codebase. This task graph will be executed by AI agents working in parallel, coordinated through MCP Agent Mail with file reservations to prevent conflicts.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary analysis, preparation, implementation, testing, and documentation tasks. Go beyond the basics -- consider edge cases, error handling, security considerations, backwards compatibility, and integration points. Each task should be specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

<critical_constraint>
You must NOT implement any of the changes yourself. Your ONLY output is a bash shell script containing `bd create` and `bd dep add` commands. Do NOT use `bd add` -- the correct command is `bd create`. Do not write code. Do not create files other than the shell script. Do not modify existing files. Read and analyze the codebase, then produce the script.

The script MUST create a single parent **epic** first (`bd create -t epic`) and parent **every** task bead to it via `--parent "$EPIC"`, so the whole change is one trackable rollup. The epic is an organizational rollup only -- never make it a blocking dependency (do NOT `bd dep add` to or from the epic; `bd dep add` is for real ordering edges between task beads, and a blocking edge on an epic both excludes it wrongly and inverts `bd dep tree`). Membership is the `--parent` relationship, nothing else.
</critical_constraint>

## Change Information

### Change Type
MIGRATION -- this is a Dart parity port of an existing project-owned Nim reference implementation and M21 conformance surface. No new serialized listener semantics, helper kinds, registry keys, importer behavior, or debug rendering are in scope.

### Description
Port pointer helper listener dispatch to the Dart runtime and match the M21 conformance goldens.

The serialized contract and Nim reference slice have landed. Dart already has the shared model fields for pointer listener kinds and helper targets in `runtime-dart/lib/src/model.dart`, and the loader already parses and validates pointer listener JSON/BNB records in `runtime-dart/lib/src/loader.dart`. The remaining Dart gap is runtime behavior: helper world queries and hit testing, pointer listener input mutation, richer listener event payloads, event ordering relative to transitions, and M21 `.bony`/`.bnb` golden replay.

Match the project-owned contract and Nim behavior exactly:

- Pointer listeners target existing non-rendered helper attachments (`point` and `boundingBox`) only.
- Point hit testing uses the helper's world position and listener `hitRadius`; a pointer is inside when distance is `<= hitRadius`.
- Bounding-box hit testing uses transformed polygon vertices and the helper geometry boundary tolerance.
- Pointer listeners mutate their configured bool/number/trigger input before transition evaluation.
- Pointer listener events are appended in listener array order, before any later transition/lifecycle events caused by the mutated input.
- Listener events stay in the existing state-machine `events` channel, not `animationEvents`.
- Dart must match every `m21_pointer_listener_*` golden for both `.bony` and `.bnb` assets within `1e-4`.

### Links to Relevant Documentation
- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md` (capability categories only)
- Pointer listener contract: `docs/pointer-helper-listener-contract.md`
- Helper geometry contract: `docs/helper-geometry-attachment-contract.md`
- Float math/tolerance: `docs/float-math-contract.md`
- Conformance docs/assets: `conformance/README.md`, `conformance/assets/m21_pointer_listener_rig.bony`, `conformance/assets/bnb/m21_pointer_listener_rig.bnb`, `conformance/scripts/m21_pointer_listener_story.json`, `conformance/goldens/m21_pointer_listener_{rest,enter,down,move,up,exit}.json`
- Nim reference: `runtime-nim/src/bony/statemachine/core.nim`, `runtime-nim/src/bony/transform.nim`, `runtime-nim/tests/test_pointer_listener.nim`, `runtime-nim/tests/test_m21_pointer_listener_conformance.nim`
- Dart seams: `runtime-dart/lib/src/model.dart`, `runtime-dart/lib/src/loader.dart`, `runtime-dart/lib/src/statemachine.dart`, `runtime-dart/lib/src/transform.dart`, `runtime-dart/lib/bony.dart`
- Dart test patterns: `runtime-dart/test/m8_statemachine_test.dart`, `runtime-dart/test/helper_geometry_attachment_test.dart`, `runtime-dart/test/m10_conformance_test.dart`, `runtime-dart/test/m5_ik_story_test.dart`, `runtime-dart/test/m5_physics_story_test.dart`, `runtime-dart/test/m18_deform_story_test.dart`, `runtime-dart/test/m19_event_story_test.dart`
- Beads: parent `bony-1umq`; child `bony-lrfz`; dependency `bony-3moo` is closed.

### Affected Areas
- **`runtime-dart/lib/src/model.dart`** -- `StateMachineListenerKind` already includes `pointerDown`, `pointerUp`, `pointerEnter`, `pointerExit`, and `pointerMove`; `PointerHelperTargetKind` already includes `point` and `boundingBox`; `StateMachineListener` already carries `slot`, `targetKind`, `target`, `hitRadius`, `input`, `boolValue`, and `numberValue`. Extend only if runtime events need model-adjacent public value types.
- **`runtime-dart/lib/src/loader.dart`** -- JSON and `.bnb` pointer listener parsing/validation already exists, including slot/target/input/radius/value checks. Add focused regression coverage for BNB listener loading and malformed cases, but do not change wire semantics unless an actual mismatch with `docs/pointer-helper-listener-contract.md` or Nim is found.
- **`runtime-dart/lib/src/transform.dart`** -- add public or package-visible helper geometry query functions equivalent to Nim `worldPointAttachmentPose`, `worldBoundingBoxAttachmentPolygon`, `pointInHelperPolygon`, `pointerHitsPointTarget`, and `pointerHitsBoundingBoxTarget`. Reuse existing `Affine2`, `_transformPoint`, `computeWorldTransforms`, and world rotation math patterns. Boundary tolerance must match `docs/helper-geometry-attachment-contract.md` / Nim behavior.
- **`runtime-dart/lib/src/statemachine.dart`** -- enrich `StateMachineListenerEvent` so pointer events can expose slot, target kind/name, input, input kind, bool/number/trigger value, pointer coordinates, and pointer presence without breaking lifecycle event callers. Add `dispatchPointerListeners` or the local-pattern equivalent on `StateMachineRuntime`, validate pointer kind, hit active helper targets, mutate inputs, and append events before callers evaluate transitions.
- **`runtime-dart/lib/bony.dart`** -- ensure any new public helper query or dispatch types/functions needed by tests and host code are exported through the package root.
- **`runtime-dart/test/m8_statemachine_test.dart`** -- currently includes pointer listener JSON loading and malformed JSON validation. Extend or keep as loader-focused coverage for JSON/BNB listener records and validation.
- **`runtime-dart/test/helper_geometry_attachment_test.dart`** -- currently covers helper attachment JSON/BNB loading. Extend or add focused tests for point radius, bounding-box inside/outside/boundary tolerance, transformed helper poses, and malformed helper query inputs.
- **`runtime-dart/test/m21_pointer_listener_test.dart`** -- preferred new focused conformance test mirroring the style of `m5_ik_story_test.dart`, `m5_physics_story_test.dart`, `m18_deform_story_test.dart`, and `m19_event_story_test.dart`. It should replay `conformance/scripts/m21_pointer_listener_story.json` against both `.bony` and `.bnb` assets, compare listener events, state machine state, world transforms, draw batches, and helper slot metadata against all six M21 goldens.
- **`runtime-dart/test/m10_conformance_test.dart`** -- optional alternative for setup/golden plumbing only; do not force M21's state-machine pointer story into the setup-pose-only helper if a focused test is clearer.
- **Reference-only surfaces** -- do not modify `runtime-nim/`, `conformance/assets/m21_pointer_listener_rig.bony`, `conformance/assets/bnb/m21_pointer_listener_rig.bnb`, `conformance/scripts/m21_pointer_listener_story.json`, `conformance/goldens/`, registry files, defaults, or generated wire files unless the implementation discovers a true contract defect that requires stopping this Dart port and revisiting step 1 surfaces.

No `docs/specs/` or `docs/adr/` directory is present in this checkout, so the authoritative project architecture context for this change is the contract docs listed above plus the existing Dart/Nim runtime and conformance patterns.

### Success Criteria
- Dart loads the same pointer listener JSON and `.bnb` surface as Nim, including listener kind, slot, target kind/name, point `hitRadius`, input, and bool/number/trigger value behavior.
- Dart rejects malformed pointer listener records where Dart has matching validation coverage: lifecycle fields on pointer listeners, pointer fields on lifecycle listeners, unknown slot/target/input, invalid target kind, missing or invalid point `hitRadius`, invalid bounding-box `hitRadius`, missing bool/number values, and forbidden trigger values.
- Dart helper hit tests match Nim behavior for point radius and bounding-box polygon hits, including transformed helper coordinates and boundary tolerance.
- `StateMachineRuntime.dispatchPointerListeners` or its chosen local-pattern API mutates the configured input before transition evaluation and appends pointer events in normalized listener array order.
- Pointer listener event payloads match Nim/M21 semantics: listener name/kind, slot, target kind/name, input, input kind, bool/number/trigger value, pointer coordinates, and pointer-presence marker. Lifecycle events remain compatible.
- The `down` M21 sample proves ordering by producing the pointer event first, followed by `idle_exit`, `idle_to_pressed`, and `pressed_enter` after `update(0.0)` or equivalent transition evaluation that preserves pointer events.
- Dart matches every M21 JSON golden and every M21 BNB golden within `1e-4`: `rest`, `enter`, `down`, `move`, `up`, and `exit`.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`
  - `cd runtime-dart && dart test`

### Constraints
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime source, importer source, generated definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories, never for algorithms, identifiers, event ordering, or serialized wire shape.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not add pointer listener kinds, fields, registry keys, input-script semantics, or helper target kinds beyond the contract from `docs/pointer-helper-listener-contract.md` and the Nim reference from `bony-3moo`.
- Do not add visible debug rendering for helper attachments.
- Keep the serialized contract stable. If a defect is found in the contract, stop and update the contract/docs/registry/defaults/generated surfaces rather than creating Dart-only behavior.
- Keep the slice small enough for one meaningful implementation session; prefer one focused M21 test file over broad conformance harness churn.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/specs/` and `docs/adr/` for existing architectural decisions
2. Examine the directory/module structure of the affected areas listed above
3. Identify key interfaces, APIs, and integration points that must be preserved
4. Note existing test patterns and coverage in the affected areas
5. Assess risk areas where changes could break existing functionality

Use your analysis to make each bead specific -- reference actual file paths, module names, and patterns you observed.

Then generate a shell script that creates the complete task graph.

**IMPORTANT: Your ONLY deliverable is a bash shell script with `bd create` commands. Not an implementation plan. Not a design document. Not a code review. A runnable `.sh` script.**

---

## Output Format

Generate a shell script that creates the full task graph. The script should:

1. **Initialize Beads** (if not already initialized)
2. **Create one parent epic** (`bd create -t epic`) representing the whole change, capturing its ID into `$EPIC`
3. **Create all task beads** with appropriate priorities, each parented to the epic via `--parent "$EPIC"`
4. **Establish dependencies** between task beads (ordering edges only -- never to or from the epic)
5. **Add labels** for phase grouping (child beads inherit the epic's labels unless `--no-inherit-labels`)

### Example Output

```bash
#!/bin/bash
# Project: bony
# Change: Port pointer helper listener dispatch to Dart
# Generated: 2026-07-06

set -e

# Initialize beads if needed
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating change beads..."

# ========================================
# Parent epic -- every task below is parented to it (--parent "$EPIC").
# The epic is an organizational rollup: it is NEVER given a blocking dep
# (no `bd dep add` to or from it) and is never dispatched as work itself.
# ========================================

EPIC=$(bd create "Epic: Port pointer helper listener dispatch to Dart" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work -- keep it out of `bd ready`

# ========================================
# Phase 1: Analysis & Preparation
# ========================================

ANALYZE_REFERENCE=$(bd create "Analyze Nim pointer helper listener runtime in runtime-nim/src/bony/statemachine/core.nim and runtime-nim/src/bony/transform.nim, documenting dispatch order, hit-test math, event payload fields, and active-skin target resolution" -p 0 --label analysis --parent "$EPIC" --silent)

MAP_DART_SURFACE=$(bd create "Map Dart pointer listener loader/model/runtime seams in runtime-dart/lib/src/model.dart, loader.dart, statemachine.dart, transform.dart, and bony.dart; identify existing validation coverage and public API compatibility constraints" -p 0 --label analysis --parent "$EPIC" --silent)

CHARACTERIZE_EXISTING=$(bd create "Add characterization tests around existing Dart pointer listener JSON parsing and lifecycle event compatibility before runtime dispatch changes" -p 1 --label prep --parent "$EPIC" --silent)
bd dep add "$CHARACTERIZE_EXISTING" "$MAP_DART_SURFACE"

# ========================================
# Phase 2: Runtime Implementation
# ========================================

HELPER_HIT_TESTS=$(bd create "Implement Dart helper world query and hit-test APIs in runtime-dart/lib/src/transform.dart for point poses, bounding-box polygons, polygon boundary tolerance, point-radius hits, and bounding-box hits" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add "$HELPER_HIT_TESTS" "$ANALYZE_REFERENCE"
bd dep add "$HELPER_HIT_TESTS" "$MAP_DART_SURFACE"

EVENT_PAYLOAD=$(bd create "Extend runtime-dart/lib/src/statemachine.dart StateMachineListenerEvent to carry pointer listener payload fields while preserving lifecycle event behavior" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add "$EVENT_PAYLOAD" "$ANALYZE_REFERENCE"
bd dep add "$EVENT_PAYLOAD" "$CHARACTERIZE_EXISTING"

POINTER_DISPATCH=$(bd create "Implement Dart StateMachineRuntime pointer dispatch that validates pointer kinds, resolves active helper targets, mutates bool/number/trigger inputs, emits pointer events in listener order, and leaves transition evaluation to append later lifecycle events" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add "$POINTER_DISPATCH" "$HELPER_HIT_TESTS"
bd dep add "$POINTER_DISPATCH" "$EVENT_PAYLOAD"

EXPORT_API=$(bd create "Export any new public pointer dispatch or helper query API from runtime-dart/lib/bony.dart without exposing debug rendering or new serialized semantics" -p 2 --label impl --parent "$EPIC" --silent)
bd dep add "$EXPORT_API" "$POINTER_DISPATCH"

# ========================================
# Phase 3: Loader and Unit Tests
# ========================================

LOADER_TESTS=$(bd create "Broaden Dart pointer listener loader tests for JSON and BNB in runtime-dart/test/m8_statemachine_test.dart or a focused loader test, covering valid records and malformed validation cases from docs/pointer-helper-listener-contract.md" -p 1 --label testing --parent "$EPIC" --silent)
bd dep add "$LOADER_TESTS" "$MAP_DART_SURFACE"

HIT_TEST_TESTS=$(bd create "Add Dart helper hit-test unit tests covering point radius, bounding-box inside/outside/boundary tolerance, transformed helper coordinates, and query error cases" -p 1 --label testing --parent "$EPIC" --silent)
bd dep add "$HIT_TEST_TESTS" "$HELPER_HIT_TESTS"

DISPATCH_TESTS=$(bd create "Add Dart pointer dispatch tests proving input mutation before transitions, bool/number/trigger behavior, listener array ordering, pointer event payload fields, and lifecycle event compatibility" -p 1 --label testing --parent "$EPIC" --silent)
bd dep add "$DISPATCH_TESTS" "$POINTER_DISPATCH"

# ========================================
# Phase 4: M21 Conformance
# ========================================

M21_REPLAY=$(bd create "Add runtime-dart/test/m21_pointer_listener_test.dart that replays conformance/scripts/m21_pointer_listener_story.json against both M21 .bony and .bnb assets and compares rest/enter/down/move/up/exit goldens within 1e-4" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add "$M21_REPLAY" "$POINTER_DISPATCH"
bd dep add "$M21_REPLAY" "$EXPORT_API"

M21_NONVACUITY=$(bd create "Add non-vacuity assertions for M21 pointer story: down sample pointer event precedes transition events, move/up hit the rotated point, exit mutates hover false, and BNB output matches JSON output" -p 1 --label testing --parent "$EPIC" --silent)
bd dep add "$M21_NONVACUITY" "$M21_REPLAY"

# ========================================
# Phase 5: Verification & Closeout
# ========================================

DOC_AUDIT=$(bd create "Audit docs/pointer-helper-listener-contract.md, docs/helper-geometry-attachment-contract.md, and conformance/README.md for Dart parity status; update only if existing text is stale after the port" -p 2 --label docs --parent "$EPIC" --silent)
bd dep add "$DOC_AUDIT" "$M21_REPLAY"

FULL_VERIFY=$(bd create "Run final verification: python3 codegen/generate.py --check; python3 -m unittest discover -s codegen -p 'test_*.py'; make test; cd runtime-dart && dart test" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add "$FULL_VERIFY" "$LOADER_TESTS"
bd dep add "$FULL_VERIFY" "$HIT_TEST_TESTS"
bd dep add "$FULL_VERIFY" "$DISPATCH_TESTS"
bd dep add "$FULL_VERIFY" "$M21_NONVACUITY"
bd dep add "$FULL_VERIFY" "$DOC_AUDIT"

echo ""
echo "Bead graph created! View with:"
echo "  bd show $EPIC"
echo "  bd children $EPIC"
echo "  bd ready"
```

---

## Bead Creation Guidelines

### Epic / Hierarchy (REQUIRED)
- Create exactly **one parent epic** for the whole change: `EPIC=$(bd create "Epic: <change summary>" -t epic -p 0 --label epic --silent)`.
- Parent **every** task bead to it: add `--parent "$EPIC"` to every `bd create` (children inherit the epic's labels unless you pass `--no-inherit-labels`).
- The epic is a **rollup, not work**: never `bd dep add` to or from it. Membership is `--parent`; `bd dep add` is reserved for real ordering edges *between task beads*. A blocking edge on an epic wrongly keeps it out of (or drops it into) `bd ready` and inverts `bd dep tree`.
- **Keep the epic out of `bd ready`** by marking it active right after creation: `bd update "$EPIC" --status in_progress`. `bd ready` excludes `in_progress`/`blocked`/`deferred`/`hooked`. Do **not** rely on `--exclude-type epic` -- that flag is ineffective on some `bd`/`bn` builds, whereas status-based exclusion works everywhere.
- An epic must have **>= 2 children** to be meaningful -- a one-task change does not need this skill.
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
6. `bd dep add` is for ordering edges **between task beads only** -- never use it to attach a task to the epic (that is `--parent`), and never add a blocking edge to or from the epic

### Task Granularity
- Each bead should be completable in **under 750 lines of code changed**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area

---

## Change-Specific Considerations

### For New Features
- Start with analysis of similar existing features
- Consider feature flag for gradual rollout if relevant
- Plan for A/B testing if relevant
- Include documentation and changelog updates

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

For each major work area, note the file patterns that will need exclusive reservation:

```bash
# Pointer listener Dart port: runtime-dart/lib/src/statemachine.dart, runtime-dart/lib/src/transform.dart, runtime-dart/lib/bony.dart
# Loader/test validation: runtime-dart/lib/src/loader.dart, runtime-dart/test/m8_statemachine_test.dart, runtime-dart/test/helper_geometry_attachment_test.dart
# M21 conformance: runtime-dart/test/m21_pointer_listener_test.dart, runtime-dart/test/m10_conformance_test.dart if touched
# Reference-only: runtime-nim/**, conformance/assets/m21_pointer_listener_rig.bony, conformance/assets/bnb/m21_pointer_listener_rig.bnb, conformance/goldens/** (do not edit)
```

This helps agents claim appropriate file surfaces when they start work.

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check the rollup**: `bd children "$EPIC"` should list every task bead, and `bd dep tree` should show them under the epic with no orphan (un-parented) tasks
3. **Check ready work**: `bd ready` should show initial analysis/prep tasks and **not** the epic. Epics are rollups, never dispatched as work -- and because some `bd`/`bn` builds do not exclude epic-typed issues from `ready` (with `--exclude-type epic` sometimes ineffective), the script marks the epic `in_progress` right after creating it; status-based exclusion keeps it out of `ready` on every build.
4. **Check no cycles**: `bd dep cycles` should report none

---

## Completeness Checklist

Ensure your task graph includes:

- [ ] A single parent epic (`-t epic`); every task bead parented to it via `--parent "$EPIC"`, with no orphan tasks and no blocking dep to/from the epic
- [ ] Analysis of current implementation in affected areas
- [ ] Characterization tests for existing behavior
- [ ] Feature flag or gradual rollout mechanism (if applicable)
- [ ] Core implementation broken into small units
- [ ] Unit tests for new/changed code
- [ ] Integration tests for affected workflows
- [ ] Regression testing plan
- [ ] Documentation updates
- [ ] Migration scripts (if data changes)
- [ ] Rollback plan
- [ ] Cleanup tasks for post-rollout
- [ ] Clear dependency chains with no cycles
