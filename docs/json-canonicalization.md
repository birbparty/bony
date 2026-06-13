# JSON Canonicalization

This contract defines canonical `.bony` JSON for authoring output,
round-trip checks, and the M6 `json->bnb->json` idempotency gate.

Canonicalization is a text-emission rule for a loaded `SkeletonData` value. It
does not change runtime semantics.

## Scope

- Applies to `.bony` JSON emitted by project tools.
- Required for `json->bnb->json` idempotency modulo default omission.
- Does not define binary byte stability; that is owned by
  `docs/binary-canonicalization.md`.

## Object Key Order

JSON objects are emitted with a single total order:

1. Keys listed by generated `spec/bony.schema.json` for that object type, in
   schema order. The generated schema preserves the registry/default-table
   source order; JSON Schema property order is not otherwise semantic.
2. Extension or unknown-but-preserved keys, sorted by their canonical escaped
   key bytes after UTF-8 validation.

Top-level keys use the same rule. The initial schema order must mirror the
conceptual model order:

```text
skeleton
bones
slots
ik
transforms
paths
physics
skins
events
parameters
animations
stateMachines
atlas
```

Arrays keep their semantic order. Canonicalization never sorts arrays of bones,
slots, constraints, skins, timelines, or vertices.

JSON object keys must be valid Unicode scalar sequences. Loaders reject lone
UTF-16 surrogate escapes and non-shortest UTF-8. No Unicode normalization is
performed; canonically equivalent spellings remain distinct keys. Extension-key
sorting compares the bytes of the canonical escaped key spelling described
below.

## Whitespace And Encoding

- Emit UTF-8 without a byte-order mark.
- Emit one trailing newline.
- Use two-space indentation.
- Do not emit trailing spaces.
- Object member separators are `,` followed by newline in pretty output.
- String escaping is deterministic:
  - Emit unescaped UTF-8 for every valid scalar value except `"` and `\` and
    control characters U+0000 through U+001F.
  - Escape `"` as `\"` and `\` as `\\`.
  - Escape backspace, form feed, newline, carriage return, and tab as `\b`,
    `\f`, `\n`, `\r`, and `\t`.
  - Escape all other U+0000 through U+001F controls as lowercase
    `\u00xx`.
  - Do not escape `/`.
  - Do not emit `\uXXXX` for non-control non-ASCII scalar values.

## Defaults

Serializers omit fields whose loaded value equals the documented default table.
Deserializers apply defaults before validation that depends on field values.

Idempotency is therefore defined on loaded values, not byte-for-byte source
JSON:

```text
load(input.json) == load(canonical(load(input.json)))
```

Unknown-but-well-formed extension keys are outside the core
`json->bnb->json` idempotency fixture set until an extension-preservation
bucket is designed. Tools may preserve them in a typed bucket or drop them with
a diagnostic when converting through `SkeletonData`, but conformance fixtures
for the core gate must not rely on unknown extension preservation.

## Numbers

Only finite JSON numbers are valid. `NaN`, `Infinity`, and `-Infinity` are
invalid at load time.

Canonical numeric emission has two profiles.

### General Number Profile

Use this profile for integers, counts, indices, and any field whose registry
backing type is not `float32`.

- Emit negative zero as `0`.
- Emit integers without a decimal point when the value is integral and
  `abs(value) <= 9007199254740991`.
- Otherwise emit the shortest decimal that round-trips to the same IEEE-754
  binary64 value using the ECMAScript `Number::toString` algorithm.
- Use lowercase `e` for exponents.
- Do not emit a leading `+`.
- Do not emit leading zeroes in exponents.
- If fixed-point and exponent spellings have the same length, use fixed-point.

### Float32 Profile

Use this profile for every numeric field whose `.bnb` registry backing type is
`float32`, including transform, color-float, timeline, vertex, and time values.

- Quantize to IEEE-754 binary32 at the JSON-to-SkeletonData boundary.
- Emit the shortest decimal that round-trips to the same binary32 value when
  parsed as binary32.
- Use the same exponent, sign, integer, and tie-break rules as the general
  profile.

This profile is what makes `json->bnb->json` exact on loaded values for fields
that are stored as f32 in `.bnb`. Source JSON may contain a higher-precision
decimal, but after load the semantic value is the f32 value.

## Angles

JSON stores angles in degrees. Runtime internals may use radians, but JSON
loaders and serializers convert at the boundary.

Canonical angle emission:

- Preserve the semantic angle; do not normalize by modulo 360 during
  canonicalization.
- Quantize degree values with the Float32 Profile before storing them in
  `SkeletonData` and before converting them to internal radians.
- Emit degrees using the Float32 Profile.
- Do not emit unit suffixes.
- Imports that accept external authoring forms such as `skewX/skewY` must
  convert them into canonical rotation/shear fields before `.bony` emission;
  those external field names are not part of the canonical `.bony` surface.

Degree/radian conversion precision for JSON boundaries is:

- Load: parse degrees as binary64, quantize to binary32 degrees, then convert
  that f32 degree value to radians for runtime use.
- Store: convert runtime radians to degrees in binary64, quantize to binary32
  degrees, then emit with the Float32 Profile.
- The absolute error introduced by one degree->radian->degree JSON boundary
  cycle must be `<= 1e-4` degrees.

The later float-math contract may further constrain runtime intermediate math,
but it must not loosen this JSON boundary rule.

## Validation

A canonical JSON emitter must reject without emitting output when it sees:

- Non-finite numbers.
- String references that cannot resolve to required named objects.
- Field values with the wrong primitive type after defaults are applied.
- Duplicate object names in arrays where names form the reference key.

The later load-validation contract owns malformed-input behavior in detail.
This document only requires that canonical output is deterministic and valid.

## Conformance Checks

The M6 idempotency gate must include:

- Mixed input key orders canonicalize to the same output.
- Default-valued fields are omitted and then re-applied on load.
- `-0` emits as `0`.
- Representative small, large, fractional, and exponent-form inputs emit with
  the canonical number grammar for both numeric profiles.
- Float32-backed fields canonicalize high-precision source decimals to the
  corresponding f32 semantic value.
- Degree angle fields survive `json->bnb->json` with exact loaded f32-degree
  value equality, and each degree/radian boundary cycle stays within
  `1e-4` degrees.
- Unknown extension keys are excluded from the core idempotency fixture set
  until extension preservation is explicitly designed.
