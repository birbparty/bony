part of 'loader.dart';

BoneTimelineKind _parseBoneTimelineKind(String prop, String ctx) {
  switch (prop) {
    case 'rotate':
      return BoneTimelineKind.rotate;
    case 'translateX':
      return BoneTimelineKind.translateX;
    case 'translateY':
      return BoneTimelineKind.translateY;
    case 'scaleX':
      return BoneTimelineKind.scaleX;
    case 'scaleY':
      return BoneTimelineKind.scaleY;
    case 'shearX':
      return BoneTimelineKind.shearX;
    case 'shearY':
      return BoneTimelineKind.shearY;
    case 'translate':
      return BoneTimelineKind.translate;
    case 'scale':
      return BoneTimelineKind.scale;
    case 'shear':
      return BoneTimelineKind.shear;
    case 'inherit':
      return BoneTimelineKind.inherit;
    default:
      throw FormatException('$ctx.property unknown: $prop');
  }
}

SlotTimelineKind _parseSlotTimelineKind(String prop, String ctx) {
  switch (prop) {
    case 'attachment':
      return SlotTimelineKind.attachment;
    case 'rgba':
      return SlotTimelineKind.rgba;
    case 'rgb':
      return SlotTimelineKind.rgb;
    case 'alpha':
      return SlotTimelineKind.alpha;
    case 'rgba2':
      return SlotTimelineKind.rgba2;
    case 'sequence':
      return SlotTimelineKind.sequence;
    default:
      throw FormatException('$ctx.property unknown: $prop');
  }
}

TimelineCurve _parseCurve(Map<String, dynamic> j, String ctx) {
  final curveStr = j['curve'] as String?;
  if (curveStr == null || curveStr == 'linear') return TimelineCurve.linear;
  if (curveStr == 'stepped') return TimelineCurve.stepped;
  if (curveStr == 'bezier') {
    final c1x = (j['c1x'] as num?)?.toDouble();
    final c1y = (j['c1y'] as num?)?.toDouble();
    final c2x = (j['c2x'] as num?)?.toDouble();
    final c2y = (j['c2y'] as num?)?.toDouble();
    if (c1x == null) throw FormatException('missing required field: $ctx.c1x');
    if (c1y == null) throw FormatException('missing required field: $ctx.c1y');
    if (c2x == null) throw FormatException('missing required field: $ctx.c2x');
    if (c2y == null) throw FormatException('missing required field: $ctx.c2y');
    final qc1x = quantizeF32(c1x);
    final qc1y = quantizeF32(c1y);
    final qc2x = quantizeF32(c2x);
    final qc2y = quantizeF32(c2y);
    if (!qc1x.isFinite)
      throw FormatException('$ctx.c1x must be a finite f32 value');
    if (!qc1y.isFinite)
      throw FormatException('$ctx.c1y must be a finite f32 value');
    if (!qc2x.isFinite)
      throw FormatException('$ctx.c2x must be a finite f32 value');
    if (!qc2y.isFinite)
      throw FormatException('$ctx.c2y must be a finite f32 value');
    if (qc1x < 0.0 || qc1x > 1.0)
      throw FormatException('$ctx.c1x must be in 0..1');
    if (qc2x < 0.0 || qc2x > 1.0)
      throw FormatException('$ctx.c2x must be in 0..1');
    return TimelineCurve.bezier(qc1x, qc1y, qc2x, qc2y);
  }
  throw FormatException('$ctx.curve unknown: $curveStr');
}

ScalarKeyframe _parseKeyframe(Map<String, dynamic> j, String ctx) {
  final t = (j['t'] as num?)?.toDouble();
  if (t == null) throw FormatException('missing required field: $ctx.t');
  final value = (j['value'] as num?)?.toDouble();
  if (value == null)
    throw FormatException('missing required field: $ctx.value');
  return ScalarKeyframe(time: t, value: value, curve: _parseCurve(j, ctx));
}

Vector2Keyframe _parseVector2Keyframe(Map<String, dynamic> j, String ctx) {
  final t = (j['t'] as num?)?.toDouble();
  if (t == null) throw FormatException('missing required field: $ctx.t');
  final x = (j['x'] as num?)?.toDouble() ?? 0.0;
  final y = (j['y'] as num?)?.toDouble() ?? 0.0;
  // Vector keyframes may carry separate curves for x and y.
  final curveXStr = j['curveX'] as String? ?? j['curve'] as String?;
  final curveYStr = j['curveY'] as String? ?? j['curve'] as String?;
  final jx = curveXStr != null ? {...j, 'curve': curveXStr} : j;
  final jy = curveYStr != null ? {...j, 'curve': curveYStr} : j;
  return Vector2Keyframe(
    time: t,
    x: x,
    y: y,
    curveX: _parseCurve(jx, ctx),
    curveY: _parseCurve(jy, ctx),
  );
}

