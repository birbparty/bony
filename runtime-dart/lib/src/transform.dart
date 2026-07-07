// World transform computation: M2 skeleton pose (t=0 setup pose only).
//
// Ports the Nim reference implementation in runtime-nim/src/bony/transform.nim.

import 'dart:math' as math;
import 'deform.dart';
import 'drawbatch_clipping.dart';
import 'ik.dart';
import 'model.dart';
import 'numeric_guards.dart' show distance, lerp, radToDeg;
import 'physics_constraint.dart';
import 'transform_constraint.dart';

const double _basisEpsilon = 1e-12;
const double helperGeometryTolerance = 1e-4;
const int _pathArcLengthSamples = 32;

// 2x2 linear (rotation/scale/shear) matrix — intermediate for parent factoring.
class _Lin2 {
  const _Lin2(this.a, this.b, this.c, this.d);
  final double a, b, c, d;

  _Lin2 mul(_Lin2 r) => _Lin2(
        a * r.a + c * r.b,
        b * r.a + d * r.b,
        a * r.c + c * r.d,
        b * r.c + d * r.d,
      );
}

const _identity = _Lin2(1.0, 0.0, 0.0, 1.0);

Affine2 _affine(_Lin2 m, double tx, double ty) =>
    Affine2(a: m.a, b: m.b, c: m.c, d: m.d, tx: tx, ty: ty);

// Inverse of a 2x2 linear part [[a, c], [b, d]] (column-major a/b, c/d); null if
// singular. Mirrors runtime-nim's inverseLinear.
_Lin2? _inverseLinear(_Lin2 m) {
  final det = m.a * m.d - m.c * m.b;
  if (det.abs() < _basisEpsilon) return null;
  return _Lin2(m.d / det, -m.b / det, -m.c / det, m.a / det);
}

class _Point {
  const _Point(this.x, this.y);
  final double x, y;
}

class _Cubic {
  const _Cubic(this.p0, this.p1, this.p2, this.p3);
  final _Point p0, p1, p2, p3;
}

class _ArcLengthTable {
  const _ArcLengthTable(this.samples, this.distances, this.totalLength);
  final List<_Point> samples;
  final List<double> distances;
  final double totalLength;
}

class _PathSample {
  const _PathSample(this.position, this.tangentAngle, this.distance);
  final _Point position;
  final double tangentAngle;
  final double distance;
}

/// World-space point used by helper geometry query APIs.
class HelperPoint {
  const HelperPoint({required this.x, required this.y});

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      other is HelperPoint && other.x == x && other.y == y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'HelperPoint(x: $x, y: $y)';
}

/// World-space pose of a point helper attachment.
class HelperPointPose {
  const HelperPointPose({
    required this.x,
    required this.y,
    required this.rotation,
  });

  final double x;
  final double y;
  final double rotation;

  @override
  bool operator ==(Object other) =>
      other is HelperPointPose &&
      other.x == x &&
      other.y == y &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(x, y, rotation);

  @override
  String toString() => 'HelperPointPose(x: $x, y: $y, rotation: $rotation)';
}

class _BoneGroupEntry {
  const _BoneGroupEntry(this.bones);
  final List<int> bones;
}

enum _ConstraintKind { ik, transform, path, physics }

// Canonical kind rank for tie-breaking constraints at equal `order` (Nim
// constraintKindRank, model.nim): ckIk=0 < ckTransform=1 < ckPath=2 <
// ckPhysics=3. Physics ranks last but is NOT dispatched in the world-transform
// pass — it runs in the separate stateful stage ([advancePhysics]); the rank is
// carried only for parity with the Nim ordering.
int _constraintKindRank(_ConstraintKind kind) => switch (kind) {
      _ConstraintKind.ik => 0,
      _ConstraintKind.transform => 1,
      _ConstraintKind.path => 2,
      _ConstraintKind.physics => 3,
    };

class _ConstraintEntry {
  const _ConstraintEntry(this.kind, this.sourceIndex, this.active);
  final _ConstraintKind kind;
  final int sourceIndex;
  final bool active;
}

// Convert bone local transform to a 2x2 linear matrix.
_Lin2 _localLinear(BoneData bone) {
  final xAngle = (bone.rotation + bone.shearX) * math.pi / 180.0;
  final yAngle = (bone.rotation + 90.0 + bone.shearY) * math.pi / 180.0;
  return _Lin2(
    math.cos(xAngle) * bone.scaleX,
    math.sin(xAngle) * bone.scaleX,
    math.cos(yAngle) * bone.scaleY,
    math.sin(yAngle) * bone.scaleY,
  );
}

// Decomposed factors from a parent Affine2 (rotation, reflection, scaleShear).
class _Factors {
  const _Factors(this.rotation, this.reflection, this.scaleShear);
  final _Lin2 rotation, reflection, scaleShear;
}

_Factors _factorParent(Affine2 p) {
  final sx = math.sqrt(p.a * p.a + p.b * p.b);
  if (sx > _basisEpsilon) {
    final det = p.a * p.d - p.b * p.c;
    final sign = det < 0.0 ? -1.0 : 1.0;
    final r0x = p.a / sx;
    final r0y = p.b / sx;
    final r1x = -r0y;
    final r1y = r0x;
    final k = r0x * p.c + r0y * p.d;
    final sy = sign * (r1x * p.c + r1y * p.d);
    return _Factors(
      _Lin2(r0x, r0y, r1x, r1y),
      _Lin2(1.0, 0.0, 0.0, sign),
      _Lin2(sx, 0.0, k, sy),
    );
  }
  final vy = math.sqrt(p.c * p.c + p.d * p.d);
  if (vy > _basisEpsilon) {
    final r1x = p.c / vy;
    final r1y = p.d / vy;
    final r0x = r1y;
    final r0y = -r1x;
    return _Factors(
      _Lin2(r0x, r0y, r1x, r1y),
      _identity,
      _Lin2(0.0, 0.0, 0.0, vy),
    );
  }
  return _Factors(_identity, _identity, _Lin2(0.0, 0.0, 0.0, 0.0));
}

Affine2 _worldForBone(Affine2 parent, BoneData bone, bool hasParent) {
  final local = _localLinear(bone);
  if (!hasParent) {
    return _affine(local, bone.x, bone.y);
  }

  final f = _factorParent(parent);
  var inherited = _identity;
  if (bone.inheritRotation) inherited = inherited.mul(f.rotation);
  if (bone.inheritReflection) inherited = inherited.mul(f.reflection);
  if (bone.inheritScale) inherited = inherited.mul(f.scaleShear);

  final worldLin = inherited.mul(local);
  final tx = parent.tx + parent.a * bone.x + parent.c * bone.y;
  final ty = parent.ty + parent.b * bone.x + parent.d * bone.y;
  return _affine(worldLin, tx, ty);
}

BoneData _withLocal(BoneData base, {double? x, double? y, double? rotation}) {
  return BoneData(
    name: base.name,
    parent: base.parent,
    x: x ?? base.x,
    y: y ?? base.y,
    rotation: rotation ?? base.rotation,
    scaleX: base.scaleX,
    scaleY: base.scaleY,
    shearX: base.shearX,
    shearY: base.shearY,
    inheritRotation: base.inheritRotation,
    inheritScale: base.inheritScale,
    inheritReflection: base.inheritReflection,
    transformMode: base.transformMode,
    skinRequired: base.skinRequired,
  );
}

_Point _transformPoint(Affine2 world, double x, double y) => _Point(
      world.a * x + world.c * y + world.tx,
      world.b * x + world.d * y + world.ty,
    );

Affine2 _composeAffine(Affine2 parent, Affine2 child) => Affine2(
      a: parent.a * child.a + parent.c * child.b,
      b: parent.b * child.a + parent.d * child.b,
      c: parent.a * child.c + parent.c * child.d,
      d: parent.b * child.c + parent.d * child.d,
      tx: parent.a * child.tx + parent.c * child.ty + parent.tx,
      ty: parent.b * child.tx + parent.d * child.ty + parent.ty,
    );

DrawVertex _composeVertex(Affine2 parent, DrawVertex vertex) {
  final point = _transformPoint(parent, vertex.x, vertex.y);
  return DrawVertex(
    x: point.x,
    y: point.y,
    u: vertex.u,
    v: vertex.v,
    r: vertex.r,
    g: vertex.g,
    b: vertex.b,
    a: vertex.a,
  );
}

