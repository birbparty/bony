# /big-change prompt - contract + Nim runtime + conformance (M5 transform constraint)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 2**. Must land before prompt
> `10-dart-transform-constraint-parity.md` — that prompt's Dart runtime is
> gated on the numeric golden this prompt produces.
> **Candidate category:** frontier.

---

/big-change Promote transform constraints from a standalone Nim solver module to a first-class, conformance-gated `.bony`/`.bnb` format feature evaluated by the Nim reference runtime.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony` M5 covers four constraint families: IK, transform, path, and physics
(`registry/wire.yml` `keyRanges` scope for M5, and `docs/constraint-total-order.md`
lists `ik[]`, `transforms[]`, `paths[]`, `physics[]`). IK and path are already
first-class format records with cross-runtime conformance goldens. Transform
constraints are **half-built**: the solver math already exists and is unit-tested,
but there is no format record, no schema, no registry entry, no conformance asset,
and the runtime world-transform pass explicitly skips them.

Concretely, already in place:
- `runtime-nim/src/bony/constraints/transform_constraints.nim` (137 lines) exports
  the full solver: `TransformConstraintMix`, `TransformConstraintPose`,
  `transformConstraintMix`, `affineToTransformPose`, `transformPoseToAffine`, and
  `applyTransformConstraint(constrained, target, mix)` — pure project-owned affine
  decomposition/recomposition with per-channel mix in `[0,1]`. Covered by
  `runtime-nim/tests/test_smoke.nim`.
- `runtime-nim/src/bony/model.nim:32-36` already defines
  `ConstraintKind = enum ckIk, ckTransform, ckPath, ckPhysics`.
- `constraintKindRank` (`model.nim:715-720`) already ranks `ckIk=0, ckTransform=1,
  ckPath=2, ckPhysics=3`, and `constraintStageRank` puts everything except
  `ckPhysics` in stage 0. So the deterministic total order for transform
  constraints is already defined; no ordering contract change is required.
- `runtime-nim/src/bony/transform.nim:167-176` dispatches `ccekConstraint` entries:
  `of ckPath` / `of ckIk`, with an `else` branch commented
  `# ckTransform / ckPhysics are out of scope for this slice.`

Missing (this milestone builds exactly this, transform only):
1. Format record: a `transformConstraint` registry type + `.bony` JSON schema
   `$def` + `transformConstraints` array on the skeleton + flat
   `bony-wire.schema.json` entry + `spec/defaults.yml` coverage + regenerated
   codegen. `registry/wire.yml` type keys `4000` (path), `4001` (pathAttachment),
   `4002` (ikConstraint) are used; the next free M5 **type** key is `4003`.
   M5 **property** keys `4000..4016` are used; the next free M5 property key is
   `4017`. Reuse existing shared property keys where the field already exists —
   `bone`, `target`, `order`, `translateMix`, `rotateMix` are owned by the `path`
   constraint record (path uses a **singular** `bone` and these two mixes), so
   reuse **path's** property keys, NOT `ikConstraint`'s (`ikConstraint` uses a
   plural `bones` chain and a single `mix` + `bendPositive`, which do not apply
   here). Allocate new property keys (`4017+`) only for `scaleMix` and `shearMix`.
   The four-mix shape (`translateMix`/`rotateMix`/`scaleMix`/`shearMix`) is novel —
   neither existing constraint has four mixes — so do not template the record body
   off `ikConstraint`.
2. Nim model: a `TransformConstraintData` type mirroring `IkConstraintData`, a
   `transformConstraints: seq[TransformConstraintData]` field on `SkeletonData`
   (next to `paths`/`ikConstraints` at `model.nim:198-199`), an accessor mirroring
   `ikConstraints*` (`model.nim:457`), and constructor + validation wiring. The
   real object constructor is `proc skeletonData*` at `model.nim:671-693` (it
   assigns `result.paths` at 690 and `result.ikConstraints` at 693 — add
   `result.transformConstraints` alongside); thread a `transformConstraints`
   parameter through **both** `validateSkeletonData*` overloads (the raw-fields
   overload at `model.nim:501-511` and the `SkeletonData` overload at
   `model.nim:696-699`). Do not stop at only adding the type/field — the field
   must be wired into the constructor and both validators. Load-time validation
   mirrors the `ikConstraints` block at `model.nim:601-602` (unique name, known
   `bone`/`target` references, mixes finite and in `[0,1]` — reuse the checks
   already in `transform_constraints.nim`).
