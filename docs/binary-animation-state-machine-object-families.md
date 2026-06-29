# Binary Animation And State-Machine Object Families

This document chooses the project-owned `.bnb` object shape for the current
animation and state-machine contract slice. It intentionally does not edit
`registry/wire.yml`; the follow-up registry bead should allocate concrete keys
from the existing M3 and M8 bands.

Inputs for this decision are limited by
[animation-state-machine-cleanroom-boundary.md](animation-state-machine-cleanroom-boundary.md)
and the local surface inventory in
[animation-state-machine-contract-boundaries.md](animation-state-machine-contract-boundaries.md).

## Scope

This slice preserves only the local features already present in JSON/runtime
surfaces:

- Animation clips.
- Bone scalar, vector, and inherit timelines.
- Slot attachment, color, two-color, and sequence timelines.
- Linear, stepped, and Bezier timeline curves.
- State machines with typed inputs.
- Layers with clip states and blend1d states.
- Blend clips.
- Transitions, conditions, and listeners.

Event timelines are not retained in this slice. Nim has event timeline data
types, but current JSON loading does not populate them and Dart has no
`EventData`/`EventTimeline` model. Adding `.bnb` event records before JSON and
Dart parity would make round-trip expectations ambiguous.

## Object Family Summary

Use flat object-stream records, with ownership implied by adjacency:

```text
animationClip
  boneTimeline*
  slotTimeline*

stateMachine
  stateMachineInput*
  stateMachineLayer+
    stateMachineState*
    stateMachineBlendClip*
    stateMachineTransition*
    stateMachineCondition*
  stateMachineListener*
```

Keyframes are packed inside timeline payload properties instead of emitted as
child objects. This keeps the object count bounded by authored timeline count,
not key count, and keeps the follow-up runtime/CLI implementation small.

The parser keeps a current parent while scanning known objects:

- A `boneTimeline` or `slotTimeline` belongs to the most recent
  `animationClip`.
- A `stateMachineInput`, `stateMachineLayer`, or `stateMachineListener` belongs
  to the most recent `stateMachine`.
- A `stateMachineState` or `stateMachineTransition` belongs to the most recent
  `stateMachineLayer`.
- A `stateMachineBlendClip` belongs to the most recent blend1d
  `stateMachineState`.
- A `stateMachineCondition` belongs to the most recent `stateMachineTransition`.

Encountering a child without the required current parent is a schema violation.
Encountering a new parent closes the previous parent at that level. The exact
canonical order and child-adjacency rules are owned by the follow-up canonical
order bead, but the implementation should not require backpatching or
cross-parent search to attach children.
Skipped unknown objects and skipped unknown properties do not change the current
known parent stack.

## Registry Bands

Registry edits should use:

- M3 type/property range `2000..2999` for animation clips, timelines, curves,
  and keyframe payloads.
- M8 type/property range `7000..7999` for state machines, inputs, layers,
  states, blend clips, transitions, conditions, and listeners.

Shared existing properties such as `name`, `bone`, `slot`, and `attachment` may
be reused only when their existing backing type and semantics match. New
properties with different backing requirements must use new property keys.

## Animation Objects

### `animationClip`

Parent record for one animation.

Properties:

- `name` (`string`, existing property): animation name. Required and non-empty.

Do not store `duration`. Loaders derive duration from the last key time across
owned timelines, matching the local runtime constructors.

### `boneTimeline`

Child record of the current `animationClip`.

Properties:

- `boneIndex` (`varuint`, new M3 property): binary index of the target bone in
  loaded bone order.
- `boneTimelineKind` (`varuint`, new M3 property): project-owned tag for the
  local bone timeline kind.
- `timelineKeys` (`bytes`, new M3 property): packed keyframe payload.

Kinds are grouped by payload shape:

- Scalar: rotate, translateX, translateY, scaleX, scaleY, shearX, shearY.
- Vector: translate, scale, shear.
- Inherit: inherit.

The loader must reject a kind whose `timelineKeys` payload does not match the
kind's shape.

### `slotTimeline`

Child record of the current `animationClip`.

Properties:

- `slotIndex` (`varuint`, new M3 property): binary index of the target slot in
  loaded slot order.
- `slotTimelineKind` (`varuint`, new M3 property): project-owned tag for the
  local slot timeline kind.
