/// M5 transform constraint solver.
///
/// Clean-room port of the bony Nim reference
/// `runtime-nim/src/bony/constraints/transform_constraints.nim` (project-owned
/// affine decomposition + per-channel mix, ported symbol-for-symbol). Not
/// derived from any third-party runtime.
import 'dart:math' as math;

import 'model.dart';
import 'numeric_guards.dart'
    show degToRad, hypot, lerp, radToDeg, requireFinite, requireMix;

/// Per-channel blend amounts, each in `[0, 1]`. Defaults to full influence (1.0)
/// on every channel, matching the Nim `transformConstraintMix` proc.
class TransformConstraintMix {
  const TransformConstraintMix({
    this.translate = 1.0,
    this.rotate = 1.0,
    this.scale = 1.0,
    this.shear = 1.0,
  });

  final double translate;
  final double rotate;
  final double scale;
  final double shear;
}

/// Decomposed 2D affine pose: translation, rotation (degrees), per-axis scale,
/// and per-axis shear (degrees). Mirrors the Nim `TransformConstraintPose`.
class TransformConstraintPose {
  const TransformConstraintPose({
    required this.x,
    required this.y,
    required this.rotation,
    required this.scaleX,
    required this.scaleY,
    required this.shearX,
    required this.shearY,
  });

  final double x;
  final double y;
  final double rotation;
  final double scaleX;
  final double scaleY;
  final double shearX;
  final double shearY;
}

TransformConstraintMix _safeMix(TransformConstraintMix mix) =>
    TransformConstraintMix(
      translate: requireMix(mix.translate, 'transformConstraint.translateMix'),
      rotate: requireMix(mix.rotate, 'transformConstraint.rotateMix'),
      scale: requireMix(mix.scale, 'transformConstraint.scaleMix'),
      shear: requireMix(mix.shear, 'transformConstraint.shearMix'),
    );

Affine2 _safeAffine(Affine2 world, String context) => Affine2(
      a: requireFinite(world.a, '$context.a'),
      b: requireFinite(world.b, '$context.b'),
      c: requireFinite(world.c, '$context.c'),
      d: requireFinite(world.d, '$context.d'),
      tx: requireFinite(world.tx, '$context.tx'),
      ty: requireFinite(world.ty, '$context.ty'),
    );

double _normalizeDegrees(double value) {
  var result = value;
  while (result < -180.0) {
    result += 360.0;
  }
  while (result > 180.0) {
    result -= 360.0;
  }
  return result;
}

double _lerpAngle(double a, double b, double mix) =>
    a + _normalizeDegrees(b - a) * mix;

/// Decompose a world affine into a translation/rotation/scale/shear pose.
/// Canonicalizes all shear into `shearY` (shearX is always 0), matching the Nim
/// `affineToTransformPose`.
TransformConstraintPose affineToTransformPose(Affine2 world) {
  final safe = _safeAffine(world, 'transformConstraint.world');
  final det = safe.a * safe.d - safe.b * safe.c;
  final scaleXMagnitude = hypot(safe.a, safe.b);
  final scaleX = det < 0.0 ? -scaleXMagnitude : scaleXMagnitude;
  final rotation = scaleX < 0.0
      ? radToDeg(math.atan2(-safe.b, -safe.a))
      : radToDeg(math.atan2(safe.b, safe.a));
  final yAngle = radToDeg(math.atan2(safe.d, safe.c));
  final scaleY = hypot(safe.c, safe.d);

  return TransformConstraintPose(
    x: safe.tx,
    y: safe.ty,
    rotation: rotation,
    scaleX: scaleX,
    scaleY: scaleY,
    shearX: 0.0,
    shearY: _normalizeDegrees(yAngle - rotation - 90.0),
  );
}

/// Recompose a pose into a world affine. Exact inverse of the local-linear
/// composition used by the FK path, matching the Nim `transformPoseToAffine`.
Affine2 transformPoseToAffine(TransformConstraintPose pose) {
  final x = requireFinite(pose.x, 'transformConstraint.pose.x');
  final y = requireFinite(pose.y, 'transformConstraint.pose.y');
  final rotation =
      requireFinite(pose.rotation, 'transformConstraint.pose.rotation');
  final scaleX = requireFinite(pose.scaleX, 'transformConstraint.pose.scaleX');
  final scaleY = requireFinite(pose.scaleY, 'transformConstraint.pose.scaleY');
  final shearX = requireFinite(pose.shearX, 'transformConstraint.pose.shearX');
  final shearY = requireFinite(pose.shearY, 'transformConstraint.pose.shearY');
  final xAngle = degToRad(rotation + shearX);
  final yAngle = degToRad(rotation + 90.0 + shearY);

  return Affine2(
    a: math.cos(xAngle) * scaleX,
    b: math.sin(xAngle) * scaleX,
    c: math.cos(yAngle) * scaleY,
    d: math.sin(yAngle) * scaleY,
    tx: x,
    ty: y,
  );
}

/// Blend the constrained bone's world pose toward the target's world pose,
/// per channel. Mirrors the Nim `applyTransformConstraint`.
Affine2 applyTransformConstraint(
    Affine2 constrained, Affine2 target, TransformConstraintMix mix) {
  final storedMix = _safeMix(mix);
  final constrainedPose = affineToTransformPose(constrained);
  final targetPose = affineToTransformPose(target);
  return transformPoseToAffine(TransformConstraintPose(
    x: lerp(constrainedPose.x, targetPose.x, storedMix.translate),
    y: lerp(constrainedPose.y, targetPose.y, storedMix.translate),
    rotation: _lerpAngle(
        constrainedPose.rotation, targetPose.rotation, storedMix.rotate),
    scaleX: lerp(constrainedPose.scaleX, targetPose.scaleX, storedMix.scale),
    scaleY: lerp(constrainedPose.scaleY, targetPose.scaleY, storedMix.scale),
    shearX:
        _lerpAngle(constrainedPose.shearX, targetPose.shearX, storedMix.shear),
    shearY:
        _lerpAngle(constrainedPose.shearY, targetPose.shearY, storedMix.shear),
  ));
}
