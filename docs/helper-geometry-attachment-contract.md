# Helper Geometry Attachment Contract

Status: binding. Owner bead: `bony-wb1d`.

This contract defines two project-owned, non-rendered attachment records:
`pointAttachment` and `boundingBoxAttachment`. They are loadable `.bony` JSON
and `.bnb` binary records, may be referenced by `slot.attachment`, and are
available to host/runtime helper-geometry queries. They do not emit draw
batches.

## Model

### Point Attachment

A `pointAttachment` is a named locator in the owning slot bone's local space.
It has:

- `name`: non-empty string, unique within point attachments and unambiguous in
  the slot attachment namespace.
- `x`: required finite f32 skeleton-space local x coordinate.
- `y`: required finite f32 skeleton-space local y coordinate.
- `rotation`: required finite f32 local rotation in degrees.

Point attachments emit no `DrawBatch`.

### Bounding-Box Attachment

A `boundingBoxAttachment` is a named convex polygon in the owning slot bone's
local space. It has:

- `name`: non-empty string, unique within bounding-box attachments and
  unambiguous in the slot attachment namespace.
- `vertices`: required flat coordinate list `[x0, y0, x1, y1, ...]`.

The `vertices` list must contain at least three points, have even length, carry
only finite f32 coordinates, have non-zero signed area, and maintain one
consistent convex turn direction. Collinear edges are allowed when the polygon
still has non-zero area and no turn reverses direction beyond the polygon
epsilon used by the loaders.

Bounding-box attachments emit no `DrawBatch`.

## Slot Attachment References

The existing `slot.attachment` field may name a region, clipping, mesh, point,
or bounding-box attachment. Attachment names must be unambiguous across all
slot-visible concrete attachment classes so resolution is deterministic.

When first-class skins are present, skin entry `target` values may also resolve
to point or bounding-box attachments. A helper attachment selected by a slot or
skin remains invisible to `buildDrawBatches`.

## Canonical JSON

Point attachments live in the top-level `pointAttachments` array:

```json
{
  "pointAttachments": [
    { "name": "muzzle", "x": 12, "y": 3, "rotation": 45 }
  ]
}
```

Bounding-box attachments live in the top-level `boundingBoxAttachments` array:

```json
{
  "boundingBoxAttachments": [
    { "name": "button_hit", "vertices": [-10, -5, 10, -5, 10, 5, -10, 5] }
  ]
}
```

Canonical JSON emits helper attachment arrays only when non-empty.

## BNB Object Shape

`pointAttachment` uses type key `1002` and properties:

- `name` (`1`, string), required.
- `x` (`1000`, f32), required.
- `y` (`1001`, f32), required.
- `rotation` (`1002`, f32), required.

`boundingBoxAttachment` uses type key `1003` and properties:

- `name` (`1`, string), required.
- `vertices` (`3000`, bytes), required.

The `vertices` property intentionally reuses the compatible packed f32-pair
polygon payload introduced for clipping attachments.

## Packed Vertices Byte Layout BNB

The `vertices` bytes payload is:

```text
varuint pointCount
repeat pointCount:
  f32 x
  f32 y
```

The decoded semantic list is flat `[x0, y0, x1, y1, ...]`. Loaders validate the
same polygon invariants after decoding JSON or BNB.

## Helper Query Semantics

These deterministic geometry rules are public project-owned math used by
runtime helper-geometry queries and pointer helper listener dispatch.

A point attachment's world pose is the owning slot bone world transform composed
with the point's local translation and rotation. Translation uses the affine
point transform. Rotation adds the local point rotation, in degrees, to the
owning bone's world x-axis rotation.

A bounding-box attachment's world polygon is each local vertex transformed by
the owning slot bone world transform.

A point-in-bounding-box test uses the standard crossing-number even-odd rule
over the transformed polygon. Boundary points are inside when their distance to
any polygon edge is within the project tolerance from
`docs/float-math-contract.md`.

## Non-Goals

Pointer listener records over these helpers are defined separately in
`docs/pointer-helper-listener-contract.md`.

This contract does not define pointer input scripts, runtime state-machine
dispatch, importer conversion, visible debug rendering, vector paths, nested
rigs, skin-owned helper attachments, linked meshes, or `skinRequired`.
