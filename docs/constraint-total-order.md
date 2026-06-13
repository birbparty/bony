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
