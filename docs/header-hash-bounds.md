# Header Hash And Bounds Decision

This document records the v1 decision for `SkeletonData.header.hash` and
`SkeletonData.header.bounds`. It is intentionally narrow: do not reopen these
defaults in later loader/runtime work unless a new bead explicitly changes this
contract and dependent conformance fixtures.

## Decision Summary

- `header.bounds` is optional, nonessential metadata.
- Loaders recompute runtime bounds from loaded geometry when bounds are needed.
- Bounds are excluded from byte-stability and Dart conformance targets.
- `header.hash` is a defined digest over canonical `.bnb` bytes.
- The digest input excludes the `header.hash` property itself.

## Bounds

`header.bounds` may be present in source assets as an authoring/editor hint, but
runtime correctness must not depend on it.

Loader behavior:

- If `bounds` is absent, loading proceeds normally.
- If `bounds` is present and well-formed, loaders may retain it for diagnostics
  or editor tooling.
- If `bounds` is present but malformed, loaders reject it like any other known
  malformed field.
- Runtime systems that need bounds recompute them from geometry, attachments,
  skins, and animation/deformer state relevant to their use case.

Canonical emission:

- Canonical `.bnb` omits `bounds`.
- Canonical `.bony` omits `bounds` unless a future editor-profile contract
  explicitly opts into emitting editor metadata.
- `bounds` is not included in `bnb->json->bnb` byte-stability fixtures.
- `bounds` is not a Dart runtime conformance target.

This avoids making stale editor metadata part of runtime determinism.

## Hash

`header.hash` is a content digest for canonical binary assets. It is not a
security boundary and must not be used as a trust check.

Digest algorithm:

```text
BLAKE3-256(canonical_bnb_without_header_hash_property)
```

The emitted value is the 32-byte digest encoded as lowercase hexadecimal in
JSON and as raw 32 bytes in `.bnb`.

Required registry shape:

- Object: header/skeleton metadata object.
- Property: `header.hash`.
- Backing type: `bytes`.
- Binary payload: exactly 32 raw digest bytes, so the surrounding property
  `byteLength` is exactly `32`.
- JSON representation: exactly 64 lowercase hexadecimal characters.

Canonical hash computation:

1. Build the loaded `SkeletonData` value.
2. Emit canonical `.bnb` exactly as defined by
   `docs/binary-canonicalization.md`, except omit the `header.hash` property
   even if the loaded value contains one.
3. Compute BLAKE3-256 over those bytes.
4. If emitting a profile that includes `header.hash`, write the computed digest.

Canonical core `.bnb` emission may omit `header.hash` when no hash property is
registered yet. Once the registry adds `header.hash`, canonical shipping
profiles should emit it using the algorithm above.

Canonical writers that include `header.hash` ignore any loaded hash value and
always emit the recomputed digest. Verification mode controls whether a loaded
hash mismatch is reported during load/tool validation; it does not control
canonical writer recomputation.

Load behavior:

- If `header.hash` is absent, loading proceeds normally.
- If `header.hash` is present, loaders validate its shape: 32 raw bytes in
  `.bnb` or 64 lowercase hex characters in JSON.
- Loaders may verify the digest through an explicit loader/tooling option, but
  default runtime loading does not reject a hash mismatch unless verification
  mode is enabled.
- Verification mode computes the digest using the same
  `canonical_bnb_without_header_hash_property` rule and reports mismatch as a
  typed validation error.

## Byte-Stability Interaction

The `header.hash` value must not make canonical emission self-referential.

For byte-stability tests:

- Fixtures without `header.hash` remain byte-stable under the normal
  `bnb->json->bnb` rule.
- Fixtures with `header.hash` are byte-stable only if the writer recomputes the
  same digest from canonical bytes with the hash property omitted.
- Test harnesses must compare the emitted hash to the independently computed
  digest, not to a digest over bytes that include the hash itself.

## Conformance Checks

The M6 hash/bounds-adjacent checks must include:

- Missing `bounds` loads successfully.
- Present well-formed `bounds` does not affect runtime numeric outputs.
- Canonical `.bnb` byte-stability fixtures omit `bounds`.
- Missing `header.hash` loads successfully.
- Malformed hash shape is rejected when the field is present.
- Hash verification mode accepts a digest computed over canonical bytes with
  `header.hash` omitted.
- Hash verification mode rejects a digest computed over bytes that include
  `header.hash`.
- A committed fixture records an independently computed BLAKE3 digest for a
  canonical `.bnb` with `header.hash` omitted from the digest input.
- The same fixture proves `.bnb` emits the digest as 32 raw bytes with
  `byteLength == 32` and JSON emits the digest as 64 lowercase hexadecimal
  characters.
- `bnb->json->bnb` recomputes and preserves the canonical digest even when the
  loaded source hash is stale.
