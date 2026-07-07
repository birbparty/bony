# bony-me5.13: IK chains anchor at the CURRENT (live) pivot, not the rest origin.
#
# In a single computeWorldTransforms pass, an earlier-ordered constraint can move
# the world of a bone that is an IK chain root's external parent. The chain must
# then anchor at that live parent's position so the end-effector can reach a live
# target (contract §4). This test drives the private applyRuntimeIk directly
# (via include) with a hand-set `worlds` array in which the chain root's parent
# has been moved, so current-pivot vs rest-anchor produce opposite results.

include "../src/bony/transform.nim"

import std/tables

proc worldRot(a: Affine2): float64 = worldRotationDegrees(a)

block anchorsAtCurrentPivotNotRest:
  # root -> parent0 -> arm0 (the one-bone IK chain); goal is the IK target.
  # arm0 rests at (5, 0); goal sits at (5, 10).
  let data = skeletonData(
    skeletonHeader("ikpivot", "1.0.0"),
    @[
      boneData("root", ""),
      boneData("parent0", "root"),
      boneData("arm0", "parent0", localTransform(x = 5.0, y = 0.0)),
      boneData("goal", "root", localTransform(x = 5.0, y = 10.0)),
    ],
    ikConstraints = @[ikConstraintData("ik", "goal", @["arm0"])],
  )
  let indexes = boneIndexByName(data.bones)
  var locals: seq[LocalTransform]
  for b in data.bones:
    locals.add b.local
  var worlds = newSeq[Affine2](data.bones.len)
  var computed = newSeq[bool](data.bones.len)

  # root + goal at rest; parent0 MOVED up to (0, 20) as if an earlier constraint
  # translated it. arm0's live origin is therefore (5, 20) -- 10 ABOVE the target
  # at (5, 10) -- so the live chain must aim DOWN (-90 deg). The rest origin
  # (5, 0) is 10 BELOW the target, which would aim UP (+90 deg).
  worlds[indexes["root"]] = Affine2(a: 1.0, d: 1.0)
  computed[indexes["root"]] = true
  worlds[indexes["parent0"]] = Affine2(a: 1.0, d: 1.0, tx: 0.0, ty: 20.0)
  computed[indexes["parent0"]] = true
  worlds[indexes["goal"]] = Affine2(a: 1.0, d: 1.0, tx: 5.0, ty: 10.0)
  computed[indexes["goal"]] = true

  data.applyRuntimeIk(data.ikConstraints[0], locals, worlds, computed, indexes)

  let armRot = worldRot(worlds[indexes["arm0"]])
  doAssert abs(armRot - (-90.0)) <= 1e-4,
    "IK must anchor at the live pivot (expected -90 deg), got " & $armRot &
    " (a rest anchor would give +90 deg)"

block twoBoneReachesLiveTargetFromMovedParent:
  # Two-bone chain arm0 (len 10) + arm1 (len 10); with the parent moved so the
  # live anchor is (0, 10), a target at (0, 30) is exactly reachable (distance
  # 20 = total length). From the rest anchor (10, 0) that target is out of reach,
  # so the end-effector would land elsewhere.
  let data = skeletonData(
    skeletonHeader("ikreach", "1.0.0"),
    @[
      boneData("root", ""),
      boneData("mover", "root"),
      boneData("arm0", "mover", localTransform(x = 10.0, y = 0.0)),
      boneData("arm1", "arm0", localTransform(x = 10.0, y = 0.0)),
      # goal RESTS at the chain's rest tip (30,0) so the rest-derived segment
      # lengths are 10/10 (contract §6). Its LIVE world is moved to (0,30) below.
      boneData("goal", "root", localTransform(x = 30.0, y = 0.0)),
    ],
    ikConstraints = @[ikConstraintData("ik", "goal", @["arm0", "arm1"])],
  )
  let indexes = boneIndexByName(data.bones)
  var locals: seq[LocalTransform]
  for b in data.bones:
    locals.add b.local
  var worlds = newSeq[Affine2](data.bones.len)
  var computed = newSeq[bool](data.bones.len)

  worlds[indexes["root"]] = Affine2(a: 1.0, d: 1.0)
  computed[indexes["root"]] = true
  # Move `mover` so arm0's live origin is (0, 10) instead of its rest (10, 0):
  # rotate mover +90 deg about (0,10)'s parent... simplest is to set mover's world
  # to a +90 rotation at the origin, making arm0 (local x=10) land at (0, 10).
  worlds[indexes["mover"]] = Affine2(a: 0.0, b: 1.0, c: -1.0, d: 0.0)
  computed[indexes["mover"]] = true
  worlds[indexes["goal"]] = Affine2(a: 1.0, d: 1.0, tx: 0.0, ty: 30.0)
  computed[indexes["goal"]] = true

  data.applyRuntimeIk(data.ikConstraints[0], locals, worlds, computed, indexes)

  # End-effector = arm1 world origin advanced by its length (10) along its
  # world direction. With the live anchor at (0,10) and target (0,30) exactly at
  # full reach, both bones point straight up and the tip lands at (0, 30).
  let arm1 = worlds[indexes["arm1"]]
  let tipRad = degToRad(worldRot(arm1))
  let tipX = arm1.tx + cos(tipRad) * 10.0
  let tipY = arm1.ty + sin(tipRad) * 10.0
  doAssert abs(tipX - 0.0) <= 1e-3 and abs(tipY - 30.0) <= 1e-3,
    "two-bone chain must reach the live target (0,30) from the moved parent, got (" &
    $tipX & ", " & $tipY & ")"