DrawBatch _composeBatch(Affine2 parent, DrawBatch batch) => DrawBatch(
      slot: batch.slot,
      bone: batch.bone,
      attachment: batch.attachment,
      blendMode: batch.blendMode,
      texturePage: batch.texturePage,
      clipId: batch.clipId,
      world: _composeAffine(parent, batch.world),
      vertices: [
        for (final vertex in batch.vertices) _composeVertex(parent, vertex)
      ],
      indices: List<int>.from(batch.indices),
    );

_Point _transformVector(Affine2 world, double x, double y) => _Point(
      world.a * x + world.c * y,
      world.b * x + world.d * y,
    );

Affine2? _inverseAffine(Affine2 world) {
  final det = world.a * world.d - world.b * world.c;
  if (det.abs() <= _basisEpsilon) return null;
  final invA = world.d / det;
  final invB = -world.b / det;
  final invC = -world.c / det;
  final invD = world.a / det;
  return Affine2(
    a: invA,
    b: invB,
    c: invC,
    d: invD,
    tx: -(invA * world.tx + invC * world.ty),
    ty: -(invB * world.tx + invD * world.ty),
  );
}

double _shortestAngleDelta(double fromAngle, double toAngle) {
  var delta = (toAngle - fromAngle) % 360.0;
  if (delta > 180.0) {
    delta -= 360.0;
  } else if (delta < -180.0) {
    delta += 360.0;
  }
  return delta;
}

// --- M5-IK evaluation helpers (mirror runtime-nim/src/bony/transform.nim) ---
//
// Kind-agnostic prep for the IK evaluation pass (`_applyRuntimeIk`, added in a
// later slice). Public so they can be unit-tested directly; all are pure.

/// World rotation of an affine transform, in degrees (transform.nim:349).
/// The world x-axis is (a, b), so the rotation is atan2(b, a).
double worldRotationDegrees(Affine2 world) =>
    radToDeg(math.atan2(world.b, world.a));

/// Euclidean distance between two IK points (transform.nim:353).
double ikDistance(IkPoint a, IkPoint b) => distance(a.x, a.y, b.x, b.y);

HelperPoint helperPoint(double x, double y) => HelperPoint(x: x, y: y);

Affine2 _slotBoneWorld(
  SkeletonData data,
  List<Affine2> worlds,
  String slotName,
  String activeSkin,
) {
  if (worlds.length != data.bones.length) {
    throw const FormatException(
        'helper query world transform count does not match skeleton bones');
  }
  final activation = data.activeSkinMembership(activeSkin);
  for (final slot in data.slots) {
    if (slot.name == slotName) {
      for (var boneIndex = 0; boneIndex < data.bones.length; boneIndex++) {
        final bone = data.bones[boneIndex];
        if (bone.name == slot.bone) {
          if (!activation.bones[boneIndex]) {
            throw FormatException('helper query slot is inactive: $slotName');
          }
          return worlds[boneIndex];
        }
      }
      throw FormatException(
          'helper query slot references unknown bone: ${slot.bone}');
    }
  }
  throw FormatException('helper query references unknown slot: $slotName');
}

/// World-space pose for a point helper attachment through [slotName]'s bone.
HelperPointPose worldPointAttachmentPose(
  SkeletonData data,
  List<Affine2> worlds,
  String slotName,
  String attachmentName, {
  String activeSkin = 'default',
}) {
  final world = _slotBoneWorld(data, worlds, slotName, activeSkin);
  final resolvedAttachment = data.skins.isNotEmpty
      ? data.resolveSkinAttachmentTarget(activeSkin, slotName, attachmentName)
      : '';
  final targetAttachment =
      resolvedAttachment.isNotEmpty ? resolvedAttachment : attachmentName;
  for (final point in data.pointAttachments) {
    if (point.name == targetAttachment) {
      final pos = _transformPoint(world, point.x, point.y);
      return HelperPointPose(
        x: pos.x,
        y: pos.y,
        rotation: worldRotationDegrees(world) + point.rotation,
      );
    }
  }
  throw FormatException('unknown point attachment: $attachmentName');
}

/// World-space polygon for a bounding-box helper attachment through [slotName].
List<HelperPoint> worldBoundingBoxAttachmentPolygon(
  SkeletonData data,
  List<Affine2> worlds,
  String slotName,
  String attachmentName, {
  String activeSkin = 'default',
}) {
  final world = _slotBoneWorld(data, worlds, slotName, activeSkin);
  final resolvedAttachment = data.skins.isNotEmpty
      ? data.resolveSkinAttachmentTarget(activeSkin, slotName, attachmentName)
      : '';
  final targetAttachment =
      resolvedAttachment.isNotEmpty ? resolvedAttachment : attachmentName;
  for (final box in data.boundingBoxAttachments) {
    if (box.name == targetAttachment) {
      final polygon = <HelperPoint>[];
      final vertices = box.vertices;
      if (vertices.length < 6 || vertices.length.isOdd) {
        throw FormatException(
            'bounding-box attachment has malformed vertices: $attachmentName');
      }
      for (var index = 0; index < vertices.length; index += 2) {
        final pos =
            _transformPoint(world, vertices[index], vertices[index + 1]);
        polygon.add(HelperPoint(x: pos.x, y: pos.y));
      }
      return polygon;
    }
  }
  throw FormatException('unknown bounding-box attachment: $attachmentName');
}

double _distanceToSegment(HelperPoint point, HelperPoint a, HelperPoint b) {
  final dx = b.x - a.x;
  final dy = b.y - a.y;
  final lengthSquared = dx * dx + dy * dy;
  if (lengthSquared <= _basisEpsilon) {
    return math.sqrt(
      (point.x - a.x) * (point.x - a.x) + (point.y - a.y) * (point.y - a.y),
    );
  }
  final rawT = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared;
  final t = math.min(1.0, math.max(0.0, rawT));
  final px = a.x + dx * t;
  final py = a.y + dy * t;
  return math.sqrt(
    (point.x - px) * (point.x - px) + (point.y - py) * (point.y - py),
  );
}

bool pointInHelperPolygon(
  HelperPoint point,
  List<HelperPoint> polygon, {
  double tolerance = helperGeometryTolerance,
}) {
  if (polygon.length < 3) {
    throw const FormatException(
        'helper polygon must contain at least three points');
  }
  for (var index = 0; index < polygon.length; index++) {
    final a = polygon[index];
    final b = polygon[(index + 1) % polygon.length];
    if (_distanceToSegment(point, a, b) <= tolerance) return true;
  }

  var inside = false;
  var previous = polygon.last;
  for (final current in polygon) {
    final crossesY = (current.y > point.y) != (previous.y > point.y);
    if (crossesY) {
      final xAtY = (previous.x - current.x) *
              (point.y - current.y) /
              (previous.y - current.y) +
          current.x;
      if (point.x < xAtY) inside = !inside;
    }
    previous = current;
  }
  return inside;
}

bool pointerHitsPointTarget(
  SkeletonData data,
  List<Affine2> worlds,
  String slotName,
  String attachmentName,
  double x,
  double y,
  double hitRadius, {
  String activeSkin = 'default',
}) {
  if (hitRadius < 0.0) {
    throw const FormatException('point helper hit radius must be non-negative');
  }
  final pose = worldPointAttachmentPose(data, worlds, slotName, attachmentName,
      activeSkin: activeSkin);
  return math.sqrt((x - pose.x) * (x - pose.x) + (y - pose.y) * (y - pose.y)) <=
      hitRadius;
}

bool pointerHitsBoundingBoxTarget(
  SkeletonData data,
  List<Affine2> worlds,
  String slotName,
  String attachmentName,
  double x,
  double y, {
  String activeSkin = 'default',
}) {
  final polygon = worldBoundingBoxAttachmentPolygon(
      data, worlds, slotName, attachmentName,
      activeSkin: activeSkin);
  return pointInHelperPolygon(HelperPoint(x: x, y: y), polygon);
}

/// Rest-pose world transform of a bone, FK-composed over the UNMUTATED rest
/// locals (`data.bones[*]`), independent of any animated/constrained pose
/// (transform.nim:357). IK segment lengths and rest joint origins are derived
/// from this rest FK (contract §6), while the chain still anchors at the live
/// pivot at evaluation time. [indexes] maps bone name -> index into
/// `data.bones`; [memo] caches results so shared ancestors are composed once.
Affine2 restWorldFor(
  SkeletonData data,
  int boneIndex,
  Map<String, int> indexes,
  Map<int, Affine2> memo,
) {
  final cached = memo[boneIndex];
  if (cached != null) return cached;
  final bone = data.bones[boneIndex];
  final hasParent = bone.parent.isNotEmpty;
  var parentWorld =
      const Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
  if (hasParent) {
    parentWorld = restWorldFor(data, indexes[bone.parent]!, indexes, memo);
  }
  final world = _worldForBone(parentWorld, bone, hasParent);
  memo[boneIndex] = world;
  return world;
}

