/// M5 physics constraint fixed-substep integrator.
///
/// Clean-room port of the bony Nim reference
/// `runtime-nim/src/bony/constraints/physics_constraints.nim` (project-owned
/// spring integrator, ported symbol-for-symbol and step-for-step). The
/// per-substep force-accumulation order, the fixed step, the max-substep clamp,
/// and the drop rule are the binding numeric contract from
/// `docs/physics-integrator-contract.md` and must not be algebraically
/// rewritten. Not derived from any third-party runtime.
import 'dart:math' as math;

import 'numeric_guards.dart' show requireFinite, requireMix, requireNonNegative;

/// Fixed simulation step (60 Hz). Never varies by runtime/frame-rate/host.
const double physicsFixedDt = 1.0 / 60.0;

/// Largest frame delta consumed in one advance; excess is clamped.
const double physicsMaxFrameDt = 0.25;

/// Largest number of fixed substeps integrated in one advance.
const int physicsMaxSubsteps = 8;

/// Accumulator snap tolerance (treat |accumulator| below this as exactly 0).
const double physicsStepEpsilon = 1e-9;

/// Floor applied to `mass` when dividing, so a zero mass does not divide by 0.
const double physicsMassEpsilon = 1e-6;

/// Channels a physics constraint may drive. Ordinals define the wire bitmask
/// bit positions (x=bit0 .. shearX=bit4), mirroring the Nim `PhysicsChannel`.
enum PhysicsChannel { x, y, rotate, scaleX, shearX }

/// Integrator inputs for one constraint. Mirrors the Nim `PhysicsParams`.
class PhysicsParams {
  const PhysicsParams({
    required this.inertia,
    required this.strength,
    required this.damping,
    required this.mass,
    required this.gravity,
    required this.wind,
    required this.mix,
  });

  final double inertia;
  final double strength;
  final double damping;
  final double mass;
  final double gravity;
  final double wind;
  final double mix;
}

/// Live per-channel spring state carried across frames. Mirrors the Nim
/// `PhysicsChannelState`.
class PhysicsChannelState {
  double offset = 0.0;
  double velocity = 0.0;
  double previousTarget = 0.0;
  bool initialized = false;
}

/// Live per-constraint state: substep accumulator, activity flag, and one
/// [PhysicsChannelState] per channel. Mirrors the Nim `PhysicsConstraintState`
/// (an array over every channel, default-constructed / un-initialized).
class PhysicsConstraintState {
  double accumulator = 0.0;
  bool active = false;
  final Map<PhysicsChannel, PhysicsChannelState> channels = {
    for (final channel in PhysicsChannel.values) channel: PhysicsChannelState(),
  };
}

/// One channel's animated target for an advance. Mirrors `PhysicsChannelInput`.
class PhysicsChannelInput {
  const PhysicsChannelInput(this.channel, this.target);
  final PhysicsChannel channel;
  final double target;
}

/// One channel's solved output. Mirrors `PhysicsChannelOutput`.
class PhysicsChannelOutput {
  const PhysicsChannelOutput({
    required this.channel,
    required this.value,
    required this.offset,
    required this.velocity,
  });
  final PhysicsChannel channel;
  final double value;
  final double offset;
  final double velocity;
}

/// Result of one advance. Mirrors `PhysicsUpdateResult`.
class PhysicsUpdateResult {
  PhysicsUpdateResult();
  final List<PhysicsChannelOutput> outputs = [];
  int substeps = 0;
  int droppedSteps = 0;
  double accumulator = 0.0;
}

/// Build validated integrator params. Defaults mirror the Nim `physicsParams`
/// proc (mass=1.0, mix=1.0, everything else 0.0), including the bounds checks.
PhysicsParams physicsParams({
  double inertia = 0.0,
  double strength = 0.0,
  double damping = 0.0,
  double mass = 1.0,
  double gravity = 0.0,
  double wind = 0.0,
  double mix = 1.0,
}) {
  return PhysicsParams(
    inertia: requireFinite(inertia, 'physics.inertia'),
    strength: requireFinite(strength, 'physics.strength'),
    damping: requireFinite(damping, 'physics.damping'),
    mass: requireNonNegative(mass, 'physics.mass'),
    gravity: requireFinite(gravity, 'physics.gravity'),
    wind: requireFinite(wind, 'physics.wind'),
    mix: requireMix(mix, 'physics.mix'),
  );
}

PhysicsChannelInput physicsChannelInput(
        PhysicsChannel channel, double target) =>
    PhysicsChannelInput(channel, requireFinite(target, 'physics.target'));

/// Seed a channel to rest at the given target (offset/velocity zero), matching
/// the Nim `seedPhysicsChannel`.
void seedPhysicsChannel(PhysicsChannelState state, double target) {
  state.offset = 0.0;
  state.velocity = 0.0;
  state.previousTarget = requireFinite(target, 'physics.target');
  state.initialized = true;
}

PhysicsChannelOutput _outputFor(PhysicsChannel channel,
    PhysicsChannelState state, double target, double mix) {
  return PhysicsChannelOutput(
    channel: channel,
    value: target + state.offset * mix,
    offset: state.offset,
    velocity: state.velocity,
  );
}

