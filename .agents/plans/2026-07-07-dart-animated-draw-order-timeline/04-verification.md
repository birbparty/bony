# Verification

## Required Local Gates

Run from repo root unless noted:

```bash
python3 codegen/generate.py --check
python3 -m unittest discover -s codegen -p 'test_*.py'
(cd runtime-dart && flutter test)
make test
bd dep cycles
bd preflight
```

If implementation touches only docs, run at least:

```bash
python3 codegen/generate.py --check
bd preflight
```

## Focused Dart Tests

The implementation must add focused tests for:

- JSON parser accepts a valid draw-order timeline and exposes it through
  `AnimationClip.drawOrderTimeline`.
- JSON parser rejects:
  - unknown slot references;
  - duplicate offset slot names in one keyframe;
  - negative target indices;
  - target indices beyond slot count;
  - duplicate target indices after implicit zero offsets;
  - missing target indices after applying offsets;
  - empty declared timeline;
  - non-strict keyframe time order;
  - dynamic clipping ranges where a clipping slot moves to or after its
    `untilSlot`, or active ranges overlap after sampled draw order.
- `.bnb` decoder accepts equivalent data and rejects missing `drawOrderKeys`,
  duplicate draw-order timeline child records, and out-of-range slot indices.
- `sampleDrawOrderTimeline` covers before-first-key, between keys, after last
  key, and restore-to-setup. Before the first key, sampled order is setup slot
  order.
- `AnimationMixer` applies draw order as a thresholded stepped channel.
- `applyPose` preserves every `SkeletonData` field while reordering slots.
- `buildDrawBatches` batch order follows sampled slot order.
- Clipping ranges use the sampled slot order.

## Canonicalization Tests

When writer support exists, add tests for:

- Empty/absent `drawOrderTimeline` is omitted.
- Offset entries are emitted in setup slot order.
- Zero offsets are accepted by loaders but omitted by canonical writers.
- Legacy fixture output is byte-identical when no draw-order timeline exists.
- `loadBonyJson(writeBonyJson(data))` preserves draw-order values.

When writer support does not exist yet, the implementation must leave a clear
dependency note in the canonical writer plan or a Beads follow-up. Do not mark
writer round-trip acceptance complete without a writer.

## Conformance Acceptance

Minimum conformance fixture:

- three visible slots in setup order;
- explicit expected visual direction: index `0` is backmost/drawn first and
  larger indices draw later/in front;
- a key that swaps or moves one slot in front of another using offset entries
  for every displaced slot;
- a held interval proving no interpolation;
- a restore-to-setup key with `offsets: []`;
- expected batch slot-order samples at:
  - setup/rest;
  - first key time;
  - middle of held interval;
  - restore time.

If clipping is in scope for the same fixture, include a clip attachment whose
covered range changes observably when slot order changes. Otherwise add a
focused Dart unit test for clipping order and keep the conformance fixture
simple.

Do not commit `.bnb` conformance fixtures until Nim canonical conversion can
preserve `drawOrderTimeline` through `json-to-bnb` and `bnb-to-json`.

## Clean-Room Checklist

Before merge:

- New names and keys are documented in bony-owned docs/registry/spec files.
- `docs/PROVENANCE.md` records the draw-order timeline serialized names.
- No implementation task used third-party runtime source, generated schemas, or
  exact third-party wire layouts.
- Comparable product mentions are limited to capability category context.
- Flashy is not mentioned in public runtime API docs except optional downstream
  adoption notes outside the binding contract.

## Handoff Checklist

The final implementation response should include:

- bony commit SHA;
- whether JSON load, `.bnb` load, runtime evaluation, writer integration, and
  conformance are complete;
- any follow-up bead IDs for deferred Dart writer support;
- exact Dart API names for downstream repin;
- statement that Flashy can remove its local draw-order envelope only after it
  repins to the commit and any writer dependency it needs has landed.
