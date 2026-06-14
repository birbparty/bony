## M8 state-machine core, ordered layers, and evaluation skeleton.

import std/[algorithm, math, sets, tables]

import bony/anim/mixer
import bony/anim/timelines
import bony/model

type
  StateMachineInputKind* = enum
    boolInput,
    numberInput,
    triggerInput

  StateMachineInput* = object
    name*: string
    kind*: StateMachineInputKind
    defaultBool*: bool
    defaultNumber*: float64

  StateMachineInputValue* = object
    name*: string
    kind*: StateMachineInputKind
    boolValue*: bool
    numberValue*: float64

  StateMachineState* = object
    name*: string
    clip*: AnimationClip
    loop*: bool

  StateMachineLayer* = object
    name*: string
    states*: seq[StateMachineState]
    initialState*: string

  StateMachine* = object
    name*: string
    layers*: seq[StateMachineLayer]
    inputs*: seq[StateMachineInput]

  StateMachineLayerRuntime* = object
    layer*: StateMachineLayer
    currentState*: string
    time*: float64

  StateMachineRuntime* = object
    machine*: StateMachine
    layers*: seq[StateMachineLayerRuntime]
    inputs*: seq[StateMachineInputValue]

  EvaluatedStateMachineLayer* = object
    layer*: string
    state*: string
    time*: float64
    pose*: MixedPose

  EvaluatedStateMachine* = object
    layers*: seq[EvaluatedStateMachineLayer]
    pose*: MixedPose


proc quantizeStateMachineTime(value: float64; context: string): float64 =
  result = quantizeF32(value, context)
  if result < 0:
    raise newBonyLoadError(schemaViolation, context & " must be non-negative")


proc validateName(value, context: string) =
  if value.len == 0:
    raise newBonyLoadError(schemaViolation, context & " name must not be empty")


proc validateState(state: StateMachineState) =
  validateName(state.name, "state-machine state")
  validateName(state.clip.name, "state-machine state animation")


proc requireInactiveNumberUnset(value: float64; context: string) =
  let stored = quantizeF32(value, context)
  if stored != 0:
    raise newBonyLoadError(schemaViolation, context & " must not be set for this input kind")


proc normalizeInput(input: StateMachineInput): StateMachineInput =
  validateName(input.name, "state-machine input")
  result = StateMachineInput(name: input.name, kind: input.kind)
  case input.kind
  of boolInput:
    requireInactiveNumberUnset(input.defaultNumber, "stateMachine.input.defaultNumber")
    result.defaultBool = input.defaultBool
  of numberInput:
    if input.defaultBool:
      raise newBonyLoadError(schemaViolation, "state-machine number input must not have a bool default value")
    result.defaultNumber = quantizeF32(input.defaultNumber, "stateMachine.input.defaultNumber")
  of triggerInput:
    requireInactiveNumberUnset(input.defaultNumber, "stateMachine.input.defaultNumber")
    if input.defaultBool:
      raise newBonyLoadError(schemaViolation, "state-machine trigger input must not have a default value")


proc stateMachineBoolInput*(name: string; defaultValue = false): StateMachineInput =
  normalizeInput(StateMachineInput(name: name, kind: boolInput, defaultBool: defaultValue))


proc stateMachineNumberInput*(name: string; defaultValue = 0.0): StateMachineInput =
  normalizeInput(StateMachineInput(name: name, kind: numberInput, defaultNumber: defaultValue))


proc stateMachineTriggerInput*(name: string): StateMachineInput =
  normalizeInput(StateMachineInput(name: name, kind: triggerInput))


proc defaultValue(input: StateMachineInput): StateMachineInputValue =
  let input = normalizeInput(input)
  case input.kind
  of boolInput:
    StateMachineInputValue(name: input.name, kind: input.kind, boolValue: input.defaultBool)
  of numberInput:
    StateMachineInputValue(name: input.name, kind: input.kind, numberValue: input.defaultNumber)
  of triggerInput:
    StateMachineInputValue(name: input.name, kind: input.kind)


proc stateMachineState*(name: string; clip: AnimationClip; loop = false): StateMachineState =
  result = StateMachineState(name: name, clip: clip, loop: loop)
  validateState(result)


