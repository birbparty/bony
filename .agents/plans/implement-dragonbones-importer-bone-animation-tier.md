# Big Change Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown for a change to an existing codebase. This task graph will be executed by AI agents working in parallel, coordinated through MCP Agent Mail with file reservations to prevent conflicts.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary analysis, preparation, implementation, testing, and documentation tasks. Go beyond the basics -- consider edge cases, error handling, security considerations, backwards compatibility, and integration points. Each task should be specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

<critical_constraint>
You must NOT implement any of the changes yourself. Your ONLY output is a bash shell script containing `bd create` and `bd dep add` commands. Do NOT use `bd add` -- the correct command is `bd create`. Do not write code. Do not create files other than the shell script. Do not modify existing files. Read and analyze the codebase, then produce the script.

The script MUST create a single parent **epic** first (`bd create -t epic`) and parent **every** task bead to it via `--parent "$EPIC"`, so the whole change is one trackable rollup. The epic is an organizational rollup only -- never make it a blocking dependency (do NOT `bd dep add` to or from the epic; `bd dep add` is for real ordering edges between task beads, and a blocking edge on an epic both excludes it wrongly and inverts `bd dep tree`). Membership is the `--parent` relationship, nothing else.

This repository already has open feature issue `bony-0vu9` for this exact scope. The generated script must make the new epic explicitly replace or complete that tracker rather than leaving duplicate work open. Prefer `bd supersede bony-0vu9 --with="$EPIC"` after creating the epic if the local `bd` command supports it; otherwise add a clear `bd update bony-0vu9 --notes` command that names the new epic as the task graph for `bony-0vu9` and add a final task that closes `bony-0vu9` only after the full epic verifies. Do not leave `bony-0vu9` as an unrelated open blocker for `bony-dqsn`.
</critical_constraint>

## Change Information

### Change Type
NEW_FEATURE

### Description
Implement the DragonBones importer bone-animation tier already specified by the project-owned design note.

`docs/dragonbones-importer-design.md` defines a clean-room Tier 1 importer that includes bone `translateFrame`, `rotateFrame`, and `scaleFrame` animation channels. The current CLI importer in `cli/bony_cli.nim` imports static bones, slots, default skin image displays, and setup transforms, but it does not parse or emit DragonBones animation clips. It also has a path where animation can be present and omitted unless `--setup-only` is used.

Implement the specified bone-animation tier:

- Extend the importer-owned adapter model in `cli/bony_cli.nim` with animation, bone-channel, and per-channel frame records as described in `docs/dragonbones-importer-design.md`.
- Parse only the project-owned input contract already recorded in the design note.
- Emit bony-native `AnimationClip` data for supported bone translate, rotate, and scale channels using the repository's existing animation model and JSON writer.
- Reject slot channels, mesh displays, Bezier curves, non-zero easing, `clockwise`, negative scale, and other out-of-tier features with deterministic diagnostics.
- Add CLI fixtures that compare canonical `.bony` output and at least one nonzero-time golden from the imported animation.

Do not read external DragonBones runtime/importer code, generated schemas, or third-party prose. This slice is driven by the local design note and user-supplied fixture JSON only.

