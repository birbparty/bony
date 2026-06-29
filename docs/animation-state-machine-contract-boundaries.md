# Animation And State-Machine Contract Boundaries

This note records the existing project-owned animation and state-machine surface
before assigning `.bnb` object families for the same data. It is intentionally an
inventory, not a new binary design.

The repository does not currently have `docs/specs/` or `docs/adr/`; contract
documents live directly under `docs/`, with supporting material in
`docs/spikes/` and `docs/prompts/`.

## Current Ownership Split

Nim and Dart do not expose the same loaded asset shape today.

- Nim `SkeletonData` owns static skeleton, slots, regions, paths, parameters,
  and deformers. Animations and state machines are parsed through
  `loadBonyJsonAnimations` and `loadBonyJsonStateMachines`, but
  `loadBonyJson` validates them and discards them from the returned
  `SkeletonData`.
- Dart `SkeletonData` owns the same static data plus `animations` and
  `stateMachines`. `applyPose` explicitly preserves `animations`,
  `parameters`, `deformers`, and `stateMachines`.
- Dart `.bnb` loading currently decodes static skeleton, path, parameter, and
  deformer object families only. It has no `.bnb` animation or state-machine
  type keys, so `loadBonyBnb` returns empty `animations` and `stateMachines`.

The binary contract work must therefore choose both binary object families and
the Nim loaded-asset shape. If `.bnb` carries animations/state machines, Nim
needs a place to preserve them after load instead of validating and dropping
them.

## Nim Animation Surface

`runtime-nim/src/bony/anim/timelines.nim` owns the reference animation model and
constructor validation.

Timeline curve kinds:

- `linearCurve`
- `steppedCurve`
- `bezierCurve`

Bezier curves require explicit `c1x`, `c1y`, `c2x`, and `c2y` control points.
All controls are quantized to f32; `c1x` and `c2x` must be in `0..1`.

Bone timeline kinds:

- Scalar keys: `rotateTimeline`, `translateXTimeline`, `translateYTimeline`,
  `scaleXTimeline`, `scaleYTimeline`, `shearXTimeline`, `shearYTimeline`
- Vector keys: `translateTimeline`, `scaleTimeline`, `shearTimeline`
- Inherit keys: `inheritTimeline`

Slot timeline kinds:

- Attachment keys: `attachmentTimeline`
- Color keys: `rgbaTimeline`, `rgbTimeline`, `alphaTimeline`
- Two-color keys: `rgba2Timeline`
- Sequence keys: `sequenceTimeline`

Sequence modes are `sequenceOnce`, `sequenceLoop`, `sequencePingpong`,
`sequenceReverse`, and `sequenceHold`.

Keyframe validation boundaries:

- Timeline target names must be non-empty.
- Scalar, vector, inherit, attachment, color, two-color, sequence, and event
  timelines must contain at least one keyframe.
- Non-event key times must be strictly increasing.
- Event key times may be non-decreasing.
- Key times are f32-quantized and non-negative.
- Scalar/vector numeric values are f32-quantized.
- Color channels are f32-quantized and constrained to `0..1`.
- Sequence delay is f32-quantized and non-negative.
- Inherit key flags must match the stored `transformMode`.
- Each timeline kind may carry only the matching key array.
- Animation names must be non-empty.
- Animation timeline targets must resolve to known bones or slots.
- Attachment timeline non-empty attachment names must resolve to known region
  attachments.
- Animation duration is derived from the greatest last key time across bone,
  slot, and event timelines.

Event data exists in the Nim timeline model and is included in `AnimationClip`,
but the current JSON parser does not load an `eventTimelines` field.

Event timeline boundaries:

- `EventData` stores `name`, `intValue`, `floatValue`, `stringValue`,
  `audioPath`, `volume`, and `balance`.
- Event names must be non-empty.
- Event `floatValue`, `volume`, and `balance` are f32-quantized.
- `EventKeyframe` stores a non-negative time and an event payload. Overloads can
  override the event's `intValue`, `floatValue`, and/or `stringValue` at the
  keyframe.
- Event timeline key times are non-decreasing, unlike the strictly increasing
  non-event timeline keys.
- Event timelines contribute to `AnimationClip.duration`.
- Dart currently has no `EventData`, `EventKeyframe`, or `EventTimeline`
  equivalent on `AnimationClip`; Dart `anim.dart` exposes an events list and
  `eventThreshold`, but event dispatch is placeholder-only until event
  timelines are ported.

