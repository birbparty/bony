# Binary Canonicalization

This contract defines canonical `.bnb` byte emission for round-trip tools and
the M6 `bnb->json->bnb` byte-stability gate. It is the binary sibling of
`docs/json-canonicalization.md` and uses the property-record skip rule from
`docs/binary-toc-skip-semantics.md`.

Canonicalization is an emission rule for a loaded `SkeletonData` value. It does
not change runtime semantics.

## Scope

This document owns:

- File-section order.
- Minimal integer and scalar encodings.
- Table-of-contents ordering.
- String table construction.
- Object stream ordering.
- Property ordering and default omission.
- Interaction with optional `header.hash` and `header.bounds`.

It does not define binary validation for malformed inputs; that belongs to the
load-validation contract. It also does not define registry key allocation.
`header.hash` and `header.bounds` policy is defined in
`docs/header-hash-bounds.md`.

## Stability Target

Canonical byte stability is defined as:

```text
canonicalBnb(load(canonicalBnb(load(input)))) == canonicalBnb(load(input))
```

A non-canonical `.bnb` input may re-emit to different bytes on the first pass.
Once emitted canonically, a `bnb->json->bnb` cycle in the same runtime must
produce identical bytes.

Unknown objects and unknown properties are excluded from the core byte-stability
fixture set until an extension-preservation bucket is designed. Forward-compatible
skipping of unknown content is covered by `docs/binary-toc-skip-semantics.md`
and its M6 tests.

## File Section Order

Canonical `.bnb` files emit sections in this order:

1. Fingerprint: ASCII bytes `BONY`.
2. Version: `varuint` packed as `(major << 16) | minor`.
3. Flags: `varuint`.
4. Table of contents.
5. String table, if the string-interning flag is set.
6. Object stream.
7. Object-stream EOF marker: `varuint 0`.
8. Embedded atlas payload, if the embedded-atlas flag is set.

The string-interning flag is on by default for canonical emission. Atlas
embedding is controlled by loaded data; canonicalization does not force external
assets to become embedded.

## Scalar Encoding

All integers use the shortest valid LEB128 representation.

- `varuint`: unsigned LEB128, no redundant continuation groups.
- `varint`: zig-zag encode signed integer, then shortest `varuint`.
- `f32`: IEEE-754 binary32, little-endian. NaN and infinity are invalid in
  canonical data.
- `bool`: one byte, `0` for false and `1` for true. Other byte values are
  invalid on load and never emitted.
- `string`: `varuint` index into the canonical string table.
- `color`: four bytes in RGBA order.
- `bytes`: raw payload bytes. The surrounding property `byteLength` is the byte
  count.

Writers must not emit alternate encodings for the same value.

## Table Of Contents

The ToC contains every property key emitted at least once in the object stream.
Properties omitted because they equal defaults and have `omitWhenDefault: true`
in `spec/defaults.yml` are not included.

Canonical ToC order is ascending numeric `propertyKey`.

The ToC section is:

```text
varuint propertyCount
repeat propertyCount times:
  varuint propertyKey
  u8 backingTypeCode
```

There is no ToC terminator. `propertyCount` is the exact number of entries.

Each ToC entry is:

```text
varuint propertyKey
u8 backingTypeCode
```

`backingTypeCode` is the stable `code` for the property's backing type in
`registry/wire.yml`. A canonical writer must reject before emission if two
emitted uses of the same property key require different backing type codes.

## String Table

Canonical string interning uses first-seen order while walking the canonical
object stream and canonical property order.

Rules:

- Start with an empty string table.
- Visit every string encoded anywhere inside emitted payloads, including strings
  nested inside future composite payloads.
- Traversal order is canonical object order, then canonical property order, then
  the field order defined by the backing type's registry layout. Array-like
  composite payloads are traversed by ascending element index.
- Append each string the first time it is seen.
- Later occurrences reuse the first index.
- String comparison for interning is exact Unicode scalar sequence equality; no
  normalization is performed.
- String table entries are emitted as `varuint byteLength` followed by UTF-8
  bytes.
- The table itself is emitted as `varuint count` followed by entries.
- Emit UTF-8 without a byte-order mark. Writers must reject strings that are not
  valid Unicode scalar sequences, including lone surrogates. No normalization is
  performed before UTF-8 encoding.

Only emitted payloads contribute strings. Strings belonging to default-valued
omitted properties do not appear in the table.

## Object Stream Order

Canonical object order follows the conceptual runtime dependency order:

```text
skeleton
bones
slots
attachments
ik
transforms
paths
physics
skins
events
parameters
deformers
animations
stateMachines
atlasMetadata
```

Within each group:

- Bones are parent-first in loaded skeleton array order.
- Slots are setup draw order.
- Attachments are grouped by skin order, then slot order, then attachment name
  sorted by canonical UTF-8 bytes. Attachment ordering is independent of the
  runtime's in-memory map or array representation.
- IK, transform, path, and physics arrays keep loaded array order. Runtime
  evaluation order is separately defined by `docs/constraint-total-order.md`.
- Skins, events, parameters, deformers, animations, and state machines keep
  loaded array order unless a later contract assigns a more specific order.
- Animation records are emitted before state-machine records. This is required
  because state-machine clip and blend-clip references index the loaded
  animation sequence.
