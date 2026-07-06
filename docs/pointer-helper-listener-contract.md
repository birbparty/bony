# Pointer Helper Listener Contract

Status: binding. Owner bead: `bony-g65e`.

This contract defines project-owned state-machine pointer listener records that
target non-rendered helper attachments. It covers serialized JSON and `.bnb`
shape, loader validation, helper hit semantics, and runtime dispatch order.

## Listener Kinds

State-machine listeners now have eight project-owned kinds:

- Lifecycle kinds: `stateEnter`, `stateExit`, and `transition`.
- Pointer kinds: `pointerDown`, `pointerUp`, `pointerEnter`, `pointerExit`, and
  `pointerMove`.

Lifecycle listener behavior is unchanged. Lifecycle listeners use `layer`,
`fromState`, and/or `toState` exactly as defined by the M8 state-machine
contracts.

Pointer listeners mutate or fire one input in their owning state machine when
the runtime pointer dispatcher reports a hit on their target helper.

## JSON Shape

Pointer listeners live in the existing state-machine `listeners` array:

```json
{
  "name": "button_down",
  "kind": "pointerDown",
  "slot": "button_slot",
  "targetKind": "boundingBox",
  "target": "button_hit",
  "input": "pressed",
  "value": true
}
```

Pointer listener fields are:

- `name`: non-empty listener name, unique in the owning state machine.
- `kind`: one of the five pointer kinds.
- `slot`: target slot name. It must resolve to `SkeletonData.slots`.
- `targetKind`: `point` or `boundingBox`.
- `target`: concrete helper attachment name. `point` targets resolve to
  `SkeletonData.pointAttachments`; `boundingBox` targets resolve to
  `SkeletonData.boundingBoxAttachments`.
- `hitRadius`: required finite non-negative f32 for `point` targets; invalid
  for `boundingBox` targets.
- `input`: state-machine input name in the owning state machine.
- `value`: required bool for bool inputs, required finite f32 number for number
  inputs, and invalid for trigger inputs.

Pointer listeners must not carry lifecycle fields: `layer`, `fromState`, or
`toState`.

## Target Resolution

File loaders validate both the helper definition and that the target slot can
expose the helper:

1. `slot` resolves to a loaded slot.
2. `target` resolves to exactly the helper class named by `targetKind`.
3. The target slot can resolve to the helper either because setup
   `slot.attachment == target`, or because at least one declared skin entry for
   that slot has `target == listener.target`.

Runtime dispatch must use the active-skin lookup rules from
`docs/skin-attachment-set-contract.md`: resolve the slot-visible attachment
through the active skin and then `"default"` fallback, then compare the concrete
target against the listener's `target`.

## Hit Semantics

Point listener hit testing uses the point helper's world position and the
listener's explicit `hitRadius`. A pointer is inside when its world-space
distance to the point is less than or equal to `hitRadius`.

Bounding-box listener hit testing uses the bounding-box helper polygon rules
from `docs/helper-geometry-attachment-contract.md`, including the documented
boundary behavior.

## BNB Shape

Pointer listeners reuse the existing `stateMachineListener` object type
(`7007`). Existing lifecycle properties remain valid for lifecycle kinds.
Pointer kinds use these M8 properties:

- `stateMachineListenerKind` (`7060`, varuint): `0..2` are lifecycle kinds,
  `3..7` are `pointerDown`, `pointerUp`, `pointerEnter`, `pointerExit`, and
  `pointerMove`.
- `listenerSlotIndex` (`7064`, varuint): skeleton slot index.
- `listenerHelperKind` (`7065`, varuint): `0` point, `1` boundingBox.
- `listenerHelperTarget` (`7066`, string): concrete helper attachment name.
- `listenerInputIndex` (`7067`, varuint): owning-machine input index.
- `listenerBoolValue` (`7068`, bool): present only for bool-input pointer
  listeners.
- `listenerNumberValue` (`7069`, f32): present only for number-input pointer
  listeners.
- `listenerHitRadius` (`7070`, f32): present only for point-target pointer
  listeners.

The generated schema records defaults for kind-specific fields only so canonical
writers may omit zero-valued indices or values, but loaders validate raw
presence from the record according to listener kind, input kind, and target
kind.

## Event Channel And Dispatch Order

Runtime dispatch visits pointer listeners in the order they appear in the owning
state machine's normalized `listeners` array, after resolving the active skin for
the current slot attachment.

Matching pointer listeners append state-machine listener events to the existing
`events` channel. Pointer events carry the listener name/kind, slot, target kind
and target name, mutated input/value payload, and pointer world coordinates.

When a host dispatches pointer listeners before advancing the state machine for
the same sample and preserves the event queue through that update, pointer events
remain before any lifecycle events produced by transition evaluation. Lifecycle
event order remains `stateExit`, `transition`, then `stateEnter`.

## Non-Goals

This contract does not define pointer input-script file shape, renderer-visible
helper batches, conformance golden layout, Rive or Spine importer behavior, or
host UI event plumbing.
