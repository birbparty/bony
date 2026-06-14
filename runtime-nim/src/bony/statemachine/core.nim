## M8 state-machine core, ordered layers, and evaluation skeleton.

import std/[math, sets]

import bony/anim/mixer
import bony/anim/timelines
import bony/model

type
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

  StateMachineLayerRuntime* = object
    layer*: StateMachineLayer
    currentState*: string
    time*: float64

  StateMachineRuntime* = object
    machine*: StateMachine
    layers*: seq[StateMachineLayerRuntime]

  EvaluatedStateMachineLayer* = object
    layer*: string
    state*: string
    time*: float64
    pose*: MixedPose

  EvaluatedStateMachine* = object
    layers*: seq[EvaluatedStateMachineLayer]


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


proc stateMachine*(name: string; layers: openArray[StateMachineLayer]): StateMachine =
  normalizeMachine(StateMachine(name: name, layers: @layers))


proc initStateMachineRuntime*(machine: StateMachine): StateMachineRuntime =
  result.machine = normalizeMachine(machine)
  for layer in result.machine.layers:
    result.layers.add StateMachineLayerRuntime(layer: layer, currentState: layer.initialState)


proc currentState*(runtime: StateMachineLayerRuntime): StateMachineState =
  runtime.layer.stateByName(runtime.currentState)


proc setState*(runtime: var StateMachineLayerRuntime; state: string; resetTime = true) =
  discard runtime.layer.stateByName(state)
  runtime.currentState = state
  if resetTime:
    runtime.time = 0.0


proc setState*(runtime: var StateMachineRuntime; layer: string; state: string; resetTime = true) =
  for item in runtime.layers.mitems:
    if item.layer.name == layer:
      item.setState(state, resetTime)
      return
  raise newBonyLoadError(unknownRequiredReference, "unknown state-machine layer: " & layer)


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


proc evaluate*(runtime: StateMachineRuntime; data: ref SkeletonData = nil): EvaluatedStateMachine =
  let runtime = normalizedRuntime(runtime)
  for layer in runtime.layers:
    let state = layer.currentState
    let active = layer.currentState()
    let time = layer.sampleTime(active)
    var animation = animationState(data, 1)
    animation.setAnimation(0, active.clip, loop = active.loop)
    animation.tracks[0].current.time = quantizeF32(time, "stateMachine.sample.time")
    result.layers.add EvaluatedStateMachineLayer(layer: layer.layer.name, state: state, time: time, pose: animation.sample())
