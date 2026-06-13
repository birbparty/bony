# JSON Canonicalization

This contract defines canonical `.bony` JSON for authoring output,
round-trip checks, and the M6 `json->bnb->json` idempotency gate.

Canonicalization is a text-emission rule for a loaded `SkeletonData` value. It
does not change runtime semantics.

## Scope

- Applies to `.bony` JSON emitted by project tools.
- Required for `json->bnb->json` idempotency modulo default omission.
- Does not define binary byte stability; that is owned by the binary
  canonicalization contract.

## Object Key Order

JSON objects are emitted with a single total order:

1. Keys listed by generated `spec/bony.schema.json` for that object type, in
   schema order.
2. Extension or unknown-but-preserved keys, sorted by Unicode scalar value.

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

## Whitespace And Encoding

- Emit UTF-8 without a byte-order mark.
- Emit one trailing newline.
- Use two-space indentation.
- Do not emit trailing spaces.
- Object member separators are `,` followed by newline in pretty output.
- String escaping uses JSON escapes only where required by RFC 8259, plus
  `\n`, `\r`, `\t`, `\"`, and `\\` for readability.

## Defaults

Serializers omit fields whose loaded value equals the documented default table.
Deserializers apply defaults before validation that depends on field values.

Idempotency is therefore defined on loaded values, not byte-for-byte source
JSON:

```text
load(input.json) == load(canonical(load(input.json)))
```

Unknown-but-well-formed extension keys are preserved only when the loader has a
typed preservation bucket for that object. Otherwise tools may drop them with a
diagnostic when converting through `SkeletonData`.

## Numbers

Only finite JSON numbers are valid. `NaN`, `Infinity`, and `-Infinity` are
invalid at load time.

Canonical numeric emission:

- Emit negative zero as `0`.
- Emit integers without a decimal point when the value is integral and
  `abs(value) <= 9007199254740991`.
- Otherwise emit the shortest decimal that round-trips to the same IEEE-754
  binary64 value.
- Use lowercase `e` for exponents.
- Do not emit a leading `+`.
- Do not emit leading zeroes in exponents.
- Do not emit an exponent for values where the shortest round-trip decimal is
  shorter without one.

Runtime-specific storage may later choose `float32` for some fields, but
canonical JSON text is emitted from the loaded semantic value using this
binary64 decimal rule unless a field-specific contract says otherwise.

## Angles

JSON stores angles in degrees. Runtime internals may use radians, but JSON
loaders and serializers convert at the boundary.

Canonical angle emission:

- Preserve the semantic angle; do not normalize by modulo 360 during
  canonicalization.
- Emit degrees using the canonical number rule.
- Do not emit unit suffixes.
- Imports that accept authoring forms such as `skewX/skewY` must convert them
  into the canonical rotation/shear fields before emission.

Degree-to-radian and radian-to-degree conversion tolerances are governed by the
float-math contract. Canonical JSON must not add extra rounding beyond the
canonical number rule.

## Validation

A canonical JSON emitter must reject or diagnose:

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
  the canonical number grammar.
- Degree angle fields survive `json->bnb->json` within the numeric tolerance
  defined by the float-math contract.
