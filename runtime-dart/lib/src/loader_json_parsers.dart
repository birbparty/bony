part of 'loader.dart';

// Throw FormatException with a clear message if the value is null or the
// wrong type. This is intentionally strict so callers get a FormatException
// (not a TypeError) on schema violations.
T _required<T>(dynamic value, String field) {
  if (value == null) throw FormatException('missing required field: $field');
  if (value is! T) {
    throw FormatException(
      'field $field: expected ${T.toString()}, got ${value.runtimeType}',
    );
  }
  return value;
}

List<T> _parseList<T>(
  Map<String, dynamic> root,
  String key,
  T Function(Map<String, dynamic> item, int index) parse,
) {
  final raw = root[key];
  if (raw == null) return <T>[];
  final list = _required<List<dynamic>>(raw, key);
  return [
    for (var i = 0; i < list.length; i++)
      parse(_required<Map<String, dynamic>>(list[i], '$key[$i]'), i),
  ];
}

BoneData _parseBone(Map<String, dynamic> j) {
  double field(String key, double defaultValue) {
    final raw = j[key];
    if (raw == null) return quantizeF32(defaultValue);
    if (raw is! num) {
      throw FormatException(
        'field bone.$key: expected num, got ${raw.runtimeType}',
      );
    }
    final value = quantizeF32(raw.toDouble());
    if (!value.isFinite) {
      throw FormatException('bone.$key must be a finite f32 value');
    }
    return value;
  }

  return BoneData(
    name: _required<String>(j['name'], 'bone.name'),
    parent: (j['parent'] as String?) ?? '',
    x: field('x', 0.0),
    y: field('y', 0.0),
    rotation: field('rotation', 0.0),
    scaleX: field('scaleX', 1.0),
    scaleY: field('scaleY', 1.0),
    shearX: field('shearX', 0.0),
    shearY: field('shearY', 0.0),
    inheritRotation: (j['inheritRotation'] as bool?) ?? true,
    inheritScale: (j['inheritScale'] as bool?) ?? true,
    inheritReflection: (j['inheritReflection'] as bool?) ?? true,
    transformMode: (j['transformMode'] as String?) ?? 'normal',
    skinRequired: (j['skinRequired'] as bool?) ?? false,
  );
}

SlotData _parseSlot(Map<String, dynamic> j) {
  return SlotData(
    name: _required<String>(j['name'], 'slot.name'),
    bone: _required<String>(j['bone'], 'slot.bone'),
    attachment: (j['attachment'] as String?) ?? '',
  );
}

RegionAttachment _parseRegion(Map<String, dynamic> j) {
  double field(String key, double defaultValue) {
    final raw = j[key];
    if (raw == null) return quantizeF32(defaultValue);
    if (raw is! num) {
      throw FormatException(
        'field region.$key: expected num, got ${raw.runtimeType}',
      );
    }
    return quantizeF32(raw.toDouble());
  }

  return RegionAttachment(
    name: _required<String>(j['name'], 'region.name'),
    width: quantizeF32(_required<num>(j['width'], 'region.width').toDouble()),
    height:
        quantizeF32(_required<num>(j['height'], 'region.height').toDouble()),
    texturePage: (j['texturePage'] as String?) ?? '',
    u0: field('u0', 0.0),
    v0: field('v0', 0.0),
    u1: field('u1', 1.0),
    v1: field('v1', 1.0),
    alphaMode: (j['alphaMode'] as String?) ?? 'straight',
  );
}

PointAttachment _parsePointAttachment(Map<String, dynamic> j) {
  return PointAttachment(
    name: _required<String>(j['name'], 'pointAttachment.name'),
    x: quantizeF32(_required<num>(j['x'], 'pointAttachment.x').toDouble()),
    y: quantizeF32(_required<num>(j['y'], 'pointAttachment.y').toDouble()),
    rotation: quantizeF32(
        _required<num>(j['rotation'], 'pointAttachment.rotation').toDouble()),
  );
}

BoundingBoxAttachment _parseBoundingBoxAttachment(Map<String, dynamic> j) {
  final verticesRaw =
      _required<List<dynamic>>(j['vertices'], 'boundingBoxAttachment.vertices');
  return BoundingBoxAttachment(
    name: _required<String>(j['name'], 'boundingBoxAttachment.name'),
    vertices:
        verticesRaw.map((v) => quantizeF32((v as num).toDouble())).toList(),
  );
}

