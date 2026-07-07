// M5 IK constraint solvers.
//
// Clean-room port of runtime-nim/src/bony/constraints/ik.nim: the one-bone,
// two-bone, and FABRIK chain solvers plus their result types, the quantizing
// ikPoint() solver-input constructor, and the finite/non-negative/mix guards.
// The only behavioral sources are the Nim reference and the IK format contract
// (docs/ik-constraint-format-contract.md) — no DragonBones/Spine/Rive/etc.
//
// Quantization note: the runtime evaluation path (transform.dart) constructs
// its solver-input points WITHOUT quantization to match the committed goldens,
// so it uses the raw `IkPoint(x, y)` constructor. `ikPoint()` here quantizes
// both coordinates through float32 and is intended for hand-authored solver
// unit tests only (the runtime-nim test_smoke.nim parallel). Do NOT route the
// runtime path through ikPoint().

import 'dart:math' as math;

import 'deform.dart' show quantizeF32;
import 'numeric_guards.dart'
    show
        degToRad,
        distance,
        hypot,
        lerp,
        radToDeg,
        requireFinite,
        requireMix,
        requireNonNegative;

/// FABRIK forward/backward reaching iteration count (ik.nim:8).
const int fabrikIterations = 8;

/// FABRIK convergence tolerance on the end-effector (ik.nim:9).
const double fabrikTolerance = 1e-4;

/// Below this a segment/target distance is treated as degenerate (ik.nim:10).
const double _solverEpsilon = 1e-12;

/// A 2D point in world space used by the solvers.
class IkPoint {
  const IkPoint(this.x, this.y);

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is IkPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'IkPoint($x, $y)';
}

/// Result of [solveOneBoneIk]: an ABSOLUTE world rotation (degrees) + tip.
class OneBoneIkResult {
  const OneBoneIkResult(this.rotation, this.endPoint);

  final double rotation;
  final IkPoint endPoint;
}

/// Result of [solveTwoBoneIk]. `parentRotation` is ABSOLUTE world (degrees);
/// `childRotation` is RELATIVE to the parent (absolute = parent + child).
class TwoBoneIkResult {
  const TwoBoneIkResult(
    this.parentRotation,
    this.childRotation,
    this.midPoint,
    this.endPoint,
  );

  final double parentRotation;
  final double childRotation;
  final IkPoint midPoint;
  final IkPoint endPoint;
}

/// Result of [solveChainIk]. `rotations` are ABSOLUTE segment angles in
/// degrees, ordered like `points[0 ..^ 1]`.
class ChainIkResult {
  const ChainIkResult(this.points, this.rotations);

  final List<IkPoint> points;
  final List<double> rotations;
}

/// Solver-input constructor that quantizes BOTH coordinates through float32.
/// For hand-authored solver unit tests only — the runtime path constructs
/// points directly via [IkPoint] without quantization (see file header).
IkPoint ikPoint(double x, double y) => IkPoint(quantizeF32(x), quantizeF32(y));

IkPoint _requirePoint(IkPoint point, String context) => IkPoint(
      requireFinite(point.x, '$context.x'),
      requireFinite(point.y, '$context.y'),
    );

double _clampUnit(double value) => math.max(-1.0, math.min(1.0, value));

({double x, double y}) _direction(
  IkPoint fromPoint,
  IkPoint toPoint,
  double fallbackAngle,
) {
  final dx = toPoint.x - fromPoint.x;
  final dy = toPoint.y - fromPoint.y;
  final distance = hypot(dx, dy);
  if (distance > _solverEpsilon) {
    return (x: dx / distance, y: dy / distance);
  }
  return (x: math.cos(fallbackAngle), y: math.sin(fallbackAngle));
}

/// One-bone IK: rotate a single bone from [origin] toward [target].
/// Returns an ABSOLUTE world rotation in degrees. `mix = 0` is identity
/// (returns the current rotation / current tip).
OneBoneIkResult solveOneBoneIk(
  IkPoint origin,
  double length,
  double currentRotation,
  IkPoint target, {
  double mix = 1.0,
}) {
  final safeOrigin = _requirePoint(origin, 'ik.origin');
  final safeTarget = _requirePoint(target, 'ik.target');
  final storedLength = requireNonNegative(length, 'ik.length');
  final storedMix = requireMix(mix, 'ik.mix');
  final baseRotation = requireFinite(currentRotation, 'ik.currentRotation');
  final targetRotation = radToDeg(
    math.atan2(safeTarget.y - safeOrigin.y, safeTarget.x - safeOrigin.x),
  );
  final rotation = lerp(baseRotation, targetRotation, storedMix);
  final radians = degToRad(rotation);
  final endPoint = IkPoint(
    safeOrigin.x + math.cos(radians) * storedLength,
    safeOrigin.y + math.sin(radians) * storedLength,
  );
  return OneBoneIkResult(rotation, endPoint);
}

