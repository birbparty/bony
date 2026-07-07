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

  factory TimelineCurve.bezier(
          double c1x, double c1y, double c2x, double c2y) =>
      TimelineCurve._(
          kind: TimelineCurveKind.bezier,
          c1x: c1x,
          c1y: c1y,
          c2x: c2x,
          c2y: c2y);

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
  // Vector (X+Y pair) bone timeline kinds — use BoneTimeline.vectorKeys.
  translate,
  scale,
  shear,
  // Stepped inherit-mode kind — use BoneTimeline.inheritKeys.
  inherit,
}

enum SlotTimelineKind {
  attachment,
  rgba,
  rgb,
  alpha,
  rgba2,
  sequence,
}

enum SequenceMode { once, loop, pingpong, reverse, hold }

class ColorRgba {
  const ColorRgba(
      {required this.r, required this.g, required this.b, required this.a});
  final double r;
  final double g;
  final double b;
  final double a;
}

class ColorRgba2 {
  const ColorRgba2(
      {required this.light,
      required this.darkR,
      required this.darkG,
      required this.darkB});
  final ColorRgba light;
  final double darkR;
  final double darkG;
  final double darkB;
}

class ScalarKeyframe {
  const ScalarKeyframe(
      {required this.time,
      required this.value,
      this.curve = TimelineCurve.linear});
  final double time;
  final double value;
  final TimelineCurve curve;
}

class Vector2Keyframe {
  const Vector2Keyframe({
    required this.time,
    required this.x,
    required this.y,
    this.curveX = TimelineCurve.linear,
    this.curveY = TimelineCurve.linear,
  });
  final double time;
  final double x;
  final double y;
  final TimelineCurve curveX;
  final TimelineCurve curveY;
}

class InheritKeyframe {
  const InheritKeyframe({
    required this.time,
    required this.inheritRotation,
    required this.inheritScale,
    required this.inheritReflection,
    required this.transformMode,
  });
  final double time;
  final bool inheritRotation;
  final bool inheritScale;
  final bool inheritReflection;
  final String transformMode;
}

class AttachmentKeyframe {
  const AttachmentKeyframe({required this.time, required this.attachment});
  final double time;
  final String attachment;
}

class ColorKeyframe {
  const ColorKeyframe(
      {required this.time,
      required this.color,
      this.curve = TimelineCurve.linear});
  final double time;
  final ColorRgba color;
  final TimelineCurve curve;
}

class Color2Keyframe {
  const Color2Keyframe(
      {required this.time,
      required this.color,
      this.curve = TimelineCurve.linear});
  final double time;
  final ColorRgba2 color;
  final TimelineCurve curve;
}

class SequenceKeyframe {
  const SequenceKeyframe({
    required this.time,
    required this.index,
    required this.delay,
    this.mode = SequenceMode.once,
  });
  final double time;
  final int index;
  final double delay;
  final SequenceMode mode;
}

/// A single per-vertex mesh offset (`x`, `y`) for a deform (FFD) timeline.
class MeshDelta {
  const MeshDelta({required this.x, required this.y});
  final double x;
  final double y;
}

/// One keyframe of a deform timeline: a sparse `offset`-anchored run of
/// per-vertex [deltas] at [time], interpolated with [curve]. Mirrors the Nim
/// `DeformKeyframe` record (anim/timelines.nim).
class DeformKeyframe {
  const DeformKeyframe({
    required this.time,
    required this.offset,
    required this.deltas,
    this.curve = TimelineCurve.linear,
  });
  final double time;
  final int offset;
  final List<MeshDelta> deltas;
  final TimelineCurve curve;
}

/// A clip-owned per-vertex mesh-offset (FFD) timeline targeting the mesh
/// attachment named [attachment] on slot [slot] under skin [skin]. See
/// docs/deform-timeline-contract.md. The model keys a mesh by its name, so
/// [attachment] is the mesh name.
class DeformTimeline {
  const DeformTimeline({
    required this.skin,
    required this.slot,
    required this.attachment,
    required this.vertexCount,
    required this.keys,
  });
  final String skin;
  final String slot;
  final String attachment;
  final int vertexCount;
  final List<DeformKeyframe> keys;
}

class BoneTimeline {
  const BoneTimeline({
    required this.bone,
    required this.kind,
    this.scalarKeys = const [],
    this.vectorKeys = const [],
    this.inheritKeys = const [],
  });
  final String bone;
  final BoneTimelineKind kind;
  final List<ScalarKeyframe> scalarKeys;
  final List<Vector2Keyframe> vectorKeys;
  final List<InheritKeyframe> inheritKeys;
}

class SlotTimeline {
  const SlotTimeline({
    required this.slot,
    required this.kind,
    this.attachmentKeys = const [],
    this.colorKeys = const [],
    this.color2Keys = const [],
    this.sequenceKeys = const [],
  });
  final String slot;
  final SlotTimelineKind kind;
  final List<AttachmentKeyframe> attachmentKeys;
  final List<ColorKeyframe> colorKeys;
  final List<Color2Keyframe> color2Keys;
  final List<SequenceKeyframe> sequenceKeys;
}

/// A clip-owned, application-facing event payload. Mirrors Nim `EventData`
/// (runtime-nim/src/bony/anim/timelines.nim:99-106). `audioPath`/`volume`/
/// `balance` are audio metadata carried verbatim — the runtime never decodes or
/// plays audio (docs/event-timeline-contract.md). `volume`/`balance`/`floatValue`
/// are f32-quantized on load but never range-clamped.
class EventData {
  const EventData({
    required this.name,
    this.intValue = 0,
    this.floatValue = 0.0,
    this.stringValue = '',
    this.audioPath = '',
    this.volume = 1.0,
    this.balance = 0.0,
  });
  final String name;
  final int intValue;
  final double floatValue;
  final String stringValue;
  final String audioPath;
  final double volume;
  final double balance;
}

/// A single event keyframe: a [time] and its [event] payload. Mirrors Nim
/// `EventKeyframe` (timelines.nim:108-110). Events are not interpolated, so —
/// unlike bone/slot/deform keyframes — there is no curve.
class EventKeyframe {
  const EventKeyframe({required this.time, required this.event});
  final double time;
  final EventData event;
}

/// A clip-owned, clip-global event timeline: an ordered list of keyframes with
/// no bone/slot/attachment target. Mirrors Nim `EventTimeline`
/// (timelines.nim:112-113). Keyframe times are non-decreasing (equal times
/// allowed), unlike the strictly-increasing bone/slot/deform rule.
class EventTimeline {
  const EventTimeline({required this.keys});
  final List<EventKeyframe> keys;
}

class AnimationClip {
  const AnimationClip({
    required this.name,
    required this.duration,
    required this.boneTimelines,
    this.slotTimelines = const [],
    this.deformTimelines = const [],
    this.eventTimelines = const [],
  });
  final String name;
  final double duration;
  final List<BoneTimeline> boneTimelines;
  final List<SlotTimeline> slotTimelines;
  final List<DeformTimeline> deformTimelines;
  final List<EventTimeline> eventTimelines;
}

/// A deform timeline resolved to a dense per-vertex delta set at a sample time,
/// keyed by its target [slot] + mesh [attachment]. Staged transiently on the
/// posed [SkeletonData] by `applyPose` and consumed by `buildDrawBatches`
/// immediately after skinning; it is never serialized (mirrors the Nim seam).
class DeformOverride {
  const DeformOverride({
    required this.slot,
    required this.attachment,
    required this.deltas,
  });
  final String slot;
  final String attachment;
  final List<MeshDelta> deltas;
}
