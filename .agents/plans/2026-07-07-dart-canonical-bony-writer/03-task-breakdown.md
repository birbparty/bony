# Task Breakdown

This is written as a Beads-sized implementation graph. The implementation agent
should create an epic and child beads before coding.

## Suggested Beads Script

```bash
#!/usr/bin/env bash
set -euo pipefail

if [ ! -d ".beads" ]; then
  bd init
fi

EPIC=$(bd create "Epic: Dart canonical .bony writer" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress

ANALYZE=$(bd create "Inventory Nim toBonyJson coverage and map every emitted object family to Dart model fields" -t task -p 0 --label analysis --parent "$EPIC" --silent)
VALIDATION=$(bd create "Expose shared Dart SkeletonData validation for loaders and writer without duplicating loader_validation.dart rules" -t task -p 0 --label prep --parent "$EPIC" --silent)
CANON_HELPERS=$(bd create "Implement Dart canonical JSON writer primitives for indentation, string escaping, finite number emission, f32 quantization, and default comparison" -t task -p 0 --label impl --parent "$EPIC" --silent)
COPY_WITH=$(bd create "Add exhaustive SkeletonData.copyWith including serialized collections and deformOverrides" -t task -p 1 --label impl --parent "$EPIC" --silent)
REGISTRY_HELPERS=$(bd create "Adjust codegen/generated wire metadata so Dart writer can resolve property order, defaults, backing types, and required fields without hand-maintained tables" -t task -p 0 --label impl --parent "$EPIC" --silent)
CANON_FIXTURES=$(bd create "Add Nim-generated canonical JSON fixtures and a stale-fixture check for Dart writer parity over JSON and .bnb conformance assets" -t task -p 0 --label testing --parent "$EPIC" --silent)
PACKED_PAYLOADS=$(bd create "Implement and test Dart canonical JSON reconstruction for packed timelines, mesh payloads, skin membership, deformers, and state-machine index references" -t task -p 0 --label impl --parent "$EPIC" --silent)
CORE_WRITER=$(bd create "Implement writeBonyJson for skeleton, bones, slots, attachments, constraints, skins, animations, deformers, and state machines in runtime-dart/lib/src/writer.dart" -t task -p 0 --label impl --parent "$EPIC" --silent)
CODEC_STUBS=$(bd create "Remove generated Dart encodeBonyObject/decodeBonyObject aggregate throwing stubs from the public generated surface" -t task -p 1 --label impl --parent "$EPIC" --silent)
WRITER_TESTS=$(bd create "Add Dart writer tests for validation failure, default omission, number/string canonicalization, round-trip fixed points, and Nim byte parity" -t task -p 0 --label testing --parent "$EPIC" --silent)
BNB_POLICY=$(bd create "Document Dart .bnb write policy as read-only for this change and file any binary-writer follow-up if needed" -t task -p 1 --label docs --parent "$EPIC" --silent)
VERSION_POLICY=$(bd create "Document bonyRegistryVersion bump policy for downstream consumers in docs/versioning.md" -t task -p 2 --label docs --parent "$EPIC" --silent)
FLASHY_ADOPTION=$(bd create "Record Flashy adoption handoff: resulting bony commit SHA, expected dependency repin, and temporary exporter deletion path" -t task -p 2 --label docs --parent "$EPIC" --silent)
VERIFY=$(bd create "Run and document final verification: python codegen check/tests, runtime-dart flutter test, and repo make test" -t task -p 0 --label testing --parent "$EPIC" --silent)

bd dep add "$VALIDATION" "$ANALYZE"
bd dep add "$CANON_HELPERS" "$ANALYZE"
bd dep add "$REGISTRY_HELPERS" "$ANALYZE"
bd dep add "$CANON_FIXTURES" "$ANALYZE"
bd dep add "$PACKED_PAYLOADS" "$CANON_HELPERS"
bd dep add "$PACKED_PAYLOADS" "$REGISTRY_HELPERS"
bd dep add "$CORE_WRITER" "$VALIDATION"
bd dep add "$CORE_WRITER" "$CANON_HELPERS"
bd dep add "$CORE_WRITER" "$REGISTRY_HELPERS"
bd dep add "$CORE_WRITER" "$CANON_FIXTURES"
bd dep add "$CORE_WRITER" "$PACKED_PAYLOADS"
bd dep add "$WRITER_TESTS" "$CORE_WRITER"
bd dep add "$WRITER_TESTS" "$COPY_WITH"
bd dep add "$WRITER_TESTS" "$CANON_FIXTURES"
bd dep add "$CODEC_STUBS" "$REGISTRY_HELPERS"
bd dep add "$BNB_POLICY" "$CORE_WRITER"
bd dep add "$VERSION_POLICY" "$REGISTRY_HELPERS"
bd dep add "$FLASHY_ADOPTION" "$BNB_POLICY"
bd dep add "$FLASHY_ADOPTION" "$VERSION_POLICY"
bd dep add "$FLASHY_ADOPTION" "$WRITER_TESTS"
bd dep add "$VERIFY" "$WRITER_TESTS"
bd dep add "$VERIFY" "$CODEC_STUBS"
bd dep add "$VERIFY" "$BNB_POLICY"
bd dep add "$VERIFY" "$VERSION_POLICY"

echo "Created epic $EPIC"
echo "Initial work:"
bd ready
```

