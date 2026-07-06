// Bony SkeletonData model: M1 static + M2 world transform + M3 animation types.

import 'physics_constraint.dart' show PhysicsChannel;

export 'physics_constraint.dart' show PhysicsChannel;

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
    this.skinRequired = false,
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
  final bool skinRequired;
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

class PointAttachment {
  const PointAttachment({
    required this.name,
    required this.x,
    required this.y,
    required this.rotation,
  });

  final String name;
  final double x;
  final double y;
  final double rotation;
}

class BoundingBoxAttachment {
  const BoundingBoxAttachment({
    required this.name,
    required this.vertices,
  });

  final String name;

  /// Convex polygon as a flat `[x0, y0, x1, y1, ...]` list in the owning slot's
  /// bone-local space.
  final List<double> vertices;
}

class NestedRigAttachment {
  const NestedRigAttachment({
    required this.name,
    required this.skeleton,
    this.skin = '',
    this.animation = '',
  });

  final String name;
  final String skeleton;
  final String skin;
  final String animation;
}

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

class ClippingAttachment {
  const ClippingAttachment({
    required this.name,
    required this.vertices,
    required this.untilSlot,
  });

  final String name;

  /// Convex polygon as a flat `[x0, y0, x1, y1, ...]` list in the owning slot's
  /// bone-local space.
  final List<double> vertices;

  /// Slot name at which the clip range stops (inclusive); empty clips to the end
  /// of draw order.
  final String untilSlot;
}

/// One bone influence on a weighted mesh vertex: the vertex's bind position in
/// `bone`'s local space and its blend weight. Mirrors the Nim `MeshInfluence`.
class MeshInfluence {
  const MeshInfluence({
    required this.bone,
    required this.bindX,
    required this.bindY,
    required this.weight,
  });

  final String bone;
  final double bindX;
  final double bindY;
  final double weight;
}

/// One mesh vertex: either a flat bone-local position (`x`,`y`, unweighted) or a
/// set of weighted bone `influences`. `weighted` agrees with the owning mesh's
/// `weighted` flag. Mirrors the Nim `MeshVertex`.
class MeshVertex {
  const MeshVertex.unweighted(this.x, this.y)
      : weighted = false,
        influences = const [];

  const MeshVertex.weighted(this.influences)
      : weighted = true,
        x = 0.0,
        y = 0.0;

  final bool weighted;
  final double x;
  final double y;
  final List<MeshInfluence> influences;
}

/// A per-vertex texture coordinate. Mirrors the Nim `MeshUv`.
class MeshUv {
  const MeshUv(this.u, this.v);

  final double u;
  final double v;
}

/// A slot-bound deformable triangle mesh with per-vertex texture coordinates and
/// either flat bone-local positions or per-vertex weighted bone influences
/// (skinning). Mirrors the Nim `MeshAttachment` and the prompt-19 contract.
class MeshAttachment {
  const MeshAttachment({
    required this.name,
    required this.weighted,
    required this.vertices,
    required this.uvs,
    required this.triangles,
  });

  final String name;

  /// Whether vertices carry per-vertex bone influences (skinning) rather than
  /// flat bone-local positions.
  final bool weighted;

  final List<MeshVertex> vertices;

  /// One texture coordinate per vertex (`uvs.length == vertices.length`).
  final List<MeshUv> uvs;

  /// Flat vertex-index triples (`triangles.length` is a multiple of 3).
  final List<int> triangles;
}

class SkinEntryData {
  const SkinEntryData({
    required this.slot,
    required this.attachment,
    required this.target,
  });

  final String slot;
  final String attachment;
  final String target;
}

class SkinData {
  const SkinData({
    required this.name,
    this.entries = const [],
    this.bones = const [],
    this.ikConstraints = const [],
    this.transformConstraints = const [],
    this.pathConstraints = const [],
    this.physicsConstraints = const [],
  });

