# Skin Required Activation Contract

Status: **binding**. Owner bead: `bony-hfa2` (skinRequired activation contract).

This contract defines the `bony`-owned runtime and validation semantics for
`skinRequired` bones and constraints. It layers on top of the first-class
`skins[]` attachment model in `docs/skin-attachment-set-contract.md`, the
constraint cache ordering rules in `docs/constraint-total-order.md`, and the
inactive physics rules in `docs/physics-integrator-contract.md`.

This slice is **contract only**. It does not assign JSON field names, binary
type keys, property keys, schema entries, runtime code, conformance assets, or
importer mappings. A later format/load slice must implement the serialized
membership surface described below.

## Scope

This document owns:

- Active-skin membership semantics for `skinRequired` bones.
- Active-skin membership semantics for `skinRequired` IK, transform, path, and
  physics constraints.
- Runtime behavior for inactive required bones and constraints.
- Load-time validation rules needed before runtime filtering is implemented.
- Future serialized-surface requirements for required-item membership.
- Conformance scenarios that later implementation slices must add.

This document does not change attachment lookup. Slot-visible attachments still
resolve through the active skin first and the `"default"` skin fallback second,
as defined by `docs/skin-attachment-set-contract.md`.

## Definitions

`active skin`
: The skin selected for a `SkeletonInstance`. If no non-default skin is selected,
  the active skin is `"default"`. Selecting an unknown skin is a runtime/load
  integration error; runtimes must not silently fall back to `"default"` for an
  unknown active-skin name.

`required item`
: A bone or constraint whose loaded `skinRequired` flag is true.

`membership record`
: A future skin-owned reference saying that a required bone or required
  constraint belongs to that skin. Membership references are semantic names in
  canonical JSON and typed indices in `.bnb`.

`active membership set`
: The union of required-item membership records from `"default"` and the active
  skin. When the active skin is `"default"`, the set is just `"default"`.
  Duplicate membership references inside the union are idempotent.

`directly active`
: A non-required item, or a required item present in the active membership set.

`effectively active`
: A directly active item whose runtime dependencies are also active. Bones use
  parent-chain dependency; constraints use their referenced bones and helper
  attachment dependencies.

Only effectively active items participate in runtime output.

## Active Membership Model

The `"default"` skin contributes membership for every active skin. A non-default
skin adds membership; it cannot remove or mask membership from `"default"`.

For a required bone:

- The bone is directly active when its name is present in the active membership
  set.
- The bone is effectively active only when its parent is absent or effectively
  active.
- If a required bone is not present in the active membership set, it is inactive
  for that pose.

For a required constraint:

- The constraint is directly active when its name is present in the active
  membership set for its constraint family.
- The constraint is effectively active only when every referenced runtime input
  it needs is effectively active.
- If a required constraint is not present in the active membership set, it is
  inactive for that pose.

Membership is per family. A bone and a constraint may share the same text name
without colliding because their membership records resolve in different typed
domains.

Non-required bones and constraints do not need membership records. A membership
record for a non-required item is invalid because it would imply that a
non-gated item can be gated by skin selection.

## Constraint Dependencies

An effectively active constraint must have all of the dependencies below
effectively active:

- IK: every constrained bone and the target bone.
- Transform: the constrained bone and the target bone.
- Path: the constrained bone, target bone, path attachment, and any bone/slot
  chain needed to evaluate that path attachment.
- Physics: the constrained bone.

Path attachment dependencies follow the same active-bone and active-slot rules
as render/helper attachments. If the path attachment is not available under the
current active skin plus `"default"` fallback, the path constraint cannot be
effectively active.

## Inactive Required Bones

An inactive required bone is skipped for observable runtime behavior:

- Its world transform is not a valid public pose output for that frame.
- Animation timelines may still sample their values, but applying those values
  must not make the bone observable while it is inactive.
- Constraints and physics must not write to it.
- Child bones are effectively inactive unless the full parent chain is active.
- Slots bound to it are inactive.
- Attachments on inactive slots are not resolved through skin lookup and do not
  emit render data.
- Point, bounding-box, clipping, and path helper attachments on inactive slots
  are unavailable to hit tests, listeners, clipping, and constraints.
- A nested-rig attachment hosted by an inactive slot is not instantiated,
  advanced, queried, or emitted for that frame.
- Draw-batch construction emits no vertices, indices, clip state, or batch break
  caused only by an inactive slot.

If an attachment could be visible while its mesh, clipping polygon, path, point,
or bounding-box data references an inactive required bone, the asset is invalid
unless a later contract defines an explicit fallback. The default runtime must
not substitute identity transforms, zero weights, stale transforms, or setup
pose transforms for inactive required bones.

## Inactive Required Constraints

Inactive required constraints keep their canonical position in precomputed
constraint caches. Cache construction must include active and inactive
constraints and must use the potential read/write dependencies of the loaded
constraint, not the current active-skin state, so a skin swap cannot reorder
later active constraints.