## Task Details

### 1. Inventory Nim Writer Coverage

Reservation:

- read-only: `runtime-nim/src/bony/jsonio.nim`
- read-only: `runtime-dart/lib/src/model/**`
- read-only: `runtime-dart/lib/src/loader*.dart`

Deliverables:

- A checklist in the bead notes mapping every Nim `toBonyJson` section to Dart
  model fields.
- Confirmation of top-level section order from actual Nim output and committed
  conformance assets.
- Identification of any Dart model fields that cannot be emitted without helper
  decoding.

Acceptance:

- No writer implementation starts until every current object family has an
  owner in the checklist.

### 2. Shared Validation

Reservation:

- `runtime-dart/lib/src/loader.dart`
- `runtime-dart/lib/src/loader_validation.dart`
- `runtime-dart/lib/bony.dart`
- `runtime-dart/test/*validation*`

Deliverables:

- Public or package-level `validateBonyData(SkeletonData data)`.
- Loader tests proving existing `loadBonyJson`/`loadBonyBnb` failures still
  throw as before.
- Writer tests can invoke the same validator.

Acceptance:

- Validation logic remains in one implementation.
- Invalid duplicate names, unknown references, malformed mesh/clip data, and
  invalid state-machine references fail before writer emission.

### 3. Canonical Writer Primitives

Reservation:

- `runtime-dart/lib/src/writer.dart`
- `runtime-dart/test/writer*_test.dart`

Deliverables:

- Deterministic string escaping.
- Canonical number formatting.
- Float32 quantization integration using existing `quantizeF32`.
- Default equality helpers for string, bool, int/uint, f32, f64, bytes, and
  ordinal enum payloads as needed.

Acceptance:

- Focused tests cover `-0.0`, safe integral values, non-finite rejection,
  float32 high precision collapse, control escaping, slash non-escaping, and
  non-ASCII preservation.

### 4. `SkeletonData.copyWith`

Reservation:

- `runtime-dart/lib/src/model/skin_model.dart`
- `runtime-dart/test/*copy*`

Deliverables:

- Exhaustive `copyWith` method for all 20 constructor fields.
- Test that modifying one field preserves all other references/values,
  including `deformOverrides`.

Acceptance:

- A test creates a fully populated `SkeletonData`, calls
  `copyWith(header: ...)`, and asserts every other constructor field is
  identical, including `deformOverrides`.
- A second test changes at least two list fields in one call and proves only
  those fields changed.

### 5. Registry and Codegen Helpers

Reservation:

- `codegen/emit.py`
- `codegen/test_generate.py`
- `runtime-dart/lib/src/generated/wire.dart`
- `runtime-nim/src/bony/generated/wire.nim` if generated output changes

Deliverables:

- Generated Dart lookup helpers for defaults/backing types if needed.
- Codegen tests proving helper output and codec-stub resolution.
- Regenerated generated files.

Acceptance:

- `python3 codegen/generate.py --check` passes.
- `python3 -m unittest discover -s codegen -p 'test_*.py'` passes.

### 6. Canonical Fixture Oracle

