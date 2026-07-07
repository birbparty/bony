## Runtime world-transform, constraint, and physics evaluation stages.

import std/[math, tables]

import bony/constraints/ik
import bony/constraints/path_constraints
import bony/constraints/physics_constraints
import bony/constraints/transform_constraints
import bony/constraints/update_cache
import bony/model
import bony/transform/affine

proc pathByName(data: SkeletonData): Table[string, PathAttachmentData]
proc applyRuntimePathConstraint(
  data: SkeletonData;
  path: PathConstraintData;
  locals: var seq[LocalTransform];
  worlds: var seq[Affine2];
  computed: var seq[bool];
  indexes: Table[string, int];
  attachments: Table[string, PathAttachmentData];
)
proc applyRuntimeIk(
  data: SkeletonData;
  ik: IkConstraintData;
  locals: var seq[LocalTransform];
  worlds: var seq[Affine2];
  computed: var seq[bool];
  indexes: Table[string, int];
)
proc applyRuntimeTransformConstraint(
  data: SkeletonData;
  tc: TransformConstraintData;
  locals: var seq[LocalTransform];
  worlds: var seq[Affine2];
  computed: var seq[bool];
  indexes: Table[string, int];
)

proc computeWorldsAndLocals(
  data: SkeletonData;
  activation: ActiveSkinMembership;
): tuple[worlds: seq[Affine2]; locals: seq[LocalTransform]] =
  ## Core world-transform pass. Returns BOTH the world affines and the final
  ## per-bone local transforms (which the ik/path/transform constraints may have
  ## rewritten). The physics stage needs the constraint-adjusted locals as its
  ## animated targets, so this is factored out of computeWorldTransforms; the
  ## pure entry point below is a thin wrapper and its output is byte-for-byte
  ## unchanged.
  var hasRuntimeConstraints = false
  for path in data.paths:
    if path.runtimeEvaluable:
      hasRuntimeConstraints = true
      break
  if not hasRuntimeConstraints:
    for ik in data.ikConstraints:
      if ik.runtimeEvaluable:
        hasRuntimeConstraints = true
        break
  if not hasRuntimeConstraints:
    for tc in data.transformConstraints:
      if tc.runtimeEvaluable:
        hasRuntimeConstraints = true
        break
  if hasRuntimeConstraints:
    let indexes = boneIndexByName(data.bones)
    let attachments = data.pathByName()
    let cache = buildRuntimeConstraintUpdateCache(data, activation)
    var locals: seq[LocalTransform]
    for bone in data.bones:
      locals.add bone.local
    var worlds = newSeq[Affine2](data.bones.len)
    var computed = newSeq[bool](data.bones.len)
    for entry in cache:
      case entry.kind
      of ccekBoneGroup:
        for index in entry.bones:
          if not activation.bones[index]:
            continue
          let bone = data.bones[index]
          if bone.parent.len == 0:
            worlds[index] = worldForBone(Affine2(a: 1.0, d: 1.0), boneData(bone.name, "", locals[index]), false)
          else:
            let parentIndex = indexes[bone.parent]
            if not activation.bones[parentIndex]:
              continue
            worlds[index] = worldForBone(worlds[parentIndex], boneData(bone.name, bone.parent, locals[index]), true)
          computed[index] = true
      of ccekConstraint:
        if not entry.active:
          continue
        case entry.constraint.kind
        of ckPath:
          let path = data.paths[entry.constraint.sourceIndex]
          data.applyRuntimePathConstraint(path, locals, worlds, computed, indexes, attachments)
        of ckIk:
          let ik = data.ikConstraints[entry.constraint.sourceIndex]
          data.applyRuntimeIk(ik, locals, worlds, computed, indexes)
        of ckTransform:
          let tc = data.transformConstraints[entry.constraint.sourceIndex]
          data.applyRuntimeTransformConstraint(tc, locals, worlds, computed, indexes)
        else:
          # ckPhysics is a SEPARATE stateful stage (advancePhysics), not an entry
          # in this pure world-transform loop.
          discard
    return (worlds: worlds, locals: locals)

  var byName = initTable[string, int]()
  let bones = data.bones
  var worlds = newSeq[Affine2](bones.len)
  var locals = newSeq[LocalTransform](bones.len)
  for index, bone in bones:
    locals[index] = bone.local
    if not activation.bones[index]:
      byName[bone.name] = index
      continue
    if bone.parent.len == 0:
      worlds[index] = worldForBone(Affine2(a: 1.0, d: 1.0), bone, false)
    else:
      let parentIndex = byName[bone.parent]
      if not activation.bones[parentIndex]:
        byName[bone.name] = index
        continue
      worlds[index] = worldForBone(worlds[parentIndex], bone, true)
    byName[bone.name] = index
  (worlds: worlds, locals: locals)


