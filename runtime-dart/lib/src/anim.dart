// M3 animation engine: Bézier easing, timeline sampling, multi-track mixer,
// and event dispatch. Ports runtime-nim/src/bony/anim/timelines.nim and
// runtime-nim/src/bony/anim/mixer.nim.

import 'dart:math' as math;
import 'model.dart';

// --- Bézier easing (16-sample table + 2 Newton-Raphson refinements) ---

double _clamp01(double v) => v < 0.0 ? 0.0 : (v > 1.0 ? 1.0 : v);

double _cubicBezier(double c1, double c2, double s) {
  final inv = 1.0 - s;
  return 3.0 * inv * inv * s * c1 + 3.0 * inv * s * s * c2 + s * s * s;
}

double _cubicBezierDerivative(double c1, double c2, double s) {
  final inv = 1.0 - s;
  return 3.0 * inv * inv * c1 + 6.0 * inv * s * (c2 - c1) + 3.0 * s * s * (1.0 - c2);
}

double evaluateCurve(TimelineCurve curve, double t) {
  final input = _clamp01(t);
  switch (curve.kind) {
    case TimelineCurveKind.stepped:
      return 0.0;
    case TimelineCurveKind.linear:
      return input;
    case TimelineCurveKind.bezier:
      if (input == 0.0) return 0.0;
      if (input == 1.0) return 1.0;
      // Build 16-sample table of x values (t → bezierX).
      final table = List<double>.generate(
        16,
        (i) => _cubicBezier(curve.c1x, curve.c2x, i / 15.0),
      );
      // Find the segment containing `input` and interpolate s.
      var s = input;
      for (var i = 0; i < 15; i++) {
        final left = table[i];
        final right = table[i + 1];
        if (left <= input && input <= right && right > left) {
          final segT = (input - left) / (right - left);
          s = (i + segT) / 15.0;
          break;
        }
      }
      // Two Newton-Raphson refinements.
      for (var iter = 0; iter < 2; iter++) {
        final deriv = _cubicBezierDerivative(curve.c1x, curve.c2x, s);
        if (deriv == 0.0 || deriv.isNaN || deriv.isInfinite) break;
        s = _clamp01(s - (_cubicBezier(curve.c1x, curve.c2x, s) - input) / deriv);
      }
      return _cubicBezier(curve.c1y, curve.c2y, s);
  }
}

double _mixCurve(TimelineCurve curve, double a, double b, double t) {
  if (curve.kind == TimelineCurveKind.stepped) return a;
  return a + (b - a) * evaluateCurve(curve, t);
}

// --- Timeline sampling ---

int _findSpanBy<T>(List<T> keys, double Function(T) getTime, double time) {
  if (time <= getTime(keys.first)) return 0;
  for (var i = 0; i < keys.length - 1; i++) {
    if (time < getTime(keys[i + 1])) return i;
  }
  return keys.length - 1;
}

int _findSpan(List<ScalarKeyframe> keys, double time) =>
    _findSpanBy(keys, (k) => k.time, time);

double sampleBoneTimeline(BoneTimeline timeline, double time) {
  final keys = timeline.scalarKeys;
  final idx = _findSpan(keys, time);
  final cur = keys[idx];
  if (idx == keys.length - 1 || time <= cur.time) return cur.value;
  final next = keys[idx + 1];
  final t = (time - cur.time) / (next.time - cur.time);
  return _mixCurve(cur.curve, cur.value, next.value, t);
}

/// Sample a vector (X+Y pair) bone timeline at [time].
(double x, double y) sampleBoneVectorTimeline(BoneTimeline timeline, double time) {
  final keys = timeline.vectorKeys;
  final idx = _findSpanBy(keys, (k) => k.time, time);
  final cur = keys[idx];
  if (idx == keys.length - 1 || time <= cur.time) return (cur.x, cur.y);
  final next = keys[idx + 1];
  final t = (time - cur.time) / (next.time - cur.time);
  return (
    _mixCurve(cur.curveX, cur.x, next.x, t),
    _mixCurve(cur.curveY, cur.y, next.y, t),
  );
}