### Links to Relevant Documentation
- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md`
- DragonBones importer design: `docs/dragonbones-importer-design.md`
- Animation/state-machine boundary: `docs/animation-state-machine-contract-boundaries.md`
- Loaded asset shape: `docs/nim-loaded-asset-shape.md`
- CLI importer: `cli/bony_cli.nim`
- Nim animation model and JSON/Binary preservation:
  - `runtime-nim/src/bony/anim/timelines.nim`
  - `runtime-nim/src/bony/anim/mixer.nim`
  - `runtime-nim/src/bony/jsonio.nim`
  - `runtime-nim/src/bony/binary/semantic.nim`
- Existing CLI tests:
  - `runtime-nim/tests/test_smoke.nim`
  - `runtime-nim/tests/test_cli_pose.nim`
- Existing Beads issue: `bony-0vu9`

### Affected Areas
- `cli/bony_cli.nim`: primary implementation surface. The DragonBones importer starts around the `# ===== DragonBones Importer =====` section. Existing adapter records include `DbTransform`, `DbDisplay`, `DbSkinSlotEntry`, `DbSkin`, `DbBoneEntry`, `DbSlotEntry`, and `DbArmature`; parsing currently records `hasAnimation` only and `importDragonbones` writes `toBonyJson(data)` from setup-only `SkeletonData`.
- `runtime-nim/src/bony/anim/timelines.nim`: use existing exported constructors and kinds such as `animationClip`, `boneScalarTimeline`, `boneVectorTimeline`, `scalarKeyframe`, `vector2Keyframe`, `rotateTimeline`, `translateTimeline`, and `scaleTimeline`. The task graph must not require changes to animation sampling semantics.
- `runtime-nim/src/bony/asset.nim` and `runtime-nim/src/bony/jsonio.nim`: use `BonyAsset` plus `toBonyJson(asset)` so imported skeletons can carry `animations` while static imports can remain skeleton-only where appropriate.
- `runtime-nim/src/bony/binary/semantic.nim`: binary round-trip preservation should be validated for imported animations, but the importer tier should not introduce new registry keys or generated schema changes.
- `runtime-nim/tests/test_smoke.nim`: existing DragonBones smoke coverage lives near the minimal `_ske.json` import test and rejection fixtures for mesh display, invalid slot parent, and display transform. Extend or split this coverage for animation fixtures, canonical JSON, diagnostics, and partial-output prevention.
- `runtime-nim/tests/test_cli_pose.nim` and CLI pose/play paths in `cli/bony_cli.nim`: use an existing normal runtime sampling path for at least one nonzero-time numeric golden after importing an animation, so importer output is verified through pose sampling rather than string-only inspection. If current `play --t` or golden-generation commands reject nonzero clip time for plain clips, the task graph must either use an existing state-machine/input-script path or add a narrow CLI sampling helper; do not broaden this importer tier into general playback work.
- `docs/dragonbones-importer-design.md`, `docs/CLEANROOM.md`, and `docs/PROVENANCE.md`: binding local design and clean-room constraints. No `docs/specs/` or `docs/adr/` directories are present in this repository, so these linked documents are the relevant architecture context.
- `.agents/big-change-prompts/50-tooling-dragonbones-bone-animation-import.md`: source planning prompt for this change. Keep task graph wording aligned with this scope.

Recent repo activity shows adjacent importer/tooling work, including atlas-backed region texture metadata and nested rig composition conformance, so the task graph should reserve shared CLI/test surfaces carefully.

### Success Criteria
- `bony import-dragonbones` emits bony animation clips for supported `translateFrame`, `rotateFrame`, and `scaleFrame` channels.
- Imported channel times use `armature.frameRate`; each non-empty channel's `duration: 0` terminator is emitted as the endpoint keyframe; duration validation makes clip duration equal `animation.duration / armature.frameRate`.
- `--setup-only` remains the explicit way to suppress valid animation. With `--setup-only`, importer output stays setup/static-only and animation channel validation is skipped except for structural errors that prevent parsing the armature. Without `--setup-only`, supported animation is preserved and unsupported animation fails rather than being silently dropped.
- Tests cover linear translate, rotate, and scale channels; step/hold behavior for absent or null `tweenEasing`; a single-channel animation that holds other channels and omitted animated bones at rest; a no-animation static rig; and a nonzero-time numeric golden generated through a normal runtime sampling path.
- Rejection fixtures cover at least `clockwise`, non-zero `tweenEasing`, well-formed `curve`, malformed `curve`, slot channels, invalid bone channel references, bad duration sums, and partial-output prevention on failure.
- Diagnostic text is deterministic and does not copy third-party docs prose.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`

### Constraints
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime source, importer source, generated definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- DragonBones field names may appear only at the importer parser boundary and in importer-owned fixtures/diagnostics.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not implement DragonBones mesh displays, slot color/display animation, IK/constraint import, atlas import, multiple-armature composition, negative scale, Bezier easing, or shortest-arc `clockwise` handling.
- Do not implement display transform mapping in this bone-animation tier. Although `docs/dragonbones-importer-design.md` describes display transform mapping for a broader importer target, current code rejects non-identity display transforms and this prompt preserves that behavior.
- Do not change bony runtime animation semantics to fit DragonBones input.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/specs/` and `docs/adr/` for existing architectural decisions. If absent, explicitly note that the local design/clean-room docs listed above are the controlling context.
2. Examine the directory/module structure of the affected areas listed above.
3. Identify key interfaces, APIs, and integration points that must be preserved.
4. Note existing test patterns and coverage in the affected areas.
5. Assess risk areas where changes could break existing functionality.

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
6. **Use rich task metadata**: every generated task bead should include a concrete `--description` and `--acceptance` describing file reservations, clean-room constraints, expected verification, and how the task avoids broadening the importer scope. Do not rely on title-only tasks except for the parent epic.