At evaluation time:

- An inactive IK, transform, or path constraint is a no-op at its cache
  position.
- Skipping the no-op must not collapse, renumber, or move any later cache entry.
- A stateless solver may use a no-op fast path only when it has the same
  observable result as evaluating an inactive constraint at that canonical
  position.
- `mix == 0` is not the same as inactive; zero-mix behavior remains owned by the
  solver contract for that constraint family.

For physics constraints:

- An inactive required physics constraint does not add `dt` to its accumulator.
- It does not process fixed substeps.
- It does not update channel offset, velocity, previous target, or output.
- It preserves existing state while inactive.
- When it becomes active again after being inactive, it resets using the
  initialization/reset rules in `docs/physics-integrator-contract.md`.

The reactivation reset is required for skin swaps, active membership changes,
and any other event that makes an inactive required physics constraint active
again. A future preserve-state mode would need an explicit serialized/runtime
opt-in and conformance fixtures; it is outside this default contract.

## Load Validation

A conforming loader must reject malformed membership before runtime
construction.

Required membership checks:

1. Every membership reference resolves to exactly one loaded item in its typed
   domain. Unknown required bones, IK constraints, transform constraints, path
   constraints, or physics constraints are `unknownRequiredReference` errors.
2. A membership list must not contain duplicate references within one skin and
   family. Duplicates across `"default"` and a non-default skin are allowed and
   collapse in the active membership set.
3. A membership reference to an item whose `skinRequired` flag is false is a
   schema/semantic violation.
4. For every skin, a required bone membership must include every required
   ancestor that is not already provided by `"default"`.
5. A non-required bone whose parent can be inactive is invalid unless every skin
   that can make the parent inactive also makes the descendant unobservable.
   The v1 portable rule is stricter: reject a non-required bone with a
   `skinRequired` ancestor.
6. A required constraint membership must include, or inherit from `"default"`,
   every required bone and helper dependency needed by that constraint.
7. A non-required constraint that references a required bone or helper that can
   be inactive is invalid. Either the dependency must be non-required or default
   membership must make it active for every skin.
8. An active skin must not make a child required bone active while leaving a
   required parent inactive.
9. Active membership validation must be performed for `"default"` alone and for
   each declared non-default skin unioned with `"default"`.

These checks make runtime filtering a deterministic activation decision rather
than a best-effort recovery path.

## Future Serialized Surface

A later format/load slice must add explicit skin-owned membership lists for:

- Required bones.
- Required IK constraints.
- Required transform constraints.
- Required path constraints.
- Required physics constraints.

The future surface must satisfy these requirements:

- Membership is stored under the owning skin, separate from attachment `entries`.
- Canonical JSON references loaded item names.
- `.bnb` references typed loaded indices and remains append-only in the
  registry.
- Canonical emission preserves deterministic order: bones in skeleton order and
  constraints in their source array order within each family.
- The `"default"` skin's membership is emitted and loaded like any other skin's
  membership.
- Unknown future membership families are skipped only if no known active item
  requires them.
- Loaders preserve source order for constraint arrays before resolving
  membership, so source-index tie-breaking remains stable.

This contract does not assign the concrete JSON field names or binary keys for
those lists. It relies on the local spec's existing `skinRequired` term and the
project-owned bone/constraint family model; it introduces no net-new serialized
identifier in this slice.

## Runtime Skin Swaps

Changing the active skin recomputes the active membership set before the next
pose evaluation. Implementations must then:

1. Mark required bones and constraints effectively active/inactive from the new
   set.
2. Treat newly inactive slots and helpers as unavailable immediately.
3. Keep constraint cache order unchanged.
4. Reset any required physics constraint that transitions from inactive to
   active.
5. Re-resolve slot-visible attachments through active skin then `"default"` as
   defined by the skin attachment-set contract.

Skin swaps do not mutate immutable `SkeletonData`. They affect only the
instance's active-skin selection and live state.

## Conformance Scenarios

Later implementation slices must add fixtures for:

- A non-default skin that adds a required bone while `"default"` contributes a
  shared required helper bone.
- A required child bone omitted from the active membership set, proving its
  slot, attachment, helper queries, and draw batches disappear.
- A non-required descendant of a required parent rejected by load validation.
- A required IK constraint inactive under one skin and active under another,
  proving later active constraints keep the same canonical cache positions.
- A required transform constraint whose target bone is missing from membership,
  proving load validation rejects the asset.
- A required path constraint whose path helper attachment is inactive, proving
  load validation rejects the active membership combination.
- A required physics constraint inactive for several updates, proving its
  accumulator and channel state do not advance.
- The same physics constraint reactivated by a skin swap, proving reset-on-
  reactivation behavior.
- Duplicate membership entries rejected within one skin/family but accepted as
  an idempotent union across `"default"` and a non-default skin.
- JSON-to-binary-to-JSON round-trip preserving membership order once the
  serialized surface exists.