3. Runtime evaluation: add a `transformConstraints` descriptor loop to
   `buildRuntimeConstraintUpdateCache` (`update_cache.nim:169-183`) emitting
   `ckTransform` descriptors with `writes = [constrained bone]` and
   `reads = @[target]` (mirroring the IK/path loops so the shared
   `buildConstraintUpdateCache` orders them by the existing rank); and an
   `applyRuntimeTransformConstraint` proc in `transform.nim` wired into the
   dispatch at `transform.nim:172-176`, replacing the `ckTransform` stub. It must
   call the existing `applyTransformConstraint` solver and write the constrained
   bone's world affine — mirror the structure of `applyRuntimeIk`
   (`transform.nim:389`) and `applyRuntimePathConstraint` (`transform.nim:273`).
4. Conformance asset + golden: author `conformance/assets/m5_transform_rig.bony`
   (a rig where one constrained bone is driven toward a target bone with a partial
   mix so the constrained bone's solved world affine differs **non-vacuously** from
   its unconstrained pose), generate `conformance/assets/bnb/m5_transform_rig.bnb`
   with the Nim CLI `bony json-to-bnb <src.bony> <dst.bnb>` (the same tool that
   produced `m5_ik_rig.bnb`, bead bony-6g5.5), author
   `conformance/scripts/m5_transform_sample.json` (setup pose at `t=0`, mirroring
   `conformance/scripts/m5_ik_sample.json`), and emit
   `conformance/goldens/m5_transform_rig_t0.json` from the Nim reference runtime
   via the CLI `bony golden-gen <asset> <out> --t 0` (see the "Adding a new
   milestone" recipe in `conformance/README.md`). The CI Python scripts under
   `scripts/ci/` only VERIFY goldens — they do not emit them.
5. Docs: add a `M5 (transform)` row and rig section to `conformance/README.md`
   (mirroring the `M5 (IK)` row/section), and add a transform-constraint runtime
   contract note to `docs/constraint-total-order.md` mirroring the existing
   "Path Constraint Runtime Contract" section (state that transform constraints
   are runtime-evaluable in v1, list the fields, and state the mix semantics).

Keep the record **minimal and solver-faithful**: fields are `name`, `bone`
(constrained), `target`, `order`, `translateMix`, `rotateMix`, `scaleMix`,
`shearMix` — exactly the inputs `applyTransformConstraint` consumes. Do **not**
add offset/local/relative fields, multi-bone target lists, or a
`runtimeEvaluable`-style opt-in gate for this slice.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md (transform constraints are a
  named comparable capability category only — not an implementation source)
- Constraint order contract: docs/constraint-total-order.md
- Registry key bands: registry/key-ranges.md (M5 = 4000..4999)
- Registry source: registry/wire.yml (ikConstraint entry at line 241; M5 property
  keys 4000..4016)
- Defaults: spec/defaults.yml (ikConstraint block at line 193; path block at 170)
- JSON schema: spec/bony.schema.json (ikConstraint $def at line 566;
  ikConstraints array at line 42)
- Wire schema: spec/bony-wire.schema.json
- Codegen: codegen/generate.py (`validate_sources()` is defined at
  generate.py:200 and called unconditionally from `main()` at generate.py:1281 —
  even under `--check`. It fails if a registry object lacks defaults.yml/
  requiredProperties coverage or vice-versa (every registry property must be
  covered by exactly one of `objectDefaults` or `requiredProperties`, no overlap).
  This is why the registry entry, the defaults entry, the `requiredProperties`
  entry for `name`/`bone`/`target`, and the codegen regen must all land together
  in this one change. NOTE: a pre-existing unrelated helper `transform_constraint_schema()`
  already exists at generate.py:916 — it emits bone `transformMode`/inheritance
  schema, NOT this transform-constraint record; do not confuse or collide names
  with it.)
- Nim solver: runtime-nim/src/bony/constraints/transform_constraints.nim
- Nim model: runtime-nim/src/bony/model.nim (ConstraintKind enum line 32,
  constraintKindRank line 715, SkeletonData constraint fields line 198)
- Nim cache: runtime-nim/src/bony/constraints/update_cache.nim
  (buildRuntimeConstraintUpdateCache line 169)
- Nim world pass: runtime-nim/src/bony/transform.nim (dispatch line 167,
  applyRuntimeIk line 389, applyRuntimePathConstraint line 273)
- Analogous IK asset to template: conformance/assets/m5_ik_rig.bony,
  conformance/scripts/m5_ik_sample.json, conformance/goldens/m5_ik_rig_t0.json
- Conformance runners: scripts/ci/input_script_run.py, scripts/ci/conformance_run.py,
  scripts/ci/round_trip_run.py, scripts/ci/schema_validate_assets.py
- Repo gate: Makefile `test` target
- Beads: file under this milestone before implementing (see prompt reporter)

**Success Criteria**
- `registry/wire.yml` gains a `transformConstraint` type (key `4003`, milestone
  `M5`, owner bead cited) plus any new property keys from `4017+`; no key collides
  with an existing M5 entry; each new entry cites its owning bead in `doc`.
- `spec/defaults.yml` has a `transformConstraint` object block covering every
  defaultable property; `python3 codegen/generate.py --check` passes (validates
  registry↔defaults coverage). Follow the existing `path`/`ikConstraint` blocks
  (`spec/defaults.yml:170-210`): `order` is structural → `value: 0`,
  `applyOnLoad: true`; the four mixes are runtime solver params → each
  `applyOnLoad: false` with default `value: 1.0` (matching `transformConstraintMix*`
  in `transform_constraints.nim:24`, which defaults all four to `1.0`). Do NOT set
  `applyOnLoad: true` on the mixes.
- `spec/bony.schema.json` gains a `transformConstraint` $def and a
  `transformConstraints` array on the skeleton; `spec/bony-wire.schema.json` gains
  the matching flat entry; `python3 scripts/ci/schema_validate_assets.py` passes
  for all assets including the new one.
- Codegen regenerated: `runtime-nim/src/bony/generated/wire.nim` and
  `runtime-dart/lib/src/generated/wire.dart` updated by `codegen/generate.py`
  (do not hand-edit generated files).
- `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim` is clean;
  Nim unit tests pass (`runtime-nim/tests/test_smoke.nim` and the constraint tests).
- The Nim reference reproduces `conformance/goldens/m5_transform_rig_t0.json` from
  `conformance/assets/m5_transform_rig.bony` driven by
  `conformance/scripts/m5_transform_sample.json`, and the same golden is
  reproduced from `conformance/assets/bnb/m5_transform_rig.bnb` (JSON and binary
  loaders agree). Verify locally with `python3 scripts/ci/suite_run.py` (the
  aggregate runner covering numeric-golden → image-golden → input-script →
  round-trip gates), which wraps `scripts/ci/conformance_run.py`,
  `input_script_run.py`, and `round_trip_run.py`.
- The golden is **non-vacuous**: document in the conformance README the world-affine
  delta between the constrained bone's solved pose and its unconstrained pose, and
  confirm the delta is well above the `1e-4` tolerance. (There is no literal "~36
  delta" note in the README today — the analogous IK section documents an angle
  sweep across story samples. Write a NEW note in that bullet's style, but reporting
  a constrained-vs-unconstrained world-affine delta for the single
  `m5_transform_rig_t0.json` setup golden.)
- `make test` passes.
- `conformance/README.md` and `docs/constraint-total-order.md` updated as described.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source, importer source, generated definitions,
  exact wire layouts, type/property keys, or copied docs prose. The affine
  decomposition and mix semantics are project-owned (already in
  `transform_constraints.nim`); do not import a third party's transform-constraint
  field set, parameter names, or offset model.
- Use `docs/comparable-feature-set.md` only to justify the transform-constraint
  capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for
  human/legal review.
- Registry edits: use only the M5 band (`4000..4999`) per `registry/key-ranges.md`,
  and follow the registry shared-surface reservation rule in that file.
- Land the registry entry, `defaults.yml` entry, and codegen regeneration together
  in this one change — `validate_sources()` fails if they drift apart.
- Do **not** implement physics constraints, transform-constraint offsets, or the
  Dart runtime in this prompt. Dart parity is prompt 10.
- Keep the slice to one meaningful implementation session: one new constraint
  family, one new conformance asset, Nim reference only.