_Point _evaluateCubic(_Cubic curve, double u) {
  final inverse = 1.0 - u;
  final w0 = inverse * inverse * inverse;
  final w1 = 3.0 * inverse * inverse * u;
  final w2 = 3.0 * inverse * u * u;
  final w3 = u * u * u;
  return _Point(
    w0 * curve.p0.x + w1 * curve.p1.x + w2 * curve.p2.x + w3 * curve.p3.x,
    w0 * curve.p0.y + w1 * curve.p1.y + w2 * curve.p2.y + w3 * curve.p3.y,
  );
}

_Point _cubicTangent(_Cubic curve, double u) {
  final inverse = 1.0 - u;
  return _Point(
    3.0 * inverse * inverse * (curve.p1.x - curve.p0.x) +
        6.0 * inverse * u * (curve.p2.x - curve.p1.x) +
        3.0 * u * u * (curve.p3.x - curve.p2.x),
    3.0 * inverse * inverse * (curve.p1.y - curve.p0.y) +
        6.0 * inverse * u * (curve.p2.y - curve.p1.y) +
        3.0 * u * u * (curve.p3.y - curve.p2.y),
  );
}

double _tangentAngle(_Point tangent, [double fallbackAngle = 0.0]) {
  if (math.sqrt(tangent.x * tangent.x + tangent.y * tangent.y) <=
      _basisEpsilon) {
    return fallbackAngle;
  }
  return radToDeg(math.atan2(tangent.y, tangent.x));
}

_ArcLengthTable _buildPathArcLengthTable(_Cubic curve) {
  final samples = List<_Point>.filled(
    _pathArcLengthSamples + 1,
    curve.p0,
    growable: false,
  );
  final distances = List<double>.filled(_pathArcLengthSamples + 1, 0.0);
  var previous = curve.p0;
  var total = 0.0;
  for (var index = 1; index <= _pathArcLengthSamples; index++) {
    final current = _evaluateCubic(curve, index / _pathArcLengthSamples);
    samples[index] = current;
    total += distance(previous.x, previous.y, current.x, current.y);
    distances[index] = total;
    previous = current;
  }
  return _ArcLengthTable(samples, distances, total);
}

_PathSample _samplePathByDistance(
    _Cubic curve, _ArcLengthTable table, double distance) {
  final clampedDistance = math.max(0.0, math.min(table.totalLength, distance));
  var sampleIndex = 0;
  while (sampleIndex + 1 < table.distances.length &&
      table.distances[sampleIndex + 1] < clampedDistance) {
    sampleIndex++;
  }
  final nextIndex = math.min(sampleIndex + 1, table.distances.length - 1);
  final startDistance = table.distances[sampleIndex];
  final endDistance = table.distances[nextIndex];
  final segmentMix = endDistance - startDistance <= _basisEpsilon
      ? 0.0
      : (clampedDistance - startDistance) / (endDistance - startDistance);
  final startPoint = table.samples[sampleIndex];
  final endPoint = table.samples[nextIndex];
  final u = (sampleIndex + segmentMix) / _pathArcLengthSamples;
  final segmentTangent =
      _Point(endPoint.x - startPoint.x, endPoint.y - startPoint.y);
  return _PathSample(
    _Point(lerp(startPoint.x, endPoint.x, segmentMix),
        lerp(startPoint.y, endPoint.y, segmentMix)),
    _tangentAngle(_cubicTangent(curve, u), _tangentAngle(segmentTangent)),
    clampedDistance,
  );
}

_Cubic _pathCubicInWorld(PathAttachment attachment, Affine2 targetWorld) {
  return _Cubic(
    _transformPoint(targetWorld, attachment.p0x, attachment.p0y),
    _transformPoint(targetWorld, attachment.p1x, attachment.p1y),
    _transformPoint(targetWorld, attachment.p2x, attachment.p2y),
    _transformPoint(targetWorld, attachment.p3x, attachment.p3y),
  );
}

List<Object> _buildRuntimeConstraintUpdateCache(
  SkeletonData data,
  Map<String, int> byName,
  ActiveSkinMembership activation,
) {
  final parents = List<int>.filled(data.bones.length, -1);
  final seen = <String, int>{};
  for (var index = 0; index < data.bones.length; index++) {
    final bone = data.bones[index];
    if (bone.parent.isNotEmpty) {
      final parentIndex = seen[bone.parent];
      if (parentIndex == null) {
        throw FormatException(
            'bone parent must appear before child: ${bone.name}');
      }
      parents[index] = parentIndex;
    }
    seen[bone.name] = index;
  }

  // Collect BOTH path and ik constraints into ONE ordered list (Nim
  // buildRuntimeConstraintUpdateCache, update_cache.nim:169). Sorting them
  // together by the canonical comparator is load-bearing: for the path+ik
  // subset both share stage rank 0, so sort by `order`, then kind rank
  // (ckIk before ckPath) on a tie, then sourceIndex. A dual-loop over paths
  // then IK would get the tie order wrong (an IK and a path both at order 0
  // must run IK first) and break the golden. Non-runtime constraints still
  // participate in ordering/write-blockers (reads empty; dispatch no-ops).
  // Nim's per-entry `active` flag is intentionally not carried: the dispatched
  // _applyRuntime* functions each re-check `runtimeEvaluable`, so the flag would
  // be redundant.
  final descriptors = <({
    _ConstraintKind kind,
    int order,
    int sourceIndex,
    List<String> writes,
    List<String> reads,
    bool active,
  })>[];
  for (var index = 0; index < data.paths.length; index++) {
    final path = data.paths[index];
    descriptors.add((
      kind: _ConstraintKind.path,
      order: path.order,
      sourceIndex: index,
      writes: <String>[path.bone],
      reads: path.runtimeEvaluable ? <String>[path.target] : const <String>[],
      active: activation.pathConstraints[index],
    ));
  }
  for (var index = 0; index < data.ikConstraints.length; index++) {
    final ik = data.ikConstraints[index];
    descriptors.add((
      kind: _ConstraintKind.ik,
      order: ik.order,
      sourceIndex: index,
      // An IK constraint WRITES its whole bone chain, not a single bone.
      writes: ik.bones,
      reads: ik.runtimeEvaluable ? <String>[ik.target] : const <String>[],
      active: activation.ikConstraints[index],
    ));
  }
  for (var index = 0; index < data.transformConstraints.length; index++) {
    final tc = data.transformConstraints[index];
    descriptors.add((
      kind: _ConstraintKind.transform,
      order: tc.order,
      sourceIndex: index,
      writes: <String>[tc.bone],
      reads: tc.runtimeEvaluable ? <String>[tc.target] : const <String>[],
      active: activation.transformConstraints[index],
    ));
  }
  descriptors.sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    final byKind =
        _constraintKindRank(a.kind).compareTo(_constraintKindRank(b.kind));
    if (byKind != 0) return byKind;
    return a.sourceIndex.compareTo(b.sourceIndex);
  });

  final writeBlockers = List<int>.filled(data.bones.length, -1);
  for (var itemIndex = 0; itemIndex < descriptors.length; itemIndex++) {
    for (final boneName in descriptors[itemIndex].writes) {
      final boneIndex = byName[boneName];
      if (boneIndex == null) {
        throw FormatException('unknown constraint write bone: $boneName');
      }
      writeBlockers[boneIndex] = math.max(writeBlockers[boneIndex], itemIndex);
    }
  }

  final releaseAfter = List<int>.filled(data.bones.length, -1);
  for (var index = 0; index < data.bones.length; index++) {
    releaseAfter[index] = writeBlockers[index];
    if (parents[index] >= 0) {
      releaseAfter[index] =
          math.max(releaseAfter[index], releaseAfter[parents[index]]);
    }
  }

  final result = <Object>[];
  final emitted = List<bool>.filled(data.bones.length, false);
  void emitBoneGroup(List<int> bones) {
    if (bones.isNotEmpty) result.add(_BoneGroupEntry(bones));
  }

  for (var itemIndex = 0; itemIndex < descriptors.length; itemIndex++) {
    final descriptor = descriptors[itemIndex];
    // Emit read dependencies: each read bone's unemitted ancestor lineage is
    // emitted before the constraint. Nim lists only the target as a read; the
    // chain root's EXTERNAL parent is deliberately NOT walked here — it is
    // enforced at runtime inside _applyRuntimeIk (ordering violation), not by
    // extra cache lineage.
    final readGroup = <int>[];
    for (final readName in descriptor.reads) {
      final readIndex = byName[readName];
      if (readIndex == null) {
        throw FormatException('unknown constraint read bone: $readName');
      }
      final lineage = <int>[];
      var cursor = readIndex;
      while (cursor >= 0) {
        lineage.add(cursor);
        cursor = parents[cursor];
      }
      for (final index in lineage.reversed) {
        if (index != readIndex && writeBlockers[index] >= itemIndex) {
          throw FormatException(
            'constraint read bone ancestor cannot be emitted before later write: ${data.bones[readIndex].name}',
          );
        }
        if (!emitted[index]) {
          readGroup.add(index);
          emitted[index] = true;
        }
      }
    }
    emitBoneGroup(readGroup);

    final group = <int>[];
    for (var index = 0; index < data.bones.length; index++) {
      if (!emitted[index] && releaseAfter[index] < itemIndex) {
        group.add(index);
        emitted[index] = true;
      }
    }
    emitBoneGroup(group);
    result.add(_ConstraintEntry(
        descriptor.kind, descriptor.sourceIndex, descriptor.active));
  }

  final finalGroup = <int>[];
  for (var index = 0; index < data.bones.length; index++) {
    if (!emitted[index]) finalGroup.add(index);
  }
  emitBoneGroup(finalGroup);
  return result;
}

