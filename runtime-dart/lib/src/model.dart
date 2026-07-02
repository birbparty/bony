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
    this.position,
    this.translateMix,
    this.rotateMix,
  });

  final String name;
  final String bone;
  final String target;
  final String path;
  final int order;
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
    this.mix,
    this.bendPositive,
  });

  final String name;

  /// Bone chain the constraint solves, root -> tip. Required (never empty).
  final List<String> bones;
  final String target;
  final int order;

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
    this.translateMix,
    this.rotateMix,
    this.scaleMix,
    this.shearMix,
  });

  final String name;
  final String bone;
  final String target;
  final int order;
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
    this.ikConstraints = const [],
    this.transformConstraints = const [],
    this.animations = const [],
    this.parameters = const [],
    this.deformers = const [],
    this.stateMachines = const [],
  });

  final SkeletonHeader header;
  final List<BoneData> bones;
  final List<SlotData> slots;
  final List<RegionAttachment> regions;
  final List<PathConstraintData> paths;
  final List<PathAttachment> pathAttachments;
  final List<IkConstraintData> ikConstraints;
  final List<TransformConstraintData> transformConstraints;
  final List<AnimationClip> animations;
  final List<ParameterAxis> parameters;
  final List<DeformerRecord> deformers;
  final List<StateMachineData> stateMachines;
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

class AnimationClip {
  const AnimationClip({
    required this.name,
    required this.duration,
    required this.boneTimelines,
    this.slotTimelines = const [],
  });
  final String name;
  final double duration;
  final List<BoneTimeline> boneTimelines;
  final List<SlotTimeline> slotTimelines;
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

// --- M8 state machine types ---

enum StateMachineInputKind { bool_, number, trigger }

class StateMachineInput {
  const StateMachineInput({
    required this.name,
    required this.kind,
    this.defaultBool = false,
    this.defaultNumber = 0.0,
  });
  final String name;
  final StateMachineInputKind kind;
  final bool defaultBool;
  final double defaultNumber;
}

enum StateMachineConditionKind {
  boolEquals,
  numberEquals,
  numberGreater,
  numberGreaterOrEqual,
  numberLess,
  numberLessOrEqual,
  triggerSet,
}

class StateMachineCondition {
  const StateMachineCondition({
    required this.input,
    required this.kind,
    this.boolValue = false,
    this.numberValue = 0.0,
  });
  final String input;
  final StateMachineConditionKind kind;
  final bool boolValue;
  final double numberValue;
}

class StateMachineTransition {
  const StateMachineTransition({
    required this.fromState,
    required this.toState,
    required this.conditions,
  });
  final String fromState;
  final String toState;
  final List<StateMachineCondition> conditions;
}

enum StateMachineListenerKind { stateEnter, stateExit, transition_ }

class StateMachineListener {
  const StateMachineListener({
    required this.name,
    required this.kind,
    required this.layer,
    this.fromState = '',
    this.toState = '',
  });
  final String name;
  final StateMachineListenerKind kind;
  final String layer;
  final String fromState;
  final String toState;
}

enum StateMachineStateKind { clip, blend1d }

class StateMachineBlendClip {
  const StateMachineBlendClip({
    required this.clipName,
    required this.value,
    this.loop = false,
  });
  final String clipName;
  final double value;
  final bool loop;
}

class StateMachineState {
  const StateMachineState({
    required this.name,
    required this.kind,
    this.clipName = '',
    this.loop = false,
    this.blendInput = '',
    this.blendClips = const [],
  });
  final String name;
  final StateMachineStateKind kind;
  final String clipName;
  final bool loop;
  final String blendInput;
  final List<StateMachineBlendClip> blendClips;
}

class StateMachineLayer {
  const StateMachineLayer({
    required this.name,
    required this.states,
    required this.initialState,
    this.transitions = const [],
  });
  final String name;
  final List<StateMachineState> states;
  final String initialState;
  final List<StateMachineTransition> transitions;
}

class StateMachineData {
  const StateMachineData({
    required this.name,
    required this.layers,
    this.inputs = const [],
    this.listeners = const [],
  });
  final String name;
  final List<StateMachineLayer> layers;
  final List<StateMachineInput> inputs;
  final List<StateMachineListener> listeners;
}
