## M2 world-transform evaluation and backend-neutral draw batches.

import std/[math, tables]

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


proc computeWorldTransforms*(data: SkeletonData): seq[Affine2] =
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