/// Testing hook: the kind ('ik'/'path') and per-kind source index of each
/// runtime constraint, in the exact order [computeWorldTransforms] dispatches
/// it. Lets tests pin the canonical ordering — notably that ckIk precedes
/// ckPath at equal `order` — which the committed goldens do not exercise (no
/// golden rig mixes both constraint kinds).
List<({String kind, int sourceIndex})> debugRuntimeConstraintDispatchOrder(
    SkeletonData data) {
  final byName = <String, int>{
    for (var i = 0; i < data.bones.length; i++) data.bones[i].name: i,
  };
  final activation = data.activeSkinMembership();
  return [
    for (final entry
        in _buildRuntimeConstraintUpdateCache(data, byName, activation))
      if (entry is _ConstraintEntry)
        (
          kind: switch (entry.kind) {
            _ConstraintKind.ik => 'ik',
            _ConstraintKind.transform => 'transform',
            _ConstraintKind.path => 'path',
            // Physics never enters this cache (separate stage); unreachable.
            _ConstraintKind.physics => 'physics',
          },
          sourceIndex: entry.sourceIndex,
        ),
  ];
}

void _applyRuntimePathConstraint(
  SkeletonData data,
  PathConstraintData path,
  List<BoneData> locals,
  List<Affine2> worlds,
  List<bool> computed,
  Map<String, int> indexes,
  Map<String, PathAttachment> attachments,
) {
  if (!path.runtimeEvaluable) return;

  final boneIndex = indexes[path.bone]!;
  final targetIndex = indexes[path.target]!;
  if (!computed[targetIndex]) {
    throw FormatException(
        'runtime path target must be emitted before constraint: ${path.name}');
  }

  final parent = data.bones[boneIndex].parent;
  final hasParent = parent.isNotEmpty;
  var parentWorld =
      const Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
  if (hasParent) {
    final parentIndex = indexes[parent]!;
    if (!computed[parentIndex]) {
      throw FormatException(
          'runtime path parent must be emitted before constraint: ${path.name}');
    }
    parentWorld = worlds[parentIndex];
  }

  final translateMix = path.translateMix ?? 1.0;
  final rotateMix = path.rotateMix ?? 0.0;
  final inverse = _inverseAffine(parentWorld);
  if ((translateMix > 0.0 || rotateMix > 0.0) && inverse == null) {
    throw FormatException(
        'runtime path parent transform is singular: ${path.name}');
  }

  final curve = _pathCubicInWorld(attachments[path.path]!, worlds[targetIndex]);
  final table = _buildPathArcLengthTable(curve);
  final sample = _samplePathByDistance(
      curve, table, (path.position ?? 0.0) * table.totalLength);
  var local = locals[boneIndex];

  if (translateMix > 0.0) {
    final sampledLocal =
        _transformPoint(inverse!, sample.position.x, sample.position.y);
    local = _withLocal(
      local,
      x: local.x + (sampledLocal.x - local.x) * translateMix,
      y: local.y + (sampledLocal.y - local.y) * translateMix,
    );
  }

  if (rotateMix > 0.0) {
    final tangentAngleRadians = sample.tangentAngle * math.pi / 180.0;
    final tangentLocal = _transformVector(
      inverse!,
      math.cos(tangentAngleRadians),
      math.sin(tangentAngleRadians),
    );
    final targetRotation = _tangentAngle(tangentLocal, local.rotation);
    local = _withLocal(
      local,
      rotation: local.rotation +
          _shortestAngleDelta(local.rotation, targetRotation) * rotateMix,
    );
  }

  locals[boneIndex] = local;
  worlds[boneIndex] = _worldForBone(parentWorld, local, hasParent);
  computed[boneIndex] = true;
}

