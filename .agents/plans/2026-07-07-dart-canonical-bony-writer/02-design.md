# Design

## Public API

Add a Dart writer API exported from `package:bony/bony.dart`:

```dart
String writeBonyJson(SkeletonData data)
```

Recommended error surface:

```dart
final class BonyWriteException implements Exception {
  const BonyWriteException(this.message, [this.cause]);
  final String message;
  final Object? cause;
}
```

Behavior:

- Validate `data` before emitting anything.
- Wrap validation failures in `BonyWriteException`, preserving the original
  `FormatException` as `cause`.
- Wrap non-validation emission failures in `BonyWriteException` too, with a
  message that names the object family or field when available.
- Return canonical JSON text with a trailing newline.
- Do not mutate input `SkeletonData`.
- Do not emit `SkeletonData.deformOverrides`.

Add `SkeletonData.copyWith` in `runtime-dart/lib/src/model/skin_model.dart`.
It must include every constructor field, including `deformOverrides`, so editor
commands cannot silently drop newly added collections.

Acceptance for error behavior:

- `writeBonyJson` never emits partial output.
- Invalid input throws `BonyWriteException`.
- Tests assert `exception.cause is FormatException` for validation failures.

## Validation Reuse

Expose loader validation without copying rule logic.

Recommended path:

1. In `runtime-dart/lib/src/loader.dart`, add:

   ```dart
   void validateBonyData(SkeletonData data) => _validate(data);
   ```

2. Export it from `runtime-dart/lib/bony.dart`.
3. Have `writeBonyJson` call `validateBonyData(data)`.

This keeps `loader_validation.dart` as a part file while giving writers and
consumers one public validation entry point.

If the implementer wants a narrower public API, use
`runtime-dart/lib/src/validation.dart` and restructure the current part file
into an importable library. That is more invasive and should be a separate bead
from the writer logic.

## Writer Module

Create a new source file:

- `runtime-dart/lib/src/writer.dart`

It should import:

- `dart:typed_data` if byte unpacking is needed.
- `deform.dart` for `quantizeF32`.
- `generated/wire.dart` as `wire`.
- `loader.dart` for `validateBonyData`.
- `model.dart`.
- helper modules needed to decode packed runtime fields into canonical JSON.

Recommended internal shape:

- `_JsonWriter`: small string-buffer helper with `field`, indentation, string
  escaping, and number emission helpers.
- `_Scalar`: typed representation of scalar properties for default omission.
- `_emitObject`: writes object fields in `wire.bonyObjectSpec(typeId).properties`
  order.
- Type-specific emitters that assemble scalar/property values from typed model
  objects and call `_emitObject`.

Do not build a `Map` and call `jsonEncode`; Dart's JSON encoder will not
guarantee the required pretty format, number spelling, or escaping parity.

## Default Omission

Use generated registry metadata as the default source of truth:

- `wire.bonyObjectSpecs` for property order.
- `wire.bonyPropertyDefaults` for equality/default/omit rules.
- `wire.bonyIsRequiredProperty` for required fields.
- `wire.bonyOrdinalEnums` for ordinal enum contracts.

Add generated helper APIs if hand-written lookup code becomes repetitive:

- default lookup by `(objectId, propertyId)`.
- backing type lookup by property id.
- ordinal enum lookup by enum id.

When changing generated output:

1. edit `codegen/emit.py`;
2. update `codegen/test_generate.py`;
3. run `python3 codegen/generate.py`;
4. include regenerated Dart and Nim generated files if both are affected.

Avoid manually editing `runtime-dart/lib/src/generated/wire.dart`.

## Number and String Canonicalization

Mirror Nim `canonicalNumber` in Dart:

- Reject non-finite numbers.
- Emit `0` for both `0.0` and `-0.0`.
- Emit integral safe integers without a decimal point.
- Otherwise emit the shortest Dart spelling that round-trips to the same value.

For float32-backed fields, run through `quantizeF32` before emission. The writer
must compare omitted defaults after applying the same quantization profile the
loader uses.

Implement string escaping directly:

