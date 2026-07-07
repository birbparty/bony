# Dart Animated Draw-Order Timeline Plan

## Source

This plan addresses
`.agents/requests/2026-07-07-dart-animated-draw-order-timeline.md`.

The motivating downstream consumer is Flashy, but the planned change is a
`bony` format/runtime feature: a clip-global animated draw-order timeline in
the Dart runtime model, loaders, evaluator, canonical contracts, and tests.
Flashy's temporary envelope field is only adoption context and must not shape
the `bony` API, field names, or wire layout.

## Change Classification

Type: NEW_FEATURE with format-contract, registry/codegen, Dart runtime, and
canonicalization work.

Primary deliverable:

- Add a `bony`-owned, clip-global draw-order timeline to `AnimationClip` and
  evaluate it in Dart so `buildDrawBatches` sees the sampled slot order.

Required companion decisions:

- Mint a project-owned draw-order timeline contract under `docs/`, including
  JSON shape, `.bnb` packed payload, validation rules, and clean-room
  provenance.
- Allocate registry keys from the animation timeline family, documenting why
  an animated draw-order record belongs with M3 timeline records even though
  the broader draw-order capability is mentioned in the M2 key-range scope.
- Keep static per-slot stacking overrides out of scope. The setup `slots[]`
  order remains the baseline order.
- Keep Flashy editor concepts out of the model. No `FlashyEditorEnvelope`,
  per-editor z-index rows, DragonBones importer degradation, or UI terminology
  belongs in this change.
- Treat Dart `.bnb` writing as dependent on the canonical writer track, but do
  not treat the format feature as complete until Nim canonical JSON/BNB paths
  can preserve the timeline. Nim remains the reference for canonical conversion
  and conformance gates.

## Plan Files

- `01-current-state.md`: repo facts, affected surfaces, and risks.
- `02-design.md`: proposed `bony` model, JSON/BNB shape, validation, and runtime
  semantics.
- `03-task-breakdown.md`: Beads-sized implementation graph for another agent.
- `04-verification.md`: exact acceptance gates and handoff checklist.
- `05-review-notes.md`: independent review outcomes and applied revisions.

## Non-Goals

- Do not implement Flashy's authoring timeline, envelope workaround deletion,
  DragonBones export/import behavior, or Flutter UI changes.
- Do not add a static `SlotData.zOrder` or any persistent static slot stacking
  override.
- Do not derive names, layouts, or algorithms from third-party runtime source or
  generated schemas. Comparable products justify only the capability category.
- Do not broaden this into slot blend modes. Blend modes are a sibling request.
- Do not require Dart `.bnb` write support before the separate canonical writer
  work is ready; do require Nim canonical support before adding `.bnb`
  conformance fixtures or claiming format completion.

## Success Summary

The change is complete when:

- Dart `AnimationClip` exposes a clip-global draw-order timeline with stepped
  keyframes.
- `loadBonyJson` and `loadBonyBnb` parse the timeline and reject unknown slots
  or invalid permutations with documented diagnostics.
- The Dart mixer samples the timeline with hold semantics and returns draw
  batches in the sampled order, preserving setup/list order for absent slots
  only when the resulting keyframe remains a valid permutation.
- Canonical JSON docs/schema omit the timeline when empty, preserving legacy
  byte output, and define deterministic key order and offset normalization.
- Conformance assets include a small animated draw-order story with setup,
  restacked, held, and restore-to-setup samples, gated by Nim reference support.
- Final handoff records the bony commit SHA for downstream repinning.