Reservation:

- `conformance/goldens/canonical-json/**`
- `scripts/ci/check_dart_writer_canonical_json.py` or equivalent
- read-only: `runtime-nim/src/bony/jsonio.nim`
- read-only: `cli/bony_cli.nim`

Deliverables:

- Nim-generated canonical JSON fixtures for the selected JSON assets.
- Nim-generated canonical JSON fixtures for representative `.bnb` assets.
- A non-interactive stale-fixture check that regenerates from current Nim and
  fails on diff.

Acceptance:

- The fixture check runs before or alongside Dart writer tests.
- The check documents the exact Nim command or helper used to regenerate
  fixtures.

### 7. Packed Payload Reconstruction

Reservation:

- `runtime-dart/lib/src/writer.dart`
- packed payload helper files under `runtime-dart/lib/src/` if needed
- `runtime-dart/test/*writer*`

Deliverables:

- Canonical JSON reconstruction for packed bone, slot, deform, and event
  timelines.
- Canonical JSON reconstruction for mesh vertices, UVs, triangles, and weighted
  influence data.
- Canonical JSON reconstruction for skin membership, deformer payloads, and
  state-machine index references.

Acceptance:

- Tests cover at least one fixture for each packed family listed above.
- No canonical JSON emitter writes raw packed byte arrays where the JSON
  contract expects structured arrays or records.

### 8. `writeBonyJson`

Reservation:

- `runtime-dart/lib/src/writer.dart`
- `runtime-dart/lib/bony.dart`
- possibly narrow helper files under `runtime-dart/lib/src/`

Deliverables:

- `writeBonyJson(SkeletonData)` exported from `package:bony/bony.dart`.
- Complete object-family emitters.
- Public writer error behavior documented in code comments/API docs.

Acceptance:

- At least one minimal skeleton and one fixture covering constraints, skins,
  animations, packed payloads, and state machines emit exact expected strings.
- `loadBonyJson(writeBonyJson(data))` succeeds for all valid test fixtures.
- Invalid data throws `BonyWriteException` and preserves the validation
  `FormatException` as `cause`.

### 9. Codec Stub Cleanup

Reservation:

- `codegen/emit.py`
- `codegen/test_generate.py`
- `runtime-dart/lib/src/generated/wire.dart`
- docs touched by public API notes

Deliverables:

- Public Dart API no longer exposes always-throwing `encodeBonyObject` and
  `decodeBonyObject`.
- Tests updated so they no longer expect throw-by-design public behavior.

Acceptance:

- `rg "Never encodeBonyObject|Never decodeBonyObject|no registered fields yet" runtime-dart codegen` has no Dart public throw surface left, except historical test fixtures if explicitly justified.

### 10. Conformance Tests

Reservation:

- `runtime-dart/test/*writer*`
- `conformance/goldens/canonical-json/**` if committed fixtures are chosen
- helper script under `scripts/ci/`

Deliverables:

- Dart test coverage for JSON assets and representative `.bnb` assets via both
  `loadBonyJson` and `loadBonyBnb`.
- Fixed-point tests for canonical input.
- Value round-trip tests for valid model data.

Acceptance:

- Dart/Nim canonical JSON byte parity is asserted, not just semantic equality.
- The stale-fixture check is included in the final verification path.

### 11. Docs and Downstream Policy

Reservation:

- `docs/versioning.md`
- docs page for Dart writer and `.bnb` policy
- `docs/README.md` if a new page is added

Deliverables:

- `.bnb` Dart write policy.
- `bonyRegistryVersion` bump policy.
- Flashy adoption note with the final commit SHA after implementation.

Acceptance:

- A downstream maintainer can tell whether to repin by registry version,
  package version, or commit SHA, and knows that Dart JSON writing is supported.
- Documentation tasks are serialized through dependencies so concurrent agents
  do not edit the same policy sections independently.

### 12. Final Verification

Reservation:

- no source reservations unless failures require fixes

Required commands:

```bash
python3 codegen/generate.py --check
python3 -m unittest discover -s codegen -p 'test_*.py'
(cd runtime-dart && flutter test)
make test
```

Acceptance:

- All commands pass.
- Final response includes the commit SHA for Flashy to repin.