proc stateByName(layer: StateMachineLayer; name: string): StateMachineState =
  for state in layer.states:
    if state.name == name:
      return state
  raise newBonyLoadError(unknownRequiredReference, "unknown state-machine state: " & name)


proc normalizeLayer(layer: StateMachineLayer): StateMachineLayer =
  validateName(layer.name, "state-machine layer")
  if layer.states.len == 0:
    raise newBonyLoadError(schemaViolation, "state-machine layer must contain at least one state")
  var names = initHashSet[string]()
  result.name = layer.name
  for state in layer.states:
    validateState(state)
    if state.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate state-machine state: " & state.name)
    names.incl(state.name)
    result.states.add state
  result.initialState = if layer.initialState.len == 0: result.states[0].name else: layer.initialState
  discard result.stateByName(result.initialState)


proc stateMachineLayer*(
  name: string;
  states: openArray[StateMachineState];
  initialState = "";
): StateMachineLayer =
  normalizeLayer(StateMachineLayer(name: name, states: @states, initialState: initialState))


proc normalizeMachine(machine: StateMachine): StateMachine =
  validateName(machine.name, "state machine")
  if machine.layers.len == 0:
    raise newBonyLoadError(schemaViolation, "state machine must contain at least one layer")
  var names = initHashSet[string]()
  result.name = machine.name
  for layer in machine.layers:
    let normalized = normalizeLayer(layer)
    if normalized.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate state-machine layer: " & normalized.name)
    names.incl(normalized.name)
    result.layers.add normalized
  names.clear()
  for input in machine.inputs:
    let normalized = normalizeInput(input)
    if normalized.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate state-machine input: " & normalized.name)
    names.incl(normalized.name)
    result.inputs.add normalized


proc stateMachine*(
  name: string;
  layers: openArray[StateMachineLayer];
  inputs: openArray[StateMachineInput] = [];
): StateMachine =
  normalizeMachine(StateMachine(name: name, layers: @layers, inputs: @inputs))


proc initStateMachineRuntime*(machine: StateMachine): StateMachineRuntime =
  result.machine = normalizeMachine(machine)
  for layer in result.machine.layers:
    result.layers.add StateMachineLayerRuntime(layer: layer, currentState: layer.initialState)
  for input in result.machine.inputs:
    result.inputs.add input.defaultValue()


proc currentState*(runtime: StateMachineLayerRuntime): StateMachineState =
  runtime.layer.stateByName(runtime.currentState)


proc normalizedRuntime(runtime: StateMachineRuntime): StateMachineRuntime


proc setState*(runtime: var StateMachineLayerRuntime; state: string; resetTime = true) =
  discard runtime.layer.stateByName(state)
  runtime.currentState = state
  if resetTime:
    runtime.time = 0.0


proc setState*(runtime: var StateMachineRuntime; layer: string; state: string; resetTime = true) =
  runtime = normalizedRuntime(runtime)
  for item in runtime.layers.mitems:
    if item.layer.name == layer:
      item.setState(state, resetTime)
      return
  raise newBonyLoadError(unknownRequiredReference, "unknown state-machine layer: " & layer)


proc inputByName(machine: StateMachine; name: string): StateMachineInput =
  for input in machine.inputs:
    if input.name == name:
      return input
  raise newBonyLoadError(unknownRequiredReference, "unknown state-machine input: " & name)


proc inputValueIndex(runtime: StateMachineRuntime; name: string): int =
  for index, value in runtime.inputs:
    if value.name == name:
      return index
  -1


proc setBoolInput*(runtime: var StateMachineRuntime; name: string; value: bool) =
  runtime = normalizedRuntime(runtime)
  let input = runtime.machine.inputByName(name)
  if input.kind != boolInput:
    raise newBonyLoadError(schemaViolation, "state-machine input is not bool: " & name)
  runtime.inputs[runtime.inputValueIndex(name)].boolValue = value


proc getBoolInput*(runtime: StateMachineRuntime; name: string): bool =
  let runtime = normalizedRuntime(runtime)
  let input = runtime.machine.inputByName(name)
  if input.kind != boolInput:
    raise newBonyLoadError(schemaViolation, "state-machine input is not bool: " & name)
  runtime.inputs[runtime.inputValueIndex(name)].boolValue


