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
NEW_FEATURE (frontier candidate) — promoting a half-built, unit-tested Nim solver module into a first-class, conformance-gated `.bony`/`.bnb` format record with runtime evaluation. This is **step 1 of 2**: the numeric golden it produces gates the Dart-parity follow-up (prompt `10-dart-transform-constraint-parity.md`).

### Description
Promote transform constraints from a standalone Nim solver module to a first-class, conformance-gated `.bony`/`.bnb` format feature evaluated by the Nim reference runtime.

`bony` M5 covers four constraint families: IK, transform, path, and physics. IK and path are already first-class format records with cross-runtime conformance goldens. Transform constraints are **half-built**: the solver math exists and is unit-tested (`runtime-nim/src/bony/constraints/transform_constraints.nim`), but there is no format record, no schema, no registry entry, no conformance asset, and the world-transform pass explicitly skips them (`transform.nim:176` `# ckTransform / ckPhysics are out of scope for this slice.`).

Already in place (verified):
- Solver `transform_constraints.nim` exports `TransformConstraintMix`, `TransformConstraintPose`, `transformConstraintMix` (all four mixes default `1.0`, line 24), `affineToTransformPose` (76), `transformPoseToAffine` (104), and `applyTransformConstraint(constrained, target, mix)` (125). Covered by `test_smoke.nim`.
- `model.nim:32` defines `ConstraintKind = enum ckIk, ckTransform, ckPath, ckPhysics`.
- `constraintKindRank` (`model.nim:715`) ranks `ckIk=0, ckTransform=1, ckPath=2, ckPhysics=3`; `constraintStageRank` (709) puts everything except `ckPhysics` in stage 0. The deterministic total order for transform constraints is already defined — **no ordering-contract change required**.
- `transform.nim:169-176` dispatches `ccekConstraint` entries with `of ckPath` / `of ckIk` and an `else` stub for `ckTransform`/`ckPhysics`.

