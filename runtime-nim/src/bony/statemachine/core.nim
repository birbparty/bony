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

  StateMachineConditionKind* = enum
    boolEqualsCondition,
    numberEqualsCondition,
    numberGreaterCondition,
    numberGreaterOrEqualCondition,
    numberLessCondition,
    numberLessOrEqualCondition,
    triggerSetCondition

  StateMachineCondition* = object
    input*: string
    kind*: StateMachineConditionKind
    boolValue*: bool
    numberValue*: float64

  StateMachineTransition* = object
    fromState*: string
    toState*: string
    conditions*: seq[StateMachineCondition]

  MatchedTransition = object
    layerIndex: int
    transition: StateMachineTransition

  StateMachineListenerKind* = enum
    stateEnterListener,
    stateExitListener,
    transitionListener

  StateMachineListener* = object
    name*: string
    kind*: StateMachineListenerKind
    layer*: string
    fromState*: string
    toState*: string

  StateMachineListenerEvent* = object
    listener*: string
    kind*: StateMachineListenerKind
    layer*: string
    fromState*: string
    toState*: string

  StateMachineStateKind* = enum
    clipState,
    blend1DState

  StateMachineBlendClip* = object
    clip*: AnimationClip
    value*: float64
    loop*: bool

  StateMachineState* = object
    name*: string
    kind*: StateMachineStateKind
    clip*: AnimationClip
    loop*: bool
    blendInput*: string
    blendClips*: seq[StateMachineBlendClip]

  StateMachineLayer* = object
    name*: string
    states*: seq[StateMachineState]
    initialState*: string
    transitions*: seq[StateMachineTransition]

  StateMachine* = object
    name*: string
    layers*: seq[StateMachineLayer]
    inputs*: seq[StateMachineInput]
    listeners*: seq[StateMachineListener]

  StateMachineLayerRuntime* = object
    layer*: StateMachineLayer
    currentState*: string
    time*: float64

  StateMachineRuntime* = object
    machine*: StateMachine
    layers*: seq[StateMachineLayerRuntime]
    inputs*: seq[StateMachineInputValue]
    events*: seq[StateMachineListenerEvent]

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


proc blendClipOrder(a, b: StateMachineBlendClip): int = cmp(a.value, b.value)


proc normalizeBlendClip(clip: StateMachineBlendClip): StateMachineBlendClip =
  validateName(clip.clip.name, "state-machine blend clip animation")
  StateMachineBlendClip(
    clip: clip.clip,
    value: quantizeF32(clip.value, "stateMachine.blendClip.value"),
    loop: clip.loop,
  )


proc normalizeState(state: StateMachineState): StateMachineState =
  validateName(state.name, "state-machine state")
  result = StateMachineState(name: state.name, kind: state.kind)
  case state.kind
  of clipState:
    validateName(state.clip.name, "state-machine state animation")
    if state.blendInput.len != 0 or state.blendClips.len != 0:
      raise newBonyLoadError(schemaViolation, "state-machine clip state must not contain blend data")
    result.clip = state.clip
    result.loop = state.loop
  of blend1DState:
    if state.clip.name.len != 0:
      raise newBonyLoadError(schemaViolation, "state-machine blend state must not contain a direct animation")
    if state.loop:
      raise newBonyLoadError(schemaViolation, "state-machine blend state must not set direct loop")
    validateName(state.blendInput, "state-machine blend input")
    if state.blendClips.len == 0:
      raise newBonyLoadError(schemaViolation, "state-machine blend state must contain at least one clip")
    result.blendInput = state.blendInput
    for input in state.blendClips:
      result.blendClips.add normalizeBlendClip(input)
    result.blendClips.sort(blendClipOrder)
    for index in 1 ..< result.blendClips.len:
      if result.blendClips[index - 1].value == result.blendClips[index].value:
        raise newBonyLoadError(duplicateKey, "duplicate state-machine blend clip value")


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