## Nim State-Machine Surface

`runtime-nim/src/bony/statemachine/core.nim` owns the state-machine model,
validation, runtime, listener events, and evaluation skeleton.

Inputs:

- `boolInput`, with `defaultBool`
- `numberInput`, with f32-quantized `defaultNumber`
- `triggerInput`, with no default value

Conditions:

- `boolEqualsCondition`
- `numberEqualsCondition`
- `numberGreaterCondition`
- `numberGreaterOrEqualCondition`
- `numberLessCondition`
- `numberLessOrEqualCondition`
- `triggerSetCondition`

States:

- `clipState`, which references one `AnimationClip` and has a `loop` flag
- `blend1DState`, which references a number input and sorted blend clips

Layer and machine boundaries:

- State-machine, layer, state, input, transition, and listener names must be
  non-empty where applicable.
- A layer must contain at least one state.
- Duplicate state names are invalid within a layer.
- Empty `initialState` resolves to the first state in the layer.
- Transitions require at least one condition, and `fromState`/`toState` must
  resolve within the layer.
- A machine must contain at least one layer.
- Duplicate layer names, input names, and listener names are invalid.
- Blend state inputs must resolve to number inputs.
- Condition inputs must resolve and match the condition family:
  bool conditions require bool inputs, number comparisons require number
  inputs, and trigger conditions require trigger inputs.
- Listener targets must resolve to their layer and state. Transition listeners
  must target an existing transition.

Runtime behavior to preserve:

- Runtime layers initialize to each layer's resolved initial state.
- Runtime inputs initialize from declared defaults.
- `update(dt)` rejects negative/non-finite time through f32 quantization and
  advances layer times before transition matching.
- Transition matching uses a pre-transition runtime snapshot, collects at most
  the first matching transition per layer, then applies all matches in layer
  order.
- Applying a matched transition emits state-exit, transition, and state-enter
  listener events in that order, resets the transitioned layer time, and only
  then consumes trigger inputs used by the matched transitions.
- Evaluation samples clip states by loop/clamp time, samples blend1D states by
  number input, and overlays later layers over earlier layers per channel key.

## Nim JSON Boundary

`runtime-nim/src/bony/jsonio.nim` currently accepts root keys:

- `skeleton`
- `bones`
- `slots`
- `regions`
- `pathAttachments`
- `paths`
- `parameters`
- `deformers`
- `animations`
- `stateMachines`

Animation JSON shape:

- `animations[]` entries have `name`, optional `boneTimelines`, and optional
  `slotTimelines`.
- Bone timeline fields are `bone`, `property`, and `keyframes`.
- Bone timeline properties are `rotate`, `translateX`, `translateY`,
  `scaleX`, `scaleY`, `shearX`, `shearY`, `translate`, `scale`, `shear`, and
  `inherit`.
- Scalar keyframes use `t`, `value`, and optional `curve`/Bezier controls.
- Vector keyframes use `t`, optional `x`, optional `y`, optional `curve`,
  optional `curveX`, optional `curveY`, and Bezier controls.
- Inherit keyframes use `t`, `inheritRotation`, `inheritScale`,
  `inheritReflection`, and `transformMode`.
- Slot timeline fields are `slot`, `property`, and `keyframes`.
- Slot properties are `attachment`, `rgba`, `rgb`, `alpha`, `rgba2`, and
  `sequence`.
- Attachment keyframes use `t` and optional `attachment`.
- Color keyframes use `t`, optional `r`, `g`, `b`, `a`, optional `curve`, and
  Bezier controls.
- Two-color keyframes also use `dr`, `dg`, and `db`.
- Sequence keyframes use `t`, optional `index`, optional `delay`, and optional
  `mode`.

State-machine JSON shape:

- `stateMachines[]` entries have `name`, optional `inputs`, required `layers`,
  and optional `listeners`.
- Inputs use `name`, `kind`, and optional `default`; kinds are `bool`,
  `number`, and `trigger`.
- Layers use `name`, `states`, optional `initialState`, and optional
  `transitions`.
- States use `kind` `clip` with `clip`/`loop`, or `kind` `blend1d` with
  `blendInput` and `blendClips`.
