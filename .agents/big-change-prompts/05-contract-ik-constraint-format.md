# /big-change prompt - registry/spec (IK constraint format)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 3**. Freezes the IK wire/JSON format that
> step 2 (Nim runtime) decodes and step 3 (conformance) emits. Run first.
> **Candidate category:** frontier.

---

/big-change Define the project-owned IK (inverse kinematics) constraint format: registry keys, JSON schema, the loaded data model, and the format contract note.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

The Nim IK solver already exists at `runtime-nim/src/bony/constraints/ik.nim`
(`solveOneBoneIk`, `solveTwoBoneIk`, `solveChainIk`) but no IK constraint can be
expressed in `.bony` JSON, decoded from `.bnb`, or loaded into `SkeletonData` -
the solver is unreachable dead code. `ConstraintKind` already lists `ckIk` first
(`runtime-nim/src/bony/model.nim:33`) and the constraint ordering contract
already assigns IK a priority (`docs/constraint-total-order.md`).

This slice closes only the **format** half: it allocates IK registry keys in the
M5 band, defines the JSON schema surface, defines the in-memory
`IkConstraintData` model plus its constructor, and records the format contract.
It deliberately does **not** wire the solver into the pose pipeline or add
conformance assets - those are steps 2 and 3. After this slice the format is
frozen so the runtime decode in step 2 has stable keys.

Mirror the existing **path constraint** precedent exactly; it is the closest
shipped sibling and already covers registry + schema + model + loaders:
- Registry path entries: `registry/wire.yml` type key `4000` (`path`), property
  keys `target` (4000), `path` (4001), `order` (4002).
- Schema: `spec/bony.schema.json` `paths` array (line ~30, `"$ref": "#/$defs/path"`)
  and the lowercase **`path`** object definition under `$defs`
  (`spec/bony.schema.json:516-559`). Note the schema naming convention is the
  lowercase registry `id` (`path`), **not** the Nim type name `PathConstraintData`;
  name the new IK definition `ikConstraint` to match.
- Model: `PathConstraintData` (`runtime-nim/src/bony/model.nim:77-89`),
  `SkeletonData.paths` field (`model.nim:188`), and the `pathConstraintData*`
  constructor (`model.nim:281`).

**Recommended IK data shape (decide and freeze in this slice).** Derive the
shape from the existing solver inputs, not from any third-party format. The
solver consumes bone-derived points/lengths and a target, returning rotations in
degrees. The lowest-key-cost shape that drives one-bone, two-bone, and N-bone
solves is:

- `name` (string).
- `bones`: an ordered list of constrained bone names, root -> tip. Its length
  selects the solver: 1 bone -> `solveOneBoneIk`, 2 -> `solveTwoBoneIk`,
  >= 3 -> `solveChainIk`. (Reuse a new property key for this string list.)
- `target`: the bone name whose world position is the IK goal (reuse the shared
  `target` property key 4000).
- `order`: signed global constraint order (reuse the shared `order` property
  key 4002).