proc stateMachineBoolCondition*(input: string; value = true): StateMachineCondition =
  validateName(input, "state-machine condition input")
  StateMachineCondition(input: input, kind: boolEqualsCondition, boolValue: value)


proc stateMachineNumberCondition*(
  input: string;
  kind: StateMachineConditionKind;
  value: float64;
): StateMachineCondition =
  if kind notin {
    numberEqualsCondition,
    numberGreaterCondition,
    numberGreaterOrEqualCondition,
    numberLessCondition,
    numberLessOrEqualCondition,
  }:
    raise newBonyLoadError(schemaViolation, "state-machine number condition kind is not numeric")
  validateName(input, "state-machine condition input")
  StateMachineCondition(input: input, kind: kind, numberValue: quantizeF32(value, "stateMachine.condition.number"))


proc stateMachineTriggerCondition*(input: string): StateMachineCondition =
  validateName(input, "state-machine condition input")
  StateMachineCondition(input: input, kind: triggerSetCondition)


proc normalizeCondition(condition: StateMachineCondition): StateMachineCondition =
  validateName(condition.input, "state-machine condition input")
  result = StateMachineCondition(input: condition.input, kind: condition.kind)
  case condition.kind
  of boolEqualsCondition:
    requireInactiveNumberUnset(condition.numberValue, "stateMachine.condition.number")
    result.boolValue = condition.boolValue
  of numberEqualsCondition, numberGreaterCondition, numberGreaterOrEqualCondition, numberLessCondition, numberLessOrEqualCondition:
    if condition.boolValue:
      raise newBonyLoadError(schemaViolation, "state-machine number condition must not have a bool value")
    result.numberValue = quantizeF32(condition.numberValue, "stateMachine.condition.number")
  of triggerSetCondition:
    requireInactiveNumberUnset(condition.numberValue, "stateMachine.condition.number")
    if condition.boolValue:
      raise newBonyLoadError(schemaViolation, "state-machine trigger condition must not have a bool value")


proc stateMachineTransition*(
  fromState: string;
  toState: string;
  conditions: openArray[StateMachineCondition];
): StateMachineTransition =
  validateName(fromState, "state-machine transition from")
  validateName(toState, "state-machine transition to")
  if conditions.len == 0:
    raise newBonyLoadError(schemaViolation, "state-machine transition must contain at least one condition")
  result = StateMachineTransition(fromState: fromState, toState: toState)
  for condition in conditions:
    result.conditions.add normalizeCondition(condition)


proc stateMachineStateEnterListener*(name, layer, state: string): StateMachineListener =
  result = StateMachineListener(name: name, kind: stateEnterListener, layer: layer, toState: state)
  validateName(result.name, "state-machine listener")
  validateName(result.layer, "state-machine listener layer")
  validateName(result.toState, "state-machine listener state")


proc stateMachineStateExitListener*(name, layer, state: string): StateMachineListener =
  result = StateMachineListener(name: name, kind: stateExitListener, layer: layer, fromState: state)
  validateName(result.name, "state-machine listener")
  validateName(result.layer, "state-machine listener layer")
  validateName(result.fromState, "state-machine listener state")


proc stateMachineTransitionListener*(name, layer, fromState, toState: string): StateMachineListener =
  result = StateMachineListener(
    name: name,
    kind: transitionListener,
    layer: layer,
    fromState: fromState,
    toState: toState,
  )
  validateName(result.name, "state-machine listener")
  validateName(result.layer, "state-machine listener layer")
  validateName(result.fromState, "state-machine listener from")
  validateName(result.toState, "state-machine listener to")


proc stateMachineBlendClip*(clip: AnimationClip; value: float64; loop = false): StateMachineBlendClip =
  normalizeBlendClip(StateMachineBlendClip(clip: clip, value: value, loop: loop))


proc stateMachineState*(name: string; clip: AnimationClip; loop = false): StateMachineState =
  normalizeState(StateMachineState(name: name, kind: clipState, clip: clip, loop: loop))


