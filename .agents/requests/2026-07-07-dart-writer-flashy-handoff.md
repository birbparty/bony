# Dart Writer Flashy Adoption Handoff

This note closes the Flashy-facing adoption path for the public Dart canonical
`.bony` writer request.

## Resulting Bony Commit

Repin Flashy's bony dependency to:

`f3653dbbc516bfc26727e86d7e992a2996df532f`

That commit is on `origin/main` and includes:

- `writeBonyJson(SkeletonData data)` exported from `package:bony/bony.dart`.
- Pre-write validation through the shared Dart `SkeletonData` validator.
- Canonical `.bony` JSON emission for the current serialized Dart model.
- Dart writer parity tests for JSON and `.bnb` fixtures against Nim-generated
  canonical JSON goldens.
- The runtime-dart `.bnb` policy note: Dart loads `.bnb` and can project it to
  canonical `.bony` JSON, but does not expose a Dart `.bnb` binary writer in
  this change.
- Final verification record in
  `.agents/requests/2026-07-07-dart-writer-final-verification.md`.

## Flashy Dependency Repin

Flashy should update its local/path/git dependency for bony's Dart package to
the commit above, then run its normal export and `.bnr` persistence gates.

After repin, Flashy writer code should call:

```dart
final jsonText = writeBonyJson(skeletonData);
```

Invalid `SkeletonData` will throw `BonyWriteException` with the underlying
validation error attached as `cause`.

## Temporary Exporter Deletion Path

Flashy's temporary writer at:

`~/git/flashy/lib/export/bony/bony_exporter.dart`

can be deleted outright if its only remaining job is canonical `.bony` JSON
serialization. If it also owns Flashy-specific orchestration, file naming, or UI
export flow, reduce it to a thin adapter around `writeBonyJson` and delete its
hand-written bony field/default/string/number serialization logic.

The temporary exporter should not continue to duplicate bony's canonical JSON
field ordering or default omission rules after the repin.

## `.bnb` Follow-Up

Direct Dart `.bnb` byte emission is not part of this adoption handoff. If Flashy
still needs local binary export after adopting `writeBonyJson`, track that
through `bony-7pom` instead of extending the JSON writer.

