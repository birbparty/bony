# Animation And State-Machine Clean-Room Boundary

This note records the provenance constraints for designing `.bnb` animation and
state-machine object families. It complements
[animation-state-machine-contract-boundaries.md](animation-state-machine-contract-boundaries.md)
by defining what evidence may be used for the next binary contract slice.

## Binding Sources

This slice may derive implementation and binary-contract details only from:

- The local binding spec at
  `/Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md`, especially its
  clean-room mandate.
- Project-owned local behavior in the current repository, including
  `runtime-nim/src/bony/anim/timelines.nim`,
  `runtime-nim/src/bony/statemachine/core.nim`,
  `runtime-nim/src/bony/jsonio.nim`, `runtime-nim/src/bony/model.nim`,
  `runtime-dart/lib/src/model.dart`, `runtime-dart/lib/src/loader.dart`,
  `runtime-dart/lib/src/anim.dart`, and
  `runtime-dart/lib/src/statemachine.dart`.
- Project-owned contracts in `docs/`, `spec/`, `registry/`, generated code
  produced from those project sources, and conformance assets already committed
  to this repository.
- Capability categories recorded in
  [comparable-feature-set.md](comparable-feature-set.md), such as timelines,
  state machines, events, tracks, constraints, skins, and runtime/export
  surfaces.
- Public/textbook animation and computer-graphics math, such as affine
  transforms, interpolation, Bezier evaluation, linear blend skinning, root
  finding, and deterministic numeric techniques.

Capability categories are allowed only as product-context prompts. They do not
authorize copying identifiers, keys, field layouts, object order, binary
sections, runtime architecture, generated definitions, examples, or prose from
another product.

## Excluded Sources

Do not inspect, fetch, browse, clone, download, derive from, transliterate, or
copy any of the following while designing or implementing the `.bnb`
animation/state-machine contract:

- DragonBones runtime source, importer source, generated schemas, exact
  `_ske.json` or atlas layouts, or copied documentation prose.
- Spine runtime source, importer source, exact JSON or binary layouts, atlas
  layout details, generated data definitions, examples, or documentation prose.
- Rive runtime source, generated core definitions, exact `.riv` binary format,
  object/type keys, property keys, object ordering, schema/code layout, linked
  source snippets, or runtime-format documentation used as design input.
- Live2D Cubism Core or SDK source, proprietary model layouts, generated data,
  or importer implementation details.
- Lottie runtime/importer source, exact interchange schema details as a source
  for `bony` internals, or copied importer/exporter implementation code.
- Any disassembled binary, mirrored source tree, package source, generated
  runtime definition file, or third-party code snippet for the products above.

If a proposed design appears to need one of those sources, stop and file a
design or legal-review Bead instead of continuing.

## Permitted Use Of Existing Project Notes

`docs/comparable-feature-set.md` is informational research, not a binding
format contract. It may be used to say that users expect broad categories like
animation timelines, events, state-machine inputs, listeners, animation mixing,
skins/avatar reuse, or runtime/export surfaces. It must not be used to choose
`bony` object names, property names, type keys, binary encodings, object
ordering, validation behavior, or runtime data structures.

`docs/PROVENANCE.md` records previous capability-context entries, including
DragonBones importer boundary work and the comparable feature survey. Those
entries do not expand the implementation source set for this `.bnb` slice.
Importer-specific field names may remain parser-boundary facts for the importer
work that introduced them, but they must not leak into core `bony` runtime,
registry, conformance asset, or binary-contract naming.

`docs/CLEANROOM.md` remains the controlling rule when there is any conflict:
prior-art capability context can motivate project-owned design questions, but
implementation details must come from local `bony` contracts or public math.

## Allowed Design Inputs For The Next Slice

The next binary animation/state-machine contract may use:

- The project-owned JSON/runtime inventory in
  [animation-state-machine-contract-boundaries.md](animation-state-machine-contract-boundaries.md).
- Current Nim validation boundaries for timeline kind ownership, key sorting,
  quantization, references, state-machine layers, inputs, transitions, listeners,
  and runtime transition ordering.
- Current Dart preservation and validation gaps, including the fact that Dart
  preserves animations/state machines in `SkeletonData` while Nim does not.
- Current `.bnb` validation and skip semantics from project-owned docs,
  especially binary ToC/property skipping, canonicalization, and load-time
  validation contracts.
- Project-owned registry key allocation rules and generated wire definitions
  when assigning new `bony` keys.

The design must invent fresh project-owned type keys, property keys, object
families, field names, and ordering rules. Similarity to another product's exact
layout is a bug, not compatibility.

## Review Gate

Before merging any follow-on change that assigns `.bnb` animation or
state-machine object families, reviewers should verify:

- The change can be explained from local `bony` runtime/JSON behavior,
  project-owned docs, registry/spec files, or public math.
- No third-party runtime source, importer source, generated definitions,
  exact wire layouts, or copied docs prose were used.
- New binary keys, object ordering, reference rules, and validation ownership
  are documented as `bony`-owned decisions.
- Any use of comparable products stays at capability-category level.
- New provenance evidence, if any, is recorded in `docs/PROVENANCE.md` before
  implementation relies on it.