- `mix`: optional, default `1.0`, range `[0,1]` (the solver's `mix`).
- `bendPositive`: optional bool, default `true`, used only for the two-bone case
  (maps to the solver's `bendSign`: `true` -> `+1`, `false` -> `-1`).

**Segment lengths are computed at runtime from the bones' rest-pose world
positions, NOT stored in the format.** This is a binding decision for this
milestone: do not allocate per-segment length keys. It keeps the format minimal
and matches how skeletal IK derives bone lengths. Record this decision in the
contract note so step 2 computes lengths and does not invent length keys.

**Links to Relevant Documentation**
- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md`
- Registry key bands: `registry/key-ranges.md` (M5 = `4000..4999`, IK is in scope)
- Registry wire format: `registry/wire.yml`, `registry/README.md`
- JSON schema: `spec/bony.schema.json`, `spec/README.md`, `spec/DEFAULTS.md`
- Constraint ordering contract: `docs/constraint-total-order.md`
- Existing IK solver (do not modify here): `runtime-nim/src/bony/constraints/ik.nim`
- Loaded-asset model: `runtime-nim/src/bony/model.nim`
- Schema-validation gate: `scripts/ci/schema_validate_assets.py`

**Current Local Facts To Preserve**
- `registry/wire.yml` already uses M5 type keys `4000` (path) and `4001`
  (pathAttachment), and M5 property keys `4000..4013`. Allocate IK keys from the
  remaining free M5 band only; never reuse or renumber an existing key. The
  shared property keys `target` (4000) and `order` (4002) are cross-constraint
  concepts and may be reused by IK; introduce new property keys only for
  IK-specific fields (e.g. the IK target chain endpoint, bone list, bend
  direction, and mix).
- `registry/wire.yml` entries are append-only and each must cite an `ownerBead`
  and the owning `milestone: M5`.
- `ConstraintKind` (`model.nim:32` enum header; `ckIk` is line 33) already lists
  `ckIk` first; do not change the enum order - `docs/constraint-total-order.md`
  derives priority from it.
- The JSON loader validates the allowed root keys at `runtime-nim/src/bony/jsonio.nim:311`
  (`validateKnownKeys(root, [...])`). Adding a new top-level `ikConstraints` array
  means this list must gain the new key in step 2; record that the chosen JSON
  key name is final here so step 2 matches it.
- Decide and document the IK data shape needed by the existing solver: the solver
  consumes an origin chain of bones, per-segment lengths, a target point, an
  optional bend sign (`solveTwoBoneIk` `bendSign`), and a `mix` in `[0,1]`. The
  format must carry enough to drive one-bone, two-bone, and N-bone chain solves
  using bone references (names), not raw points - the runtime derives points from
  world transforms in step 2.

**Success Criteria**
- `registry/wire.yml` gains an `ikConstraint` type key and any IK-specific
  property keys, all within `4000..4999`, each with `status`, `milestone: M5`,
  `ownerBead`, and a `doc` string. `registry/key-ranges.md` needs no band change
  but confirm its M5 row still reads correctly.
- `spec/bony.schema.json` gains an `ikConstraints` array property and a lowercase
  `ikConstraint` object definition under `$defs` carrying the fields above
  (`bones` list, `target`, `order`, optional `mix`, optional `bendPositive`),
  consistent in style with the existing `path` `$def`. Required vs optional fields
  and defaults (`mix` = 1.0, `bendPositive` = true) are documented in
  `spec/DEFAULTS.md`.
- `runtime-nim/src/bony/model.nim` gains an `IkConstraintData` object (with the
  fields above plus `has*` flags for optionals, mirroring `PathConstraintData`),
  an `ikConstraints` field on `SkeletonData`, and an `ikConstraintData*`
  constructor mirroring `pathConstraintData*`. The model compiles but is not yet
  loaded or evaluated (that is step 2).
- The contract note records the binding decision that segment lengths are
  rest-pose-derived at runtime and never stored in the format.
- The chosen top-level JSON key name and all field names are written down in this
  slice's output so steps 2 and 3 use identical spelling and casing (verify JSON
  field casing on both the schema side and the planned Nim loader side).
- No solver code, loader code, binary decode, pose-pipeline integration, or
  conformance asset is added in this slice.
- Verification (format-only; no runtime behavior to exercise yet):

```bash
python3 -c "import yaml,sys; yaml.safe_load(open('registry/wire.yml'))"
python3 -c "import json,sys; json.load(open('spec/bony.schema.json'))"
nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim
python3 scripts/ci/schema_validate_assets.py || true   # existing assets must still validate; IK assets arrive in step 3
```

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose. The
  IK data shape must be derived from the existing `ik.nim` solver inputs and the
  path-constraint precedent, not from any third-party format.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- IK only. Do not define, register, or schema transform constraints or physics
  constraints; their solvers (`transform_constraints.nim`, `physics_constraints.nim`)
  remain unwired and out of scope for this milestone.
- Append-only registry: never renumber, repurpose, or delete an existing key.
- Keep the slice small enough for one meaningful implementation session.
