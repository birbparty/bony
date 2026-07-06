## M2 world-transform evaluation and backend-neutral draw batches.

import std/[math, tables]

import bony/constraints/path_constraints
import bony/constraints/update_cache
import bony/constraints/ik
import bony/constraints/transform_constraints
import bony/constraints/physics_constraints
import bony/mesh/deform
import bony/mesh/drawbatch_clipping
import bony/mesh/skinning
import bony/model

const basisEpsilon = 1e-12
const helperGeometryTolerance* = 1e-4

type
  HelperPoint* = object
    x*: float64
    y*: float64

  HelperPointPose* = object
    x*: float64
    y*: float64
    rotation*: float64

  Linear2 = object
    a: float64
    b: float64
    c: float64
    d: float64

  ParentFactors = object
    rotation: Linear2
    reflection: Linear2
    scaleShear: Linear2


proc identityLinear(): Linear2 =
  Linear2(a: 1.0, b: 0.0, c: 0.0, d: 1.0)


proc mul(left, right: Linear2): Linear2 =
  Linear2(
    a: left.a * right.a + left.c * right.b,
    b: left.b * right.a + left.d * right.b,
    c: left.a * right.c + left.c * right.d,
    d: left.b * right.c + left.d * right.d,
  )


proc affine(linear: Linear2; tx, ty: float64): Affine2 =
  Affine2(a: linear.a, b: linear.b, c: linear.c, d: linear.d, tx: tx, ty: ty)


proc inverseLinear(m: Linear2): tuple[ok: bool; inverse: Linear2] =
  ## Inverse of the 2x2 linear part [[a, c], [b, d]] (column-major a/b, c/d).
  let det = m.a * m.d - m.c * m.b
  if abs(det) < basisEpsilon:
    return (false, identityLinear())
  (true, Linear2(a: m.d / det, b: -m.b / det, c: -m.c / det, d: m.a / det))


proc localLinear(local: LocalTransform): Linear2 =
  let xAngle = degToRad(local.rotation + local.shearX)
  let yAngle = degToRad(local.rotation + 90.0 + local.shearY)
  Linear2(
    a: cos(xAngle) * local.scaleX,
    b: sin(xAngle) * local.scaleX,
    c: cos(yAngle) * local.scaleY,
    d: sin(yAngle) * local.scaleY,
  )


proc factorParent(parent: Affine2): ParentFactors =
  let pa = parent.a
  let pb = parent.b
  let pc = parent.c
  let pd = parent.d
  let sx = hypot(pa, pb)

  if sx > basisEpsilon:
    let detP = pa * pd - pb * pc
    let reflectionSign = if detP < 0.0: -1.0 else: 1.0
    let r0x = pa / sx
    let r0y = pb / sx
    let r1x = -r0y
    let r1y = r0x
    let k = r0x * pc + r0y * pd
    let sy = reflectionSign * (r1x * pc + r1y * pd)
    return ParentFactors(
      rotation: Linear2(a: r0x, b: r0y, c: r1x, d: r1y),
      reflection: Linear2(a: 1.0, b: 0.0, c: 0.0, d: reflectionSign),
      scaleShear: Linear2(a: sx, b: 0.0, c: k, d: sy),
    )

  let vy = hypot(pc, pd)
  if vy > basisEpsilon:
    let r1x = pc / vy
    let r1y = pd / vy
    let r0x = r1y
    let r0y = -r1x
    return ParentFactors(
      rotation: Linear2(a: r0x, b: r0y, c: r1x, d: r1y),
      reflection: identityLinear(),
      scaleShear: Linear2(a: 0.0, b: 0.0, c: 0.0, d: vy),
    )

  ParentFactors(
    rotation: identityLinear(),
    reflection: identityLinear(),
    scaleShear: Linear2(a: 0.0, b: 0.0, c: 0.0, d: 0.0),
  )


proc worldForBone(parent: Affine2; bone: BoneData; hasParent: bool): Affine2 =
  let local = bone.local
  let localLinear = localLinear(local)
  if not hasParent:
    return affine(localLinear, local.x, local.y)

  let factors = factorParent(parent)
  var inherited = identityLinear()
  if local.inheritRotation:
    inherited = inherited.mul(factors.rotation)
  if local.inheritReflection:
    inherited = inherited.mul(factors.reflection)
  if local.inheritScale:
    inherited = inherited.mul(factors.scaleShear)

  let worldLinear = inherited.mul(localLinear)
  let tx = parent.tx + parent.a * local.x + parent.c * local.y
  let ty = parent.ty + parent.b * local.x + parent.d * local.y
  affine(worldLinear, tx, ty)


