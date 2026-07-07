# Current State

## Request Context

Flashy needs a public deterministic Dart `.bony` writer. Its current exporter
in `~/git/flashy/lib/export/bony/bony_exporter.dart` duplicates bony defaults
and canonical ordering by hand. The upstream request calls this dependency
temporary and blocks Flashy `.bony` export plus `.bnr` v2 persistence closure.

The prior Flashy request for `BoneData.copyWith` has already landed, so the
preferred direction is to move shared editor-facing helpers into
`runtime-dart`.

## Existing Dart Surface

`runtime-dart/lib/bony.dart` exports:

- animation, deform, IK, state machine, transform, and physics helpers
- `src/generated/wire.dart`
- `src/loader.dart`
- `src/model.dart`
- `src/version.dart`

There is no writer export.

`runtime-dart/lib/src/loader.dart` currently owns both JSON and `.bnb` loading.
It imports `dart:convert`, `dart:typed_data`, `deform.dart` for `quantizeF32`,
generated wire metadata, model types, and physics channel decoding. Validation
is a private part file:

- `runtime-dart/lib/src/loader_validation.dart`
- entry point: `_validate(SkeletonData data)`

Because `_validate` is private to the `loader.dart` library, a new writer file
cannot reuse it directly unless the implementation creates a public or
package-private validation facade.

`runtime-dart/lib/src/model/skin_model.dart` defines `SkeletonData` with 20
constructor fields:

- serialized fields: `header`, `bones`, `slots`, `regions`, `paths`,
  `pathAttachments`, `pointAttachments`, `boundingBoxAttachments`,
  `nestedRigAttachments`, `clippingAttachments`, `meshAttachments`,
  `ikConstraints`, `transformConstraints`, `physicsConstraints`, `skins`,
  `animations`, `parameters`, `deformers`, `stateMachines`
- non-serialized runtime field: `deformOverrides`

`SkeletonData` does not currently have `copyWith`.

## Generated Codec Stubs

`runtime-dart/lib/src/generated/wire.dart` exports useful metadata:

- `bonyRegistryVersion`
- type and property key constants
- `bonyObjectSpecs`
- `bonyPropertyDefaults`
- `bonyRequiredProperties`
- `bonyOrdinalEnums`
- `bonyObjectSpec(String typeId)`
- `bonyIsRequiredProperty(String objectId, String propertyId)`

But the public stubs still throw:

- `Never encodeBonyObject(String typeId)`
- `Never decodeBonyObject(String typeId)`

They are emitted by `codegen/emit.py`, so resolving them means changing codegen
and regenerating outputs, not hand-editing generated Dart.

The generated Nim surface has richer scalar encode/decode helpers, but its
aggregate `encodeBonyObject` and `decodeBonyObject` still throw too. For this
request, do not widen the change to implement Nim aggregate stubs unless needed
to keep codegen symmetric. It is acceptable to remove/rename/document the Dart
public aggregate stubs while leaving lower-level registry helpers available.

## Nim Reference Writer

The reference writer lives in:

- `runtime-nim/src/bony/jsonio.nim`
- entry point: `toBonyJson*(data: SkeletonData): string`

It validates before emission via `validateSkeletonData(data)` and then emits
canonical pretty JSON. Important writer helpers include:

- `canonicalNumber`: finite numbers only, `-0` collapses to `0`, integral safe
  numbers emit without a decimal point.
- `addJsonString`: deterministic JSON string escaping.
- generated scalar helpers such as `encodeBoneJsonScalars`, which omit defaults
  per registry/default metadata.

The Nim `.bnb` writer exists in:

- `runtime-nim/src/bony/binary/semantic.nim`
- entry point: `toBonyBnb(data)` / `writeBonyBnb`

Dart currently has only `.bnb` loading.

## Canonicalization Contracts

Use these documents as implementation requirements:

- `docs/json-canonicalization.md`
- `docs/binary-canonicalization.md`
- `docs/load-validation-contract.md`
- `docs/float-math-contract.md`
- `codegen/canonical_json_overrides.json`
- `docs/versioning.md`

JSON emission details that matter for parity:

- UTF-8 text, no BOM, one trailing newline.
- Two-space indentation.
- Deterministic escaping: only quotes, backslash, and control characters are
  escaped; non-control non-ASCII is emitted directly.
- Top-level and object fields follow schema/registry order.
- Arrays preserve semantic order; writers do not sort bones, slots,
  constraints, skins, timelines, or vertices.
- Defaults are omitted only when the default entry has `omitWhenDefault: true`.
- Float32-backed fields must use the same `quantizeF32` boundary behavior used
  elsewhere in Dart.

## Test Surface

Dart tests run from `runtime-dart` via `flutter test`, not plain `dart test`.
`Makefile` already runs `$(MAKE) dart-test`, which runs:

```bash
cd runtime-dart && flutter test
```

Existing conformance assets:

- JSON assets: `conformance/assets/*.bony`
- binary assets: `conformance/assets/bnb/*.bnb`
- numeric goldens: `conformance/goldens/*.json`

Existing Nim tests that show useful parity expectations:

- `runtime-nim/tests/test_canonical_serialization.nim`
- `runtime-nim/tests/test_json_bnb_json_idempotency.nim`
- `runtime-nim/tests/test_bnb_byte_stability.nim`
- feature-specific round-trip tests such as mesh, skin, clipping, nested rig,
  event, transform, physics, and helper geometry tests.

## Affected Areas

Primary Dart implementation:

- `runtime-dart/lib/src/writer.dart` or a similar new writer library.
- `runtime-dart/lib/bony.dart`.
- `runtime-dart/lib/src/loader.dart` and/or `loader_validation.dart` to expose
  validation reuse without duplicating rules.
- `runtime-dart/lib/src/model/skin_model.dart` for `SkeletonData.copyWith`.
- `runtime-dart/test/*` for writer, validation, copyWith, and conformance tests.

Codegen and generated files:

- `codegen/emit.py`
- `codegen/test_generate.py`
- `runtime-dart/lib/src/generated/wire.dart`
- possibly `runtime-nim/src/bony/generated/wire.nim` if the generator change is
  shared.

Docs:

- `docs/versioning.md`
- a new or existing docs page for Dart writer and `.bnb` write policy, such as
  `docs/dart-writer-policy.md` or a section in `docs/json-canonicalization.md`.
- `docs/README.md` if adding a new document.

Optional scripts:

- A small parity helper under `scripts/` only if direct Dart tests cannot invoke
  Nim canonicalization cheaply.

## Main Risks

- Duplicating validation rules would drift from loader behavior. Prefer one
  validation implementation invoked by both `loadBonyJson`/`loadBonyBnb` and
  `writeBonyJson`.
- Hand-written default omission can drift from `spec/defaults.yml`. The writer
  should go through generated metadata or generated typed helpers rather than
  maintain a separate table.
- JSON string escaping and number formatting must match Nim exactly, including
  negative zero and float32 quantization.
- Packed byte-backed fields such as timelines, mesh payloads, skin membership,
  and deformer payloads need canonical JSON object/array reconstruction that
  matches the loader model, not raw binary bytes.
- `deformOverrides` is runtime/transient and must not be emitted or included in
  serialized round-trip comparisons.
- Adding public writer APIs is a package surface change. Document exceptions and
  error types clearly.