proc computeWorldsAndLocals(data: SkeletonData): tuple[worlds: seq[Affine2]; locals: seq[LocalTransform]] =
  computeWorldsAndLocals(data, activeSkinMembership(data))


proc computeWorldTransforms*(data: SkeletonData; activeSkin: string): seq[Affine2] =
  computeWorldsAndLocals(data, activeSkinMembership(data, activeSkin)).worlds


proc computeWorldTransforms*(data: SkeletonData): seq[Affine2] =
  ## Pure world-transform pass (no time, no mutable state). Used by setup-pose /
  ## t=0 callers and every existing M1-M9 golden. Unchanged by physics work.
  computeWorldTransforms(data, "default")

proc pathByName(data: SkeletonData): Table[string, PathAttachmentData] =
  result = initTable[string, PathAttachmentData]()
  for attachment in data.pathAttachments:
    result[attachment.name] = attachment


proc pathCubicInWorld(attachment: PathAttachmentData; targetWorld: Affine2): PathCubic =
  let p0 = transformPoint(targetWorld, attachment.p0x, attachment.p0y)
  let p1 = transformPoint(targetWorld, attachment.p1x, attachment.p1y)
  let p2 = transformPoint(targetWorld, attachment.p2x, attachment.p2y)
  let p3 = transformPoint(targetWorld, attachment.p3x, attachment.p3y)
  pathCubic(
    pathPoint(p0.x, p0.y),
    pathPoint(p1.x, p1.y),
    pathPoint(p2.x, p2.y),
    pathPoint(p3.x, p3.y),
  )


proc optionalPathValue(value: float64; hasValue: bool; defaultValue: float64): float64 =
  if hasValue: value else: defaultValue


proc pathPosition(path: PathConstraintData): float64 =
  optionalPathValue(path.position, path.hasPosition, 0.0)


proc pathTranslateMix(path: PathConstraintData): float64 =
  optionalPathValue(path.translateMix, path.hasTranslateMix, 1.0)


proc pathRotateMix(path: PathConstraintData): float64 =
  optionalPathValue(path.rotateMix, path.hasRotateMix, 0.0)


proc resolveParentWorldOrRaise(
  data: SkeletonData;
  boneIndex: int;
  indexes: Table[string, int];
  worlds: openArray[Affine2];
  computed: openArray[bool];
  constraintName: string;
  errorPrefix: string;
): tuple[parentWorld: Affine2; hasParent: bool; parentName: string] =
  let parent = data.bones[boneIndex].parent
  if parent.len == 0:
    return (parentWorld: Affine2(a: 1.0, d: 1.0), hasParent: false, parentName: parent)
  let parentIndex = indexes[parent]
  if not computed[parentIndex]:
    raise newBonyLoadError(orderingViolation, errorPrefix & " parent must be emitted before constraint: " & constraintName)
  (parentWorld: worlds[parentIndex], hasParent: true, parentName: parent)