NestedRigAttachment _parseNestedRigAttachment(Map<String, dynamic> j) {
  return NestedRigAttachment(
    name: _required<String>(j['name'], 'nestedRigAttachment.name'),
    skeleton: _required<String>(j['skeleton'], 'nestedRigAttachment.skeleton'),
    skin: (j['skin'] as String?) ?? '',
    animation: (j['animation'] as String?) ?? '',
  );
}

ClippingAttachment _parseClippingAttachment(Map<String, dynamic> j) {
  final verticesRaw =
      _required<List<dynamic>>(j['vertices'], 'clippingAttachment.vertices');
  return ClippingAttachment(
    name: _required<String>(j['name'], 'clippingAttachment.name'),
    // Quantize to f32 at load, matching the Nim clipAttachmentData constructor
    // (runtime-nim/src/bony/model.nim) and the .bnb path (which reads f32) so the
    // JSON and binary loaders agree bit-for-bit.
    vertices:
        verticesRaw.map((v) => quantizeF32((v as num).toDouble())).toList(),
    untilSlot: (j['untilSlot'] as String?) ?? '',
  );
}

MeshAttachment _parseMeshAttachment(Map<String, dynamic> j) {
  final weighted = (j['weighted'] as bool?) ?? false;
  final verticesRaw =
      _required<List<dynamic>>(j['vertices'], 'meshAttachment.vertices');
  final vertices = verticesRaw.map((raw) {
    final v = raw as Map<String, dynamic>;
    // Quantize each numeric to f32 at load, matching the Nim mesh constructors
    // (meshInfluence / unweightedMeshVertex) and the .bnb path (which reads f32),
    // so the JSON and binary loaders agree bit-for-bit.
    if (v.containsKey('influences')) {
      final influencesRaw = _required<List<dynamic>>(
          v['influences'], 'meshAttachment.vertex.influences');
      return MeshVertex.weighted(influencesRaw.map((iraw) {
        final i = iraw as Map<String, dynamic>;
        return MeshInfluence(
          bone: _required<String>(i['bone'], 'meshAttachment.influence.bone'),
          bindX: quantizeF32(
              _required<num>(i['bindX'], 'meshAttachment.influence.bindX')
                  .toDouble()),
          bindY: quantizeF32(
              _required<num>(i['bindY'], 'meshAttachment.influence.bindY')
                  .toDouble()),
          weight: quantizeF32(
              _required<num>(i['weight'], 'meshAttachment.influence.weight')
                  .toDouble()),
        );
      }).toList());
    }
    return MeshVertex.unweighted(
      quantizeF32(_required<num>(v['x'], 'meshAttachment.vertex.x').toDouble()),
      quantizeF32(_required<num>(v['y'], 'meshAttachment.vertex.y').toDouble()),
    );
  }).toList();

  // uvs are a flat [u0, v0, u1, v1, ...] list; pair them into MeshUv. An odd
  // length is malformed (a dropped coordinate) — reject it explicitly rather
  // than silently truncating and surfacing a confusing count mismatch later.
  final uvsRaw = _required<List<dynamic>>(j['uvs'], 'meshAttachment.uvs');
  if (uvsRaw.length.isOdd) {
    throw const FormatException('meshAttachment.uvs must have even length');
  }
  final uvs = <MeshUv>[];
  for (var i = 0; i + 1 < uvsRaw.length; i += 2) {
    uvs.add(MeshUv(
      quantizeF32((uvsRaw[i] as num).toDouble()),
      quantizeF32((uvsRaw[i + 1] as num).toDouble()),
    ));
  }

  final trianglesRaw =
      _required<List<dynamic>>(j['triangles'], 'meshAttachment.triangles');
  return MeshAttachment(
    name: _required<String>(j['name'], 'meshAttachment.name'),
    weighted: weighted,
    vertices: vertices,
    uvs: uvs,
    triangles: trianglesRaw.map((t) => (t as num).toInt()).toList(),
  );
}

