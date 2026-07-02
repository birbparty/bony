# Constraint Total-Order Contract

This contract defines the deterministic ordering key for all runtime
constraints. It must be followed by the Nim reference runtime, the Dart runtime,
and the conformance harness before M5 constraint work begins.

## Scope

Skeleton data stores constraints in four arrays:

- `ik[]`
- `transforms[]`
- `paths[]`
- `physics[]`

Each constraint carries an integer `order` field. The `order` field alone is
not a total order because different arrays, and multiple entries inside the
same array, can share the same value. Implementations must therefore use the
tie-break rules in this document whenever they construct update caches or run
constraints.

This document owns:

- The canonical constraint sort key.
- The execution domains that consume that key.
- Inactive-constraint behavior for ordering.
- Conformance scenarios for deterministic tie handling.

It does not define solver math, transform composition formulas, or physics
integration formulas.

## Path Constraint Runtime Contract

`paths[]` entries currently store only:

- `name`
- `bone`
- `target`
- `path`
- `order`

That payload is sufficient for validation, serialization, deterministic update
cache construction, and path-attachment reference checks. It is not sufficient
to define a runtime path solver. A runtime-evaluable path constraint needs at
least an explicit path position/distance channel, coordinate-space policy,
translation/rotation behavior, and output mix. Implementations must therefore
not infer solver defaults from the current five-field payload.

Until those fields are added to the JSON schema, wire registry, and loaders,
the v1 runtime behavior for existing `paths[]` entries is:

- Include each path constraint in the canonical world-transform update cache at
  its `(stageRank, order, kindRank, sourceIndex)` position.
- Validate that `bone`, `target`, and `path` references are known.
- Do not modify bone world transforms, draw batches, or numeric/image goldens.
- Preserve existing `m5_rig_t0.json` and `m5_rig_play.png` output.

The runtime-evaluable v1 path-constraint extension must add explicit solver
fields before changing output. The solver extension is opt-in: a path
constraint is runtime-evaluable only when at least one of the solver fields
below is present after load. Five-field path constraints continue to use the
validation-only behavior above. If any solver field is present, absent solver
fields use the evaluation defaults below for that constraint, but those absent
fields still remain absent for canonical emission and binary presence tracking.

The extension fields and defaults are:

- `position`: f32 normalized distance along the path in `[0, 1]`. Default
  `0.0`, but this default is `applyOnLoad: false` for compatibility: old
  five-field files do not become runtime-evaluable merely because the default
  exists. When the field is present, `position = 0.0` samples the path start
  and `position = 1.0` samples the path end.
- `translateMix`: f32 blend in `[0, 1]`. Default `1.0` with
  `applyOnLoad: false`. When present, the constrained bone's local translation
  is blended from its unconstrained local translation toward the sampled path
  point transformed into the parent bone's local space.
- `rotateMix`: f32 blend in `[0, 1]`. Default `0.0` with
  `applyOnLoad: false`. When present and greater than zero, the constrained
  bone's local rotation is blended toward the sampled path tangent angle in the
  parent bone's local basis. `rotateMix = 0.0` preserves existing rotation.

Path attachment control points are interpreted in the `target` bone's local
space. To evaluate a runtime path constraint:

1. Compute the target bone world transform at the constraint's canonical
   update-cache position.
2. Transform the cubic path attachment control points by the target bone world
   transform into skeleton/root space.
3. Build the fixed `pathArcLengthSamples = 32` arc-length table already
   defined by `runtime-nim/src/bony/constraints/path_constraints.nim`.
4. Sample by `position * totalLength`.
5. Convert the sampled position from skeleton/root space into the constrained
   bone parent's local space using the full inverse parent affine. If the
   constrained bone has no parent, skeleton/root space is the parent local
   space. If the parent affine is singular and `translateMix > 0`, the
   runtime-evaluable path constraint is invalid and must be rejected; runtimes
   must not use a pseudo-inverse or host-specific fallback.