proc pathByName(data: SkeletonData): Table[string, PathAttachmentData]
proc boneIndexes(data: SkeletonData): Table[string, int]
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


proc computeWorldsAndLocals(data: SkeletonData): tuple[worlds: seq[Affine2]; locals: seq[LocalTransform]] =
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
    let indexes = data.boneIndexes()
    let attachments = data.pathByName()
    let cache = buildRuntimeConstraintUpdateCache(data)
    var locals: seq[LocalTransform]
    for bone in data.bones:
      locals.add bone.local
    var worlds = newSeq[Affine2](data.bones.len)
    var computed = newSeq[bool](data.bones.len)
    for entry in cache:
      case entry.kind
      of ccekBoneGroup:
        for index in entry.bones:
          let bone = data.bones[index]
          if bone.parent.len == 0:
            worlds[index] = worldForBone(Affine2(a: 1.0, d: 1.0), boneData(bone.name, "", locals[index]), false)
          else:
            let parentIndex = indexes[bone.parent]
            worlds[index] = worldForBone(worlds[parentIndex], boneData(bone.name, bone.parent, locals[index]), true)
          computed[index] = true
      of ccekConstraint:
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
    if bone.parent.len == 0:
      worlds[index] = worldForBone(Affine2(a: 1.0, d: 1.0), bone, false)
    else:
      let parentIndex = byName[bone.parent]
      worlds[index] = worldForBone(worlds[parentIndex], bone, true)
    byName[bone.name] = index
  (worlds: worlds, locals: locals)


proc computeWorldTransforms*(data: SkeletonData): seq[Affine2] =
  ## Pure world-transform pass (no time, no mutable state). Used by setup-pose /
  ## t=0 callers and every existing M1-M9 golden. Unchanged by physics work.
  computeWorldsAndLocals(data).worlds


proc transformPoint(world: Affine2; x, y: float64): tuple[x: float64, y: float64] =
  (
    x: world.a * x + world.c * y + world.tx,
    y: world.b * x + world.d * y + world.ty,
  )


proc worldRotationDegrees(world: Affine2): float64


proc helperPoint*(x, y: float64): HelperPoint =
  HelperPoint(x: x, y: y)


proc slotBoneWorld(data: SkeletonData; worlds: openArray[Affine2]; slotName: string): Affine2 =
  for slot in data.slots:
    if slot.name == slotName:
      for boneIndex, bone in data.bones:
        if bone.name == slot.bone:
          if boneIndex >= worlds.len:
            raise newBonyLoadError(schemaViolation, "helper query world transform count does not match skeleton bones")
          return worlds[boneIndex]
      raise newBonyLoadError(unknownRequiredReference, "helper query slot references unknown bone: " & slot.bone)
  raise newBonyLoadError(unknownRequiredReference, "helper query references unknown slot: " & slotName)


proc worldPointAttachmentPose*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  attachmentName: string;
): HelperPointPose =
  let world = data.slotBoneWorld(worlds, slotName)
  for point in data.pointAttachments:
    if point.name == attachmentName:
      let pos = transformPoint(world, point.x, point.y)
      return HelperPointPose(
        x: pos.x,
        y: pos.y,
        rotation: worldRotationDegrees(world) + point.rotation,
      )
  raise newBonyLoadError(unknownRequiredReference, "unknown point attachment: " & attachmentName)


proc worldBoundingBoxAttachmentPolygon*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  attachmentName: string;
): seq[HelperPoint] =
  let world = data.slotBoneWorld(worlds, slotName)
  for box in data.boundingBoxAttachments:
    if box.name == attachmentName:
      let vertices = box.vertices
      for index in countup(0, vertices.len - 2, 2):
        let pos = transformPoint(world, vertices[index], vertices[index + 1])
        result.add HelperPoint(x: pos.x, y: pos.y)
      return
  raise newBonyLoadError(unknownRequiredReference, "unknown bounding-box attachment: " & attachmentName)


