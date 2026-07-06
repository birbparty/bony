# /big-change prompt - contract (skinRequired activation)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 1**. Can run independently.
> **Candidate category:** frontier.

---

/big-change Define the project-owned skinRequired activation contract for active-skin bones and constraints.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony` already has first-class skin attachment sets and active-skin attachment
lookup, but the current skin contract explicitly excludes `skinRequired` and
skin-owned bones/constraints. Other binding contracts already reserve behavior
for inactive `skinRequired` constraints: `docs/constraint-total-order.md`
requires inactive constraints to keep their canonical update-cache position, and
`docs/physics-integrator-contract.md` requires inactive physics constraints not
to advance accumulators and to reset when reactivated.

Write the contract slice only. Create a binding document that defines the
project-owned semantics for `skinRequired` activation across bones and the
existing constraint families. Ground the design in the local binding spec's
`skinRequired` and active-skin concepts, the existing `skins[]` lookup model,
the constraint ordering contract, and the physics integrator contract. Do not
edit registry keys, schemas, generated files, Nim runtime code, Dart runtime
code, conformance assets, or importers in this slice.

The contract should define:

- The active-skin membership model for required bones and required IK,
  transform, path, and physics constraints.
- How `"default"` skin membership participates when a non-default skin is
  active, and what happens when a required item is not included by the active
  membership set.
- The runtime effect of inactive required bones on slots, attachments, child
  bones, helper targets, nested-rig host slots, and draw-batch emission.
- The runtime effect of inactive required constraints on total-order caches,
  stateless solver evaluation, stateful physics accumulators, and reactivation.
- Load-time validation requirements for unknown membership references,
  duplicate membership entries, parent/child bone membership consistency, and
  constraints whose bones are inactive.
- The future serialized surface that a later format prompt should implement,
  without assigning keys yet. If the contract introduces net-new public
  identifiers beyond the local spec's existing `skinRequired` term, record their
  project-owned provenance.
- Conformance scenarios for later implementation prompts, including an inactive
  constraint that preserves later active constraint ordering and an inactive
  physics constraint that does not advance state.

Keep this as a contract/review milestone. It should leave an implementer with
clear enough semantics to file later format/load, Nim runtime, conformance, and
Dart parity prompts without having to make policy choices during implementation.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local binding spec: /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md
- Current skin contract: docs/skin-attachment-set-contract.md
- Constraint ordering: docs/constraint-total-order.md
- Physics inactive-state requirements: docs/physics-integrator-contract.md
- Load validation: docs/load-validation-contract.md
- Transform composition and bone hierarchy: docs/transform-composition-contract.md
- Runtime models for context only: runtime-nim/src/bony/model.nim,
  runtime-dart/lib/src/model.dart
- Runtime draw/constraint seams for context only: runtime-nim/src/bony/transform.nim,
  runtime-dart/lib/src/transform.dart
- Beads: bony-hfa2

**Success Criteria**
- `docs/skin-required-activation-contract.md` is created and marked binding.
- `docs/README.md` lists the new contract in the appropriate binding-contract
  section.
- `docs/skin-attachment-set-contract.md` links to the new contract and keeps its
  existing attachment-set scope clear.
- `docs/constraint-total-order.md` and `docs/physics-integrator-contract.md`
  either link to the new contract or are confirmed to already say enough.
- The contract defines active membership, inactive bone behavior, inactive
  constraint behavior, physics reactivation/reset behavior, load-validation
  rules, future serialized-surface requirements, and later conformance
  scenarios.
- `docs/CLEANROOM.md` and `docs/PROVENANCE.md` are updated only if the contract
  introduces net-new serialized/public identifiers; any such entry must explain
  the names from the local spec and project-owned skin/constraint model.
- Verification: docs/contract-only slice; run `git diff --check`.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not add DragonBones or Lottie importer mapping.
- Do not edit `registry/wire.yml`, `registry/key-ranges.md`,
  `spec/defaults.yml`, generated schemas, generated wire files, runtime code,
  CLI code, or conformance assets in this contract slice.
- Do not implement active-skin filtering, physics-state changes, or runtime
  draw-batch behavior in this slice.
- Keep the slice small enough for one contract-focused implementation session.
