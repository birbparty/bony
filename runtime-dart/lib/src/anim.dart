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

int _findSpan(List<ScalarKeyframe> keys, double time) {
  if (time <= keys.first.time) return 0;
  for (var i = 0; i < keys.length - 1; i++) {
    if (time < keys[i + 1].time) return i;
  }
  return keys.length - 1;
}

double sampleBoneTimeline(BoneTimeline timeline, double time) {
  final keys = timeline.keys;
  final idx = _findSpan(keys, time);
  final cur = keys[idx];
  if (idx == keys.length - 1 || time <= cur.time) return cur.value;
  final next = keys[idx + 1];
  final t = (time - cur.time) / (next.time - cur.time);
  return _mixCurve(cur.curve, cur.value, next.value, t);
}

// --- Mixer types ---

enum MixBlend { first, replace, add }

class _MixedScalar {
  _MixedScalar({required this.bone, required this.kind, required this.value});
  final String bone;
  final BoneTimelineKind kind;
  double value;
}

class MixedPose {
  const MixedPose({required this.scalars});
  final List<({String bone, BoneTimelineKind kind, double value})> scalars;
}

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
      }
    }
  }
  return 0.0;
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
  final key = '$boneName\x00${kind.index}';
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
      // only write if not yet set (already seeded with setup value above)
      break;
    case MixBlend.replace:
      entry.value = entry.value + (sampledValue - entry.value) * weight;
    case MixBlend.add:
      entry.value = entry.value + sampledValue * weight;
  }
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
    final track = _ensureTrack(trackIndex);
    final entry = TrackEntry(clip: clip, loop: loop, mixDuration: mixDuration, blend: blend)
      ..time = -delay;
    track.queue.add(entry);
  }

  void update(double dt) {
    events.clear();
    for (var ti = 0; ti < tracks.length; ti++) {
      final track = tracks[ti];
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

    for (var ti = 0; ti < tracks.length; ti++) {
      final track = tracks[ti];
      final cur = track.current;
      if (cur == null) continue;

      final mixWeight = track._currentMixWeight;
      final prev = track.previous;
      if (prev != null) {
        _applyEntry(scalars, track, prev, 1.0 - mixWeight);
      }
      _applyEntry(scalars, track, cur, mixWeight);
    }

    final result = scalars.values.map((e) => (bone: e.bone, kind: e.kind, value: e.value)).toList()
      ..sort((a, b) {
        final c = a.bone.compareTo(b.bone);
        return c != 0 ? c : a.kind.index.compareTo(b.kind.index);
      });

    return MixedPose(scalars: result);
  }

  void _applyEntry(
    Map<String, _MixedScalar> out,
    AnimationTrack track,
    TrackEntry entry,
    double weight,
  ) {
    final t = _wrappedTime(entry.time, entry.clip.duration, entry.loop);
    final finalWeight = _clamp01(track.alpha * weight);

    for (final tl in entry.clip.boneTimelines) {
      final sampled = sampleBoneTimeline(tl, t);
      _putScalar(out, data, tl.bone, tl.kind, sampled, entry.blend, finalWeight);
    }
  }
}

/// Apply a [MixedPose] to [SkeletonData] and return a new [SkeletonData]
/// with animated bone local transforms.
SkeletonData applyPose(SkeletonData data, MixedPose pose) {
  if (pose.scalars.isEmpty) return data;

  // Build lookup: (boneName, kind) → animated value.
  final lookup = <String, double>{};
  for (final s in pose.scalars) {
    lookup['${s.bone}\x00${s.kind.index}'] = s.value;
  }

  double _get(String bone, BoneTimelineKind kind, double setup) =>
      lookup['$bone\x00${kind.index}'] ?? setup;

  final animBones = data.bones.map((b) {
    return BoneData(
      name: b.name,
      parent: b.parent,
      x: _get(b.name, BoneTimelineKind.translateX, b.x),
      y: _get(b.name, BoneTimelineKind.translateY, b.y),
      rotation: _get(b.name, BoneTimelineKind.rotate, b.rotation),
      scaleX: _get(b.name, BoneTimelineKind.scaleX, b.scaleX),
      scaleY: _get(b.name, BoneTimelineKind.scaleY, b.scaleY),
      shearX: _get(b.name, BoneTimelineKind.shearX, b.shearX),
      shearY: _get(b.name, BoneTimelineKind.shearY, b.shearY),
      inheritRotation: b.inheritRotation,
      inheritScale: b.inheritScale,
      inheritReflection: b.inheritReflection,
      transformMode: b.transformMode,
    );
  }).toList();

  return SkeletonData(
    header: data.header,
    bones: animBones,
    slots: data.slots,
    regions: data.regions,
    paths: data.paths,
    pathAttachments: data.pathAttachments,
    animations: data.animations,
  );
}