InheritKeyframe _parseInheritKeyframe(Map<String, dynamic> j, String ctx) {
  final t = (j['t'] as num?)?.toDouble();
  if (t == null) throw FormatException('missing required field: $ctx.t');
  final ir = (j['inheritRotation'] as bool?) ?? true;
  final is_ = (j['inheritScale'] as bool?) ?? true;
  final irf = (j['inheritReflection'] as bool?) ?? true;
  final tm = (j['transformMode'] as String?) ?? 'normal';
  return InheritKeyframe(
    time: t,
    inheritRotation: ir,
    inheritScale: is_,
    inheritReflection: irf,
    transformMode: tm,
  );
}

AttachmentKeyframe _parseAttachmentKeyframe(
    Map<String, dynamic> j, String ctx) {
  final t = (j['t'] as num?)?.toDouble();
  if (t == null) throw FormatException('missing required field: $ctx.t');
  return AttachmentKeyframe(
      time: t, attachment: (j['attachment'] as String?) ?? '');
}

ColorRgba _parseColorRgba(Map<String, dynamic> j, String ctx) {
  return ColorRgba(
    r: (j['r'] as num?)?.toDouble() ?? 1.0,
    g: (j['g'] as num?)?.toDouble() ?? 1.0,
    b: (j['b'] as num?)?.toDouble() ?? 1.0,
    a: (j['a'] as num?)?.toDouble() ?? 1.0,
  );
}

ColorKeyframe _parseColorKeyframe(Map<String, dynamic> j, String ctx) {
  final t = (j['t'] as num?)?.toDouble();
  if (t == null) throw FormatException('missing required field: $ctx.t');
  return ColorKeyframe(
      time: t, color: _parseColorRgba(j, ctx), curve: _parseCurve(j, ctx));
}

Color2Keyframe _parseColor2Keyframe(Map<String, dynamic> j, String ctx) {
  final t = (j['t'] as num?)?.toDouble();
  if (t == null) throw FormatException('missing required field: $ctx.t');
  final light = _parseColorRgba(j, ctx);
  final darkR = (j['dr'] as num?)?.toDouble() ?? 0.0;
  final darkG = (j['dg'] as num?)?.toDouble() ?? 0.0;
  final darkB = (j['db'] as num?)?.toDouble() ?? 0.0;
  return Color2Keyframe(
    time: t,
    color: ColorRgba2(light: light, darkR: darkR, darkG: darkG, darkB: darkB),
    curve: _parseCurve(j, ctx),
  );
}

SequenceMode _parseSequenceMode(String? s) {
  switch (s) {
    case 'once':
      return SequenceMode.once;
    case 'loop':
      return SequenceMode.loop;
    case 'pingpong':
      return SequenceMode.pingpong;
    case 'reverse':
      return SequenceMode.reverse;
    case 'hold':
      return SequenceMode.hold;
    default:
      return SequenceMode.once;
  }
}

SequenceKeyframe _parseSequenceKeyframe(Map<String, dynamic> j, String ctx) {
  final t = (j['t'] as num?)?.toDouble();
  if (t == null) throw FormatException('missing required field: $ctx.t');
  final index = (j['index'] as num?)?.toInt() ?? 0;
  final delay = (j['delay'] as num?)?.toDouble() ?? 0.0;
  final mode = _parseSequenceMode(j['mode'] as String?);
  return SequenceKeyframe(time: t, index: index, delay: delay, mode: mode);
}

bool _hasSkin(List<SkinData> skins, String skinName) {
  if (skins.isEmpty) return skinName == 'default';
  for (final skin in skins) {
    if (skin.name == skinName) return true;
  }
  return false;
}