- Timeline child objects are emitted immediately after their owning animation
  object. Within one animation, emit all `boneTimeline` records in loaded
  `boneTimelines` order, then all `slotTimeline` records in loaded
  `slotTimelines` order. Keyframes for the current animation/state-machine
  slice are packed inside `timelineKeys` bytes properties, so no separate
  keyframe child objects are emitted in this slice.
- State-machine child records are emitted immediately after their owning parent
  record, recursively:
  1. `stateMachine`
  2. all owned `stateMachineInput` records in loaded input order
  3. each `stateMachineLayer` in loaded layer order
  4. each layer's `stateMachineState` records in loaded state order, with each
     blend1d state's `stateMachineBlendClip` records immediately following the
     owning state in normalized blend-value order
  5. each layer's `stateMachineTransition` records in loaded transition order,
     with each transition's `stateMachineCondition` records immediately
     following the owning transition in loaded condition order
  6. all owned `stateMachineListener` records in loaded listener order

Unknown objects are excluded from canonical emission until extension
preservation is designed. A canonical writer that cannot preserve unknown
objects without changing known child adjacency must reject instead of emitting a
partial canonical file.

If a future registry entry introduces a map-like collection, its canonical
binary order must be defined in the bead that introduces it.

Raw embedded atlas bytes are not object-stream entries. Atlas metadata objects,
if present, use the `atlasMetadata` group above. The raw embedded atlas payload
is emitted only in the post-EOF atlas section defined by File Section Order.

## Animation Packed Payload Traversal

Animation `timelineKeys` packed `bytes` properties participate in canonical
output even though their internal fields are not object-stream properties.

Rules:

- For `timelineKeys`, writers visit keys by ascending stored key index and then
  visit fields in the order shown in
  [binary-animation-state-machine-object-families.md](binary-animation-state-machine-object-families.md).
- Curve payload fields are visited as `curveKind`, then Bezier control points
  `c1x`, `c1y`, `c2x`, `c2y` only when `curveKind` is Bezier.
- The current animation and state-machine packed payloads use indices and
  numeric tags, not strings. If a future animation/state-machine packed payload
  includes strings, those strings must be interned at the point they are visited
  by that payload's explicitly declared packed field order.
- Packed payload bytes compare by exact bytes for default omission and canonical
  equality. The default table may omit a `bytes` property only when the loaded
  semantic payload equals the default payload and the default entry sets
  `omitWhenDefault: true`.

Packed `bytes` properties outside this animation/state-machine slice keep the
traversal rules owned by their original contracts. This section does not change
existing packed payloads such as deformer `blendAxes`.

## Property Emission

For each object:

1. Determine all properties whose loaded values differ from the default table,
   plus default-valued properties whose default entry has `omitWhenDefault:
   false`.
2. Sort those properties by ascending numeric `propertyKey`.
3. For each property, encode its payload bytes.
4. Emit `propertyKey`, `byteLength`, and payload bytes.
5. Emit property terminator `varuint 0`.

`byteLength` is the exact count of payload bytes, encoded as shortest
`varuint`. It is present for every nonzero property key and absent for the
terminator.

Duplicate property keys within one object are invalid and are never emitted.

## Defaults

Default omission is based on the loaded semantic value after JSON/default-table
application and binary decoding.

Rules:

- Omit a property equal to its default value only when the default entry has
  `omitWhenDefault: true`.
- Emit every property not equal to its default value, even if the value is
  falsey, empty, or zero-like.
- Equality for f32-backed fields compares the stored f32 value, not the source
  decimal spelling.
- Equality for arrays compares length and elements in order.
- Equality for strings compares exact scalar sequence.

The default-table source owns default values. This contract owns only the
binary omission rule.

## Header Flags

Canonical flags are computed from emitted sections:

- `bit0`: embedded atlas payload is present.
- `bit1`: string table is present. Canonical emission sets this bit.

All unassigned flag bits are `0`. A later feature bead that adds a flag must
define its canonical emission rule in the same change.

## Conformance Checks

The M6 `bnb->json->bnb` byte-stability gate must include:

- Non-canonical ToC order re-emits in ascending property-key order.
- ToC section starts with exact `propertyCount` and has no terminator.
- Writers emit shortest LEB128 encodings. Non-minimal LEB128 input is malformed
  and belongs to the load-validation rejection gate rather than the
  `bnb->json->bnb` byte-stability gate.
- Repeated strings intern to first-seen indices in canonical object/property
  order.
- Strings nested inside composite payloads intern using the composite layout's
  declared field and element order.
- Invalid Unicode scalar sequences are rejected before binary emission.
- Default-valued properties omitted from objects and absent from the ToC.
- Falsey non-default values still emitted.
- Object stream order follows the canonical group order.
- Animation records emit before state-machine records.
- Timeline records immediately follow their owning animation, with
  `boneTimeline` records before `slotTimeline` records and each family in loaded
  order.
- State-machine inputs, layers, states, blend clips, transitions, conditions,
  and listeners follow the recursive child-adjacency order defined above.
- Packed `timelineKeys` bytes are emitted and traversed in contract field order,
  and any future packed strings intern at their packed traversal point.
- Attachment object order is independent of source/runtime map representation.
- Raw embedded atlas bytes appear only after the object-stream EOF marker.
- Property order within an object is ascending property key.
- `byteLength` matches exact payload byte count for scalar and composite
  payloads.
- A canonical `.bnb` survives `bnb->json->bnb` with byte-identical output.
