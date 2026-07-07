import '../physics_constraint.dart' show PhysicsChannel;

class PathConstraintData {
  const PathConstraintData({
    required this.name,
    required this.bone,
    required this.target,
    required this.path,
    required this.order,
    this.skinRequired = false,
    this.position,
    this.translateMix,
    this.rotateMix,
  });

  final String name;
  final String bone;
  final String target;
  final String path;
  final int order;
  final bool skinRequired;
  final double? position;
  final double? translateMix;
  final double? rotateMix;

  bool get runtimeEvaluable =>
      position != null || translateMix != null || rotateMix != null;
}

class IkConstraintData {
  const IkConstraintData({
    required this.name,
    required this.bones,
    required this.target,
    required this.order,
    this.skinRequired = false,
    this.mix,
    this.bendPositive,
  });

  final String name;

  /// Bone chain the constraint solves, root -> tip. Required (never empty).
  final List<String> bones;
  final String target;
  final int order;
  final bool skinRequired;

  /// Solver blend amount. `null` means the field was absent on load (defaults
  /// to 1.0); mirrors the Nim `hasMix` flag via nullability.
  final double? mix;

  /// `null` means absent on load (defaults to true); mirrors `hasBendPositive`.
  final bool? bendPositive;

  /// Constraint-only predicate mirroring runtime-nim's `runtimeEvaluable`
  /// (model.nim): an IK constraint contributes nothing when mix == 0 or it
  /// names no bones. Absent mix defaults to 1.0 (evaluable). Dart now evaluates
  /// IK: `computeWorldTransforms` solves each evaluable constraint via
  /// `_applyRuntimeIk` (see transform.dart).
  bool get runtimeEvaluable => bones.isNotEmpty && (mix ?? 1.0) > 0.0;
}

/// Transform constraint: blends a single constrained bone's world pose toward a
/// target bone's world pose, per channel. The four mixes are nullable doubles
/// where `null` means the field was absent on load (defaults to 1.0); the
/// nullability mirrors the Nim `hasTranslateMix`/... presence flags.
class TransformConstraintData {
  const TransformConstraintData({
    required this.name,
    required this.bone,
    required this.target,
    required this.order,
    this.skinRequired = false,
    this.translateMix,
    this.rotateMix,
    this.scaleMix,
    this.shearMix,
  });

  final String name;
  final String bone;
  final String target;
  final int order;
  final bool skinRequired;
  final double? translateMix;
  final double? rotateMix;
  final double? scaleMix;
  final double? shearMix;

  /// Constraint-only predicate mirroring runtime-nim's `runtimeEvaluable(tc)`:
  /// a transform constraint contributes nothing when every mix is zero. Absent
  /// mixes default to 1.0 (evaluable). Used consistently in the detection gate,
  /// the update-cache read gating, and the apply guard.
  bool get runtimeEvaluable =>
      (translateMix ?? 1.0) > 0.0 ||
      (rotateMix ?? 1.0) > 0.0 ||
      (scaleMix ?? 1.0) > 0.0 ||
      (shearMix ?? 1.0) > 0.0;
}

/// Loadable physics-constraint record. Mirrors the Nim `PhysicsConstraintData`:
/// a constrained bone, a signed order, the enabled channel set, and the
/// integrator inputs consumed by `physicsParams` / `updatePhysicsConstraint`.
/// Physics springs off the bone's own animated target, so there is NO target
/// bone. Each optional param is null when absent (the integrator applies the
/// same defaults as the Nim `physicsParams`: mass=1.0, physicsMix=1.0, the rest
/// 0.0), mirroring how [TransformConstraintData] carries nullable mixes.
class PhysicsConstraintData {
  const PhysicsConstraintData({
    required this.name,
    required this.bone,
    required this.channels,
    this.order = 0,
    this.skinRequired = false,
    this.inertia,
    this.strength,
    this.damping,
    this.mass,
    this.gravity,
    this.wind,
    this.physicsMix,
  });

  final String name;
  final String bone;
  final Set<PhysicsChannel> channels;
  final int order;
  final bool skinRequired;
  final double? inertia;
  final double? strength;
  final double? damping;
  final double? mass;
  final double? gravity;
  final double? wind;
  final double? physicsMix;
}