proc stateMachineBlendState*(
  name: string;
  input: string;
  clips: openArray[StateMachineBlendClip];
): StateMachineState =
  normalizeState(StateMachineState(name: name, kind: blend1DState, blendInput: input, blendClips: @clips))


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
    let normalized = normalizeState(state)
    if normalized.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate state-machine state: " & normalized.name)
    names.incl(normalized.name)
    result.states.add normalized
  result.initialState = if layer.initialState.len == 0: result.states[0].name else: layer.initialState
  discard result.stateByName(result.initialState)
  for transition in layer.transitions:
    validateName(transition.fromState, "state-machine transition from")
    validateName(transition.toState, "state-machine transition to")
    discard result.stateByName(transition.fromState)
    discard result.stateByName(transition.toState)
    if transition.conditions.len == 0:
      raise newBonyLoadError(schemaViolation, "state-machine transition must contain at least one condition")
    var normalized = StateMachineTransition(fromState: transition.fromState, toState: transition.toState)
    for condition in transition.conditions:
      normalized.conditions.add normalizeCondition(condition)
    result.transitions.add normalized


proc stateMachineLayer*(
  name: string;
  states: openArray[StateMachineState];
  initialState = "";
  transitions: openArray[StateMachineTransition] = [];
): StateMachineLayer =
  normalizeLayer(StateMachineLayer(name: name, states: @states, initialState: initialState, transitions: @transitions))


proc inputByName(machine: StateMachine; name: string): StateMachineInput


proc layerByName(machine: StateMachine; name: string): StateMachineLayer =
  for layer in machine.layers:
    if layer.name == name:
      return layer
  raise newBonyLoadError(unknownRequiredReference, "unknown state-machine layer: " & name)


proc hasTransition(layer: StateMachineLayer; fromState, toState: string): bool =
  for transition in layer.transitions:
    if transition.fromState == fromState and transition.toState == toState:
      return true
  false


proc normalizeListener(machine: StateMachine; listener: StateMachineListener): StateMachineListener =
  validateName(listener.name, "state-machine listener")
  validateName(listener.layer, "state-machine listener layer")
  let layer = machine.layerByName(listener.layer)
  result = StateMachineListener(name: listener.name, kind: listener.kind, layer: listener.layer)
  case listener.kind
  of stateEnterListener:
    if listener.fromState.len != 0:
      raise newBonyLoadError(schemaViolation, "state-machine enter listener must not have a from state")
    validateName(listener.toState, "state-machine listener state")
    discard layer.stateByName(listener.toState)
    result.toState = listener.toState
  of stateExitListener:
    validateName(listener.fromState, "state-machine listener state")
    if listener.toState.len != 0:
      raise newBonyLoadError(schemaViolation, "state-machine exit listener must not have a to state")
    discard layer.stateByName(listener.fromState)
    result.fromState = listener.fromState
  of transitionListener:
    validateName(listener.fromState, "state-machine listener from")
    validateName(listener.toState, "state-machine listener to")
    discard layer.stateByName(listener.fromState)
    discard layer.stateByName(listener.toState)
    if not layer.hasTransition(listener.fromState, listener.toState):
      raise newBonyLoadError(unknownRequiredReference, "unknown state-machine transition listener target")
    result.fromState = listener.fromState
    result.toState = listener.toState


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
  for layer in result.layers:
    for state in layer.states:
      if state.kind == blend1DState:
        let input = result.inputByName(state.blendInput)
        if input.kind != numberInput:
          raise newBonyLoadError(schemaViolation, "state-machine blend input is not number: " & state.blendInput)
    for transition in layer.transitions:
      for condition in transition.conditions:
        let input = result.inputByName(condition.input)
        case condition.kind
        of boolEqualsCondition:
          if input.kind != boolInput:
            raise newBonyLoadError(schemaViolation, "state-machine condition input is not bool: " & condition.input)
        of numberEqualsCondition, numberGreaterCondition, numberGreaterOrEqualCondition, numberLessCondition, numberLessOrEqualCondition:
          if input.kind != numberInput:
            raise newBonyLoadError(schemaViolation, "state-machine condition input is not number: " & condition.input)
        of triggerSetCondition:
          if input.kind != triggerInput:
            raise newBonyLoadError(schemaViolation, "state-machine condition input is not trigger: " & condition.input)
  names.clear()
  for listener in machine.listeners:
    let normalized = result.normalizeListener(listener)
    if normalized.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate state-machine listener: " & normalized.name)
    names.incl(normalized.name)
    result.listeners.add normalized