SkinData _parseSkin(Map<String, dynamic> j, int index) {
  final ctx = 'skins[$index]';
  List<String> stringList(String key) =>
      ((j[key] as List<dynamic>?) ?? const [])
          .map((v) => _required<String>(v, '$ctx.$key[]'))
          .toList();
  final entriesRaw = j['entries'] as List<dynamic>? ?? const [];
  final entries = <SkinEntryData>[];
  for (var ei = 0; ei < entriesRaw.length; ei++) {
    final entry = entriesRaw[ei] as Map<String, dynamic>;
    final ectx = '$ctx.entries[$ei]';
    entries.add(SkinEntryData(
      slot: _required<String>(entry['slot'], '$ectx.slot'),
      attachment: _required<String>(entry['attachment'], '$ectx.attachment'),
      target: _required<String>(entry['target'], '$ectx.target'),
    ));
  }
  return SkinData(
    name: _required<String>(j['name'], '$ctx.name'),
    entries: entries,
    bones: stringList('bones'),
    ikConstraints: stringList('ikConstraints'),
    transformConstraints: stringList('transformConstraints'),
    pathConstraints: stringList('pathConstraints'),
    physicsConstraints: stringList('physicsConstraints'),
  );
}

PathConstraintData _parsePath(Map<String, dynamic> j) {
  return PathConstraintData(
    name: _required<String>(j['name'], 'path.name'),
    bone: _required<String>(j['bone'], 'path.bone'),
    target: _required<String>(j['target'], 'path.target'),
    path: _required<String>(j['path'], 'path.path'),
    // JSON doesn't distinguish int from double; toInt() handles "order": 0.0.
    order: (j['order'] as num?)?.toInt() ?? 0,
    skinRequired: (j['skinRequired'] as bool?) ?? false,
    position: (j['position'] as num?)?.toDouble(),
    translateMix: (j['translateMix'] as num?)?.toDouble(),
    rotateMix: (j['rotateMix'] as num?)?.toDouble(),
  );
}

IkConstraintData _parseIk(Map<String, dynamic> j) {
  final bonesRaw = j['bones'];
  if (bonesRaw is! List<dynamic>) {
    throw const FormatException('missing required field: ikConstraint.bones');
  }
  // mix is an f32 on the wire; quantize the JSON f64 so the JSON and .bnb load
  // paths agree bit-for-bit (matches runtime-nim's ikConstraintData ctor, which
  // stores quantizeF32(mix)). Range validation happens in _validate.
  final mixRaw = (j['mix'] as num?)?.toDouble();
  return IkConstraintData(
    name: _required<String>(j['name'], 'ikConstraint.name'),
    bones: bonesRaw
        .map((b) => _required<String>(b, 'ikConstraint.bones[]'))
        .toList(),
    target: _required<String>(j['target'], 'ikConstraint.target'),
    // JSON doesn't distinguish int from double; toInt() handles "order": 0.0.
    order: (j['order'] as num?)?.toInt() ?? 0,
    skinRequired: (j['skinRequired'] as bool?) ?? false,
    // null preserves "absent" (mix defaults to 1.0, bendPositive to true).
    mix: mixRaw == null ? null : quantizeF32(mixRaw),
    bendPositive: j['bendPositive'] as bool?,
  );
}

TransformConstraintData _parseTransform(Map<String, dynamic> j) {
  // Each mix is an f32 on the wire; quantize the JSON f64 so the JSON and .bnb
  // load paths agree bit-for-bit (matches runtime-nim's transformConstraintData
  // ctor). null preserves "absent" (mix defaults to 1.0). Range validation
  // happens in _validate.
  double? mixOf(String key) {
    final raw = (j[key] as num?)?.toDouble();
    return raw == null ? null : quantizeF32(raw);
  }

  return TransformConstraintData(
    name: _required<String>(j['name'], 'transformConstraint.name'),
    bone: _required<String>(j['bone'], 'transformConstraint.bone'),
    target: _required<String>(j['target'], 'transformConstraint.target'),
    order: (j['order'] as num?)?.toInt() ?? 0,
    skinRequired: (j['skinRequired'] as bool?) ?? false,
    translateMix: mixOf('translateMix'),
    rotateMix: mixOf('rotateMix'),
    scaleMix: mixOf('scaleMix'),
    shearMix: mixOf('shearMix'),
  );
}

