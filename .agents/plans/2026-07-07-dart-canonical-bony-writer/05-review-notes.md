# Review Notes

This file records independent planning reviews and revisions applied before the
plan was handed off for implementation.

## Reviewer A

Concerns raised:

1. Nim canonical fixture generation was underspecified and could allow Dart
   tests to pass against stale fixtures.
2. The fixture oracle depended on the Dart writer, even though Nim fixtures
   should be generated before implementation.
3. Packed byte-backed fields were listed as a risk but not owned by a task.
4. Verification covered JSON loader parity but not
   `writeBonyJson(loadBonyBnb(bytes))`.
5. Number formatting needed Nim-derived golden cases for exponent notation,
   safe-integer boundaries, and large/small doubles.
6. Verification commands used `cd runtime-dart && flutter test` followed by
   `make test`, which would run `make test` from the wrong directory if pasted
   into one shell.

## Reviewer B

Concerns raised:

1. The public writer error type was unresolved.
2. Codec stub cleanup was left as a decision tree.
3. The `.bnb` policy was left as optional implementation scope.
4. Documentation beads could conflict because `.bnb` policy, version policy,
   and Flashy handoff were independently ready.
5. Several acceptance criteria used non-measurable phrasing.

## Applied Revisions

- Chose `BonyWriteException` as the public writer failure type.
- Chose removal of generated Dart aggregate throwing stubs
  `encodeBonyObject` and `decodeBonyObject` from the public generated surface.
- Fixed Dart `.bnb` writing as out of scope for this change; Dart remains
  read-only for `.bnb`.
- Added a canonical fixture oracle task before writer implementation, with a
  required stale-fixture check against current Nim output.
- Added a dedicated packed-payload reconstruction task.
- Added `.bnb` loader parity assertions for
  `writeBonyJson(loadBonyBnb(bytes))`.
- Added numeric golden requirements for exponent notation, safe-integer
  boundaries, and large/small doubles.
- Serialized overlapping docs/handoff beads through dependencies.
- Replaced vague acceptance wording with explicit tests and checks.
- Fixed verification commands to use `(cd runtime-dart && flutter test)`.