proc setNumberInput*(runtime: var StateMachineRuntime; name: string; value: float64) =
  runtime = normalizedRuntime(runtime)
  let input = runtime.machine.inputByName(name)
  if input.kind != numberInput:
    raise newBonyLoadError(schemaViolation, "state-machine input is not number: " & name)
  runtime.inputs[runtime.inputValueIndex(name)].numberValue = quantizeF32(value, "stateMachine.input.number")


proc getNumberInput*(runtime: StateMachineRuntime; name: string): float64 =
  let runtime = normalizedRuntime(runtime)
  let input = runtime.machine.inputByName(name)
  if input.kind != numberInput:
    raise newBonyLoadError(schemaViolation, "state-machine input is not number: " & name)
  runtime.inputs[runtime.inputValueIndex(name)].numberValue


proc fireTrigger*(runtime: var StateMachineRuntime; name: string) =
  runtime = normalizedRuntime(runtime)
  let input = runtime.machine.inputByName(name)
  if input.kind != triggerInput:
    raise newBonyLoadError(schemaViolation, "state-machine input is not trigger: " & name)
  runtime.inputs[runtime.inputValueIndex(name)].boolValue = true


proc isTriggerSet*(runtime: StateMachineRuntime; name: string): bool =
  let runtime = normalizedRuntime(runtime)
  let input = runtime.machine.inputByName(name)
  if input.kind != triggerInput:
    raise newBonyLoadError(schemaViolation, "state-machine input is not trigger: " & name)
  runtime.inputs[runtime.inputValueIndex(name)].boolValue


proc clearTrigger*(runtime: var StateMachineRuntime; name: string) =
  runtime = normalizedRuntime(runtime)
  let input = runtime.machine.inputByName(name)
  if input.kind != triggerInput:
    raise newBonyLoadError(schemaViolation, "state-machine input is not trigger: " & name)
  runtime.inputs[runtime.inputValueIndex(name)].boolValue = false


proc consumeTrigger*(runtime: var StateMachineRuntime; name: string): bool =
  result = runtime.isTriggerSet(name)
  runtime.clearTrigger(name)


proc resetInputs*(runtime: var StateMachineRuntime) =
  runtime = normalizedRuntime(runtime)
  runtime.inputs.setLen(0)
  for input in runtime.machine.inputs:
    runtime.inputs.add input.defaultValue()


proc update*(runtime: var StateMachineRuntime; dt: float64) =
  let step = quantizeStateMachineTime(dt, "stateMachine.dt")
  for layer in runtime.layers.mitems:
    discard quantizeStateMachineTime(layer.time, "stateMachine.layer.time")
    layer.time = quantizeStateMachineTime(layer.time + step, "stateMachine.layer.time")


proc sampleTime(layer: StateMachineLayerRuntime; state: StateMachineState): float64 =
  if state.loop and state.clip.duration > 0:
    layer.time mod state.clip.duration
  else:
    min(layer.time, state.clip.duration)


proc normalizedRuntime(runtime: StateMachineRuntime): StateMachineRuntime =
  result.machine = normalizeMachine(runtime.machine)
  if runtime.layers.len != result.machine.layers.len:
    raise newBonyLoadError(schemaViolation, "state-machine runtime layer count must match machine")
  for index, layer in runtime.layers:
    let expected = result.machine.layers[index]
    if layer.layer.name != expected.name:
      raise newBonyLoadError(unknownRequiredReference, "state-machine runtime layer does not match machine")
    let current = StateMachineLayerRuntime(
      layer: expected,
      currentState: if layer.currentState.len == 0: expected.initialState else: layer.currentState,
      time: quantizeStateMachineTime(layer.time, "stateMachine.layer.time"),
    )
    discard current.currentState()
    result.layers.add current
  if runtime.inputs.len != result.machine.inputs.len:
    raise newBonyLoadError(schemaViolation, "state-machine runtime input count must match machine")
  var names = initHashSet[string]()
  for value in runtime.inputs:
    if value.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate state-machine runtime input: " & value.name)
    names.incl(value.name)
  for input in result.machine.inputs:
    let index = runtime.inputValueIndex(input.name)
    if index < 0:
      raise newBonyLoadError(unknownRequiredReference, "missing state-machine runtime input: " & input.name)
    let value = runtime.inputs[index]
    if value.kind != input.kind:
      raise newBonyLoadError(schemaViolation, "state-machine runtime input kind mismatch: " & input.name)
    case input.kind
    of boolInput:
      result.inputs.add StateMachineInputValue(name: input.name, kind: input.kind, boolValue: value.boolValue)
    of numberInput:
      result.inputs.add StateMachineInputValue(
        name: input.name,
        kind: input.kind,
        numberValue: quantizeF32(value.numberValue, "stateMachine.input.number"),
      )
    of triggerInput:
      result.inputs.add StateMachineInputValue(name: input.name, kind: input.kind, boolValue: value.boolValue)


