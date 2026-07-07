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

EPIC=$(bd create "Epic: Dart animated draw-order timeline" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress

CONTRACT=$(bd create "Write bony-owned draw-order timeline contract covering JSON shape, validation, .bnb payload, runtime semantics, clean-room provenance, and non-goals" -t task -p 0 --label docs --parent "$EPIC" --silent)
REGISTRY=$(bd create "Allocate registry/codegen/schema support for drawOrderTimeline and drawOrderKeys using the animation timeline key family" -t task -p 0 --label impl --parent "$EPIC" --silent)
MODEL=$(bd create "Add Dart DrawOrderTimeline model types and optional AnimationClip.drawOrderTimeline with duration support" -t task -p 0 --label impl --parent "$EPIC" --silent)
JSON_LOAD=$(bd create "Parse and validate drawOrderTimeline in Dart JSON animation loader with unknown-slot and permutation diagnostics" -t task -p 0 --label impl --parent "$EPIC" --silent)
BNB_LOAD=$(bd create "Decode drawOrderTimeline from .bnb drawOrderKeys payload in Dart and share validation with JSON/direct model data" -t task -p 1 --label impl --parent "$EPIC" --silent)
SAMPLER=$(bd create "Implement Dart draw-order timeline sampler and focused unit tests for stepped hold, restore-to-setup, and invalid permutations" -t task -p 0 --label impl --parent "$EPIC" --silent)
MIXER=$(bd create "Wire sampled draw order through AnimationMixer/MixedPose/applyPose so posed SkeletonData.slots drives buildDrawBatches order" -t task -p 0 --label impl --parent "$EPIC" --silent)
DRAW_TESTS=$(bd create "Add Dart runtime tests proving animated draw order reorders draw batches and uses sampled order for clipping ranges" -t task -p 0 --label testing --parent "$EPIC" --silent)
NIM_FORMAT=$(bd create "Implement Nim draw-order timeline model, JSON load/write, .bnb semantic encode/decode, and CLI conversion preservation" -t task -p 0 --label impl --parent "$EPIC" --silent)
NIM_RUNTIME=$(bd create "Implement Nim draw-order timeline sampling/evaluation and clipping-validity checks matching the Dart semantics" -t task -p 0 --label impl --parent "$EPIC" --silent)
CANON=$(bd create "Update canonicalization docs and writer-facing rules for drawOrderTimeline omission, key order, offset normalization, and future writer integration" -t task -p 1 --label docs --parent "$EPIC" --silent)
CONFORMANCE=$(bd create "Add a compact animated draw-order conformance asset/story with setup, restack, held, restore, and canonical JSON/BNB preservation samples" -t task -p 1 --label testing --parent "$EPIC" --silent)
HANDOFF=$(bd create "Record downstream adoption handoff: bony commit SHA, Dart API shape, and Flashy envelope deletion conditions without editing Flashy" -t task -p 2 --label docs --parent "$EPIC" --silent)
VERIFY=$(bd create "Run final verification for codegen, Dart tests, repo test gate, bead graph hygiene, and clean-room/provenance checklist" -t task -p 0 --label testing --parent "$EPIC" --silent)

bd dep add "$REGISTRY" "$CONTRACT"
bd dep add "$MODEL" "$CONTRACT"
bd dep add "$JSON_LOAD" "$MODEL"
bd dep add "$JSON_LOAD" "$REGISTRY"
bd dep add "$BNB_LOAD" "$MODEL"
bd dep add "$BNB_LOAD" "$REGISTRY"
bd dep add "$BNB_LOAD" "$JSON_LOAD"
bd dep add "$SAMPLER" "$MODEL"
bd dep add "$MIXER" "$SAMPLER"
bd dep add "$MIXER" "$JSON_LOAD"
bd dep add "$DRAW_TESTS" "$MIXER"
bd dep add "$DRAW_TESTS" "$BNB_LOAD"
bd dep add "$NIM_FORMAT" "$REGISTRY"
bd dep add "$NIM_FORMAT" "$CONTRACT"
bd dep add "$NIM_RUNTIME" "$NIM_FORMAT"
bd dep add "$NIM_RUNTIME" "$SAMPLER"
bd dep add "$CANON" "$REGISTRY"
bd dep add "$CANON" "$JSON_LOAD"
bd dep add "$CONFORMANCE" "$DRAW_TESTS"
bd dep add "$CONFORMANCE" "$CANON"
bd dep add "$CONFORMANCE" "$NIM_FORMAT"
bd dep add "$CONFORMANCE" "$NIM_RUNTIME"
bd dep add "$HANDOFF" "$CONFORMANCE"
bd dep add "$VERIFY" "$DRAW_TESTS"
bd dep add "$VERIFY" "$CANON"
bd dep add "$VERIFY" "$CONFORMANCE"
bd dep add "$VERIFY" "$NIM_RUNTIME"

echo "Created epic $EPIC"
echo "Initial work:"
bd ready
```

## Task Details

### 1. Contract and Provenance

Reservation:

- `docs/draw-order-timeline-contract.md`
- `docs/README.md`
- `docs/PROVENANCE.md`
- `docs/CLEANROOM.md` only if a new clean-room exception is needed

Deliverables:

- Binding contract for the draw-order timeline.
- Explicit statement that setup `slots[]` order is the baseline.
- JSON and `.bnb` shape, validation rules, runtime sampling, clipping
  interaction, canonicalization rules, and non-goals.
- Provenance entry explaining project-owned names and key allocations.

Acceptance:

- The contract can be implemented without reading third-party runtime source or
  generated schemas.
- The docs distinguish animated draw order from static slot stacking.
- Flashy is mentioned only as adoption context, if at all.

### 2. Registry, Schema, and Codegen

Reservation:

- `registry/wire.yml`
- `spec/defaults.yml`
- `codegen/canonical_json_overrides.json`
- `codegen/schema.py`
- `codegen/test_generate.py`
- generated files under `runtime-dart/lib/src/generated/`,
  `runtime-nim/src/bony/generated/`, and `spec/`

Deliverables:

- `drawOrderTimeline` object family.
- `drawOrderKeys` packed bytes property with metadata pointing to the contract
  anchor.
- `animationClip` child-order docs updated to include draw-order timelines.
- Project JSON schema includes optional `drawOrderTimeline`.
- Schema/codegen keeps `drawOrderTimeline` as a singular nested
  `animationClip` property and does not create an unintended root collection.
- Generated Dart/Nim wire metadata is refreshed.

Acceptance:

- Uses only the allocated range from `registry/key-ranges.md`.
- Documents the M3 timeline-family allocation decision.
- `python3 codegen/generate.py --check` passes after regeneration.
- `python3 -m unittest discover -s codegen -p 'test_*.py'` passes.

### 3. Dart Model

Reservation:

- `runtime-dart/lib/src/model/animation_model.dart`
- `runtime-dart/lib/src/model.dart`
- tests that construct `AnimationClip`

Deliverables:

- `DrawOrderOffset`, `DrawOrderKeyframe`, and `DrawOrderTimeline`.
- Optional `AnimationClip.drawOrderTimeline`.
- Duration calculation includes the draw-order last key time.

Acceptance:

- Existing Dart tests compile without requiring call-site churn.
- New model tests prove construction, equality-by-field expectations where
  relevant, and duration behavior.

### 4. JSON Loader and Validation

Reservation:

- `runtime-dart/lib/src/loader_animation_parsers.dart`
- `runtime-dart/lib/src/loader_validation.dart`
- `runtime-dart/lib/src/loader_timeline_helpers.dart`
- `runtime-dart/test/*animation*`
- `runtime-dart/test/*validation*`

Deliverables:

- Parser for `drawOrderTimeline`.
- Shared validator for direct model, JSON, and `.bnb`.
- Diagnostics for unknown slots, duplicate slots, invalid target indices,
  duplicate target indices, missing target indices, negative times, empty
  timeline, non-strict time order, and invalid dynamic clipping ranges.

Acceptance:

- `loadBonyJson` rejects an unknown slot with a diagnostic containing
  `drawOrderTimeline` and `unknown slot`.
- Restore-to-setup keyframes with `offsets: []` load successfully.
- A partial keyframe that collides with an absent slot is rejected unless the
  displaced slot is also explicitly offset.
- Explicit `offset: 0` entries load successfully but normalize away.

### 5. `.bnb` Decoder

Reservation:

- `runtime-dart/lib/src/bnb_decoder.dart`
- `runtime-dart/lib/src/bnb_reader.dart`
- `runtime-dart/test/*bnb*`

Deliverables:

- Decode `drawOrderTimeline` child records under the active animation clip.
- Packed payload reader for `drawOrderKeys`.
- `_BnbAnimationBuilder` stores at most one draw-order timeline per clip.
- `.bnb` duration calculation includes draw-order keys.

Acceptance:

- Missing `drawOrderKeys` is rejected.
- Duplicate draw-order timeline child records under one clip are rejected.
- `.bnb` unknown/out-of-range slot indices are rejected before model creation.
- JSON and `.bnb` versions of the same fixture produce equivalent
  `AnimationClip.drawOrderTimeline` values.

### 6. Sampler and Mixer

Reservation:

- `runtime-dart/lib/src/anim.dart`
- `runtime-dart/test/*draw_order*`
- existing animation/mixer tests if touched

Deliverables:

- Pure `sampleDrawOrderTimeline` helper.
- Mixed pose support for a sampled slot-name order.
- `AnimationMixer._applyEntry` samples draw order under
  `mixAttachmentThreshold`.
- `applyPose` returns a skeleton whose `slots` list follows the sampled order
  while preserving attachment changes and every other `SkeletonData` field.

Acceptance:

- Tests cover before-first-key, between keys, after last key, and restore to
  setup order.
- Multi-track behavior is documented and tested as thresholded last-winner
  behavior consistent with attachment/deform channels.
- Regression tests ensure IK, transform, physics constraints, mesh/clipping
  attachments, skins, animations, state machines, and deform overrides survive
  a draw-order-only pose.

### 7. Draw Batch and Clipping Tests

Reservation:

- `runtime-dart/lib/src/draw_batches.dart` only if a bug forces a local change
- `runtime-dart/test/*draw_order*`
- `conformance/assets/**` if adding fixture assets
- `conformance/goldens/**` if adding goldens

Deliverables:

- A minimal two/three slot asset proving rendered batch order changes over
  time.
- A clipping case proving animated slot order is the order used for clip ranges.

Acceptance:

- `buildDrawBatches(applyPose(data, pose)).map((b) => b.slot)` matches the
  expected sampled order.
- Clipping tests fail if clipping still uses setup order after a draw-order pose.
- Tests cover invalid dynamic clip ranges: draw-order keys that move a clipping
  slot to or after `untilSlot`, or create overlapping active clip ranges, are
  rejected by validation.

### 8. Nim Reference Support

Reservation:

- `runtime-nim/src/bony/anim/**`
- `runtime-nim/src/bony/jsonio/**`
- `runtime-nim/src/bony/binary/semantic/**`
- `cli/bony_cli.nim`
- `runtime-nim/tests/**`

Deliverables:

- Nim model/timeline constructors and validators matching the Dart contract.
- Nim JSON load and canonical JSON emission.
- Nim `.bnb` semantic encode/decode in animation clip child order:
  bone, slot, draw-order, deform, event.
- CLI conversion preserves the new timeline through JSON and `.bnb`.
- Nim runtime/mixer sampling matches Dart before-first/setup, stepped hold, and
  restore semantics.

Acceptance:

- Nim tests cover JSON load/write, `.bnb` round trip, runtime sampled order, and
  clipping-range validation.
- No `.bnb` conformance fixture is added before these paths are green.

### 9. Canonicalization and Writer Integration

Reservation:

- `docs/json-canonicalization.md`
- `docs/binary-canonicalization.md`
- `runtime-dart/lib/src/writer.dart` only if the canonical writer branch has
  landed
- writer tests only if writer exists

Deliverables:

- Document omission when empty/absent.
- Document key order and offset normalization.
- Document `.bnb` canonical object order: animation clip child records in
  bone, slot, draw-order, deform, event order.
- Document that zero offsets are accepted by readers but omitted by canonical
  writers.
- If `writeBonyJson` already exists, add writer emission and round-trip tests.
- If not, file or leave an explicit dependency note for the writer epic.

Acceptance:

- Legacy assets without draw order remain byte-identical through canonical
  writer paths once writer support exists.
- A draw-order timeline round-trips value-equivalent through
  `loadBonyJson(writeBonyJson(data))` when writer support exists.

### 10. Conformance and Handoff

Reservation:

- `conformance/assets/**`
- `conformance/goldens/**`
- `conformance/README.md`
- `.agents/requests/` only for follow-up requests if needed

Deliverables:

- Draw-order story fixture with setup, restacked, held, and restored samples.
- Golden data that records batch slot order at selected times.
- Handoff note with resulting bony commit SHA.

Acceptance:

- The final verification bead cannot close while cross-runtime parity is
  ambiguous. Nim reference support is implemented and green before conformance
  fixtures are committed.

### 11. Final Verification

Reservation:

- no source reservations unless fixing verification failures

Deliverables:

- Run and record:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `cd runtime-dart && flutter test`
  - `make test`
  - `bd dep cycles`
  - `bd preflight`
- Close finished beads and push git plus beads data.

Acceptance:

- All gates pass or failures have dedicated follow-up beads and are not part of
  the claimed acceptance.
