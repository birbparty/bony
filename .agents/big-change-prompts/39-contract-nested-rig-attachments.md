# /big-change prompt - contract + format (nested rig attachments)

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

/big-change Define project-owned nested rig attachment records and load them through JSON and BNB.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

The repo has no open Beads issues and the existing prompt series ends at M21
pointer helper listeners. The local binding spec still lists a `nested`
attachment kind: a slot-visible attachment that displays another
`SkeletonData`, with `skeleton`, `skin`, and `animation` defaults, where the host
slot's world transform becomes the nested root's parent transform. Existing
binding contracts mention nested rigs only as non-goals:
`docs/skin-attachment-set-contract.md`,
`docs/helper-geometry-attachment-contract.md`, and
`docs/mesh-attachment-contract.md`.

Build the contract/format slice for nested rig attachments:

1. Add a binding contract document at
   `docs/nested-rig-attachment-contract.md`.
2. Define a project-owned top-level canonical JSON array for nested rig
   attachment definitions. Suggested shape:
   - `nestedRigAttachments[]`
   - `name` - slot-visible attachment definition name
   - `skeleton` - required external or host-resolved nested skeleton reference id
   - `skin` - optional default skin name for the nested skeleton
   - `animation` - optional default animation name for the nested skeleton
   Use these names only if the implementation keeps them project-owned and
   documents them in the new contract, registry, defaults, and provenance.
3. Define loader validation:
   - `name` and `skeleton` are non-empty strings;
   - nested attachment names are unique and unambiguous across all slot-visible
     concrete attachment classes;
   - `slot.attachment` may name a nested rig attachment;
   - when first-class skins are present, `skinEntry.target` may resolve to a
     nested rig attachment;
   - `skin` and `animation` are stored as nested-skeleton defaults but are not
     resolved against the current `SkeletonData`;
   - nested skeleton asset loading, recursion/cycle detection across assets, and
     runtime playback validation are deferred to a later runtime slice.
4. Define `.bnb` wire shape by appending one M4 attachment-family type key and
   any needed M4 property keys in `registry/wire.yml`, using only
   `registry/key-ranges.md`. Reuse existing property keys only when their
   backing type and documented meaning are compatible; otherwise append new
   project-owned keys.
5. Update `spec/defaults.yml` and regenerate generated outputs with
   `python3 codegen/generate.py`:
   - `runtime-nim/src/bony/generated/wire.nim`
   - `runtime-dart/lib/src/generated/wire.dart`
   - `spec/bony.schema.json`
   - `spec/bony-wire.schema.json`
6. Add Nim model, JSON, and BNB load/round-trip shape without runtime nested
   playback:
   - `runtime-nim/src/bony/model.nim`
   - `runtime-nim/src/bony/jsonio.nim`
   - `runtime-nim/src/bony/binary/semantic.nim`
7. Add Dart model, JSON, and BNB load/round-trip shape without runtime nested
   playback:
   - `runtime-dart/lib/src/model.dart`
   - `runtime-dart/lib/src/loader.dart`
8. Update documentation and provenance:
   - `docs/README.md`
   - `docs/CLEANROOM.md`
   - `docs/PROVENANCE.md`
   - `docs/skin-attachment-set-contract.md`
   - `docs/helper-geometry-attachment-contract.md`
   - `docs/mesh-attachment-contract.md`

Do not implement nested skeleton asset loading, draw-batch composition, nested
state-machine playback, animation driving, importer mapping, or conformance
goldens in this slice. This milestone only freezes the serialized surface and
load-time validation rules.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local binding spec: /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md
- Registry key bands: registry/key-ranges.md
- Registry/default/schema sources: registry/wire.yml, spec/defaults.yml,
  codegen/generate.py, spec/bony.schema.json, spec/bony-wire.schema.json
- Existing attachment/skin contracts:
  docs/skin-attachment-set-contract.md,
  docs/helper-geometry-attachment-contract.md,
  docs/mesh-attachment-contract.md
- Nim seams: runtime-nim/src/bony/model.nim,
  runtime-nim/src/bony/jsonio.nim,
  runtime-nim/src/bony/binary/semantic.nim,
  runtime-nim/src/bony/generated/wire.nim
- Dart seams: runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart,
  runtime-dart/lib/src/generated/wire.dart
- Beads: bony-5b5w

**Success Criteria**
- `docs/nested-rig-attachment-contract.md` exists and defines the nested rig
  attachment model, JSON shape, `.bnb` object shape, validation rules,
  active-skin target resolution behavior, canonical ordering, and explicit
  non-goals.
- `docs/CLEANROOM.md` and `docs/PROVENANCE.md` record the new serialized names
  as project-owned and explain that comparable nested-armature/artboard
  capabilities were category context only.
- `registry/wire.yml` and `spec/defaults.yml` contain append-only M4 changes or
  documented compatible property reuse, and generated files are refreshed by
  `python3 codegen/generate.py`.
- Nim and Dart can load and round-trip nested rig attachment records through
  JSON and `.bnb`, and reject malformed records with existing loader error
  categories.
- Existing region, clipping, mesh, point, bounding-box, skin, deform timeline,
  and pointer listener behavior remains backward compatible.
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
- Keep DragonBones and Lottie importer mapping out of this slice.
- Do not add nested draw-batch composition, nested state-machine playback,
  cross-asset cycle detection, or conformance goldens in this slice.
- Do not add vector paths, text, layout, data binding, or renderer features.
- Use only your allocated range from `registry/key-ranges.md`.
- Keep the slice small enough for one meaningful implementation session.