  final String name;
  final List<SkinEntryData> entries;
  final List<String> bones;
  final List<String> ikConstraints;
  final List<String> transformConstraints;
  final List<String> pathConstraints;
  final List<String> physicsConstraints;
}

class SkeletonData {
  const SkeletonData({
    required this.header,
    required this.bones,
    required this.slots,
    required this.regions,
    required this.paths,
    required this.pathAttachments,
    this.pointAttachments = const [],
    this.boundingBoxAttachments = const [],
    this.nestedRigAttachments = const [],
    this.clippingAttachments = const [],
    this.meshAttachments = const [],
    this.ikConstraints = const [],
    this.transformConstraints = const [],
    this.physicsConstraints = const [],
    this.skins = const [],
    this.animations = const [],
    this.parameters = const [],
    this.deformers = const [],
    this.stateMachines = const [],
    this.deformOverrides = const [],
  });

  final SkeletonHeader header;
  final List<BoneData> bones;
  final List<SlotData> slots;
  final List<RegionAttachment> regions;
  final List<PathConstraintData> paths;
  final List<PathAttachment> pathAttachments;
  final List<PointAttachment> pointAttachments;
  final List<BoundingBoxAttachment> boundingBoxAttachments;
  final List<NestedRigAttachment> nestedRigAttachments;
  final List<ClippingAttachment> clippingAttachments;
  final List<MeshAttachment> meshAttachments;
  final List<IkConstraintData> ikConstraints;
  final List<TransformConstraintData> transformConstraints;
  final List<PhysicsConstraintData> physicsConstraints;
  final List<SkinData> skins;
  final List<AnimationClip> animations;
  final List<ParameterAxis> parameters;
  final List<DeformerRecord> deformers;
  final List<StateMachineData> stateMachines;

  /// Transient per-slot/attachment deform-timeline override staged by
  /// `applyPose` and applied to skinned mesh vertices in `buildDrawBatches`.
  /// Non-serialized: excluded from any `.bony`/`.bnb` round-trip, mirroring the
  /// Nim reference seam (docs/deform-timeline-contract.md).
  final List<DeformOverride> deformOverrides;
}

extension SkinResolution on SkeletonData {
  bool hasSkin(String skinName) {
    if (skins.isEmpty) return skinName == 'default';
    for (final skin in skins) {
      if (skin.name == skinName) return true;
    }
    return false;
  }

  String resolveSkinAttachmentTarget(
    String activeSkin,
    String slotName,
    String attachmentName,
  ) {
    if (attachmentName.isEmpty) return '';
    if (skins.isEmpty) return attachmentName;
    for (final skin in skins) {
      if (skin.name == activeSkin) {
        for (final entry in skin.entries) {
          if (entry.slot == slotName && entry.attachment == attachmentName) {
            return entry.target;
          }
        }
        break;
      }
    }
    if (activeSkin != 'default') {
      for (final skin in skins) {
        if (skin.name == 'default') {
          for (final entry in skin.entries) {
            if (entry.slot == slotName && entry.attachment == attachmentName) {
              return entry.target;
            }
          }
          break;
        }
      }
    }
    return '';
  }
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

enum StateMachineListenerKind {
  stateEnter,
  stateExit,
  transition_,
  pointerDown,
  pointerUp,
  pointerEnter,
  pointerExit,
  pointerMove,
}

enum PointerHelperTargetKind { point, boundingBox }

class StateMachineListener {
  const StateMachineListener({
    required this.name,
    required this.kind,
    this.layer = '',
    this.fromState = '',
    this.toState = '',
    this.slot = '',
    this.targetKind = PointerHelperTargetKind.point,
    this.target = '',
    this.hitRadius,
    this.input = '',
    this.boolValue,
    this.numberValue,
  });
  final String name;
  final StateMachineListenerKind kind;
  final String layer;
  final String fromState;
  final String toState;
  final String slot;
  final PointerHelperTargetKind targetKind;
  final String target;
  final double? hitRadius;
  final String input;
  final bool? boolValue;
  final double? numberValue;
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