/// Evaluate one IK constraint and write its solved rotations back into the
/// chain bones (ports runtime-nim/src/bony/transform.nim:389-524). Geometry per
/// docs/ik-constraint-format-contract.md §3-§6: fixed segment lengths come from
/// the REST pose, but the chain anchors at the CURRENT (live) joint origins
/// (me5.13 current-pivot anchoring, §4) so a moved parent is tracked; the bones'
/// CURRENT world rotations feed the solver and the target's CURRENT world
/// position is the goal. `mix` is applied ONCE inside the solver, so mix=0 is
/// the current-pose identity. Output conventions differ per solver (1-bone and
/// chain return ABSOLUTE world angles; solveTwoBoneIk's child is RELATIVE to its
/// parent) but the absolute-angle write-back below normalizes them.
void _applyRuntimeIk(
  SkeletonData data,
  IkConstraintData ik,
  List<BoneData> locals,
  List<Affine2> worlds,
  List<bool> computed,
  Map<String, int> indexes,
) {
  if (!ik.runtimeEvaluable) return;
  const identity = Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);

  final targetIndex = indexes[ik.target]!;
  if (!computed[targetIndex]) {
    throw FormatException(
        'runtime ik target must be emitted before constraint: ${ik.name}');
  }
  // Raw (non-quantized) IK points — mirrors Nim applyRuntimeIk; routing these
  // through ikPoint()'s quantization would diverge from the committed golden.
  final target = IkPoint(worlds[targetIndex].tx, worlds[targetIndex].ty);

  final chainIndexes = [for (final name in ik.bones) indexes[name]!];

  // Rest-pose geometry: fixed segment lengths and rest joint origins (§6).
  final restMemo = <int, Affine2>{};
  final restOrigins = <IkPoint>[];
  for (final boneIndex in chainIndexes) {
    final rw = restWorldFor(data, boneIndex, indexes, restMemo);
    restOrigins.add(IkPoint(rw.tx, rw.ty));
  }
  final targetRest = restWorldFor(data, targetIndex, indexes, restMemo);
  final targetRestPoint = IkPoint(targetRest.tx, targetRest.ty);

  // Current FK worlds of the chain, captured BEFORE mutating, composed from
  // bone[0]'s external parent forward so the solver sees current rotations.
  final currentWorlds = <Affine2>[];
  for (var i = 0; i < chainIndexes.length; i++) {
    final boneIndex = chainIndexes[i];
    final parent = data.bones[boneIndex].parent;
    final hasParent = parent.isNotEmpty;
    var parentWorld = identity;
    if (hasParent) {
      if (i > 0 && parent == ik.bones[i - 1]) {
        parentWorld = currentWorlds[i - 1];
      } else {
        final parentIndex = indexes[parent]!;
        if (!computed[parentIndex]) {
          throw FormatException(
              'runtime ik bone parent must be emitted before constraint: ${ik.name}');
        }
        parentWorld = worlds[parentIndex];
      }
    }
    currentWorlds
        .add(_worldForBone(parentWorld, data.bones[boneIndex], hasParent));
  }

  // Live (current-pivot) joint origins (§4). Segment lengths stay rest-derived,
  // so the bones remain rigid regardless of the live pose.
  final currentOrigins = <IkPoint>[
    for (final w in currentWorlds) IkPoint(w.tx, w.ty),
  ];

  // ik.mix is already f32-quantized at load (loader.dart), so no re-quantization
  // is needed here; absent mix/bendPositive default to 1.0/true.
  final storedMix = ik.mix ?? 1.0;
  final bendSign = (ik.bendPositive ?? true) ? 1.0 : -1.0;

  // Solved ABSOLUTE world angle (degrees) per constrained bone, chain order.
  final solvedWorldAngles = List<double>.filled(ik.bones.length, 0.0);
  switch (ik.bones.length) {
    case 1:
      {
        final length = ikDistance(restOrigins[0], targetRestPoint);
        final currentRotation = worldRotationDegrees(currentWorlds[0]);
        final solved = solveOneBoneIk(
            currentOrigins[0], length, currentRotation, target,
            mix: storedMix);
        solvedWorldAngles[0] = solved.rotation;
      }
    case 2:
      {
        final parentLength = ikDistance(restOrigins[0], restOrigins[1]);
        final childLength = ikDistance(restOrigins[1], targetRestPoint);
        final parentRotation = worldRotationDegrees(currentWorlds[0]);
        // solveTwoBoneIk's child input is RELATIVE to the parent (current child
        // world rotation minus current parent world rotation).
        final childRotation =
            worldRotationDegrees(currentWorlds[1]) - parentRotation;
        final solved = solveTwoBoneIk(currentOrigins[0], parentLength,
            childLength, parentRotation, childRotation, target,
            bendSign: bendSign, mix: storedMix);
        solvedWorldAngles[0] = solved.parentRotation;
        solvedWorldAngles[1] = solved.parentRotation + solved.childRotation;
      }
    default:
      {
        final n = ik.bones.length;
        final lengths = List<double>.filled(n, 0.0);
        for (var i = 0; i < n - 1; i++) {
          lengths[i] = ikDistance(restOrigins[i], restOrigins[i + 1]);
        }
        lengths[n - 1] = ikDistance(restOrigins[n - 1], targetRestPoint);
        // Live input polyline: live joint origins plus the last bone's live tip
        // (its live origin advanced by the rest last-segment length along its
        // current world direction).
        final points = <IkPoint>[...currentOrigins];
        final lastRadians =
            worldRotationDegrees(currentWorlds[n - 1]) * math.pi / 180.0;
        points.add(IkPoint(
          currentOrigins[n - 1].x + math.cos(lastRadians) * lengths[n - 1],
          currentOrigins[n - 1].y + math.sin(lastRadians) * lengths[n - 1],
        ));
        final solved = solveChainIk(points, lengths, target, mix: storedMix);
        for (var i = 0; i < n; i++) {
          solvedWorldAngles[i] = solved.rotations[i];
        }
      }
  }

  // Sequential FK write-back: convert each solved absolute world angle to the
  // bone's LOCAL rotation against its (already re-worlded) parent, then re-world
  // the bone so it serves as the next chain bone's parent world.
  for (var i = 0; i < chainIndexes.length; i++) {
    final boneIndex = chainIndexes[i];
    final parent = data.bones[boneIndex].parent;
    final hasParent = parent.isNotEmpty;
    var parentWorld = identity;
    if (hasParent) {
      if (i > 0 && parent == ik.bones[i - 1]) {
        parentWorld = worlds[chainIndexes[i - 1]];
      } else {
        parentWorld = worlds[indexes[parent]!];
      }
    }
    // A bone that does not inherit its parent's rotation has world rotation
    // equal to its own local rotation, so no parent angle is subtracted.
    final inheritsRotation = locals[boneIndex].inheritRotation;
    final parentRotation = (hasParent && inheritsRotation)
        ? worldRotationDegrees(parentWorld)
        : 0.0;
    final newLocal = _withLocal(locals[boneIndex],
        rotation: solvedWorldAngles[i] - parentRotation);
    locals[boneIndex] = newLocal;
    worlds[boneIndex] = _worldForBone(parentWorld, newLocal, hasParent);
    computed[boneIndex] = true;
  }
}

// Build a local BoneData from a decomposed pose, carrying the inherit flags and
// transformMode from the template (invariant under a transform constraint).
BoneData _boneFromPose(BoneData base, TransformConstraintPose pose) => BoneData(
      name: base.name,
      parent: base.parent,
      x: pose.x,
      y: pose.y,
      rotation: pose.rotation,
      scaleX: pose.scaleX,
      scaleY: pose.scaleY,
      shearX: pose.shearX,
      shearY: pose.shearY,
      inheritRotation: base.inheritRotation,
      inheritScale: base.inheritScale,
      inheritReflection: base.inheritReflection,
      transformMode: base.transformMode,
      skinRequired: base.skinRequired,
    );

// Port of runtime-nim/src/bony/transform.nim applyRuntimeTransformConstraint.
// Blend the constrained bone's CURRENT world pose toward the target bone's world
// pose per channel, then write the result back as a LOCAL transform (inverting
// _worldForBone) so the trailing FK bone-group re-derivation reproduces it
// instead of overwriting it. The constrained bone is a WRITE target and so is
// not pre-emitted; its current world is FK-composed here.
void _applyRuntimeTransformConstraint(
  SkeletonData data,
  TransformConstraintData tc,
  List<BoneData> locals,
  List<Affine2> worlds,
  List<bool> computed,
  Map<String, int> indexes,
) {
  if (!tc.runtimeEvaluable) return;

  final boneIndex = indexes[tc.bone]!;
  final targetIndex = indexes[tc.target]!;
  if (!computed[targetIndex]) {
    throw FormatException(
        'runtime transform target must be emitted before constraint: ${tc.name}');
  }

  final parent = data.bones[boneIndex].parent;
  final hasParent = parent.isNotEmpty;
  var parentWorld =
      const Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
  if (hasParent) {
    final parentIndex = indexes[parent]!;
    if (!computed[parentIndex]) {
      throw FormatException(
          'runtime transform parent must be emitted before constraint: ${tc.name}');
    }
    parentWorld = worlds[parentIndex];
  }

  final baseLocal = locals[boneIndex];
  final currentWorld = _worldForBone(parentWorld, baseLocal, hasParent);

  final mix = TransformConstraintMix(
    translate: tc.translateMix ?? 1.0,
    rotate: tc.rotateMix ?? 1.0,
    scale: tc.scaleMix ?? 1.0,
    shear: tc.shearMix ?? 1.0,
  );
  final solvedWorld =
      applyTransformConstraint(currentWorld, worlds[targetIndex], mix);

  BoneData newLocal;
  if (!hasParent) {
    newLocal = _boneFromPose(baseLocal, affineToTransformPose(solvedWorld));
  } else {
    final f = _factorParent(parentWorld);
    var inherited = _identity;
    if (baseLocal.inheritRotation) inherited = inherited.mul(f.rotation);
    if (baseLocal.inheritReflection) inherited = inherited.mul(f.reflection);
    if (baseLocal.inheritScale) inherited = inherited.mul(f.scaleShear);
    final inheritedInverse = _inverseLinear(inherited);
    final parentInverse = _inverseAffine(parentWorld);
    if (inheritedInverse == null || parentInverse == null) {
      throw FormatException(
          'runtime transform parent transform is singular: ${tc.name}');
    }
    final solvedLinear =
        _Lin2(solvedWorld.a, solvedWorld.b, solvedWorld.c, solvedWorld.d);
    final localLinear = inheritedInverse.mul(solvedLinear);
    final localOrigin =
        _transformPoint(parentInverse, solvedWorld.tx, solvedWorld.ty);
    newLocal = _boneFromPose(
      baseLocal,
      affineToTransformPose(_affine(localLinear, localOrigin.x, localOrigin.y)),
    );
  }

  locals[boneIndex] = newLocal;
  worlds[boneIndex] = _worldForBone(parentWorld, newLocal, hasParent);
  computed[boneIndex] = true;
}