proc applyRuntimePathConstraint(
  data: SkeletonData;
  path: PathConstraintData;
  locals: var seq[LocalTransform];
  worlds: var seq[Affine2];
  computed: var seq[bool];
  indexes: Table[string, int];
  attachments: Table[string, PathAttachmentData];
) =
  if not path.runtimeEvaluable:
    return

  let boneIndex = indexes[path.bone]
  let targetIndex = indexes[path.target]
  if not computed[targetIndex]:
    raise newBonyLoadError(orderingViolation, "runtime path target must be emitted before constraint: " & path.name)

  let parent = resolveParentWorldOrRaise(data, boneIndex, indexes, worlds, computed, path.name, "runtime path")
  let parentWorld = parent.parentWorld
  let hasParent = parent.hasParent

  let translateMix = path.pathTranslateMix()
  let rotateMix = path.pathRotateMix()
  let inverse = inverseAffine(parentWorld)
  if (translateMix > 0.0 or rotateMix > 0.0) and not inverse.ok:
    raise newBonyLoadError(schemaViolation, "runtime path parent transform is singular: " & path.name)

  let curve = pathCubicInWorld(attachments[path.path], worlds[targetIndex])
  let table = buildPathArcLengthTable(curve)
  let sample = samplePathByDistance(curve, path.pathPosition() * table.totalLength)
  var local = locals[boneIndex]

  if translateMix > 0.0:
    let sampledLocal = transformPoint(inverse.inverse, sample.position.x, sample.position.y)
    local = localTransform(
      x = local.x + (sampledLocal.x - local.x) * translateMix,
      y = local.y + (sampledLocal.y - local.y) * translateMix,
      rotation = local.rotation,
      scaleX = local.scaleX,
      scaleY = local.scaleY,
      shearX = local.shearX,
      shearY = local.shearY,
      inheritRotation = local.inheritRotation,
      inheritScale = local.inheritScale,
      inheritReflection = local.inheritReflection,
      transformMode = local.transformMode,
    )

  if rotateMix > 0.0:
    let tangentAngleRadians = degToRad(sample.tangentAngle)
    let tangentLocal = transformVector(inverse.inverse, cos(tangentAngleRadians), sin(tangentAngleRadians))
    let targetRotation = tangentAngle(pathPoint(tangentLocal.x, tangentLocal.y), local.rotation)
    local = localTransform(
      x = local.x,
      y = local.y,
      rotation = local.rotation + shortestAngleDelta(local.rotation, targetRotation) * rotateMix,
      scaleX = local.scaleX,
      scaleY = local.scaleY,
      shearX = local.shearX,
      shearY = local.shearY,
      inheritRotation = local.inheritRotation,
      inheritScale = local.inheritScale,
      inheritReflection = local.inheritReflection,
      transformMode = local.transformMode,
    )

  locals[boneIndex] = local
  worlds[boneIndex] = worldForBone(parentWorld, boneData(data.bones[boneIndex].name, parent.parentName, local), hasParent)
  computed[boneIndex] = true


proc ikDistance(a, b: IkPoint): float64 =
  hypot(b.x - a.x, b.y - a.y)


proc restWorldFor(
  data: SkeletonData;
  boneIndex: int;
  indexes: Table[string, int];
  memo: var Table[int, Affine2];
): Affine2 =
  ## Rest-pose world transform of a bone, FK-composed over its UNMUTATED rest
  ## locals (data.bones[*].local), independent of the animated `locals` array.
  if boneIndex in memo:
    return memo[boneIndex]
  let bone = data.bones[boneIndex]
  let hasParent = bone.parent.len > 0
  var parentWorld = Affine2(a: 1.0, d: 1.0)
  if hasParent:
    parentWorld = restWorldFor(data, indexes[bone.parent], indexes, memo)
  result = worldForBone(parentWorld, bone, hasParent)
  memo[boneIndex] = result


proc withRotation(local: LocalTransform; rotation: float64): LocalTransform =
  ## Copy a local transform, replacing only its rotation (degrees).
  localTransform(
    x = local.x, y = local.y, rotation = rotation,
    scaleX = local.scaleX, scaleY = local.scaleY,
    shearX = local.shearX, shearY = local.shearY,
    inheritRotation = local.inheritRotation,
    inheritScale = local.inheritScale,
    inheritReflection = local.inheritReflection,
    transformMode = local.transformMode,
  )


proc poseToLocal(pose: TransformConstraintPose; templateLocal: LocalTransform): LocalTransform =
  ## Build a LocalTransform from a decomposed pose, carrying the inherit flags and
  ## transformMode from the constrained bone's existing local (they are invariant
  ## under a transform constraint; only the geometry changes). affineToTransformPose
  ## is the exact inverse of localLinear/transformPoseToAffine, so re-composing this
  ## local through worldForBone reproduces the affine it was decomposed from.
  localTransform(
    x = pose.x, y = pose.y, rotation = pose.rotation,
    scaleX = pose.scaleX, scaleY = pose.scaleY,
    shearX = pose.shearX, shearY = pose.shearY,
    inheritRotation = templateLocal.inheritRotation,
    inheritScale = templateLocal.inheritScale,
    inheritReflection = templateLocal.inheritReflection,
    transformMode = templateLocal.transformMode,
  )