proc distanceToSegment(point, a, b: HelperPoint): float64 =
  let dx = b.x - a.x
  let dy = b.y - a.y
  let lengthSquared = dx * dx + dy * dy
  if lengthSquared <= basisEpsilon:
    return hypot(point.x - a.x, point.y - a.y)
  let rawT = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
  let t = min(1.0, max(0.0, rawT))
  let px = a.x + dx * t
  let py = a.y + dy * t
  hypot(point.x - px, point.y - py)


proc pointInHelperPolygon*(
  point: HelperPoint;
  polygon: openArray[HelperPoint];
  tolerance = helperGeometryTolerance;
): bool =
  if polygon.len < 3:
    raise newBonyLoadError(schemaViolation, "helper polygon must contain at least three points")
  for index in 0 ..< polygon.len:
    let a = polygon[index]
    let b = polygon[(index + 1) mod polygon.len]
    if distanceToSegment(point, a, b) <= tolerance:
      return true

  var inside = false
  var previous = polygon[^1]
  for current in polygon:
    let crossesY = (current.y > point.y) != (previous.y > point.y)
    if crossesY:
      let xAtY = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
      if point.x < xAtY:
        inside = not inside
    previous = current
  inside


proc pointerHitsPointTarget*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  attachmentName: string;
  x, y, hitRadius: float64;
): bool =
  if hitRadius < 0.0:
    raise newBonyLoadError(schemaViolation, "point helper hit radius must be non-negative")
  let pose = data.worldPointAttachmentPose(worlds, slotName, attachmentName)
  hypot(x - pose.x, y - pose.y) <= hitRadius


proc pointerHitsBoundingBoxTarget*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  attachmentName: string;
  x, y: float64;
): bool =
  let polygon = data.worldBoundingBoxAttachmentPolygon(worlds, slotName, attachmentName)
  pointInHelperPolygon(HelperPoint(x: x, y: y), polygon)


proc transformVector(world: Affine2; x, y: float64): tuple[x: float64, y: float64] =
  (
    x: world.a * x + world.c * y,
    y: world.b * x + world.d * y,
  )


proc inverseAffine(world: Affine2): tuple[ok: bool; inverse: Affine2] =
  let det = world.a * world.d - world.b * world.c
  if abs(det) <= basisEpsilon:
    return (false, Affine2())
  let invA = world.d / det
  let invB = -world.b / det
  let invC = -world.c / det
  let invD = world.a / det
  (
    true,
    Affine2(
      a: invA,
      b: invB,
      c: invC,
      d: invD,
      tx: -(invA * world.tx + invC * world.ty),
      ty: -(invB * world.tx + invD * world.ty),
    ),
  )


proc shortestAngleDelta(fromAngle, toAngle: float64): float64 =
  var delta = (toAngle - fromAngle) mod 360.0
  if delta > 180.0:
    delta -= 360.0
  elif delta < -180.0:
    delta += 360.0
  delta


proc pathByName(data: SkeletonData): Table[string, PathAttachmentData] =
  result = initTable[string, PathAttachmentData]()
  for attachment in data.pathAttachments:
    result[attachment.name] = attachment


proc boneIndexes(data: SkeletonData): Table[string, int] =
  result = initTable[string, int]()
  for index, bone in data.bones:
    result[bone.name] = index


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


proc pathPosition(path: PathConstraintData): float64 =
  if path.hasPosition: path.position else: 0.0


proc pathTranslateMix(path: PathConstraintData): float64 =
  if path.hasTranslateMix: path.translateMix else: 1.0


proc pathRotateMix(path: PathConstraintData): float64 =
  if path.hasRotateMix: path.rotateMix else: 0.0


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

  let parent = data.bones[boneIndex].parent
  let hasParent = parent.len > 0
  var parentWorld = Affine2(a: 1.0, d: 1.0)
  if hasParent:
    let parentIndex = indexes[parent]
    if not computed[parentIndex]:
      raise newBonyLoadError(orderingViolation, "runtime path parent must be emitted before constraint: " & path.name)
    parentWorld = worlds[parentIndex]

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
  worlds[boneIndex] = worldForBone(parentWorld, boneData(data.bones[boneIndex].name, parent, local), hasParent)
  computed[boneIndex] = true


