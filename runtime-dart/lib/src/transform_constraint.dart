/// M5 transform constraint solver.
///
/// Clean-room port of the bony Nim reference
/// `runtime-nim/src/bony/constraints/transform_constraints.nim` (project-owned
/// affine decomposition + per-channel mix, ported symbol-for-symbol). Not
/// derived from any third-party runtime.
import 'dart:math' as math;

import 'model.dart';

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

double _requireFinite(double value, String context) {
  if (value.isNaN || value.isInfinite) {
    throw FormatException('$context must be finite');
  }
  return value;
}

double _requireMix(double value, String context) {
  final result = _requireFinite(value, context);
  if (result < 0.0 || result > 1.0) {
    throw FormatException('$context must be in [0, 1]');
  }
  return result;
}

TransformConstraintMix _safeMix(TransformConstraintMix mix) =>
    TransformConstraintMix(
      translate: _requireMix(mix.translate, 'transformConstraint.translateMix'),
      rotate: _requireMix(mix.rotate, 'transformConstraint.rotateMix'),
      scale: _requireMix(mix.scale, 'transformConstraint.scaleMix'),
      shear: _requireMix(mix.shear, 'transformConstraint.shearMix'),
    );

Affine2 _safeAffine(Affine2 world, String context) => Affine2(
      a: _requireFinite(world.a, '$context.a'),
      b: _requireFinite(world.b, '$context.b'),
      c: _requireFinite(world.c, '$context.c'),
      d: _requireFinite(world.d, '$context.d'),
      tx: _requireFinite(world.tx, '$context.tx'),
      ty: _requireFinite(world.ty, '$context.ty'),
    );

double _lerp(double a, double b, double mix) => a + (b - a) * mix;

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

double _degToRad(double deg) => deg * math.pi / 180.0;
double _radToDeg(double rad) => rad * 180.0 / math.pi;

/// Decompose a world affine into a translation/rotation/scale/shear pose.
/// Canonicalizes all shear into `shearY` (shearX is always 0), matching the Nim
/// `affineToTransformPose`.
TransformConstraintPose affineToTransformPose(Affine2 world) {
  final safe = _safeAffine(world, 'transformConstraint.world');
  final det = safe.a * safe.d - safe.b * safe.c;
  final scaleXMagnitude = _hypot(safe.a, safe.b);
  final scaleX = det < 0.0 ? -scaleXMagnitude : scaleXMagnitude;
  final rotation = scaleX < 0.0
      ? _radToDeg(math.atan2(-safe.b, -safe.a))
      : _radToDeg(math.atan2(safe.b, safe.a));
  final yAngle = _radToDeg(math.atan2(safe.d, safe.c));
  final scaleY = _hypot(safe.c, safe.d);

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
  final x = _requireFinite(pose.x, 'transformConstraint.pose.x');
  final y = _requireFinite(pose.y, 'transformConstraint.pose.y');
  final rotation = _requireFinite(pose.rotation, 'transformConstraint.pose.rotation');
  final scaleX = _requireFinite(pose.scaleX, 'transformConstraint.pose.scaleX');
  final scaleY = _requireFinite(pose.scaleY, 'transformConstraint.pose.scaleY');
  final shearX = _requireFinite(pose.shearX, 'transformConstraint.pose.shearX');
  final shearY = _requireFinite(pose.shearY, 'transformConstraint.pose.shearY');
  final xAngle = _degToRad(rotation + shearX);
  final yAngle = _degToRad(rotation + 90.0 + shearY);

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
    x: _lerp(constrainedPose.x, targetPose.x, storedMix.translate),
    y: _lerp(constrainedPose.y, targetPose.y, storedMix.translate),
    rotation:
        _lerpAngle(constrainedPose.rotation, targetPose.rotation, storedMix.rotate),
    scaleX: _lerp(constrainedPose.scaleX, targetPose.scaleX, storedMix.scale),
    scaleY: _lerp(constrainedPose.scaleY, targetPose.scaleY, storedMix.scale),
    shearX:
        _lerpAngle(constrainedPose.shearX, targetPose.shearX, storedMix.shear),
    shearY:
        _lerpAngle(constrainedPose.shearY, targetPose.shearY, storedMix.shear),
  ));
}

double _hypot(double x, double y) => math.sqrt(x * x + y * y);