- `timelineKeys` (`bytes`, shared M3 property): packed keyframe payload.

Kinds are grouped by payload shape:

- Attachment: attachment.
- Color: rgba, rgb, alpha.
- Two-color: rgba2.
- Sequence: sequence.

Attachment keyframes store attachment references as region indices plus an
explicit none marker, not as strings. A non-none attachment reference must
resolve to a loaded region attachment.

## Keyframe Payloads

All `timelineKeys` payloads start with:

```text
varuint keyCount
```

`keyCount` must be at least one.

Times are stored as f32 seconds and validated as non-negative. Timeline times in
this slice must be strictly increasing.

### Curve Payload

Interpolated key types store a curve after each key value:

```text
varuint curveKind
if curveKind == bezier:
  f32 c1x
  f32 c1y
  f32 c2x
  f32 c2y
```

Curve kind tags are project-owned values assigned by the registry/runtime
implementation slice. The only valid semantic values are linear, stepped, and
Bezier. Bezier `c1x` and `c2x` must be in `0..1`.

The last key may still carry a curve in binary for a uniform decoder. Writers
should emit linear for the last key unless a later canonicalization bead assigns
a different default-omission rule for packed payload internals. Loaders must not
use the last key's curve for interpolation.

### Bone Scalar Keys

```text
repeat keyCount:
  f32 time
  f32 value
  curve
```

### Bone Vector Keys

Vector timelines store independent curves for x and y:

```text
repeat keyCount:
  f32 time
  f32 x
  f32 y
  curve curveX
  curve curveY
```

### Bone Inherit Keys

Inherit timelines are stepped and store no curve:

```text
repeat keyCount:
  f32 time
  bool inheritRotation
  bool inheritScale
  bool inheritReflection
  varuint transformMode
```

The loader must validate that the flags match `transformMode`.

### Slot Attachment Keys

```text
repeat keyCount:
  f32 time
  varuint attachmentTag
```

`attachmentTag == 0` means no attachment. Nonzero tags store
`regionIndex + 1`, so every nonzero value must resolve to a loaded region.

### Slot Color Keys

```text
repeat keyCount:
  f32 time
  f32 r
  f32 g
  f32 b
  f32 a
  curve
```

Each channel must be in `0..1`. `rgb` and `alpha` timelines use the same packed
shape as `rgba`; runtime application decides which channels matter for the
timeline kind.

### Slot Two-Color Keys

```text
repeat keyCount:
  f32 time
  f32 r
  f32 g
  f32 b
  f32 a
  f32 darkR
  f32 darkG
  f32 darkB
  curve
```

Each channel must be in `0..1`.

### Slot Sequence Keys

Sequence timelines are stepped and store no curve:

```text
repeat keyCount:
  f32 time
  varuint index
  f32 delay
  varuint sequenceMode
```

`delay` must be non-negative. Valid sequence modes are once, loop, pingpong,
reverse, and hold.

## State-Machine Objects

### `stateMachine`

Parent record for one state machine.

Properties:

- `name` (`string`, existing property): state-machine name. Required and
  non-empty.

At least one owned layer is required.

### `stateMachineInput`

Child record of the current `stateMachine`.

Properties:

- `name` (`string`, existing property): input name. Required and non-empty.
- `stateMachineInputKind` (`varuint`, new M8 property): bool, number, or
  trigger.
- `inputDefaultBool` (`bool`, new M8 property): present only for bool inputs
  when non-default.
- `inputDefaultNumber` (`f32`, new M8 property): present only for number inputs
  when non-default.

Trigger inputs have no default. Inactive default fields are invalid if present.

### `stateMachineLayer`

Child record of the current `stateMachine`.

Properties:

- `name` (`string`, existing property): layer name. Required and non-empty.
- `initialStateIndex` (`varuint`, new M8 property): index into this layer's
  owned state list. Optional; omitted means state index `0`.

At least one owned state is required.

### `stateMachineState`

Child record of the current `stateMachineLayer`.

Properties:

- `name` (`string`, existing property): state name. Required and non-empty.
- `stateMachineStateKind` (`varuint`, new M8 property): clip or blend1d.
- `stateClipIndex` (`varuint`, new M8 property): animation index for clip
  states.