proc applyRuntimeIk(
  data: SkeletonData;
  ik: IkConstraintData;
  locals: var seq[LocalTransform];
  worlds: var seq[Affine2];
  computed: var seq[bool];
  indexes: Table[string, int];
) =
  ## Evaluate one IK constraint and write its solved rotations back into the
  ## chain bones. Geometry per docs/ik-constraint-format-contract.md §3-§5:
  ## fixed segment lengths come from the REST pose (§6), but the chain anchors at
  ## the CURRENT (live) joint origins, so a chain whose root has a moved parent
  ## aims from the live pivot and the end-effector can reach a live target; the
  ## bones' CURRENT world rotations feed the solver; the target's CURRENT world
  ## position is the goal. `mix` is applied ONCE inside the solver, and because
  ## the input pose is the live pose, mix=0 is the current-pose identity. Output
  ## conventions differ per solver — 1-bone/chain return ABSOLUTE world angles,
  ## solveTwoBoneIk's child is RELATIVE to its parent — but the unified
  ## absolute-angle write-back below normalizes that (the child's absolute angle
  ## is parentRotation + childRotation).
  ##
  ## Ordering: a chain whose root's external parent is written by a LATER-ordered
  ## constraint raises an orderingViolation rather than reading a pre-constraint
  ## world — the same ordering model as applyRuntimePathConstraint.
  if not ik.runtimeEvaluable:
    return

  let targetIndex = indexes[ik.target]
  if not computed[targetIndex]:
    raise newBonyLoadError(orderingViolation, "runtime ik target must be emitted before constraint: " & ik.name)
  let target = IkPoint(x: worlds[targetIndex].tx, y: worlds[targetIndex].ty)

  var chainIndexes = newSeq[int](ik.bones.len)
  for i, boneName in ik.bones:
    chainIndexes[i] = indexes[boneName]

  # Rest-pose geometry (fixed segment lengths / joint origins).
  var restMemo = initTable[int, Affine2]()
  var restOrigins = newSeq[IkPoint](ik.bones.len)
  for i, boneIndex in chainIndexes:
    let rw = restWorldFor(data, boneIndex, indexes, restMemo)
    restOrigins[i] = IkPoint(x: rw.tx, y: rw.ty)
  let targetRest = restWorldFor(data, targetIndex, indexes, restMemo)
  let targetRestPoint = IkPoint(x: targetRest.tx, y: targetRest.ty)

  # Current FK worlds of the chain, captured BEFORE mutating, FK-composed from
  # bone[0]'s external parent forward so the solver sees current rotations.
  var currentWorlds = newSeq[Affine2](ik.bones.len)
  for i, boneIndex in chainIndexes:
    let parent = data.bones[boneIndex].parent
    let hasParent = parent.len > 0
    var parentWorld = Affine2(a: 1.0, d: 1.0)
    if hasParent:
      if i > 0 and parent == ik.bones[i - 1]:
        parentWorld = currentWorlds[i - 1]
      else:
        parentWorld = resolveParentWorldOrRaise(data, boneIndex, indexes, worlds, computed, ik.name, "runtime ik bone").parentWorld
    currentWorlds[i] = worldForBone(parentWorld, data.bones[boneIndex], hasParent)

  # Live (current-pivot) joint origins. The chain anchors at the live pivot so a
  # moved/animated parent is tracked and the end-effector can reach a live target
  # (contract §4); mix=0 becomes the current-pose identity. Segment LENGTHS stay
  # rest-derived (§6), so bones remain rigid regardless of the live pose.
  var currentOrigins = newSeq[IkPoint](ik.bones.len)
  for i in 0 ..< ik.bones.len:
    currentOrigins[i] = IkPoint(x: currentWorlds[i].tx, y: currentWorlds[i].ty)

  let storedMix = ik.mix
  let bendSign = if ik.bendPositive: 1.0 else: -1.0

  # Solved ABSOLUTE world angle (degrees) per constrained bone, chain order.
  var solvedWorldAngles = newSeq[float64](ik.bones.len)
  case ik.bones.len
  of 1:
    let length = ikDistance(restOrigins[0], targetRestPoint)
    let currentRotation = worldRotationDegrees(currentWorlds[0])
    let solved = solveOneBoneIk(currentOrigins[0], length, currentRotation, target, storedMix)
    solvedWorldAngles[0] = solved.rotation
  of 2:
    let parentLength = ikDistance(restOrigins[0], restOrigins[1])
    let childLength = ikDistance(restOrigins[1], targetRestPoint)
    let parentRotation = worldRotationDegrees(currentWorlds[0])
    # solveTwoBoneIk lerps the child toward a RELATIVE bend angle, so its
    # childRotation input must be the child's current rotation relative to the
    # parent (current child world rotation minus current parent world rotation),
    # not an absolute world rotation.
    let childRotation = worldRotationDegrees(currentWorlds[1]) - parentRotation
    let solved = solveTwoBoneIk(currentOrigins[0], parentLength, childLength, parentRotation, childRotation, target, bendSign, storedMix)
    solvedWorldAngles[0] = solved.parentRotation
    solvedWorldAngles[1] = solved.parentRotation + solved.childRotation
  else:
    # Fixed segment lengths from the rest pose (§6): rest joint origins plus the
    # rest tip (the target's rest world position).
    var lengths = newSeq[float64](ik.bones.len)
    for i in 0 ..< ik.bones.len - 1:
      lengths[i] = ikDistance(restOrigins[i], restOrigins[i + 1])
    lengths[^1] = ikDistance(restOrigins[^1], targetRestPoint)
    # Live-pose input polyline: live joint origins plus the last bone's live tip
    # (its live origin advanced by the rest last-segment length along its current
    # world direction). This anchors the chain at the live root and makes mix=0
    # the current-pose identity; mix=1 reaches the live target.
    var points = newSeq[IkPoint](ik.bones.len + 1)
    for i in 0 ..< ik.bones.len:
      points[i] = currentOrigins[i]
    let lastRadians = degToRad(worldRotationDegrees(currentWorlds[^1]))
    points[^1] = IkPoint(
      x: currentOrigins[^1].x + cos(lastRadians) * lengths[^1],
      y: currentOrigins[^1].y + sin(lastRadians) * lengths[^1],
    )
    let solved = solveChainIk(points, lengths, target, storedMix)
    for i in 0 ..< ik.bones.len:
      solvedWorldAngles[i] = solved.rotations[i]

  # Sequential FK write-back: convert each solved absolute world angle to the
  # bone's LOCAL rotation against its (already re-worlded) parent, then re-world
  # the bone so it serves as the next chain bone's parent world.
  for i, boneIndex in chainIndexes:
    let parent = data.bones[boneIndex].parent
    let hasParent = parent.len > 0
    var parentWorld = Affine2(a: 1.0, d: 1.0)
    if hasParent:
      if i > 0 and parent == ik.bones[i - 1]:
        parentWorld = worlds[chainIndexes[i - 1]]
      else:
        parentWorld = worlds[indexes[parent]]
    # A bone that does not inherit its parent's rotation has world rotation equal
    # to its own local rotation, so no parent angle is subtracted in that case.
    let inheritsRotation = locals[boneIndex].inheritRotation
    let parentRotation = if hasParent and inheritsRotation: worldRotationDegrees(parentWorld) else: 0.0
    let newLocal = withRotation(locals[boneIndex], solvedWorldAngles[i] - parentRotation)
    locals[boneIndex] = newLocal
    worlds[boneIndex] = worldForBone(parentWorld, boneData(data.bones[boneIndex].name, parent, newLocal), hasParent)
    computed[boneIndex] = true