void _validateInputs(List<PhysicsChannelInput> inputs) {
  final seen = <PhysicsChannel>{};
  for (final input in inputs) {
    if (!seen.add(input.channel)) {
      throw const FormatException('physics channel input must be unique');
    }
    requireFinite(input.target, 'physics.target');
  }
}

/// One fixed substep. The order of the four force terms and the
/// velocity-then-offset update is the binding contract — do not reorder.
void integrateChannel(PhysicsChannelState state, PhysicsParams params,
    double target, bool firstSubstep) {
  if (firstSubstep) {
    final targetDelta = target - state.previousTarget;
    state.offset = state.offset - targetDelta * params.inertia;
  }

  var force = 0.0;
  final mass = math.max(params.mass, physicsMassEpsilon);
  force += (-params.strength * state.offset) / mass;
  force += params.gravity;
  force += params.wind;
  force += (-params.damping * state.velocity) / mass;

  state.velocity = state.velocity + force * physicsFixedDt;
  state.offset = state.offset + state.velocity * physicsFixedDt;
  if (firstSubstep) {
    state.previousTarget = target;
  }
}

/// Advance one physics constraint by `dt`, mutating `state`. Mirrors the Nim
/// `updatePhysicsConstraint`: clamp dt, (re)seed, integrate up to
/// [physicsMaxSubsteps] fixed substeps, apply the drop rule, and emit outputs.
PhysicsUpdateResult updatePhysicsConstraint(
  PhysicsConstraintState state,
  PhysicsParams params,
  List<PhysicsChannelInput> inputs,
  double dt, {
  bool reset = false,
  bool active = true,
}) {
  final result = PhysicsUpdateResult();
  final safeParams = physicsParams(
    inertia: params.inertia,
    strength: params.strength,
    damping: params.damping,
    mass: params.mass,
    gravity: params.gravity,
    wind: params.wind,
    mix: params.mix,
  );
  _validateInputs(inputs);
  final safeDt =
      math.min(requireNonNegative(dt, 'physics.dt'), physicsMaxFrameDt);

  if (!active) {
    state.active = false;
    for (final input in inputs) {
      result.outputs.add(PhysicsChannelOutput(
        channel: input.channel,
        value: input.target,
        offset: state.channels[input.channel]!.offset,
        velocity: state.channels[input.channel]!.velocity,
      ));
    }
    result.accumulator = state.accumulator;
    return result;
  }

  final shouldReset = reset || !state.active;
  state.active = true;

  if (shouldReset) {
    state.accumulator = 0.0;
    for (final input in inputs) {
      seedPhysicsChannel(state.channels[input.channel]!, input.target);
    }
  }

  for (final input in inputs) {
    if (!state.channels[input.channel]!.initialized) {
      seedPhysicsChannel(state.channels[input.channel]!, input.target);
    }
  }

  state.accumulator += safeDt;
  while (result.substeps < physicsMaxSubsteps &&
      state.accumulator >= physicsFixedDt) {
    final firstSubstep = result.substeps == 0;
    for (final input in inputs) {
      integrateChannel(state.channels[input.channel]!, safeParams, input.target,
          firstSubstep);
    }
    state.accumulator -= physicsFixedDt;
    if (state.accumulator.abs() <= physicsStepEpsilon) {
      state.accumulator = 0.0;
    }
    result.substeps += 1;
  }

  if (state.accumulator >= physicsFixedDt) {
    final dropped =
        ((state.accumulator + physicsStepEpsilon) / physicsFixedDt).floor();
    if (dropped > 0) {
      state.accumulator -= dropped * physicsFixedDt;
      if (state.accumulator.abs() <= physicsStepEpsilon) {
        state.accumulator = 0.0;
      }
      result.droppedSteps = dropped;
    }
  }

  for (final input in inputs) {
    final channelState = state.channels[input.channel]!;
    result.outputs.add(
        _outputFor(input.channel, channelState, input.target, safeParams.mix));
  }
  result.accumulator = state.accumulator;
  return result;
}

/// Decode the wire channel bitmask (x=bit0 .. shearX=bit4) into a channel set,
/// rejecting unknown bits. Mirrors the Nim `physicsChannelsFromMask`.
Set<PhysicsChannel> physicsChannelsFromMask(int mask,
    {String context = 'physicsConstraint.channels'}) {
  final limit = 1 << PhysicsChannel.values.length;
  if (mask < 0 || mask >= limit) {
    throw FormatException('$context has unknown channel bits set');
  }
  final result = <PhysicsChannel>{};
  for (final channel in PhysicsChannel.values) {
    if ((mask & (1 << channel.index)) != 0) {
      result.add(channel);
    }
  }
  return result;
}

/// Pack a channel set into the wire bitmask. Mirrors `physicsChannelsToMask`.
int physicsChannelsToMask(Set<PhysicsChannel> channels) {
  var mask = 0;
  for (final channel in channels) {
    mask |= 1 << channel.index;
  }
  return mask;
}