({List<Affine2> worlds, List<BoneData> locals}) _computeWorldsAndLocals(
  SkeletonData data,
  ActiveSkinMembership activation,
) {
  const rootParent = Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
  const zero = Affine2(a: 0.0, b: 0.0, c: 0.0, d: 0.0, tx: 0.0, ty: 0.0);
  final hasRuntimeConstraints = data.paths.any((p) => p.runtimeEvaluable) ||
      data.ikConstraints.any((c) => c.runtimeEvaluable) ||
      data.transformConstraints.any((t) => t.runtimeEvaluable);
  if (hasRuntimeConstraints) {
    final byName = <String, int>{};
    for (var i = 0; i < data.bones.length; i++) {
      byName[data.bones[i].name] = i;
    }
    final attachments = <String, PathAttachment>{
      for (final attachment in data.pathAttachments)
        attachment.name: attachment,
    };
    final cache = _buildRuntimeConstraintUpdateCache(data, byName, activation);
    final locals = data.bones.map((bone) => bone).toList();
    final result = List<Affine2>.filled(data.bones.length, zero);
    final computed = List<bool>.filled(data.bones.length, false);

    for (final entry in cache) {
      if (entry is _BoneGroupEntry) {
        for (final index in entry.bones) {
          if (!activation.bones[index]) continue;
          final bone = locals[index];
          if (bone.parent.isEmpty) {
            result[index] = _worldForBone(rootParent, bone, false);
          } else {
            final parentIndex = byName[bone.parent]!;
            if (!activation.bones[parentIndex]) continue;
            result[index] = _worldForBone(result[parentIndex], bone, true);
          }
          computed[index] = true;
        }
      } else if (entry is _ConstraintEntry) {
        if (!entry.active) continue;
        switch (entry.kind) {
          case _ConstraintKind.path:
            _applyRuntimePathConstraint(
              data,
              data.paths[entry.sourceIndex],
              locals,
              result,
              computed,
              byName,
              attachments,
            );
          case _ConstraintKind.ik:
            _applyRuntimeIk(
              data,
              data.ikConstraints[entry.sourceIndex],
              locals,
              result,
              computed,
              byName,
            );
          case _ConstraintKind.transform:
            _applyRuntimeTransformConstraint(
              data,
              data.transformConstraints[entry.sourceIndex],
              locals,
              result,
              computed,
              byName,
            );
          case _ConstraintKind.physics:
            // Physics is a separate stateful stage (advancePhysics); it is never
            // emitted into this cache, so this branch is unreachable.
            throw StateError(
                'physics constraints are evaluated in advancePhysics, '
                'not the world-transform pass');
        }
      }
    }
    return (worlds: result, locals: locals);
  }

  final result = List<Affine2>.filled(data.bones.length, zero);
  final locals = data.bones.map((bone) => bone).toList();
  final byName = <String, int>{};
  for (var i = 0; i < data.bones.length; i++) {
    final bone = data.bones[i];
    byName[bone.name] = i;
    if (!activation.bones[i]) continue;
    if (bone.parent.isEmpty) {
      result[i] = _worldForBone(rootParent, bone, false);
    } else {
      final parentIndex = byName[bone.parent]!;
      if (!activation.bones[parentIndex]) continue;
      result[i] = _worldForBone(result[parentIndex], bone, true);
    }
  }
  return (worlds: result, locals: locals);
}

/// Compute the setup-pose world affine transform for every bone.
///
/// Returns one [Affine2] per bone, in the same order as [data.bones].
List<Affine2> computeWorldTransforms(
  SkeletonData data, {
  String activeSkin = 'default',
}) {
  return _computeWorldsAndLocals(data, data.activeSkinMembership(activeSkin))
      .worlds;
}

/// One default [PhysicsConstraintState] per physics constraint (index = source
/// order in `data.physicsConstraints`). Mirrors the Nim `newPhysicsStates`:
/// default accumulator=0, inactive, channels un-initialized for lazy seeding on
/// the first [advancePhysics].
List<PhysicsConstraintState> newPhysicsStates(SkeletonData data) => [
      for (var i = 0; i < data.physicsConstraints.length; i++)
        PhysicsConstraintState(),
    ];

double _physicsChannelValue(BoneData bone, PhysicsChannel channel) {
  switch (channel) {
    case PhysicsChannel.x:
      return bone.x;
    case PhysicsChannel.y:
      return bone.y;
    case PhysicsChannel.rotate:
      return bone.rotation;
    case PhysicsChannel.scaleX:
      return bone.scaleX;
    case PhysicsChannel.shearX:
      return bone.shearX;
  }
}

BoneData _withPhysicsChannel(
    BoneData base, PhysicsChannel channel, double value) {
  // Mirror the Nim withPhysicsChannel, which routes the written channel through
  // localTransform's f32 quantization (the public output boundary). The other
  // channels are already f32 from load/applyPose, so quantizing only the newly
  // written value reproduces the reference's f32 boundary exactly.
  final v = quantizeF32(value);
  return BoneData(
    name: base.name,
    parent: base.parent,
    x: channel == PhysicsChannel.x ? v : base.x,
    y: channel == PhysicsChannel.y ? v : base.y,
    rotation: channel == PhysicsChannel.rotate ? v : base.rotation,
    scaleX: channel == PhysicsChannel.scaleX ? v : base.scaleX,
    scaleY: base.scaleY,
    shearX: channel == PhysicsChannel.shearX ? v : base.shearX,
    shearY: base.shearY,
    inheritRotation: base.inheritRotation,
    inheritScale: base.inheritScale,
    inheritReflection: base.inheritReflection,
    transformMode: base.transformMode,
    skinRequired: base.skinRequired,
  );
}

List<Affine2> _recomputeWorldsFromLocals(
  SkeletonData data,
  List<BoneData> locals,
  Map<String, int> byName,
  ActiveSkinMembership activation,
) {
  const rootParent = Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
  const zero = Affine2(a: 0.0, b: 0.0, c: 0.0, d: 0.0, tx: 0.0, ty: 0.0);
  final result = List<Affine2>.filled(locals.length, zero);
  for (var i = 0; i < locals.length; i++) {
    final bone = locals[i];
    if (!activation.bones[i]) continue;
    if (bone.parent.isEmpty) {
      result[i] = _worldForBone(rootParent, bone, false);
    } else {
      final parentIndex = byName[bone.parent]!;
      if (!activation.bones[parentIndex]) continue;
      result[i] = _worldForBone(result[parentIndex], bone, true);
    }
  }
  return result;
}

/// Stateful advance seam: bony's only time- and state-dependent pose entry
/// point, mirroring the Nim `advancePhysics`. Runs the pure world-transform/
/// constraint pass to produce the animated target pose, then the physics stage
/// (physics runs AFTER that pass, per docs/constraint-total-order.md), then
/// recomposes worlds from the physics-adjusted locals. `states` carries one
/// [PhysicsConstraintState] per constraint across frames (see
/// [newPhysicsStates]); `dt` is the non-negative frame delta and the ONLY time
/// source. With no physics constraints this is exactly [computeWorldTransforms].
///
/// NOTE: physics rigs in this slice carry no ik/transform/path constraints, so
/// the constraint-adjusted locals equal `data.bones` (the posed skeleton). A rig
/// that mixed physics with those constraints would need the adjusted locals
/// threaded here (as the Nim `computeWorldsAndLocals` does); that is out of
/// scope until such a rig exists.
List<Affine2> advancePhysics(
  SkeletonData data,
  List<PhysicsConstraintState> states,
  double dt, {
  String activeSkin = 'default',
}) {
  if (dt < 0.0) {
    throw const FormatException('physics advance dt must be non-negative');
  }
  final activation = data.activeSkinMembership(activeSkin);
  if (data.physicsConstraints.isEmpty) {
    return computeWorldTransforms(data, activeSkin: activeSkin);
  }
  if (states.length != data.physicsConstraints.length) {
    throw FormatException(
        'physics state count (${states.length}) does not match physics '
        'constraint count (${data.physicsConstraints.length})');
  }

  final byName = <String, int>{
    for (var i = 0; i < data.bones.length; i++) data.bones[i].name: i,
  };
  final computed = _computeWorldsAndLocals(data, activation);
  final locals = List<BoneData>.of(computed.locals);

  // Deterministic physics-stage order (docs/constraint-total-order.md): by
  // `order`, then source index. Mirrors buildPhysicsConstraintOrder.
  final order = List<int>.generate(data.physicsConstraints.length, (i) => i)
    ..sort((a, b) {
      final byOrder = data.physicsConstraints[a].order
          .compareTo(data.physicsConstraints[b].order);
      return byOrder != 0 ? byOrder : a.compareTo(b);
    });

  for (final sourceIndex in order) {
    final pc = data.physicsConstraints[sourceIndex];
    final boneIndex = byName[pc.bone]!;
    // Enabled channels in canonical (enum ordinal) order, mirroring Nim set
    // iteration.
    final inputs = <PhysicsChannelInput>[
      for (final channel in PhysicsChannel.values)
        if (pc.channels.contains(channel))
          physicsChannelInput(
              channel, _physicsChannelValue(locals[boneIndex], channel)),
    ];
    final params = physicsParams(
      inertia: pc.inertia ?? 0.0,
      strength: pc.strength ?? 0.0,
      damping: pc.damping ?? 0.0,
      mass: pc.mass ?? 1.0,
      gravity: pc.gravity ?? 0.0,
      wind: pc.wind ?? 0.0,
      mix: pc.physicsMix ?? 1.0,
    );
    final res = updatePhysicsConstraint(
      states[sourceIndex],
      params,
      inputs,
      dt,
      active: activation.physicsConstraints[sourceIndex],
    );
    if (!activation.physicsConstraints[sourceIndex]) continue;
    for (final output in res.outputs) {
      locals[boneIndex] =
          _withPhysicsChannel(locals[boneIndex], output.channel, output.value);
    }
  }

  return _recomputeWorldsFromLocals(data, locals, byName, activation);
}