/// Sample an inherit bone timeline at [time] (stepped — no interpolation).
InheritKeyframe sampleBoneInheritTimeline(BoneTimeline timeline, double time) {
  final keys = timeline.inheritKeys;
  return keys[_findSpanBy(keys, (k) => k.time, time)];
}

/// Sample an attachment slot timeline at [time] (stepped).
String sampleSlotAttachment(SlotTimeline timeline, double time) {
  final keys = timeline.attachmentKeys;
  return keys[_findSpanBy(keys, (k) => k.time, time)].attachment;
}

/// Sample a color slot timeline at [time].
ColorRgba sampleSlotColor(SlotTimeline timeline, double time) {
  final keys = timeline.colorKeys;
  final idx = _findSpanBy(keys, (k) => k.time, time);
  final cur = keys[idx];
  if (idx == keys.length - 1 || time <= cur.time) return cur.color;
  final next = keys[idx + 1];
  final t = (time - cur.time) / (next.time - cur.time);
  return ColorRgba(
    r: _mixCurve(cur.curve, cur.color.r, next.color.r, t),
    g: _mixCurve(cur.curve, cur.color.g, next.color.g, t),
    b: _mixCurve(cur.curve, cur.color.b, next.color.b, t),
    a: _mixCurve(cur.curve, cur.color.a, next.color.a, t),
  );
}

/// Sample a two-color (rgba2) slot timeline at [time].
ColorRgba2 sampleSlotColor2(SlotTimeline timeline, double time) {
  final keys = timeline.color2Keys;
  final idx = _findSpanBy(keys, (k) => k.time, time);
  final cur = keys[idx];
  if (idx == keys.length - 1 || time <= cur.time) return cur.color;
  final next = keys[idx + 1];
  final t = (time - cur.time) / (next.time - cur.time);
  final c = cur.curve;
  return ColorRgba2(
    light: ColorRgba(
      r: _mixCurve(c, cur.color.light.r, next.color.light.r, t),
      g: _mixCurve(c, cur.color.light.g, next.color.light.g, t),
      b: _mixCurve(c, cur.color.light.b, next.color.light.b, t),
      a: _mixCurve(c, cur.color.light.a, next.color.light.a, t),
    ),
    darkR: _mixCurve(c, cur.color.darkR, next.color.darkR, t),
    darkG: _mixCurve(c, cur.color.darkG, next.color.darkG, t),
    darkB: _mixCurve(c, cur.color.darkB, next.color.darkB, t),
  );
}

/// Sample a sequence slot timeline at [time] (stepped).
SequenceKeyframe sampleSlotSequence(SlotTimeline timeline, double time) {
  final keys = timeline.sequenceKeys;
  return keys[_findSpanBy(keys, (k) => k.time, time)];
}

// --- Mixer types ---

enum MixBlend { first, replace, add }

class _MixedScalar {
  _MixedScalar({required this.bone, required this.kind, required this.value});
  final String bone;
  final BoneTimelineKind kind;
  double value;
}

class _MixedVector {
  _MixedVector({required this.bone, required this.kind, required this.x, required this.y});
  final String bone;
  final BoneTimelineKind kind;
  double x;
  double y;
}

class _MixedAttachment {
  _MixedAttachment({required this.slot, required this.attachment});
  final String slot;
  String attachment;
}

class _MixedInherit {
  _MixedInherit({required this.bone, required this.value});
  final String bone;
  InheritKeyframe value;
}

class _MixedColor {
  _MixedColor({required this.slot, required this.kind, required this.color});
  final String slot;
  final SlotTimelineKind kind;
  ColorRgba color;
}

class _MixedColor2 {
  _MixedColor2({required this.slot, required this.color});
  final String slot;
  ColorRgba2 color;
}

class _MixedSequence {
  _MixedSequence({required this.slot, required this.value});
  final String slot;
  SequenceKeyframe value;
}