proc stateMachine*(
  name: string;
  layers: openArray[StateMachineLayer];
  inputs: openArray[StateMachineInput] = [];
  listeners: openArray[StateMachineListener] = [];
): StateMachine =
  normalizeMachine(StateMachine(name: name, layers: @layers, inputs: @inputs, listeners: @listeners))


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


proc conditionMatches(runtime: StateMachineRuntime; condition: StateMachineCondition): bool =
  let input = runtime.machine.inputByName(condition.input)
  let index = runtime.inputValueIndex(condition.input)
  if index < 0:
    raise newBonyLoadError(unknownRequiredReference, "missing state-machine runtime input: " & condition.input)
  let value = runtime.inputs[index]
  case condition.kind
  of boolEqualsCondition:
    if input.kind != boolInput or value.kind != boolInput:
      raise newBonyLoadError(schemaViolation, "state-machine condition input is not bool: " & condition.input)
    value.boolValue == condition.boolValue
  of numberEqualsCondition:
    if input.kind != numberInput or value.kind != numberInput:
      raise newBonyLoadError(schemaViolation, "state-machine condition input is not number: " & condition.input)
    value.numberValue == condition.numberValue
  of numberGreaterCondition:
    if input.kind != numberInput or value.kind != numberInput:
      raise newBonyLoadError(schemaViolation, "state-machine condition input is not number: " & condition.input)
    value.numberValue > condition.numberValue
  of numberGreaterOrEqualCondition:
    if input.kind != numberInput or value.kind != numberInput:
      raise newBonyLoadError(schemaViolation, "state-machine condition input is not number: " & condition.input)
    value.numberValue >= condition.numberValue
  of numberLessCondition:
    if input.kind != numberInput or value.kind != numberInput:
      raise newBonyLoadError(schemaViolation, "state-machine condition input is not number: " & condition.input)
    value.numberValue < condition.numberValue
  of numberLessOrEqualCondition:
    if input.kind != numberInput or value.kind != numberInput:
      raise newBonyLoadError(schemaViolation, "state-machine condition input is not number: " & condition.input)
    value.numberValue <= condition.numberValue
  of triggerSetCondition:
    if input.kind != triggerInput or value.kind != triggerInput:
      raise newBonyLoadError(schemaViolation, "state-machine condition input is not trigger: " & condition.input)
    value.boolValue


proc transitionMatches(runtime: StateMachineRuntime; transition: StateMachineTransition): bool =
  for condition in transition.conditions:
    if not runtime.conditionMatches(condition):
      return false
  true


proc addListenerEvents(
  runtime: var StateMachineRuntime;
  kind: StateMachineListenerKind;
  layer: string;
  fromState: string;
  toState: string;
) =
  for listener in runtime.machine.listeners:
    if listener.kind != kind or listener.layer != layer:
      continue
    case kind
    of stateEnterListener:
      if listener.toState != toState:
        continue
    of stateExitListener:
      if listener.fromState != fromState:
        continue
    of transitionListener:
      if listener.fromState != fromState or listener.toState != toState:
        continue
    runtime.events.add StateMachineListenerEvent(
      listener: listener.name,
      kind: kind,
      layer: layer,
      fromState: fromState,
      toState: toState,
    )


