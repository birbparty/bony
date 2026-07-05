# bony Documentation Index

This directory contains architecture contracts, design spikes, governance
documents, and QA checklists for the bony project.

Documents listed under **Contracts** sections are binding specifications —
runtime implementations, the conformance harness, and tooling must follow them.
Design spikes and governance docs are informational.

> This index reflects the binding status of each document. It does not define
> that status — a doc's binding status is determined by its content and the bead
> that introduced it, not by its position in this index.

The `docs/prompts/` and `docs/spikes/` subdirectories hold exploratory material
(AI prompts, numeric spike scripts) and are intentionally not catalogued here.

---

## Determinism Contracts

These documents define the numeric and ordering rules that all runtimes and the
conformance harness must follow to produce identical results within tolerance.

| Document | What it defines |
|----------|----------------|
| [float-math-contract.md](float-math-contract.md) | Cross-runtime numeric tolerance (`1e-4`), float ordering rules, determinism scope |
| [transform-composition-contract.md](transform-composition-contract.md) | Local-to-world bone transform math, `transformMode` variants, degenerate fallback |
| [constraint-total-order.md](constraint-total-order.md) | Deterministic evaluation order for all runtime constraints |
| [physics-integrator-contract.md](physics-integrator-contract.md) | Deterministic physics constraint integration, float-order rules |

---

## Binary Format Contracts

Contracts governing the `.bnb` binary wire format, key spaces, and forward
compatibility. See also [registry/key-ranges.md](../registry/key-ranges.md) for
the milestone-to-key-range table.

| Document | What it defines |
|----------|----------------|
| [binary-canonicalization.md](binary-canonicalization.md) | Canonical `.bnb` byte emission for round-trip tools and the M6 byte-stability gate |
| [binary-toc-skip-semantics.md](binary-toc-skip-semantics.md) | `.bnb` table-of-contents skip rule for composite values (arrays of structs) |
| [binary-animation-state-machine-contract.md](binary-animation-state-machine-contract.md) | Binding overview and cross-link map for preserving animations/state machines in `.bnb` |
| [binary-animation-state-machine-object-families.md](binary-animation-state-machine-object-families.md) | Project-owned `.bnb` object-family decision for current animation and state-machine features |
| [binary-animation-state-machine-reference-semantics.md](binary-animation-state-machine-reference-semantics.md) | Binary index/reference domains for loading animation and state-machine records into the project semantic graph |
| [animation-state-machine-validation-ownership.md](animation-state-machine-validation-ownership.md) | Ownership matrix for animation/state-machine schema, decoding, loader validation, and runtime constructor checks |
| [nim-loaded-asset-shape.md](nim-loaded-asset-shape.md) | Nim aggregate loaded-asset shape for preserving animation/state-machine data while keeping `SkeletonData` APIs static |
| [header-hash-bounds.md](header-hash-bounds.md) | v1 decision for `SkeletonData.header.hash` and `header.bounds` |

---

## JSON Format Contracts

| Document | What it defines |
|----------|----------------|
| [json-canonicalization.md](json-canonicalization.md) | Canonical `.bony` JSON for authoring output and the M6 `json→bnb→json` idempotency gate |
| [load-validation-contract.md](load-validation-contract.md) | Load-time validation pass shared by JSON and binary loaders and the M6 fuzz gate |

`spec/bony.schema.json` describes the canonical `.bony` JSON surface. The flat
binary registry-object schema lives in `spec/bony-wire.schema.json`; see
[binary-animation-state-machine-contract.md](binary-animation-state-machine-contract.md)
for the animation/state-machine preservation-vs-playback boundary.

---

## Attachment Contracts

Contracts governing project-owned attachment record classes: their format, load
validation, and (where applicable) the deterministic runtime algorithm.