/// A snapshot of sampled animation channel values, ready to apply to a skeleton.
///
/// Covers all channel types tracked by the Nim reference runtime (mixer.nim):
///
/// - `scalars`     — single-axis bone transforms (rotate, translateX/Y, scaleX/Y, shearX/Y)
/// - `vectors`     — paired-axis bone transforms (translate, scale, shear)
/// - `attachments` — slot attachment changes
/// - `inherits`    — bone inherit-mode keyframes
/// - `colors`      — slot RGBA / RGB / alpha colour channels
/// - `colors2`     — slot two-colour (light RGBA + dark RGB)
/// - `sequences`   — slot sequence frame index
class MixedPose {
  const MixedPose({
    required this.scalars,
    this.vectors = const [],
    this.attachments = const [],
    this.inherits = const [],
    this.colors = const [],
    this.colors2 = const [],
    this.sequences = const [],
  });
  final List<({String bone, BoneTimelineKind kind, double value})> scalars;
  final List<({String bone, BoneTimelineKind kind, double x, double y})> vectors;
  final List<({String slot, String attachment})> attachments;
  final List<({String bone, InheritKeyframe value})> inherits;
  final List<({String slot, SlotTimelineKind kind, ColorRgba color})> colors;
  final List<({String slot, ColorRgba2 color})> colors2;
  final List<({String slot, SequenceKeyframe value})> sequences;
}

String _scalarKey(String bone, BoneTimelineKind kind) => '$bone\x00${kind.index}';
String _vectorKey(String bone, BoneTimelineKind kind) => '$bone\x00v${kind.index}';
String _colorKey(String slot, SlotTimelineKind kind) => '$slot\x00${kind.index}';

double _setupScalar(SkeletonData data, String boneName, BoneTimelineKind kind) {
  for (final bone in data.bones) {
    if (bone.name == boneName) {
      switch (kind) {
        case BoneTimelineKind.rotate:
          return bone.rotation;
        case BoneTimelineKind.translateX:
          return bone.x;
        case BoneTimelineKind.translateY:
          return bone.y;
        case BoneTimelineKind.scaleX:
          return bone.scaleX;
        case BoneTimelineKind.scaleY:
          return bone.scaleY;
        case BoneTimelineKind.shearX:
          return bone.shearX;
        case BoneTimelineKind.shearY:
          return bone.shearY;
        // Vector kinds never appear in scalarKeys.
        case BoneTimelineKind.translate:
        case BoneTimelineKind.scale:
        case BoneTimelineKind.shear:
        case BoneTimelineKind.inherit:
          return 0.0;
      }
    }
  }
  return 0.0;
}

(double x, double y) _setupVector(SkeletonData data, String boneName, BoneTimelineKind kind) {
  for (final bone in data.bones) {
    if (bone.name == boneName) {
      return switch (kind) {
        BoneTimelineKind.translate => (bone.x, bone.y),
        BoneTimelineKind.scale => (bone.scaleX, bone.scaleY),
        BoneTimelineKind.shear => (bone.shearX, bone.shearY),
        _ => (0.0, 0.0),
      };
    }
  }
  return (0.0, 0.0);
}

void _putScalar(
  Map<String, _MixedScalar> out,
  SkeletonData data,
  String boneName,
  BoneTimelineKind kind,
  double sampledValue,
  MixBlend blend,
  double weight,
) {
  final key = _scalarKey(boneName, kind);
  if (!out.containsKey(key)) {
    out[key] = _MixedScalar(
      bone: boneName,
      kind: kind,
      value: _setupScalar(data, boneName, kind),
    );
  }
  final entry = out[key]!;
  switch (blend) {
    case MixBlend.first:
      // Keep the setup-pose seed; first track wins, subsequent tracks don't overwrite.
      break;
    case MixBlend.replace:
      entry.value = entry.value + (sampledValue - entry.value) * weight;
    case MixBlend.add:
      entry.value = entry.value + sampledValue * weight;
  }
}

