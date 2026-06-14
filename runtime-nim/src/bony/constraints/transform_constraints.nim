## M5 transform constraint solvers.

import std/math

import bony/model

type
  TransformConstraintMix* = object
    translate*: float64
    rotate*: float64
    scale*: float64
    shear*: float64

  TransformConstraintPose* = object
    x*: float64
    y*: float64
    rotation*: float64
    scaleX*: float64
    scaleY*: float64
    shearX*: float64
    shearY*: float64


proc transformConstraintMix*(translate = 1.0; rotate = 1.0; scale = 1.0; shear = 1.0): TransformConstraintMix =
  TransformConstraintMix(translate: translate, rotate: rotate, scale: scale, shear: shear)


proc requireFinite(value: float64; context: string): float64 =
  if classify(value) in {fcNan, fcInf, fcNegInf}:
    raise newBonyLoadError(numericOutOfRange, context & " must be finite")
  value


proc requireMix(value: float64; context: string): float64 =
  result = requireFinite(value, context)
  if result < 0.0 or result > 1.0:
    raise newBonyLoadError(schemaViolation, context & " must be in [0, 1]")


proc safeMix(mix: TransformConstraintMix): TransformConstraintMix =
  TransformConstraintMix(
    translate: requireMix(mix.translate, "transformConstraint.translateMix"),
    rotate: requireMix(mix.rotate, "transformConstraint.rotateMix"),
    scale: requireMix(mix.scale, "transformConstraint.scaleMix"),
    shear: requireMix(mix.shear, "transformConstraint.shearMix"),
  )


proc safeAffine(world: Affine2; context: string): Affine2 =
  Affine2(
    a: requireFinite(world.a, context & ".a"),
    b: requireFinite(world.b, context & ".b"),
    c: requireFinite(world.c, context & ".c"),
    d: requireFinite(world.d, context & ".d"),
    tx: requireFinite(world.tx, context & ".tx"),
    ty: requireFinite(world.ty, context & ".ty"),
  )


proc lerp(a, b, mix: float64): float64 =
  a + (b - a) * mix


proc affineToTransformPose*(world: Affine2): TransformConstraintPose =
  let safe = safeAffine(world, "transformConstraint.world")
  let scaleX = hypot(safe.a, safe.b)
  let rotation = radToDeg(arctan2(safe.b, safe.a))
  let yAngle = radToDeg(arctan2(safe.d, safe.c))
  let scaleY = hypot(safe.c, safe.d)

  TransformConstraintPose(
    x: safe.tx,
    y: safe.ty,
    rotation: rotation,
    scaleX: scaleX,
    scaleY: scaleY,
    shearX: 0.0,
    shearY: yAngle - rotation - 90.0,
  )


proc transformPoseToAffine*(pose: TransformConstraintPose): Affine2 =
  let x = requireFinite(pose.x, "transformConstraint.pose.x")
  let y = requireFinite(pose.y, "transformConstraint.pose.y")
  let rotation = requireFinite(pose.rotation, "transformConstraint.pose.rotation")
  let scaleX = requireFinite(pose.scaleX, "transformConstraint.pose.scaleX")
  let scaleY = requireFinite(pose.scaleY, "transformConstraint.pose.scaleY")
  let shearX = requireFinite(pose.shearX, "transformConstraint.pose.shearX")
  let shearY = requireFinite(pose.shearY, "transformConstraint.pose.shearY")
  let xAngle = degToRad(rotation + shearX)
  let yAngle = degToRad(rotation + 90.0 + shearY)

  Affine2(
    a: cos(xAngle) * scaleX,
    b: sin(xAngle) * scaleX,
    c: cos(yAngle) * scaleY,
    d: sin(yAngle) * scaleY,
    tx: x,
    ty: y,
  )


proc applyTransformConstraint*(constrained, target: Affine2; mix: TransformConstraintMix): Affine2 =
  let storedMix = safeMix(mix)
  let constrainedPose = affineToTransformPose(constrained)
  let targetPose = affineToTransformPose(target)
  transformPoseToAffine(TransformConstraintPose(
    x: lerp(constrainedPose.x, targetPose.x, storedMix.translate),
    y: lerp(constrainedPose.y, targetPose.y, storedMix.translate),
    rotation: lerp(constrainedPose.rotation, targetPose.rotation, storedMix.rotate),
    scaleX: lerp(constrainedPose.scaleX, targetPose.scaleX, storedMix.scale),
    scaleY: lerp(constrainedPose.scaleY, targetPose.scaleY, storedMix.scale),
    shearX: lerp(constrainedPose.shearX, targetPose.shearX, storedMix.shear),
    shearY: lerp(constrainedPose.shearY, targetPose.shearY, storedMix.shear),
  ))