proc scalarKey(value: MixedScalar): string = value.target & "\0" & $value.kind
proc vectorKey(value: MixedVector): string = value.target & "\0" & $value.kind
proc colorKey(value: MixedColor): string = value.target & "\0" & $value.kind


proc scalarOrder(a, b: MixedScalar): int =
  result = cmp(a.target, b.target)
  if result == 0:
    result = cmp(ord(a.kind), ord(b.kind))


proc vectorOrder(a, b: MixedVector): int =
  result = cmp(a.target, b.target)
  if result == 0:
    result = cmp(ord(a.kind), ord(b.kind))


proc attachmentOrder(a, b: MixedAttachment): int = cmp(a.target, b.target)
proc inheritOrder(a, b: MixedInherit): int = cmp(a.target, b.target)


proc colorOrder(a, b: MixedColor): int =
  result = cmp(a.target, b.target)
  if result == 0:
    result = cmp(ord(a.kind), ord(b.kind))


proc color2Order(a, b: MixedColor2): int = cmp(a.target, b.target)
proc sequenceOrder(a, b: MixedSequence): int = cmp(a.target, b.target)


proc overlayPose(base: var MixedPose; layer: MixedPose) =
  var scalars = initTable[string, MixedScalar]()
  var vectors = initTable[string, MixedVector]()
  var attachments = initTable[string, MixedAttachment]()
  var inherits = initTable[string, MixedInherit]()
  var colors = initTable[string, MixedColor]()
  var colors2 = initTable[string, MixedColor2]()
  var sequences = initTable[string, MixedSequence]()
  for value in base.scalars:
    scalars[value.scalarKey] = value
  for value in base.vectors:
    vectors[value.vectorKey] = value
  for value in base.attachments:
    attachments[value.target] = value
  for value in base.inherits:
    inherits[value.target] = value
  for value in base.colors:
    colors[value.colorKey] = value
  for value in base.colors2:
    colors2[value.target] = value
  for value in base.sequences:
    sequences[value.target] = value
  for value in layer.scalars:
    scalars[value.scalarKey] = value
  for value in layer.vectors:
    vectors[value.vectorKey] = value
  for value in layer.attachments:
    attachments[value.target] = value
  for value in layer.inherits:
    inherits[value.target] = value
  for value in layer.colors:
    colors[value.colorKey] = value
  for value in layer.colors2:
    colors2[value.target] = value
  for value in layer.sequences:
    sequences[value.target] = value
  base = MixedPose()
  for value in scalars.values:
    base.scalars.add value
  base.scalars.sort(scalarOrder)
  for value in vectors.values:
    base.vectors.add value
  base.vectors.sort(vectorOrder)
  for value in attachments.values:
    base.attachments.add value
  base.attachments.sort(attachmentOrder)
  for value in inherits.values:
    base.inherits.add value
  base.inherits.sort(inheritOrder)
  for value in colors.values:
    base.colors.add value
  base.colors.sort(colorOrder)
  for value in colors2.values:
    base.colors2.add value
  base.colors2.sort(color2Order)
  for value in sequences.values:
    base.sequences.add value
  base.sequences.sort(sequenceOrder)


proc evaluate*(runtime: StateMachineRuntime; data: ref SkeletonData = nil): EvaluatedStateMachine =
  let runtime = normalizedRuntime(runtime)
  for layer in runtime.layers:
    let state = layer.currentState
    let active = layer.currentState()
    let time = layer.sampleTime(active)
    var animation = animationState(data, 1)
    animation.setAnimation(0, active.clip, loop = active.loop)
    animation.tracks[0].current.time = quantizeF32(time, "stateMachine.sample.time")
    let pose = animation.sample()
    result.layers.add EvaluatedStateMachineLayer(layer: layer.layer.name, state: state, time: time, pose: pose)
    result.pose.overlayPose(pose)
