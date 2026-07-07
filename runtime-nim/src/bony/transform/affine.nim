## Core affine, local-FK, and nested-composition helpers for bony transforms.

import std/math

import bony/model

const basisEpsilon* = 1e-12

type
  Linear2* = object
    a*: float64
    b*: float64
    c*: float64
    d*: float64

  ParentFactors* = object
    rotation*: Linear2
    reflection*: Linear2
    scaleShear*: Linear2


proc identityLinear*(): Linear2 =
  Linear2(a: 1.0, b: 0.0, c: 0.0, d: 1.0)


proc mul*(left, right: Linear2): Linear2 =
  Linear2(
    a: left.a * right.a + left.c * right.b,
    b: left.b * right.a + left.d * right.b,
    c: left.a * right.c + left.c * right.d,
    d: left.b * right.c + left.d * right.d,
  )


proc affine*(linear: Linear2; tx, ty: float64): Affine2 =
  Affine2(a: linear.a, b: linear.b, c: linear.c, d: linear.d, tx: tx, ty: ty)


proc inverseLinear*(m: Linear2): tuple[ok: bool; inverse: Linear2] =
  ## Inverse of the 2x2 linear part [[a, c], [b, d]] (column-major a/b, c/d).
  let det = m.a * m.d - m.c * m.b
  if abs(det) < basisEpsilon:
    return (false, identityLinear())
  (true, Linear2(a: m.d / det, b: -m.b / det, c: -m.c / det, d: m.a / det))


proc localLinear*(local: LocalTransform): Linear2 =
  let xAngle = degToRad(local.rotation + local.shearX)
  let yAngle = degToRad(local.rotation + 90.0 + local.shearY)
  Linear2(
    a: cos(xAngle) * local.scaleX,
    b: sin(xAngle) * local.scaleX,
    c: cos(yAngle) * local.scaleY,
    d: sin(yAngle) * local.scaleY,
  )


proc factorParent*(parent: Affine2): ParentFactors =
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


proc worldForBone*(parent: Affine2; bone: BoneData; hasParent: bool): Affine2 =
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


proc composeAffine*(parent, child: Affine2): Affine2 =
  ## Column-major affine composition: parent * child.
  Affine2(
    a: parent.a * child.a + parent.c * child.b,
    b: parent.b * child.a + parent.d * child.b,
    c: parent.a * child.c + parent.c * child.d,
    d: parent.b * child.c + parent.d * child.d,
    tx: parent.a * child.tx + parent.c * child.ty + parent.tx,
    ty: parent.b * child.tx + parent.d * child.ty + parent.ty,
  )


proc composeVertex(parent: Affine2; vertex: DrawVertex): DrawVertex =
  let point = transformPoint(parent, vertex.x, vertex.y)
  DrawVertex(
    x: point.x,
    y: point.y,
    u: vertex.u,
    v: vertex.v,
    r: vertex.r,
    g: vertex.g,
    b: vertex.b,
    a: vertex.a,
  )


proc composeBatch*(parent: Affine2; batch: DrawBatch): DrawBatch =
  result = DrawBatch(
    slot: batch.slot,
    bone: batch.bone,
    attachment: batch.attachment,
    texturePage: batch.texturePage,
    blendMode: batch.blendMode,
    clipId: batch.clipId,
    world: composeAffine(parent, batch.world),
    vertices: newSeq[DrawVertex](batch.vertices.len),
    indices: batch.indices,
  )
  for index, vertex in batch.vertices:
    result.vertices[index] = composeVertex(parent, vertex)


proc transformVector*(world: Affine2; x, y: float64): tuple[x: float64, y: float64] =
  (
    x: world.a * x + world.c * y,
    y: world.b * x + world.d * y,
  )


proc inverseAffine*(world: Affine2): tuple[ok: bool; inverse: Affine2] =
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


proc shortestAngleDelta*(fromAngle, toAngle: float64): float64 =
  var delta = (toAngle - fromAngle) mod 360.0
  if delta > 180.0:
    delta -= 360.0
  elif delta < -180.0:
    delta += 360.0
  delta


proc worldRotationDegrees*(world: Affine2): float64 =
  radToDeg(arctan2(world.b, world.a))
