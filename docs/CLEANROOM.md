# Clean-Room Engineering

`bony` is a clean-room implementation of a new 2D skeletal and deform
animation format. The binding implementation source is the local functional
specification plus project-owned contracts in this repository. Prior art is
used only to understand capabilities, never as source material for code, field
layouts, binary layouts, identifiers, or prose.

## Binding Rule

Implementations must be derived from:

- `/Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md`, especially
  section 1, "Clean-room engineering mandate".
- Project-owned contracts in `docs/`, `spec/`, `registry/`, and generated code
  produced from those project sources.
- Public, general animation math and computer-graphics techniques such as
  affine transforms, linear blend skinning, Bezier evaluation, FABRIK/CCD-style
  IK, clipping, interpolation, and numerical integration.

Implementations must not be derived from another animation runtime's protected
expression. Do not copy, paste, transliterate, rename variables from, or
structurally clone any third-party runtime, generated schema, binary definition,
wire layout, documentation text, or importer implementation.

## No-Fetch-Source Build Rule

Agents, scripts, CI jobs, build steps, and implementation tasks MUST NOT fetch,
clone, browse, download, inspect, or otherwise retrieve Spine, Live2D, Rive, or
DragonBones runtime source via web tools, GitHub tools, package tools, mirrors,
or direct network commands while implementing this project.

This includes web tools, GitHub tools, package mirrors, generated runtime
definition files, SDK source trees, disassembled binaries, and copied snippets
from those projects. If an implementation task appears to need source from one
of those runtimes, stop and write or update a design issue instead.

Allowed inputs are capability-level descriptions, the binding `bony` spec,
project-owned docs, dependency license metadata for dependencies we actually
vendor or link, and public/textbook math.

## Reference Caveats

These references are capability context only:

| Reference | Allowed use | Not allowed |
| --- | --- | --- |
| Spine | Understand the broad skeletal-animation capability class: bones, slots, attachments, timelines, constraints, atlases. | Reading or deriving from Spine runtime source, generated files, exact JSON/binary layouts, importer code, or documentation wording. |
| DragonBones | Understand armature terminology, skew-style authored transforms, nested-armature concepts, and migration needs. | Reading runtime/importer source while implementing, cloning `_ske.json`/`_tex` layout field-for-field, or copying names/code/prose. |
| Rive | Understand interactive state-machine capabilities and the general idea of forward-compatible type-keyed serialization. | Copying `rive-runtime` source, generated core definitions, binary keys, object model names, or schema/code layout. |
| Live2D Cubism | Understand the concept of parameter-driven warp/rotation deformers and keyform interpolation. | Reading Cubism Core/SDK source, reproducing proprietary model layouts, or implementing a Live2D importer. |
| Lottie | Understand vector/timeline interchange as a possible migration baseline. | Treating Lottie as a source for `bony` runtime internals or copying importer/exporter implementation code. |
| glTF 2.0 | Understand generic buffer/accessor and animation channel/sampler ideas. | Reusing layouts verbatim where `bony` has its own registry, schema, and binary contracts. |
| Creature | Understand directional-warp and motor-system capability ideas. | Copying code, format layout, or documentation expression. |

## Importer Boundary

DragonBones and Lottie importers require design-spike beads before
implementation. A Spine importer is blocked for human/legal review before any
work. Live2D import is out of scope unless a later legal and design review
explicitly changes that.

Importers are migration tools only. They must parse documented, user-supplied
asset files and convert into `bony`'s own data model; they must not target
byte-compatibility or reproduce another runtime.

## Review Checklist

Before merging work that touches runtime behavior, binary/JSON layout,
conformance assets, or importers:

- Confirm the implementation can be explained from `bony` docs/specs or public
  math, without pointing to a third-party runtime source file.
- Confirm new identifiers, keys, type tags, object ordering, and binary
  encodings are project-owned and documented in `spec/`, `registry/`, or
  `docs/`.
- Confirm no build step or script fetches prior-art runtime source.
- Update `docs/PROVENANCE.md` when a new source of implementation evidence is
  introduced.

## Checklist Satisfaction Record

Net-new serialized identifiers confirmed against the review checklist above.

### Mesh Attachment Serialized Names (2026-07-02, bead `bony-lzj.1`)

- **Net-new identifiers**: type `meshAttachment` (+ skeleton array
  `meshAttachments`); property keys `meshWeighted`, `meshVertices`, `meshUvs`,
  `meshTriangles`; canonical-JSON fields `weighted`, `vertices`, `uvs`,
  `triangles`.
- **Explainable without prior-art source**: yes — the names come from `bony`'s
  own pre-existing mesh runtime types (`runtime-nim/src/bony/mesh/attachments.nim`,
  `mesh/skinning.nim`) and generic mesh / linear-blend-skinning terminology; the
  record and its packed byte layouts are specified in
  `docs/mesh-attachment-contract.md`.
- **Project-owned & documented**: keys (type `3001`, properties `3002`–`3005` in
  the M4 band) live in `registry/wire.yml`; defaults in `spec/defaults.yml`;
  schema in `spec/`; the model/skinning formula/weight encoding are project-owned.
- **No build-step fetch of prior-art source**: confirmed.
- **PROVENANCE updated**: yes — see "Mesh Attachment Schema Names (2026-07-02)"
  in `docs/PROVENANCE.md`.
- **Result**: checklist **satisfied**.

### Deform Timeline Serialized Names (2026-07-03, epic `bony-68lj`)

