# /big-change prompt - contract + format (helper geometry attachments)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 1**. Can run independently. It intentionally
> stops at contract/format/load parity; pointer-listener runtime dispatch can be
> planned later from this project-owned surface.
> **Candidate category:** frontier.

---

/big-change Define project-owned point and bounding-box helper attachments as non-rendered `.bony`/`.bnb` records with load validation and Nim/Dart round-trip parity.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

There are no open Beads issues, and the current prompt set ends at
`34-dart-skin-parity.md`. The repo has conformance assets through M20, including
mesh, clipping, deform timelines, events, skins, IK, transform constraints, and
physics. The next unfinished local frontier implied by the binding spec is the
helper-geometry attachment surface: the spec names `boundingbox` and `point`
attachments and state-machine pointer listeners over bounding-box or point
targets, but the current model has only region/path/clipping/mesh attachments.

This slice creates the project-owned helper attachment contract and format/load
surface only. Do not implement pointer input dispatch, state-machine listener
hit testing, importer conversion, vector paths, nested rigs, or renderer output
in this slice.

Build exactly this milestone:

1. Add `docs/helper-geometry-attachment-contract.md` as a binding attachment
   contract. Define two non-rendered attachment classes:
   - `pointAttachment`: a named locator in the owning slot bone's local space,
     with required finite `x`, `y`, and `rotation` degrees. It emits no
     `DrawBatch` and exists for host/runtime hit-test or locator queries.
   - `boundingBoxAttachment`: a named convex polygon in the owning slot bone's
     local space, stored as flat `vertices: [x0, y0, x1, y1, ...]` with at
     least three points, even length, finite coordinates, non-zero signed area,
     and consistent convex turn direction. It emits no `DrawBatch`.
   Define that slots may reference region, clipping, mesh, point, or
   bounding-box attachment names through the existing `slot.attachment` field,
   but helper attachments are invisible to `buildDrawBatches`.
2. Define deterministic helper-query semantics in the contract without wiring
   pointer listeners yet:
   - A point attachment's world pose is the owning slot bone world transform
     composed with the point's local translate/rotation.
   - A bounding-box attachment's world polygon is each local vertex transformed
     by the owning slot bone world transform.
   - A point-in-bounding-box test uses the standard crossing-number/even-odd
     rule over the transformed polygon, with boundary points treated as inside
     if their distance to any edge is within the project tolerance from
     `docs/float-math-contract.md`.
   These rules are project-owned public geometry math and may be implemented
   later by both runtimes from this contract.
3. Add append-only registry/default/schema entries for `pointAttachment` and
   `boundingBoxAttachment`. Use only unused keys from
   `registry/key-ranges.md`. Prefer the M2 band because these are static
   attachment records like `region`; if code review finds the existing M4
   `vertices` property key is the correct compatible packed f32-pair polygon
   property to reuse for `boundingBoxAttachment`, document that compatibility
   explicitly in `registry/wire.yml` rather than silently changing meaning.
   Reuse the existing global `name`, `x`, `y`, and `rotation` property keys for
   `pointAttachment` if their backing types and semantics are compatible.
4. Update `spec/defaults.yml` and `codegen/generate.py` only as required by the
   registry additions, then run `python3 codegen/generate.py` to refresh
   generated schema/runtime metadata. Do not hand-edit generated files.
5. Update Nim load/round-trip shape:
   - `runtime-nim/src/bony/model.nim`: add minimal data records, fields on
     `SkeletonData`, constructors/accessors, and validation. Helper attachment
     names must be unique within their class, non-empty, and accepted by
     `slot.attachment` resolution. Keep helper attachments out of draw batches.
   - `runtime-nim/src/bony/jsonio.nim`: load/write top-level
     `pointAttachments` and `boundingBoxAttachments` arrays.
   - `runtime-nim/src/bony/binary/semantic.nim`: write/read the new BNB object
     records in canonical attachment order.
6. Update Dart load/round-trip shape to match the Nim surface:
   - `runtime-dart/lib/src/model.dart`: add matching immutable data records and
     `SkeletonData` fields.
   - `runtime-dart/lib/src/loader.dart`: parse JSON, parse/write BNB if the
     current loader has the matching object-stream helpers, and preserve the
     same validation rules where Dart currently validates equivalent attachment
     data.
   - Keep helper attachments out of `buildDrawBatches`.
7. Update docs and provenance:
   - Add the new contract to `docs/README.md` under Attachment Contracts.
   - Update `docs/CLEANROOM.md` and `docs/PROVENANCE.md` with the new serialized
     names and clean-room rationale.
   - If `docs/load-validation-contract.md` needs a row for helper attachment
     invariants, update it consistently.

Keep this slice intentionally narrow: it establishes stable project-owned
format and validation. It does not add pointer listener runtime dispatch, input
scripts for pointer events, DragonBones/Lottie importer support, visible debug
rendering, nested rigs, skin-owned helper attachments, linked meshes, or
`skinRequired`.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local binding spec: /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md
- Existing attachment contracts: docs/clipping-attachment-contract.md,
  docs/mesh-attachment-contract.md, docs/skin-attachment-set-contract.md
- Float math/tolerance: docs/float-math-contract.md
- Validation ownership: docs/load-validation-contract.md
- Registry key bands: registry/key-ranges.md
- Registry/default/schema sources: registry/wire.yml, spec/defaults.yml,
  codegen/generate.py, spec/bony.schema.json, spec/bony-wire.schema.json
- Nim seams: runtime-nim/src/bony/model.nim,
  runtime-nim/src/bony/jsonio.nim,
  runtime-nim/src/bony/binary/semantic.nim,
  runtime-nim/src/bony/transform.nim
- Dart seams: runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart,
  runtime-dart/lib/src/transform.dart
- CLI/importer seam to keep out of scope: cli/bony_cli.nim
- Beads: parent bony-wb1d

**Success Criteria**
- `docs/helper-geometry-attachment-contract.md` exists and normatively defines
  point and bounding-box helper attachments, JSON shape, BNB object shape,
  validation rules, helper-query semantics, and explicit non-goals.
- `docs/README.md`, `docs/CLEANROOM.md`, and `docs/PROVENANCE.md` are updated
  with project-owned naming/provenance for `pointAttachment`,
  `boundingBoxAttachment`, `pointAttachments`, and `boundingBoxAttachments`.
- `registry/wire.yml` and `spec/defaults.yml` contain append-only additions or
  documented compatible property reuse; generated schema/runtime metadata is
  refreshed with `python3 codegen/generate.py`.
- Nim loads and writes `.bony`/`.bnb` helper attachment records and validates
  duplicate names, malformed point values, malformed bounding-box vertices, and
  slot references to helper attachments without emitting draw batches.
- Dart loads the same JSON/BNB helper attachment surface and keeps it invisible
  to draw-batch output.
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
- Keep pointer-event/listener dispatch out of this slice; this prompt only
  establishes the local project-owned target geometry and helper-query contract.
- Do not add renderer-visible batches for point or bounding-box attachments.
- Do not add vector paths, nested rigs, skin-owned helper attachments, linked
  meshes, or `skinRequired`.
- Use only your allocated range from `registry/key-ranges.md`.
- Keep the slice small enough for one meaningful implementation session.
