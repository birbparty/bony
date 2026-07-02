# /big-change prompt - contract + format (M5 physics constraint, Nim load path)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 4** of the M5 physics milestone. Must land
> before `12-runtime-nim-physics-evaluation.md` (runtime eval reads the format
> record this prompt defines). Prompts 13 (conformance) and 14 (Dart parity)
> follow.
> **Candidate category:** frontier.

---

/big-change Promote physics constraints from a standalone Nim integrator module to a first-class, loadable, validated, round-trippable `.bony`/`.bnb` format record (no runtime evaluation yet).

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony` M5 covers four constraint families: IK, transform, path, and physics
(`registry/key-ranges.md` M5 scope line; `docs/constraint-total-order.md`).
IK, path, and transform are already first-class format records with
cross-runtime conformance goldens. Physics is **half-built**: the deterministic
integrator math already exists and is unit-tested, but there is no format
record, no schema, no registry entry, no defaults coverage, and the loader does
not parse a physics constraint.

Concretely, already in place:
- `runtime-nim/src/bony/constraints/physics_constraints.nim` exports the full
  integrator: constants `physicsFixedDt (1/60)`, `physicsMaxFrameDt (0.25)`,
  `physicsMaxSubsteps (8)`, `physicsStepEpsilon (1e-9)`, `physicsMassEpsilon
  (1e-6)`; types `PhysicsChannel = enum pcX, pcY, pcRotate, pcScaleX, pcShearX`,
  `PhysicsParams {inertia, strength, damping, mass, gravity, wind, mix}` (all
  f64), `PhysicsChannelState`, `PhysicsConstraintState {accumulator, active,
  channels}`, `PhysicsChannelInput`, `PhysicsChannelOutput`,
  `PhysicsUpdateResult`; and procs `physicsParams` (defaults inertia=0,
  strength=0, damping=0, mass=1, gravity=0, wind=0, mix=1, with finite/
  non-negative/[0,1] validation), `physicsChannelInput`, `seedPhysicsChannel`,
  `integrateChannel`, `updatePhysicsConstraint`. This module is the numeric
  contract; do NOT re-derive or duplicate its math here.
- `runtime-nim/src/bony/model.nim:32` already defines `ConstraintKind = enum
  ckIk, ckTransform, ckPath, ckPhysics`; `constraintStageRank` (model.nim:822)
  already puts `ckPhysics` in a later stage than the other three, and
  `constraintKindRank` ranks `ckPhysics = 3`. So the ordering contract already
  covers physics — no ordering change is required.
- `runtime-nim/src/bony/constraints/update_cache.nim` already partitions
  physics out of the world-transform pass (`if descriptor.kind != ckPhysics`
  at update_cache.nim:116) and provides `buildPhysicsConstraintOrder`
  (update_cache.nim:161). No cache change is required in this prompt.
- `docs/physics-integrator-contract.md` is the binding runtime contract
  (integrator, fixed step, accumulator, reset, per-substep order, channel
  mapping). It is authored but not yet referenced by any format record.

Missing (this prompt builds exactly this — **format/load only, no eval**):
1. Registry: a `physicsConstraint` type in `registry/wire.yml`. The next free
   M5 **type** key is `4004` (type keys `4000` path, `4001` pathAttachment,
   `4002` ikConstraint, `4003` transformConstraint are used). M5 **property**
   keys `4000..4018` are used; the next free M5 property key is `4019`. Reuse
   the existing `bone` property key (M2 key `1012`, a bone-name reference —
   already reused by `transformConstraint`) for the
   singular constrained bone and the existing `order` key (`4002`) for the
   signed order. Allocate NEW property keys from `4019+` for the seven physics
   params (`inertia`, `strength`, `damping`, `mass`, `gravity`, `wind`, `mix` —
   `f32` backing per the contract's "may store parameters as f32-backed
   values") and for the enabled-channel encoding. For the channel encoding, do
   NOT template off `ikConstraint`'s `bones` (key 4014, `backingType: bytes`):
   that is a variable-length packed *array of string-table indices*,
   structurally unrelated to a fixed enable-set over the five `PhysicsChannel`
   values. Use ONE of two decisive shapes instead — (a) a single `varuint`
   property that is a bitmask with one bit per `PhysicsChannel` ordinal
   (`pcX=bit0 .. pcShearX=bit4`), preferred; or (b) five `bool` properties, one
   per channel, following the existing `bendPositive` (key 4016,
   `backingType: bool`) precedent. Prefer (a) unless a five-bool shape reads
   more naturally in the schema. Do NOT reuse the IK `mix` key (4015): its
   registry `doc` scopes it to IK solved-rotation blend, which is a different
   semantic than the physics spring-offset mix. Each new entry must cite its
   owning bead in `doc` and use only the M5 band.
2. Nim model: a `PhysicsConstraintData` type mirroring `TransformConstraintData`
   (model.nim:100) — fields `name`, `bone` (constrained), `order`, the enabled
   channel set, and the seven params — plus a `physicsConstraints:
   seq[PhysicsConstraintData]` field on `SkeletonData` (next to
   `transformConstraints` at model.nim:214), an accessor mirroring
   `transformConstraints*` (model.nim:542), and constructor + validation wiring.
   Thread a `physicsConstraints` parameter through the `skeletonData*`
   constructor (model.nim:781; it assigns `result.transformConstraints` at
   model.nim:806 — add `result.physicsConstraints` alongside) and through
   **both** `validateSkeletonData*` overloads (raw-fields overload at
   model.nim:586, `SkeletonData` overload at model.nim:809, whose forwarding
   call is at model.nim:812). Load-time validation follows the STRUCTURE of the
   `transformConstraints` block at model.nim:711-733 (unique non-empty name,
   known `bone` reference) but the per-field checks are physics-specific: params
   finite / mass non-negative / mix in [0,1] — reuse the
   `requireFinite`/`requireNonNegative`/`requireMix` checks already in
   `physics_constraints.nim`, and construct a `PhysicsParams` via
   `physicsParams(...)` so validation is single-sourced. NOTE: the transform
   block validates four always-present mixes and has NO "enabled channel"
   concept, so the "at least one enabled channel must be set" check that physics
   needs is **net-new** — author it; do not expect to find it in the transform
   template.
3. JSON + BNB loader: parse `physicsConstraints` in the `.bony` JSON loader and
   the flat `.bnb` binary loader, mirroring exactly how `transformConstraints`
   is parsed (JSON path around the transform-constraint parse added by bead
   bony-8i1; BNB path in the same loader module). No eval — just load into
   `PhysicsConstraintData` and validate.
4. Defaults + schema: a `physicsConstraint` object block in `spec/defaults.yml`
   (mirror the `transformConstraint` blocks at defaults.yml:211 and 446-457):
   `order` is structural → `value: 0`, `applyOnLoad: true`; the seven params are
   runtime integrator inputs → each `applyOnLoad: false` with defaults matching
   `physicsParams` (`inertia/strength/damping/gravity/wind` → `0.0`, `mass` →
   `1.0`, `mix` → `1.0`). A `physicsConstraint` `$def` + `physicsConstraints`
   array in `spec/bony.schema.json` (mirror `transformConstraint` at
   bony.schema.json:48) and the matching flat entry in
   `spec/bony-wire.schema.json` (mirror the `transformConstraint` `$def` at
   bony-wire.schema.json:690 and the array at bony-wire.schema.json:48).
5. Codegen regen: run `codegen/generate.py` to regenerate
   `runtime-nim/src/bony/generated/wire.nim` and
   `runtime-dart/lib/src/generated/wire.dart` (do not hand-edit generated
   files). `validate_sources()` runs unconditionally and fails if the registry
   object, `defaults.yml` coverage, and `requiredProperties` drift apart — so
   the registry entry, defaults entry, `requiredProperties` for `name`/`bone`,
   schema, and regen must ALL land in this one change.

Keep the record **minimal and integrator-faithful**: fields are exactly the
inputs `updatePhysicsConstraint`/`physicsParams` consume plus `name`, `bone`,
`order`, and the enabled-channel set. Do NOT add a target bone (physics springs
off the bone's own animated target pose, per
`docs/physics-integrator-contract.md` "State"/"Per-Substep Integration"), and do
NOT add reset-timeline fields, `skinRequired` gating, or per-channel param
overrides in this slice.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md (physics/spring constraints
  are a named comparable capability category only — not an implementation source)
- Physics runtime contract: docs/physics-integrator-contract.md
- Constraint order contract: docs/constraint-total-order.md
- Registry key bands: registry/key-ranges.md (M5 = 4000..4999)
- Registry source: registry/wire.yml (transformConstraint type key 4003;
  ikConstraint `bones` packed key 4014; M5 property keys 4000..4018 used)
- Defaults: spec/defaults.yml (transformConstraint objectDefaults block at 211;
  transformConstraint requiredProperties at 446, 450, 454 — the block spans
  446-457, line 458 is pathAttachment)
- JSON schema: spec/bony.schema.json (transformConstraint $def; transformConstraints
  array at line 48)
- Wire schema: spec/bony-wire.schema.json (transformConstraint $def at 690,
  array at 48)
- Codegen: codegen/generate.py (`validate_sources()` runs unconditionally from
  `main()` even under `--check`; every registry property must be covered by
  exactly one of `objectDefaults`/`requiredProperties`, no overlap)
- Nim integrator (the numeric contract; do not duplicate its math):
  runtime-nim/src/bony/constraints/physics_constraints.nim
- Nim model: runtime-nim/src/bony/model.nim (ConstraintKind line 32,
  TransformConstraintData line 100, SkeletonData constraint fields line 212-214,
  transformConstraints accessor line 542, validateSkeletonData overloads lines
  586 and 809, transformConstraints validation block line 712, skeletonData
  constructor line 781)
- Analogous freshest record to mirror: the `transformConstraint` wiring landed by
  bead bony-8i1 (registry + model + loader + defaults + schema); diff it as the
  template.
- Repo gate: Makefile `test` target
- Beads: file under the physics milestone parent before implementing

**Success Criteria**
- `registry/wire.yml` gains a `physicsConstraint` type (key `4004`, milestone
  `M5`, owner bead cited) plus new property keys from `4019+` for the seven
  params and the channel encoding; no key collides with an existing M5 entry;
  each new entry cites its owning bead.
- `spec/defaults.yml` has a `physicsConstraint` block covering every defaultable
  property; `python3 codegen/generate.py --check` passes.
- `spec/bony.schema.json` gains a `physicsConstraint` $def and a
  `physicsConstraints` array; `spec/bony-wire.schema.json` gains the matching
  flat entry; `python3 scripts/ci/schema_validate_assets.py` passes for all
  assets.
- Codegen regenerated (`generated/wire.nim` and `generated/wire.dart`) via
  `codegen/generate.py`; no hand-edits to generated files.
- `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim` is
  clean; Nim unit tests pass (`runtime-nim/tests/test_smoke.nim`), including a
  NEW round-trip test that loads a physics constraint from both a `.bony` JSON
  fixture and its `.bnb` and asserts the parsed `PhysicsConstraintData` fields
  and params match (JSON and binary loaders agree).
- Update the hardcoded registry change-detector assertions in
  `runtime-nim/tests/test_smoke.nim:102-105` (`bonyTypeKeys.len == 25`,
  `bonyPropertyKeys.len == 87`, `bonyPropertyDefaults.len == 45`,
  `bonyRequiredProperties.len == 65`) to the new totals — the new type key and
  ~7-8 new property keys WILL break these counts. This is the exact stale-count
  drift documented for bead bony-bru; bump them in this change or `make test`
  fails.
- `make test` passes.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine,
  Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose. The
  integrator math and parameter set are project-owned (already in
  `physics_constraints.nim` and `docs/physics-integrator-contract.md`); do not
  import a third party's physics/spring field set or parameter names.
- Use `docs/comparable-feature-set.md` only to justify the physics-constraint
  capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for
  human/legal review.
- Registry edits: use only the M5 band (`4000..4999`) per
  `registry/key-ranges.md`, and follow the registry shared-surface reservation
  rule in that file.
- Land the registry entry, `defaults.yml` entry, schema, `requiredProperties`,
  and codegen regeneration together in this one change — `validate_sources()`
  fails if they drift apart.
- Do **NOT** implement runtime evaluation, per-instance physics state, a
  conformance rig/golden, or the Dart runtime in this prompt. Those are prompts
  12, 13, and 14. This slice ends when a physics constraint loads, validates,
  and round-trips through JSON and `.bnb` — but is not yet evaluated.
- Keep the slice to one meaningful implementation session: one new loadable
  format record, Nim load path only.
