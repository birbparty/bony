# /big-change prompt - format (skinRequired activation surface)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 4**. Must land before
> `45-runtime-nim-skin-required-activation.md`.
> **Candidate category:** frontier.

---

/big-change Add the serialized format and load surface for skinRequired activation.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Implement the format/load slice required by
`docs/skin-required-activation-contract.md`. The contract is already binding but
is currently contract-only: `BoneData`, `IkConstraintData`,
`TransformConstraintData`, `PathConstraintData`, `PhysicsConstraintData`, and
`SkinData` do not yet carry `skinRequired` flags or skin-owned membership lists.

Add the project-owned serialized surface and loader/model support for:

- A `skinRequired` boolean on bones and each existing constraint family.
- Skin-owned required-item membership lists for bones, IK constraints,
  transform constraints, path constraints, and physics constraints.
- JSON and `.bnb` load/emit support in both Nim and Dart.
- Load validation for the contract's membership rules before runtime filtering
  exists.
- Generated schema/default/wire freshness.

This is not the runtime filtering milestone. The existing runtime may continue
to evaluate all loaded bones and constraints after this slice; it must simply
preserve, validate, and round-trip the new metadata so the Nim runtime slice can
consume it next.

Suggested project-owned JSON names are `skinRequired` on bone/constraint
records and skin fields named by the existing typed domains (`bones`,
`ikConstraints`, `transformConstraints`, `pathConstraints`,
`physicsConstraints`). If implementation chooses different names to avoid a
real local conflict, document the choice in the same slice and update
`docs/CLEANROOM.md` / `docs/PROVENANCE.md`. Do not copy names, field grouping,
or layout from any third-party runtime or file format.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local binding spec: /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md
- Binding contract: docs/skin-required-activation-contract.md
- Current skin surface: docs/skin-attachment-set-contract.md
- Registry rules: registry/README.md, registry/key-ranges.md, registry/wire.yml
- Defaults/codegen: spec/defaults.yml, codegen/generate.py
- Generated schema/wire outputs: spec/bony.schema.json,
  spec/bony-wire.schema.json, runtime-nim/src/bony/generated/wire.nim,
  runtime-dart/lib/src/generated/wire.dart
- Nim model/load/emit: runtime-nim/src/bony/model.nim,
  runtime-nim/src/bony/jsonio.nim, runtime-nim/src/bony/binary/semantic.nim
- Dart model/load: runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart
- Existing tests to extend or mirror: runtime-nim/tests/test_skin_resolution.nim,
  runtime-nim/tests/test_json_bnb_json_idempotency.nim,
  runtime-nim/tests/test_bnb_byte_stability.nim,
  runtime-dart/test/m20_skin_test.dart
- Beads: bony-i4x6, bony-i4x6.1

**Success Criteria**
- `BoneData`, `IkConstraintData`, `TransformConstraintData`,
  `PathConstraintData`, and `PhysicsConstraintData` in Nim and Dart expose a
  loaded `skinRequired` flag with default `false`.
- `SkinData` in Nim and Dart exposes typed membership lists for required bones,
  IK constraints, transform constraints, path constraints, and physics
  constraints.
- `.bony` JSON loading and canonical emission preserve `skinRequired` flags and
  membership lists with deterministic ordering from
  `docs/skin-required-activation-contract.md`.
- `.bnb` writing and reading preserve the same data through `registry/wire.yml`,
  `spec/defaults.yml`, and regenerated wire/schema outputs.
- Load validation rejects the contract's malformed membership cases:
  unknown membership reference, duplicate reference within one skin/family,
  membership reference to a non-required item, non-required bone under a
  required ancestor, non-required constraint with a dependency that can become
  inactive, and per-skin missing required parent/dependency membership.
- The new serialized identifiers and key choices are recorded in
  `docs/CLEANROOM.md` and `docs/PROVENANCE.md` if they are net-new.
- Existing active-skin attachment lookup behavior remains unchanged.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`
  - `cd runtime-dart && dart test`

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not add DragonBones or Lottie importer mapping.
- Use only allocated key ranges from `registry/key-ranges.md`; if the slice
  needs cross-band keys, document the cross-band reason in registry docs and
  bead notes.
- Keep registry/default/codegen/generated edits atomic so
  `python3 codegen/generate.py --check` is green at the end of the slice.
- Do not implement runtime inactive filtering, physics reactivation behavior,
  conformance assets, or Dart runtime parity beyond load/round-trip metadata
  preservation in this slice.
