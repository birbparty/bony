# Physics Integrator Contract

This contract defines deterministic runtime integration for `physics`
constraints. It refines the float-order rules in `docs/float-math-contract.md`
and must be followed before the M5 physics-constraint implementation.

## Scope

Physics constraints add spring-driven inertial offsets to selected logical bone
channels. They run at the physics stage of the pose pipeline, after the
non-physics world-transform/constraint pass has produced the animated target
pose. If the later constraint-total-order contract allows physics constraints
to interleave with other constraint kinds, it must update this document and the
physics conformance expectations in the same change.

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
- `dt == 0` performs no substeps. Resets are still applied before this no-op
  check, so a reset with `dt == 0` clears/seeds state and writes the target.
- `dt` values are clamped before accumulation to `maxFrameDt = 0.25` seconds.
- Process at most `maxSubsteps = 8` substeps per update.
- If `accumulator >= fixedDt` remains after `maxSubsteps`, drop whole excess
  steps with:
  `droppedSteps = floor((accumulator + stepEpsilon) / fixedDt)`;
  `accumulator = accumulator - droppedSteps * fixedDt`; if
  `abs(accumulator) <= stepEpsilon`, set it to `0`.
- Otherwise carry the exact remainder in `accumulator`.

Constants:

- `stepEpsilon = 1e-9`

Dropping excess after the max-substep clamp prevents unbounded catch-up spirals
while keeping subsequent frames deterministic.
`maxFrameDt` intentionally exceeds `maxSubsteps * fixedDt`; the frame clamp
bounds hostile or paused hosts, while the substep clamp bounds CPU work.

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

If a reset and `dt` occur in the same update call, reset is applied first, then
`dt` is accumulated. With non-zero `dt`, gravity/wind/spring terms may move the
freshly reset channel during that same call. This is intentional: reset removes
old state, not current-frame forces.

If an update interval crosses a physics timeline reset key, split the update at
the reset time: integrate the pre-reset segment, apply reset, then integrate
the remaining segment.

## Per-Substep Integration

The integrator is semi-implicit Euler. Explicit Euler is not allowed because it
diverges from semi-implicit Euler under spring forces.

Targets are sampled once per outer update after animation and non-physics
constraints have produced the target pose. `targetDelta` is applied on the
first substep that sees a changed target; later substeps in the same update use
`targetDelta = 0`.

For each processed substep and channel:

```text
target = animated target for this update
targetDelta = target - previousTarget  # first substep only; otherwise 0
offset = offset - targetDelta * inertia

force = 0
force += (-strength * offset) / max(mass, massEpsilon)
force += gravity
force += wind
force += (-damping * velocity) / max(mass, massEpsilon)

velocity = velocity + force * fixedDt
offset = offset + velocity * fixedDt

output = target + offset * mix
previousTarget = target  # after the first substep for this update
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

Physics emits logical channel outputs:

- Translation output values are skeleton world-unit channel values.
- Rotation/shear output values are radians.
- Scale output values are unitless scale channel values.

The transform-composition contract owns how logical channel outputs are folded
back into local/world matrices, including inherit modes, reflection factoring,
and decomposition/writeback details.

## Constraint Ordering

Physics constraints execute in the physics stage of the pose pipeline. Within
that stage they use the total order defined by the constraint-total-order
contract. If multiple physics constraints affect the same channel, each
constraint reads the current logical channel value after earlier physics
constraints and writes its own output before later physics constraints run.

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
  accumulator. When it becomes active again, reset it. A future explicit
  preserve-state API mode may be added, but it is outside the default
  conformance contract until fixtures encode that mode.

## Conformance Scenarios

The M5 physics conformance suite must include:

- `dt == 0` no-op.
- Reset with `dt == 0`.
- Single `1/60` step from a seeded state.
- Fractional `dt` carry across two updates.
- Large `dt` clamp with `maxSubsteps = 8`.
- Excess-step drop using the `stepEpsilon` remainder algorithm.
- Reset plus non-zero `dt` in the same update call.
- Reset key crossed inside an update interval.
- Translation and rotation channels using independent state.
- Two physics constraints affecting the same channel in ordered sequence.
- Inactive `skinRequired` constraint not advancing its accumulator.
