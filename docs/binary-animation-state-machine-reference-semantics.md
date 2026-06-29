# Binary Animation And State-Machine Reference Semantics

This document defines how `.bnb` animation and state-machine records resolve
references to the same semantic graph produced by `.bony` JSON loading.

It refines the reference summary in
[binary-animation-state-machine-object-families.md](binary-animation-state-machine-object-families.md)
and aligns with [load-validation-contract.md](load-validation-contract.md).
It does not allocate registry keys or implement runtime APIs.

## Decision

Binary animation and state-machine records use bounded integer references on the
wire. After load, runtimes reconstruct the project-owned semantic model with the
same names and graph relationships that JSON would produce.

Rules:

- JSON input remains name-backed at the authoring boundary.
- Binary input is index-backed at the wire boundary.
- Loaded Nim/Dart runtime values expose the existing project-owned names and
  object relationships.
- Known binary references must resolve only to known loaded objects.
- Skipped unknown binary objects and unknown properties are never semantic
  reference targets.

This keeps binary payloads compact and deterministic while preserving the
name-addressed graph expected by the current animation and state-machine
runtimes.

## Reference Domains

Every index is scoped to one explicit domain. Implementations must not resolve
an index against a different domain even when another domain has the same count.

| Binary source | Property / payload | Target domain | Loaded semantic value |
|---------------|--------------------|---------------|-----------------------|
| `boneTimeline` | `boneIndex` | Asset skeleton bone array | Timeline target bone name/index used by runtime sampling |
| `slotTimeline` | `slotIndex` | Asset skeleton slot array | Timeline target slot name/index used by runtime sampling |
| Slot attachment key | nonzero `attachmentTag - 1` | Asset region-attachment array | Attachment key target region attachment; zero remains no attachment |
| Clip state | `stateClipIndex` | Asset animation sequence | `StateMachineState.clip` / clip name equivalent |
| Blend clip | `blendClipAnimationIndex` | Asset animation sequence | `StateMachineBlendClip.clip` / clip name equivalent |
| Blend1d state | `stateBlendInputIndex` | Owning state-machine input sequence | Blend input name |
| Layer | `initialStateIndex` | Owning layer state sequence | Initial state name |
| Transition | `transitionFromStateIndex` | Owning layer state sequence | Source state name |
| Transition | `transitionToStateIndex` | Owning layer state sequence | Target state name |
| Condition | `conditionInputIndex` | Owning state-machine input sequence | Condition input name |
| Listener | `listenerLayerIndex` | Owning state-machine layer sequence | Listener layer name |
| Listener | `listenerFromStateIndex` | Referenced layer state sequence | Listener source state name |
| Listener | `listenerToStateIndex` | Referenced layer state sequence | Listener target state name |

The asset animation sequence is the ordered `BonyAsset.animations` sequence
chosen by [nim-loaded-asset-shape.md](nim-loaded-asset-shape.md). JSON loading
collects this sequence from source `animations` array order. Binary loading
collects it from canonical binary animation object order.

## Name Reconstruction

Binary records that define name-addressable objects carry their own `name`
property. Those names are the authority for the loaded graph:

- `animationClip.name`
- `stateMachine.name`
- `stateMachineInput.name`
- `stateMachineLayer.name`
- `stateMachineState.name`
- `stateMachineListener.name`

Binary reference properties do not replace names in the runtime model. They are
only the compact file representation used to find the target during load. After
resolution, runtime values must contain the same names that JSON loading would
have stored for equivalent input.

Examples:

- A `stateClipIndex` resolves to an animation in `asset.animations`; the loaded
  state owns that clip object in Nim and can emit the clip's name in JSON.
- A `conditionInputIndex` resolves to an input in the owning state machine; the
  loaded condition stores the input name expected by the state-machine runtime.
- A listener's layer/state indices resolve to names before runtime construction;
  transition listeners then validate against the layer's resolved transitions.

## Resolution Order

Binary aggregate loading resolves references in phases:

1. Decode byte-level object records and packed timeline payloads with bounded
   lengths.
2. Build known static skeleton arrays and name-addressable static attachment
   domains.
3. Build ordered animation clips from known `animationClip` records and their
   owned timeline records.
4. Build ordered state-machine inputs, layers, states, transitions, conditions,
   and listeners from known state-machine records.
5. Resolve every known reference against its explicit domain.
6. Validate graph/type invariants before constructing runtime values.

Loaders may combine phases internally, but the observable accept/reject behavior
must match this order. In particular, state-machine clip references resolve only
after the full known animation sequence exists, and listener transition
validation runs only after layer states and transitions have resolved.

## Static Skeleton And Attachment Domains

