# Dart Runtime Writer Policy

This note records the runtime-dart writer surface after the public deterministic
`.bony` JSON writer change.

## Public Writer Surface

The Dart runtime exposes `writeBonyJson(SkeletonData data)` from
`package:bony/bony.dart`.

`writeBonyJson` validates an already-constructed `SkeletonData` with the same
structural rules used by the JSON and binary loaders, then emits canonical
`.bony` JSON. The writer is intended for deterministic authoring output,
downstream tool handoff, and byte-parity checks against Nim canonical JSON
fixtures.

The Dart runtime also continues to expose loaders for both supported serialized
inputs:

- `loadBonyJson(String jsonText)` for `.bony` JSON.
- `loadBonyBnb(Uint8List bytes)` for `.bnb` binary.

Data loaded from either input can be projected back to canonical `.bony` JSON
with `writeBonyJson`.

## `.bnb` Write Policy

For this change, runtime-dart is read-only for `.bnb`.

That means:

- Dart may load `.bnb` with `loadBonyBnb`.
- Dart may convert loaded `.bnb` data to canonical `.bony` JSON with
  `writeBonyJson(loadBonyBnb(bytes))`.
- Dart does not expose a public `.bnb` encoder or binary writer API.
- `.bnb` byte emission remains owned by the existing binary canonicalization
  contract and the Nim/tooling implementation until a dedicated Dart binary
  writer task is accepted.

This boundary is intentional. The public Dart writer added here is a canonical
JSON writer, not a binary writer. A Dart `.bnb` writer would need its own
coverage for table-of-contents emission, string-table ordering, packed payload
layouts, canonical varints, header flags, and `bnb->json->bnb` byte-stability.

## Follow-Up Policy

If a downstream integration needs Dart to emit `.bnb` bytes directly, file a
dedicated task for a Dart binary writer rather than extending
`writeBonyJson`. The current follow-up is `bony-7pom`. That task should
reference:

- [binary-canonicalization.md](binary-canonicalization.md)
- [binary-toc-skip-semantics.md](binary-toc-skip-semantics.md)
- [registry/README.md](../registry/README.md)
- [load-validation-contract.md](load-validation-contract.md)