proc worldRotationDegrees(world: Affine2): float64 =
  radToDeg(arctan2(world.b, world.a))


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
        let parentIndex = indexes[parent]
        if not computed[parentIndex]:
          raise newBonyLoadError(orderingViolation, "runtime ik bone parent must be emitted before constraint: " & ik.name)
        parentWorld = worlds[parentIndex]
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

  let parent = data.bones[boneIndex].parent
  let hasParent = parent.len > 0
  var parentWorld = Affine2(a: 1.0, d: 1.0)
  if hasParent:
    let parentIndex = indexes[parent]
    if not computed[parentIndex]:
      raise newBonyLoadError(orderingViolation, "runtime transform parent must be emitted before constraint: " & tc.name)
    parentWorld = worlds[parentIndex]

  let baseLocal = locals[boneIndex]
  let currentWorld = worldForBone(parentWorld, boneData(data.bones[boneIndex].name, parent, baseLocal), hasParent)

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
  worlds[boneIndex] = worldForBone(parentWorld, boneData(data.bones[boneIndex].name, parent, newLocal), hasParent)
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
): seq[Affine2] =
  ## Plain FK from the physics-adjusted locals. Bones are validated parent-before
  ## -child, so a single array pass recomputes every world (and every physics-
  ## affected descendant) from the locals the constraint pass and physics stage
  ## left behind.
  result = newSeq[Affine2](data.bones.len)
  for index, bone in data.bones:
    if bone.parent.len == 0:
      result[index] = worldForBone(Affine2(a: 1.0, d: 1.0), boneData(bone.name, "", locals[index]), false)
    else:
      result[index] = worldForBone(result[indexes[bone.parent]], boneData(bone.name, bone.parent, locals[index]), true)


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
  if data.physicsConstraints.len == 0:
    return computeWorldTransforms(data)
  if states.len != data.physicsConstraints.len:
    raise newBonyLoadError(schemaViolation,
      "physics state count (" & $states.len & ") does not match physics constraint count (" &
      $data.physicsConstraints.len & ")")

  var (worlds, locals) = computeWorldsAndLocals(data)
  let indexes = data.boneIndexes()

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

  worlds = recomputeWorldsFromLocals(data, locals, indexes)
  worlds


proc vertex(world: Affine2; x, y, u, v: float64): DrawVertex =
  let point = transformPoint(world, x, y)
  DrawVertex(
    x: point.x,
    y: point.y,
    u: u,
    v: v,
    r: 1.0,
    g: 1.0,
    b: 1.0,
    a: 1.0,
  )


proc skinMeshVertices*(
  data: SkeletonData;
  slotBone: string;
  mesh: MeshAttachment;
  skinningMethod = linearBlendSkinning;
): seq[SkinnedMeshVertex] =
  ## Convenience overload relocated from `bony/mesh/skinning` to break the
  ## former transform <-> skinning import cycle: recomputes worlds via the pure
  ## world-transform pass, then defers to the explicit-worlds overload.
  skinMeshVertices(data, computeWorldTransforms(data), slotBone, mesh, skinningMethod)


proc skinMeshVertices*(
  data: SkeletonData;
  slot: SlotData;
  mesh: MeshAttachment;
  skinningMethod = linearBlendSkinning;
): seq[SkinnedMeshVertex] =
  skinMeshVertices(data, slot.bone, mesh, skinningMethod)


proc meshVertex(sv: SkinnedMeshVertex): DrawVertex =
  ## Wrap an already-world-space skinned mesh vertex into a `DrawVertex`. Unlike
  ## `vertex()`, this does NOT re-apply a world transform (skinning already did)
  ## and it carries the uniform region color (r=g=b=a=1): the v1 mesh record has
  ## no per-vertex color, so a mesh and a region on the same slot are
  ## indistinguishable in color.
  DrawVertex(
    x: sv.x,
    y: sv.y,
    u: sv.u,
    v: sv.v,
    r: 1.0,
    g: 1.0,
    b: 1.0,
    a: 1.0,
  )