- `stateLoop` (`bool`, new M8 property): direct clip loop flag, omitted when
  false.
- `stateBlendInputIndex` (`varuint`, new M8 property): state-machine-local
  input index for blend1d states.

Clip states must contain `stateClipIndex` and must not own blend clips. Blend1d
states must contain `stateBlendInputIndex`, must own at least one
`stateMachineBlendClip`, and must not contain direct clip fields. The referenced
blend input must resolve to a number input.

### `stateMachineBlendClip`

Child record of the current blend1d `stateMachineState`.

Properties:

- `blendClipAnimationIndex` (`varuint`, new M8 property): animation index.
- `blendClipValue` (`f32`, new M8 property): blend coordinate.
- `blendClipLoop` (`bool`, new M8 property): loop flag, omitted when false.

Owned blend clips are sorted by `blendClipValue` during normalization. Duplicate
values are invalid.

### `stateMachineTransition`

Child record of the current `stateMachineLayer`.

Properties:

- `transitionFromStateIndex` (`varuint`, new M8 property): layer-local source
  state index.
- `transitionToStateIndex` (`varuint`, new M8 property): layer-local target
  state index.

At least one owned condition is required.

### `stateMachineCondition`

Child record of the current `stateMachineTransition`.

Properties:

- `conditionInputIndex` (`varuint`, new M8 property): state-machine-local input
  index.
- `stateMachineConditionKind` (`varuint`, new M8 property): boolEquals,
  numberEquals, numberGreater, numberGreaterOrEqual, numberLess,
  numberLessOrEqual, or triggerSet.
- `conditionBoolValue` (`bool`, new M8 property): only valid for boolEquals.
- `conditionNumberValue` (`f32`, new M8 property): only valid for numeric
  conditions.

Condition kind must match the referenced input kind. Trigger conditions carry no
value field.

### `stateMachineListener`

Child record of the current `stateMachine`.

Properties:

- `name` (`string`, existing property): listener name. Required and non-empty.
- `stateMachineListenerKind` (`varuint`, new M8 property): stateEnter,
  stateExit, or transition.
- `listenerLayerIndex` (`varuint`, new M8 property): state-machine-local layer
  index.
- `listenerFromStateIndex` (`varuint`, new M8 property): layer-local state
  index, present for stateExit and transition listeners.
- `listenerToStateIndex` (`varuint`, new M8 property): layer-local state index,
  present for stateEnter and transition listeners.

Transition listeners must target an existing transition in the referenced layer.

## Reference Semantics

Binary references are indices, not strings:

- Bone timelines reference loaded bones by bone index.
- Slot timelines reference loaded slots by slot index.
- Attachment keyframes reference loaded regions by region index plus one, with
  zero reserved for no attachment.
- Clip states and blend clips reference loaded animations by animation index.
- Layer initial states, transitions, and listeners reference layer-local state
  indices.
- Conditions and blend inputs reference state-machine-local input indices.
- Listeners reference state-machine-local layer indices.

All indices are checked after byte-level decoding and before runtime
construction. Unknown skipped objects and properties are not semantic targets.
A known reference to skipped unknown binary content is an
`unknownRequiredReference` load error.

## Validation Ownership

The binary loader owns these checks before constructing runtime values:

- Parent/child adjacency is structurally valid.
- Required properties are present after default application.
- Object-kind and timeline/state/condition tags are valid project-owned values.
- Packed key payloads are fully consumed by their decoders.
- Timeline key counts are nonzero.
- Timeline times are non-negative and strictly increasing.
- Numeric fields satisfy the f32/domain rules from the local runtime inventory.
- Duplicate animation, state-machine, layer, state, input, and listener names
  are rejected in their owning scopes.
- Animation and state-machine references resolve to the correct known target
  family.
- State-machine type constraints are enforced before runtime construction.

Runtime code may normalize ordering, such as blend clips by value, but it should
not receive partially validated object graphs.

## Follow-Up Work

This decision intentionally leaves these items to dependent Beads:

- Concrete registry type/property key allocation.
- Canonical object order, child adjacency finalization, string traversal, and
  default-omission rules.
- Nim loaded-asset shape for preserving animations and state machines.
- Runtime/CLI implementation and conformance fixtures.
- Event timeline JSON/model/runtime parity and eventual `.bnb` event records.