6. Blend translation by `translateMix` and rotation by `rotateMix`, then
   recompute the constrained bone world transform before any later cache
   entries read it.

Rotation uses the same parent-space conversion as translation: transform the
sampled tangent vector by the parent's inverse linear 2x2 matrix, then compute
`atan2(y, x)` in degrees. If the parent linear matrix is singular and
`rotateMix > 0`, the runtime-evaluable path constraint is invalid and must be
rejected. If `rotateMix = 0`, runtimes may skip tangent conversion and preserve
the unconstrained local rotation. Blend rotation by shortest signed angular
delta, matching the transform-constraint shortest-angle rule. The constrained
bone's own `inheritRotation`, `inheritScale`, `inheritReflection`, and
`transformMode` flags are applied only when recomputing its world transform
from the blended local transform; they do not change the sampled path-space
conversion.

The extension does not define chain spacing, offset rotation, percent-vs-fixed
distance modes, or multi-bone path distribution. Those require additional
fields and must not be inferred from the v1 extension.

Serialization requirements for the extension:

- Add JSON schema fields and wire property keys for `position`,
  `translateMix`, and `rotateMix`.
- Default-table entries must use `applyOnLoad: false` so old files remain
  validation-only.
- Canonical emission may omit default-valued solver fields only when they were
  absent on load or explicitly canonicalized by a versioned migration. It must
  not silently remove the last present solver field from a runtime-evaluable
  constraint.
- Binary loaders must preserve whether solver fields were present, not just
  their numeric value, because presence is the opt-in signal.

When those fields land, conformance must update `m5_rig.bony` to opt into the
new solver behavior explicitly and regenerate `m5_rig_t0.json` plus any image
goldens that observe changed world transforms. Older five-field path
constraints must remain byte/load compatible and continue to produce the
validation-only output described above unless a migration explicitly opts them
into solver fields.

## Transform Constraint Runtime Contract

Unlike path constraints, transform constraints are **runtime-evaluable in v1** —
the format record already carries every field the solver consumes. A
`transformConstraints[]` entry stores:

- `name`
- `bone` — the constrained bone (singular; not a chain)
- `target` — the bone whose world pose is the blend target
- `order`
- `translateMix`, `rotateMix`, `scaleMix`, `shearMix` — four independent f32
  blend amounts in `[0, 1]`, each `omitWhenDefault` with default `1.0` and
  `applyOnLoad: false`, presence-tracked so the four mixes round-trip byte-stably.

A transform constraint is runtime-evaluable when **any** mix is greater than
zero (an all-zero constraint is a no-op and is skipped by the detection gate,
the update-cache read gating, and the apply guard alike — the same
constraint-only predicate is used in all three places). There is no separate
opt-in field: the mix values themselves are the signal, and because they default
to `1.0`, a bare transform constraint evaluates at full influence.

The constraint participates in the canonical world-transform update cache at its
`(stageRank, order, kindRank, sourceIndex)` position; `constraintKindRank` places
transform constraints **after IK and before path** (`ckIk = 0 < ckTransform = 1
< ckPath = 2`). The descriptor sets `writes = [bone]` and, when runtime-evaluable,
`reads = [target]`, so the shared builder emits the target (and its lineage)
before the constraint and re-derives the constrained bone from its constraint-set
local afterward.

To evaluate a runtime transform constraint:

1. Compute the constrained bone's **current** world transform by FK-composing its
   live local transform onto its already-emitted parent world (the constrained
   bone is a constraint write target, so it is not pre-emitted by a bone group).
2. Read the `target` bone's already-computed world transform. If the target (or
   the constrained bone's parent) has not been emitted yet, the constraint is
   mis-ordered and must be rejected with an ordering violation.