This milestone builds exactly the missing surface, **transform only**:
1. **Format record (atomic registry+codegen unit)** — `transformConstraint` registry **type key `4003`** (next free type key; verified `4000-4002` used) added in THREE `wire.yml` sub-sections that must all move together: `typeKeys:` (the 4003 entry), `propertyKeys:` (new keys only for `scaleMix`/`shearMix`), and the **`objects:` membership block** (`wire.yml:947+`, mirroring the `- type: ikConstraint` block at `:992`) enumerating all eight properties `name, bone, target, order, translateMix, rotateMix, scaleMix, shearMix`. `validate_sources()` (`generate.py:304`) rejects any `requiredProperties {object}.{property}` not present in that `objects:` list, so it is NOT optional. Property-key reuse (verified against `wire.yml`): `bone` → **shared key `1012`** (id `bone`, M2, "Bone name referenced by a slot"; path already reuses this singular key — there is NO M5 "bone" key), `target` → `4000`, `order` → `4002`, `translateMix` → `4012` (`backingType: f32`), `rotateMix` → `4013` (`f32`). Allocate **new property keys from `4017+`** only for `scaleMix` and `shearMix`, both `backingType: f32` to stay symmetric with the reused mixes. The four-mix shape is novel — do **not** template the record body off `ikConstraint` (plural `bones` + single `mix` + `bendPositive` do not apply). `spec/defaults.yml` gains a `transformConstraint` `objectDefaults` block (own per-object defaults — do NOT inherit path's `rotateMix: 0.0`; all four mixes default `1.0`) and `requiredProperties` entries for `name`/`bone`/`target`. **`spec/bony.schema.json` and `spec/bony-wire.schema.json` are GENERATED** by `codegen/generate.py` (`generate_schema`/`generate_wire_schema` are data-driven off the registry, written via `write_or_check` at `generate.py:1283-1284`) — the `$def` + `transformConstraints` skeleton array appear automatically from the registry entries; **do NOT hand-author them** (same posture as `wire.nim`/`wire.dart`). This whole item is ONE bead: registry (3 sub-sections) + defaults + requiredProperties + `python3 codegen/generate.py` regen must land together or `validate_sources()`/`--check` fails on drift.
2. **Nim model** — a `TransformConstraintData` type with the four mixes carrying `has*` **presence flags** (mirror `IkConstraintData` `hasMix`/`hasBendPositive` `model.nim:90-98` and `PathConstraintData` `hasTranslateMix`/`hasRotateMix` `77-88`, since the mixes are `omitWhenDefault: true` and the serializer must preserve presence for byte-stable round-trip); a `transformConstraints: seq[TransformConstraintData]` field on `SkeletonData` (next to `ikConstraints` at `model.nim:199`); an accessor mirroring `ikConstraints*` (`model.nim:457`); wire the field into the `skeletonData*` constructor (`model.nim:671-693`, assign `result.transformConstraints` alongside line 693) as a NEW trailing parameter (default `= []`) **and** thread a `transformConstraints` parameter through **both** `validateSkeletonData*` overloads (raw-fields overload `501-511`, `SkeletonData` overload `696-699`). Load-time validation mirrors the `ikConstraints` block (`model.nim:601-602`): unique name, known `bone`/`target` refs, mixes finite and in `[0,1]` — reuse the checks in `transform_constraints.nim`. NOTE the trailing-param signature change has a call-site blast radius (see item 3 loaders) — a default keeps existing positional calls compiling but they pass NO constraints until each caller is updated, so the loader/CLI edits are hard dependents of this bead.
3. **Load path (JSON + BNB + CLI)** — the reason a "model + eval" pair is insufficient: nothing populates `SkeletonData.transformConstraints` from serialized input. (a) **JSON loader** `runtime-nim/src/bony/jsonio.nim`: add `"transformConstraints"` to the root key allowlist (`:312`), a parse loop mirroring the `ikConstraints` block (`:453`), thread the result into the `skeletonData(...)` call (`:608`), and add a serializer emit block mirroring `ikConstraints` (`:1519`) or JSON round-trip regresses. (b) **BNB codec** `runtime-nim/src/bony/binary/semantic.nim`: add `transformConstraintTypeKey = 4003'u64` (`:15-21`) + `scaleMix`/`shearMix` key consts, an encode loop and a `of transformConstraintTypeKey:` decode branch (mirror the ikConstraint encode/decode), threaded into its `skeletonData(...)` call (`:1476`). (c) **CLI** `cli/bony_cli.nim` (the real `json-to-bnb`/`golden-gen` binary — `bony.nimble` has `bin = @[]`): update the `skeletonData(...)` skeleton reconstruction (`:1431`) to carry `data.transformConstraints`, else `json-to-bnb` silently drops the constraint. Without all three, `data.transformConstraints` is always empty and the golden is vacuous / JSON↔BNB "agree" trivially at empty.
4. **Runtime evaluation** — TWO edits in `transform.nim`, both required: (a) **extend the `hasRuntimeConstraints` detection gate** (`transform.nim:137-147`, currently scans ONLY `data.paths` and `data.ikConstraints`) to also fire for transform constraints — WITHOUT this the entire cache/dispatch path at `:147+` is skipped for a transform-only rig and the golden is vacuous; and (b) add an `applyRuntimeTransformConstraint` proc wired into the dispatch at `:172-176`, replacing the `ckTransform` stub, calling `applyTransformConstraint` and writing the constrained bone's world affine. Mirror the STRUCTURE of `applyRuntimeIk` (389)/`applyRuntimePathConstraint` (273) but do **NOT** copy their `if not ik.runtimeEvaluable: return` / `if not path.runtimeEvaluable: return` opening guard (`:413`/`:282`) — `runtimeEvaluable` is a derived predicate on path/IK only (`model.nim:405`,`418`); transform constraints have no such field, so either evaluate unconditionally or define a transform analog and use it consistently in BOTH the detection gate and the guard. Also add the `transformConstraints` descriptor loop to `buildRuntimeConstraintUpdateCache` (`update_cache.nim`) emitting `ckTransform` descriptors with `writes = [constrained bone]`, `reads = @[target]` (mirroring the IK/path loops so the shared builder orders by existing `constraintKindRank`).
5. **Conformance asset + golden** — author `conformance/assets/m5_transform_rig.bony` (a constrained bone driven toward a target with a partial mix so its solved world affine differs **non-vacuously** from its unconstrained pose); generate `conformance/assets/bnb/m5_transform_rig.bnb` via `bony json-to-bnb` (built from `cli/bony_cli.nim`); author `conformance/scripts/m5_transform_sample.json` (setup pose at `t=0`, mirroring `m5_ik_sample.json`) — it MUST validate against `spec/bony-input-script.schema.json` (the `input_script_run.py` gate inside `suite_run.py`); emit `conformance/goldens/m5_transform_rig_t0.json` from the Nim reference via `bony golden-gen <asset> <out> --t 0` (note `conformance_run.py:41` invokes the plain `golden-gen ... --t 0.0` path with no `--input-script`; the CI scripts under `scripts/ci/` only VERIFY goldens, they do not emit them).
6. **Docs** — add an `M5 (transform)` row + rig section to `conformance/README.md` (mirroring the `M5 (IK)` row/section, including a NEW non-vacuous constrained-vs-unconstrained world-affine delta note ≫ `1e-4`), and add a transform-constraint runtime contract note to `docs/constraint-total-order.md` mirroring the "Path Constraint Runtime Contract" section.

Keep the record **minimal and solver-faithful**: fields are exactly `name`, `bone` (constrained), `target`, `order`, `translateMix`, `rotateMix`, `scaleMix`, `shearMix` — the inputs `applyTransformConstraint` consumes. Do **not** add offset/local/relative fields, multi-bone target lists, or a stored `runtimeEvaluable`-style opt-in gate on the record (note: this "no opt-in field" rule is about the *format record*; item 4 still requires wiring transform constraints into the runtime `hasRuntimeConstraints` detection so they actually evaluate).

### Links to Relevant Documentation
- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md` (capability category only — NOT an implementation source)
- Constraint order contract: `docs/constraint-total-order.md`
- Registry key bands: `registry/key-ranges.md` (M5 = 4000..4999)
- Registry source: `registry/wire.yml` (typeKeys `ikConstraint` = 4002 at line 241; propertyKeys 4000..4016 in the `propertyKeys:` section starting line 350; `path` property block around 484-505)
- Defaults: `spec/defaults.yml` (ikConstraint block ~193; path block ~170)
- JSON schema (**GENERATED** — do not hand-edit): `spec/bony.schema.json` (auto-emitted `$def` + `transformConstraints` array once registry has the type/object/property entries)
- Wire schema (**GENERATED** — do not hand-edit): `spec/bony-wire.schema.json`
- Nim JSON loader/serializer: `runtime-nim/src/bony/jsonio.nim` (root allowlist `:312`, ikConstraints parse `:453`, `skeletonData(...)` `:608`, serializer `:1519`)
- Nim BNB codec: `runtime-nim/src/bony/binary/semantic.nim` (typeKey consts `:15-21`, `skeletonData(...)` `:1476`)
- Nim CLI binary (`json-to-bnb`/`golden-gen`): `cli/bony_cli.nim` (`skeletonData(...)` reconstruction `:1431`, usage `:13-18`)
- Codegen: `codegen/generate.py` (`validate_sources()` at ~200, called **unconditionally** from `main()` even under `--check` — fails if a registry object lacks defaults.yml/requiredProperties coverage or vice-versa; every registry property must be covered by exactly one of `objectDefaults`/`requiredProperties`, no overlap. NOTE: pre-existing unrelated helper `transform_constraint_schema()` at ~916 emits bone `transformMode`/inheritance schema — do NOT collide names with it.)
- Nim solver: `runtime-nim/src/bony/constraints/transform_constraints.nim`
- Nim model: `runtime-nim/src/bony/model.nim` (ConstraintKind 32, constraintKindRank 715, SkeletonData constraint fields 199, accessor 457, constructor 671-693, validators 501-511 & 696-699, ikConstraints validation block 601-602)
- Nim cache: `runtime-nim/src/bony/constraints/update_cache.nim` (buildRuntimeConstraintUpdateCache; writes/reads descriptor at 12-13)
- Nim world pass: `runtime-nim/src/bony/transform.nim` (dispatch 169-176, applyRuntimePathConstraint 273, applyRuntimeIk 389)
- Analogous IK asset trio: `conformance/assets/m5_ik_rig.bony`, `conformance/scripts/m5_ik_sample.json`, `conformance/goldens/m5_ik_rig_t0.json`
- Conformance runners: `scripts/ci/suite_run.py` (aggregate), `conformance_run.py`, `input_script_run.py`, `round_trip_run.py`, `schema_validate_assets.py`
- Repo gate: `Makefile` `test` target
- Conformance recipe: `conformance/README.md` "Adding a new milestone"

### Affected Areas
- `registry/` — `wire.yml` (THREE sub-sections: `typeKeys:` 4003, `propertyKeys:` 4017+ for scaleMix/shearMix, `objects:` membership block), `key-ranges.md` reservation note
- `spec/` — `defaults.yml` (hand-edited); `bony.schema.json` + `bony-wire.schema.json` are **GENERATED** (regen only, do not hand-edit)
- `codegen/` — `generate.py` regen produces `spec/bony.schema.json`, `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, `runtime-dart/lib/src/generated/wire.dart` (regenerate only; do not hand-edit any of the four)
- `runtime-nim/src/bony/` — model: `model.nim`; runtime eval: `transform.nim`, `constraints/update_cache.nim`; **load path**: `jsonio.nim` (JSON), `binary/semantic.nim` (BNB)
- `cli/` — `bony_cli.nim` (`json-to-bnb`/`golden-gen` skeleton reconstruction must carry `transformConstraints`)
- `conformance/` — `assets/m5_transform_rig.bony`, `assets/bnb/m5_transform_rig.bnb`, `scripts/m5_transform_sample.json`, `goldens/m5_transform_rig_t0.json`, `README.md`
- `docs/` — `constraint-total-order.md`

### Success Criteria
- `registry/wire.yml` gains a `transformConstraint` type across all THREE sub-sections — `typeKeys:` (key `4003`, milestone `M5`, owner bead in `doc`/`ownerBead`), `propertyKeys:` (new `4017+` for `scaleMix`/`shearMix`, `backingType: f32`), and the `objects:` membership block listing all eight properties; `bone` reuses shared key `1012`, `target`/`order`/`translateMix`/`rotateMix` reuse path's keys; no key collides with an existing M5 entry.
- `spec/defaults.yml` has a `transformConstraint` `objectDefaults` block (own defaults — NOT inheriting path's `rotateMix: 0.0`) plus `requiredProperties` for `name`/`bone`/`target`; every registry property is covered by exactly one of `objectDefaults`/`requiredProperties`; `python3 codegen/generate.py --check` passes (`validate_sources()` clean). `order` structural → `value: 0`, `applyOnLoad: true`; the four mixes → each `applyOnLoad: false`, default `value: 1.0`. Do NOT set `applyOnLoad: true` on the mixes.
- Running `python3 codegen/generate.py` (no `--check`) REGENERATES `spec/bony.schema.json` (auto `$def` + `transformConstraints` array), `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, and `runtime-dart/lib/src/generated/wire.dart`; none hand-edited. `python3 scripts/ci/schema_validate_assets.py` passes for all assets including the new one.
- Load path lands: `jsonio.nim` (root allowlist + parse + serializer + `skeletonData` call), `binary/semantic.nim` (typeKey/mix consts + encode + decode + `skeletonData` call), and `cli/bony_cli.nim` (`skeletonData` reconstruction) all carry `transformConstraints`, so a `.bony`/`.bnb` asset's constraints actually populate the model.
- `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim` is clean; Nim unit tests pass (`test_smoke.nim` + constraint tests).
- The runtime `hasRuntimeConstraints` gate (`transform.nim:137-147`) fires for the transform-only rig (extended to scan `data.transformConstraints`), so `applyRuntimeTransformConstraint` actually runs; the ported guard does NOT reference a nonexistent `runtimeEvaluable` field.
- The Nim reference reproduces `conformance/goldens/m5_transform_rig_t0.json` from `conformance/assets/m5_transform_rig.bony` driven by `conformance/scripts/m5_transform_sample.json`, and the SAME golden is reproduced from `conformance/assets/bnb/m5_transform_rig.bnb` (JSON and binary loaders agree, both non-empty). Verify via `python3 scripts/ci/suite_run.py` (numeric-golden + input-script + round-trip gates; the sample validates against `spec/bony-input-script.schema.json`).
- The golden is **non-vacuous**: the conformance README documents the world-affine delta between the constrained bone's solved pose and its unconstrained pose, well above `1e-4` tolerance (a NEW note in the IK section's style, for the single `m5_transform_rig_t0.json` setup golden).
- `make test` passes.
- `conformance/README.md` and `docs/constraint-total-order.md` updated as described.

### Constraints
- Preserve clean-room posture: do NOT inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime source, importer source, generated definitions, exact wire layouts, type/property keys, or copied docs prose. The affine decomposition and mix semantics are project-owned (already in `transform_constraints.nim`); do not import a third party's field set, parameter names, or offset model.
- Use `docs/comparable-feature-set.md` only to justify the transform-constraint capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for human/legal review.
- Registry edits: use only the M5 band (`4000..4999`) per `registry/key-ranges.md`, and follow the registry shared-surface reservation rule in that file (reuse path's shared property keys; allocate new keys only for `scaleMix`/`shearMix`).
- Land the registry entry, `defaults.yml` entry, `requiredProperties` entries (`name`/`bone`/`target`), and codegen regeneration **together in this one change** — `validate_sources()` fails if they drift apart. This coupling means the registry+defaults+schema+codegen-regen work is effectively a single atomic bead (no half can pass its own gate alone).
- Do NOT implement physics constraints, transform-constraint offsets, or the Dart runtime in this prompt. Dart parity is prompt 10.
- Keep the slice to one meaningful implementation session: one new constraint family, one new conformance asset, Nim reference only.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/` (CLEANROOM, PROVENANCE, constraint-total-order) for existing architectural decisions
2. Examine the registry/spec/codegen/runtime-nim/conformance structure of the affected areas listed above
3. Identify key interfaces, APIs, and integration points that must be preserved (ConstraintKind ordering, validate_sources coverage invariant, JSON↔BNB loader agreement)
4. Note existing test patterns and coverage (test_smoke.nim, conformance goldens, suite_run.py)
5. Assess risk areas where changes could break existing functionality (validate_sources drift, key collisions, ordering rank)

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
# Change: Promote transform constraints to a first-class, conformance-gated format feature (Nim reference)
# Generated: 2026-07-01

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

EPIC=$(bd create "Epic: Transform constraint — first-class format record + Nim reference eval (M5)" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work — keep it out of `bd ready`

# ... analysis, format-record, model, runtime, conformance, docs, verify beads ...

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
- The epic is a **rollup, not work**: never `bd dep add` to or from it. Membership is `--parent`; `bd dep add` is reserved for real ordering edges *between task beads*.
- **Keep the epic out of `bd ready`** by marking it active right after creation: `bd update "$EPIC" --status in_progress`.
- An epic must have **≥ 2 children** to be meaningful.

### Priority Levels
- `-p 0` = Critical (blocking other work, or high-risk changes needing early validation)
- `-p 1` = High (important implementation work)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (cleanup, nice-to-haves)

### Labels (Phase Grouping)
- `analysis`, `prep`, `impl`, `testing`, `migration`, `docs`, `cleanup`

### Dependency Rules
1. Never create cycles
2. Analysis tasks should complete before implementation begins
3. Characterization/gate tests should exist before or alongside changing code
4. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
5. Parallel work should share a common ancestor, not depend on each other
6. `bd dep add` is for ordering edges **between task beads only** — never attach a task to the epic with it, never add a blocking edge to/from the epic

### Task Granularity
- Each bead should be completable in **under 750 lines of code changed**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area — EXCEPT the registry+defaults+schema+codegen-regen unit, which MUST stay one bead because `validate_sources()` fails on any drift between halves

---

## Change-Specific Considerations

### For New Features
- Start with analysis of the analogous IK/path first-class records (they are the template for record shape, model wiring, runtime dispatch, and conformance assets)
- No feature flag / opt-in gate for this slice (explicitly out of scope)
- The `validate_sources()` coupling forces registry + defaults + requiredProperties + codegen-regen into a single atomic bead
- Include the conformance asset/golden emission and the docs updates as first-class beads
- Golden must be provably non-vacuous (constrained ≠ unconstrained by ≫ 1e-4)

---

## File Reservation Planning

```bash
# Registry/spec/codegen atomic unit (high coupling — one bead, one reservation):
#   registry/wire.yml (typeKeys + propertyKeys + objects membership), spec/defaults.yml
#   (hand-edit), codegen/generate.py regen output: spec/bony.schema.json, spec/bony-wire.schema.json,
#   runtime-nim/src/bony/generated/wire.nim, runtime-dart/lib/src/generated/wire.dart (regen only)
# Nim model:      runtime-nim/src/bony/model.nim (type + field + accessor + constructor + BOTH validators — do not split)
# Load path:      runtime-nim/src/bony/jsonio.nim, runtime-nim/src/bony/binary/semantic.nim,
#                 cli/bony_cli.nim (all depend on the model signature; may be one bead or a JSON+BNB+CLI trio)
# Nim runtime:    runtime-nim/src/bony/transform.nim (hasRuntimeConstraints gate + applyRuntimeTransformConstraint),
#                 runtime-nim/src/bony/constraints/update_cache.nim
# Conformance:    conformance/assets/m5_transform_rig.bony, conformance/assets/bnb/m5_transform_rig.bnb,
#                 conformance/scripts/m5_transform_sample.json, conformance/goldens/m5_transform_rig_t0.json
# Docs:           conformance/README.md, docs/constraint-total-order.md
# Dependency spine: registry-atomic → model → load-path → runtime-eval → conformance/golden → docs → verify
#                   (load-path & runtime-eval both depend on model; conformance depends on BOTH load-path AND runtime-eval)
```

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check the rollup**: `bd children "$EPIC"` lists every task bead; `bd dep tree` shows them under the epic with no orphan tasks
3. **Check ready work**: `bd ready` shows initial analysis/prep tasks and **not** the epic
4. **Check no cycles**: `bd dep cycles` reports none

---

## Completeness Checklist

- [ ] A single parent epic (`-t epic`); every task bead parented via `--parent "$EPIC"`; no orphans; no blocking dep to/from the epic
- [ ] Analysis of the analogous IK/path first-class records + validate_sources coverage invariant + the `objects:` membership requirement
- [ ] Atomic registry bead: wire.yml (typeKeys 4003 + propertyKeys 4017+ for scaleMix/shearMix f32 + `objects:` membership) + defaults.yml (objectDefaults + requiredProperties) + codegen regen (wire.nim, wire.dart, bony.schema.json, bony-wire.schema.json — all generated) — validate_sources drift guard
- [ ] Nim model bead: type with `has*` presence flags + field + accessor + constructor (trailing param) + BOTH validators + load-time validation
- [ ] Load-path bead(s): jsonio.nim (allowlist+parse+serializer+skeletonData call) + binary/semantic.nim (typeKey/mix consts+encode+decode+skeletonData call) + cli/bony_cli.nim (skeletonData reconstruction) — depends on model bead
- [ ] Nim runtime bead: extend `hasRuntimeConstraints` detection (transform.nim:137-147) + applyRuntimeTransformConstraint dispatch (no `runtimeEvaluable` guard copy) + update_cache descriptor loop
- [ ] Conformance asset + bnb + sample script (validates vs bony-input-script.schema.json) + golden — depends on BOTH load-path AND runtime beads (JSON↔BNB agreement, both non-empty)
- [ ] Non-vacuous golden delta documented (constrained vs unconstrained ≫ 1e-4)
- [ ] Docs updates (conformance/README.md M5-transform row/section + constraint-total-order.md contract note)
- [ ] Verification bead: nim check + Nim unit tests + suite_run.py + schema_validate_assets.py + make test
- [ ] Owner-bead citation threaded into registry `doc`/`ownerBead`
- [ ] Clear dependency chains with no cycles (spine: registry → model → load-path & runtime-eval → conformance → docs → verify)