proc applyRuntimeTransformConstraint(
  data: SkeletonData;
  tc: TransformConstraintData;
  locals: var seq[LocalTransform];
  worlds: var seq[Affine2];
  computed: var seq[bool];
  indexes: Table[string, int];
) =
  ## Blend the constrained bone's CURRENT world pose toward the target bone's
  ## CURRENT world pose, per channel by the four mixes (affine<->pose lerp in
  ## constraints/transform_constraints.nim). Like the path/IK apply procs the
  ## constrained bone is a constraint WRITE target and so is NOT pre-emitted: its
  ## current world is FK-composed here from its (live) local and its parent's
  ## already-emitted world. mix=0 is the current-pose identity; mix=1 snaps a
  ## channel fully to the target.
  ##
  ## The solved value is a WORLD affine, but the result MUST be written back as a
  ## LOCAL transform: a trailing ccekBoneGroup re-derives this bone's world from
  ## locals[boneIndex] (see buildConstraintUpdateCache), so a world-only write
  ## would be silently overwritten. We invert worldForBone — translation via the
  ## parent-world inverse, linear via inherited^-1 (the same parent-factor product
  ## worldForBone composes per inherit flags) — then decompose to a pose.
  if not tc.runtimeEvaluable:
    return

  let boneIndex = indexes[tc.bone]
  let targetIndex = indexes[tc.target]
  if not computed[targetIndex]:
    raise newBonyLoadError(orderingViolation, "runtime transform target must be emitted before constraint: " & tc.name)

  let parent = resolveParentWorldOrRaise(data, boneIndex, indexes, worlds, computed, tc.name, "runtime transform")
  let parentWorld = parent.parentWorld
  let hasParent = parent.hasParent

  let baseLocal = locals[boneIndex]
  let currentWorld = worldForBone(parentWorld, boneData(data.bones[boneIndex].name, parent.parentName, baseLocal), hasParent)

  let mix = transformConstraintMix(
    translate = tc.translateMix,
    rotate = tc.rotateMix,
    scale = tc.scaleMix,
    shear = tc.shearMix,
  )
  let solvedWorld = applyTransformConstraint(currentWorld, worlds[targetIndex], mix)

  var newLocal: LocalTransform
  if not hasParent:
    newLocal = poseToLocal(affineToTransformPose(solvedWorld), baseLocal)
  else:
    let factors = factorParent(parentWorld)
    var inherited = identityLinear()
    if baseLocal.inheritRotation:
      inherited = inherited.mul(factors.rotation)
    if baseLocal.inheritReflection:
      inherited = inherited.mul(factors.reflection)
    if baseLocal.inheritScale:
      inherited = inherited.mul(factors.scaleShear)
    let inheritedInverse = inverseLinear(inherited)
    let parentInverse = inverseAffine(parentWorld)
    if not inheritedInverse.ok or not parentInverse.ok:
      raise newBonyLoadError(schemaViolation, "runtime transform parent transform is singular: " & tc.name)
    let solvedLinear = Linear2(a: solvedWorld.a, b: solvedWorld.b, c: solvedWorld.c, d: solvedWorld.d)
    let localLinearM = inheritedInverse.inverse.mul(solvedLinear)
    let localOrigin = transformPoint(parentInverse.inverse, solvedWorld.tx, solvedWorld.ty)
    newLocal = poseToLocal(affineToTransformPose(affine(localLinearM, localOrigin.x, localOrigin.y)), baseLocal)

  locals[boneIndex] = newLocal
  worlds[boneIndex] = worldForBone(parentWorld, boneData(data.bones[boneIndex].name, parent.parentName, newLocal), hasParent)
  computed[boneIndex] = true


