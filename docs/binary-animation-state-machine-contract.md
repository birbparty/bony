# Binary Animation And State-Machine Contract

This is the binding overview for preserving current animation and state-machine
data in `.bnb` without enabling `.bnb` state-machine playback.

It cross-links the project-owned decisions that define the wire shape,
canonical emission, reference resolution, validation ownership, loaded Nim asset
shape, and clean-room source boundary. When a section below points to a more
specific contract, that contract owns the detailed rule.

## Scope

This contract covers the current local feature slice:

- Animation clips.
- Bone scalar, vector, and inherit timelines.
- Slot attachment, color, two-color, and sequence timelines.
- Linear, stepped, and Bezier curves.
- State machines with bool, number, and trigger inputs.
- Layers with clip states and blend1d states.
- Blend clips, transitions, conditions, and listeners.
- Pointer helper listeners over point and bounding-box helper attachments.

Event timelines are out of scope for this binary slice. Nim has event timeline
types, but current JSON loading does not populate them and Dart does not expose
matching event timeline data. Binary event records require a later parity
decision.

## Binding Sources

The detailed rules are split across these project-owned contracts:

| Area | Binding source |
|------|----------------|
| Object families, payload shapes, registry bands | [binary-animation-state-machine-object-families.md](binary-animation-state-machine-object-families.md) |
| Canonical object order, child adjacency, string traversal, default omission | [binary-canonicalization.md](binary-canonicalization.md) |
| Binary reference domains and name reconstruction | [binary-animation-state-machine-reference-semantics.md](binary-animation-state-machine-reference-semantics.md) |
| Schema/decoder/loader/runtime validation ownership | [animation-state-machine-validation-ownership.md](animation-state-machine-validation-ownership.md) |
| Pointer helper listener JSON/BNB shape and target validation | [pointer-helper-listener-contract.md](pointer-helper-listener-contract.md) |
| Nim aggregate loaded-asset shape | [nim-loaded-asset-shape.md](nim-loaded-asset-shape.md) |
| Binary ToC and unknown-property skip mechanics | [binary-toc-skip-semantics.md](binary-toc-skip-semantics.md) |
| Shared load error categories and unknown-object handling | [load-validation-contract.md](load-validation-contract.md) |
| JSON canonical output and default omission sibling rules | [json-canonicalization.md](json-canonicalization.md) |
| Clean-room source boundary | [CLEANROOM.md](CLEANROOM.md), [PROVENANCE.md](PROVENANCE.md), [animation-state-machine-cleanroom-boundary.md](animation-state-machine-cleanroom-boundary.md) |

The local runtime/JSON inventory in
[animation-state-machine-contract-boundaries.md](animation-state-machine-contract-boundaries.md)
is evidence for this slice, not an external source.

## Object Families

The `.bnb` object stream uses project-owned flat records:

```text
animationClip
  boneTimeline*
  slotTimeline*

stateMachine
  stateMachineInput*
  stateMachineLayer+
    stateMachineState*
    stateMachineBlendClip*
    stateMachineTransition*
    stateMachineCondition*
  stateMachineListener*
```

Keyframes are packed in `timelineKeys` bytes payloads. They are not emitted as
child objects in this slice.

Concrete type keys and property keys are not allocated by this overview. The
registry follow-up must append them to `registry/wire.yml` using the ranges
reserved in [registry/key-ranges.md](../registry/key-ranges.md):

- M3 `2000..2999` for animation clips, timelines, curves, and keyframe payloads.
- M8 `7000..7999` for state machines, inputs, layers, states, blend clips,
  transitions, conditions, and listeners.

Registry edits must be append-only. They must not reuse prior keys for different
backing types or semantics. Shared existing properties such as `name` may be
reused only when their backing type and meaning match.

## Canonical Emission

Canonical `.bnb` emission follows [binary-canonicalization.md](binary-canonicalization.md).
For this slice:

- Animation records emit before state-machine records.
- Animation order is loaded `BonyAsset.animations` order.
- Within one animation, emit all `boneTimeline` records in loaded
  `boneTimelines` order, then all `slotTimeline` records in loaded
  `slotTimelines` order.
- State-machine records emit in loaded `BonyAsset.stateMachines` order.
- State-machine children immediately follow their owning parent: inputs, layers,
  layer states with blend clips, layer transitions with conditions, then
  listeners.
- Packed `timelineKeys` fields emit in the field order chosen by
  [binary-animation-state-machine-object-families.md](binary-animation-state-machine-object-families.md).
- The current packed animation/state-machine payloads use indices and numeric
  tags, not strings. Future packed strings must define their traversal point for
  string interning.

Default omission remains owned by `spec/defaults.yml` and the binary/JSON
canonicalization contracts. Writers omit a default-valued property only when the
default table says `omitWhenDefault: true`; falsey non-default values still
emit.

## Generated Schema Limits

The generated wire schema, `spec/bony-wire.schema.json`, represents
`timelineKeys` as a base64 `bytes` carrier with a `x-bony-packedBytes`
annotation that points back to
[binary-animation-state-machine-object-families.md](binary-animation-state-machine-object-families.md).
It intentionally does not inline the keyframe subformat as JSON Schema because
the payload shape depends on `boneTimelineKind` or `slotTimelineKind`, loader
reference domains, f32 quantization, curve tags, and complete byte consumption.
Those checks remain loader-owned validation.

