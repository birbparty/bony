part of 'transform.dart';

const double helperGeometryTolerance = 1e-4;

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
