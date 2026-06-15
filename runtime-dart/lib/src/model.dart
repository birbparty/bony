// Bony SkeletonData model: M1 static + M2 world transform + M3 animation types.

class SkeletonHeader {
  const SkeletonHeader({required this.name, required this.version});
  final String name;
  final String version;
}

class BoneData {
  const BoneData({
    required this.name,
    required this.parent,
    required this.x,
    required this.y,
    required this.rotation,
    required this.scaleX,
    required this.scaleY,
    required this.shearX,
    required this.shearY,
    required this.inheritRotation,
    required this.inheritScale,
    required this.inheritReflection,
    required this.transformMode,
  });

  final String name;
  final String parent;
  final double x;
  final double y;
  final double rotation;
  final double scaleX;
  final double scaleY;
  final double shearX;
  final double shearY;
  final bool inheritRotation;
  final bool inheritScale;
  final bool inheritReflection;
  final String transformMode;
}

class SlotData {
  const SlotData({
    required this.name,
    required this.bone,
    required this.attachment,
  });

  final String name;
  final String bone;
  final String attachment;
}

class RegionAttachment {
  const RegionAttachment({
    required this.name,
    required this.width,
    required this.height,
  });

  final String name;
  final double width;
  final double height;
}

class PathConstraintData {
  const PathConstraintData({
    required this.name,
    required this.bone,
    required this.target,
    required this.path,
    required this.order,
  });

  final String name;
  final String bone;
  final String target;
  final String path;
  final int order;
}

class PathAttachment {
  const PathAttachment({
    required this.name,
    required this.p0x,
    required this.p0y,
    required this.p1x,
    required this.p1y,
    required this.p2x,
    required this.p2y,
    required this.p3x,
    required this.p3y,
  });

  final String name;
  final double p0x;
  final double p0y;
  final double p1x;
  final double p1y;
  final double p2x;
  final double p2y;
  final double p3x;
  final double p3y;
}

class SkeletonData {
  const SkeletonData({
    required this.header,
    required this.bones,
    required this.slots,
    required this.regions,
    required this.paths,
    required this.pathAttachments,
    this.animations = const [],
    this.parameters = const [],
    this.deformers = const [],
  });

  final SkeletonHeader header;
  final List<BoneData> bones;
  final List<SlotData> slots;
  final List<RegionAttachment> regions;
  final List<PathConstraintData> paths;
  final List<PathAttachment> pathAttachments;
  final List<AnimationClip> animations;
  final List<ParameterAxis> parameters;
  final List<DeformerRecord> deformers;
}

// --- M7 deformer types ---

class ParameterAxis {
  const ParameterAxis({
    required this.name,
    required this.minValue,
    required this.maxValue,
    this.defaultValue = 0.0,
  });
  final String name;
  final double minValue;
  final double maxValue;
  final double defaultValue;
}

class ParameterSample {
  const ParameterSample({required this.name, required this.value});
  final String name;
  final double value;
}

class DeformerPoint {
  const DeformerPoint({required this.x, required this.y});
  final double x;
  final double y;
}

class WarpLattice {
  const WarpLattice({
    required this.rows,
    required this.cols,
    required this.minX,
    required this.minY,
    required this.maxX,
    required this.maxY,
    required this.controlPoints,
  });
  final int rows;
  final int cols;
  final double minX;
  final double minY;
  final double maxX;
  final double maxY;
  final List<DeformerPoint> controlPoints;
}

class RotationDeformerData {
  const RotationDeformerData({
    required this.pivotX,
    required this.pivotY,
    required this.angleDegrees,
    this.scaleX = 1.0,
    this.scaleY = 1.0,
    this.opacity = 1.0,
  });
  final double pivotX;
  final double pivotY;
  final double angleDegrees;
  final double scaleX;
  final double scaleY;
  final double opacity;
}

enum DeformerKind { warp, rotation }

class DeformerData {
  const DeformerData({
    required this.id,
    this.parent = '',
    required this.order,
    required this.kind,
    this.warp,
    this.rotation,
  });
  final String id;
  final String parent;
  final int order;
  final DeformerKind kind;
  final WarpLattice? warp;
  final RotationDeformerData? rotation;
}

class Keyform {
  const Keyform({required this.coordinates, required this.values});
  final List<ParameterSample> coordinates;
  final List<double> values;
}

class KeyformBlend {
  const KeyformBlend({
    this.axes = const [],
    this.valueCount = 0,
    this.keyforms = const [],
  });
  final List<ParameterAxis> axes;
  final int valueCount;
  final List<Keyform> keyforms;
}

class DeformerRecord {
  const DeformerRecord({required this.deformer, required this.keyformBlend});
  final DeformerData deformer;
  final KeyformBlend keyformBlend;
}

// --- M3 Animation types ---

enum TimelineCurveKind { linear, stepped, bezier }

class TimelineCurve {
  const TimelineCurve._({
    required this.kind,
    this.c1x = 0.0,
    this.c1y = 0.0,
    this.c2x = 1.0,
    this.c2y = 1.0,
  });

  factory TimelineCurve.bezier(double c1x, double c1y, double c2x, double c2y) =>
      TimelineCurve._(kind: TimelineCurveKind.bezier, c1x: c1x, c1y: c1y, c2x: c2x, c2y: c2y);

  static const linear = TimelineCurve._(kind: TimelineCurveKind.linear);
  static const stepped = TimelineCurve._(kind: TimelineCurveKind.stepped);

  final TimelineCurveKind kind;
  final double c1x, c1y, c2x, c2y;
}

enum BoneTimelineKind {
  rotate,
  translateX,
  translateY,
  scaleX,
  scaleY,
  shearX,
  shearY,
}

class ScalarKeyframe {
  const ScalarKeyframe({required this.time, required this.value, this.curve = TimelineCurve.linear});
  final double time;
  final double value;
  final TimelineCurve curve;
}

class BoneTimeline {
  const BoneTimeline({required this.bone, required this.kind, required this.keys});
  final String bone;
  final BoneTimelineKind kind;
  final List<ScalarKeyframe> keys;
}

class AnimationClip {
  const AnimationClip({required this.name, required this.duration, required this.boneTimelines});
  final String name;
  final double duration;
  final List<BoneTimeline> boneTimelines;
}

/// 2D affine world transform matrix (column-major: [a c tx / b d ty / 0 0 1]).
class Affine2 {
  const Affine2({
    required this.a,
    required this.b,
    required this.c,
    required this.d,
    required this.tx,
    required this.ty,
  });

  final double a;
  final double b;
  final double c;
  final double d;
  final double tx;
  final double ty;
}

class DrawVertex {
  const DrawVertex({
    required this.x,
    required this.y,
    required this.u,
    required this.v,
    required this.r,
    required this.g,
    required this.b,
    required this.a,
  });

  final double x;
  final double y;
  final double u;
  final double v;
  final double r;
  final double g;
  final double b;
  final double a;
}

class DrawBatch {
  const DrawBatch({
    required this.slot,
    required this.bone,
    required this.attachment,
    required this.blendMode,
    required this.texturePage,
    required this.clipId,
    required this.world,
    required this.vertices,
    required this.indices,
  });

  final String slot;
  final String bone;
  final String attachment;
  final String blendMode;
  final String texturePage;
  final String clipId;
  final Affine2 world;
  final List<DrawVertex> vertices;
  final List<int> indices;
}
