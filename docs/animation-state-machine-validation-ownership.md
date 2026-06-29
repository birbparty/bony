# Animation And State-Machine Validation Ownership

This document assigns validation responsibility for the current animation and
state-machine `.bony`/`.bnb` contract slice.

It narrows the general loader phases in
[load-validation-contract.md](load-validation-contract.md) for the object
families chosen in
[binary-animation-state-machine-object-families.md](binary-animation-state-machine-object-families.md)
and the reference semantics in
[binary-animation-state-machine-reference-semantics.md](binary-animation-state-machine-reference-semantics.md).
It does not add event timeline binary support.

## Ownership Layers

Validation has four ownership layers:

1. **Schema and wire shape**: JSON object shape, binary object/property shape,
   required fields, mutually exclusive fields, backing types, byte lengths, and
   project-owned enum tags.
2. **Registry/default decoding**: default application, omitted default handling,
   f32 quantization, integer range decoding, and generated backing-type checks.
3. **Loader semantic validation**: reference resolution, duplicate-name checks,
   graph/type invariants, timeline payload shape, and checks that require more
   than one object.
4. **Runtime constructors**: defensive normalization for programmatic callers.
   Constructors may re-check semantic invariants, but loaders must not depend on
   runtime panics, out-of-bounds access, or partially constructed values to
   reject malformed files.

For file loading, the loader is the conformance boundary. A valid loader may
call runtime constructors after semantic validation, and constructors may raise
the same typed errors as a backstop, but malformed input must still map to the
categories in [load-validation-contract.md](load-validation-contract.md).

## Error Category Policy

Use the existing Nim `BonyLoadErrorKind` categories in
`runtime-nim/src/bony/model.nim` and the shared categories in
[load-validation-contract.md](load-validation-contract.md).

Category mapping for this slice:

| Failure | Category |
|---------|----------|
| Wrong JSON field type, unknown enum string/tag, inactive field present, missing required field, child without parent, wrong payload shape | `schemaViolation` |
| Non-finite f32/f64, f32 overflow, numeric domain outside the authored contract | `numericOutOfRange` |
| Duplicate animation, state-machine, layer, state, input, listener, or duplicate blend value | `duplicateKey` |
| Unknown bone, slot, region attachment, animation clip, input, layer, state, transition, or known reference to skipped unknown binary content | `unknownRequiredReference` |
| Non-increasing timeline key times or rejected canonical child/order rule | `orderingViolation` when owned by ordering contract; otherwise `schemaViolation` for constructor parity |
| Packed payload trailing bytes or known-property byte length mismatch | `lengthMismatch` for shared conformance fixtures; Nim may currently surface `schemaViolation` until the binary implementation adds a dedicated kind |
| Count or payload exceeds conformance limits | `resourceLimitExceeded` |

The current Nim constructors often use `schemaViolation` for negative values,
channel ranges, and sorted-key failures. The file loader should prefer the
shared category table above for cross-runtime fixtures when it can distinguish
the failure before calling constructors. Constructor category choices are
acceptable for direct programmatic API calls.

## Animation Clip Ownership

| Check | Owner | Category |
|-------|-------|----------|
| `animationClip.name` is present and non-empty | Schema/loader | `schemaViolation` |
| Animation names are unique in the aggregate asset | Loader semantic validation | `duplicateKey` |
| `duration` is not stored in binary | Schema/writer | `schemaViolation` if present as a known property |
| Clip duration equals the maximum last key time across owned timelines | Runtime constructor/writer derivation | n/a |
| Event timelines are absent from this `.bnb` slice | Schema/loader | `schemaViolation` for known event records in this slice |

Loaders derive duration after timeline validation. Writers must not accept a
source duration field as authoritative for binary output.

## Timeline Object Ownership

