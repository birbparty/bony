# Skin Attachment-Set Contract

Status: **binding**. Owner bead: `bony-4set` (M20 skin attachment-set milestone,
prompt 31).

This contract defines the `bony`-owned **skin attachment set** model: a named set
of slot-visible attachment variants. Skins do not define geometry. Region,
clipping, mesh, helper, and nested rig attachment records remain the concrete
attachment definitions; skin entries bind those definitions into the attachment
names that slots and attachment timelines can select.

This slice is **format and contract only**. It does not add active-skin runtime
lookup, importer behavior, conformance rigs, Dart parity, linked meshes,
`inheritDeform`, `skinRequired`, or nested rig playback.

## Model

A skeleton owns a top-level `skins` array. A first-class skin asset MUST contain
at least one skin named exactly `"default"`:

```json
{
  "skins": [
    {
      "name": "default",
      "entries": [
        { "slot": "body", "attachment": "body", "target": "body_mesh" }
      ]
    },
    {
      "name": "armor",
      "entries": [
        { "slot": "body", "attachment": "body", "target": "body_armor_mesh" }
      ]
    }
  ]
}
```

Each skin has:

- `name` (string, required) - unique skin identity. `"default"` is reserved for
  the required fallback skin and is otherwise an ordinary skin record.
- `entries` (array, optional, default `[]`) - bindings from a slot-visible
  attachment name to a concrete attachment definition.

Each entry has:

- `slot` (string, required) - loaded slot name.
- `attachment` (string, required) - the slot-visible attachment name selected by
  setup slots and slot attachment timelines.
- `target` (string, required) - the concrete attachment definition name. It MUST
  resolve to exactly one loaded slot-visible concrete attachment definition:
  region, clipping, mesh, point, bounding-box, or nested rig attachment.

The entry key is `(skin.name, slot, attachment)`. Multiple skins may use the same
`slot` and `attachment` key to point at different targets.

## Lookup

Given an active skin, slot name, and slot-visible attachment name:

1. Look for an entry in the active skin whose `(slot, attachment)` matches.
2. If no active-skin entry exists, look for the same `(slot, attachment)` in the
   `"default"` skin.
3. If neither entry exists, the attachment is unresolved.
4. If an entry resolves, draw/runtime code uses the entry's `target` attachment
   definition.

Until the runtime slice adds active-skin selection, setup slots keep their
current behavior: `slot.attachment` stores the setup active attachment name.
First-class skin lookup is a future runtime step layered on top of that setup
name.

An empty setup `slot.attachment` still means no visible attachment for that slot.
An empty attachment name is never a skin entry key.

## Validation

A conforming loader rejects a first-class skin asset unless all rules hold:

1. `skins` is present and contains exactly one skin named `"default"`.
2. Every skin name is non-empty and unique.
3. Every entry's `slot`, `attachment`, and `target` are non-empty.
4. Every entry's `slot` names a loaded slot.
5. Within one skin, `(slot, attachment)` is unique.
6. Every entry's `target` resolves to exactly one loaded slot-visible concrete
   attachment definition: region, clipping attachment, mesh attachment, point
   attachment, bounding-box attachment, or nested rig attachment.
7. A target name that is unknown or ambiguous across concrete attachment classes
   is invalid.
8. A setup slot with a non-empty `slot.attachment` must resolve through the
   active skin and `"default"` fallback once runtime active-skin lookup is
   implemented.

The `"default"` skin may have zero entries only for skeletons whose setup slots
do not name attachments and whose animations do not select attachments.

## Deform Timeline Resolution

Deform timelines keep their `(skin, slot, attachment)` identity. The `skin` field
resolves against the loaded `skins` array:

- `"default"` resolves to the required fallback skin.
- A non-default `skin` value is valid only when a skin with that name is declared.
- The `(skin, slot, attachment)` tuple must resolve via the skin entry lookup
  rules to a concrete attachment definition.
- The resolved `target` must be a mesh attachment, and `vertexCount` must equal
  that mesh's vertex count.

If a non-default deform timeline has no entry in its named skin, it falls back to
the `"default"` skin exactly like runtime attachment lookup. The timeline still
belongs to the named skin for identity and conflict resolution.

## Canonical JSON

Canonical `.bony` JSON exposes skins as:

```json
{
  "skins": [
    {
      "name": "default",
      "entries": [
        { "slot": "slotName", "attachment": "visibleName", "target": "meshName" }
      ]
    }
  ]
}
```

Rules:

- Emit `skins` after `physicsConstraints` and before `parameters`,
  `deformers`, `animations`, and `stateMachines`.
- Preserve loaded skin order, with `"default"` first in canonical output.
- Within a skin, sort entries by slot order, then by `attachment` canonical UTF-8
  byte order.
- Omit `entries` when it is empty.

## `.bnb` Object Shape

The binary stream uses two project-owned M4 object records:

- `skin` (type key `3003`) - parent record with required `name`.
- `skinEntry` (type key `3004`) - child record owned by the most recent `skin`
  record, with required `slot`, `skinAttachment`, and `skinTarget` properties.

`skinEntry.skinAttachment` is the canonical-JSON `attachment` field.
`skinEntry.skinTarget` is the canonical-JSON `target` field.

Canonical object order:

1. Emit `skin` records in loaded skin order, with `"default"` first.
2. Emit each skin's `skinEntry` children immediately after the owning `skin`.
3. Within one skin, emit entries by slot order, then by `skinAttachment`
   canonical UTF-8 byte order.

The concrete attachment definitions referenced by `skinTarget` remain in the
earlier `attachments` object-stream group; skin records are only bindings.

## Non-Goals

This slice does not define or implement:

- Runtime active-skin selection or draw-batch lookup.
- Linked meshes, parent meshes, `inheritDeform`, or mesh inheritance.
- `skinRequired` constraints or inactive constraint filtering.
- Nested rig runtime playback, nested asset loading, nested armatures, or
  skin-owned bones.
- Importer mapping behavior for any third-party format.
