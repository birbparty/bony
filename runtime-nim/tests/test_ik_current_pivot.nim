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
  let indexes = data.boneIndexes()
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
  let indexes = data.boneIndexes()
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