### Example Output

```bash
#!/bin/bash
# Project: bony
# Change: Refactor auth middleware for compliance
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

EPIC=$(bd create "Epic: Refactor auth middleware for compliance" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work -- keep it out of `bd ready`

# ========================================
# Phase 1: Analysis & Preparation
# ========================================

ANALYZE_CURRENT=$(bd create "Analyze current auth middleware implementation in src/auth/ -- document all session token storage patterns and consumer dependencies" -p 0 --label analysis --parent "$EPIC" --silent)

IDENTIFY_DEPS=$(bd create "Map all modules importing from src/auth/ and catalog their usage patterns" -p 0 --label analysis --parent "$EPIC" --silent)

CHAR_TESTS=$(bd create "Add characterization tests capturing current auth middleware behavior before refactoring" -p 0 --label prep --parent "$EPIC" --silent)
bd dep add $CHAR_TESTS $ANALYZE_CURRENT

# ========================================
# Phase 2: Core Implementation
# ========================================

IMPL_NEW_STORAGE=$(bd create "Implement compliant session token storage in src/auth/session.ts replacing in-memory store" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $IMPL_NEW_STORAGE $CHAR_TESTS
bd dep add $IMPL_NEW_STORAGE $IDENTIFY_DEPS

IMPL_MIGRATION=$(bd create "Create migration script for existing session data to new storage format" -p 1 --label impl --parent "$EPIC" --silent)
bd dep add $IMPL_MIGRATION $IMPL_NEW_STORAGE

UPDATE_CONSUMERS=$(bd create "Update all consumer modules to use new auth middleware API surface" -p 1 --label impl --parent "$EPIC" --silent)
bd dep add $UPDATE_CONSUMERS $IMPL_NEW_STORAGE

# ========================================
# Phase 3: Testing & Validation
# ========================================

UNIT_TESTS=$(bd create "Add unit tests for new session storage implementation" -p 1 --label testing --parent "$EPIC" --silent)
bd dep add $UNIT_TESTS $IMPL_NEW_STORAGE

INTEGRATION_TESTS=$(bd create "Add integration tests for auth flow end-to-end with new middleware" -p 1 --label testing --parent "$EPIC" --silent)
bd dep add $INTEGRATION_TESTS $UPDATE_CONSUMERS

REGRESSION_CHECK=$(bd create "Run full regression suite and verify characterization tests still pass" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $REGRESSION_CHECK $INTEGRATION_TESTS
bd dep add $REGRESSION_CHECK $UNIT_TESTS

# ========================================
# Phase 4: Cleanup & Documentation
# ========================================

UPDATE_DOCS=$(bd create "Update auth middleware documentation and API reference" -p 2 --label docs --parent "$EPIC" --silent)
bd dep add $UPDATE_DOCS $REGRESSION_CHECK

CLEANUP=$(bd create "Remove deprecated session storage code and update changelog" -p 3 --label cleanup --parent "$EPIC" --silent)
bd dep add $CLEANUP $REGRESSION_CHECK

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
- Consider feature flag for gradual rollout only if relevant. For this CLI importer tier, prefer strict default behavior over runtime feature flags unless analysis finds an existing CLI pattern.
- Include documentation and changelog updates only if implementation discovers that `docs/dragonbones-importer-design.md` or CLI usage text is stale.

### DragonBones Importer-Specific Guidance
- Keep all DragonBones field-name handling inside `cli/bony_cli.nim` parser-boundary code and importer-owned fixtures.
- Preserve existing setup-only static import behavior and existing rejection diagnostics for mesh displays, bad slot parents, and non-identity display transforms.
- Add parser records for animations, per-bone animation channels, and per-channel frames before adding emission logic.
- Emit one bony endpoint keyframe for each valid DragonBones channel terminator frame (`duration: 0`) and validate the duration sum before building output. Include step/hold keyframes for absent or null `tweenEasing`, and linear keyframes for `tweenEasing = 0`.
- Validate unsupported features before writing the output path. Include a partial-output prevention bead that proves failed imports do not create an absent output path and do not overwrite a preexisting sentinel output file. Prefer validating fully before any write; use atomic temp-write/rename only if needed.
- Clarify `--setup-only` in implementation tasks: it is the opt-in static import mode and may ignore otherwise unsupported animation details, but normal import mode must reject unsupported animation rather than dropping it.
- Use the existing `AnimationClip`/timeline constructors and `BonyAsset` JSON writer instead of adding importer-specific JSON string construction.
- Keep binary round-trip verification as validation, not as a request for new binary registry or semantic schema changes.
- Treat runtime/model/schema files as read-mostly integration surfaces. The default implementation should not edit `runtime-nim/src/bony/anim/timelines.nim`, `runtime-nim/src/bony/jsonio.nim`, `runtime-nim/src/bony/asset.nim`, or `runtime-nim/src/bony/binary/semantic.nim`; allow narrow fixes only when a proven existing bug blocks importer output that already uses public APIs.

---

## File Reservation Planning

For each major work area, note the file patterns that will need exclusive reservation:

```bash
# DragonBones importer parser/emitter: cli/bony_cli.nim
# CLI smoke and rejection fixtures: runtime-nim/tests/test_smoke.nim
# Nonzero-time pose golden through CLI path: runtime-nim/tests/test_cli_pose.nim and cli/bony_cli.nim
# Animation model and JSON writer integration checks, read-mostly: runtime-nim/src/bony/anim/timelines.nim, runtime-nim/src/bony/asset.nim, runtime-nim/src/bony/jsonio.nim
# Binary round-trip validation, read-mostly: runtime-nim/src/bony/binary/semantic.nim, runtime-nim/tests/test_smoke.nim
# Clean-room/design docs: docs/dragonbones-importer-design.md, docs/CLEANROOM.md, docs/PROVENANCE.md
```

These shared files have high test and feature overlap. Split beads so parser model, emission logic, acceptance fixtures, rejection fixtures, and final verification can be worked independently with clear reservation boundaries.

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
- [ ] Analysis of `docs/dragonbones-importer-design.md`, `cli/bony_cli.nim`, animation constructors, asset JSON emission, and current CLI tests
- [ ] Characterization tests for current setup-only/static DragonBones importer behavior before changing importer output behavior
- [ ] Parser adapter tasks for animation clips, bone channels, frame timing, easing, and unsupported-feature detection
- [ ] Emission tasks that convert supported channels into bony-native `AnimationClip` timelines through existing constructors, including terminator endpoint keyframes and clip duration validation
- [ ] Acceptance tests for translate, rotate, scale, step/hold easing, single-channel/rest-hold behavior, omitted animated bones holding setup pose, static no-animation rigs, canonical output, and nonzero-time pose golden
- [ ] Rejection tests for `clockwise`, non-zero `tweenEasing`, well-formed and malformed `curve`, slot animation channels, invalid animated bone references, bad duration sums, and partial-output prevention for both absent and preexisting outputs
- [ ] Regression coverage that existing static importer rejections remain intact, including mesh display, bad slot parent, non-identity display transform, unsupported version, non-normal blend mode, parent cycles, extra transform keys, non-finite/zero scale, negative scale, and invalid `displayIndex`
- [ ] Binary round-trip validation for imported animations
- [ ] Full verification bead covering `python3 codegen/generate.py --check`, `python3 -m unittest discover -s codegen -p 'test_*.py'`, and `make test`
- [ ] Documentation update bead only for local docs/CLI usage drift found during implementation
- [ ] Clean-room compliance notes in relevant bead descriptions, including the prohibition on external DragonBones/Spine/Rive/Live2D/Lottie source or copied docs prose
- [ ] Beads tracking step that supersedes or links `bony-0vu9` to the generated epic and ensures `bony-dqsn` is unblocked only after the implementation verifies