- escape `"` and `\`;
- escape `\b`, `\f`, `\n`, `\r`, `\t`;
- escape other U+0000 through U+001F controls as lowercase `\u00xx`;
- do not escape `/`;
- emit non-control non-ASCII directly.

Add explicit tests for negative zero, integer-looking floats, high-precision
float32 inputs, controls, slash, and non-ASCII text.

## Object Coverage

The first implementation must cover the current loaded `SkeletonData` model:

- skeleton header
- bones
- slots
- regions
- point attachments
- bounding boxes
- nested rig attachments
- path attachments and path constraints
- clipping attachments
- mesh attachments, including weighted/unweighted data
- IK, transform, and physics constraints
- skins and skin entries
- animations: bone, slot, deform, and event timelines
- parameters
- deformers: warp lattice, rotation deformer, keyforms/blends
- state machines: inputs, layers, states, blend clips, transitions,
  conditions, listeners

Use Nim `toBonyJson` as the coverage checklist. The implementation agent should
walk from `runtime-nim/src/bony/jsonio.nim:toBonyJson` through every section and
create matching Dart emitters.

Packed payloads need explicit ownership. The writer must reconstruct canonical
JSON for:

- packed bone, slot, deform, and event timeline keys;
- mesh vertices, UVs, triangles, and weighted influence data;
- skin membership lists;
- deformer warp/control/keyform payloads;
- state-machine index references that the JSON surface expresses as names or
  nested records.

Do not emit raw packed bytes into JSON. Tests must include at least one fixture
for every packed payload family above.

## Top-Level Emission

The docs list a conceptual order that uses names like `ik` and `transforms`,
but current assets and loaders use concrete top-level keys such as
`ikConstraints` and `transformConstraints`. Match the Nim writer and committed
canonical assets for exact field names and section order.

Do not omit required top-level arrays if Nim emits empty arrays for them today.
The parity target is Nim writer output, not a new prettier JSON shape.

## Codec Stub Resolution

Resolve the public throwing stubs as a codegen task, not by editing generated
files.

Required option for this change:

- Remove aggregate `encodeBonyObject(String)` and `decodeBonyObject(String)`
  from the generated Dart public surface.
- Keep metadata and any useful scalar helpers public.
- Add a short docs note that aggregate typed object writing is provided by
  `writeBonyJson`, and generated aggregate codecs are reserved for future
  registry-driven binary/JSON internals.

Do not leave a public `Never` API whose only behavior is `UnsupportedError`.

## `.bnb` Write Policy

Record a policy in docs during this change.

Required policy:

- Dart writes canonical `.bony` JSON only in this milestone.
- `.bnb` remains read-only in Dart until a later dedicated binary writer task
  ports `runtime-nim/src/bony/binary/semantic.nim` and byte-stability tests.
- Downstream editors that need durable authoring output should write JSON and
  let the Nim CLI or a future Dart encoder produce `.bnb`.

This unblocks Flashy because its immediate blocker is the decision, not
necessarily Dart `.bnb` bytes. Create a follow-up bead for Dart `writeBonyBnb`
if Flashy still wants local binary export after JSON writer adoption.

## Conformance Strategy

Add Dart tests that compare against Nim canonical JSON. Required approach:

1. Add a test helper that loads every selected `conformance/assets/*.bony`.
2. For each asset, assert:
   - `writeBonyJson(loadBonyJson(input)) == nimCanonicalText`.
   - `writeBonyJson(loadBonyJson(writeBonyJson(data))) == writeBonyJson(data)`.
3. Commit canonical JSON fixture files under
   `conformance/goldens/canonical-json/`, produced by the Nim reference.
4. Add a repo-level check script, for example
   `scripts/ci/check_dart_writer_canonical_json.py`, that regenerates those
   fixtures from current Nim and fails if any committed fixture is stale.

The check script should build or invoke a small Nim canonicalizer that calls
`toBonyJson(loadBonyJsonAsset(readFile(path)))` for JSON assets. For `.bnb`
assets, it should use the existing CLI path:

```bash
nim c --hints:off -d:release -o:/tmp/bony_cli cli/bony_cli.nim
/tmp/bony_cli bnb-to-json conformance/assets/bnb/m1_rig.bnb /tmp/m1_rig.bony
```

The exact script interface is up to the implementation agent, but the command
must be non-interactive and wired into `make test` or an equivalent final gate
so stale fixtures cannot pass silently.

Minimum coverage set must include feature-complete current assets:

- `m1_rig.bony`
- `m5_ik_rig.bony`
- `m5_transform_rig.bony`
- `m5_physics_rig.bony`
- `m11_clip_rig.bony`
- `m12_mesh_rig.bony`
- `m13_mesh_deform_rig.bony`
- `m16_mesh_multi_deform_rig.bony`
- `m18_mesh_deform_anim_rig.bony`
- `m19_event_rig.bony`
- `m20_skin_rig.bony`
- `m21_pointer_listener_rig.bony`
- `m22_skin_required_rig.bony`
- `m23_nested_rig.bony`
- `m24_atlas_region_rig.bony`

Include all current assets if feasible; the list above is the minimum for
coverage of every current object family.

Also include representative `.bnb` loader coverage:

- `writeBonyJson(loadBonyBnb(bytes))` must match the Nim canonical JSON for at
  least the `.bnb` counterparts of the minimum assets above.
- Prefer all `conformance/assets/bnb/*.bnb` once the fixture check exists.