3. Decompose both world affines into `(x, y, rotation, scaleX, scaleY, shearX,
   shearY)` poses and blend **per channel**: translation (`x`, `y`) by
   `translateMix`, `rotation` by `rotateMix` using the shortest signed angular
   delta, `scaleX`/`scaleY` by `scaleMix`, and `shearX`/`shearY` by `shearMix`
   (also shortest-angle). `mix = 0` on a channel preserves the constrained pose;
   `mix = 1` snaps it fully to the target.
4. Recompose the blended pose into a world affine, then write it back as the
   constrained bone's **local** transform (inverting `worldForBone`: translation
   via the full inverse parent affine, linear via the inherited-factor inverse
   selected by the bone's `inheritRotation`/`inheritScale`/`inheritReflection`
   flags) so the trailing FK re-derivation reproduces it. If the parent affine or
   its inherited-factor product is singular, the constraint is invalid and must be
   rejected; runtimes must not use a pseudo-inverse or host-specific fallback.

Serialization mirrors the other M5 constraint records: the four mixes get JSON
schema fields (bounded `[0, 1]`) and wire property keys (`translateMix = 4012`
and `rotateMix = 4013` reused from path; `scaleMix = 4017` and `shearMix = 4018`
new), default-table entries use `applyOnLoad: false`, and binary loaders preserve
mix presence, not just value. The conformance rig `m5_transform_rig` exercises all
four channels at a partial `0.5` mix; see `conformance/README.md`.

## Canonical Sort Key

Every constraint has a canonical key:

```text
(stageRank, order, kindRank, sourceIndex)
```

Fields are compared lexicographically in ascending order.

`stageRank`
: `0` for world-transform constraints (`ik`, `transform`, `path`) and `1` for
  physics constraints.

`order`
: The integer `order` property stored on the constraint.

`kindRank`
: Fixed constraint-kind priority:
  `ik = 0`, `transform = 1`, `path = 2`, `physics = 3`.

`sourceIndex`
: The zero-based index of the constraint in its source array after loading and
  validation.

`stageRank` is intentionally the primary key. A physics constraint with a lower
`order` than a non-physics constraint still runs in the physics stage, after the
world-transform constraint pass.

No other value participates in ordering. Names, object identities, hash-table
iteration order, pointer addresses, allocation order, and map insertion order
must never affect constraint order.

## Execution Domains

The canonical key is shared by all constraint kinds, but the pose pipeline has
two execution domains. Cross-domain `order` values never move constraints
across the stage boundary.

### World-Transform Constraint Pass

The world-transform pass consumes only entries with `stageRank = 0`. IK,
transform, and path constraints are merged into a precomputed parent-first bone
update cache using their canonical order.

If two non-physics constraints share the same `order`, the fixed kind priority
applies before source array index:

```text
ik before transform before path
```

If two constraints of the same kind share the same `order`, the lower
`sourceIndex` runs first.

The update cache must precompute this order once per loaded skeleton data, or
recompute it only when skeleton data changes. Per-frame runtime state must not
change the order.

The cache is built as a sequence of `(bone-group | constraint)` entries:

1. Start with bones in parent-first skeleton array order.
2. Sort active and inactive non-physics constraints by canonical key.
3. For each constraint in sorted order, emit one `bone-group` containing every
   not-yet-emitted bone whose parent chain does not depend on that constraint.
4. Emit the constraint.
5. After the last constraint, emit one final `bone-group` containing every
   remaining not-yet-emitted bone.

Within a `bone-group`, bones are evaluated in parent-first skeleton array order.
A bone is "not-yet-emitted" until its world transform has been computed by the
cache for the current pose. A bone "depends on" a constraint when the constraint
can write that bone or any ancestor needed to compute that bone's world
transform. If two runtimes disagree about dependency analysis, they must choose
the conservative result that delays the bone until after the constraint. This
may reduce batching, but it preserves the canonical constraint order.