void _putVector(
  Map<String, _MixedVector> out,
  SkeletonData data,
  String boneName,
  BoneTimelineKind kind,
  double sx,
  double sy,
  MixBlend blend,
  double weight,
) {
  final key = _vectorKey(boneName, kind);
  if (!out.containsKey(key)) {
    final setup = _setupVector(data, boneName, kind);
    out[key] = _MixedVector(bone: boneName, kind: kind, x: setup.$1, y: setup.$2);
  }
  final entry = out[key]!;
  switch (blend) {
    case MixBlend.first:
      break;
    case MixBlend.replace:
      entry.x = entry.x + (sx - entry.x) * weight;
      entry.y = entry.y + (sy - entry.y) * weight;
    case MixBlend.add:
      entry.x = entry.x + sx * weight;
      entry.y = entry.y + sy * weight;
  }
}

void _putAttachment(Map<String, _MixedAttachment> out, String slot, String attachment) {
  out[slot] = _MixedAttachment(slot: slot, attachment: attachment);
}

void _putInherit(Map<String, _MixedInherit> out, String bone, InheritKeyframe value) {
  out[bone] = _MixedInherit(bone: bone, value: value);
}

void _putColor(Map<String, _MixedColor> out, String slot, SlotTimelineKind kind, ColorRgba color) {
  out[_colorKey(slot, kind)] = _MixedColor(slot: slot, kind: kind, color: color);
}

void _putColor2(Map<String, _MixedColor2> out, String slot, ColorRgba2 color) {
  out[slot] = _MixedColor2(slot: slot, color: color);
}

void _putSequence(Map<String, _MixedSequence> out, String slot, SequenceKeyframe value) {
  out[slot] = _MixedSequence(slot: slot, value: value);
}

double _wrappedTime(double time, double duration, bool loop) {
  if (loop && duration > 0.0) return time % duration;
  return math.min(time, duration);
}

class TrackEntry {
  TrackEntry({
    required this.clip,
    this.loop = false,
    this.mixDuration = 0.0,
    this.blend = MixBlend.replace,
  });

  final AnimationClip clip;
  bool loop;
  double mixDuration;
  MixBlend blend;
  double time = 0.0;
  double mixTime = 0.0;
}

class AnimationTrack {
  TrackEntry? current;
  TrackEntry? previous;
  final List<TrackEntry> queue = [];
  double alpha = 1.0;
  double timeScale = 1.0;
  double mixAttachmentThreshold = 0.5;
  double eventThreshold = 0.5;

  double get _currentMixWeight {
    final cur = current;
    final prev = previous;
    if (prev != null && cur != null && cur.mixDuration > 0.0) {
      return _clamp01(cur.mixTime / cur.mixDuration);
    }
    return 1.0;
  }
}

class DispatchedEvent {
  const DispatchedEvent({required this.trackIndex, required this.name, required this.time});
  final int trackIndex;
  final String name;
  final double time;
}

class AnimationState {
  AnimationState(this.data);

  final SkeletonData data;
  final List<AnimationTrack> tracks = [];

  /// Always empty until event timelines are ported (planned post-M3).
  final List<DispatchedEvent> events = [];

  AnimationTrack _ensureTrack(int index) {
    while (tracks.length <= index) {
      tracks.add(AnimationTrack());
    }
    return tracks[index];
  }

  void setAnimation(
    int trackIndex,
    AnimationClip clip, {
    bool loop = false,
    double mixDuration = 0.0,
    MixBlend blend = MixBlend.replace,
  }) {
    if (mixDuration < 0.0) throw ArgumentError.value(mixDuration, 'mixDuration', 'must be >= 0');
    final track = _ensureTrack(trackIndex);
    final entry = TrackEntry(clip: clip, loop: loop, mixDuration: mixDuration, blend: blend);
    if (track.current != null && mixDuration > 0.0) {
      track.previous = track.current;
    } else {
      track.previous = null;
    }
    track.current = entry;
    track.queue.clear();
  }

