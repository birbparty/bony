# Physics Integrator Contract

This contract defines deterministic runtime integration for `physics`
constraints. It refines the float-order rules in `docs/float-math-contract.md`
and must be followed before the M5 physics-constraint implementation.

## Scope

Physics constraints add spring-driven inertial offsets to selected bone
channels after animation, state-machine, world-transform, IK, transform, and
path constraints have produced the animated target pose.

This document owns:

- Integrator choice.
- Fixed substep size.
- Accumulator and max-substep policy.
- Initial state seeding.
- Reset semantics.
- Per-substep operation order.

It does not define UI authoring behavior or renderer behavior.

## State

Each live `SkeletonInstance` owns one physics state per active physics
constraint and constrained channel.

Per-channel state:

- `offset`: displacement from the animated target for the channel.
- `velocity`: velocity of that offset.
- `previousTarget`: target value used during the previous processed substep.
- `initialized`: whether this state has been seeded.

Per-constraint state:

- `accumulator`: unprocessed time in seconds.

All state values use f64/double. Serialized skeleton data may store parameters
as f32-backed values, but live physics state is not rounded to f32 until public
output boundaries.

## Fixed Step

The physics step is fixed at:

```text
fixedDt = 1 / 60 seconds
```

Each update call adds non-negative frame `dt` to `accumulator`.

Rules:

- `dt < 0` is a load/runtime error for deterministic playback.
- `dt == 0` performs no substeps and leaves state unchanged.
- `dt` values are clamped before accumulation to `maxFrameDt = 0.25` seconds.
- Process at most `maxSubsteps = 8` substeps per update.
- If `accumulator >= fixedDt` remains after `maxSubsteps`, drop the excess and
  keep `accumulator = accumulator mod fixedDt`.
- Otherwise carry the exact remainder in `accumulator`.

Dropping excess after the max-substep clamp prevents unbounded catch-up spirals
while keeping subsequent frames deterministic.

## Initialization

State is seeded lazily the first time an active constraint/channel is evaluated
for an instance, and whenever a reset is requested.

Initial values:

- `offset = 0`
- `velocity = 0`
- `previousTarget = current animated target`
- `initialized = true`

No spring force is applied during the seeding operation itself. The next
processed substep starts from the seeded state.

## Reset Semantics

A reset is requested by a physics timeline `reset` flag or by runtime events
such as explicit skeleton reset, animation seek, skin swap invalidating the
constraint, or host teleport.

Reset behavior:

1. Clear `accumulator` to `0`.
2. Seed every active channel using the initialization rules above.
3. Write the animated target directly to the affected bone/channel.
4. Do not emit residual velocity or offset.

If a reset and a non-zero `dt` occur in the same update call, reset is applied
first, then `dt` is accumulated. This keeps scrubbing/teleport behavior
deterministic while still allowing the frame to advance.

## Per-Substep Integration

The integrator is semi-implicit Euler. Explicit Euler is not allowed because it
diverges from semi-implicit Euler under spring forces.

For each processed substep and channel:

```text
target = animated target for this update
targetDelta = target - previousTarget
offset = offset - targetDelta * inertia

force = 0
force += (-strength * offset) / max(mass, massEpsilon)
force += gravity
force += wind
force += (-damping * velocity) / max(mass, massEpsilon)

velocity = velocity + force * fixedDt
offset = offset + velocity * fixedDt

output = target + offset * mix
previousTarget = target
```

Constants:

- `massEpsilon = 1e-6`
- `mix` is clamped to `[0, 1]` at load time.
- `inertia`, `strength`, `damping`, `mass`, `gravity`, and `wind` are loaded
  using the numeric rules from `docs/float-math-contract.md`.

Operation order is binding. Implementations must not algebraically rewrite or
reorder the force accumulation terms.

## Channel Mapping

Physics can affect `x`, `y`, `rotate`, `scaleX`, and `shearX` channels.

- `x`, `y`: units are skeleton world units.
- `rotate`, `shearX`: units are radians internally.
- `scaleX`: unitless scale delta.

Each enabled channel has independent `offset` and `velocity`. Shared
constraint parameters may feed all enabled channels, but channel state is not
shared.

When writing the result back:

- Translation writes to the affected bone world translation component.
- Rotation/shear writes angular offsets in radians.
- Scale writes additive scale delta before final mix.

The transform-composition contract owns how these channel writes are folded
back into matrices.

## Constraint Ordering

Physics constraints execute in the global constraint order defined by the
constraint-total-order contract. If multiple physics constraints affect the
same channel, each constraint reads the current channel value after earlier
constraints and writes its own output before later constraints run.

The physics accumulator is per constraint, not global. All constraints use the
same `fixedDt`, `maxFrameDt`, and `maxSubsteps`.

## Determinism Requirements

- Use f64/double for all live state and substep arithmetic.
- Process constraints, channels, and force terms in documented order.
- Do not vary `fixedDt` by runtime, frame rate, display refresh rate, or host
  platform.
- Do not use wall-clock time inside the integrator; only the supplied `dt`.
- Do not integrate inactive `skinRequired` constraints.
- When a constraint becomes inactive, preserve its state but do not advance its
  accumulator. When it becomes active again, reset it unless the caller
  explicitly asks to preserve physics state.

## Conformance Scenarios

The M5 physics conformance suite must include:

- `dt == 0` no-op.
- Single `1/60` step from a seeded state.
- Fractional `dt` carry across two updates.
- Large `dt` clamp with `maxSubsteps = 8`.
- Reset plus non-zero `dt` in the same update call.
- Translation and rotation channels using independent state.
- Two physics constraints affecting the same channel in ordered sequence.
- Inactive `skinRequired` constraint not advancing its accumulator.
