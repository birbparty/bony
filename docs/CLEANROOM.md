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
