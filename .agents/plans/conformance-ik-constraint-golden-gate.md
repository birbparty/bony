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
NEW_FEATURE — additive cross-runtime conformance coverage. This slice adds a new M5-band IK conformance rig and its committed goldens (numeric golden, `.bnb` binary fixture, input script) plus CI gate/README wiring. It does **not** change runtime evaluation code (IK load + eval already shipped in steps 1–2: `runtime-nim/src/bony/jsonio.nim`, `binary/semantic.nim`, `transform.nim` `applyRuntimeIk`, `constraints/update_cache.nim`) and does **not** modify the CI runners (they auto-enroll fixtures by naming convention). It is the existing "Adding a new milestone" recipe applied to IK, mirroring the `m5_rig` path rig and the `m9_non_scalar_rig` second-asset-in-band precedent.

### Description
Add cross-runtime conformance coverage for IK constraints: a rig asset, numeric golden, binary fixture, input script, and gate wiring.

Steps 1–2 made IK constraints expressible and runtime-evaluable in the Nim reference runtime. This slice (step 3 of 3) makes IK part of the cross-runtime contract by adding a dedicated M5 IK conformance rig and committing its goldens, exactly as the existing M5 path rig (`m5_rig`) and the M9 second-asset precedent (`m9_non_scalar_rig`) do. IK lives in the M5 band, so the asset is named `m5_ik_rig` to sit alongside `m5_rig` without renumbering milestones.

Follow the documented "Adding a new milestone" recipe in `conformance/README.md`: create rig → generate `.bnb` → generate numeric golden → create input script → commit → verify gates.

The IK constraint schema (`spec/bony.schema.json` `$defs/ikConstraint`) is: `name` (string, required), `bones` (array of bone-name strings, `minItems` 1, required), `target` (bone-name string, required), `order` (int, default 0), `mix` (number 0–1, default 1.0), `bendPositive` (bool, default true). The rig's `ikConstraints` array entries must use exactly these keys. The runtime IK solver (`applyRuntimeIk`) is form-(a) mix>0: `mix=1` points the bone exactly at the target, `mix=0` is a no-op rest pose, fractional mix blends **once**.

To exercise the solver at a nonzero time (Success Criteria), follow the M8/M9 input-script pattern: give the rig an animation whose `boneTimeline` moves the IK **target** bone, a `stateMachine` that plays it, and an input script (`bony.input-script.v1`) carrying a `stateMachine` field with named samples whose `inputs` drive that animation. Advancing time moves the target, and the IK solver re-solves to follow it — producing a golden that differs from the `t=0` pose.

### Links to Relevant Documentation
- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research (capability categories only): `docs/comparable-feature-set.md`
- Conformance suite docs + "Adding a new milestone" recipe: `conformance/README.md`
- Numeric-golden format/tolerance (`bony.numeric-golden.v1`, `1e-4`): `conformance/README.md`, `docs/float-math-contract.md`
- Input-script schema: `spec/bony-input-script.schema.json`
- IK constraint schema: `spec/bony.schema.json` (`$defs/ikConstraint`)
- Existing M5 path rig (style template): `conformance/assets/m5_rig.bony`, `conformance/assets/bnb/m5_rig.bnb`, `conformance/goldens/m5_rig_t0.json`, `conformance/scripts/m5_sample.json`
- Second-asset-in-band precedent (incl. animation + state-machine + nonzero-time script): `conformance/assets/m9_non_scalar_rig.bony`, `conformance/goldens/m9_non_scalar_rig_t0.json`, `conformance/scripts/m8_gesture_story.json`
- IK fixture shapes (one/two/chain-bone, mix, bend sign) for authoring reference: `runtime-nim/tests/test_smoke.nim` (`ikConstraintData(...)` cases ~lines 1160–1257)
- CI gate runners (no edits expected): `scripts/ci/conformance_run.py`, `scripts/ci/round_trip_run.py`, `scripts/ci/input_script_run.py`, `scripts/ci/suite_run.py`, `scripts/ci/schema_validate_assets.py`
- CLI commands: `cli/README.md`, `cli/bony_cli.nim` (`json-to-bnb`, `golden-gen`, `play`)
- Step 2 output: a bony CLI binary that emits and round-trips IK constraints (built from `cli/bony_cli.nim` over the IK-aware runtime).