proc applyTransitions(runtime: var StateMachineRuntime) =
  runtime = normalizedRuntime(runtime)
  let snapshot = runtime
  var matches: seq[MatchedTransition]
  var consumedTriggers = initHashSet[string]()
  for layerIndex, layer in snapshot.layers:
    for transition in layer.layer.transitions:
      if transition.fromState == layer.currentState and snapshot.transitionMatches(transition):
        matches.add MatchedTransition(layerIndex: layerIndex, transition: transition)
        for condition in transition.conditions:
          if condition.kind == triggerSetCondition:
            consumedTriggers.incl(condition.input)
        break
  for match in matches:
    let layerName = runtime.layers[match.layerIndex].layer.name
    runtime.addListenerEvents(stateExitListener, layerName, match.transition.fromState, match.transition.toState)
    runtime.addListenerEvents(transitionListener, layerName, match.transition.fromState, match.transition.toState)
    runtime.layers[match.layerIndex].setState(match.transition.toState)
    runtime.addListenerEvents(stateEnterListener, layerName, match.transition.fromState, match.transition.toState)
  for inputName in consumedTriggers:
    let index = runtime.inputValueIndex(inputName)
    if index < 0:
      raise newBonyLoadError(unknownRequiredReference, "missing state-machine runtime input: " & inputName)
    runtime.inputs[index].boolValue = false


proc update*(runtime: var StateMachineRuntime; dt: float64) =
  runtime = normalizedRuntime(runtime)
  runtime.events.setLen(0)
  let step = quantizeStateMachineTime(dt, "stateMachine.dt")
  for layer in runtime.layers.mitems:
    discard quantizeStateMachineTime(layer.time, "stateMachine.layer.time")
    layer.time = quantizeStateMachineTime(layer.time + step, "stateMachine.layer.time")
  runtime.applyTransitions()


proc sampleTime(layer: StateMachineLayerRuntime; state: StateMachineState): float64 =
  if state.kind == blend1DState:
    return layer.time
  if state.loop and state.clip.duration > 0:
    layer.time mod state.clip.duration
  else:
    min(layer.time, state.clip.duration)


proc sampleTime(time: float64; clip: AnimationClip; loop: bool): float64 =
  if loop and clip.duration > 0:
    time mod clip.duration
  else:
    min(time, clip.duration)


proc normalizedRuntime(runtime: StateMachineRuntime): StateMachineRuntime =
  result.machine = normalizeMachine(runtime.machine)
  result.events = runtime.events
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


proc addWeightedPose(
  output: var MixedPose;
  pose: MixedPose;
  weight: float64;
  replaceDiscrete = false;
) =
  let weight = min(1.0, max(0.0, weight))
  if weight <= 0:
    return
  for value in pose.scalars:
    output.scalars.add MixedScalar(target: value.target, kind: value.kind, value: value.value * weight)
  for value in pose.vectors:
    output.vectors.add MixedVector(target: value.target, kind: value.kind, x: value.x * weight, y: value.y * weight)
  for value in pose.colors:
    output.colors.add MixedColor(
      target: value.target,
      kind: value.kind,
      color: colorRgba(
        value.color.r * weight,
        value.color.g * weight,
        value.color.b * weight,
        value.color.a * weight,
      ),
    )
  for value in pose.colors2:
    output.colors2.add MixedColor2(
      target: value.target,
      color: colorRgba2(
        colorRgba(
          value.color.light.r * weight,
          value.color.light.g * weight,
          value.color.light.b * weight,
          value.color.light.a * weight,
        ),
        value.color.darkR * weight,
        value.color.darkG * weight,
        value.color.darkB * weight,
      ),
    )
  if replaceDiscrete:
    output.attachments = pose.attachments
    output.inherits = pose.inherits
    output.sequences = pose.sequences