echo "ik current-pivot anchor tests passed"

include smoke_support

spec "ik smoke coverage":
  it "solves one-bone IK with mix":
    let full = solveOneBoneIk(ikPoint(0.0, 0.0), 10.0, 0.0, ikPoint(0.0, 10.0))
    let mixed = solveOneBoneIk(ikPoint(0.0, 0.0), 10.0, 0.0, ikPoint(0.0, 10.0), mix = 0.5)

    then:
      closeTo(full.rotation, 90.0)
      closeTo(full.endPoint.x, 0.0)
      closeTo(full.endPoint.y, 10.0)
      closeTo(mixed.rotation, 45.0)
      closeTo(mixed.endPoint.x, 7.0710678118654755)
      closeTo(mixed.endPoint.y, 7.071067811865475)
      raisesBonyLoadError(proc() =
        discard solveOneBoneIk(ikPoint(0.0, 0.0), -1.0, 0.0, ikPoint(1.0, 0.0))
      , schemaViolation)
      raisesBonyLoadError(proc() =
        discard solveOneBoneIk(ikPoint(0.0, 0.0), 1.0, 0.0, ikPoint(1.0, 0.0), mix = 2.0)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        discard solveOneBoneIk(IkPoint(x: Inf, y: 0.0), 1.0, 0.0, ikPoint(1.0, 0.0))
      , numericOutOfRange)

  it "solves analytic two-bone IK cases":
    let reachable = solveTwoBoneIk(ikPoint(0.0, 0.0), 100.0, 70.0, 0.0, 0.0, ikPoint(80.0, 50.0))
    let overExtended = solveTwoBoneIk(ikPoint(0.0, 0.0), 100.0, 70.0, 10.0, 20.0, ikPoint(200.0, 0.0))
    let tooClose = solveTwoBoneIk(ikPoint(0.0, 0.0), 100.0, 70.0, 0.0, 0.0, ikPoint(5.0, 2.0))
    let mirrored = solveTwoBoneIk(
      ikPoint(0.0, 0.0),
      100.0,
      70.0,
      0.0,
      0.0,
      ikPoint(80.0, 50.0),
      bendSign = -1.0,
    )
    let partial = solveTwoBoneIk(ikPoint(0.0, 0.0), 100.0, 70.0, 10.0, 20.0, ikPoint(80.0, 50.0), mix = 0.5)

    then:
      closeTo(reachable.parentRotation, -10.092678909779805)
      closeTo(reachable.childRotation, 115.3769335251523)
      closeTo(reachable.endPoint.x, 80.0)
      closeTo(reachable.endPoint.y, 50.0)
      closeTo(overExtended.parentRotation, 0.0)
      closeTo(overExtended.childRotation, 0.0)
      closeTo(tooClose.childRotation, 180.0)
      closeTo(tooClose.endPoint.x, 27.85430072655778)
      closeTo(tooClose.endPoint.y, 11.141720290623123)
      closeTo(mirrored.endPoint.x, 80.0)
      closeTo(mirrored.endPoint.y, 50.0)
      closeTo(partial.parentRotation, -0.04633945488990246)
      closeTo(partial.childRotation, 67.68846676257615)
      raisesBonyLoadError(proc() =
        discard solveTwoBoneIk(ikPoint(0.0, 0.0), 100.0, 70.0, 0.0, 0.0, ikPoint(80.0, 50.0), bendSign = Inf)
      , numericOutOfRange)
      raisesBonyLoadError(proc() =
        discard solveTwoBoneIk(ikPoint(0.0, 0.0), 100.0, 70.0, 0.0, 0.0, IkPoint(x: NaN, y: 0.0))
      , numericOutOfRange)

  it "solves chain IK with fixed FABRIK settings":
    let reachable = solveChainIk(
      @[ikPoint(0.0, 0.0), ikPoint(5.0, 0.0), ikPoint(10.0, 0.0)],
      @[5.0, 5.0],
      ikPoint(6.0, 6.0),
    )
    let unreachable = solveChainIk(
      @[ikPoint(0.0, 0.0), ikPoint(5.0, 0.0), ikPoint(10.0, 0.0)],
      @[5.0, 5.0],
      ikPoint(20.0, 0.0),
    )
    let mixed = solveChainIk(
      @[ikPoint(0.0, 0.0), ikPoint(5.0, 0.0), ikPoint(10.0, 0.0)],
      @[5.0, 5.0],
      ikPoint(6.0, 6.0),
      mix = 0.5,
    )
    let coincident = solveChainIk(
      @[ikPoint(0.0, 0.0), ikPoint(0.0, 0.0), ikPoint(0.0, 0.0)],
      @[5.0, 5.0],
      ikPoint(6.0, 0.0),
    )

    then:
      fabrikIterations == 8
      closeTo(fabrikTolerance, 1e-4)
      closeWithin(reachable.points[^1].x, 6.0, fabrikTolerance)
      closeWithin(reachable.points[^1].y, 6.0, fabrikTolerance)
      reachable.rotations.len == 2
      closeTo(unreachable.points[^1].x, 10.0)
      closeTo(unreachable.points[^1].y, 0.0)
      closeWithin(mixed.points[^1].x, 8.0, fabrikTolerance)
      closeWithin(mixed.points[^1].y, 3.0, fabrikTolerance)
      closeWithin(coincident.points[^1].x, 6.0, fabrikTolerance)
      closeWithin(coincident.points[^1].y, 0.0, fabrikTolerance)
      closeWithin(coincident.points[0].x, 0.0, fabrikTolerance)
      closeWithin(pointDistance(coincident.points[0], coincident.points[1]), 5.0, fabrikTolerance)
      closeWithin(pointDistance(coincident.points[1], coincident.points[2]), 5.0, fabrikTolerance)
      raisesBonyLoadError(proc() =
        discard solveChainIk(@[ikPoint(0.0, 0.0)], @[], ikPoint(1.0, 0.0))
      , schemaViolation)
      raisesBonyLoadError(proc() =
        discard solveChainIk(@[ikPoint(0.0, 0.0), ikPoint(1.0, 0.0)], @[], ikPoint(1.0, 0.0))
      , schemaViolation)
      raisesBonyLoadError(proc() =
        discard solveChainIk(@[IkPoint(x: NaN, y: 0.0), ikPoint(1.0, 0.0)], @[1.0], ikPoint(1.0, 0.0))
      , numericOutOfRange)

  it "evaluates one-bone IK reach and mix interpolation in the pose pass":
    # b0 pivots at (10,0); goal sits straight above at (10,20) -> world rot 90.
    proc oneBoneRig(m: float64; hasMix: bool): seq[Affine2] =
      let data = skeletonData(
        skeletonHeader("one", "1.0.0"),
        @[
          boneData("root", ""),
          boneData("b0", "root", localTransform(x = 10.0, y = 0.0)),
          boneData("goal", "root", localTransform(x = 10.0, y = 20.0)),
        ],
        ikConstraints = @[ikConstraintData("ik", "goal", @["b0"], hasMix = hasMix, mix = m)],
      )
      computeWorldTransforms(data)
    let full = oneBoneRig(1.0, true)
    let half = oneBoneRig(0.5, true)
    let zero = oneBoneRig(0.0, true)

    then:
      # mix=1 points exactly at the target.
      closeWithin(ikWorldRot(full[1]), 90.0, 1e-4)
      # mix=0.5 applies the blend ONCE: lerp(0,90,0.5)=45, not mix^2=22.5.
      closeWithin(ikWorldRot(half[1]), 45.0, 1e-4)
      # mix=0 is a no-op (runtimeEvaluable is false): the rest pose is kept.
      closeWithin(ikWorldRot(zero[1]), 0.0, 1e-4)

  it "evaluates two-bone IK reach for both bend signs":
    proc twoBoneRig(bendPositive: bool): seq[Affine2] =
      let data = skeletonData(
        skeletonHeader("two", "1.0.0"),
        @[
          boneData("root", ""),
          boneData("b0", "root", localTransform(x = 0.0, y = 0.0)),
          boneData("b1", "b0", localTransform(x = 10.0, y = 0.0)),
          boneData("goal", "root", localTransform(x = 10.0, y = 10.0)),
        ],
        ikConstraints = @[ikConstraintData("ik", "goal", @["b0", "b1"],
          hasBendPositive = true, bendPositive = bendPositive)],
      )
      computeWorldTransforms(data)
    let childLength = 10.0
    let pos = twoBoneRig(true)
    let neg = twoBoneRig(false)
    # End-effector = b1 origin + childLength along b1's world direction.
    let posTipX = pos[2].tx + cos(degToRad(ikWorldRot(pos[2]))) * childLength
    let posTipY = pos[2].ty + sin(degToRad(ikWorldRot(pos[2]))) * childLength
    let negTipX = neg[2].tx + cos(degToRad(ikWorldRot(neg[2]))) * childLength
    let negTipY = neg[2].ty + sin(degToRad(ikWorldRot(neg[2]))) * childLength

    # The elbow (b1 world origin) is a circle intersection: |elbow-b0|=10 and
    # |tip-elbow|=10 with tip=(10,10) gives exactly (10,0) or (0,10). The two
    # bend signs must land on these two DISTINCT solutions (opposite sides of the
    # root->target diagonal), not merely "differ".
    proc nearXY(x, y, ex, ey: float64): bool =
      closeWithin(x, ex, 1e-3) and closeWithin(y, ey, 1e-3)
    let posElbowA = nearXY(pos[2].tx, pos[2].ty, 10.0, 0.0)
    let posElbowB = nearXY(pos[2].tx, pos[2].ty, 0.0, 10.0)
    let negElbowA = nearXY(neg[2].tx, neg[2].ty, 10.0, 0.0)
    let negElbowB = nearXY(neg[2].tx, neg[2].ty, 0.0, 10.0)

    then:
      # Both bend signs reach the same reachable target...
      closeWithin(posTipX, 10.0, 1e-4)
      closeWithin(posTipY, 10.0, 1e-4)
      closeWithin(negTipX, 10.0, 1e-4)
      closeWithin(negTipY, 10.0, 1e-4)
      # ...with elbows at the two distinct valid intersections, one each.
      (posElbowA and negElbowB) or (posElbowB and negElbowA)

  it "evaluates an N-bone chain IK reach in the pose pass":
    let data = skeletonData(
      skeletonHeader("chain", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("b0", "root", localTransform(x = 0.0, y = 0.0)),
        boneData("b1", "b0", localTransform(x = 10.0, y = 0.0)),
        boneData("b2", "b1", localTransform(x = 10.0, y = 0.0)),
        boneData("goal", "root", localTransform(x = 15.0, y = 15.0)),
      ],
      ikConstraints = @[ikConstraintData("ik", "goal", @["b0", "b1", "b2"])],
    )
    let worlds = computeWorldTransforms(data)
    # last segment length = |goalRest(15,15) - b2Rest(20,0)|.
    let tipLen = sqrt((15.0 - 20.0) * (15.0 - 20.0) + (15.0 - 0.0) * (15.0 - 0.0))
    let tipX = worlds[3].tx + cos(degToRad(ikWorldRot(worlds[3]))) * tipLen
    let tipY = worlds[3].ty + sin(degToRad(ikWorldRot(worlds[3]))) * tipLen

    then:
      # Target distance ~21.2 < total reach 30, so the chain reaches it.
      closeWithin(tipX, 15.0, 1e-2)
      closeWithin(tipY, 15.0, 1e-2)

  it "keeps a degenerate collapsed IK target non-fatal":
    # A genuinely UNREACHABLE target cannot be built from a STATIC rig: the
    # contract sizes the last segment as |target_rest - bone1_rest|, so by the
    # triangle inequality |target - bone0| <= parentLength + childLength always
    # holds for a static pose (solver-level over-extension is already covered by
    # the chain-solver test above). The constructible integration degeneracy is a
    # target COINCIDENT with the chain origin: the chain must fold without raising
    # or producing NaN, and the end-effector still returns to the target.
    let data = skeletonData(
      skeletonHeader("deg", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("b0", "root", localTransform(x = 0.0, y = 0.0)),
        boneData("b1", "b0", localTransform(x = 10.0, y = 0.0)),
        boneData("goal", "root", localTransform(x = 0.0, y = 0.0)),
      ],
      ikConstraints = @[ikConstraintData("ik", "goal", @["b0", "b1"])],
    )
    let worlds = computeWorldTransforms(data)
    let childLength = 10.0
    let tipX = worlds[2].tx + cos(degToRad(ikWorldRot(worlds[2]))) * childLength
    let tipY = worlds[2].ty + sin(degToRad(ikWorldRot(worlds[2]))) * childLength

    then:
      worlds.len == 4
      # Finite (NaN != NaN) — the solver fallback prevented a blow-up...
      worlds[1].a == worlds[1].a and worlds[2].a == worlds[2].a
      worlds[2].tx == worlds[2].tx and worlds[2].ty == worlds[2].ty
      # ...and the folded chain still returns the end-effector to the target.
      closeWithin(tipX, 0.0, 1e-4)
      closeWithin(tipY, 0.0, 1e-4)