DrawVertex _vertex(Affine2 world, double lx, double ly, double u, double v) {
  return DrawVertex(
    x: world.a * lx + world.c * ly + world.tx,
    y: world.b * lx + world.d * ly + world.ty,
    u: u,
    v: v,
    r: 1.0,
    g: 1.0,
    b: 1.0,
    a: 1.0,
  );
}

/// Build draw batches for the setup pose, with M7 deformers applied at
/// default parameter values (mirroring the Nim CLI golden-gen pipeline).
///
/// Each slot with a non-empty attachment that resolves to a region becomes one
/// [DrawBatch] with 4 vertices and 6 indices (two triangles).
/// Linear-blend skinning for a mesh attachment's setup vertices, ported fresh to
/// match the Nim `skinMeshVertices` formula and evaluation order
/// (docs/mesh-attachment-contract.md) so both runtimes agree within 1e-4:
///
///   weighted:   worldPos = sum_i weight_i * (boneWorld_i * (bindX_i, bindY_i)),
///               influences accumulated in stored order.
///   unweighted: worldPos = slotBoneWorld * (x, y)  (FK).
///
/// Output x/y/u/v are f32-quantized at the boundary (matching Nim's
/// SkinnedMeshVertex). Meshes carry no per-vertex color in v1, so r=g=b=a=1.
List<DrawVertex> _skinMeshVertices(
  List<Affine2> worlds,
  Map<String, int> boneIndex,
  String slotBone,
  MeshAttachment mesh,
) {
  final out = <DrawVertex>[];
  for (var i = 0; i < mesh.vertices.length; i++) {
    final vertex = mesh.vertices[i];
    final uv = mesh.uvs[i];
    var x = 0.0;
    var y = 0.0;
    if (vertex.weighted) {
      for (final influence in vertex.influences) {
        final w = worlds[boneIndex[influence.bone]!];
        final p = _transformPoint(w, influence.bindX, influence.bindY);
        x += influence.weight * p.x;
        y += influence.weight * p.y;
      }
    } else {
      final p =
          _transformPoint(worlds[boneIndex[slotBone]!], vertex.x, vertex.y);
      x = p.x;
      y = p.y;
    }
    out.add(DrawVertex(
      x: quantizeF32(x),
      y: quantizeF32(y),
      u: quantizeF32(uv.u),
      v: quantizeF32(uv.v),
      r: 1.0,
      g: 1.0,
      b: 1.0,
      a: 1.0,
    ));
  }
  return out;
}

/// Offset skinned mesh [vertices] by a dense per-vertex deform [deltas] list,
/// re-quantizing to f32 at the boundary. Ports `applyDeformDeltas`
/// (runtime-nim/src/bony/mesh/deform.nim:140-153): position is offset, u/v and
/// colour carry through unchanged.
List<DrawVertex> _applyDeformDeltas(
    List<DrawVertex> vertices, List<MeshDelta> deltas) {
  final out = <DrawVertex>[];
  for (var i = 0; i < vertices.length; i++) {
    final v = vertices[i];
    out.add(DrawVertex(
      x: quantizeF32(v.x + deltas[i].x),
      y: quantizeF32(v.y + deltas[i].y),
      u: v.u,
      v: v.v,
      r: v.r,
      g: v.g,
      b: v.b,
      a: v.a,
    ));
  }
  return out;
}

class _DrawBatchBuild {
  const _DrawBatchBuild(
    this.batches,
    this.batchSlotIndex,
    this.batchClipPerTriangle,
  );

  final List<DrawBatch> batches;
  final List<int> batchSlotIndex;
  final List<bool> batchClipPerTriangle;
}