/// Two-bone IK (law-of-cosines). `parentRotation`/`childRotation` are the
/// bones' CURRENT rotations, with `childRotation` RELATIVE to the parent. The
/// result mirrors that convention. `bendSign` selects the elbow direction
/// (< 0 flips it); `mix = 0` is identity.
TwoBoneIkResult solveTwoBoneIk(
  IkPoint origin,
  double parentLength,
  double childLength,
  double parentRotation,
  double childRotation,
  IkPoint target, {
  double bendSign = 1.0,
  double mix = 1.0,
}) {
  final safeOrigin = _requirePoint(origin, 'ik.origin');
  final safeTarget = _requirePoint(target, 'ik.target');
  final l1 = requireNonNegative(parentLength, 'ik.parentLength');
  final l2 = requireNonNegative(childLength, 'ik.childLength');
  final storedMix = requireMix(mix, 'ik.mix');
  final currentParent = requireFinite(parentRotation, 'ik.parentRotation');
  final currentChild = requireFinite(childRotation, 'ik.childRotation');
  final safeBendSign = requireFinite(bendSign, 'ik.bendSign');
  final sign = safeBendSign < 0.0 ? -1.0 : 1.0;

  final tx = safeTarget.x - safeOrigin.x;
  final ty = safeTarget.y - safeOrigin.y;
  final d = hypot(tx, ty);
  final denominator = 2.0 * l1 * l2;
  final solvedChild = denominator <= _solverEpsilon
      ? 0.0
      : math.acos(_clampUnit((d * d - l1 * l1 - l2 * l2) / denominator)) * sign;
  final k1 = l1 + l2 * math.cos(solvedChild);
  final k2 = l2 * math.sin(solvedChild);
  final solvedParent = math.atan2(ty, tx) - math.atan2(k2, k1);

  final resultParent = lerp(currentParent, radToDeg(solvedParent), storedMix);
  final resultChild = lerp(currentChild, radToDeg(solvedChild), storedMix);

  final parentRadians = degToRad(resultParent);
  final childRadians = degToRad(resultParent + resultChild);
  final midPoint = IkPoint(
    safeOrigin.x + math.cos(parentRadians) * l1,
    safeOrigin.y + math.sin(parentRadians) * l1,
  );
  final endPoint = IkPoint(
    midPoint.x + math.cos(childRadians) * l2,
    midPoint.y + math.sin(childRadians) * l2,
  );
  return TwoBoneIkResult(resultParent, resultChild, midPoint, endPoint);
}

