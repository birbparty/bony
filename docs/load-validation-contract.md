# Load-Time Validation Contract

This contract defines the validation pass shared by `.bony` JSON loaders,
`.bnb` binary loaders, and the M6 fuzz/forward-compatibility gates. It
reconciles two requirements:

- Unknown-but-well-formed same-major binary content must be skipped when the
  format permits skipping.
- Malformed input must be rejected hard with typed errors/exceptions, bounded
  work, and no crashes or hangs.

## Scope

This document owns:

- Required loader phases.
- Byte-level binary validation.
- JSON structural validation.
- Cross-reference and graph validation.
- Unknown object/property handling.
- Runtime-specific acceptance bars for Nim and Dart.

It does not define canonical emission. Canonical `.bony` output is covered by
`docs/json-canonicalization.md`; canonical `.bnb` output is covered by
`docs/binary-canonicalization.md`.

## Error Model

Loaders must fail closed. If validation cannot prove the input is well-formed,
the file is invalid.

Runtime acceptance bars:

- Nim: return or raise a typed load error. No panic, segmentation fault,
  out-of-bounds read/write, unbounded loop, or process abort.
- Dart: throw a typed load exception. No uncaught VM range error from parser
  internals, no hang, and no unbounded allocation.

Both runtimes must include enough error kind/context for tests to assert the
category, but exact human-readable message text is not a conformance surface.

Minimum error categories:

- `badMagic`
- `unsupportedVersion`
- `truncatedInput`
- `malformedVarint`
- `invalidBackingType`
- `lengthMismatch`
- `duplicateKey`
- `unknownRequiredReference`
- `cycleDetected`
- `orderingViolation`
- `schemaViolation`
- `numericOutOfRange`

## Loader Phases

Loaders validate in these phases:

1. Decode bytes/text into a bounded intermediate representation.
2. Apply defaults for known fields.
3. Resolve known references.
4. Validate graph shape, ordering, and semantic invariants.
5. Build immutable `SkeletonData`.

Runtime systems must not receive partially validated data. A loader may combine
phases internally, but it must preserve the same observable accept/reject
behavior.

## Binary Byte-Level Validation

Binary loaders validate `.bnb` framing before building semantic objects.

Required checks:

- Fingerprint is exactly ASCII `BONY`.
- Version `major` is supported. Unsupported future major versions are rejected.
  Unsupported future minor versions with the same major may be loaded only by
  using forward-compatible skip rules.
- Header flags use only assigned bits. Unknown flag bits are rejected unless a
  later same-major contract explicitly makes them skippable.
- Every `varuint` and `varint` is finite, minimally bounded by implementation
  limits, and terminates before the configured maximum byte width. Truncated or
  overlong encodings are malformed.
- ToC `propertyCount` does not exceed remaining bytes or implementation entry
  limits.
- ToC property keys are nonzero, unique, and sorted only if canonical mode
  requires sorted input. Non-canonical load mode may accept unsorted ToC entries,
  but duplicate keys are always malformed.
- Known ToC property keys must use the backing type code registered for that
  key.
- Unknown backing type codes are allowed only for unknown property keys.
- Every nonzero property key encountered in the object stream must be present
  in the ToC before its payload is decoded or skipped.
- Every nonzero property record has a `byteLength`, and `byteLength` must fit
  within the remaining file bytes.
- Known-property decoders must consume exactly `byteLength` bytes.
- Unknown properties are skipped by `byteLength`.
- Unknown objects are skipped by scanning property records until property key
  `0`; each contained property must still satisfy ToC and length validation.
- Type key `0` terminates the object stream and is not followed by a property
  list.
- Data after the object-stream terminator is allowed only for sections enabled
  by header flags, such as embedded atlas payload. Unclaimed trailing bytes are
  malformed.

Binary loaders must enforce implementation resource limits before allocation,
including string-table count, object count, array count, payload length, and
atlas byte length. Limits may be configurable, but the default test profile must
reject hostile sizes without exhausting memory.

## JSON Structural Validation

JSON loaders validate the source before canonical value construction.

Required checks:

- Input is UTF-8 without malformed byte sequences.
- Object keys are valid Unicode scalar sequences; lone UTF-16 surrogate escapes
  are invalid.
- Duplicate keys in the same JSON object are invalid.
- Numbers are finite. `NaN`, `Infinity`, and `-Infinity` are invalid.
- Integer, count, and index fields are integral and within the registry/default
  table range for that field.