- Blend clips use `clip`, `value`, and optional `loop`.
- Transitions use `fromState`, `toState`, and `conditions`.
- Conditions use `input`, `kind`, and optional/required `value` depending on
  kind. Condition kinds are `boolEquals`, `numberEquals`, `numberGreater`,
  `numberGreaterOrEqual`, `numberLess`, `numberLessOrEqual`, and `triggerSet`.
- Listeners use `name`, `kind`, `layer`, and the state fields required by
  `stateEnter`, `stateExit`, or `transition`.

Important persistence boundary:

- `loadBonyJson` builds a `SkeletonData`, parses animations and state machines
  to validate them, and discards both parsed results.
- `loadBonyJsonAnimations` reparses and returns a table of `AnimationClip` by
  name.
- `loadBonyJsonStateMachines` reparses animations first, then parses and
  returns state machines.
- `toBonyJson` serializes only `SkeletonData`; it does not emit animations or
  state machines because Nim `SkeletonData` does not store them.

## Nim SkeletonData Boundary

`runtime-nim/src/bony/model.nim` `SkeletonData` currently stores:

- `header`
- `bones`
- `slots`
- `regions`
- `pathAttachments`
- `paths`
- `parameters`
- `deformers`

It does not store animations or state machines.

Existing validation to keep separate from animation/state-machine validation:

- Skeleton name is required.
- Bone names are unique and non-empty.
- Bone parents must resolve and appear before children.
- Bone inherit flags must match `transformMode`.
- Region names are unique and dimensions are non-negative.
- Slot names are unique, slot bones resolve, and setup attachments resolve to
  regions.
- Path attachment names are unique and all path control points are finite f64.
- Path constraint names are unique; bone, target, and path references resolve.
- Parameter names are unique, `min < max`, and defaults are within range.
- Deformer ids and orders are unique, parents resolve, parent order is earlier,
  and deformer parent graphs are acyclic.

## Dart Loaded Model Boundary

`runtime-dart/lib/src/model.dart` stores animations and state machines directly
on `SkeletonData`:

- `animations: List<AnimationClip>`
- `stateMachines: List<StateMachineData>`

Dart animation data mirrors the Nim concepts with Dart names:

- `TimelineCurveKind.linear`, `stepped`, `bezier`
- `BoneTimelineKind.rotate`, `translateX`, `translateY`, `scaleX`, `scaleY`,
  `shearX`, `shearY`, `translate`, `scale`, `shear`, `inherit`
- `SlotTimelineKind.attachment`, `rgba`, `rgb`, `alpha`, `rgba2`, `sequence`
- `SequenceMode.once`, `loop`, `pingpong`, `reverse`, `hold`
- `AnimationClip` stores name, duration, bone timelines, and slot timelines.
- `AnimationClip` does not store event timelines on Dart today.

Dart state-machine data mirrors the Nim JSON-level representation:

- `StateMachineInputKind.bool_`, `number`, `trigger`
- Condition kinds matching the JSON strings.
- Listener kind `transition_` uses a trailing underscore for Dart naming.
- `StateMachineBlendClip` stores `clipName`, not an embedded clip object.
- `StateMachineState` stores `clipName` and `blendInput` by name.
- `StateMachineData` stores name, layers, inputs, and listeners.

## Dart JSON And Binary Boundary

`runtime-dart/lib/src/loader.dart` JSON loading parses and preserves:

- Parses `animations` into `SkeletonData.animations`.
- Parses `stateMachines` into `SkeletonData.stateMachines`.

Dart JSON loading validates:

- Validates animation bone/slot references against static skeleton names.
- Validates state-machine references against loaded animation names, inputs,
  layer states, and listener target layers/states.
- Sorts blend clips by value and rejects duplicate blend values.

The Dart JSON validation is not identical to Nim:

- Dart preserves animations/state machines on `SkeletonData`; Nim discards them
  from `loadBonyJson`.
- Dart JSON parsing does not reject unknown root/object keys with the same
  strict `validateKnownKeys` behavior used by Nim.
- Dart sequence mode parsing defaults unknown or missing values to `once`;
  Nim rejects unknown sequence modes.
- Dart animation validation checks timeline bone and slot targets, but it does
  not validate non-empty attachment timeline attachment names against regions the
  way Nim does.
- Dart state-machine validation does not currently enforce all Nim non-empty and
  duplicate-name constraints for machines, layers, states, inputs, and
  listeners.