  void addAnimation(
    int trackIndex,
    AnimationClip clip, {
    bool loop = false,
    double delay = 0.0,
    double mixDuration = 0.0,
    MixBlend blend = MixBlend.replace,
  }) {
    if (delay < 0.0) throw ArgumentError.value(delay, 'delay', 'must be >= 0');
    if (mixDuration < 0.0) throw ArgumentError.value(mixDuration, 'mixDuration', 'must be >= 0');
    final track = _ensureTrack(trackIndex);
    final entry = TrackEntry(clip: clip, loop: loop, mixDuration: mixDuration, blend: blend)
      ..time = -delay;
    track.queue.add(entry);
  }

  void update(double dt) {
    if (dt < 0.0) throw ArgumentError.value(dt, 'dt', 'must be >= 0');
    events.clear();
    for (var ti = 0; ti < tracks.length; ti++) {
      final track = tracks[ti];
      if (track.timeScale < 0.0) throw ArgumentError.value(track.timeScale, 'timeScale', 'must be >= 0');
      final cur = track.current;
      if (cur == null) continue;

      var remaining = dt * track.timeScale;
      while (remaining > 0.0) {
        if (track.queue.isNotEmpty) {
          final next = track.queue.first;
          final switchAt = -next.time; // next.time stored as negative delay
          if (cur.time + remaining >= switchAt) {
            final beforeSwitch = math.max(0.0, switchAt - cur.time);
            _advanceEntry(track, ti, beforeSwitch);
            remaining -= beforeSwitch;
            track.queue.removeAt(0);
            if (next.mixDuration > 0.0) {
              track.previous = track.current;
            } else {
              track.previous = null;
            }
            track.current = next;
            _advanceEntry(track, ti, remaining);
            remaining = 0.0;
            continue;
          }
        }
        _advanceEntry(track, ti, remaining);
        remaining = 0.0;
      }
      // Post-loop: promote a queued entry that is already due (delay elapsed during
      // a prior switch this frame). Mirrors mixer.nim:283-292.
      if (track.queue.isNotEmpty && track.current != null) {
        final next = track.queue.first;
        final switchAt = -next.time;
        if (track.current!.time >= switchAt) {
          track.queue.removeAt(0);
          if (next.mixDuration > 0.0) {
            track.previous = track.current;
          } else {
            track.previous = null;
          }
          track.current = next;
        }
      }
    }
  }

  void _advanceEntry(AnimationTrack track, int ti, double amount) {
    if (amount <= 0.0) return;
    final cur = track.current;
    if (cur == null) return;
    final fromTime = cur.time;
    cur.time += amount;
    final prev = track.previous;
    if (prev != null) {
      prev.time += amount;
      cur.mixTime += amount;
      if (cur.mixDuration <= 0.0 || cur.mixTime >= cur.mixDuration) {
        track.previous = null;
      }
    }
    // Dispatch events for current entry.
    _dispatchEventsForEntry(ti, cur, fromTime, cur.time);
  }

  void _dispatchEventsForEntry(int ti, TrackEntry entry, double fromTime, double toTime) {
    if (toTime < fromTime) return;
    // Bony M3 has no event timelines yet; placeholder for future milestones.
  }