| Check | Owner | Category |
|-------|-------|----------|
| `boneTimeline` / `slotTimeline` appears under an `animationClip` parent | Loader structural validation | `schemaViolation` |
| Timeline target index is present and in range | Loader reference validation | `unknownRequiredReference` |
| Timeline kind tag is known and belongs to the object family | Registry/default decoding | `schemaViolation` |
| `timelineKeys` is present for each known timeline | Schema/loader | `schemaViolation` |
| Packed key payload is fully consumed | Loader byte/payload validation | `lengthMismatch` |
| Key payload shape matches the timeline kind | Loader semantic validation | `schemaViolation` |
| Key count is at least one | Loader semantic validation | `schemaViolation` |
| Key times are f32, finite, non-negative, and strictly increasing | Registry/default decoding plus loader semantic validation | `numericOutOfRange` for non-finite/out-of-domain time; `schemaViolation` or `orderingViolation` for non-increasing order |
| Bone/slot/attachment references resolve to known static domains | Loader reference validation | `unknownRequiredReference` |

Runtime timeline constructors in `runtime-nim/src/bony/anim/timelines.nim`
remain a defensive backstop for target names, key counts, sorted times, and
kind/payload mismatch. Binary loaders still own index resolution and packed
payload validation before constructing runtime timelines.

## Keyframe And Curve Ownership

| Check | Owner | Category |
|-------|-------|----------|
| Scalar/vector numeric values are finite and quantized to f32 | Registry/default decoding | `numericOutOfRange` |
| Color light/dark channels are in `0..1` after f32 quantization | Loader semantic validation | `numericOutOfRange` |
| Bezier `c1x` and `c2x` are in `0..1` after f32 quantization | Loader semantic validation | `numericOutOfRange` |
| Bezier `c1y` and `c2y` are finite f32 values | Registry/default decoding | `numericOutOfRange` |
| Curve kind is linear, stepped, or Bezier | Registry/default decoding | `schemaViolation` |
| Inherit key flags match `transformMode` | Loader semantic validation | `schemaViolation` |
| Attachment key `0` means no attachment | Schema/reference contract | n/a |
| Nonzero attachment key resolves to a region attachment | Loader reference validation | `unknownRequiredReference` |
| Sequence `delay` is finite f32 and non-negative | Registry/default decoding plus loader semantic validation | `numericOutOfRange` |
| Sequence `mode` is one of once, loop, pingpong, reverse, hold | Registry/default decoding | `schemaViolation` |
| Sequence `index` fits the registered unsigned integer domain | Registry/default decoding | `numericOutOfRange` |

The current runtime constructors reject some numeric-domain failures as
`schemaViolation`; conformance tests for file loaders should use
`numericOutOfRange` for non-finite, f32 overflow, and numeric contract domain
violations.

## State-Machine Object Ownership

| Check | Owner | Category |
|-------|-------|----------|
| `stateMachine.name` is present and non-empty | Schema/loader | `schemaViolation` |
| State-machine names are unique in the asset | Loader semantic validation | `duplicateKey` |
| A state machine owns at least one layer | Loader semantic validation | `schemaViolation` |
| Input/layer/state/listener names are present and non-empty | Schema/loader | `schemaViolation` |
| Input, layer, state, and listener names are unique in their owning scopes | Loader semantic validation | `duplicateKey` |
| Input kind is bool, number, or trigger | Registry/default decoding | `schemaViolation` |
| Inactive input default fields are absent/defaulted | Schema/loader | `schemaViolation` |
| Number input default is finite f32 | Registry/default decoding | `numericOutOfRange` |
| Layer `initialStateIndex` resolves, or omitted value resolves to state `0` | Loader reference validation | `unknownRequiredReference` |
| A layer owns at least one state | Loader semantic validation | `schemaViolation` |

Runtime constructors in `runtime-nim/src/bony/statemachine/core.nim` normalize
state-machine objects and re-check names, duplicates, default fields, and layer
shape. File loaders should still perform these checks while resolving binary
indices or JSON names so failures carry file context.

## State And Blend Ownership