Animation timeline references into static setup data use the domains already
defined by the static binary loader:

- `boneIndex` resolves against loaded skeleton bones.
- `slotIndex` resolves against loaded skeleton slots.
- Attachment keyframes resolve nonzero `attachmentTag` values against loaded
  region attachments.

Attachment keyframes intentionally do not store attachment names as strings in
this slice. A writer maps a JSON attachment name to the corresponding loaded
region index. A loader maps the region index back to the loaded region
attachment and can recover the project-owned attachment name from that target
when emitting JSON.

If a future attachment family adds non-region timeline targets, it must define a
new tag space rather than reusing this region-only `attachmentTag` meaning.

## Animation References

The binary animation index domain is the ordered list of known loaded animation
clips in the asset aggregate.

Required checks:

- Duplicate animation names are `duplicateKey`.
- `stateClipIndex` and `blendClipAnimationIndex` must be in range.
- A state machine must not reference an animation that was skipped as an unknown
  object.
- The resolved animation object must be a known `animationClip`, not another
  object family with a matching ordinal position.

Binary indices are not stable cross-file identifiers. They are stable only
within one loaded `.bnb` file after applying known-object skip rules.

## State-Machine Local References

State-machine references are local to the owning state machine unless the target
domain explicitly says otherwise.

Input references:

- `stateBlendInputIndex` and `conditionInputIndex` resolve against the owning
  state machine's input sequence.
- Blend inputs must resolve to number inputs.
- Condition kind must match the referenced input kind.

Layer/state references:

- `initialStateIndex`, transition state indices, and listener state indices
  resolve against the referenced layer's state sequence.
- Listener layer references resolve against the owning state machine's layer
  sequence before state indices are resolved.
- Transition listeners must match an existing transition in the referenced
  layer after both source and target state indices resolve.

Names remain the runtime identity after resolution. Duplicate input, layer,
state, and listener names in their owning scopes are rejected as `duplicateKey`.

## Unknown Object Handling

Forward-compatible skip behavior must not create hidden reference targets.

Allowed:

- Unknown same-major objects may be skipped when their property records are
  well formed.
- Unknown properties on known objects may be skipped when their ToC entries and
  payload lengths are valid.
- Known references may continue to resolve by ordinal among known objects when
  skipped unknown objects are outside the target domain.

Rejected:

- A known reference whose numeric value falls outside the known target domain is
  `unknownRequiredReference`.
- A known object that depends on an unknown skipped object for required
  semantics is `unknownRequiredReference`.
- A known object that uses an unknown property to override a known reference is
  invalid; unknown properties cannot change known reference semantics.

Skipped unknown objects do not occupy positions in known typed arrays. For
example, an unknown object between two `animationClip` records does not consume
an animation index, and a known `stateClipIndex` cannot target that unknown
object.

## Error Categories

Reference failures use the existing load-validation categories:

| Failure | Category |
|---------|----------|
| Out-of-range binary reference index | `unknownRequiredReference` |
| Known reference to skipped unknown content | `unknownRequiredReference` |
| Duplicate name in a name-addressable domain | `duplicateKey` |
| Child object without required current parent | `schemaViolation` |
| Reference property present on an incompatible object kind | `schemaViolation` |
| Condition/input kind mismatch | `schemaViolation` |
| Blend input is not a number input | `schemaViolation` |
| Transition listener targets no existing transition | `unknownRequiredReference` |
| Timeline key references non-region attachment in this slice | `unknownRequiredReference` |

Exact human-readable error strings are not part of the contract.

## Round-Trip Requirements

For equivalent `.bony` and `.bnb` inputs, aggregate loaders must produce the
same semantic graph:

```text
loadBonyJsonAsset(json).animations/stateMachines
  == loadBonyBnbAsset(bnb).animations/stateMachines
```

Equality here means project-owned semantic equality, not pointer identity or
byte-for-byte source equality:

- Names match.
- Array orders match the contract-owned semantic order.
- Timeline targets resolve to the same bones, slots, and attachments.
- State-machine states, transitions, conditions, blend clips, and listeners
  resolve to the same named targets.
- Numeric values have already been quantized according to the JSON/binary
  numeric contracts.

When emitting JSON from a binary-loaded asset, serializers must emit names, not
binary indices, for name-addressed JSON fields.

## Follow-Up Work

Dependent implementation Beads should add conformance coverage for:

- Every reference domain listed above.
- Out-of-range reference rejection.
- Duplicate name rejection in each owning scope.
- Known references failing when they would require skipped unknown content.
- `.bony -> .bnb -> .bony` preservation of state-machine clip, blend clip,
  condition, transition, and listener targets.