| Document | What it defines |
|----------|----------------|
| [clipping-attachment-contract.md](clipping-attachment-contract.md) | Slot-bound convex clipping attachment: format, load validation, `untilSlot`-inclusive range + no-overlap rule, packed `vertices` byte layout, and the (forward-referenced) deterministic Sutherland-Hodgman clip algorithm |
| [helper-geometry-attachment-contract.md](helper-geometry-attachment-contract.md) | Non-rendered point and bounding-box helper attachments: JSON/BNB shape, slot-reference validation, shared packed polygon `vertices` payload, and deterministic future helper-query math |
| [mesh-attachment-contract.md](mesh-attachment-contract.md) | Slot-bound deformable mesh attachment: format, load-validated `(a)-(g)` invariants, the three packed `meshVertices`/`meshUvs`/`meshTriangles` byte layouts, and the (forward-referenced) deterministic linear-blend skinning algorithm |
| [skin-attachment-set-contract.md](skin-attachment-set-contract.md) | First-class named skin attachment sets: top-level `skins[]`, required `"default"` fallback, `(slot, attachment)` to concrete attachment target bindings, lookup/fallback, validation, canonical JSON, and `.bnb` skin/skinEntry object shape |
| [deform-timeline-contract.md](deform-timeline-contract.md) | Clip-owned deform timeline animating a mesh attachment's per-vertex offsets: format, load-validated `(a)-(g)` invariants, the packed `deformKeys` byte layout (reusing the shared bone/slot curve tail), and the deterministic sampling algorithm plus first-class skin-resolution/cross-track mixing rules |
| [event-timeline-contract.md](event-timeline-contract.md) | Clip-owned (target-less) event timeline of keyframed application-facing events: format, load-validated invariants + `(a)-(e)` edge cases, the **non-decreasing** (not strict) time rule, the audio-metadata-only non-goal, the packed `eventKeys` byte layout (string-table-interned strings, svarint `intValue`, no curve tail), and the (forward-referenced, prompts 28–29) `animationEvents` dispatch output channel + incremental per-sample stepping model |

---

## Renderer Contracts

| Document | What it defines |
|----------|----------------|
| [drawbatch-raylib-contract.md](drawbatch-raylib-contract.md) | How the naylib renderer adapter consumes `DrawBatch`: blend modes, tint-black shader, clipping, atlas page handling |

---

## Importer Design Notes

Informational notes on importer targets. Clean-room designs from bony spec and
public capability-level knowledge only — no runtime source from third parties.

| Document | Scope |
|----------|-------|
| [dragonbones-importer-design.md](dragonbones-importer-design.md) | DragonBones importer first target: `_ske.json` wire format subset to bony |
| [lottie-importer-design.md](lottie-importer-design.md) | Lottie importer first target: Lottie JSON subset to bony animation timelines |

---

## Comparable Research

Informational capability surveys used for milestone planning. These are not
runtime contracts and must not be used as implementation source.

| Document | Scope |
|----------|-------|
| [comparable-feature-set.md](comparable-feature-set.md) | Capability-level feature set comparison for DragonBones, Spine, and Rive |

---

## Animation and State-Machine Provenance Notes

Provenance and boundary notes for the `.bnb` animation/state-machine contract
work.

| Document | Scope |
|----------|-------|
| [animation-state-machine-contract-boundaries.md](animation-state-machine-contract-boundaries.md) | Inventory of current project-owned Nim/Dart animation and state-machine runtime and JSON surfaces |
| [animation-state-machine-cleanroom-boundary.md](animation-state-machine-cleanroom-boundary.md) | Provenance and clean-room source boundary for designing `.bnb` animation/state-machine object families |

---

## Runtime Design Notes (Deferred)

Design notes for future runtime targets. No implementation in v1.

| Document | Scope |
|----------|-------|
| [csharp-runtime-design.md](csharp-runtime-design.md) | C# managed runtime: Unity/Godot embedder seams, codegen strategy, conformance-vector compatibility |

---

## Governance and Provenance

| Document | What it records |
|----------|----------------|
| [CLEANROOM.md](CLEANROOM.md) | Clean-room engineering policy: allowed sources, prohibited references, process |
| [PROVENANCE.md](PROVENANCE.md) | Implementation provenance policy, current sources of implementation truth |
| [versioning.md](versioning.md) | Versioning policy for format, Nim/Dart packages, and spec; breaking-change rules |
| [nim-dependency-license-scan.md](nim-dependency-license-scan.md) | Permissive-license audit for Nim runtime dependencies |

---

## QA Checklists

| Document | When to use |
|----------|-------------|
| [naylib-manual-visual-check.md](naylib-manual-visual-check.md) | After changing `runtime-nim/src/render/naylib*` or the `DrawBatch` contract — blend mode, tint-black, clipping visual cases |

---

## Related

- **[conformance/README.md](../conformance/README.md)** — cross-runtime numeric
  golden contract, milestone coverage table, gate descriptions.
- **[registry/key-ranges.md](../registry/key-ranges.md)** — milestone-to-key-range
  table for `.bnb` binary key spaces.
- **[registry/README.md](../registry/README.md)** — binary wire format registry
  overview, key-space rules, property backing types.
- **[spec/](../spec/)** — JSON Schema and human-readable specification documents.