/// FABRIK chain IK over [points] (>= 2) with fixed segment [lengths]
/// (`points.length - 1` of them). Returns ABSOLUTE segment angles. Handles the
/// root-past-total-length straight-line case and degenerate/collinear
/// bend-plane seeding before iterating. `mix = 0` is identity.
ChainIkResult solveChainIk(
  List<IkPoint> points,
  List<double> lengths,
  IkPoint target, {
  double mix = 1.0,
}) {
  if (points.length < 2) {
    throw const FormatException('ik chain needs at least two points');
  }
  if (lengths.length != points.length - 1) {
    throw const FormatException(
      'ik chain length count must equal point count minus one',
    );
  }
  final storedMix = requireMix(mix, 'ik.mix');
  final safeTarget = _requirePoint(target, 'ik.target');
  final resultPoints = <IkPoint>[
    for (var index = 0; index < points.length; index++)
      _requirePoint(points[index], 'ik.point[$index]'),
  ];
  // Independent snapshot of the validated inputs: the FABRIK passes mutate
  // resultPoints in place, but the final mix blends against these originals
  // (Nim's `safePoints`, which stays unmutated after `result.points` copies).
  final safePoints = List<IkPoint>.of(resultPoints);

  var totalLength = 0.0;
  final solvedLengths = <double>[
    for (var index = 0; index < lengths.length; index++)
      requireNonNegative(lengths[index], 'ik.length[$index]'),
  ];
  for (final length in solvedLengths) {
    totalLength += length;
  }

  final root = safePoints[0];
  final targetAngle = math.atan2(safeTarget.y - root.y, safeTarget.x - root.x);
  final rootToTarget = distance(root.x, root.y, safeTarget.x, safeTarget.y);
  if (rootToTarget > totalLength) {
    final angle = targetAngle;
    for (var index = 1; index < resultPoints.length; index++) {
      resultPoints[index] = IkPoint(
        resultPoints[index - 1].x + math.cos(angle) * solvedLengths[index - 1],
        resultPoints[index - 1].y + math.sin(angle) * solvedLengths[index - 1],
      );
    }
  } else {
    var hasDegenerateSegment = false;
    for (var index = 0; index < resultPoints.length - 1; index++) {
      if (solvedLengths[index] > _solverEpsilon &&
          distance(
                resultPoints[index].x,
                resultPoints[index].y,
                resultPoints[index + 1].x,
                resultPoints[index + 1].y,
              ) <=
              _solverEpsilon) {
        hasDegenerateSegment = true;
        break;
      }
    }
    if (hasDegenerateSegment && rootToTarget > _solverEpsilon) {
      final ux = (safeTarget.x - root.x) / rootToTarget;
      final uy = (safeTarget.y - root.y) / rootToTarget;
      final bend = math.sqrt(
            math.max(
              totalLength * totalLength - rootToTarget * rootToTarget,
              0.0,
            ),
          ) *
          0.5;
      var walked = 0.0;
      for (var index = 1; index < resultPoints.length - 1; index++) {
        walked += solvedLengths[index - 1];
        final t = walked / totalLength;
        final offset = math.sin(math.pi * t) * bend;
        resultPoints[index] = IkPoint(
          root.x + (safeTarget.x - root.x) * t - uy * offset,
          root.y + (safeTarget.y - root.y) * t + ux * offset,
        );
      }
    }

    for (var iteration = 0; iteration < fabrikIterations; iteration++) {
      resultPoints[resultPoints.length - 1] = safeTarget;
      for (var index = resultPoints.length - 2; index >= 0; index--) {
        final next = resultPoints[index + 1];
        final current = resultPoints[index];
        final fallback = index == 0
            ? targetAngle
            : math.atan2(
                resultPoints[index].y - resultPoints[index - 1].y,
                resultPoints[index].x - resultPoints[index - 1].x,
              );
        final unit = _direction(next, current, fallback);
        resultPoints[index] = IkPoint(
          next.x + unit.x * solvedLengths[index],
          next.y + unit.y * solvedLengths[index],
        );
      }

      resultPoints[0] = root;
      for (var index = 0; index < resultPoints.length - 1; index++) {
        final current = resultPoints[index];
        final next = resultPoints[index + 1];
        final fallback = index + 2 < resultPoints.length
            ? math.atan2(
                resultPoints[index + 2].y - resultPoints[index + 1].y,
                resultPoints[index + 2].x - resultPoints[index + 1].x,
              )
            : targetAngle;
        final unit = _direction(current, next, fallback);
        resultPoints[index + 1] = IkPoint(
          current.x + unit.x * solvedLengths[index],
          current.y + unit.y * solvedLengths[index],
        );
      }

      if (distance(
            resultPoints[resultPoints.length - 1].x,
            resultPoints[resultPoints.length - 1].y,
            safeTarget.x,
            safeTarget.y,
          ) <=
          fabrikTolerance) {
        break;
      }
    }
  }

  for (var index = 0; index < safePoints.length; index++) {
    final original = safePoints[index];
    resultPoints[index] = IkPoint(
      lerp(original.x, resultPoints[index].x, storedMix),
      lerp(original.y, resultPoints[index].y, storedMix),
    );
  }
  // Segment angles are derived AFTER the mix blend (mirroring Nim), so with
  // mix < 1 they describe the blended pose, not the fully-solved one.
  final rotations = <double>[];
  for (var index = 0; index < resultPoints.length - 1; index++) {
    final current = resultPoints[index];
    final next = resultPoints[index + 1];
    rotations.add(
      radToDeg(math.atan2(next.y - current.y, next.x - current.x)),
    );
  }
  return ChainIkResult(resultPoints, rotations);
}