PhysicsConstraintData _parsePhysics(Map<String, dynamic> j) {
  // Each param is an f32 on the wire; quantize the JSON f64 so the JSON and .bnb
  // load paths agree bit-for-bit (matches runtime-nim's physicsConstraintData
  // ctor). null preserves "absent" (integrator applies mass=1.0/physicsMix=1.0/
  // rest 0.0 defaults). Range validation happens in _validate.
  double? paramOf(String key) {
    final raw = (j[key] as num?)?.toDouble();
    return raw == null ? null : quantizeF32(raw);
  }

  final rawChannels = j['channels'];
  if (rawChannels == null) {
    throw const FormatException(
        'missing required field: physicsConstraint.channels');
  }
  final channels = physicsChannelsFromMask((rawChannels as num).toInt());

  return PhysicsConstraintData(
    name: _required<String>(j['name'], 'physicsConstraint.name'),
    bone: _required<String>(j['bone'], 'physicsConstraint.bone'),
    channels: channels,
    order: (j['order'] as num?)?.toInt() ?? 0,
    skinRequired: (j['skinRequired'] as bool?) ?? false,
    inertia: paramOf('inertia'),
    strength: paramOf('strength'),
    damping: paramOf('damping'),
    mass: paramOf('mass'),
    gravity: paramOf('gravity'),
    wind: paramOf('wind'),
    physicsMix: paramOf('physicsMix'),
  );
}

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

void _ensureStrictlyIncreasing(List<double> times, String ctx) {
  for (var i = 1; i < times.length; i++) {
    if (times[i] <= times[i - 1]) {
      throw FormatException(
          '$ctx.keyframes: times must be strictly increasing');
    }
  }
}

/// Event-timeline ordering: non-decreasing (equal times allowed), unlike the
/// strict bone/slot/deform rule. Rejects only a strictly decreasing adjacent
/// pair, mirroring Nim `ensureEventSorted` (timelines.nim:245-248) /
/// docs/event-timeline-contract.md edge case (c).
void _ensureNonDecreasing(List<double> times, String ctx) {
  for (var i = 1; i < times.length; i++) {
    if (times[i] < times[i - 1]) {
      throw FormatException('$ctx.keyframes: times must be non-decreasing');
    }
  }
}

List<AnimationClip> _parseAnimations(List<dynamic> anims, SkeletonData data) {
  final result = <AnimationClip>[];
  final meshesByName = <String, MeshAttachment>{
    for (final m in data.meshAttachments) m.name: m,
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

    final deformTimelines = <DeformTimeline>[];
    final dtList = anim['deformTimelines'] as List<dynamic>? ?? const [];
    for (var di = 0; di < dtList.length; di++) {
      final dt = dtList[di] as Map<String, dynamic>;
      final dtCtx = '$ctx.deformTimelines[$di]';
      final skin = _required<String>(dt['skin'], '$dtCtx.skin');
      if (!data.hasSkin(skin)) {
        throw FormatException('$dtCtx.skin names unknown skin: $skin');
      }
      final slot = _required<String>(dt['slot'], '$dtCtx.slot');
      final attachment =
          _required<String>(dt['attachment'], '$dtCtx.attachment');
      final vertexCount =
          _required<num>(dt['vertexCount'], '$dtCtx.vertexCount').toInt();
      final resolvedAttachment =
          data.resolveSkinAttachmentTarget(skin, slot, attachment);
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
        deformTimelines: deformTimelines,
        eventTimelines: eventTimelines));
  }
  return result;
}

ParameterAxis _parseParameter(Map<String, dynamic> j) {
  return ParameterAxis(
    name: _required<String>(j['name'], 'parameter.name'),
    minValue: _required<num>(j['min'], 'parameter.min').toDouble(),
    maxValue: _required<num>(j['max'], 'parameter.max').toDouble(),
    defaultValue: (j['default'] as num?)?.toDouble() ?? 0.0,
  );
}