- Dart validation does not reject zero-layer state machines with the same
  explicit `state machine must contain at least one layer` boundary as Nim.
- Dart transition parsing does not reject empty condition arrays before runtime
  validation the same way Nim constructors do.
- Dart validates listener layers and endpoint states, but it does not require a
  transition listener to target an existing transition.
- Dart validates that blend inputs exist, but not that the referenced input is a
  number input.
- Nim validates condition input type compatibility during machine construction;
  Dart currently validates condition input existence, but not all condition
  kind/input-kind combinations at load time.
- Dart currently lacks event timeline storage and dispatch, while Nim has an
  event timeline model even though JSON loading does not populate it.

`loadBonyBnb` currently omits animations and state machines entirely:

- Known `.bnb` type keys cover skeleton, bones, slots, regions, paths,
  path attachments, parameters, deformers, warp lattices, rotation deformers,
  keyform blends, and keyforms.
- No `.bnb` type keys or property keys are assigned for animation clips,
  timelines, keyframes, event timelines, state machines, inputs, layers,
  states, transitions, conditions, listeners, or blend clips.
- `_bnbDecode` constructs `SkeletonData` without `animations` or
  `stateMachines`, so the default empty lists are used.
- Binary references are index/range checked after byte-level validation.
  Unknown skipped objects and properties are not semantic targets, and a known
  reference to skipped unknown binary content must remain a load error rather
  than an implicit extension-preservation mechanism.

## Dart Runtime Boundary

`runtime-dart/lib/src/anim.dart` owns sampling, mixing, and pose application.

Animation behavior to preserve:

- Bezier evaluation uses a 16-sample x table and two Newton-Raphson refinements.
- Scalar/vector/color/two-color curves interpolate; stepped curves hold the
  previous value.
- Attachment, inherit, and sequence channels are stepped.
- Track entries support loop/clamp sample time, queueing, mix duration, blend
  mode, alpha, time scale, attachment threshold, and event threshold.
- `MixedPose` carries scalar, vector, attachment, inherit, color, two-color,
  and sequence channels.
- `applyPose` applies scalar, vector, inherit, and attachment channels to a new
  `SkeletonData`; color and sequence channels remain renderer-level output and
  are not applied to static `SlotData`.

`runtime-dart/lib/src/statemachine.dart` owns runtime state-machine behavior:

- Runtime inputs expose bool, number, and trigger setters/getters.
- `update(dt)` rejects negative `dt`, quantizes time, advances layer times,
  applies first matching transitions per layer, emits listener events, resets
  transitioned layer time, and consumes trigger inputs.
- `evaluate(data)` samples each active layer state, supports direct clip and
  blend1D states, overlays later layers by channel key, and reports per-layer
  sampled pose/time.
- Blend1D poses lerp scalar, vector, color, and two-color channels; attachment,
  inherit, and sequence channels snap at `t >= 0.5`.

## Binary Contract Implications

The next binary contract decisions must preserve these boundaries:

- Assign object families for animation clips, bone timelines, slot timelines,
  keyframes, and the currently modelled event timeline shape.
- Treat event timelines as an explicit compatibility decision: either defer
  `.bnb` event families until JSON/model/runtime parity exists, or define the
  JSON import/export and Dart model/runtime behavior before binary starts
  preserving event payloads.
- Decide whether keyframes are child objects, packed arrays, or composite
  property payloads. The choice must preserve per-kind key ownership and sorted
  time validation.
- Assign object families for state machines, inputs, layers, states,
  transitions, conditions, listeners, and blend clips.
- Preserve cross-reference validation: animation timeline targets resolve to
  bones/slots/regions, state-machine clip references resolve to animations, and
  state-machine conditions/listeners resolve to declared inputs/layers/states.
- Decide Nim asset ownership before implementing `.bnb` load preservation:
  either extend `SkeletonData` to carry animations/state machines or introduce a
  separate loaded asset wrapper used by JSON and binary loaders. The decision
  also needs to cover conversion/export APIs such as `toBonyJson`; binary
  preservation alone will not make round trips complete if JSON emission still
  serializes only static `SkeletonData`.
- Keep JSON and `.bnb` loader semantics aligned. The current Dart/Nim
  differences above should be treated as open compatibility decisions, not as
  accidental details to encode permanently.
