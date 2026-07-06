# Nested Rig Attachment Contract

Status: **binding**. Owner bead: `bony-5b5w` (M4 attachment-family format slice).

This contract defines the project-owned **nested rig attachment**: a
slot-visible attachment record that names another `SkeletonData` asset or
host-resolved skeleton id. This slice freezes the serialized surface and
load-time validation only. It does not load nested assets or play nested
animations.

## Model

A nested rig attachment is a slot-visible concrete attachment class authored
alongside region, clipping, mesh, point, and bounding-box attachments:

- A skeleton-level array `nestedRigAttachments` holds nested rig records.
- `slot.attachment` may name a nested rig attachment by its `name`.
- When first-class skins are present, `skinEntry.target` may resolve to a nested
  rig attachment exactly like other concrete attachment definitions.
- `skin` and `animation` are defaults for the nested skeleton. Loaders store
  them as strings and do not resolve them against the current host
  `SkeletonData`.

At runtime, a later slice will define how the host slot's world transform
becomes the nested root parent transform. Until then, nested rig attachments
emit no `DrawBatch` and have no playback behavior.

## Canonical JSON

Nested rig attachments live in the top-level `nestedRigAttachments` array:

```json
{
  "nestedRigAttachments": [
    {
      "name": "nested_face",
      "skeleton": "faceRig",
      "skin": "neutral",
      "animation": "blink"
    }
  ]
}
```

Fields:

- `name` (string, required) - slot-visible attachment definition name.
- `skeleton` (string, required) - external or host-resolved nested skeleton
  reference id.
- `skin` (string, optional, default `""`, omitted when default) - default skin
  name for the nested skeleton.
- `animation` (string, optional, default `""`, omitted when default) - default
  animation name for the nested skeleton.

Canonical JSON emits `nestedRigAttachments` only when non-empty. When emitted,
it follows `boundingBoxAttachments` and precedes constraints/path attachments in
the current serializer's attachment-family order.

## `.bnb` Object Shape

The binary stream uses one M4 object record:

- `nestedRigAttachment` (type key `3005`) with properties:
  - `name` (`1`, string), required.
  - `nestedSkeleton` (`3012`, string), required.
  - `nestedSkin` (`3013`, string), optional default `""`.
  - `nestedAnimation` (`3014`, string), optional default `""`.

The `nestedSkeleton`/`nestedSkin`/`nestedAnimation` property names are binary
registry identifiers. Canonical JSON intentionally exposes the shorter field
names `skeleton`/`skin`/`animation`.

Canonical `.bnb` object order emits nested rig attachment records in loaded
order with the other attachment definition objects, after mesh attachments and
before skins/constraints in the current semantic encoder. Skin records remain
bindings; they do not own nested rig records.

## Load Validation

A conforming loader rejects a nested rig attachment asset unless all rules hold:

1. `name` is a non-empty string.
2. `skeleton` is a non-empty string.
3. Nested rig attachment names are unique within `nestedRigAttachments`.
4. Nested rig attachment names are unambiguous across all slot-visible concrete
   attachment classes: region, clipping, mesh, point, bounding-box, and nested
   rig attachments.
5. With no first-class skins, any non-empty `slot.attachment` may resolve to a
   nested rig attachment.
6. With first-class skins, `skinEntry.target` may resolve to a nested rig
   attachment and must still resolve to exactly one concrete attachment class.
7. `skin` and `animation` are stored as nested-skeleton defaults but are not
   resolved against the current host `SkeletonData`.

## Non-Goals

This slice does not define or implement:

- Nested skeleton asset loading.
- Cross-asset recursion or cycle detection.
- Nested draw-batch composition.
- Nested state-machine playback or animation driving.
- Runtime active nested skin/animation validation.
- Importer mapping for DragonBones, Spine, Rive, Live2D, or Lottie.
- Conformance goldens for nested playback.
- Vector paths, text, layout, data binding, or renderer features.