DeformerRecord _parseDeformer(
  Map<String, dynamic> j,
  Map<String, ParameterAxis> paramsByName,
) {
  final id = _required<String>(j['id'], 'deformer.id');
  final parent = (j['parent'] as String?) ?? '';
  final order = (j['order'] as num?)?.toInt() ?? 0;
  final kindStr = _required<String>(j['kind'], 'deformer.kind');

  DeformerData deformerData;
  if (kindStr == 'warp') {
    final wj = _required<Map<String, dynamic>>(j['warp'], 'deformer.warp');
    final rows = (_required<num>(wj['rows'], 'warp.rows')).toInt();
    final cols = (_required<num>(wj['cols'], 'warp.cols')).toInt();
    final cpRaw =
        _required<List<dynamic>>(wj['controlPoints'], 'warp.controlPoints');
    final controlPoints = cpRaw.map((p) {
      final pm = p as Map<String, dynamic>;
      return DeformerPoint(
        x: _required<num>(pm['x'], 'warp.controlPoint.x').toDouble(),
        y: _required<num>(pm['y'], 'warp.controlPoint.y').toDouble(),
      );
    }).toList();
    deformerData = WarpDeformer(
      id: id,
      parent: parent,
      order: order,
      warp: WarpLattice(
        rows: rows,
        cols: cols,
        minX: _required<num>(wj['minX'], 'warp.minX').toDouble(),
        minY: _required<num>(wj['minY'], 'warp.minY').toDouble(),
        maxX: _required<num>(wj['maxX'], 'warp.maxX').toDouble(),
        maxY: _required<num>(wj['maxY'], 'warp.maxY').toDouble(),
        controlPoints: controlPoints,
      ),
    );
  } else if (kindStr == 'rotation') {
    final rj =
        _required<Map<String, dynamic>>(j['rotation'], 'deformer.rotation');
    deformerData = RotationDeformer(
      id: id,
      parent: parent,
      order: order,
      rotation: RotationDeformerData(
        pivotX: _required<num>(rj['pivotX'], 'rotation.pivotX').toDouble(),
        pivotY: _required<num>(rj['pivotY'], 'rotation.pivotY').toDouble(),
        angleDegrees:
            _required<num>(rj['angleDegrees'], 'rotation.angleDegrees')
                .toDouble(),
        scaleX: (rj['scaleX'] as num?)?.toDouble() ?? 1.0,
        scaleY: (rj['scaleY'] as num?)?.toDouble() ?? 1.0,
        opacity: (rj['opacity'] as num?)?.toDouble() ?? 1.0,
      ),
    );
  } else {
    throw FormatException('deformer.kind unknown: $kindStr');
  }

  final kbj = j['keyformBlend'] as Map<String, dynamic>?;
  if (kbj == null) {
    return DeformerRecord(
        deformer: deformerData, keyformBlend: const KeyformBlend());
  }

  final axisNames = _required<List<dynamic>>(kbj['axes'], 'keyformBlend.axes');
  final axes = axisNames.map((n) {
    final name = n as String;
    final axis = paramsByName[name];
    if (axis == null)
      throw FormatException('keyformBlend references unknown parameter: $name');
    return axis;
  }).toList();

  final kfList =
      _required<List<dynamic>>(kbj['keyforms'], 'keyformBlend.keyforms');
  final keyforms = kfList.map((kf) {
    final kfm = kf as Map<String, dynamic>;
    final coordMap = _required<Map<String, dynamic>>(
        kfm['coordinates'], 'keyform.coordinates');
    final coordinates = axes.map((a) {
      final v = coordMap[a.name];
      if (v == null)
        throw FormatException('keyform missing coordinate: ${a.name}');
      return ParameterSample(name: a.name, value: (v as num).toDouble());
    }).toList();
    final vals = _required<List<dynamic>>(kfm['values'], 'keyform.values');
    return Keyform(
      coordinates: coordinates,
      values: vals.map((v) => (v as num).toDouble()).toList(),
    );
  }).toList();

  final valueCount = keyforms.isEmpty ? 0 : keyforms[0].values.length;
  return DeformerRecord(
    deformer: deformerData,
    keyformBlend:
        KeyformBlend(axes: axes, valueCount: valueCount, keyforms: keyforms),
  );
}

PathAttachment _parsePathAttachment(Map<String, dynamic> j) {
  return PathAttachment(
    name: _required<String>(j['name'], 'pathAttachment.name'),
    p0x: _required<num>(j['p0x'], 'pathAttachment.p0x').toDouble(),
    p0y: _required<num>(j['p0y'], 'pathAttachment.p0y').toDouble(),
    p1x: _required<num>(j['p1x'], 'pathAttachment.p1x').toDouble(),
    p1y: _required<num>(j['p1y'], 'pathAttachment.p1y').toDouble(),
    p2x: _required<num>(j['p2x'], 'pathAttachment.p2x').toDouble(),
    p2y: _required<num>(j['p2y'], 'pathAttachment.p2y').toDouble(),
    p3x: _required<num>(j['p3x'], 'pathAttachment.p3x').toDouble(),
    p3y: _required<num>(j['p3y'], 'pathAttachment.p3y').toDouble(),
  );
}