proc physicsChannelValue(local: LocalTransform; channel: PhysicsChannel): float64 =
  ## Read the animated target for a physics channel from the constrained bone's
  ## LOCAL transform, in the runtime's native storage units (translation in
  ## skeleton units; rotation/shearX in degrees as stored; scaleX unitless). This
  ## is bony's canonical per-channel representation — the same field localLinear
  ## consumes — so physics reads and writes the identical field with no lossy
  ## angle conversion, and dt=0 is an exact pose no-op.
  case channel
  of pcX: local.x
  of pcY: local.y
  of pcRotate: local.rotation
  of pcScaleX: local.scaleX
  of pcShearX: local.shearX


proc withPhysicsChannel(local: LocalTransform; channel: PhysicsChannel; value: float64): LocalTransform =
  ## Copy a local transform, replacing only the given physics channel. Mirrors
  ## withRotation; localTransform quantizes to f32 (the public output boundary).
  var x = local.x
  var y = local.y
  var rotation = local.rotation
  var scaleX = local.scaleX
  var shearX = local.shearX
  case channel
  of pcX: x = value
  of pcY: y = value
  of pcRotate: rotation = value
  of pcScaleX: scaleX = value
  of pcShearX: shearX = value
  localTransform(
    x = x, y = y, rotation = rotation,
    scaleX = scaleX, scaleY = local.scaleY,
    shearX = shearX, shearY = local.shearY,
    inheritRotation = local.inheritRotation,
    inheritScale = local.inheritScale,
    inheritReflection = local.inheritReflection,
    transformMode = local.transformMode,
  )


