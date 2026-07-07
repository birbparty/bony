# Request: Public deterministic `.bony` writer in the Dart runtime

- **Requested by:** `flashy` planning in `~/git/flashy` (plan set
  `.agents/plans/bony-updates-july-7/`, tracking bead `flashy-12ki`;
  original ask recorded in
  `~/git/flashy/docs/specs/bony-migration/bony-upstream-requests.md`
  requests #2 and #5, beads `flashy-tenl` / follow-ups)
- **Date:** 2026-07-07
- **Priority:** High — Flashy's maintained `.bony` export and `.bnr` v2
  persistence cannot close as complete while they depend on a Flashy-local
  hand-written serializer; `bony-io-contract.md` on the Flashy side records
  that dependency as explicitly temporary.
- **Target repo:** `~/git/bony` (`runtime-dart`)
- **Consumer:** `~/git/flashy` (Flutter editor; local path dependency on
  `runtime-dart`, currently re-pinning `db1553eb` → `a0467e9`)

## Background

At bony `a0467e9`, `runtime-dart` exposes loaders and models only. There is no
public writer:

- `encodeBonyObject` / `decodeBonyObject`
  (`runtime-dart/lib/src/generated/wire.dart:648-655`) still throw
  `UnsupportedError` ("no registered fields yet"); their return type is now
  `Never`, so the gap is at least statically visible, but they remain public
  API that can never succeed.
- No `writeBonyJson(SkeletonData)` or `.bnb` encoder exists anywhere under
  `runtime-dart/lib/`.

Meanwhile the prerequisites for a writer have landed since the previous pin:

- Full canonical-emission contracts are published:
  `docs/json-canonicalization.md` (total key order, default omission, float32
  quantization, `-0` normalization, angle rules — now covering attachments,
  skins, animations, and state machines), `docs/binary-canonicalization.md`,
  and `codegen/canonical_json_overrides.json`.
- The **Nim** reference runtime gained read **and write** support
  (`runtime-nim` jsonio/binary work, iterations ~177-178).
- Loader-side validation was consolidated into
  `runtime-dart/lib/src/loader_validation.dart`, which a writer can reuse to
  validate before emission.
- The registry carries writer-relevant metadata: `bonyPropertyDefaults` with
  `omitWhenDefault`, `bonyRequiredProperties`, `bonyIsRequiredProperty()`,
  and enum ordinal contracts (`bonyOrdinalEnums`).

Because no Dart writer exists, Flashy maintains a hand-written canonical
serializer (`~/git/flashy/lib/export/bony/bony_exporter.dart`,
`exportBonyMap`/`exportBonyJson`) that mirrors loader defaults by hand and
must chase every schema change manually — this is the exact class of drift
the shared registry exists to prevent. The precedent is good: Flashy's
previous upstream ask (`BoneData.copyWith`, bead `flashy-pobr`) was delivered
at HEAD and Flashy is now adopting it.

## Blocking asks

### 1. Public `writeBonyJson(SkeletonData) → String` in `runtime-dart`

Exported from `runtime-dart/lib/bony.dart`. Required behavior:

- Deterministic, byte-stable output following `docs/json-canonicalization.md`
  exactly (key order, default omission per `omitWhenDefault`, float32
  quantization through the same `quantizeF32` used elsewhere, `-0.0` → `0.0`,
  angle conventions).
- Validates before emission (reuse the `loader_validation.dart` rules) and
  throws a documented error type on invalid data rather than emitting a file
  other runtimes would reject.
- Round-trip guarantee: `loadBonyJson(writeBonyJson(d))` is value-equal to
  `d` for any `d` that passes validation, and
  `writeBonyJson(loadBonyJson(s))` is a fixed point for canonical `s`.
- Byte-parity with the Nim writer over the shared `conformance/` assets,
  enforced by a conformance check, so Dart- and Nim-written files are
  indistinguishable.

### 2. Resolve the generated codec stubs

`encodeBonyObject`/`decodeBonyObject` should either be implemented from the
registry metadata or be removed/renamed out of the public surface with the
reservation documented. A public API whose only behavior is to throw
`UnsupportedError` forces every consumer to discover the gap at runtime.

### 3. `.bnb` encode decision

Either provide `writeBonyBnb(SkeletonData) → Uint8List` (following
`docs/binary-canonicalization.md`), or document explicitly that `.bnb` is
read-only interchange for downstream editors and JSON is the sole write
format. Flashy's `.bnb` export bead (`flashy-gl68`) is blocked on this
*decision*, not necessarily on the encoder itself.

## Non-blocking asks

- **`SkeletonData.copyWith`**: `SkeletonData` now has 20 constructor fields;
  Flashy maintains a local exhaustive copy helper to avoid silently dropping
  new collections during editor commands. Same motivation and shape as the
  delivered `BoneData.copyWith`.
- **Compatibility signal**: document the `bonyRegistryVersion` bump policy
  (when it increments, what consumers should do) so downstream pins can key
  off it instead of commit SHAs alone.

## Out of scope

- Texture sidecar/packaging conventions — partially addressed by
  `docs/atlas-region-texture-contract.md`; any remainder is a separate
  request.
- Slot blend-mode wire property — Flashy will file that separately
  (its envelope `slotBlendModes` + screen blend need a wire home; bony
  `SlotData` has no blend field and `DrawBatch.blendMode` is hardcoded
  `'normal'`).
- Writer APIs in the CLI or Nim runtime (already present or out of Flashy's
  consumption surface).

## Acceptance

- `writeBonyJson` exported from `package:bony/bony.dart`, with the round-trip
  and validation behavior above covered by `runtime-dart` tests
  (`flutter test` in `runtime-dart` passes).
- Dart↔Nim byte-parity over the conformance assets is asserted by a
  conformance script/vector.
- The generated codec stubs no longer throw-by-design in public API (either
  implemented or removed/documented).
- A `.bnb` write policy is recorded in `docs/` either way.
- A commit SHA is recorded in the response for Flashy to re-pin; on adoption
  Flashy deletes `lib/export/bony/bony_exporter.dart` (or reduces it to a
  thin adapter) and closes upstream requests #2/#5 in
  `docs/specs/bony-migration/bony-upstream-requests.md`.

## References

- Flashy ask + contracts: `~/git/flashy/docs/specs/bony-migration/bony-upstream-requests.md`
  (#2 "Dart canonical `.bony` writer", #5 "Runtime editor integration APIs"),
  `~/git/flashy/docs/specs/bony-migration/bony-io-contract.md`
- Flashy temporary writer: `~/git/flashy/lib/export/bony/bony_exporter.dart`
- Bony contracts: `docs/json-canonicalization.md`,
  `docs/binary-canonicalization.md`, `codegen/canonical_json_overrides.json`,
  `docs/load-validation-contract.md`
- Codec stubs: `runtime-dart/lib/src/generated/wire.dart:648-655`
