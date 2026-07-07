## M5 physics constraint fixed-substep integrator.

import std/math

import bony/constraints/common
import bony/model

const
  physicsFixedDt* = 1.0 / 60.0
  physicsMaxFrameDt* = 0.25
  physicsMaxSubsteps* = 8
  physicsStepEpsilon* = 1e-9
  physicsMassEpsilon* = 1e-6

type
  PhysicsParams* = object
    inertia*: float64
    strength*: float64
    damping*: float64
    mass*: float64
    gravity*: float64
    wind*: float64
    mix*: float64

  PhysicsChannelState* = object
    offset*: float64
    velocity*: float64
    previousTarget*: float64
    initialized*: bool

  PhysicsConstraintState* = object
    accumulator*: float64
    active*: bool
    channels*: array[PhysicsChannel, PhysicsChannelState]

  PhysicsChannelInput* = object
    channel*: PhysicsChannel
    target*: float64

  PhysicsChannelOutput* = object
    channel*: PhysicsChannel
    value*: float64
    offset*: float64
    velocity*: float64

  PhysicsUpdateResult* = object
    outputs*: seq[PhysicsChannelOutput]
    substeps*: int
    droppedSteps*: int
    accumulator*: float64


proc physicsParams*(
  inertia = 0.0;
  strength = 0.0;
  damping = 0.0;
  mass = 1.0;
  gravity = 0.0;
  wind = 0.0;
  mix = 1.0;
): PhysicsParams =
  PhysicsParams(
    inertia: requireFinite(inertia, "physics.inertia"),
    strength: requireFinite(strength, "physics.strength"),
    damping: requireFinite(damping, "physics.damping"),
    mass: requireNonNegative(mass, "physics.mass"),
    gravity: requireFinite(gravity, "physics.gravity"),
    wind: requireFinite(wind, "physics.wind"),
    mix: requireUnit(mix, "physics.mix"),
  )


proc physicsChannelInput*(channel: PhysicsChannel; target: float64): PhysicsChannelInput =
  PhysicsChannelInput(channel: channel, target: requireFinite(target, "physics.target"))


proc seedPhysicsChannel*(state: var PhysicsChannelState; target: float64) =
  state.offset = 0.0
  state.velocity = 0.0
  state.previousTarget = requireFinite(target, "physics.target")
  state.initialized = true


proc outputFor(channel: PhysicsChannel; state: PhysicsChannelState; target, mix: float64): PhysicsChannelOutput =
  PhysicsChannelOutput(
    channel: channel,
    value: target + state.offset * mix,
    offset: state.offset,
    velocity: state.velocity,
  )


proc validateInputs(inputs: openArray[PhysicsChannelInput]) =
  var seen: set[PhysicsChannel]
  for input in inputs:
    if input.channel in seen:
      raise newBonyLoadError(schemaViolation, "physics channel input must be unique")
    seen.incl input.channel
    discard requireFinite(input.target, "physics.target")


proc integrateChannel(state: var PhysicsChannelState; params: PhysicsParams; target: float64; firstSubstep: bool) =
  if firstSubstep:
    let targetDelta = target - state.previousTarget
    state.offset = state.offset - targetDelta * params.inertia

  var force = 0.0
  let mass = max(params.mass, physicsMassEpsilon)
  force += (-params.strength * state.offset) / mass
  force += params.gravity
  force += params.wind
  force += (-params.damping * state.velocity) / mass

  state.velocity = state.velocity + force * physicsFixedDt
  state.offset = state.offset + state.velocity * physicsFixedDt
  if firstSubstep:
    state.previousTarget = target


proc updatePhysicsConstraint*(
  state: var PhysicsConstraintState;
  params: PhysicsParams;
  inputs: openArray[PhysicsChannelInput];
  dt: float64;
  reset = false;
  active = true;
): PhysicsUpdateResult =
  let safeParams = physicsParams(
    inertia = params.inertia,
    strength = params.strength,
    damping = params.damping,
    mass = params.mass,
    gravity = params.gravity,
    wind = params.wind,
    mix = params.mix,
  )
  validateInputs(inputs)
  let safeDt = min(requireNonNegative(dt, "physics.dt"), physicsMaxFrameDt)

  if not active:
    state.active = false
    for input in inputs:
      result.outputs.add PhysicsChannelOutput(channel: input.channel, value: input.target)
    result.accumulator = state.accumulator
    return

  let shouldReset = reset or not state.active
  state.active = true

  if shouldReset:
    state.accumulator = 0.0
    for input in inputs:
      state.channels[input.channel].seedPhysicsChannel(input.target)

  for input in inputs:
    if not state.channels[input.channel].initialized:
      state.channels[input.channel].seedPhysicsChannel(input.target)

  state.accumulator += safeDt
  while result.substeps < physicsMaxSubsteps and state.accumulator >= physicsFixedDt:
    let firstSubstep = result.substeps == 0
    for input in inputs:
      state.channels[input.channel].integrateChannel(safeParams, input.target, firstSubstep)
    state.accumulator -= physicsFixedDt
    if abs(state.accumulator) <= physicsStepEpsilon:
      state.accumulator = 0.0
    inc result.substeps

  if state.accumulator >= physicsFixedDt:
    let dropped = int(floor((state.accumulator + physicsStepEpsilon) / physicsFixedDt))
    if dropped > 0:
      state.accumulator -= float64(dropped) * physicsFixedDt
      if abs(state.accumulator) <= physicsStepEpsilon:
        state.accumulator = 0.0
      result.droppedSteps = dropped

  for input in inputs:
    let channelState = state.channels[input.channel]
    result.outputs.add outputFor(input.channel, channelState, input.target, safeParams.mix)
  result.accumulator = state.accumulator