StateMachineData _parseStateMachine(Map<String, dynamic> j) {
  final name = _required<String>(j['name'], 'stateMachine.name');

  final inputsRaw = j['inputs'] as List<dynamic>? ?? [];
  final inputs = inputsRaw.map((i) {
    final m = i as Map<String, dynamic>;
    final iname = _required<String>(m['name'], 'input.name');
    final kind = _required<String>(m['kind'], 'input.kind');
    switch (kind) {
      case 'bool':
        return StateMachineInput(
          name: iname,
          kind: StateMachineInputKind.bool_,
          defaultBool: (m['default'] as bool?) ?? false,
        );
      case 'number':
        return StateMachineInput(
          name: iname,
          kind: StateMachineInputKind.number,
          defaultNumber: quantizeF32((m['default'] as num?)?.toDouble() ?? 0.0),
        );
      case 'trigger':
        return StateMachineInput(
            name: iname, kind: StateMachineInputKind.trigger);
      default:
        throw FormatException('unknown input kind: $kind');
    }
  }).toList();

  final layersRaw =
      _required<List<dynamic>>(j['layers'], 'stateMachine.layers');
  final layers = layersRaw.map((l) {
    final lm = l as Map<String, dynamic>;
    final lname = _required<String>(lm['name'], 'layer.name');
    final initialState = (lm['initialState'] as String?) ?? '';

    final statesRaw = _required<List<dynamic>>(lm['states'], 'layer.states');
    final states = statesRaw.map((s) {
      final sm = s as Map<String, dynamic>;
      final sname = _required<String>(sm['name'], 'state.name');
      final kind = _required<String>(sm['kind'], 'state.kind');
      if (kind == 'clip') {
        return StateMachineState(
          name: sname,
          kind: StateMachineStateKind.clip,
          clipName: _required<String>(sm['clip'], 'state.clip'),
          loop: (sm['loop'] as bool?) ?? false,
        );
      } else if (kind == 'blend1d') {
        final blendClipsRaw =
            _required<List<dynamic>>(sm['blendClips'], 'state.blendClips');
        final blendClips = blendClipsRaw.map((bc) {
          final bcm = bc as Map<String, dynamic>;
          return StateMachineBlendClip(
            clipName: _required<String>(bcm['clip'], 'blendClip.clip'),
            value: quantizeF32(
                _required<num>(bcm['value'], 'blendClip.value').toDouble()),
            loop: (bcm['loop'] as bool?) ?? false,
          );
        }).toList()
          ..sort((a, b) => a.value.compareTo(b.value));
        for (var bi = 1; bi < blendClips.length; bi++) {
          if (blendClips[bi].value == blendClips[bi - 1].value) {
            throw FormatException(
                'duplicate blend clip value: ${blendClips[bi].value}');
          }
        }
        return StateMachineState(
          name: sname,
          kind: StateMachineStateKind.blend1d,
          blendInput: _required<String>(sm['blendInput'], 'state.blendInput'),
          blendClips: blendClips,
        );
      } else {
        throw FormatException('unknown state kind: $kind');
      }
    }).toList();

    final transitionsRaw = lm['transitions'] as List<dynamic>? ?? [];
    final transitions = transitionsRaw.map((t) {
      final tm = t as Map<String, dynamic>;
      final conditionsRaw =
          _required<List<dynamic>>(tm['conditions'], 'transition.conditions');
      final conditions = conditionsRaw.map((c) {
        final cm = c as Map<String, dynamic>;
        final cinput = _required<String>(cm['input'], 'condition.input');
        final ckind = _required<String>(cm['kind'], 'condition.kind');
        switch (ckind) {
          case 'boolEquals':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.boolEquals,
              boolValue: _required<bool>(cm['value'], 'condition.value'),
            );
          case 'numberEquals':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberEquals,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'numberGreater':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberGreater,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'numberGreaterOrEqual':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberGreaterOrEqual,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'numberLess':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberLess,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'numberLessOrEqual':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.numberLessOrEqual,
              numberValue: quantizeF32(
                  _required<num>(cm['value'], 'condition.value').toDouble()),
            );
          case 'triggerSet':
            return StateMachineCondition(
              input: cinput,
              kind: StateMachineConditionKind.triggerSet,
            );
          default:
            throw FormatException('unknown condition kind: $ckind');
        }
      }).toList();
      return StateMachineTransition(
        fromState: _required<String>(tm['fromState'], 'transition.fromState'),
        toState: _required<String>(tm['toState'], 'transition.toState'),
        conditions: conditions,
      );
    }).toList();

    if (states.isEmpty)
      throw FormatException(
          'state machine layer "$lname" must have at least one state');
    final resolvedInitial =
        initialState.isEmpty ? states[0].name : initialState;
    if (!states.any((s) => s.name == resolvedInitial)) {
      throw FormatException(
          'state machine layer "$lname" initialState "$resolvedInitial" not found');
    }
    return StateMachineLayer(
      name: lname,
      states: states,
      initialState: resolvedInitial,
      transitions: transitions,
    );
  }).toList();

  final listenersRaw = j['listeners'] as List<dynamic>? ?? [];
  final listeners = listenersRaw.map((l) {
    final lm = l as Map<String, dynamic>;
    final lname = _required<String>(lm['name'], 'listener.name');
    final lkind = _required<String>(lm['kind'], 'listener.kind');
    bool hasAny(Iterable<String> keys) => keys.any(lm.containsKey);

    switch (lkind) {
      case 'stateEnter':
        if (hasAny(
            ['slot', 'targetKind', 'target', 'hitRadius', 'input', 'value'])) {
          throw const FormatException(
              'lifecycle listener must not contain pointer fields');
        }
        final llayer = _required<String>(lm['layer'], 'listener.layer');
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.stateEnter,
          layer: llayer,
          toState: _required<String>(lm['toState'], 'listener.toState'),
        );
      case 'stateExit':
        if (hasAny(
            ['slot', 'targetKind', 'target', 'hitRadius', 'input', 'value'])) {
          throw const FormatException(
              'lifecycle listener must not contain pointer fields');
        }
        final llayer = _required<String>(lm['layer'], 'listener.layer');
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.stateExit,
          layer: llayer,
          fromState: _required<String>(lm['fromState'], 'listener.fromState'),
        );
      case 'transition':
        if (hasAny(
            ['slot', 'targetKind', 'target', 'hitRadius', 'input', 'value'])) {
          throw const FormatException(
              'lifecycle listener must not contain pointer fields');
        }
        final llayer = _required<String>(lm['layer'], 'listener.layer');
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.transition_,
          layer: llayer,
          fromState: _required<String>(lm['fromState'], 'listener.fromState'),
          toState: _required<String>(lm['toState'], 'listener.toState'),
        );
      case 'pointerDown':
      case 'pointerUp':
      case 'pointerEnter':
      case 'pointerExit':
      case 'pointerMove':
        if (hasAny(['layer', 'fromState', 'toState'])) {
          throw const FormatException(
              'pointer listener must not contain lifecycle fields');
        }
        final targetKindRaw =
            _required<String>(lm['targetKind'], 'listener.targetKind');
        final targetKind = switch (targetKindRaw) {
          'point' => PointerHelperTargetKind.point,
          'boundingBox' => PointerHelperTargetKind.boundingBox,
          _ => throw FormatException(
              'unknown listener targetKind: $targetKindRaw'),
        };
        bool? boolValue;
        double? numberValue;
        final value = lm['value'];
        if (value is bool) {
          boolValue = value;
        } else if (value is num) {
          numberValue = quantizeF32(value.toDouble());
        } else if (lm.containsKey('value')) {
          throw const FormatException('listener.value must be bool or number');
        }
        return StateMachineListener(
          name: lname,
          kind: switch (lkind) {
            'pointerDown' => StateMachineListenerKind.pointerDown,
            'pointerUp' => StateMachineListenerKind.pointerUp,
            'pointerEnter' => StateMachineListenerKind.pointerEnter,
            'pointerExit' => StateMachineListenerKind.pointerExit,
            _ => StateMachineListenerKind.pointerMove,
          },
          slot: _required<String>(lm['slot'], 'listener.slot'),
          targetKind: targetKind,
          target: _required<String>(lm['target'], 'listener.target'),
          hitRadius: lm.containsKey('hitRadius')
              ? quantizeF32(
                  _required<num>(lm['hitRadius'], 'listener.hitRadius')
                      .toDouble())
              : null,
          input: _required<String>(lm['input'], 'listener.input'),
          boolValue: boolValue,
          numberValue: numberValue,
        );
      default:
        throw FormatException('unknown listener kind: $lkind');
    }
  }).toList();

  return StateMachineData(
    name: name,
    layers: layers,
    inputs: inputs,
    listeners: listeners,
  );
}
