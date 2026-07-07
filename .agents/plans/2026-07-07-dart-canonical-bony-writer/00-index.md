# Dart Canonical `.bony` Writer Plan

## Source

This plan addresses
`.agents/requests/2026-07-07-dart-canonical-bony-writer.md`.

The downstream blocker is Flashy replacing its temporary local writer with a
public deterministic writer from `package:bony/bony.dart`.

## Change Classification

Type: NEW_FEATURE with codegen/API cleanup and documentation decisions.

Primary deliverable:

- Export `writeBonyJson(SkeletonData) -> String` from `runtime-dart/lib/bony.dart`.

Required companion decisions:

- Resolve generated public codec stubs `encodeBonyObject` and
  `decodeBonyObject` by removing the aggregate throwing stubs from the generated
  Dart public surface. Keep registry metadata public.
- Record that Dart `.bnb` writing is explicitly out of scope for this change.
  Dart remains `.bnb` read-only until a dedicated binary-writer task ports and
  tests canonical byte emission.
- Use `BonyWriteException` as the public writer failure type for validation and
  emission failures, preserving the underlying cause where possible.
- Add `SkeletonData.copyWith` while touching the model surface, because Flashy
  currently keeps a local helper to avoid dropping new constructor fields.
- Document `bonyRegistryVersion` bump policy in `docs/versioning.md`.

## Plan Files

- `01-current-state.md`: repo facts, affected surfaces, and risk areas.
- `02-design.md`: implementation design for the Dart writer and related APIs.
- `03-task-breakdown.md`: Beads-sized tasks and dependency order.
- `04-verification.md`: exact acceptance gates and handoff checklist.
- `05-review-notes.md`: independent review outcomes and applied revisions.

## Non-Goals

- Do not change Nim writer behavior except to expose fixture output needed for
  Dart parity tests.
- Do not design texture packaging or slot blend-mode wire fields.
- Do not make a CLI writer surface for Dart.
- Do not implement Dart `.bnb` writing in this change.

## Success Summary

The change is complete when:

- `writeBonyJson(loadBonyJson(assetText))` is byte-identical to the Nim
  canonical JSON for every selected conformance asset.
- `loadBonyJson(writeBonyJson(data))` value-round-trips for valid data.
- Invalid `SkeletonData` is rejected before emission with a documented public
  `BonyWriteException`.
- `flutter test` passes in `runtime-dart`, and repo `make test` remains green.
- Flashy can delete or shrink `lib/export/bony/bony_exporter.dart` after
  repinning to the resulting bony commit.