proc blendedPose(lowPose, highPose: MixedPose; t: float64): MixedPose =
  var scalars = initTable[string, MixedScalar]()
  var vectors = initTable[string, MixedVector]()
  var colors = initTable[string, MixedColor]()
  var colors2 = initTable[string, MixedColor2]()
  var weighted = MixedPose()
  weighted.addWeightedPose(lowPose, 1.0 - t, replaceDiscrete = t < 0.5)
  weighted.addWeightedPose(highPose, t, replaceDiscrete = t >= 0.5)
  for value in weighted.scalars:
    let key = value.scalarKey
    let base = if key in scalars: scalars[key] else: MixedScalar(target: value.target, kind: value.kind)
    scalars[key] = MixedScalar(target: value.target, kind: value.kind, value: base.value + value.value)
  for value in weighted.vectors:
    let key = value.vectorKey
    let base = if key in vectors: vectors[key] else: MixedVector(target: value.target, kind: value.kind)
    vectors[key] = MixedVector(target: value.target, kind: value.kind, x: base.x + value.x, y: base.y + value.y)
  for value in weighted.colors:
    let key = value.colorKey
    let base = if key in colors: colors[key] else: MixedColor(target: value.target, kind: value.kind)
    colors[key] = MixedColor(
      target: value.target,
      kind: value.kind,
      color: colorRgba(
        base.color.r + value.color.r,
        base.color.g + value.color.g,
        base.color.b + value.color.b,
        base.color.a + value.color.a,
      ),
    )
  for value in weighted.colors2:
    let base = if value.target in colors2: colors2[value.target] else: MixedColor2(target: value.target)
    colors2[value.target] = MixedColor2(
      target: value.target,
      color: colorRgba2(
        colorRgba(
          base.color.light.r + value.color.light.r,
          base.color.light.g + value.color.light.g,
          base.color.light.b + value.color.light.b,
          base.color.light.a + value.color.light.a,
        ),
        base.color.darkR + value.color.darkR,
        base.color.darkG + value.color.darkG,
        base.color.darkB + value.color.darkB,
      ),
    )
  for value in scalars.values:
    result.scalars.add value
  result.scalars.sort(scalarOrder)
  for value in vectors.values:
    result.vectors.add value
  result.vectors.sort(vectorOrder)
  result.attachments = weighted.attachments
  result.inherits = weighted.inherits
  for value in colors.values:
    result.colors.add value
  result.colors.sort(colorOrder)
  for value in colors2.values:
    result.colors2.add value
  result.colors2.sort(color2Order)
  result.sequences = weighted.sequences


proc sampleClipPose(data: ref SkeletonData; clip: AnimationClip; loop: bool; time: float64): MixedPose =
  var animation = animationState(data, 1)
  animation.setAnimation(0, clip, loop = loop)
  animation.tracks[0].current.time = quantizeF32(time.sampleTime(clip, loop), "stateMachine.sample.time")
  animation.sample()


proc sampleBlendPose(runtime: StateMachineRuntime; state: StateMachineState; time: float64; data: ref SkeletonData): MixedPose =
  let input = runtime.getNumberInput(state.blendInput)
  let clips = state.blendClips
  if input <= clips[0].value:
    return sampleClipPose(data, clips[0].clip, clips[0].loop, time)
  for index in 0 ..< clips.len - 1:
    let low = clips[index]
    let high = clips[index + 1]
    if input <= high.value:
      let t = if high.value == low.value: 0.0 else: (input - low.value) / (high.value - low.value)
      return blendedPose(
        sampleClipPose(data, low.clip, low.loop, time),
        sampleClipPose(data, high.clip, high.loop, time),
        t,
      )
  sampleClipPose(data, clips[^1].clip, clips[^1].loop, time)


proc evaluate*(runtime: StateMachineRuntime; data: ref SkeletonData = nil): EvaluatedStateMachine =
  let runtime = normalizedRuntime(runtime)
  for layer in runtime.layers:
    let state = layer.currentState
    let active = layer.currentState()
    let time = layer.sampleTime(active)
    let pose =
      case active.kind
      of clipState:
        sampleClipPose(data, active.clip, active.loop, time)
      of blend1DState:
        runtime.sampleBlendPose(active, time, data)
    result.layers.add EvaluatedStateMachineLayer(layer: layer.layer.name, state: state, time: time, pose: pose)
    result.pose.overlayPose(pose)