### Affected Areas
**New committed artifacts (the deliverables):**
- `conformance/assets/m5_ik_rig.bony` — new hand-authored rig. Contains: (a) bones forming one-bone, two-bone, and chain (≥3-bone) IK cases with each IK **target bone offset from the unconstrained chain tip** so the `t=0` solved pose visibly differs from the unconstrained pose; **and** (b) a `stateMachine` plus an animation whose `boneTimeline` translates one IK **target** bone, used by the nonzero-time story sample. The rig needs only `skeleton` + `bones` + `ikConstraints` + `animations` + `stateMachines` — **no slots/regions/attachments are required** (the schema requires only `skeleton`+`bones`; IK references bones by name; `golden-gen` emits an empty `drawBatches` and the IK effect shows up in `bones[].world`). Do **not** mirror `m5_rig`'s slot/region/path scaffolding.
- `conformance/assets/bnb/m5_ik_rig.bnb` — generated by CLI `json-to-bnb` (canonical bytes; auto-enrolls into `round_trip_run.py`'s `*_rig.bnb` glob).
- `conformance/goldens/m5_ik_rig_t0.json` — generated by `golden-gen` at `t 0.0` (`bony.numeric-golden.v1`); consumed by `conformance_run.py` for both `.bony` and `.bnb`.
- `conformance/scripts/m5_ik_sample.json` — **setup-pose script only** (no `stateMachine` field): a single `t=0` sample → golden `m5_ik_rig_t0.json`. (This is redundant with the conformance t0 golden but matches the `m5_sample.json` precedent; keep it minimal.)
- `conformance/scripts/m5_ik_story.json` — **separate state-machine story script** (`stateMachine` field set): named samples at `t=0` and ≥1 nonzero `t` whose `inputs` drive the animation that moves the IK target bone. Each sample's golden is named `m5_ik_story_<sampleName>.json` and **every one must be committed** (a missing/misnamed golden reports SKIP in the input-script gate, silently dropping IK coverage). **Sample-name constraints (enforced by the CLI/runner — get these wrong and the gate fails):** every SM sample requires a `name`; names must match `[A-Za-z0-9_.-]` **and contain at least one non-digit** (`SAMPLE_NAME_RE`; a purely numeric name like `"0"` is rejected — use `rest`, `reach`, etc.); names must be unique; and sample **times must be non-decreasing** (`bony_cli.nim:1349`; the harness advances by delta-from-previous-sample, so order and `t` values matter).
- `conformance/goldens/m5_ik_story_<sampleName>.json` — one committed golden **per story sample**. **Generate each with a direct CLI call** (the generator is `golden-gen`, NOT `input_script_run.py` — that runner only *consumes*/compares goldens in a temp dir): `bony golden-gen conformance/assets/m5_ik_rig.bony conformance/goldens/m5_ik_story_<name>.json --state-machine <smName> --input-script conformance/scripts/m5_ik_story.json --sample <name>` (`cli/bony_cli.nim:18`; the SM path bakes the animated pose into `posedData`, then `computeWorldTransforms` re-solves IK against the moved target). Enumerate the exact sample names in the story bead so the filenames are pinned.

> **Why two scripts (structural, not stylistic):** `stateMachine` is a *script-level* field in `input_script_run.py` — if present, *every* sample routes through the state-machine path; if absent, *every* sample is a setup-pose sample. You cannot mix a `t=0` setup sample and an animated nonzero sample in one file. Separately, `golden-gen --t <nonzero>` raises `schemaViolation` via `requireSetupPoseTime` (`cli/bony_cli.nim:174`), so **only** the state-machine path can advance time. This mirrors M8 exactly (`m8_sample.json` non-SM + `m8_gesture_story.json` SM). The animated bone **must be the IK target and must lie outside the solved chain** (not a chain member, not another constraint's output), or the solve overwrites the animation and the nonzero golden is indistinguishable from the static one.

**Edited:**
- `conformance/README.md` — document the new IK rig. **Resolve the table structure first** (the milestone table is one-asset-per-milestone and has no second-asset-under-M5 precedent — m9 was a *new* milestone row): choose either (i) a dedicated IK milestone row, (ii) a second `m5_ik_rig` row under an "M5" band, or (iii) augmenting the existing M5 row's description to name both rigs. Pick one in the docs bead rather than leaving it ambiguous. Also reconcile the image-golden table (`m5_ik_rig` → `pending`, since no PNG golden is produced) and confirm the existing `m9_non_scalar_rig` rows remain.

**Used but not modified (verify, don't touch):**
- `cli/bony_cli.nim` (`json-to-bnb`, `golden-gen`, `play`) — generation tooling.
- CI runners `scripts/ci/{conformance,round_trip,input_script,suite}_run.py`, `scripts/ci/schema_validate_assets.py` — auto-enroll by naming convention; no edits expected (flag if a runner needs a change).
- Runtime IK path: `runtime-nim/src/bony/{jsonio.nim,binary/semantic.nim,transform.nim,constraints/update_cache.nim,model.nim}` — already IK-aware from steps 1–2; this slice must not modify them.
- `spec/bony.schema.json`, `spec/bony-input-script.schema.json` — authoring references; do **not** expand the input-script schema unless a concrete failure proves the existing schema cannot express the IK target animation.
- `runtime-dart/` — must still pass: it loads the IK asset model even though it defers IK evaluation.

### Success Criteria
- `conformance/assets/m5_ik_rig.bony` exists: a small rig exercising one-bone, two-bone, and chain IK, validating against `spec/bony.schema.json`. **The rig must be authored so the IK solve visibly changes the pose at `t=0`** — place each IK target bone offset from where the unconstrained chain tip would naturally rest, so the `m5_ik_rig_t0.json` golden differs from the unconstrained pose and the gate cannot pass trivially. A setup pose that coincides with the unconstrained pose does not exercise the solver and is unacceptable.
- **Non-vacuity is explicitly verified, not assumed — for BOTH the static solve and the story motion.** No gate enforces "the solve changed the pose" (each gate re-runs the same solver that produced the committed golden, so a degenerate rig passes green). The verification bead must prove two things out-of-band:
  - *Static IK non-vacuity:* regenerate a golden from an **IK-removed (or `mix:0`) variant of the rig** and confirm at least one `bones[].world` entry differs from `m5_ik_rig_t0.json` by ≫ `1e-4`. There is **no CLI flag to disable IK**, so the agent must hand-author this variant `.bony`. **It must be created in a scratch/temp dir OUTSIDE `conformance/` and never committed** — every gate globs `conformance/assets/*.bony`, so a variant left in the tree auto-enrolls and pollutes the suite (and could be committed by accident).
  - *Story-motion non-vacuity:* confirm the nonzero story sample actually moved the target and re-solved — assert at least one `bones[].world` entry in `m5_ik_story_<nonzero>.json` differs from the `t=0` story golden by ≫ `1e-4`. (A target that never translates yields identical goldens that still pass green, because `input_script_run.py` only compares each sample to its own committed golden.)
  Record both checks in the bead; do not rely on prose alone.
- `conformance/assets/bnb/m5_ik_rig.bnb` is generated by the step-2 CLI (`json-to-bnb`), never hand-edited.
- `conformance/goldens/m5_ik_rig_t0.json` is generated by `golden-gen` at `t 0.0` and reflects the solved IK pose.
- `conformance/scripts/m5_ik_sample.json` (setup-pose, non-SM) drives the `t=0` pose → `m5_ik_rig_t0.json`. **`conformance/scripts/m5_ik_story.json` (state-machine)** drives ≥1 nonzero-time sample that animates the IK target bone, with a committed golden per sample. **Because a missing/misnamed golden reports SKIP (not FAIL) and other scripts' passing samples mask the vacuous-green guard, the verification bead must confirm `input_script_run.py` reports the IK story samples as PASS (not SKIP)** — pin each sample `name` to its committed `m5_ik_story_<name>.json` golden.
- **`input_script_run.py` replays every SM story sample against BOTH `.bony` and the committed `conformance/assets/bnb/m5_ik_rig.bnb`, and a missing `.bnb` is a FAIL (not SKIP).** So the input-script/verification gate hard-depends on the generate-`.bnb` bead — make that ordering edge explicit. This path also exercises **binary IK parity at nonzero time under animation+state-machine**, which the analysis bead's `t=0`-only round-trip probe does *not* cover (see decomposition step 1's scope note).
- `conformance/README.md` documents the new IK rig (table structure resolved per the Affected-Areas note). The M9 non-scalar rig is already listed in both tables — confirm it still is; no new M9 row is needed.
- The numeric-golden gate runs `.bony` and the matching `.bnb` against the same `m5_ik_rig_t0.json` golden within `1e-4`; the IK rig must pass for **both** extensions, proving binary IK parity.
- All gates pass. **Note the per-gate specifics** — most take `--bony-bin`, but `schema_validate_assets.py` does **not** (its argparse defines only `--schema`/`--assets`; passing `--bony-bin` fails with "unrecognized arguments"):

```bash
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim
python3 scripts/ci/schema_validate_assets.py                      # NO --bony-bin flag
python3 scripts/ci/conformance_run.py   --bony-bin /tmp/bony_bin  # .bony + .bnb vs m5_ik_rig_t0.json @1e-4
python3 scripts/ci/round_trip_run.py    --bony-bin /tmp/bony_bin  # bnb→json→bnb byte stability
python3 scripts/ci/input_script_run.py  --bony-bin /tmp/bony_bin  # story samples must report PASS, not SKIP
python3 scripts/ci/suite_run.py         --bony-bin /tmp/bony_bin  # runs conformance + image_diff_check + input_script + round_trip
cd runtime-dart && dart test && cd ..
```

  `suite_run.py` also invokes `image_diff_check.py` (Pillow), which returns **SKIP** for `m5_ik_rig` because no `m5_ik_rig_play.png` is committed — that SKIP is expected and is **not** a gap. Do not add a PNG golden to silence it.
- **Dart scope (explicit):** `runtime-dart` still passes, but this proves *nothing* about IK — Dart has no IK solver and its conformance/`m5` tests are hardcoded to specific rigs, so it never loads `m5_ik_rig`. Leave `runtime-dart` **untouched**; there is no real cross-runtime IK parity yet (this slice establishes the Nim reference golden only). **Do not wire the IK rig into any Dart glob or conformance test** — Dart would emit unconstrained bone worlds and fail against the Nim IK-solved golden.

### Constraints
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime source, importer source, generated definitions, exact wire layouts, type/property keys, or copied docs prose. The rig geometry must be original and authored for this test, not derived from any third-party sample asset.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not hand-edit generated goldens or `.bnb` bytes; regenerate them with the CLI. Treat goldens and `.bnb` files as generated artifacts.
- IK only — no transform/physics constraint assets.
- Do not expand the input-script schema unless a concrete failure proves the existing schema cannot express the IK target animation.
- Keep the slice small enough for one meaningful implementation session.
- Image goldens are Nim-only and not part of the cross-runtime contract; an IK `*_play.png` is optional and may be left `pending` in the README table like M7/M9, unless the reference rasterizer renders the rig cleanly.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/specs/` and `docs/adr/` for existing architectural decisions
2. Examine the directory/module structure of the affected areas listed above
3. Identify key interfaces, APIs, and integration points that must be preserved
4. Note existing test patterns and coverage in the affected areas
5. Assess risk areas where changes could break existing functionality

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
# Change: Conformance IK constraint golden gate (m5_ik_rig)
# Generated: 2026-06-30

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

EPIC=$(bd create "Epic: Conformance IK constraint golden gate (m5_ik_rig)" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work — keep it out of `bd ready`

# ... task beads here, each with --parent "$EPIC" ...

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
- The epic is a **rollup, not work**: never `bd dep add` to or from it. Membership is `--parent`; `bd dep add` is reserved for real ordering edges *between task beads*.
- **Keep the epic out of `bd ready`** by marking it active right after creation: `bd update "$EPIC" --status in_progress`.
- An epic must have **≥ 2 children** to be meaningful.

### Priority Levels
- `-p 0` = Critical (blocking other work, or high-risk changes needing early validation)
- `-p 1` = High (important implementation work)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (cleanup, nice-to-haves)

### Labels (Phase Grouping)
Use `--label` to group beads by phase: `analysis`, `prep`, `impl`, `testing`, `docs`, `cleanup`.

### Dependency Rules
1. Never create cycles
2. Analysis tasks should complete before implementation begins
3. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
4. Parallel work should share a common ancestor, not depend on each other
5. `bd dep add` is for ordering edges **between task beads only** — never to/from the epic

### Task Granularity
- Each bead should be completable in **under 750 lines of code changed**.
- Tasks should be atomic enough for one agent to complete without coordination.

### Suggested decomposition for this change (guidance, not prescriptive)
Because the CLI generates the `.bnb` and goldens from the `.bony` source, the rig-authoring bead is the upstream blocker for every generation/gate bead. A natural ordering:

1. **analysis — HARD binary-IK-parity probe (pre-author gate).** Build the CLI binary once. Then, before authoring the real rig, **actually round-trip a throwaway probe IK rig** (authored in a **scratch/temp dir outside `conformance/`** so the gate globs never pick it up): `json-to-bnb` → `bnb-to-json` → `golden-gen --t 0.0` on **both** the `.bony` and the generated `.bnb`, and diff the two goldens within `1e-4`. This is the plan's single largest unguarded risk: `conformance_run.py` and `round_trip_run.py` newly stress IK-constraint serialization (`bones`/`target`/`order`/`mix`/`bendPositive`) through the binary semantic loader. **If binary IK parity does NOT already hold, stop and escalate** — the "do not modify runtime" + "one session" constraints become mutually unsatisfiable, and a runtime-fix bead must be filed as a blocker (this is out of the current slice's scope). **Scope note:** this probe covers only *static* (`t=0`) IK. Nonzero-time IK under animation+state-machine is separately stressed by `input_script_run.py` replaying the story `.bnb` (see step 8); non-IK binary SM/animation parity is already proven by the existing m8/m9 SM `.bnb` goldens, so the residual risk is scoped to *IK-under-SM specifically*. If cheap, extend the probe to a nonzero-time SM+animation+IK round-trip; otherwise note the residual risk lands at the step-8 gate. Only if the static probe passes does the rest proceed. Also confirm CI runners auto-enroll `m5_ik_rig` by glob/naming convention (no runner edits) — `conformance_run.py` globs `conformance/assets/*.bony` (and `bnb/*.bnb`), `round_trip_run.py` globs `*.bony` + `bnb/*_rig.bnb`, `input_script_run.py` iterates `scripts/*.json`. **`schema_validate_assets.py` validates only `conformance/assets/*.bony` against `spec/bony.schema.json` — it does NOT validate the input scripts**; the scripts are schema-checked against `spec/bony-input-script.schema.json` *inside* `input_script_run.py`, not by a standalone gate.
2. **impl (rig)** — Author `conformance/assets/m5_ik_rig.bony`: one-bone, two-bone, and chain (≥3-bone) IK with target bones offset from the unconstrained rest tip so `t=0` differs from the unconstrained pose; **plus** a `stateMachine` and an `animation` whose `boneTimeline` translates one IK **target** bone (that target must lie *outside* the solved chain). No slots/regions/attachments. Validate against `spec/bony.schema.json`. **This bead blocks all generation beads.**
3. **impl (setup script)** — Author `conformance/scripts/m5_ik_sample.json`: **no `stateMachine` field**, a single `t=0` setup sample → `m5_ik_rig_t0.json`. Validate against `spec/bony-input-script.schema.json`.
4. **impl (story script)** — Author `conformance/scripts/m5_ik_story.json`: **`stateMachine` field set**, named samples at `t=0` and ≥1 nonzero `t` whose `inputs` drive the target-bone animation. Sample names must be **alphabetic** (`SAMPLE_NAME_RE`: `[A-Za-z0-9_.-]` with ≥1 non-digit; no purely numeric names), **unique**, and sample **times non-decreasing** (harness advances by delta-from-previous). Enumerate each sample `name` so its golden filename `m5_ik_story_<name>.json` is pinned. Depends on the rig (state-machine/animation/input names must match).
5. **impl (generate .bnb)** — Generate `conformance/assets/bnb/m5_ik_rig.bnb` via `json-to-bnb`. Depends on the rig.
6. **impl (generate goldens)** — Generate `conformance/goldens/m5_ik_rig_t0.json` via `golden-gen <asset> <out> --t 0.0`, and every `conformance/goldens/m5_ik_story_<name>.json` via a **direct** `golden-gen <asset> <out> --state-machine <smName> --input-script conformance/scripts/m5_ik_story.json --sample <name>` call (NOT via `input_script_run.py`, which only consumes goldens). Depends on the rig + both scripts. Every enumerated story golden must be committed.
7. **docs** — Update `conformance/README.md`: resolve the table structure (dedicated IK milestone vs second M5 row vs augment M5 description — pick one), add the image-golden `pending` row, confirm M9 rows intact. Depends on the rig existing.
8. **testing (verification gate + non-vacuity)** — Run the full gate block over both `.bony` and `.bnb` (note: `schema_validate_assets.py` takes **no** `--bony-bin`; `suite_run.py` runs conformance + image_diff_check + input_script + round_trip; expect a SKIP from image_diff_check). Confirm binary IK parity within `1e-4` (**including** the nonzero-time story `.bnb` samples via `input_script_run.py` — which FAILs if `m5_ik_rig.bnb` is absent, so this bead depends on step 5). Confirm the story samples report **PASS not SKIP**. Perform **both non-vacuity checks**: (a) static — IK-removed/`mix:0` variant (authored in a **scratch dir outside `conformance/`, never committed**) differs from `m5_ik_rig_t0.json` ≫ `1e-4`; (b) story-motion — nonzero story golden differs from the `t=0` story golden ≫ `1e-4`. Depends on all generation + docs beads. This is the exit gate. **Caveat:** the repo's `make test` target (used by ralph/bead-swarm per-iteration VERIFY) does **not** run the conformance gates — only `.github/workflows/ci.yml` on push and this bead do. If driven by such a loop, intermediate iterations report false-green for IK conformance until this bead or CI runs; do not merge on `make test` alone.

Keep this to a single coherent session; do not split the rig across multiple beads (the artifacts must be internally consistent and are all derived from one `.bony` source). The two script files (setup + story) are separate deliverables but small. **Soft altitude note:** the rig bead (three IK chains + m8-class stateMachine+animation) is the largest/highest-risk unit; if the session runs long, the natural cleave is *static IK rig + t0 golden* first, *animated-story additions* second — do not split the `.bony` file itself.

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check the rollup**: `bd children "$EPIC"` lists every task bead; `bd dep tree` shows them under the epic with no orphan tasks.
3. **Check ready work**: `bd ready` shows the initial analysis bead and **not** the epic.
4. **Check no cycles**: `bd dep cycles` reports none.

---

## Completeness Checklist

- [ ] A single parent epic (`-t epic`); every task bead parented via `--parent "$EPIC"`, no orphans, no blocking dep to/from the epic
- [ ] Analysis bead: build the binary + **hard binary-IK-parity probe** (json-to-bnb → bnb-to-json → golden-gen on both extensions, diff ≤ `1e-4`) with a stated escalation-to-blocker path if parity fails; confirm runner glob auto-enroll
- [ ] Rig-authoring bead (`m5_ik_rig.bony`): one/two/chain IK, targets offset so `t=0` ≠ unconstrained pose, **stateMachine + animation moving a target bone that lies outside the solved chain**, no slots/regions
- [ ] Setup-script bead (`m5_ik_sample.json`, non-SM, single `t=0` → `m5_ik_rig_t0.json`)
- [ ] Story-script bead (`m5_ik_story.json`, SM field set, named samples at `t=0` + ≥1 nonzero `t`; **alphabetic unique names**, **non-decreasing times**; pinned to `m5_ik_story_<name>.json`)
- [ ] Generate-`.bnb` bead (`json-to-bnb`, never hand-edited) — upstream of the input-script gate (missing `.bnb` = FAIL there)
- [ ] Generate-goldens bead: `golden-gen --t 0.0` for t0 + every `m5_ik_story_<name>.json` via **direct `golden-gen --state-machine --input-script --sample`** (not `input_script_run.py`); all committed
- [ ] README bead: table structure resolved (one choice), image-golden `pending` row, M9 rows confirmed intact
- [ ] Verification-gate bead: gates pass for `.bony` and `.bnb` (`schema_validate_assets.py` with **no** `--bony-bin`); story samples report **PASS not SKIP**; binary parity within `1e-4` (incl. nonzero-time story `.bnb`); **two non-vacuity checks** — static (IK-removed variant, scratch dir, uncommitted) and story-motion (nonzero vs t0 story golden), both ≫ `1e-4`; image_diff_check SKIP expected; note `make test` does not run these gates
- [ ] Dart untouched — no IK rig wired into any Dart glob/conformance test; `dart test` still green
- [ ] Clean-room posture preserved; IK only; input-script schema unchanged unless a concrete failure proves otherwise