- Fields have the JSON type required by the generated schema/default table.
- Unknown extension keys are outside the core conformance surface. A loader may
  preserve or drop unknown extension data, but it must not let extension data
  override known fields.

Defaults are applied only after known fields pass type validation.

## Reference Resolution

JSON references are name-based; binary references are index-based. After load,
both forms must resolve to the same semantic graph.

Required checks:

- Names used as references resolve to exactly one target.
- Arrays whose elements are name-addressable reject duplicate names.
- Binary indices are in range for the referenced typed array.
- Slot bone references, skin slot references, attachment parent references,
  constraint bone references, path target references, timeline targets,
  parameter references, and state-machine references all resolve before runtime
  construction.
- Unknown-but-skipped binary objects cannot be referenced by known objects. A
  known reference to a skipped unknown type is an `unknownRequiredReference`
  error.

## Graph And Ordering Validation

The loader must reject semantic graphs that would make runtime traversal
ambiguous or unbounded.

Required checks:

- Bone parent graph is acyclic.
- Bones are parent-first in canonical JSON input and in loaded binary object
  order. If a non-canonical binary loader accepts out-of-order known objects, it
  must still reject cycles before building `SkeletonData`.
- Deformer tree is acyclic.
- Skin bone references do not introduce cycles or out-of-range indices.
- Nested skeleton references do not create an immediate self-reference cycle.
  Deeper cross-file cycle handling belongs to the host asset resolver, but the
  default loader must reject cycles visible in the loaded bundle.
- Constraint arrays preserve source order, and constraint `order` fields are
  valid signed integers as required by `docs/constraint-total-order.md`.
- Transform-mode flag triples are one of the five valid v1 combinations defined
  by `docs/transform-composition-contract.md`.

Cycle detection must be linear in nodes plus edges. Recursive implementations
must guard against stack overflow; iterative traversal is preferred for fuzz
targets.

## Numeric And Domain Validation

Loaders validate numeric domains before runtime use:

- f32-backed fields are quantized at the file boundary as defined by
  `docs/json-canonicalization.md` and `docs/float-math-contract.md`.
- Non-finite floats are invalid.
- Mix values documented as normalized are clamped only when their owning
  contract says to clamp; otherwise out-of-range values are invalid.
- Counts and lengths are non-negative and within implementation limits.
- Weighted skinning influences must sum to `1` within the validation tolerance
  chosen by the skinning implementation contract before playback fixtures rely
  on them.
- Physics `dt` is a runtime input, not a file field, but serialized physics
  parameters must satisfy the domains in `docs/physics-integrator-contract.md`.

## Forward-Compatible Unknown Handling

Unknown handling is permissive only for well-formed binary data that can be
skipped without changing known semantics.

Allowed:

- Unknown same-major type key with well-formed property records.
- Unknown property key on a known object when the property is present in the ToC
  and has a valid `byteLength`.
- Unknown backing type code attached to an unknown property key.

Rejected:

- Unknown property key missing from the ToC.
- Unknown property with malformed `byteLength`.
- Unknown object whose property list is unterminated before EOF.
- Unknown object or property that a known object must reference to be valid.
- Unknown header flag bit unless a later contract defines it as skippable.
- Future major version.

Skipping unknown data must not preserve it in core `SkeletonData` unless an
extension bucket is explicitly designed. Core conformance assumes skipped
unknown content is ignored after validation.

## Fuzz Gate Requirements

The M6 fuzz/validation gate must include:

- Truncated header, ToC, string table, object stream, property payload, and atlas
  payload.
- Bad, overlong, and non-terminating varuint/varint encodings.
- `byteLength` shorter and longer than the known payload decoder consumes.
- Property key absent from the ToC.
- Known property with mismatched ToC backing type code.
- Unknown property with unknown backing type code and valid `byteLength`,
  proving it is skipped.
- Unknown object with multiple unknown properties, proving it is skipped until
  property key `0`.
- Object stream type key `0` followed by unclaimed trailing bytes, proving
  trailing data rejection.
- Duplicate JSON object keys and duplicate name-addressable array entries.
- Cyclic bone parents, cyclic deformer tree, and cyclic visible bundle nested
  skeleton references.
- Binary index loops or out-of-range references for bones, skins, constraints,
  and timelines.
- Invalid transform-mode flag triples.
- Hostile count/length fields that exceed configured limits.

Each case must assert a typed error/exception category and bounded execution.