String _resolveSkinAttachmentTarget(
  List<SkinData> skins,
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

List<AnimationClip> _parseAnimations(
  List<dynamic> anims,
  List<SlotData> slots,
  List<MeshAttachment> meshAttachments,
  List<SkinData> skins,
) {
  final result = <AnimationClip>[];
  final meshesByName = <String, MeshAttachment>{
    for (final m in meshAttachments) m.name: m,
  };
  final seen = <String>{};
  for (var ai = 0; ai < anims.length; ai++) {
    final anim = anims[ai] as Map<String, dynamic>;
    final ctx = 'animations[$ai]';
    final name = _required<String>(anim['name'], '$ctx.name');
    if (!seen.add(name))
      throw FormatException('duplicate animation name: $name');

    var duration = 0.0;
    final boneTimelines = <BoneTimeline>[];
    final btList = anim['boneTimelines'] as List<dynamic>? ?? const [];
    for (var bi = 0; bi < btList.length; bi++) {
      final bt = btList[bi] as Map<String, dynamic>;
      final btCtx = '$ctx.boneTimelines[$bi]';
      final bone = _required<String>(bt['bone'], '$btCtx.bone');
      final prop = _required<String>(bt['property'], '$btCtx.property');
      final kind = _parseBoneTimelineKind(prop, btCtx);
      final kfList =
          _required<List<dynamic>>(bt['keyframes'], '$btCtx.keyframes');
      if (kfList.isEmpty)
        throw FormatException('$btCtx.keyframes must not be empty');

      late BoneTimeline tl;
      switch (kind) {
        case BoneTimelineKind.translate:
        case BoneTimelineKind.scale:
        case BoneTimelineKind.shear:
          final keys = <Vector2Keyframe>[];
          for (var ki = 0; ki < kfList.length; ki++) {
            keys.add(_parseVector2Keyframe(
                kfList[ki] as Map<String, dynamic>, '$btCtx.keyframes[$ki]'));
          }
          _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), btCtx);
          tl = BoneTimeline(bone: bone, kind: kind, vectorKeys: keys);
          if (keys.last.time > duration) duration = keys.last.time;
        case BoneTimelineKind.inherit:
          final keys = <InheritKeyframe>[];
          for (var ki = 0; ki < kfList.length; ki++) {
            keys.add(_parseInheritKeyframe(
                kfList[ki] as Map<String, dynamic>, '$btCtx.keyframes[$ki]'));
          }
          _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), btCtx);
          tl = BoneTimeline(bone: bone, kind: kind, inheritKeys: keys);
          if (keys.last.time > duration) duration = keys.last.time;
        default:
          final keys = <ScalarKeyframe>[];
          for (var ki = 0; ki < kfList.length; ki++) {
            keys.add(_parseKeyframe(
                kfList[ki] as Map<String, dynamic>, '$btCtx.keyframes[$ki]'));
          }
          _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), btCtx);
          tl = BoneTimeline(bone: bone, kind: kind, scalarKeys: keys);
          if (keys.last.time > duration) duration = keys.last.time;
      }
      boneTimelines.add(tl);
    }

    final slotTimelines = <SlotTimeline>[];
    final stList = anim['slotTimelines'] as List<dynamic>? ?? const [];
    for (var si = 0; si < stList.length; si++) {
      final st = stList[si] as Map<String, dynamic>;
      final stCtx = '$ctx.slotTimelines[$si]';
      final slot = _required<String>(st['slot'], '$stCtx.slot');
      final prop = _required<String>(st['property'], '$stCtx.property');
      final kind = _parseSlotTimelineKind(prop, stCtx);
      final kfList =
          _required<List<dynamic>>(st['keyframes'], '$stCtx.keyframes');
      if (kfList.isEmpty)
        throw FormatException('$stCtx.keyframes must not be empty');

      late SlotTimeline tl;
      switch (kind) {
        case SlotTimelineKind.attachment:
          final keys = <AttachmentKeyframe>[];
          for (var ki = 0; ki < kfList.length; ki++) {
            keys.add(_parseAttachmentKeyframe(
                kfList[ki] as Map<String, dynamic>, '$stCtx.keyframes[$ki]'));
          }
          _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), stCtx);
          tl = SlotTimeline(slot: slot, kind: kind, attachmentKeys: keys);
          if (keys.last.time > duration) duration = keys.last.time;
        case SlotTimelineKind.rgba:
        case SlotTimelineKind.rgb:
        case SlotTimelineKind.alpha:
          final keys = <ColorKeyframe>[];
          for (var ki = 0; ki < kfList.length; ki++) {
            keys.add(_parseColorKeyframe(
                kfList[ki] as Map<String, dynamic>, '$stCtx.keyframes[$ki]'));
          }
          _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), stCtx);
          tl = SlotTimeline(slot: slot, kind: kind, colorKeys: keys);
          if (keys.last.time > duration) duration = keys.last.time;
        case SlotTimelineKind.rgba2:
          final keys = <Color2Keyframe>[];
          for (var ki = 0; ki < kfList.length; ki++) {
            keys.add(_parseColor2Keyframe(
                kfList[ki] as Map<String, dynamic>, '$stCtx.keyframes[$ki]'));
          }
          _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), stCtx);
          tl = SlotTimeline(slot: slot, kind: kind, color2Keys: keys);
          if (keys.last.time > duration) duration = keys.last.time;
        case SlotTimelineKind.sequence:
          final keys = <SequenceKeyframe>[];
          for (var ki = 0; ki < kfList.length; ki++) {
            keys.add(_parseSequenceKeyframe(
                kfList[ki] as Map<String, dynamic>, '$stCtx.keyframes[$ki]'));
          }
          _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), stCtx);
          tl = SlotTimeline(slot: slot, kind: kind, sequenceKeys: keys);
          if (keys.last.time > duration) duration = keys.last.time;
      }
      slotTimelines.add(tl);
    }

    DrawOrderTimeline? drawOrderTimeline;
    final drawOrderRaw = anim['drawOrderTimeline'];
    if (drawOrderRaw != null) {
      if (drawOrderRaw is! Map<String, dynamic>) {
        throw FormatException('$ctx.drawOrderTimeline must be an object');
      }
      final dotCtx = '$ctx.drawOrderTimeline';
      final kfList = _required<List<dynamic>>(
          drawOrderRaw['keyframes'], '$dotCtx.keyframes');
      if (kfList.isEmpty) {
        throw FormatException('$dotCtx.keyframes must not be empty');
      }
      final keys = <DrawOrderKeyframe>[];
      for (var ki = 0; ki < kfList.length; ki++) {
        final kf = kfList[ki] as Map<String, dynamic>;
        final kfCtx = '$dotCtx.keyframes[$ki]';
        final t = quantizeF32(_required<num>(kf['t'], '$kfCtx.t').toDouble());
        if (!t.isFinite) {
          throw FormatException('$kfCtx.t must be a finite f32 value');
        }
        if (t < 0.0) {
          throw FormatException('$kfCtx.t must be non-negative');
        }
        final offsetsRaw = kf['offsets'] as List<dynamic>? ?? const [];
        final offsets = <DrawOrderOffset>[];
        for (var oi = 0; oi < offsetsRaw.length; oi++) {
          final o = offsetsRaw[oi] as Map<String, dynamic>;
          final oCtx = '$kfCtx.offsets[$oi]';
          final slot = _required<String>(o['slot'], '$oCtx.slot');
          final offset = _required<num>(o['offset'], '$oCtx.offset').toInt();
          if (offset != 0) {
            offsets.add(DrawOrderOffset(slot: slot, offset: offset));
          }
        }
        keys.add(DrawOrderKeyframe(time: t, offsets: offsets));
      }
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), dotCtx);
      drawOrderTimeline = DrawOrderTimeline(keys: keys);
      _validateDrawOrderTimeline(drawOrderTimeline, slots, dotCtx);
      if (keys.last.time > duration) duration = keys.last.time;
    }

    final deformTimelines = <DeformTimeline>[];
    final dtList = anim['deformTimelines'] as List<dynamic>? ?? const [];
    for (var di = 0; di < dtList.length; di++) {
      final dt = dtList[di] as Map<String, dynamic>;
      final dtCtx = '$ctx.deformTimelines[$di]';
      final skin = _required<String>(dt['skin'], '$dtCtx.skin');
      if (!_hasSkin(skins, skin)) {
        throw FormatException('$dtCtx.skin names unknown skin: $skin');
      }
      final slot = _required<String>(dt['slot'], '$dtCtx.slot');
      final attachment =
          _required<String>(dt['attachment'], '$dtCtx.attachment');
      final vertexCount =
          _required<num>(dt['vertexCount'], '$dtCtx.vertexCount').toInt();
      final resolvedAttachment =
          _resolveSkinAttachmentTarget(skins, skin, slot, attachment);
      if (resolvedAttachment.isEmpty) {
        throw FormatException(
            '$dtCtx does not resolve through skin lookup: $skin/$slot/$attachment');
      }
      final mesh = meshesByName[resolvedAttachment];
      if (mesh == null) {
        throw FormatException(
            '$dtCtx resolved attachment is not a mesh: $resolvedAttachment');
      }
      if (vertexCount != mesh.vertices.length) {
        throw FormatException(
            '$dtCtx.vertexCount does not match mesh: $resolvedAttachment');
      }
      final kfList =
          _required<List<dynamic>>(dt['keyframes'], '$dtCtx.keyframes');
      if (kfList.isEmpty) {
        throw FormatException('$dtCtx.keyframes must not be empty');
      }
      final keys = <DeformKeyframe>[];
      for (var ki = 0; ki < kfList.length; ki++) {
        final kf = kfList[ki] as Map<String, dynamic>;
        final kfCtx = '$dtCtx.keyframes[$ki]';
        final t = quantizeF32(_required<num>(kf['t'], '$kfCtx.t').toDouble());
        final offset = (kf['offset'] as num?)?.toInt() ?? 0;
        if (offset < 0) {
          throw FormatException('$kfCtx.offset must be non-negative');
        }
        final deltasRaw =
            _required<List<dynamic>>(kf['deltas'], '$kfCtx.deltas');
        if (deltasRaw.isEmpty) {
          throw FormatException('$kfCtx must contain at least one delta');
        }
        final deltas = <MeshDelta>[];
        for (final d in deltasRaw) {
          final dm = d as Map<String, dynamic>;
          deltas.add(MeshDelta(
            x: quantizeF32((dm['x'] as num?)?.toDouble() ?? 0.0),
            y: quantizeF32((dm['y'] as num?)?.toDouble() ?? 0.0),
          ));
        }
        if (offset + deltas.length > vertexCount) {
          throw FormatException(
              '$kfCtx deform key range exceeds mesh vertex count');
        }
        keys.add(DeformKeyframe(
          time: t,
          offset: offset,
          deltas: deltas,
          curve: _parseCurve(kf, kfCtx),
        ));
      }
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), dtCtx);
      if (keys.last.time > duration) duration = keys.last.time;
      deformTimelines.add(DeformTimeline(
        skin: skin,
        slot: slot,
        attachment: attachment,
        vertexCount: vertexCount,
        keys: keys,
      ));
    }

    // Event timelines (docs/event-timeline-contract.md). Clip-global, no target,
    // no curve; non-decreasing (not strictly increasing) key times.
    final eventTimelines = <EventTimeline>[];
    final etList = anim['eventTimelines'] as List<dynamic>? ?? const [];
    for (var ei = 0; ei < etList.length; ei++) {
      final et = etList[ei] as Map<String, dynamic>;
      final etCtx = '$ctx.eventTimelines[$ei]';
      final kfList =
          _required<List<dynamic>>(et['keyframes'], '$etCtx.keyframes');
      if (kfList.isEmpty) {
        throw FormatException('$etCtx.keyframes must not be empty');
      }
      final keys = <EventKeyframe>[];
      for (var ki = 0; ki < kfList.length; ki++) {
        final kf = kfList[ki] as Map<String, dynamic>;
        final kfCtx = '$etCtx.keyframes[$ki]';
        final t = quantizeF32(_required<num>(kf['t'], '$kfCtx.t').toDouble());
        if (t < 0.0) {
          throw FormatException('$kfCtx.t must be non-negative');
        }
        final evName = _required<String>(kf['name'], '$kfCtx.name');
        if (evName.isEmpty) {
          throw FormatException('$kfCtx.name must not be empty');
        }
        keys.add(EventKeyframe(
          time: t,
          event: EventData(
            name: evName,
            intValue: (kf['intValue'] as num?)?.toInt() ?? 0,
            floatValue:
                quantizeF32((kf['floatValue'] as num?)?.toDouble() ?? 0.0),
            stringValue: (kf['stringValue'] as String?) ?? '',
            audioPath: (kf['audioPath'] as String?) ?? '',
            volume: quantizeF32((kf['volume'] as num?)?.toDouble() ?? 1.0),
            balance: quantizeF32((kf['balance'] as num?)?.toDouble() ?? 0.0),
          ),
        ));
      }
      _ensureNonDecreasing(keys.map((k) => k.time).toList(), etCtx);
      if (keys.last.time > duration) duration = keys.last.time;
      eventTimelines.add(EventTimeline(keys: keys));
    }

    result.add(AnimationClip(
        name: name,
        duration: duration,
        boneTimelines: boneTimelines,
        slotTimelines: slotTimelines,
        drawOrderTimeline: drawOrderTimeline,
        deformTimelines: deformTimelines,
        eventTimelines: eventTimelines));
  }
  return result;
}