- **Net-new identifiers**: type `deformTimeline`; property keys `deformSkin`,
  `deformAttachment`, `deformVertexCount`, `deformKeys` (the `slot` binding reuses
  the existing `slot` property key); canonical-JSON fields `skin`, `slot`,
  `attachment`, `vertexCount`, `keyframes` (the runtime `keys` field is exposed as
  `keyframes`).
- **Explainable without prior-art source**: yes — the names come from `bony`'s own
  pre-existing deform runtime types (`runtime-nim/src/bony/mesh/deform.nim`:
  `DeformTimeline`, `DeformKeyframe`, `MeshDelta`) and generic animation/geometry
  terminology; the record, sampling algorithm, and packed byte layout are specified
  in `docs/deform-timeline-contract.md`, and the curve tail reuses the pre-existing
  bone/slot timeline encoding (no second curve encoding minted).
- **Project-owned & documented**: keys (type `3002`, properties `3006`–`3009` in the
  M4 band) live in `registry/wire.yml`; defaults in `spec/defaults.yml`; schema in
  `spec/`; the model/sampling formula/delta-run encoding are project-owned.
- **No build-step fetch of prior-art source**: confirmed.
- **PROVENANCE updated**: yes — see "Deform Timeline Schema Names (2026-07-03)" in
  `docs/PROVENANCE.md`.
- **Result**: checklist **satisfied**.

### Skin Attachment-Set Serialized Names (2026-07-05, bead `bony-4set`)

- **Net-new identifiers**: types `skin` and `skinEntry`; top-level canonical
  JSON array `skins`; skin field `entries`; entry fields `slot`, `attachment`,
  and `target`; property keys `skinAttachment` and `skinTarget` (the entry
  `slot` reuses the existing `slot` property key).
- **Explainable without prior-art source**: yes - the names come from `bony`'s
  binding spec requirement for `skins[]`, the existing project-owned slot and
  attachment model, and generic set/binding terminology. The lookup/fallback
  rule and binary parent/child object shape are specified in
  `docs/skin-attachment-set-contract.md`.
- **Project-owned & documented**: keys (types `3003`/`3004`, properties
  `3010`/`3011` in the M4 band) live in `registry/wire.yml`; defaults in
  `spec/defaults.yml`; schema in `spec/`; the model and ordering rules are
  project-owned.
- **No build-step fetch of prior-art source**: confirmed.
- **PROVENANCE updated**: yes - see "Skin Attachment-Set Schema Names
  (2026-07-05)" in `docs/PROVENANCE.md`.
- **Result**: checklist **satisfied**.

### Helper Geometry Attachment Serialized Names (2026-07-05, bead `bony-wb1d`)

- **Net-new identifiers**: types `pointAttachment` and
  `boundingBoxAttachment`; top-level canonical JSON arrays `pointAttachments`
  and `boundingBoxAttachments`.
- **Compatible property reuse**: `pointAttachment` reuses the existing global
  `name`, `x`, `y`, and `rotation` keys because their string/f32 backing types
  and local-space semantics match. `boundingBoxAttachment` reuses the existing
  `vertices` bytes key as the same packed f32-pair polygon payload already used
  for clipping attachments; the compatible reuse is documented in
  `registry/wire.yml` and `docs/helper-geometry-attachment-contract.md`.
- **Explainable without prior-art source**: yes - the names and rules come from
  the local binding spec's helper-geometry category, the existing project-owned
  slot/attachment model, generic point/convex-polygon terminology, and public
  affine/crossing-number geometry math.
- **Project-owned & documented**: type keys `1002` and `1003` live in the M2
  band in `registry/wire.yml`; defaults/required coverage lives in
  `spec/defaults.yml`; JSON/BNB shape, validation, helper-query semantics, and
  non-goals are specified in `docs/helper-geometry-attachment-contract.md`.
- **No build-step fetch of prior-art source**: confirmed.
- **PROVENANCE updated**: yes - see "Helper Geometry Attachment Schema Names
  (2026-07-05)" in `docs/PROVENANCE.md`.
- **Result**: checklist **satisfied**.

### Pointer Helper Listener Serialized Names (2026-07-06, bead `bony-g65e`)

- **Net-new identifiers**: listener kinds `pointerDown`, `pointerUp`,
  `pointerEnter`, `pointerExit`, and `pointerMove`; listener JSON fields
  `slot`, `targetKind`, `target`, `hitRadius`, `input`, and `value`; `.bnb`
  properties `listenerSlotIndex`, `listenerHelperKind`,
  `listenerHelperTarget`, `listenerInputIndex`, `listenerBoolValue`,
  `listenerNumberValue`, and `listenerHitRadius`.
- **Compatible object reuse**: pointer listener records reuse the existing
  project-owned `stateMachineListener` object family because they are still
  state-machine-owned listeners; new M8 properties carry the pointer-specific
  slot/helper/input/value fields.
- **Explainable without prior-art source**: yes - the names and rules come from
  the local binding spec's state-machine pointer category, existing bony helper
  attachment and skin contracts, generic pointer-event terminology, and public
  point-distance / polygon hit-test math.
- **Project-owned & documented**: property keys `7064..7070` live in the M8
  band in `registry/wire.yml`; defaults/required coverage lives in
  `spec/defaults.yml`; JSON/BNB shape, validation, hit semantics, dispatch
  order, and non-goals are specified in
  `docs/pointer-helper-listener-contract.md`.
- **No build-step fetch of prior-art source**: confirmed.
- **PROVENANCE updated**: yes - see "Pointer Helper Listener Schema Names
  (2026-07-06)" in `docs/PROVENANCE.md`.
- **Result**: checklist **satisfied**.