proc buildDrawBatches*(data: SkeletonData; worlds: seq[Affine2]; activeSkin = "default"): seq[DrawBatch] =
  ## Build draw batches using caller-supplied world transforms. Callers that have
  ## advanced the stateful physics stage pass the physics-adjusted worlds here so
  ## draw-batch vertices reflect physics. `worlds[i]` must be the world transform
  ## of `data.bones[i]` — same length and index ordering as `computeWorldTransforms`.
  ## Raised (not `doAssert`ed) so the guard survives `-d:danger`: a stripped check
  ## here would reintroduce the silent out-of-bounds read this seam exists to prevent.
  if worlds.len != data.bones.len:
    raise newBonyLoadError(schemaViolation,
      "buildDrawBatches: worlds length " & $worlds.len &
      " must match bone count " & $data.bones.len)
  var boneIndex = initTable[string, int]()
  var regions = initTable[string, RegionAttachment]()
  var meshes = initTable[string, MeshAttachment]()
  var clips = initTable[string, ClipAttachmentData]()
  # Transient deform-timeline override stamped on the posed data by the mixer,
  # keyed by slot name + mesh attachment (the mixer produces one entry per
  # slot/attachment, so keying by slot alone would collapse distinct entries).
  var deformBySlotAttachment = initTable[string, DeformOverride]()

  for index, bone in data.bones:
    boneIndex[bone.name] = index
  for region in data.regions:
    regions[region.name] = region
  for mesh in data.meshAttachments:
    meshes[mesh.name] = mesh
  for clip in data.clippingAttachments:
    clips[clip.name] = clip
  for override in data.deformOverrides:
    deformBySlotAttachment[override.slot & "\0" & override.attachment] = override

  var slotIndexByName = initTable[string, int]()
  var resolvedSlotAttachment = newSeq[string](data.slots.len)
  for index, slot in data.slots:
    slotIndexByName[slot.name] = index

  # Draw-order slot index of each emitted batch. Batches are a subsequence of the
  # slots (one per region-attachment slot), so this maps batch -> draw position
  # for computing clip-covered ranges below.
  var batchSlotIndex: seq[int] = @[]
  for slotIdx, slot in data.slots:
    if slot.attachment.len == 0:
      continue
    let attachment = data.resolveSkinAttachmentTarget(activeSkin, slot.name, slot.attachment)
    resolvedSlotAttachment[slotIdx] = attachment
    if attachment.len == 0:
      continue
    if meshes.hasKey(attachment):
      # Keying dispatch on the `meshes` table alone is unambiguous because
      # attachment names are cross-collection unique — validateSkeletonData
      # rejects a mesh name that collides with a region or clip name (model.nim),
      # so a name resolves to at most one of the three tables.
      # Mesh dispatch MUST precede the non-region guard below: a mesh-referencing
      # slot is neither a region nor a clip, so the guard would drop it silently.
      # Skin per-vertex world positions (FK for unweighted, linear-blend for
      # weighted) via the explicit-worlds overload using the worlds we already
      # hold, then emit one batch in this slot's draw-order position. Metadata
      # fields (texturePage/blendMode/clipId/world) mirror the region path so a
      # region and a mesh on the same slot are indistinguishable there.
      let mesh = meshes[attachment]
      # `world` is the slot-bone world used only as batch metadata (mirroring the
      # region path); it does NOT transform the mesh vertices. Skinning consumes
      # the full `worlds` array directly — a weighted vertex blends across its
      # influence bones and ignores slot.bone entirely.
      let world = worlds[boneIndex[slot.bone]]
      var skinned = skinMeshVertices(data, worlds, slot.bone, mesh)
      # Deform-timeline stage: offset skinned vertices by the posed override for
      # this slot/attachment, immediately after skinning and before the M7
      # deformer and clipping stages (normative order — see
      # docs/deform-timeline-contract.md). Region batches are never offset.
      let deformKey = slot.name & "\0" & mesh.name
      if deformKey in deformBySlotAttachment:
        let override = deformBySlotAttachment[deformKey]
        if override.deltas.len == skinned.len:
          skinned = applyDeformDeltas(skinned, override.deltas)
      var meshVerts = newSeq[DrawVertex](skinned.len)
      for i, sv in skinned:
        meshVerts[i] = meshVertex(sv)
      result.add DrawBatch(
        slot: slot.name,
        bone: slot.bone,
        attachment: attachment,
        texturePage: "",
        blendMode: "normal",
        clipId: "",
        world: world,
        vertices: meshVerts,
        indices: mesh.triangles,
      )
      batchSlotIndex.add slotIdx
      continue
    if not regions.hasKey(attachment):
      # A slot whose attachment names a clipping attachment (or any non-region)
      # produces no draw batch. This guard also prevents the `regions[...]`
      # Table lookup below from raising KeyError on a clip-named slot.
      continue
    let region = regions[attachment]
    let index = boneIndex[slot.bone]
    let world = worlds[index]
    let halfWidth = region.width * 0.5
    let halfHeight = region.height * 0.5
    result.add DrawBatch(
      slot: slot.name,
      bone: slot.bone,
      attachment: attachment,
      texturePage: "",
      blendMode: "normal",
      clipId: "",
      world: world,
      vertices: @[
        vertex(world, -halfWidth, -halfHeight, 0.0, 0.0),
        vertex(world, halfWidth, -halfHeight, 1.0, 0.0),
        vertex(world, halfWidth, halfHeight, 1.0, 1.0),
        vertex(world, -halfWidth, halfHeight, 0.0, 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16, 2'u16, 3'u16, 0'u16],
    )
    batchSlotIndex.add slotIdx

  # Clip pass: each slot whose attachment names a clipping attachment sets
  # `clipId` on, and geometrically clips, the draw batches in its covered range
  # (the batch after the clip's own slot through `untilSlot` inclusive, else to
  # the end of draw order). The load-time no-overlap invariant guarantees at most
  # one clip is active over any batch, so clips are applied independently.
  if data.clippingAttachments.len > 0:
    let lastSlotIndex = data.slots.len - 1
    for slotIdx, slot in data.slots:
      let attachment = resolvedSlotAttachment[slotIdx]
      if attachment.len == 0 or not clips.hasKey(attachment):
        continue
      let clip = clips[attachment]
      let ownIndex = slotIdx
      let endIndex =
        if clip.untilSlot.len > 0: slotIndexByName[clip.untilSlot]
        else: lastSlotIndex
      # Clip polygon in world space via the clip's own slot's bone world — the
      # same transform the covered region quads are built with.
      let clipWorld = worlds[boneIndex[slot.bone]]
      var clipPolygon: seq[ClipPoint] = @[]
      var p = 0
      while p + 1 < clip.vertices.len:
        let point = transformPoint(clipWorld, clip.vertices[p], clip.vertices[p + 1])
        clipPolygon.add clipPoint(
          quantizeF32(point.x, "clip.poly.x"),
          quantizeF32(point.y, "clip.poly.y"),
        )
        p += 2
      for batchIdx in 0 ..< result.len:
        let sourceSlotIndex = batchSlotIndex[batchIdx]
        if sourceSlotIndex <= ownIndex or sourceSlotIndex > endIndex:
          continue
        if meshes.hasKey(result[batchIdx].attachment):
          # Meshes are a triangle *soup* (explicit index list, shared/interior
          # vertices), so they clip per-triangle via clipDrawBatchTriangles —
          # NOT through clipDrawBatchPolygon, which reinterprets a batch's
          # vertices as one convex boundary ring and would destroy the topology.
          # See docs/mesh-attachment-contract.md ("per-triangle mesh clipping").
          result[batchIdx].clipId = clip.name
          let clipped = clipDrawBatchTriangles(
            result[batchIdx].vertices, result[batchIdx].indices, clipPolygon)
          if clipped.changed:
            result[batchIdx].vertices = clipped.vertices
            result[batchIdx].indices = clipped.indices
          continue
        result[batchIdx].clipId = clip.name
        let clipped = clipDrawBatchPolygon(result[batchIdx].vertices, clipPolygon)
        if clipped.changed:
          result[batchIdx].vertices = clipped.vertices
          result[batchIdx].indices = clipped.indices


proc buildDrawBatches*(data: SkeletonData): seq[DrawBatch] =
  ## Convenience overload: recompute worlds from the pure world-transform pass.
  ## Use the `worlds` overload when a physics stage has adjusted bone worlds.
  buildDrawBatches(data, computeWorldTransforms(data))


proc buildDrawBatches*(data: SkeletonData; activeSkin: string): seq[DrawBatch] =
  ## Convenience overload for runtime skin selection with pure world transforms.
  buildDrawBatches(data, computeWorldTransforms(data), activeSkin)