| Check | Owner | Category |
|-------|-------|----------|
| State kind is clip or blend1d | Registry/default decoding | `schemaViolation` |
| Clip state has `stateClipIndex` and no blend-only fields | Schema/loader | `schemaViolation` |
| Clip state animation reference resolves | Loader reference validation | `unknownRequiredReference` |
| Blend1d state has `stateBlendInputIndex`, owns at least one blend clip, and has no direct clip fields | Schema/loader | `schemaViolation` |
| Blend input resolves to an input in the owning machine | Loader reference validation | `unknownRequiredReference` |
| Blend input kind is number | Loader semantic validation | `schemaViolation` |
| Blend clip animation reference resolves | Loader reference validation | `unknownRequiredReference` |
| Blend clip value is finite f32 | Registry/default decoding | `numericOutOfRange` |
| Blend clips sort by value during normalization | Runtime constructor/writer derivation | n/a |
| Duplicate blend clip values after f32 quantization | Loader semantic validation | `duplicateKey` |

The loader owns the duplicate-value check because JSON and binary must agree
after f32 quantization. Runtime sorting is normalization, not permission for
file loaders to accept ambiguous duplicate blend positions.

## Transition And Condition Ownership

| Check | Owner | Category |
|-------|-------|----------|
| Transition source and target state indices/names resolve in the owning layer | Loader reference validation | `unknownRequiredReference` |
| Transition contains at least one condition | Loader semantic validation | `schemaViolation` |
| Condition input reference resolves in the owning state machine | Loader reference validation | `unknownRequiredReference` |
| Condition kind is boolEquals, numeric comparison, or triggerSet | Registry/default decoding | `schemaViolation` |
| Condition kind matches referenced input kind | Loader semantic validation | `schemaViolation` |
| Bool condition carries only bool value fields | Schema/loader | `schemaViolation` |
| Numeric condition value is finite f32 | Registry/default decoding | `numericOutOfRange` |
| Numeric condition carries no bool value field | Schema/loader | `schemaViolation` |
| Trigger condition carries no value field | Schema/loader | `schemaViolation` |

Condition type matching must happen after input references resolve. Binary
loaders cannot validate a `conditionInputIndex` solely from the packed condition
payload because the input kind lives in the owning machine's input domain.

## Listener Ownership

| Check | Owner | Category |
|-------|-------|----------|
| Listener kind is stateEnter, stateExit, or transition | Registry/default decoding | `schemaViolation` |
| Listener layer reference resolves in the owning machine | Loader reference validation | `unknownRequiredReference` |
| State-enter listener has only `toState` | Schema/loader plus reference validation | `schemaViolation` for wrong field shape; `unknownRequiredReference` for unknown state |
| State-exit listener has only `fromState` | Schema/loader plus reference validation | `schemaViolation` for wrong field shape; `unknownRequiredReference` for unknown state |
| Transition listener has both source and target states | Schema/loader plus reference validation | `schemaViolation` for missing/wrong field shape; `unknownRequiredReference` for unknown state |
| Transition listener targets an existing transition in the layer | Loader semantic validation | `unknownRequiredReference` |

Listener validation runs after layer state and transition resolution. This
matches the reference-semantics contract and avoids accepting a listener that
names two states but no actual transition.

## Runtime Constructor Role

Runtime constructors remain intentionally strict:

- They reject empty names, wrong state/timeline variants, unknown runtime
  references passed by programmatic callers, duplicate blend values, and invalid
  state-machine type relationships.
- They quantize f32-backed values at construction time for programmatic parity.
- They derive clip duration and normalize blend clip ordering.

However, file loaders must not rely on constructor side effects for:

- Binary byte-level checks.
- Packed payload length/trailing-byte checks.
- Unknown object/property skip semantics.
- Index-domain resolution.
- Error categories required by shared conformance fixtures.
- File-context diagnostics.

This split lets runtime APIs stay useful for direct construction while keeping
`.bony` and `.bnb` loading deterministic, bounded, and cross-runtime testable.

## Follow-Up Work

Implementation Beads should add tests for:

- Each row in the ownership tables above.
- Cross-runtime category mapping for file loaders.
- Constructor backstop behavior for direct Nim API calls where it differs from
  file-loader category mapping.
- Duplicate blend values after f32 quantization.
- Listener transition-target validation after transition resolution.