Runtime-evaluable path constraints also have a read dependency on their
`target` bone, because the path attachment is evaluated in target-bone local
space. The update cache must ensure the target bone and its ancestors have
already been emitted before the path constraint runs. If a later constraint
writes the target bone, the path constraint reads the pre-later-constraint world
transform; later constraints still run at their canonical positions. A path
constraint whose target cannot be emitted before the constraint without
violating parent-first order or canonical constraint order is invalid for the
runtime-evaluable extension and must be rejected when solver fields are
present. Five-field validation-only path constraints retain the existing
ordering-only behavior.

### Physics Stage

Physics constraints run after the non-physics world-transform/constraint pass
has produced the animated target pose. This matches the physics integrator
contract in `docs/physics-integrator-contract.md`.

Within the physics stage, constraints are ordered by the same canonical key.
Because every physics entry has the same `stageRank` and `kindRank`, practical
physics ordering is:

```text
(order, sourceIndex)
```

If multiple physics constraints affect the same logical channel, each
constraint reads the value written by earlier physics constraints and writes
its output before later physics constraints run.

## Source Index

JSON and binary loaders must preserve array order. The `sourceIndex` for a
constraint is its position in the loaded array, before inactive constraints are
filtered and before update caches are built.

Canonical JSON emission may reorder object keys, but it must not reorder
constraint arrays. Binary canonicalization must likewise preserve semantic
array order for constraints.

## Validation

All constraint `order` fields must be finite signed integers in the format's
allowed integer range. A missing `order` uses the schema/default-table value
chosen for that constraint kind; if no default exists, the file is invalid.

Constraint array elements must have a valid kind implied by their containing
array. Implementations must reject malformed data that places a constraint
payload in an incompatible array rather than attempting to derive ordering from
the payload shape.

Duplicate constraint names are a validation concern for references and
diagnostics only. Duplicate names do not change ordering.

## Inactive Constraints

Constraints disabled by `skinRequired`, missing required skin membership, or
other documented activation rules are skipped when evaluated. They retain their
canonical position in the update cache.

Skipping an inactive constraint must not collapse, renumber, or reorder any
later active constraint. If an inactive constraint becomes active on a later
frame, it runs at the same canonical position it always had.

Runtime `mix == 0` is not a generic inactive rule. Stateless solver contracts
may define a zero-mix fast path only when it produces the same observable
result as evaluating the constraint at its canonical position. Stateful
constraints, including physics, must follow their own state and accumulator
rules even when their output mix is zero.

## Determinism Requirements

- Sort constraints only by `(stageRank, order, kindRank, sourceIndex)`.
- Preserve source array order at load and canonical emission boundaries.
- Build ordered update caches from arrays, not maps.
- Use stable iteration over the precomputed cache during playback.
- Do not use host-language enum ordinals unless they are explicitly pinned to
  the `kindRank` table above.
- Do not parallelize constraints in a way that changes read/write order for
  affected bones or logical channels.
- Do not reorder constraints by dependency analysis unless the resulting order
  is exactly the canonical order.

## Conformance Scenarios

The M5 conformance suite must include:

- IK, transform, and path constraints with the same `order`, proving kind
  priority is `ik`, then `transform`, then `path`.
- Multiple constraints of the same kind with the same `order`, proving
  `sourceIndex` tie-breaking.
- Negative, zero, and positive `order` values, proving signed integer ordering.
- `skinRequired` inactive constraints skipped without changing later active
  constraint positions.
- Physics constraints with the same `order`, proving physics-stage
  `sourceIndex` tie-breaking.
- A low-`order` physics constraint and a higher-`order` non-physics constraint,
  proving physics still runs after the world-transform constraint pass.
- Non-physics constraints interleaved with parent-first bone groups, proving
  every runtime builds the same `(bone-group | constraint)` cache.
- A mixed fixture whose JSON object keys are deliberately shuffled, proving
  object key order does not affect constraint order.
- A fixture loaded, canonicalized, and reloaded, proving constraint array order
  is preserved across serialization boundaries.
