## M2 world-transform evaluation and backend-neutral draw batches.

import std/[math, tables]

import bony/constraints/path_constraints
import bony/constraints/update_cache
import bony/constraints/ik
import bony/model

const basisEpsilon = 1e-12

type
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


proc computeWorldTransforms*(data: SkeletonData): seq[Affine2] =
  var hasRuntimePaths = false
  for path in data.paths:
    if path.runtimeEvaluable:
      hasRuntimePaths = true
      break
  if not hasRuntimePaths:
    for ik in data.ikConstraints:
      if ik.runtimeEvaluable:
        hasRuntimePaths = true
        break
  if hasRuntimePaths:
    let indexes = data.boneIndexes()
    let attachments = data.pathByName()
    let cache = buildRuntimeConstraintUpdateCache(data)
    var locals: seq[LocalTransform]
    for bone in data.bones:
      locals.add bone.local
    result = newSeq[Affine2](data.bones.len)
    var computed = newSeq[bool](data.bones.len)
    for entry in cache:
      case entry.kind
      of ccekBoneGroup:
        for index in entry.bones:
          let bone = data.bones[index]
          if bone.parent.len == 0:
            result[index] = worldForBone(Affine2(a: 1.0, d: 1.0), boneData(bone.name, "", locals[index]), false)
          else:
            let parentIndex = indexes[bone.parent]
            result[index] = worldForBone(result[parentIndex], boneData(bone.name, bone.parent, locals[index]), true)
          computed[index] = true
      of ccekConstraint:
        case entry.constraint.kind
        of ckPath:
          let path = data.paths[entry.constraint.sourceIndex]
          data.applyRuntimePathConstraint(path, locals, result, computed, indexes, attachments)
        of ckIk:
          let ik = data.ikConstraints[entry.constraint.sourceIndex]
          data.applyRuntimeIk(ik, locals, result, computed, indexes)
        else:
          # ckTransform / ckPhysics are out of scope for this slice.
          discard
    return

  var byName = initTable[string, int]()
  let bones = data.bones
  result = newSeq[Affine2](bones.len)
  for index, bone in bones:
    if bone.parent.len == 0:
      result[index] = worldForBone(Affine2(a: 1.0, d: 1.0), bone, false)
    else:
      let parentIndex = byName[bone.parent]
      result[index] = worldForBone(result[parentIndex], bone, true)
    byName[bone.name] = index


proc transformPoint(world: Affine2; x, y: float64): tuple[x: float64, y: float64] =
  (
    x: world.a * x + world.c * y + world.tx,
    y: world.b * x + world.d * y + world.ty,
  )


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
  ## fixed segment lengths + chain joint origins come from the REST pose; the
  ## bones' CURRENT world rotations feed the solver; the target's CURRENT world
  ## position is the goal. `mix` is applied ONCE inside the solver. Output
  ## conventions differ per solver — 1-bone/chain return ABSOLUTE world angles,
  ## solveTwoBoneIk's child is RELATIVE to its parent — but the unified
  ## absolute-angle write-back below normalizes that (the child's absolute angle
  ## is parentRotation + childRotation).
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

  let storedMix = ik.mix
  let bendSign = if ik.bendPositive: 1.0 else: -1.0

  # Solved ABSOLUTE world angle (degrees) per constrained bone, chain order.
  var solvedWorldAngles = newSeq[float64](ik.bones.len)
  case ik.bones.len
  of 1:
    let length = ikDistance(restOrigins[0], targetRestPoint)
    let currentRotation = worldRotationDegrees(currentWorlds[0])
    let solved = solveOneBoneIk(restOrigins[0], length, currentRotation, target, storedMix)
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
    let solved = solveTwoBoneIk(restOrigins[0], parentLength, childLength, parentRotation, childRotation, target, bendSign, storedMix)
    solvedWorldAngles[0] = solved.parentRotation
    solvedWorldAngles[1] = solved.parentRotation + solved.childRotation
  else:
    var points = newSeq[IkPoint](ik.bones.len + 1)
    for i in 0 ..< ik.bones.len:
      points[i] = restOrigins[i]
    points[^1] = targetRestPoint
    var lengths = newSeq[float64](ik.bones.len)
    for i in 0 ..< ik.bones.len:
      lengths[i] = ikDistance(points[i], points[i + 1])
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
    let parentRotation = if hasParent: worldRotationDegrees(parentWorld) else: 0.0
    let newLocal = withRotation(locals[boneIndex], solvedWorldAngles[i] - parentRotation)
    locals[boneIndex] = newLocal
    worlds[boneIndex] = worldForBone(parentWorld, boneData(data.bones[boneIndex].name, parent, newLocal), hasParent)
    computed[boneIndex] = true


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


proc buildDrawBatches*(data: SkeletonData): seq[DrawBatch] =
  let worlds = computeWorldTransforms(data)
  var boneIndex = initTable[string, int]()
  var regions = initTable[string, RegionAttachment]()

  for index, bone in data.bones:
    boneIndex[bone.name] = index
  for region in data.regions:
    regions[region.name] = region

  for slot in data.slots:
    if slot.attachment.len == 0:
      continue
    let region = regions[slot.attachment]
    let index = boneIndex[slot.bone]
    let world = worlds[index]
    let halfWidth = region.width * 0.5
    let halfHeight = region.height * 0.5
    result.add DrawBatch(
      slot: slot.name,
      bone: slot.bone,
      attachment: slot.attachment,
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