  MixedPose sample() {
    final scalars = <String, _MixedScalar>{};
    final vectors = <String, _MixedVector>{};
    final attachments = <String, _MixedAttachment>{};
    final inherits = <String, _MixedInherit>{};
    final colors = <String, _MixedColor>{};
    final colors2 = <String, _MixedColor2>{};
    final sequences = <String, _MixedSequence>{};

    for (var ti = 0; ti < tracks.length; ti++) {
      final track = tracks[ti];
      final cur = track.current;
      if (cur == null) continue;

      final mixWeight = track._currentMixWeight;
      final prev = track.previous;
      if (prev != null) {
        _applyEntry(scalars, vectors, attachments, inherits, colors, colors2, sequences, track, prev, 1.0 - mixWeight);
      }
      _applyEntry(scalars, vectors, attachments, inherits, colors, colors2, sequences, track, cur, mixWeight);
    }

    final scalarList = scalars.values.map((e) => (bone: e.bone, kind: e.kind, value: e.value)).toList()
      ..sort((a, b) {
        final c = a.bone.compareTo(b.bone);
        return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
      });

    final vectorList = vectors.values.map((e) => (bone: e.bone, kind: e.kind, x: e.x, y: e.y)).toList()
      ..sort((a, b) {
        final c = a.bone.compareTo(b.bone);
        return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
      });

    final attachmentList = attachments.values.map((e) => (slot: e.slot, attachment: e.attachment)).toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));

    final inheritList = inherits.values.map((e) => (bone: e.bone, value: e.value)).toList()
      ..sort((a, b) => a.bone.compareTo(b.bone));

    final colorList = colors.values.map((e) => (slot: e.slot, kind: e.kind, color: e.color)).toList()
      ..sort((a, b) {
        final c = a.slot.compareTo(b.slot);
        return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
      });

    final color2List = colors2.values.map((e) => (slot: e.slot, color: e.color)).toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));

    final sequenceList = sequences.values.map((e) => (slot: e.slot, value: e.value)).toList()
      ..sort((a, b) => a.slot.compareTo(b.slot));

    return MixedPose(
      scalars: scalarList,
      vectors: vectorList,
      attachments: attachmentList,
      inherits: inheritList,
      colors: colorList,
      colors2: color2List,
      sequences: sequenceList,
    );
  }

  void _applyEntry(
    Map<String, _MixedScalar> scalars,
    Map<String, _MixedVector> vectors,
    Map<String, _MixedAttachment> attachments,
    Map<String, _MixedInherit> inherits,
    Map<String, _MixedColor> colors,
    Map<String, _MixedColor2> colors2,
    Map<String, _MixedSequence> sequences,
    AnimationTrack track,
    TrackEntry entry,
    double weight,
  ) {
    final t = _wrappedTime(entry.time, entry.clip.duration, entry.loop);
    final finalWeight = _clamp01(track.alpha * weight);

    for (final tl in entry.clip.boneTimelines) {
      switch (tl.kind) {
        case BoneTimelineKind.translate:
        case BoneTimelineKind.scale:
        case BoneTimelineKind.shear:
          final (sx, sy) = sampleBoneVectorTimeline(tl, t);
          _putVector(vectors, data, tl.bone, tl.kind, sx, sy, entry.blend, finalWeight);
        case BoneTimelineKind.inherit:
          if (finalWeight >= track.mixAttachmentThreshold) {
            _putInherit(inherits, tl.bone, sampleBoneInheritTimeline(tl, t));
          }
        default:
          _putScalar(scalars, data, tl.bone, tl.kind, sampleBoneTimeline(tl, t), entry.blend, finalWeight);
      }
    }

    if (finalWeight >= track.mixAttachmentThreshold) {
      for (final tl in entry.clip.slotTimelines) {
        switch (tl.kind) {
          case SlotTimelineKind.attachment:
            _putAttachment(attachments, tl.slot, sampleSlotAttachment(tl, t));
          case SlotTimelineKind.rgba:
          case SlotTimelineKind.rgb:
          case SlotTimelineKind.alpha:
            _putColor(colors, tl.slot, tl.kind, sampleSlotColor(tl, t));
          case SlotTimelineKind.rgba2:
            _putColor2(colors2, tl.slot, sampleSlotColor2(tl, t));
          case SlotTimelineKind.sequence:
            _putSequence(sequences, tl.slot, sampleSlotSequence(tl, t));
        }
      }
    }
  }
}

