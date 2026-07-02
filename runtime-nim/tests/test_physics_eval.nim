## M5 physics runtime-evaluation tests (bead bony-6pd).
##
## Exercises the stateful advance seam (advancePhysics) that runs the physics
## stage AFTER the pure world-transform/constraint pass. The integrator math
## itself is covered in test_smoke.nim; here we assert the SEAM: dt=0 is a pose
## no-op, a driven spring settles non-vacuously and agrees with the raw
## integrator, and the max-substep drop rule threads through unchanged.
##
## Also covers the docs/physics-integrator-contract.md "Conformance Scenarios"
## expressible at the advance seam today (bony-ocq): fractional-dt carry across
## two updates, the excess-step drop remainder algorithm, and two physics
## constraints on the same channel run in ordered sequence (read-after-write).
## The reset-timeline and inactive-skinRequired scenarios are gated on model
## features that do not exist yet and are tracked separately.

import bddy
import bony

proc closeWithin(actual, expected, tolerance: float64): bool =
  abs(actual - expected) <= tolerance

proc closeTo(actual, expected: float64): bool =
  closeWithin(actual, expected, 1e-9)

proc raisesBonyLoadError(action: proc()): bool =
  try:
    action()
    false
  except BonyLoadError:
    true

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

  it "drives the rotate channel in native degrees and agrees with the raw integrator":
    let data = skeletonData(
      skeletonHeader("phys", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("hair", "root", localTransform(rotation = 10.0)),
      ],
      physicsConstraints = @[
        physicsConstraintData(
          "spin", "hair", {pcRotate},
          hasStrength = true, strength = 50.0,
          hasDamping = true, damping = 16.0,
          hasGravity = true, gravity = 100.0,
          hasMass = true, mass = 1.0,
        ),
      ],
    )
    var states = newPhysicsStates(data)
    var rawState: PhysicsConstraintState
    let params = physicsParams(strength = 50.0, damping = 16.0, gravity = 100.0, mass = 1.0)
    let pure = computeWorldTransforms(data)
    var maxDeviation = 0.0
    for frame in 0 ..< 60:
      discard advancePhysics(data, states, physicsFixedDt)
      # Target is the stored rotation in DEGREES (10.0), not radians.
      let raw = rawState.updatePhysicsConstraint(params, @[physicsChannelInput(pcRotate, 10.0)], physicsFixedDt)
      maxDeviation = max(maxDeviation, abs(states[0].channels[pcRotate].offset - raw.outputs[0].offset))
    let advanced = advancePhysics(data, states, physicsFixedDt)
    then:
      maxDeviation < 1e-4
      states[0].channels[pcRotate].initialized
      states[0].channels[pcRotate].offset > 1e-4
      # Rotation actually changed the world basis vs the unconstrained pose.
      abs(advanced[1].a - pure[1].a) > 1e-3

  it "preserves a non-physics constraint solution through the physics recompose":
    # A transform constraint solves bone "arm" toward "goal"; a physics
    # constraint sits on unrelated bone "hair". At dt=0 physics is a no-op, so the
    # full advance must reproduce the pure pass EXACTLY (this exercises the
    # recomputeWorldsFromLocals "reproduces the constraint pass" invariant).
    let data = skeletonData(
      skeletonHeader("mix", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("arm", "root", localTransform(x = 2.0)),
        boneData("goal", "root", localTransform(x = 6.0, y = 4.0)),
        boneData("hair", "root", localTransform(x = 1.0)),
      ],
      transformConstraints = @[
        transformConstraintData("tc", "arm", "goal",
          hasTranslateMix = true, translateMix = 0.5),
      ],
      physicsConstraints = @[
        physicsConstraintData("sway", "hair", {pcX},
          hasStrength = true, strength = 50.0, hasGravity = true, gravity = 100.0),
      ],
    )
    var states = newPhysicsStates(data)
    let pure = computeWorldTransforms(data)
    let atRest = advancePhysics(data, states, 0.0)
    then:
      atRest.len == pure.len
    then:
      # Every bone (incl. the transform-constrained "arm") matches the pure pass.
      closeWithin(atRest[1].tx, pure[1].tx, 1e-9)
      closeWithin(atRest[1].ty, pure[1].ty, 1e-9)
      closeWithin(atRest[3].tx, pure[3].tx, 1e-9)
    # With time, the physics bone moves but the transform solution is preserved.
    let moved = advancePhysics(data, states, physicsFixedDt)
    then:
      closeWithin(moved[1].tx, pure[1].tx, 1e-9)
      moved[3].tx > pure[3].tx + 1e-4

  it "carries a fractional dt across two advance calls":
    # 0.025 s = 1.5 fixed steps. The accumulator must carry the 0.5-step
    # remainder BETWEEN advancePhysics calls, so two calls land 3 substeps total
    # (1 then 2) rather than resetting the sub-step budget each call.
    let data = springSkeleton(strength = 5.0, gravity = 60.0)
    var states = newPhysicsStates(data)
    var rawState: PhysicsConstraintState
    let params = physicsParams(strength = 5.0, gravity = 60.0)
    let frac = 0.025

    discard advancePhysics(data, states, frac)
    discard rawState.updatePhysicsConstraint(
      params, @[physicsChannelInput(pcX, 3.0)], frac)
    then:
      # First call: floor(1.5)=1 substep; 0.5*fixedDt carried in the accumulator.
      closeTo(states[0].accumulator, rawState.accumulator)
      closeWithin(states[0].accumulator, 0.5 * physicsFixedDt, 1e-9)

    discard advancePhysics(data, states, frac)
    discard rawState.updatePhysicsConstraint(
      params, @[physicsChannelInput(pcX, 3.0)], frac)
    then:
      # Second call: 0.5 carried + 1.5 = 2.0 steps -> 2 substeps, remainder 0.
      closeTo(states[0].accumulator, rawState.accumulator)
      closeWithin(states[0].accumulator, 0.0, 1e-9)
      # Seam state tracks the raw integrator exactly through the carry.
      closeTo(states[0].channels[pcX].offset, rawState.channels[pcX].offset)
      states[0].channels[pcX].offset > 1e-4

  it "drops excess whole steps and carries the exact fractional remainder":
    # 0.19 s ~= 11.4 fixed steps (below maxFrameDt, so no clamp): 8 substeps run
    # (maxSubsteps), leaving 3.4 steps; the drop rule removes
    # floor((rem + stepEpsilon)/fixedDt) = 3 whole steps and carries the 0.4-step
    # (< fixedDt) remainder.
    let data = springSkeleton(strength = 5.0, gravity = 60.0)
    var states = newPhysicsStates(data)
    var rawState: PhysicsConstraintState
    let params = physicsParams(strength = 5.0, gravity = 60.0)
    let bigDt = 0.19

    let raw = rawState.updatePhysicsConstraint(
      params, @[physicsChannelInput(pcX, 3.0)], bigDt)
    discard advancePhysics(data, states, bigDt)
    then:
      raw.substeps == physicsMaxSubsteps
      raw.droppedSteps == 3
      # Carried remainder is strictly below one fixed step and equals 0.4*fixedDt.
      states[0].accumulator < physicsFixedDt
      closeWithin(states[0].accumulator, 0.4 * physicsFixedDt, 1e-6)
      # Seam and raw agree on the carried remainder and the settled offset.
      closeTo(states[0].accumulator, rawState.accumulator)
      closeTo(states[0].channels[pcX].offset, rawState.channels[pcX].offset)
      # Non-vacuous: the 8 integrated substeps actually moved the spring.
      states[0].channels[pcX].offset > 1e-4

  it "applies two same-channel physics constraints in ordered sequence":
    # Two physics constraints on the SAME bone+channel with distinct `order`
    # values. The stage runs them by `order` (NOT source order), and the second
    # reads the local left by the first (read-after-write), folding both offsets
    # onto the channel. swayA/swayB use different gravity so their offsets differ.
    let data = skeletonData(
      skeletonHeader("phys", "1.0.0"),
      @[boneData("root", ""), boneData("hair", "root", localTransform(x = 3.0))],
      physicsConstraints = @[
        # Listed order=1 first, on purpose, to prove the stage sorts by `order`.
        physicsConstraintData("swayB", "hair", {pcX}, order = 1,
          hasStrength = true, strength = 5.0, hasGravity = true, gravity = 60.0),
        physicsConstraintData("swayA", "hair", {pcX}, order = 0,
          hasStrength = true, strength = 5.0, hasGravity = true, gravity = 120.0),
      ],
    )
    var states = newPhysicsStates(data)
    let worlds = advancePhysics(data, states, physicsFixedDt)
    # Source index 0 = swayB (order 1, ran second); index 1 = swayA (order 0, first).
    let offsetA = states[1].channels[pcX].offset
    let offsetB = states[0].channels[pcX].offset
    then:
      offsetA > 1e-9
      offsetB > 1e-9
      # swayA (order 0) ran first: its target was the raw local.x = 3.0.
      closeWithin(states[1].channels[pcX].previousTarget, 3.0, 1e-9)
      # swayB (order 1) ran second: its target was the value swayA wrote
      # (read-after-write) = 3.0 + offsetA, NOT the raw 3.0. The written channel
      # crosses the f32 writeback boundary, so compare at f32 precision (offsetA
      # ~ 0.033 is four orders of magnitude above this tolerance — the
      # read-after-write ordering is unambiguous).
      states[0].channels[pcX].previousTarget > 3.0 + 1e-3
      closeWithin(states[0].channels[pcX].previousTarget, 3.0 + offsetA, 1e-6)
      # Final channel value folds both offsets in sequence.
      closeWithin(worlds[1].tx, 3.0 + offsetA + offsetB, 1e-6)

  it "rejects a negative dt and a mismatched state count":
    let data = springSkeleton(strength = 10.0, gravity = 60.0)
    let nophys = skeletonData(
      skeletonHeader("nophys", "1.0.0"), @[boneData("root", "")])
    then:
      # Negative dt is rejected whether or not physics constraints exist.
      raisesBonyLoadError(proc() =
        var s = newPhysicsStates(data)
        discard advancePhysics(data, s, -1.0))
      raisesBonyLoadError(proc() =
        var s = newPhysicsStates(nophys)
        discard advancePhysics(nophys, s, -1.0))
      # State count must match the physics constraint count.
      raisesBonyLoadError(proc() =
        var s: seq[PhysicsConstraintState] = @[]
        discard advancePhysics(data, s, physicsFixedDt))
