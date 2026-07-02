## M5 physics runtime-evaluation tests (bead bony-6pd).
##
## Exercises the stateful advance seam (advancePhysics) that runs the physics
## stage AFTER the pure world-transform/constraint pass. The integrator math
## itself is covered in test_smoke.nim; here we assert the SEAM: dt=0 is a pose
## no-op, a driven spring settles non-vacuously and agrees with the raw
## integrator, and the max-substep drop rule threads through unchanged.

import bddy
import bony

proc closeWithin(actual, expected, tolerance: float64): bool =
  abs(actual - expected) <= tolerance

proc closeTo(actual, expected: float64): bool =
  closeWithin(actual, expected, 1e-9)

proc springSkeleton(
  strength = 0.0;
  damping = 0.0;
  gravity = 0.0;
  mass = 1.0;
  channels = {pcX};
  targetX = 3.0;
): SkeletonData =
  ## Root + a single constrained child carrying one physics constraint. The
  ## child's local.x is the animated target for the pcX channel; a constant
  ## target means the spring is driven purely by gravity/inertia terms.
  skeletonData(
    skeletonHeader("phys", "1.0.0"),
    @[
      boneData("root", ""),
      boneData("hair", "root", localTransform(x = targetX)),
    ],
    physicsConstraints = @[
      physicsConstraintData(
        "sway", "hair", channels,
        hasStrength = true, strength = strength,
        hasDamping = true, damping = damping,
        hasGravity = true, gravity = gravity,
        hasMass = true, mass = mass,
      ),
    ],
  )

spec "bony physics evaluation":
  it "is a pose no-op at dt=0 (setup pose)":
    let data = springSkeleton(strength = 10.0, gravity = 60.0)
    var states = newPhysicsStates(data)
    let pure = computeWorldTransforms(data)
    let advanced = advancePhysics(data, states, 0.0)
    then:
      states.len == 1
      # Seeded but not advanced: zero offset/velocity, no substeps consumed.
      closeTo(states[0].channels[pcX].offset, 0.0)
      closeTo(states[0].channels[pcX].velocity, 0.0)
      states[0].channels[pcX].initialized
      closeTo(states[0].accumulator, 0.0)
      advanced.len == pure.len
    then:
      # World transforms are identical to the unconstrained pass.
      closeWithin(advanced[1].tx, pure[1].tx, 1e-6)
      closeWithin(advanced[1].ty, pure[1].ty, 1e-6)
      closeWithin(advanced[1].a, pure[1].a, 1e-6)
      closeWithin(advanced[1].d, pure[1].d, 1e-6)

  it "settles a gravity-driven spring and agrees with the raw integrator":
    # Overdamped (zeta ~1.13): monotonic approach to equilibrium offset
    # gravity*mass/strength = 100/50 = 2.0. Params are f32-exact so the stage's
    # f32-quantized params match the raw integrator's exactly.
    let data = springSkeleton(strength = 50.0, damping = 16.0, gravity = 100.0, mass = 1.0)
    var states = newPhysicsStates(data)

    # Raw integrator driven with the same constant target and dt sequence.
    var rawState: PhysicsConstraintState
    let params = physicsParams(strength = 50.0, damping = 16.0, gravity = 100.0, mass = 1.0)

    var offsets: seq[float64]
    var localXs: seq[float64]
    var maxDeviation = 0.0
    for frame in 0 ..< 300:
      let worlds = advancePhysics(data, states, physicsFixedDt)
      let raw = rawState.updatePhysicsConstraint(params, @[physicsChannelInput(pcX, 3.0)], physicsFixedDt)
      # Stage state and raw integrator agree every frame (same f64 math, same
      # constant target rebuilt from the animated pose each call).
      maxDeviation = max(maxDeviation, abs(states[0].channels[pcX].offset - raw.outputs[0].offset))
      offsets.add states[0].channels[pcX].offset
      # World tx reflects the folded-back local.x = target + offset*mix.
      localXs.add worlds[1].tx

    then:
      # Stage never diverges from the raw integrator across all frames.
      maxDeviation < 1e-4
      # Non-vacuous: the spring actually moved.
      offsets[0] > 1e-4
      # Monotonic rise (overdamped => no overshoot).
      offsets[0] < offsets[1]
      offsets[10] < offsets[20]
      offsets[20] < offsets[40]
      # Settling approach to equilibrium 2.0.
      abs(offsets[^1] - 2.0) < abs(offsets[0] - 2.0)
      abs(offsets[^1] - 2.0) < 1e-2
      # Folded output: world x = 3.0 (target) + offset (mix defaults to 1.0).
      closeWithin(localXs[^1], 3.0 + offsets[^1], 1e-4)

  it "threads a large dt through the max-substep clamp and drop rule unchanged":
    let data = springSkeleton(strength = 5.0, gravity = 60.0)
    var states = newPhysicsStates(data)

    # Raw reference: one call with the same oversized dt.
    var rawState: PhysicsConstraintState
    let params = physicsParams(strength = 5.0, gravity = 60.0)
    let raw = rawState.updatePhysicsConstraint(params, @[physicsChannelInput(pcX, 3.0)], physicsMaxFrameDt)

    discard advancePhysics(data, states, physicsMaxFrameDt)

    then:
      # dt entered the integrator unaltered: identical resulting state.
      closeTo(states[0].accumulator, rawState.accumulator)
      closeTo(states[0].channels[pcX].offset, rawState.channels[pcX].offset)
      # Contract: at most maxSubsteps processed; excess whole steps dropped, so
      # the carried remainder is strictly below one fixed step.
      raw.substeps == physicsMaxSubsteps
      raw.droppedSteps > 0
      states[0].accumulator < physicsFixedDt

  it "keeps independent per-channel state for a multi-channel constraint":
    let data = springSkeleton(
      strength = 5.0, gravity = 10.0, mass = 1.0, channels = {pcX, pcY})
    var states = newPhysicsStates(data)
    for frame in 0 ..< 10:
      discard advancePhysics(data, states, physicsFixedDt)
    then:
      # Both enabled channels seeded and advanced.
      states[0].channels[pcX].initialized
      states[0].channels[pcY].initialized
      states[0].channels[pcX].offset > 1e-4
      # pcX target is 3.0 (local.x); pcY target is 0.0 (local.y). Gravity is the
      # same, so both offsets track together (independent but equal dynamics).
      closeWithin(states[0].channels[pcX].offset, states[0].channels[pcY].offset, 1e-9)
      # pcRotate was never enabled, so its state stays untouched.
      not states[0].channels[pcRotate].initialized

  it "returns the pure pass unchanged when there are no physics constraints":
    let data = skeletonData(
      skeletonHeader("nophys", "1.0.0"),
      @[boneData("root", ""), boneData("child", "root", localTransform(x = 4.0))],
    )
    var states = newPhysicsStates(data)
    let pure = computeWorldTransforms(data)
    let advanced = advancePhysics(data, states, physicsFixedDt)
    then:
      states.len == 0
      advanced.len == pure.len
      closeWithin(advanced[1].tx, pure[1].tx, 1e-9)