/// Apply a [MixedPose] to [SkeletonData] and return a new [SkeletonData]
/// with animated bone local transforms, inherit flags, and slot attachments.
///
/// Applies scalars, vectors, inherits, and attachment channels. Color and
/// sequence channels are carried in the pose but not applied here — those
/// require renderer-level slot state that is not stored on [SlotData].
SkeletonData applyPose(SkeletonData data, MixedPose pose) {
  final hasScalars = pose.scalars.isNotEmpty;
  final hasVectors = pose.vectors.isNotEmpty;
  final hasInherits = pose.inherits.isNotEmpty;
  final hasAttachments = pose.attachments.isNotEmpty;

  if (!hasScalars && !hasVectors && !hasInherits && !hasAttachments) return data;

  // Build lookups.
  final scalarLookup = <String, double>{};
  for (final s in pose.scalars) {
    scalarLookup[_scalarKey(s.bone, s.kind)] = s.value;
  }
  final vectorLookup = <String, ({double x, double y})>{};
  for (final v in pose.vectors) {
    vectorLookup[_vectorKey(v.bone, v.kind)] = (x: v.x, y: v.y);
  }
  final inheritLookup = <String, InheritKeyframe>{};
  for (final ih in pose.inherits) {
    inheritLookup[ih.bone] = ih.value;
  }
  final attachLookup = <String, String>{};
  for (final a in pose.attachments) {
    attachLookup[a.slot] = a.attachment;
  }

  double _getS(String bone, BoneTimelineKind kind, double setup) =>
      scalarLookup[_scalarKey(bone, kind)] ?? setup;

  final animBones = data.bones.map((b) {
    // Vector channels override the paired scalar channels when present.
    final translateVec = vectorLookup[_vectorKey(b.name, BoneTimelineKind.translate)];
    final scaleVec = vectorLookup[_vectorKey(b.name, BoneTimelineKind.scale)];
    final shearVec = vectorLookup[_vectorKey(b.name, BoneTimelineKind.shear)];
    final inh = inheritLookup[b.name];

    return BoneData(
      name: b.name,
      parent: b.parent,
      x: translateVec?.x ?? _getS(b.name, BoneTimelineKind.translateX, b.x),
      y: translateVec?.y ?? _getS(b.name, BoneTimelineKind.translateY, b.y),
      rotation: _getS(b.name, BoneTimelineKind.rotate, b.rotation),
      scaleX: scaleVec?.x ?? _getS(b.name, BoneTimelineKind.scaleX, b.scaleX),
      scaleY: scaleVec?.y ?? _getS(b.name, BoneTimelineKind.scaleY, b.scaleY),
      shearX: shearVec?.x ?? _getS(b.name, BoneTimelineKind.shearX, b.shearX),
      shearY: shearVec?.y ?? _getS(b.name, BoneTimelineKind.shearY, b.shearY),
      inheritRotation: inh?.inheritRotation ?? b.inheritRotation,
      inheritScale: inh?.inheritScale ?? b.inheritScale,
      inheritReflection: inh?.inheritReflection ?? b.inheritReflection,
      transformMode: inh?.transformMode ?? b.transformMode,
    );
  }).toList();

  final animSlots = hasAttachments
      ? data.slots.map((s) {
          final att = attachLookup[s.name];
          return att == null
              ? s
              : SlotData(name: s.name, bone: s.bone, attachment: att);
        }).toList()
      : data.slots;

  return SkeletonData(
    header: data.header,
    bones: animBones,
    slots: animSlots,
    regions: data.regions,
    paths: data.paths,
    pathAttachments: data.pathAttachments,
    // Preserve IK constraints so a posed skeleton still solves IK at pose time
    // (computeWorldTransforms evaluates them). Omitting these silently dropped
    // all IK from any animated pose.
    ikConstraints: data.ikConstraints,
    // Same preservation for transform constraints — omitting them would drop all
    // transform-constraint evaluation from any animated pose (the bony-1c5 bug
    // class). transformConstraints defaults to const [], so a miss compiles.
    transformConstraints: data.transformConstraints,
    animations: data.animations,
    parameters: data.parameters,
    deformers: data.deformers,
    stateMachines: data.stateMachines,
  );
}
