# Current State

## Request Summary

Flashy needs animated slot draw order so an animation clip can restack slots
over time. At the current bony commit (`239d091` in the request, still the head
of this workspace when this plan was written), Dart has no draw-order timeline
representation. Flashy therefore plans to store this data temporarily in a
Flashy-local editor envelope keyed by clip name.

This plan defines the upstream `bony` home for that data. The implementation
agent should treat Flashy as a consumer that will repin and delete a workaround,
not as a source of model concepts.

## Existing Dart Surfaces

Relevant files:

- `runtime-dart/lib/src/model/animation_model.dart`
- `runtime-dart/lib/src/model/skin_model.dart`
- `runtime-dart/lib/src/loader_animation_parsers.dart`
- `runtime-dart/lib/src/loader_validation.dart`
- `runtime-dart/lib/src/bnb_decoder.dart`
- `runtime-dart/lib/src/bnb_reader.dart`
- `runtime-dart/lib/src/anim.dart`
- `runtime-dart/lib/src/draw_batches.dart`
- `runtime-dart/test/m3_non_scalar_test.dart`
- `runtime-dart/test/m8_statemachine_test.dart`
- `runtime-dart/test/m19_event_story_test.dart`

Current facts:

- `AnimationClip` carries `boneTimelines`, `slotTimelines`,
  `deformTimelines`, and `eventTimelines`, but no draw-order timeline.
- `SlotTimelineKind` covers attachment/color/sequence channels only. Draw order
  should not be added as a per-slot `SlotTimelineKind`; it is clip-global.
- `EventTimeline` is the closest structural precedent: clip-owned, no target,
  ordered keyframes.
- `loadBonyJson` parses timeline arrays inside `_parseAnimations`; duration is
  computed as the max last-key time across existing timeline families.
- `_validateAnimations` currently validates bone timeline bone references and
  slot timeline slot references only.
- `_BnbAnimationBuilder` and `_animationDuration` already collect timeline
  families while decoding `.bnb`; adding a fifth family is mechanical but must
  preserve source order and duration calculation.
- `AnimationMixer._applyEntry` samples bone, slot, and deform timelines. Slot
  attachment/deform channels are thresholded by `track.mixAttachmentThreshold`
  and winner-take-style, not interpolated.
- `applyPose` returns a new `SkeletonData` with animated bones/slots and
  transient `deformOverrides`. It must preserve every constructor field when
  adding another posed field.
- `buildDrawBatches` iterates `data.slots` in order. Reordering the posed
  `slots` list is therefore the least invasive way to make rendered batches
  follow sampled draw order.

## Existing Format Surfaces

Relevant files:

- `docs/README.md`
- `docs/CLEANROOM.md`
- `docs/PROVENANCE.md`
- `docs/json-canonicalization.md`
- `docs/binary-canonicalization.md`
- `docs/load-validation-contract.md`
- `docs/drawbatch-raylib-contract.md`
- `docs/event-timeline-contract.md`
- `docs/deform-timeline-contract.md`
- `registry/key-ranges.md`
- `registry/wire.yml`
- `spec/defaults.yml`
- `spec/bony.schema.json`
- `spec/bony-wire.schema.json`
- `codegen/canonical_json_overrides.json`
- `codegen/schema.py`
- `codegen/test_generate.py`

Current facts:

- `registry/key-ranges.md` lists M2 as "World transforms, region attachments,
  draw order", but existing timeline records live in M3.
- `registry/wire.yml` defines `animationClip`, `boneTimeline`, `slotTimeline`,
  `deformTimeline`, and `eventTimeline` object families. The `animationClip`
  doc says child records are emitted in bone, slot, deform, event order.
- `.bnb` packed payload precedent:
  - bone/slot timelines use `timelineKeys`;
  - deform timelines use `deformKeys`;
  - event timelines use `eventKeys`.
- Canonical JSON currently omits empty optional timeline arrays. The new
  timeline must follow that rule so legacy clips stay byte-identical.

## Project Constraints

The implementation must stay inside bony's clean-room boundary:

- Use project-owned docs/spec/registry/codegen as binding sources.
- Comparable products can justify the capability category only.
- Do not fetch, inspect, or derive from Spine, DragonBones, Rive, Live2D, or
  other runtime source or generated format files.
- New identifiers, key allocations, packed layouts, and canonical ordering
  must be documented in bony-owned files and recorded in provenance.

## Affected Areas

- Runtime model: animation model and `SkeletonData` copy/rebuild surfaces.
- JSON loader: animation parser, schema, and validation diagnostics.
- `.bnb` reader: registry/codegen, packed payload decoder, animation builder,
  and semantic duration calculation.
- Nim reference paths: model/timeline types, JSON loader/writer, `.bnb`
  semantic encoder/decoder, mixer/evaluator, and CLI conversion commands needed
  by canonical and conformance gates.
- Mixer/runtime: timeline sampling, mixed pose state, track threshold behavior,
  and posed slot ordering.
- Draw batches and clipping: because clipping uses slot order ranges, tests
  must prove sampled order is used consistently.
- Canonicalization: JSON key order, default omission, offset normalization, and
  future writer integration.
- Conformance: one compact fixture/story that exercises restack and restore
  only after Nim reference paths can emit and consume it.

## Risk Areas

- Confusing animated draw order with a static slot z-index field.
- Reordering slots without preserving animated attachment changes, deforms,
  constraints, skins, nested rigs, and all other `SkeletonData` fields.
- Producing a valid visual order for region batches but forgetting clipping
  ranges and nested draw batches, both of which reason about slot order.
- Allowing ambiguous offset keyframes whose target indices are not a complete
  permutation after omitted slots are treated as setup positions.
- Adding JSON support but leaving `.bnb` read/decode, schema, or generated
  metadata inconsistent.
- Adding Dart support while leaving Nim canonical conversion unable to preserve
  the new field, then accidentally committing conformance fixtures the reference
  tooling cannot round-trip.
- Letting Flashy's editor-side z-index representation leak into bony's public
  model or docs.
