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
| [header-hash-bounds.md](header-hash-bounds.md) | v1 decision for `SkeletonData.header.hash` and `header.bounds` |

---

## JSON Format Contracts

| Document | What it defines |
|----------|----------------|
| [json-canonicalization.md](json-canonicalization.md) | Canonical `.bony` JSON for authoring output and the M6 `json→bnb→json` idempotency gate |
| [load-validation-contract.md](load-validation-contract.md) | Load-time validation pass shared by JSON and binary loaders and the M6 fuzz gate |

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
