# Binary ToC Skip Semantics

This contract resolves the `.bnb` table-of-contents skip rule for composite
values, especially arrays of structs such as weighted vertices and keyframes.
It supersedes the open question in the original spec section 6.2 before M6
binary work begins.

## Decision

Every property value in the object stream is encoded as a length-prefixed
payload:

```text
varuint propertyKey
varuint byteLength
byte[byteLength] payload
```

Property key `0` remains the object-property-list terminator and is not followed
by `byteLength`.

This chooses byte-count skipping over richer ToC descriptors. An old reader can
skip any unknown property by reading `byteLength` and advancing exactly that
many bytes, without understanding whether the payload is a scalar, primitive
array, struct, or array of structs.

## Revised ToC Role

The table of contents still lists every property key used by the file, but its
backing type is now a payload decoder hint for known properties, not the only
mechanism for skipping unknown properties.

ToC entry:

```text
varuint propertyKey
u8 backingTypeCode
```

`backingTypeCode` is the stable numeric code assigned to the property's
registered backing type in `registry/wire.yml`.

The ToC is still required because:

- It lets readers reject malformed files whose property payload does not match
  the registered backing type for known properties.
- It lets tooling inspect a file's property-type surface without scanning every
  object.
- It preserves the append-only registry discipline that each property key has
  exactly one backing type for the lifetime of the format.

Skipping unknown content depends on `byteLength`, not on reconstructing payload
size from `backingType`.

## Object Stream

Each object is encoded as:

```text
varuint typeKey
if typeKey == 0:
  end object stream
repeat:
  varuint propertyKey
  if propertyKey == 0:
    break
  varuint byteLength
  byte[byteLength] payload
```

Reading rules:

- Type key `0` terminates the object stream and is not followed by properties.
- Unknown `typeKey`: read property records until property key `0`, skipping
  every payload by `byteLength`, then discard the object.
- Known `typeKey`, unknown `propertyKey`: skip the payload by `byteLength` and
  continue.
- Known property: decode the payload using the property's registered backing
  type and require the decoder to consume exactly `byteLength` bytes.
- If `byteLength` exceeds the remaining file bytes, reject the file as
  malformed.
- If a known-property decoder consumes fewer or more bytes than `byteLength`,
  reject the file as malformed.
- When reading any nonzero property key, reject the file as malformed if that
  key is absent from the ToC before reading or using its payload bytes.
- If a known property appears in the ToC with a backing type code different from
  the registry entry known to the reader, reject the file as malformed for
  same-major data. Changing a shipped property backing type requires a major
  version break or a new property key.
- Unknown backing type codes are allowed only for property keys unknown to the
  reader. This preserves forward-compatible skipping for future composite
  backing types. A known property with an unknown backing type code is a backing
  type mismatch and must be rejected.

## Payload Encoding

Payload bytes contain the value encoded according to the property's registered
backing type. The payload does not repeat the property key or byte length.

Scalar payloads:

- `varuint`: unsigned LEB128 value.
- `varint`: zig-zag signed LEB128 value.
- `f32`: 4 little-endian bytes.
- `bool`: one byte, `0` or `1`.
- `string`: varuint string-table index when string interning is enabled.
- `color`: 4 bytes in canonical RGBA order.
- `bytes`: raw bytes; the surrounding `byteLength` is the byte count.

Composite payloads are now legal because the outer `byteLength` makes them
skippable. Composite backing types must define their internal payload layout in
the registry before use.

## Canonical Emission

Writers must compute `byteLength` from the encoded payload bytes. They must not
estimate size from decoded values.

Canonical writers emit each property as:

1. Encode payload into a temporary byte buffer.
2. Emit `propertyKey`.
3. Emit payload byte count as `varuint`.
4. Emit payload bytes exactly as buffered.

This rule applies to scalars and composites. It is acceptable for optimized
writers to avoid heap allocation if they produce identical bytes and identical
length validation.

## Registry Impact

`registry/wire.yml` remains the source of property backing types. After this
contract:

- Primitive backing types keep their scalar payload meaning.
- Composite backing types may be added because skip length is carried by every
  property record.
- Backing type changes for existing property keys remain forbidden.
- Property key `0` remains reserved and has no payload.

## Forward-Compatibility Requirements

M6 forward-compat tests must include:

- Unknown property with scalar payload skipped by `byteLength`.
- Unknown property with array-of-struct payload skipped by `byteLength`.
- Unknown object containing multiple unknown properties skipped until property
  key `0`.
- Object stream stops at type key `0` without reading a property list.
- Known property whose decoder consumes fewer bytes than `byteLength`, rejected
  as malformed.
- Known property whose decoder would read past `byteLength`, rejected as
  malformed.
- Property key missing from the ToC, rejected as malformed.
- ToC backing-type mismatch for a known property, rejected as malformed.
- Unknown ToC backing-type code for an unknown property, still skipped by
  `byteLength`.
- Truncated `byteLength` varuint and payload length beyond remaining bytes,
  rejected as malformed.

These tests are in addition to later binary canonicalization tests for ToC
ordering and byte-stable re-emission.