The canonical `.bony` JSON schema, `spec/bony.schema.json`, exposes
authoring/runtime names: top-level `animations` with nested `boneTimelines` and
`slotTimelines`, and top-level `stateMachines` with nested inputs, layers,
states, transitions, conditions, blend clips, and listeners. It does not expose
flat binary child-record arrays such as top-level `boneTimelines` or
`stateMachineInputs`.

## Reference Semantics

JSON references are name-backed. Binary references are index-backed. After load,
both forms must produce the same project-owned semantic graph.

Required binary domains include:

- Bone timelines reference loaded bones by index.
- Slot timelines reference loaded slots by index.
- Attachment keys reference loaded region attachments by `regionIndex + 1`, with
  zero reserved for no attachment.
- Clip states and blend clips reference the loaded animation sequence by index.
- Blend inputs and conditions reference owning-machine inputs by index.
- Initial states, transitions, and listener state fields reference layer-local
  states by index.
- Listeners reference owning-machine layers by index.
- Pointer listeners reference skeleton slots by index, helper targets by string,
  and owning-machine inputs by index.

Binary indices are scoped to the old-reader known-object projection. Skipped
unknown objects and properties are not semantic targets and must not occupy known
typed-array positions. A known reference to skipped unknown content is
`unknownRequiredReference`.

## Validation Ownership

File loaders are the conformance boundary. Runtime constructors remain a
defensive backstop for direct programmatic API callers, but loaders own:

- Byte-level framing, ToC, string table, object stream, and packed payload
  validation.
- Required fields, mutually exclusive fields, and inactive default-field
  rejection before default application.
- Duplicate names in animation/state-machine scopes.
- Timeline key count, f32 quantization, strictly increasing key times, curve
  domains, color domains, sequence delay/mode domains, and packed payload
  consumption.
- Reference resolution for bones, slots, attachments, clips, inputs, layers,
  states, transitions, conditions, and listeners.
- State-machine type constraints such as blend1d requiring a number input,
  condition kind matching input kind, and transition listeners targeting an
  existing transition.
- Pointer listener constraints such as slot/helper target resolution through
  setup attachments or skin entries, input kind matching value shape, point
  radius presence, and lifecycle-field rejection.

Shared error categories come from [load-validation-contract.md](load-validation-contract.md).
Implementation work must reconcile Nim's current `BonyLoadErrorKind` with shared
categories such as `lengthMismatch` before binary animation/state-machine loader
fixtures require that category.

## Nim Loaded Asset Shape

Nim preserves file-level animation and state-machine data with an aggregate
loaded asset, tentatively `BonyAsset`:

```nim
type
  BonyAsset* = object
    skeleton*: SkeletonData
    animations*: seq[AnimationClip]
    stateMachines*: seq[StateMachine]
```

The aggregate lives outside `runtime-nim/src/bony/model.nim` so `SkeletonData`
remains the static setup/deformer payload and existing setup/deformer APIs
continue to return `SkeletonData`.

Lossless conversion uses aggregate APIs:

```text
.bony -> loadBonyJsonAsset -> toBonyBnb(BonyAsset)
     -> loadBonyBnbAsset -> toBonyJson(BonyAsset)
```

Static `SkeletonData` APIs remain valid and intentionally setup/deformer-only.

## Runtime Acceptance Boundary

This contract preserves animation/state-machine records in `.bnb`; it does not
claim runtime playback support for `.bnb` state machines.

The CLI state-machine input-script path currently rejects `.bnb` assets for
playback. That rejection must remain until a dedicated runtime implementation
Bead wires aggregate binary loading through playback, input scripts, pose
projection, and conformance coverage.

CLI conversion commands should switch from static `SkeletonData` APIs to
aggregate APIs only after registry keys, encode/decode support, canonical JSON
emission, and conformance fixtures exist.

## Clean-Room Boundary

This contract is derived from project-owned sources:

- The local bony spec.
- Existing Nim/Dart project code and JSON surfaces inventoried in project docs.
- Project-owned binary, JSON, validation, registry, and canonicalization
  contracts.
- Public/textbook math only where algorithmic behavior is involved.

Do not derive registry keys, object ordering, payload layout, field names, or
implementation structure from Spine, Rive, DragonBones, Live2D, or other
prior-art runtime source or generated definitions. The capability survey and
provenance notes are context only and cannot justify implementation details.

## Follow-Up Work

The dependent implementation sequence should:

- Append M3/M8 registry entries and defaults.
- Add Nim aggregate asset APIs.
- Implement JSON aggregate load/store with source-order animation preservation.
- Implement `.bnb` aggregate encode/decode for known animation/state-machine
  records.
- Add conformance fixtures for canonical byte order, skipped unknown handling,
  reference resolution, validation categories, and `.bony -> .bnb -> .bony`
  preservation.
- Keep `.bnb` state-machine playback rejection until the dedicated runtime
  playback work removes it with tests.