proc recomputeWorldsFromLocals(
  data: SkeletonData;
  locals: seq[LocalTransform];
  indexes: Table[string, int];
  activation: ActiveSkinMembership;
): seq[Affine2] =
  ## Plain FK from the physics-adjusted locals. Bones are validated parent-before
  ## -child, so a single array pass recomputes every world (and every physics-
  ## affected descendant) from the locals the constraint pass and physics stage
  ## left behind.
  result = newSeq[Affine2](data.bones.len)
  for index, bone in data.bones:
    if not activation.bones[index]:
      continue
    if bone.parent.len == 0:
      result[index] = worldForBone(Affine2(a: 1.0, d: 1.0), boneData(bone.name, "", locals[index]), false)
    else:
      let parentIndex = indexes[bone.parent]
      if not activation.bones[parentIndex]:
        continue
      result[index] = worldForBone(result[parentIndex], boneData(bone.name, bone.parent, locals[index]), true)


proc newPhysicsStates*(data: SkeletonData): seq[PhysicsConstraintState] =
  ## One default PhysicsConstraintState per physics constraint (index = source
  ## order in data.physicsConstraints). Default is accumulator=0, inactive, and
  ## un-initialized channels, so the first advancePhysics call lazily seeds each
  ## channel from its current animated target per the integrator contract.
  newSeq[PhysicsConstraintState](data.physicsConstraints.len)


proc advancePhysics*(
  data: SkeletonData;
  states: var seq[PhysicsConstraintState];
  dt: float64;
  activeSkin = "default";
): seq[Affine2] =
  ## Stateful advance seam: bony's only time- and state-dependent pose entry
  ## point. Runs the pure world-transform/constraint pass to produce the animated
  ## target pose, then the physics stage (after that pass, per
  ## docs/constraint-total-order.md), then recomposes worlds from the adjusted
  ## locals. `states` carries per-constraint PhysicsConstraintState across frames
  ## (see newPhysicsStates); `dt` is the non-negative frame delta and the ONLY
  ## time source. With no physics constraints this is exactly computeWorldTransforms.
  # Reject negative dt uniformly (deterministic playback), independent of whether
  # any physics constraint is present, so callers get the same contract either way.
  if dt < 0.0:
    raise newBonyLoadError(schemaViolation, "physics advance dt must be non-negative")
  let activation = activeSkinMembership(data, activeSkin)
  if data.physicsConstraints.len == 0:
    return computeWorldTransforms(data, activeSkin)
  if states.len != data.physicsConstraints.len:
    raise newBonyLoadError(schemaViolation,
      "physics state count (" & $states.len & ") does not match physics constraint count (" &
      $data.physicsConstraints.len & ")")

  var (worlds, locals) = computeWorldsAndLocals(data, activation)
  let indexes = boneIndexByName(data.bones)

  # Deterministic physics-stage order (docs/constraint-total-order.md). Reads the
  # constrained bone's live local channels as targets, integrates each enabled
  # channel via the existing integrator, and folds outputs back onto the local.
  # Ordering a same-channel chain works naturally: each constraint reads the
  # local left by earlier ones and writes before later ones.
  var descriptors: seq[ConstraintCacheDescriptor]
  for index, pc in data.physicsConstraints:
    descriptors.add constraintCacheDescriptor(ckPhysics, pc.order, index, [pc.bone])
  let order = buildPhysicsConstraintOrder(descriptors)

  for entry in order:
    let pc = data.physicsConstraints[entry.sourceIndex]
    if not activation.physicsConstraints[entry.sourceIndex]:
      states[entry.sourceIndex].active = false
      continue
    let boneIndex = indexes[pc.bone]
    var inputs: seq[PhysicsChannelInput]
    for channel in pc.channels:
      inputs.add physicsChannelInput(channel, physicsChannelValue(locals[boneIndex], channel))
    let params = physicsParams(
      inertia = pc.inertia,
      strength = pc.strength,
      damping = pc.damping,
      mass = pc.mass,
      gravity = pc.gravity,
      wind = pc.wind,
      mix = pc.mix,
    )
    let res = updatePhysicsConstraint(states[entry.sourceIndex], params, inputs, dt)
    for output in res.outputs:
      locals[boneIndex] = withPhysicsChannel(locals[boneIndex], output.channel, output.value)

  worlds = recomputeWorldsFromLocals(data, locals, indexes, activation)
  worlds