_DrawBatchBuild _buildDrawBatchBuild(
  SkeletonData data,
  List<Affine2> worlds, {
  required String activeSkin,
  required Map<String, SkeletonData> children,
  required bool composeNested,
  required List<String> activeIds,
}) {
  if (worlds.length != data.bones.length) {
    throw FormatException(
        'buildDrawBatches: worlds length ${worlds.length} must match bone count ${data.bones.length}');
  }
  final boneIndex = <String, int>{};
  for (var i = 0; i < data.bones.length; i++) {
    boneIndex[data.bones[i].name] = i;
  }
  final activation = data.activeSkinMembership(activeSkin);
  final regionMap = <String, RegionAttachment>{
    for (final r in data.regions) r.name: r,
  };
  final meshMap = <String, MeshAttachment>{
    for (final m in data.meshAttachments) m.name: m,
  };
  final nestedMap = <String, NestedRigAttachment>{
    if (composeNested)
      for (final n in data.nestedRigAttachments) n.name: n,
  };
  // Transient deform-timeline overrides staged on the posed skeleton by
  // applyPose, keyed by slot name + mesh attachment (the mixer produces one
  // entry per slot/attachment).
  final deformMap = <String, List<MeshDelta>>{
    for (final o in data.deformOverrides)
      '${o.slot}\x00${o.attachment}': o.deltas,
  };

  final baseBatches = <DrawBatch>[];
  final batchSlotIndex = <int>[];
  final batchClipPerTriangle = <bool>[];
  final resolvedSlotAttachment = <String, String>{};
  bool meshInfluencesAreActive(MeshAttachment mesh) {
    for (final vertex in mesh.vertices) {
      for (final influence in vertex.influences) {
        final index = boneIndex[influence.bone];
        if (index == null) {
          throw FormatException(
              'mesh influence references unknown bone: ${influence.bone}');
        }
        if (!activation.bones[index]) return false;
      }
    }
    return true;
  }

  for (var slotIdx = 0; slotIdx < data.slots.length; slotIdx++) {
    final slot = data.slots[slotIdx];
    if (slot.attachment.isEmpty) continue;
    final slotBoneIndex = boneIndex[slot.bone]!;
    if (!activation.bones[slotBoneIndex]) continue;
    final attachment = data.resolveSkinAttachmentTarget(
        activeSkin, slot.name, slot.attachment);
    resolvedSlotAttachment[slot.name] = attachment;
    if (attachment.isEmpty) continue;
    final region = regionMap[attachment];
    if (region == null) {
      // A slot may instead reference a mesh. Attachment names are cross-collection
      // unique (load-validated), so a non-region name resolves to at most one mesh.
      // Skin its vertices (FK for unweighted, linear-blend for weighted) and emit
      // one batch in this slot's draw-order position, with metadata mirroring the
      // region path and the Nim reference (docs/mesh-attachment-contract.md).
      final mesh = meshMap[attachment];
      if (mesh != null) {
        if (!meshInfluencesAreActive(mesh)) continue;
        final world = worlds[slotBoneIndex];
        var meshVerts = _skinMeshVertices(worlds, boneIndex, slot.bone, mesh);
        // Deform-timeline stage: offset skinned vertices by the posed override
        // for this slot/attachment, immediately after skinning and before the
        // M7 deformer and clipping stages (normative order — see
        // docs/deform-timeline-contract.md).
        final deltas = deformMap['${slot.name}\x00${mesh.name}'];
        if (deltas != null) {
          // Nim's applyDeformDeltas raises schemaViolation on a count mismatch
          // rather than silently rendering the undeformed mesh. Match that: keep
          // the absence guard (no override for this slot/mesh), but a present
          // override whose length disagrees with the skinned vertices is a domain
          // error (defensively unreachable — the loader pins vertexCount ==
          // mesh.vertices.length — but a future invariant break must fail loudly
          // in Dart as it does in Nim, not hide as a static draw).
          if (deltas.length != meshVerts.length) {
            throw FormatException(
                'deform delta count must match skinned vertex count: '
                '${deltas.length} vs ${meshVerts.length}');
          }
          meshVerts = _applyDeformDeltas(meshVerts, deltas);
        }
        baseBatches.add(DrawBatch(
          slot: slot.name,
          bone: slot.bone,
          attachment: attachment,
          blendMode: 'normal',
          texturePage: '',
          clipId: '',
          world: world,
          vertices: meshVerts,
          indices: List<int>.from(mesh.triangles),
        ));
        batchSlotIndex.add(slotIdx);
        batchClipPerTriangle.add(true);
        continue;
      }
      final nested = nestedMap[attachment];
      if (nested != null) {
        if (activeIds.contains(nested.skeleton)) {
          throw FormatException(
              'cycleDetected: nested rig composition cycle detected for skeleton: ${nested.skeleton}');
        }
        final child = children[nested.skeleton];
        if (child == null) {
          throw FormatException(
              'unknownRequiredReference: nested rig child skeleton is not resolved: ${nested.skeleton}');
        }
        final childSkin = nested.skin.isNotEmpty ? nested.skin : 'default';
        if (!child.hasSkin(childSkin)) {
          throw FormatException(
              'unknownRequiredReference: nested rig child skin is not resolved: ${nested.skeleton}/$childSkin');
        }
        final childBuild = _buildDrawBatchBuild(
          child,
          computeWorldTransforms(child, activeSkin: childSkin),
          activeSkin: childSkin,
          children: children,
          composeNested: true,
          activeIds: [...activeIds, nested.skeleton],
        );
        final hostWorld = worlds[slotBoneIndex];
        for (var childIndex = 0;
            childIndex < childBuild.batches.length;
            childIndex++) {
          baseBatches
              .add(_composeBatch(hostWorld, childBuild.batches[childIndex]));
          batchSlotIndex.add(slotIdx);
          batchClipPerTriangle.add(childBuild.batchClipPerTriangle[childIndex]);
        }
      }
      continue;
    }

    final world = worlds[slotBoneIndex];
    final hw = region.width * 0.5;
    final hh = region.height * 0.5;
    baseBatches.add(DrawBatch(
      slot: slot.name,
      bone: slot.bone,
      attachment: attachment,
      blendMode: 'normal',
      texturePage: region.texturePage,
      clipId: '',
      world: world,
      vertices: [
        _vertex(world, -hw, -hh, region.u0, region.v0),
        _vertex(world, hw, -hh, region.u1, region.v0),
        _vertex(world, hw, hh, region.u1, region.v1),
        _vertex(world, -hw, hh, region.u0, region.v1),
      ],
      indices: [0, 1, 2, 2, 3, 0],
    ));
    batchSlotIndex.add(slotIdx);
    batchClipPerTriangle.add(false);
  }

  List<DrawBatch> visibleBatches;
  if (data.deformers.isEmpty) {
    visibleBatches = baseBatches;
  } else {
    // Sample each parameter at its default value.
    final samples = data.parameters
        .map((p) => ParameterSample(name: p.name, value: p.defaultValue))
        .toList();
    final efDefs = effectiveDeformers(data.deformers, samples);
    if (efDefs.isEmpty) {
      visibleBatches = baseBatches;
    } else {
      // Apply deformers per batch — each batch uses its own vertices as setup.
      visibleBatches = baseBatches.map((batch) {
        final verts = batch.vertices;
        final positions = verts.map((v) => (x: v.x, y: v.y)).toList();
        final deformed = applyDeformers(positions, efDefs);
        return DrawBatch(
          slot: batch.slot,
          bone: batch.bone,
          attachment: batch.attachment,
          blendMode: batch.blendMode,
          texturePage: batch.texturePage,
          clipId: batch.clipId,
          world: batch.world,
          vertices: [
            for (var i = 0; i < verts.length; i++)
              DrawVertex(
                x: deformed[i].x,
                y: deformed[i].y,
                u: verts[i].u,
                v: verts[i].v,
                r: verts[i].r,
                g: verts[i].g,
                b: verts[i].b,
                a: verts[i].a,
              ),
          ],
          indices: batch.indices,
        );
      }).toList();
    }
  }

  return _DrawBatchBuild(
    _applyClipping(
      data,
      visibleBatches,
      worlds,
      boneIndex,
      resolvedSlotAttachment,
      batchSlotIndex,
      batchClipPerTriangle,
    ),
    batchSlotIndex,
    batchClipPerTriangle,
  );
}

List<DrawBatch> buildDrawBatches(
  SkeletonData data, {
  String activeSkin = 'default',
}) {
  final worlds = computeWorldTransforms(data, activeSkin: activeSkin);
  return _buildDrawBatchBuild(
    data,
    worlds,
    activeSkin: activeSkin,
    children: const {},
    composeNested: false,
    activeIds: const [],
  ).batches;
}

List<DrawBatch> buildNestedDrawBatches(
  SkeletonData data,
  Map<String, SkeletonData> children, {
  String activeSkin = 'default',
  List<Affine2>? worlds,
}) {
  return _buildDrawBatchBuild(
    data,
    worlds ?? computeWorldTransforms(data, activeSkin: activeSkin),
    activeSkin: activeSkin,
    children: children,
    composeNested: true,
    activeIds: const [],
  ).batches;
}

/// Populate `clipId` and geometrically clip covered draw batches, mirroring the
/// Nim reference (`runtime-nim/src/bony/transform.nim`). For each slot whose
/// attachment names a clipping attachment, the covered range is the batch after
/// the clip's own slot through `untilSlot` inclusive (else to the end of draw
/// order). The load-time no-overlap invariant guarantees at most one clip is
/// active per batch. Returns the input unchanged when there are no clips.
List<DrawBatch> _applyClipping(
  SkeletonData data,
  List<DrawBatch> batches,
  List<Affine2> worlds,
  Map<String, int> boneIndex,
  Map<String, String> resolvedSlotAttachment,
  List<int> batchSlotIndex,
  List<bool> batchClipPerTriangle,
) {
  if (data.clippingAttachments.isEmpty) return batches;

  final slotIndexByName = <String, int>{};
  for (var i = 0; i < data.slots.length; i++) {
    slotIndexByName[data.slots[i].name] = i;
  }
  final clipMap = <String, ClippingAttachment>{
    for (final c in data.clippingAttachments) c.name: c,
  };
  final lastSlotIndex = data.slots.length - 1;

  final result = List<DrawBatch>.from(batches);
  for (var slotIdx = 0; slotIdx < data.slots.length; slotIdx++) {
    final slot = data.slots[slotIdx];
    final attachment = resolvedSlotAttachment[slot.name] ?? '';
    if (attachment.isEmpty) continue;
    final clip = clipMap[attachment];
    if (clip == null) continue;
    final ownIndex = slotIdx;
    final endIndex = clip.untilSlot.isNotEmpty
        ? slotIndexByName[clip.untilSlot]!
        : lastSlotIndex;
    // Clip polygon in world space via the clip's own slot's bone world — the
    // same transform the covered region quads are built with.
    final clipWorld = worlds[boneIndex[slot.bone]!];
    final clipPolygon = <ClipPoint>[];
    for (var p = 0; p + 1 < clip.vertices.length; p += 2) {
      final point =
          _transformPoint(clipWorld, clip.vertices[p], clip.vertices[p + 1]);
      clipPolygon.add(ClipPoint(quantizeF32(point.x), quantizeF32(point.y)));
    }
    for (var b = 0; b < result.length; b++) {
      final sourceSlotIndex = batchSlotIndex[b];
      if (sourceSlotIndex <= ownIndex || sourceSlotIndex > endIndex) continue;
      final batch = result[b];
      // Mesh batches clip per-triangle; region batches clip as a convex ring.
      final clipped = batchClipPerTriangle[b]
          ? clipDrawBatchTriangles(batch.vertices, batch.indices, clipPolygon)
          : clipDrawBatchPolygon(batch.vertices, clipPolygon);
      result[b] = DrawBatch(
        slot: batch.slot,
        bone: batch.bone,
        attachment: batch.attachment,
        blendMode: batch.blendMode,
        texturePage: batch.texturePage,
        clipId: clip.name,
        world: batch.world,
        vertices: clipped.changed ? clipped.vertices : batch.vertices,
        indices: clipped.changed ? clipped.indices : batch.indices,
      );
    }
  }
  return result;
}
