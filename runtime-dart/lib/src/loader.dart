// .bony JSON loader and .bnb binary loader.
//
// Defaults follow the values in the generated registry (bonyPropertyDefaults).

import 'dart:convert';
import 'dart:typed_data' show Uint8List, ByteData, Endian;
import 'deform.dart' show quantizeF32;
import 'model.dart';
import 'physics_constraint.dart' show physicsChannelsFromMask;

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

BoneData _parseBone(Map<String, dynamic> j) {
  return BoneData(
    name: _required<String>(j['name'], 'bone.name'),
    parent: (j['parent'] as String?) ?? '',
    x: (j['x'] as num?)?.toDouble() ?? 0.0,
    y: (j['y'] as num?)?.toDouble() ?? 0.0,
    rotation: (j['rotation'] as num?)?.toDouble() ?? 0.0,
    scaleX: (j['scaleX'] as num?)?.toDouble() ?? 1.0,
    scaleY: (j['scaleY'] as num?)?.toDouble() ?? 1.0,
    shearX: (j['shearX'] as num?)?.toDouble() ?? 0.0,
    shearY: (j['shearY'] as num?)?.toDouble() ?? 0.0,
    inheritRotation: (j['inheritRotation'] as bool?) ?? true,
    inheritScale: (j['inheritScale'] as bool?) ?? true,
    inheritReflection: (j['inheritReflection'] as bool?) ?? true,
    transformMode: (j['transformMode'] as String?) ?? 'normal',
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
  return RegionAttachment(
    name: _required<String>(j['name'], 'region.name'),
    width: _required<num>(j['width'], 'region.width').toDouble(),
    height: _required<num>(j['height'], 'region.height').toDouble(),
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

  // uvs are a flat [u0, v0, u1, v1, ...] list; pair them into MeshUv.
  final uvsRaw = _required<List<dynamic>>(j['uvs'], 'meshAttachment.uvs');
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

PathConstraintData _parsePath(Map<String, dynamic> j) {
  return PathConstraintData(
    name: _required<String>(j['name'], 'path.name'),
    bone: _required<String>(j['bone'], 'path.bone'),
    target: _required<String>(j['target'], 'path.target'),
    path: _required<String>(j['path'], 'path.path'),
    // JSON doesn't distinguish int from double; toInt() handles "order": 0.0.
    order: (j['order'] as num?)?.toInt() ?? 0,
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
    throw const FormatException('missing required field: physicsConstraint.channels');
  }
  final channels = physicsChannelsFromMask((rawChannels as num).toInt());

  return PhysicsConstraintData(
    name: _required<String>(j['name'], 'physicsConstraint.name'),
    bone: _required<String>(j['bone'], 'physicsConstraint.bone'),
    channels: channels,
    order: (j['order'] as num?)?.toInt() ?? 0,
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

List<AnimationClip> _parseAnimations(List<dynamic> anims) {
  final result = <AnimationClip>[];
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

    result.add(AnimationClip(
        name: name,
        duration: duration,
        boneTimelines: boneTimelines,
        slotTimelines: slotTimelines));
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
    deformerData = DeformerData(
      id: id,
      parent: parent,
      order: order,
      kind: DeformerKind.warp,
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
    deformerData = DeformerData(
      id: id,
      parent: parent,
      order: order,
      kind: DeformerKind.rotation,
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

void _validate(SkeletonData data) {
  if (data.header.name.isEmpty) {
    throw const FormatException('skeleton.name must not be empty');
  }

  final boneNames = <String>{};
  final seenBones = <String>{};
  for (var i = 0; i < data.bones.length; i++) {
    final b = data.bones[i];
    final ctx = 'bones[$i]';
    if (b.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!boneNames.add(b.name)) {
      throw FormatException('duplicate bone name: ${b.name}');
    }
  }
  // Second pass: parent ordering (parent must appear before child).
  for (var i = 0; i < data.bones.length; i++) {
    final b = data.bones[i];
    if (b.parent.isNotEmpty) {
      if (!boneNames.contains(b.parent)) {
        throw FormatException('unknown parent bone: ${b.parent}');
      }
      if (!seenBones.contains(b.parent)) {
        throw FormatException(
          'bone parent must appear before child: ${b.name}',
        );
      }
    }
    seenBones.add(b.name);
  }

  final regionNames = <String>{};
  for (var i = 0; i < data.regions.length; i++) {
    final r = data.regions[i];
    final ctx = 'regions[$i]';
    if (r.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (r.width < 0 || r.height < 0) {
      throw FormatException('$ctx dimensions must be non-negative');
    }
    if (!regionNames.add(r.name)) {
      throw FormatException('duplicate region name: ${r.name}');
    }
  }

  // Clipping attachment names share the slot.attachment namespace with regions
  // (a slot may reference either). Mirrors the Nim loader's widened check and
  // the region/clip name-collision guard (runtime-nim/src/bony/model.nim).
  final clipNames = <String>{};
  for (var i = 0; i < data.clippingAttachments.length; i++) {
    final c = data.clippingAttachments[i];
    final ctx = 'clippingAttachments[$i]';
    if (c.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (c.vertices.length < 6 || c.vertices.length.isOdd) {
      throw FormatException(
          '$ctx.vertices must contain at least three (x, y) pairs');
    }
    if (!clipNames.add(c.name)) {
      throw FormatException('duplicate clipping attachment name: ${c.name}');
    }
    if (regionNames.contains(c.name)) {
      throw FormatException(
          'clipping attachment name collides with a region attachment name: '
          '${c.name}');
    }
    // Finite + convex, non-zero-area invariants (mirror the Nim loader
    // runtime-nim/src/bony/model.nim / mesh/clipping.nim validateConvexClip).
    const clipAreaEpsilon = 1e-9;
    for (var vi = 0; vi < c.vertices.length; vi++) {
      if (!c.vertices[vi].isFinite) {
        throw FormatException('$ctx.vertices[$vi] must be finite');
      }
    }
    final pointCount = c.vertices.length ~/ 2;
    var area = 0.0;
    for (var p = 0; p < pointCount; p++) {
      final ax = c.vertices[2 * p];
      final ay = c.vertices[2 * p + 1];
      final nx = c.vertices[2 * ((p + 1) % pointCount)];
      final ny = c.vertices[2 * ((p + 1) % pointCount) + 1];
      area += ax * ny - nx * ay;
    }
    area *= 0.5;
    if (area.abs() <= clipAreaEpsilon) {
      throw FormatException('$ctx.vertices polygon area must be non-zero');
    }
    final sign = area > 0.0 ? 1.0 : -1.0;
    for (var p = 0; p < pointCount; p++) {
      final ax = c.vertices[2 * p];
      final ay = c.vertices[2 * p + 1];
      final bx = c.vertices[2 * ((p + 1) % pointCount)];
      final by = c.vertices[2 * ((p + 1) % pointCount) + 1];
      final cx = c.vertices[2 * ((p + 2) % pointCount)];
      final cy = c.vertices[2 * ((p + 2) % pointCount) + 1];
      final turn = (bx - ax) * (cy - by) - (by - ay) * (cx - bx);
      if (turn * sign < -clipAreaEpsilon) {
        throw FormatException('$ctx.vertices must be convex in v1');
      }
    }
  }

  // Mesh attachment names also share the slot.attachment namespace with regions
  // and clips. Mirror the Nim loader's cross-collection uniqueness guard
  // (runtime-nim/src/bony/model.nim): a mesh name must not collide with a region
  // or clip name.
  final meshNames = <String>{};
  for (var i = 0; i < data.meshAttachments.length; i++) {
    final m = data.meshAttachments[i];
    final ctx = 'meshAttachments[$i]';
    if (m.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!meshNames.add(m.name)) {
      throw FormatException('duplicate mesh attachment name: ${m.name}');
    }
    if (regionNames.contains(m.name)) {
      throw FormatException(
          'mesh attachment name collides with a region attachment name: '
          '${m.name}');
    }
    if (clipNames.contains(m.name)) {
      throw FormatException(
          'mesh attachment name collides with a clipping attachment name: '
          '${m.name}');
    }
  }

  final slotNames = <String>{};
  for (var i = 0; i < data.slots.length; i++) {
    final s = data.slots[i];
    final ctx = 'slots[$i]';
    if (s.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!boneNames.contains(s.bone)) {
      throw FormatException('unknown slot bone: ${s.bone}');
    }
    if (s.attachment.isNotEmpty &&
        !regionNames.contains(s.attachment) &&
        !clipNames.contains(s.attachment) &&
        !meshNames.contains(s.attachment)) {
      throw FormatException('unknown slot attachment: ${s.attachment}');
    }
    if (!slotNames.add(s.name)) {
      throw FormatException('duplicate slot name: ${s.name}');
    }
  }

  // Clipping range + no-overlap validation (mirror the Nim loader). A clip's
  // range starts at the slot that references it and runs through untilSlot
  // inclusive (else to the end of draw order); untilSlot must name a known slot
  // strictly after the clip's own slot, and ranges may not overlap.
  if (data.clippingAttachments.isNotEmpty) {
    final slotIndexByName = <String, int>{};
    for (var i = 0; i < data.slots.length; i++) {
      slotIndexByName[data.slots[i].name] = i;
    }
    final clipByName = <String, ClippingAttachment>{
      for (final c in data.clippingAttachments) c.name: c,
    };
    for (final c in data.clippingAttachments) {
      if (c.untilSlot.isNotEmpty && !slotIndexByName.containsKey(c.untilSlot)) {
        throw FormatException(
            'clipping attachment untilSlot names unknown slot: ${c.untilSlot}');
      }
    }
    final lastSlotIndex = data.slots.length - 1;
    var activeUntil = -1;
    var activeName = '';
    for (var slotIdx = 0; slotIdx < data.slots.length; slotIdx++) {
      final s = data.slots[slotIdx];
      if (s.attachment.isEmpty || !clipByName.containsKey(s.attachment)) {
        continue;
      }
      final clip = clipByName[s.attachment]!;
      final ownIndex = slotIdx;
      final endIndex = clip.untilSlot.isNotEmpty
          ? slotIndexByName[clip.untilSlot]!
          : lastSlotIndex;
      if (endIndex <= ownIndex) {
        throw FormatException(
            "clipping attachment '${s.attachment}' on slot '${s.name}' has an "
            "empty range (untilSlot at or before the clip's own slot)");
      }
      if (ownIndex <= activeUntil) {
        throw FormatException(
            "clipping ranges overlap: '${s.attachment}' begins while "
            "'$activeName' is still active");
      }
      activeUntil = endIndex;
      activeName = s.attachment;
    }
  }

  final pathAttachmentNames = <String>{};
  for (var i = 0; i < data.pathAttachments.length; i++) {
    final pa = data.pathAttachments[i];
    final ctx = 'pathAttachments[$i]';
    if (pa.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!pathAttachmentNames.add(pa.name)) {
      throw FormatException('duplicate path attachment name: ${pa.name}');
    }
  }

  final pathNames = <String>{};
  for (var i = 0; i < data.paths.length; i++) {
    final p = data.paths[i];
    final ctx = 'paths[$i]';
    if (p.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!boneNames.contains(p.bone)) {
      throw FormatException('unknown path constraint bone: ${p.bone}');
    }
    if (!boneNames.contains(p.target)) {
      throw FormatException('unknown path constraint target: ${p.target}');
    }
    if (!pathAttachmentNames.contains(p.path)) {
      throw FormatException('unknown path constraint path: ${p.path}');
    }
    if (!pathNames.add(p.name)) {
      throw FormatException('duplicate path constraint name: ${p.name}');
    }
  }

  // IK constraint validation, mirroring runtime-nim (model.nim). Applied on both
  // the JSON and .bnb load paths so Dart rejects exactly what Nim rejects.
  final ikNames = <String>{};
  final boneParentByName = <String, String>{
    for (final b in data.bones) b.name: b.parent,
  };
  for (var i = 0; i < data.ikConstraints.length; i++) {
    final ik = data.ikConstraints[i];
    final ctx = 'ikConstraints[$i]';
    if (ik.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!ikNames.add(ik.name)) {
      throw FormatException('duplicate ik constraint name: ${ik.name}');
    }
    if (ik.bones.isEmpty) {
      throw FormatException('$ctx.bones must not be empty');
    }
    for (final boneName in ik.bones) {
      if (!boneNames.contains(boneName)) {
        throw FormatException('unknown ik constraint bone: $boneName');
      }
    }
    // The chain must be contiguous root->tip: each bone after the first is the
    // direct child of the preceding one.
    for (var c = 1; c < ik.bones.length; c++) {
      if (boneParentByName[ik.bones[c]] != ik.bones[c - 1]) {
        throw FormatException(
          '$ctx.bones must form a contiguous parent-to-child chain '
          '(root to tip): ${ik.bones[c]} is not a child of ${ik.bones[c - 1]}');
      }
    }
    if (!boneNames.contains(ik.target)) {
      throw FormatException('unknown ik constraint target: ${ik.target}');
    }
    final mix = ik.mix;
    if (mix != null && (mix < 0.0 || mix > 1.0)) {
      throw FormatException('$ctx.mix must be in [0, 1]');
    }
  }

  // Transform constraint validation, mirroring runtime-nim (model.nim): unique
  // name, known bone/target refs, each present mix finite and in [0, 1].
  final transformNames = <String>{};
  for (var i = 0; i < data.transformConstraints.length; i++) {
    final tc = data.transformConstraints[i];
    final ctx = 'transformConstraints[$i]';
    if (tc.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!transformNames.add(tc.name)) {
      throw FormatException('duplicate transform constraint name: ${tc.name}');
    }
    if (!boneNames.contains(tc.bone)) {
      throw FormatException('unknown transform constraint bone: ${tc.bone}');
    }
    if (!boneNames.contains(tc.target)) {
      throw FormatException('unknown transform constraint target: ${tc.target}');
    }
    for (final entry in <String, double?>{
      'translateMix': tc.translateMix,
      'rotateMix': tc.rotateMix,
      'scaleMix': tc.scaleMix,
      'shearMix': tc.shearMix,
    }.entries) {
      final v = entry.value;
      if (v != null && (v.isNaN || v.isInfinite || v < 0.0 || v > 1.0)) {
        throw FormatException('$ctx.${entry.key} must be in [0, 1]');
      }
    }
  }

  final physicsNames = <String>{};
  for (var i = 0; i < data.physicsConstraints.length; i++) {
    final pc = data.physicsConstraints[i];
    final ctx = 'physicsConstraints[$i]';
    if (pc.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!physicsNames.add(pc.name)) {
      throw FormatException('duplicate physics constraint name: ${pc.name}');
    }
    if (!boneNames.contains(pc.bone)) {
      throw FormatException('unknown physics constraint bone: ${pc.bone}');
    }
    if (pc.channels.isEmpty) {
      throw FormatException('$ctx.channels must enable at least one channel');
    }
    // Bounds mirror the eval-time physicsParams: finite everywhere, mass >= 0,
    // physicsMix in [0, 1]. Absent (null) params take integrator defaults.
    for (final entry in <String, double?>{
      'inertia': pc.inertia,
      'strength': pc.strength,
      'damping': pc.damping,
      'gravity': pc.gravity,
      'wind': pc.wind,
    }.entries) {
      final v = entry.value;
      if (v != null && (v.isNaN || v.isInfinite)) {
        throw FormatException('$ctx.${entry.key} must be finite');
      }
    }
    final mass = pc.mass;
    if (mass != null && (mass.isNaN || mass.isInfinite || mass < 0.0)) {
      throw FormatException('$ctx.mass must be non-negative');
    }
    final mix = pc.physicsMix;
    if (mix != null && (mix.isNaN || mix.isInfinite || mix < 0.0 || mix > 1.0)) {
      throw FormatException('$ctx.physicsMix must be in [0, 1]');
    }
  }

  for (var ai = 0; ai < data.animations.length; ai++) {
    final anim = data.animations[ai];
    final ctx = 'animations[$ai](${anim.name})';
    for (var bi = 0; bi < anim.boneTimelines.length; bi++) {
      final tl = anim.boneTimelines[bi];
      if (!boneNames.contains(tl.bone)) {
        throw FormatException(
            '$ctx.boneTimelines[$bi]: unknown bone: ${tl.bone}');
      }
    }
    for (var si = 0; si < anim.slotTimelines.length; si++) {
      final tl = anim.slotTimelines[si];
      if (!slotNames.contains(tl.slot)) {
        throw FormatException(
            '$ctx.slotTimelines[$si]: unknown slot: ${tl.slot}');
      }
    }
  }

  // M7 deformer validation.
  final deformerIds = <String>{};
  final deformerOrders = <int>{};
  for (var di = 0; di < data.deformers.length; di++) {
    final rec = data.deformers[di];
    final def = rec.deformer;
    final ctx = 'deformers[$di](${def.id})';
    if (def.id.isEmpty) throw FormatException('$ctx.id must not be empty');
    if (!deformerIds.add(def.id)) {
      throw FormatException('duplicate deformer id: ${def.id}');
    }
    if (!deformerOrders.add(def.order)) {
      throw FormatException('duplicate deformer order: ${def.order}');
    }
    if (def.parent.isNotEmpty && !deformerIds.contains(def.parent)) {
      throw FormatException(
          '$ctx: parent deformer not found or not ordered before child: ${def.parent}');
    }
    if (def.kind == DeformerKind.warp) {
      final w = def.warp!;
      if (w.rows < 2)
        throw FormatException('$ctx warp.rows must be >= 2, got ${w.rows}');
      if (w.cols < 2)
        throw FormatException('$ctx warp.cols must be >= 2, got ${w.cols}');
      final expectedPts = w.rows * w.cols;
      if (w.controlPoints.length != expectedPts) {
        throw FormatException(
            '$ctx warp.controlPoints: expected $expectedPts, got ${w.controlPoints.length}');
      }
      if (w.maxX <= w.minX) {
        throw FormatException(
            '$ctx warp bounds: maxX (${w.maxX}) must be > minX (${w.minX})');
      }
      if (w.maxY <= w.minY) {
        throw FormatException(
            '$ctx warp bounds: maxY (${w.maxY}) must be > minY (${w.minY})');
      }
    }
  }

  // M8 state machine cross-reference validation.
  final animationNames = <String>{for (final a in data.animations) a.name};
  for (var smi = 0; smi < data.stateMachines.length; smi++) {
    final sm = data.stateMachines[smi];
    final smCtx = 'stateMachines[$smi](${sm.name})';
    final inputNames = <String>{for (final inp in sm.inputs) inp.name};
    final layerStateNames = <String, Set<String>>{};
    for (var li = 0; li < sm.layers.length; li++) {
      final layer = sm.layers[li];
      final lCtx = '$smCtx.layers[$li](${layer.name})';
      final stateNames = <String>{for (final s in layer.states) s.name};
      layerStateNames[layer.name] = stateNames;
      for (var si = 0; si < layer.states.length; si++) {
        final state = layer.states[si];
        final sCtx = '$lCtx.states[$si](${state.name})';
        if (state.kind == StateMachineStateKind.clip) {
          if (!animationNames.contains(state.clipName)) {
            throw FormatException(
                '$sCtx.clip references unknown animation: ${state.clipName}');
          }
        } else if (state.kind == StateMachineStateKind.blend1d) {
          if (!inputNames.contains(state.blendInput)) {
            throw FormatException(
                '$sCtx.blendInput references unknown input: ${state.blendInput}');
          }
          for (var bci = 0; bci < state.blendClips.length; bci++) {
            final bc = state.blendClips[bci];
            if (!animationNames.contains(bc.clipName)) {
              throw FormatException(
                  '$sCtx.blendClips[$bci].clip references unknown animation: ${bc.clipName}');
            }
          }
        }
      }
      for (var ti = 0; ti < layer.transitions.length; ti++) {
        final tr = layer.transitions[ti];
        final trCtx = '$lCtx.transitions[$ti]';
        if (!stateNames.contains(tr.fromState)) {
          throw FormatException(
              '$trCtx.fromState references unknown state: ${tr.fromState}');
        }
        if (!stateNames.contains(tr.toState)) {
          throw FormatException(
              '$trCtx.toState references unknown state: ${tr.toState}');
        }
        for (var ci = 0; ci < tr.conditions.length; ci++) {
          final cond = tr.conditions[ci];
          if (!inputNames.contains(cond.input)) {
            throw FormatException(
                '$trCtx.conditions[$ci].input references unknown input: ${cond.input}');
          }
        }
      }
    }
    for (var li = 0; li < sm.listeners.length; li++) {
      final lst = sm.listeners[li];
      final lstCtx = '$smCtx.listeners[$li](${lst.name})';
      final lstStates = layerStateNames[lst.layer];
      if (lstStates == null) {
        throw FormatException(
            '$lstCtx.layer references unknown layer: ${lst.layer}');
      }
      if (lst.kind == StateMachineListenerKind.stateEnter ||
          lst.kind == StateMachineListenerKind.transition_) {
        if (!lstStates.contains(lst.toState)) {
          throw FormatException(
              '$lstCtx.toState references unknown state: ${lst.toState}');
        }
      }
      if (lst.kind == StateMachineListenerKind.stateExit ||
          lst.kind == StateMachineListenerKind.transition_) {
        if (!lstStates.contains(lst.fromState)) {
          throw FormatException(
              '$lstCtx.fromState references unknown state: ${lst.fromState}');
        }
      }
    }
  }
}

// ===========================================================================
// Binary (.bnb) loader
// ===========================================================================

// .bnb type keys.
const int _bnbSkeleton = 1;
const int _bnbBone = 2;
const int _bnbSlot = 1000;
const int _bnbRegion = 1001;
const int _bnbClippingAttachment = 3000;
const int _bnbMeshAttachment = 3001;
const int _bnbPath = 4000;
const int _bnbPathAttachment = 4001;
const int _bnbIkConstraint = 4002;
const int _bnbTransformConstraint = 4003;
const int _bnbPhysicsConstraint = 4004;
const int _bnbAnimationClip = 2000;
const int _bnbBoneTimeline = 2001;
const int _bnbSlotTimeline = 2002;
const int _bnbStateMachine = 7000;
const int _bnbStateMachineInput = 7001;
const int _bnbStateMachineLayer = 7002;
const int _bnbStateMachineState = 7003;
const int _bnbStateMachineBlendClip = 7004;
const int _bnbStateMachineTransition = 7005;
const int _bnbStateMachineCondition = 7006;
const int _bnbStateMachineListener = 7007;
// M7 type keys.
const int _bnbParameter = 6000;
const int _bnbDeformer = 6001;
const int _bnbWarpLattice = 6002;
const int _bnbRotationDeformer = 6003;
const int _bnbKeyformBlend = 6004;
const int _bnbKeyform = 6005;

// .bnb property keys.
const int _bkName = 1;
const int _bkVersion = 2;
const int _bkParent = 3;
const int _bkX = 1000;
const int _bkY = 1001;
const int _bkRotation = 1002;
const int _bkScaleX = 1003;
const int _bkScaleY = 1004;
const int _bkShearX = 1005;
const int _bkShearY = 1006;
const int _bkInheritRotation = 1007;
const int _bkInheritScale = 1008;
const int _bkInheritReflection = 1009;
const int _bkTransformMode = 1010;
const int _bkBone = 1012;
const int _bkAttachment = 1013;
const int _bkWidth = 1014;
const int _bkHeight = 1015;
// Clipping attachment property keys (M4). vertices is a packed-f32-pairs bytes
// payload (varuint count + count*(f32 x, f32 y)); untilSlot is a string.
const int _bkVertices = 3000;
const int _bkUntilSlot = 3001;
// Mesh attachment property keys (M4). meshVertices/meshUvs/meshTriangles are
// packed `bytes` payloads per docs/mesh-attachment-contract.md; meshWeighted is
// a value-gated bool (default false).
const int _bkMeshWeighted = 3002;
const int _bkMeshVertices = 3003;
const int _bkMeshUvs = 3004;
const int _bkMeshTriangles = 3005;
const int _bkTarget = 4000;
const int _bkPath = 4001;
const int _bkOrder = 4002;
const int _bkP0x = 4003;
const int _bkP0y = 4004;
const int _bkP1x = 4005;
const int _bkP1y = 4006;
const int _bkP2x = 4007;
const int _bkP2y = 4008;
const int _bkP3x = 4009;
const int _bkP3y = 4010;
const int _bkPosition = 4011;
const int _bkTranslateMix = 4012;
const int _bkRotateMix = 4013;
// IK constraint property keys (frozen wire contract; bones is a bytes payload).
const int _bkBones = 4014;
const int _bkMix = 4015;
const int _bkBendPositive = 4016;
// Transform constraint property keys (translateMix/rotateMix reused from path).
const int _bkScaleMix = 4017;
const int _bkShearMix = 4018;
// Physics constraint property keys (frozen wire contract; channels is a varuint
// bitmask). Mirrors generated/wire.dart physicsConstraint keys 4019..4026.
const int _bkInertia = 4019;
const int _bkStrength = 4020;
const int _bkDamping = 4021;
const int _bkMass = 4022;
const int _bkGravity = 4023;
const int _bkWind = 4024;
const int _bkPhysicsMix = 4025;
const int _bkChannels = 4026;
const int _bkBoneIndex = 2000;
const int _bkBoneTimelineKind = 2001;
const int _bkSlotIndex = 2002;
const int _bkSlotTimelineKind = 2003;
const int _bkTimelineKeys = 2004;
const int _bkStateMachineInputKind = 7000;
const int _bkInputDefaultBool = 7001;
const int _bkInputDefaultNumber = 7002;
const int _bkInitialStateIndex = 7010;
const int _bkStateMachineStateKind = 7020;
const int _bkStateClipIndex = 7021;
const int _bkStateLoop = 7022;
const int _bkStateBlendInputIndex = 7023;
const int _bkBlendClipAnimationIndex = 7030;
const int _bkBlendClipValue = 7031;
const int _bkBlendClipLoop = 7032;
const int _bkTransitionFromStateIndex = 7040;
const int _bkTransitionToStateIndex = 7041;
const int _bkConditionInputIndex = 7050;
const int _bkStateMachineConditionKind = 7051;
const int _bkConditionBoolValue = 7052;
const int _bkConditionNumberValue = 7053;
const int _bkStateMachineListenerKind = 7060;
const int _bkListenerLayerIndex = 7061;
const int _bkListenerFromStateIndex = 7062;
const int _bkListenerToStateIndex = 7063;
// M7 property keys.
const int _bkParamMin = 6000;
const int _bkParamMax = 6001;
const int _bkParamDefault = 6002;
const int _bkDefId = 6010;
const int _bkDefOrder = 6011;
const int _bkDefKind = 6012;
const int _bkWarpRows = 6020;
const int _bkWarpCols = 6021;
const int _bkWarpMinX = 6022;
const int _bkWarpMinY = 6023;
const int _bkWarpMaxX = 6024;
const int _bkWarpMaxY = 6025;
const int _bkWarpControlPoints = 6026;
const int _bkRotPivotX = 6030;
const int _bkRotPivotY = 6031;
const int _bkRotAngle = 6032;
const int _bkRotScaleX = 6033;
const int _bkRotScaleY = 6034;
const int _bkRotOpacity = 6035;
const int _bkBlendValueCount = 6040;
const int _bkBlendAxes = 6041;
const int _bkBlendCoords = 6042;
const int _bkBlendValues = 6043;

// Type keys we recognize; everything else is skipped for forward compat.
const _bnbKnownTypes = {
  _bnbSkeleton,
  _bnbBone,
  _bnbSlot,
  _bnbRegion,
  _bnbClippingAttachment,
  _bnbMeshAttachment,
  _bnbPath,
  _bnbPathAttachment,
  _bnbIkConstraint,
  _bnbTransformConstraint,
  _bnbPhysicsConstraint,
  _bnbAnimationClip,
  _bnbBoneTimeline,
  _bnbSlotTimeline,
  _bnbParameter,
  _bnbDeformer,
  _bnbWarpLattice,
  _bnbRotationDeformer,
  _bnbKeyformBlend,
  _bnbKeyform,
  _bnbStateMachine,
  _bnbStateMachineInput,
  _bnbStateMachineLayer,
  _bnbStateMachineState,
  _bnbStateMachineBlendClip,
  _bnbStateMachineTransition,
  _bnbStateMachineCondition,
  _bnbStateMachineListener,
};

// Mutable cursor over a binary buffer.
class _BnbCur {
  _BnbCur(this.data) : _bd = ByteData.sublistView(data);
  final Uint8List data;
  final ByteData _bd;
  int pos = 0;

  void _need(int n, String ctx) {
    if (pos + n > data.length) throw FormatException('truncated $ctx');
  }

  // Unsigned LEB128 (varuint). Validates minimal encoding.
  int readVaruint() {
    final start = pos;
    int result = 0;
    int shift = 0;
    while (true) {
      if (pos >= data.length)
        throw const FormatException('truncated .bnb varuint');
      if (pos - start >= 10)
        throw const FormatException('.bnb varuint too long');
      final b = data[pos++];
      // Bit 63 overflow check: top 7 bits of the 10th byte must be 0 except bit 0.
      if (shift == 63 && (b & 0x7e) != 0) {
        throw const FormatException('.bnb varuint overflows uint64');
      }
      result |= (b & 0x7f) << shift;
      if ((b & 0x80) == 0) break;
      shift += 7;
    }
    final len = pos - start;
    // Minimal encoding: the high bits of the last byte must not all be zero
    // when more than one byte was used.
    if (len > 1 && (result >> (7 * (len - 1))) == 0) {
      throw const FormatException('.bnb varuint not minimally encoded');
    }
    return result;
  }

  // Zig-zag signed LEB128 (varint).
  int readVarint() {
    final enc = readVaruint();
    final mag = enc >> 1;
    return (enc & 1) == 0 ? mag : -(mag + 1);
  }

  double readF32() {
    _need(4, '.bnb f32');
    final v = _bd.getFloat32(pos, Endian.little);
    pos += 4;
    return v.toDouble();
  }

  double readF64() {
    _need(8, '.bnb f64');
    final v = _bd.getFloat64(pos, Endian.little);
    pos += 8;
    return v;
  }

  bool readBool() {
    if (pos >= data.length) throw const FormatException('truncated .bnb bool');
    final b = data[pos++];
    if (b != 0 && b != 1)
      throw FormatException('.bnb bool must be 0 or 1, got $b');
    return b == 1;
  }

  String readStr(List<String> strings) {
    final idx = readVaruint();
    if (idx >= strings.length) {
      throw FormatException(
          '.bnb string index $idx out of range (${strings.length})');
    }
    return strings[idx];
  }

  Uint8List readBytes(int n) {
    _need(n, '.bnb payload');
    final slice = Uint8List.sublistView(data, pos, pos + n);
    pos += n;
    return slice;
  }
}

List<String> _bnbReadStrings(_BnbCur c) {
  final count = c.readVaruint();
  final out = <String>[];
  for (var i = 0; i < count; i++) {
    final len = c.readVaruint();
    c._need(len, '.bnb string[$i]');
    out.add(utf8.decode(c.data.sublist(c.pos, c.pos + len)));
    c.pos += len;
  }
  return out;
}

typedef _BnbObj = ({int typeKey, Map<int, Uint8List> props});

List<_BnbObj> _bnbReadObjects(_BnbCur c) {
  final out = <_BnbObj>[];
  while (true) {
    final typeKey = c.readVaruint();
    if (typeKey == 0) break;
    final props = <int, Uint8List>{};
    final seenProps = <int>{};
    while (true) {
      final pk = c.readVaruint();
      if (pk == 0) break;
      if (!seenProps.add(pk)) {
        throw FormatException(
            '.bnb duplicate property key $pk in type $typeKey object');
      }
      final blen = c.readVaruint();
      props[pk] = c.readBytes(blen);
    }
    if (_bnbKnownTypes.contains(typeKey)) {
      out.add((typeKey: typeKey, props: props));
    }
  }
  if (c.pos != c.data.length) {
    throw const FormatException('.bnb trailing bytes after object stream');
  }
  return out;
}

// Property accessors — each creates a tiny cursor over the stored payload and
// validates that the payload is fully consumed (no trailing bytes).
void _bCheckExhausted(_BnbCur c, String ctx) {
  if (c.pos != c.data.length) {
    throw FormatException(
        '.bnb $ctx payload has ${c.data.length - c.pos} trailing bytes');
  }
}

String _bStr(_BnbObj obj, int key, List<String> strings, String ctx,
    {String? def}) {
  final payload = obj.props[key];
  if (payload == null) {
    if (def != null) return def;
    throw FormatException('.bnb required property missing: $ctx');
  }
  final c = _BnbCur(payload);
  final v = c.readStr(strings);
  _bCheckExhausted(c, ctx);
  return v;
}

double _bF32(_BnbObj obj, int key, String ctx, {double? def}) {
  final payload = obj.props[key];
  if (payload == null) {
    if (def != null) return def;
    throw FormatException('.bnb required property missing: $ctx');
  }
  final c = _BnbCur(payload);
  final v = c.readF32();
  _bCheckExhausted(c, ctx);
  return v;
}

double _bF64(_BnbObj obj, int key, String ctx) {
  final payload = obj.props[key];
  if (payload == null)
    throw FormatException('.bnb required property missing: $ctx');
  final c = _BnbCur(payload);
  final v = c.readF64();
  _bCheckExhausted(c, ctx);
  return v;
}

bool _bBool(_BnbObj obj, int key, {bool def = false}) {
  final payload = obj.props[key];
  if (payload == null) return def;
  final c = _BnbCur(payload);
  final v = c.readBool();
  _bCheckExhausted(c, 'bool');
  return v;
}

/// Decode the required IK `bones` payload: a varuint count followed by
/// count * (varuint string-table index), chain root -> tip. Same string-table
/// packing as blendAxes; matches runtime-nim's writeBonesPayload/readBonesPayload
/// (semantic.nim), including the trailing-bytes check.
List<String> _bIkBones(_BnbObj obj, List<String> strings) {
  final payload = obj.props[_bkBones];
  if (payload == null) {
    throw const FormatException('.bnb ikConstraint.bones is required');
  }
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final out = <String>[];
  for (var i = 0; i < count; i++) {
    out.add(c.readStr(strings));
  }
  _bCheckExhausted(c, 'ikConstraint.bones');
  return out;
}

/// Decode the required clipping-attachment `vertices` payload: a varuint point
/// count followed by count * (f32 x, f32 y) little-endian pairs, returned as a
/// flat [x0, y0, x1, y1, ...] list. Matches runtime-nim's
/// writeClipVerticesPayload / readClipVerticesPayload (semantic.nim), including
/// the trailing-bytes check.
List<double> _bClipVertices(_BnbObj obj) {
  final payload = obj.props[_bkVertices];
  if (payload == null) {
    throw const FormatException('.bnb clippingAttachment.vertices is required');
  }
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final out = <double>[];
  for (var i = 0; i < count; i++) {
    out.add(c.readF32());
    out.add(c.readF32());
  }
  _bCheckExhausted(c, 'clippingAttachment.vertices');
  return out;
}

/// Decode the required mesh `meshVertices` payload. Frozen layout
/// (docs/mesh-attachment-contract.md): varuint vertexCount, then per vertex —
/// unweighted -> (f32 x, f32 y); weighted -> varuint influenceCount then
/// influenceCount * (varuint boneStringIndex, f32 bindX, f32 bindY, f32 weight).
/// Bone names resolve through the same string table as ikConstraint bones.
/// Matches runtime-nim's writeMeshVerticesPayload/readMeshVerticesPayload
/// (semantic.nim), including the trailing-bytes check.
List<MeshVertex> _bMeshVertices(
    _BnbObj obj, bool weighted, List<String> strings) {
  final payload = obj.props[_bkMeshVertices];
  if (payload == null) {
    throw const FormatException('.bnb meshAttachment.vertices is required');
  }
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final out = <MeshVertex>[];
  for (var i = 0; i < count; i++) {
    if (weighted) {
      final influenceCount = c.readVaruint();
      final influences = <MeshInfluence>[];
      for (var k = 0; k < influenceCount; k++) {
        final bone = c.readStr(strings);
        final bindX = c.readF32();
        final bindY = c.readF32();
        final weight = c.readF32();
        influences.add(MeshInfluence(
            bone: bone, bindX: bindX, bindY: bindY, weight: weight));
      }
      out.add(MeshVertex.weighted(influences));
    } else {
      final x = c.readF32();
      final y = c.readF32();
      out.add(MeshVertex.unweighted(x, y));
    }
  }
  _bCheckExhausted(c, 'meshAttachment.vertices');
  return out;
}

/// Decode the required mesh `meshUvs` payload: varuint count then
/// count * (f32 u, f32 v). Matches runtime-nim's writeMeshUvsPayload /
/// readMeshUvsPayload (semantic.nim), including the trailing-bytes check.
List<MeshUv> _bMeshUvs(_BnbObj obj) {
  final payload = obj.props[_bkMeshUvs];
  if (payload == null) {
    throw const FormatException('.bnb meshAttachment.uvs is required');
  }
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final out = <MeshUv>[];
  for (var i = 0; i < count; i++) {
    out.add(MeshUv(c.readF32(), c.readF32()));
  }
  _bCheckExhausted(c, 'meshAttachment.uvs');
  return out;
}

/// Decode the required mesh `meshTriangles` payload: varuint count then
/// count * (varuint vertexIndex). Matches runtime-nim's
/// writeMeshTrianglesPayload / readMeshTrianglesPayload (semantic.nim),
/// including the trailing-bytes check.
List<int> _bMeshTriangles(_BnbObj obj) {
  final payload = obj.props[_bkMeshTriangles];
  if (payload == null) {
    throw const FormatException('.bnb meshAttachment.triangles is required');
  }
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final out = <int>[];
  for (var i = 0; i < count; i++) {
    out.add(c.readVaruint());
  }
  _bCheckExhausted(c, 'meshAttachment.triangles');
  return out;
}

int _bVarint(_BnbObj obj, int key, {int def = 0}) {
  final payload = obj.props[key];
  if (payload == null) return def;
  final c = _BnbCur(payload);
  final v = c.readVarint();
  _bCheckExhausted(c, 'varint');
  return v;
}

int _bVaruint(_BnbObj obj, int key, {int def = 0}) {
  final payload = obj.props[key];
  if (payload == null) return def;
  final c = _BnbCur(payload);
  final v = c.readVaruint();
  _bCheckExhausted(c, 'varuint');
  return v;
}

int _bRequiredVaruint(_BnbObj obj, int key, String ctx) {
  final payload = obj.props[key];
  if (payload == null) {
    throw FormatException('.bnb required property missing: $ctx');
  }
  final c = _BnbCur(payload);
  final v = c.readVaruint();
  _bCheckExhausted(c, ctx);
  return v;
}

// Parse warpControlPoints payload: varuint count, then count*(f32 x, f32 y) pairs.
List<DeformerPoint> _bControlPoints(_BnbObj obj, List<String> strings) {
  final payload = obj.props[_bkWarpControlPoints];
  if (payload == null)
    throw const FormatException('.bnb warpLattice.controlPoints is required');
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final pts = <DeformerPoint>[];
  for (var i = 0; i < count; i++) {
    final x = c.readF32();
    final y = c.readF32();
    pts.add(DeformerPoint(x: x, y: y));
  }
  _bCheckExhausted(c, 'warpControlPoints');
  return pts;
}

// Parse blendAxes payload: varuint count, then count*varuint (string indices).
List<ParameterAxis> _bBlendAxes(
  _BnbObj obj,
  List<String> strings,
  Map<String, ParameterAxis> paramsByName,
) {
  final payload = obj.props[_bkBlendAxes];
  if (payload == null)
    throw const FormatException('.bnb keyformBlend.axes is required');
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final axes = <ParameterAxis>[];
  for (var i = 0; i < count; i++) {
    final name = c.readStr(strings);
    final axis = paramsByName[name];
    if (axis == null) {
      throw FormatException(
          '.bnb keyformBlend references unknown parameter: $name');
    }
    axes.add(axis);
  }
  _bCheckExhausted(c, 'blendAxes');
  return axes;
}

// Parse a flat array of n f32 values from a property payload.
List<double> _bF32Array(_BnbObj obj, int key, int count, String ctx) {
  final payload = obj.props[key];
  if (payload == null)
    throw FormatException('.bnb required property missing: $ctx');
  if (payload.length != count * 4) {
    throw FormatException(
        '.bnb $ctx payload length mismatch: expected ${count * 4}, got ${payload.length}');
  }
  final c = _BnbCur(payload);
  final result = <double>[];
  for (var i = 0; i < count; i++) {
    result.add(c.readF32());
  }
  return result;
}

TimelineCurve _bCurve(_BnbCur c, String ctx) {
  final tag = c.readVaruint();
  switch (tag) {
    case 0:
      return TimelineCurve.linear;
    case 1:
      return TimelineCurve.stepped;
    case 2:
      return TimelineCurve.bezier(
          c.readF32(), c.readF32(), c.readF32(), c.readF32());
    default:
      throw FormatException('.bnb $ctx curve kind is invalid: $tag');
  }
}

BoneTimelineKind _bBoneTimelineKind(int tag) {
  switch (tag) {
    case 0:
      return BoneTimelineKind.rotate;
    case 1:
      return BoneTimelineKind.translate;
    case 2:
      return BoneTimelineKind.translateX;
    case 3:
      return BoneTimelineKind.translateY;
    case 4:
      return BoneTimelineKind.scale;
    case 5:
      return BoneTimelineKind.scaleX;
    case 6:
      return BoneTimelineKind.scaleY;
    case 7:
      return BoneTimelineKind.shear;
    case 8:
      return BoneTimelineKind.shearX;
    case 9:
      return BoneTimelineKind.shearY;
    case 10:
      return BoneTimelineKind.inherit;
    default:
      throw FormatException('.bnb boneTimeline.kind is invalid: $tag');
  }
}

SlotTimelineKind _bSlotTimelineKind(int tag) {
  if (tag < 0 || tag >= SlotTimelineKind.values.length) {
    throw FormatException('.bnb slotTimeline.kind is invalid: $tag');
  }
  return SlotTimelineKind.values[tag];
}

SequenceMode _bSequenceMode(int tag) {
  if (tag < 0 || tag >= SequenceMode.values.length) {
    throw FormatException('.bnb sequence mode is invalid: $tag');
  }
  return SequenceMode.values[tag];
}

String _bTransformMode(int tag) {
  switch (tag) {
    case 0:
      return 'normal';
    case 1:
      return 'onlyTranslation';
    case 2:
      return 'noRotationOrReflection';
    case 3:
      return 'noScale';
    case 4:
      return 'noScaleOrReflection';
    default:
      throw FormatException('.bnb transformMode is invalid: $tag');
  }
}

BoneTimeline _bBoneTimelineKeys(
    String bone, BoneTimelineKind kind, Uint8List payload, String ctx) {
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  if (count == 0)
    throw FormatException('.bnb $ctx must contain at least one key');
  switch (kind) {
    case BoneTimelineKind.translate:
    case BoneTimelineKind.scale:
    case BoneTimelineKind.shear:
      final keys = <Vector2Keyframe>[];
      for (var i = 0; i < count; i++) {
        keys.add(Vector2Keyframe(
          time: c.readF32(),
          x: c.readF32(),
          y: c.readF32(),
          curveX: _bCurve(c, '$ctx.curveX'),
          curveY: _bCurve(c, '$ctx.curveY'),
        ));
      }
      _bCheckExhausted(c, ctx);
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), ctx);
      return BoneTimeline(bone: bone, kind: kind, vectorKeys: keys);
    case BoneTimelineKind.inherit:
      final keys = <InheritKeyframe>[];
      for (var i = 0; i < count; i++) {
        keys.add(InheritKeyframe(
          time: c.readF32(),
          inheritRotation: c.readBool(),
          inheritScale: c.readBool(),
          inheritReflection: c.readBool(),
          transformMode: _bTransformMode(c.readVaruint()),
        ));
      }
      _bCheckExhausted(c, ctx);
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), ctx);
      return BoneTimeline(bone: bone, kind: kind, inheritKeys: keys);
    default:
      final keys = <ScalarKeyframe>[];
      for (var i = 0; i < count; i++) {
        keys.add(ScalarKeyframe(
            time: c.readF32(),
            value: c.readF32(),
            curve: _bCurve(c, '$ctx.curve')));
      }
      _bCheckExhausted(c, ctx);
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), ctx);
      return BoneTimeline(bone: bone, kind: kind, scalarKeys: keys);
  }
}

SlotTimeline _bSlotTimelineKeys(
  String slot,
  SlotTimelineKind kind,
  Uint8List payload,
  List<RegionAttachment> regions,
  String ctx,
) {
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  if (count == 0)
    throw FormatException('.bnb $ctx must contain at least one key');
  switch (kind) {
    case SlotTimelineKind.attachment:
      final keys = <AttachmentKeyframe>[];
      for (var i = 0; i < count; i++) {
        final time = c.readF32();
        final tag = c.readVaruint();
        if (tag == 0) {
          keys.add(AttachmentKeyframe(time: time, attachment: ''));
        } else {
          final index = tag - 1;
          if (index < 0 || index >= regions.length) {
            throw FormatException('.bnb $ctx attachment index is out of range');
          }
          keys.add(
              AttachmentKeyframe(time: time, attachment: regions[index].name));
        }
      }
      _bCheckExhausted(c, ctx);
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), ctx);
      return SlotTimeline(slot: slot, kind: kind, attachmentKeys: keys);
    case SlotTimelineKind.rgba:
    case SlotTimelineKind.rgb:
    case SlotTimelineKind.alpha:
      final keys = <ColorKeyframe>[];
      for (var i = 0; i < count; i++) {
        keys.add(ColorKeyframe(
          time: c.readF32(),
          color: ColorRgba(
              r: c.readF32(), g: c.readF32(), b: c.readF32(), a: c.readF32()),
          curve: _bCurve(c, '$ctx.curve'),
        ));
      }
      _bCheckExhausted(c, ctx);
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), ctx);
      return SlotTimeline(slot: slot, kind: kind, colorKeys: keys);
    case SlotTimelineKind.rgba2:
      final keys = <Color2Keyframe>[];
      for (var i = 0; i < count; i++) {
        final time = c.readF32();
        final light = ColorRgba(
            r: c.readF32(), g: c.readF32(), b: c.readF32(), a: c.readF32());
        keys.add(Color2Keyframe(
          time: time,
          color: ColorRgba2(
              light: light,
              darkR: c.readF32(),
              darkG: c.readF32(),
              darkB: c.readF32()),
          curve: _bCurve(c, '$ctx.curve'),
        ));
      }
      _bCheckExhausted(c, ctx);
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), ctx);
      return SlotTimeline(slot: slot, kind: kind, color2Keys: keys);
    case SlotTimelineKind.sequence:
      final keys = <SequenceKeyframe>[];
      for (var i = 0; i < count; i++) {
        keys.add(SequenceKeyframe(
          time: c.readF32(),
          index: c.readVaruint(),
          delay: c.readF32(),
          mode: _bSequenceMode(c.readVaruint()),
        ));
      }
      _bCheckExhausted(c, ctx);
      _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), ctx);
      return SlotTimeline(slot: slot, kind: kind, sequenceKeys: keys);
  }
}

double _animationDuration(
    List<BoneTimeline> boneTimelines, List<SlotTimeline> slotTimelines) {
  var duration = 0.0;
  for (final timeline in boneTimelines) {
    if (timeline.vectorKeys.isNotEmpty &&
        timeline.vectorKeys.last.time > duration) {
      duration = timeline.vectorKeys.last.time;
    }
    if (timeline.inheritKeys.isNotEmpty &&
        timeline.inheritKeys.last.time > duration) {
      duration = timeline.inheritKeys.last.time;
    }
    if (timeline.scalarKeys.isNotEmpty &&
        timeline.scalarKeys.last.time > duration) {
      duration = timeline.scalarKeys.last.time;
    }
  }
  for (final timeline in slotTimelines) {
    if (timeline.attachmentKeys.isNotEmpty &&
        timeline.attachmentKeys.last.time > duration) {
      duration = timeline.attachmentKeys.last.time;
    }
    if (timeline.colorKeys.isNotEmpty &&
        timeline.colorKeys.last.time > duration) {
      duration = timeline.colorKeys.last.time;
    }
    if (timeline.color2Keys.isNotEmpty &&
        timeline.color2Keys.last.time > duration) {
      duration = timeline.color2Keys.last.time;
    }
    if (timeline.sequenceKeys.isNotEmpty &&
        timeline.sequenceKeys.last.time > duration) {
      duration = timeline.sequenceKeys.last.time;
    }
  }
  return duration;
}

SkeletonData _bnbDecode(List<_BnbObj> objects, List<String> strings) {
  bool isStateMachineObject(_BnbObj obj) =>
      obj.typeKey >= _bnbStateMachine &&
      obj.typeKey <= _bnbStateMachineListener;
  final decodeObjects = [
    ...objects.where((obj) => !isStateMachineObject(obj)),
    ...objects.where(isStateMachineObject),
  ];
  SkeletonHeader? header;
  final bones = <BoneData>[];
  final slots = <SlotData>[];
  final regions = <RegionAttachment>[];
  final paths = <PathConstraintData>[];
  final pathAttachments = <PathAttachment>[];
  final clips = <ClippingAttachment>[];
  final meshes = <MeshAttachment>[];
  final ikConstraints = <IkConstraintData>[];
  final transformConstraints = <TransformConstraintData>[];
  final physicsConstraints = <PhysicsConstraintData>[];
  final parameters = <ParameterAxis>[];
  final deformers = <DeformerRecord>[];
  final animations = <AnimationClip>[];
  final stateMachines = <StateMachineData>[];
  var currentAnimationName = '';
  var currentBoneTimelines = <BoneTimeline>[];
  var currentSlotTimelines = <SlotTimeline>[];
  var currentMachineName = '';
  var machineInputs = <StateMachineInput>[];
  var machineLayers = <StateMachineLayer>[];
  var machineListeners = <StateMachineListener>[];
  var currentLayerName = '';
  var currentLayerInitialIndex = 0;
  var currentLayerStates = <StateMachineState>[];
  var currentLayerTransitions = <StateMachineTransition>[];
  var pendingTransitionFrom = '';
  var pendingTransitionTo = '';
  var pendingConditions = <StateMachineCondition>[];
  final seenAnimationNames = <String>{};

  void flushAnimation() {
    if (currentAnimationName.isEmpty) return;
    if (!seenAnimationNames.add(currentAnimationName)) {
      throw FormatException('duplicate animation name: $currentAnimationName');
    }
    animations.add(AnimationClip(
      name: currentAnimationName,
      duration: _animationDuration(currentBoneTimelines, currentSlotTimelines),
      boneTimelines: currentBoneTimelines,
      slotTimelines: currentSlotTimelines,
    ));
    currentAnimationName = '';
    currentBoneTimelines = [];
    currentSlotTimelines = [];
  }

  String stateNameAt(List<StateMachineState> states, int index, String ctx) {
    if (index < 0 || index >= states.length) {
      throw FormatException('.bnb $ctx state index is out of range');
    }
    return states[index].name;
  }

  void flushTransition() {
    if (pendingTransitionFrom.isEmpty) return;
    currentLayerTransitions.add(StateMachineTransition(
      fromState: pendingTransitionFrom,
      toState: pendingTransitionTo,
      conditions: pendingConditions,
    ));
    pendingTransitionFrom = '';
    pendingTransitionTo = '';
    pendingConditions = [];
  }

  void flushLayer() {
    if (currentLayerName.isEmpty) return;
    flushTransition();
    machineLayers.add(StateMachineLayer(
      name: currentLayerName,
      states: currentLayerStates,
      initialState: stateNameAt(currentLayerStates, currentLayerInitialIndex,
          'stateMachineLayer.initialStateIndex'),
      transitions: currentLayerTransitions,
    ));
    currentLayerName = '';
    currentLayerInitialIndex = 0;
    currentLayerStates = [];
    currentLayerTransitions = [];
  }

  void flushMachine() {
    if (currentMachineName.isEmpty) return;
    flushLayer();
    stateMachines.add(StateMachineData(
      name: currentMachineName,
      layers: machineLayers,
      inputs: machineInputs,
      listeners: machineListeners,
    ));
    currentMachineName = '';
    machineInputs = [];
    machineLayers = [];
    machineListeners = [];
  }

  // M7 deformer state machine — mirrors Nim semantic.nim decodeSkeletonObjects.
  var deformerPending = false;
  var pendingId = '';
  var pendingParent = '';
  var pendingOrder = 0;
  var pendingKind = DeformerKind.warp;
  WarpLattice? pendingWarp;
  RotationDeformerData? pendingRotation;
  var geometryReady = false;
  var blendPending = false;
  var pendingBlendValueCount = 0;
  var pendingBlendAxes = <ParameterAxis>[];
  var pendingKeyforms = <Keyform>[];

  void flushPending() {
    if (!deformerPending) return;
    if (!geometryReady) {
      throw const FormatException(
          '.bnb deformer header has no following geometry record');
    }
    final DeformerData deformerData;
    if (pendingKind == DeformerKind.warp) {
      deformerData = DeformerData(
        id: pendingId,
        parent: pendingParent,
        order: pendingOrder,
        kind: DeformerKind.warp,
        warp: pendingWarp!,
      );
    } else {
      deformerData = DeformerData(
        id: pendingId,
        parent: pendingParent,
        order: pendingOrder,
        kind: DeformerKind.rotation,
        rotation: pendingRotation!,
      );
    }
    final blend = blendPending && pendingBlendAxes.isNotEmpty
        ? KeyformBlend(
            axes: pendingBlendAxes,
            valueCount: pendingBlendValueCount,
            keyforms: pendingKeyforms,
          )
        : const KeyformBlend();
    deformers.add(DeformerRecord(deformer: deformerData, keyformBlend: blend));
    deformerPending = false;
    geometryReady = false;
    blendPending = false;
    pendingBlendAxes = [];
    pendingKeyforms = [];
  }

  final paramsByName = <String, ParameterAxis>{};

  for (final obj in decodeObjects) {
    switch (obj.typeKey) {
      case _bnbSkeleton:
        flushPending();
        if (header != null)
          throw const FormatException('.bnb: multiple skeleton objects');
        header = SkeletonHeader(
          name: _bStr(obj, _bkName, strings, 'skeleton.name'),
          version:
              _bStr(obj, _bkVersion, strings, 'skeleton.version', def: '0.1.0'),
        );
      case _bnbBone:
        flushPending();
        bones.add(BoneData(
          name: _bStr(obj, _bkName, strings, 'bone.name'),
          parent: _bStr(obj, _bkParent, strings, 'bone.parent', def: ''),
          x: _bF32(obj, _bkX, 'bone.x', def: 0.0),
          y: _bF32(obj, _bkY, 'bone.y', def: 0.0),
          rotation: _bF32(obj, _bkRotation, 'bone.rotation', def: 0.0),
          scaleX: _bF32(obj, _bkScaleX, 'bone.scaleX', def: 1.0),
          scaleY: _bF32(obj, _bkScaleY, 'bone.scaleY', def: 1.0),
          shearX: _bF32(obj, _bkShearX, 'bone.shearX', def: 0.0),
          shearY: _bF32(obj, _bkShearY, 'bone.shearY', def: 0.0),
          inheritRotation: _bBool(obj, _bkInheritRotation, def: true),
          inheritScale: _bBool(obj, _bkInheritScale, def: true),
          inheritReflection: _bBool(obj, _bkInheritReflection, def: true),
          transformMode: _bStr(
              obj, _bkTransformMode, strings, 'bone.transformMode',
              def: 'normal'),
        ));
      case _bnbSlot:
        flushPending();
        slots.add(SlotData(
          name: _bStr(obj, _bkName, strings, 'slot.name'),
          bone: _bStr(obj, _bkBone, strings, 'slot.bone'),
          attachment:
              _bStr(obj, _bkAttachment, strings, 'slot.attachment', def: ''),
        ));
      case _bnbRegion:
        flushPending();
        regions.add(RegionAttachment(
          name: _bStr(obj, _bkName, strings, 'region.name'),
          width: _bF32(obj, _bkWidth, 'region.width'),
          height: _bF32(obj, _bkHeight, 'region.height'),
        ));
      case _bnbClippingAttachment:
        flushPending();
        clips.add(ClippingAttachment(
          name: _bStr(obj, _bkName, strings, 'clippingAttachment.name'),
          vertices: _bClipVertices(obj),
          untilSlot: _bStr(obj, _bkUntilSlot, strings,
              'clippingAttachment.untilSlot',
              def: ''),
        ));
      case _bnbMeshAttachment:
        flushPending();
        final meshWeighted = _bBool(obj, _bkMeshWeighted, def: false);
        meshes.add(MeshAttachment(
          name: _bStr(obj, _bkName, strings, 'meshAttachment.name'),
          weighted: meshWeighted,
          vertices: _bMeshVertices(obj, meshWeighted, strings),
          uvs: _bMeshUvs(obj),
          triangles: _bMeshTriangles(obj),
        ));
      case _bnbPath:
        flushPending();
        paths.add(PathConstraintData(
          name: _bStr(obj, _bkName, strings, 'path.name'),
          bone: _bStr(obj, _bkBone, strings, 'path.bone'),
          target: _bStr(obj, _bkTarget, strings, 'path.target'),
          path: _bStr(obj, _bkPath, strings, 'path.path'),
          order: _bVarint(obj, _bkOrder, def: 0),
          position: obj.props.containsKey(_bkPosition)
              ? _bF32(obj, _bkPosition, 'path.position')
              : null,
          translateMix: obj.props.containsKey(_bkTranslateMix)
              ? _bF32(obj, _bkTranslateMix, 'path.translateMix')
              : null,
          rotateMix: obj.props.containsKey(_bkRotateMix)
              ? _bF32(obj, _bkRotateMix, 'path.rotateMix')
              : null,
        ));
      case _bnbIkConstraint:
        flushPending();
        ikConstraints.add(IkConstraintData(
          name: _bStr(obj, _bkName, strings, 'ikConstraint.name'),
          bones: _bIkBones(obj, strings),
          target: _bStr(obj, _bkTarget, strings, 'ikConstraint.target'),
          order: _bVarint(obj, _bkOrder, def: 0),
          // Absent => null (mix defaults to 1.0, bendPositive to true).
          mix: obj.props.containsKey(_bkMix)
              ? _bF32(obj, _bkMix, 'ikConstraint.mix')
              : null,
          bendPositive: obj.props.containsKey(_bkBendPositive)
              ? _bBool(obj, _bkBendPositive)
              : null,
        ));
      case _bnbTransformConstraint:
        flushPending();
        transformConstraints.add(TransformConstraintData(
          name: _bStr(obj, _bkName, strings, 'transformConstraint.name'),
          bone: _bStr(obj, _bkBone, strings, 'transformConstraint.bone'),
          target: _bStr(obj, _bkTarget, strings, 'transformConstraint.target'),
          order: _bVarint(obj, _bkOrder, def: 0),
          // Absent => null (each mix defaults to 1.0).
          translateMix: obj.props.containsKey(_bkTranslateMix)
              ? _bF32(obj, _bkTranslateMix, 'transformConstraint.translateMix')
              : null,
          rotateMix: obj.props.containsKey(_bkRotateMix)
              ? _bF32(obj, _bkRotateMix, 'transformConstraint.rotateMix')
              : null,
          scaleMix: obj.props.containsKey(_bkScaleMix)
              ? _bF32(obj, _bkScaleMix, 'transformConstraint.scaleMix')
              : null,
          shearMix: obj.props.containsKey(_bkShearMix)
              ? _bF32(obj, _bkShearMix, 'transformConstraint.shearMix')
              : null,
        ));
      case _bnbPhysicsConstraint:
        flushPending();
        if (!obj.props.containsKey(_bkChannels)) {
          throw const FormatException(
              '.bnb physicsConstraint.channels is required');
        }
        physicsConstraints.add(PhysicsConstraintData(
          name: _bStr(obj, _bkName, strings, 'physicsConstraint.name'),
          bone: _bStr(obj, _bkBone, strings, 'physicsConstraint.bone'),
          // channels is an unsigned varuint bitmask (NOT the signed/zigzag
          // varint used by `order`), matching generated/wire.dart's varuint
          // backingType and the Nim writeVaruintPayload emission.
          channels: physicsChannelsFromMask(_bVaruint(obj, _bkChannels)),
          order: _bVarint(obj, _bkOrder, def: 0),
          // Absent => null (integrator defaults: mass=1.0/physicsMix=1.0/rest 0.0).
          inertia: obj.props.containsKey(_bkInertia)
              ? _bF32(obj, _bkInertia, 'physicsConstraint.inertia')
              : null,
          strength: obj.props.containsKey(_bkStrength)
              ? _bF32(obj, _bkStrength, 'physicsConstraint.strength')
              : null,
          damping: obj.props.containsKey(_bkDamping)
              ? _bF32(obj, _bkDamping, 'physicsConstraint.damping')
              : null,
          mass: obj.props.containsKey(_bkMass)
              ? _bF32(obj, _bkMass, 'physicsConstraint.mass')
              : null,
          gravity: obj.props.containsKey(_bkGravity)
              ? _bF32(obj, _bkGravity, 'physicsConstraint.gravity')
              : null,
          wind: obj.props.containsKey(_bkWind)
              ? _bF32(obj, _bkWind, 'physicsConstraint.wind')
              : null,
          physicsMix: obj.props.containsKey(_bkPhysicsMix)
              ? _bF32(obj, _bkPhysicsMix, 'physicsConstraint.physicsMix')
              : null,
        ));
      case _bnbPathAttachment:
        flushPending();
        pathAttachments.add(PathAttachment(
          name: _bStr(obj, _bkName, strings, 'pathAttachment.name'),
          p0x: _bF64(obj, _bkP0x, 'pathAttachment.p0x'),
          p0y: _bF64(obj, _bkP0y, 'pathAttachment.p0y'),
          p1x: _bF64(obj, _bkP1x, 'pathAttachment.p1x'),
          p1y: _bF64(obj, _bkP1y, 'pathAttachment.p1y'),
          p2x: _bF64(obj, _bkP2x, 'pathAttachment.p2x'),
          p2y: _bF64(obj, _bkP2y, 'pathAttachment.p2y'),
          p3x: _bF64(obj, _bkP3x, 'pathAttachment.p3x'),
          p3y: _bF64(obj, _bkP3y, 'pathAttachment.p3y'),
        ));
      // --- M7 objects ---
      case _bnbParameter:
        flushPending();
        final name = _bStr(obj, _bkName, strings, 'parameter.name');
        final min = _bF32(obj, _bkParamMin, 'parameter.min');
        final max = _bF32(obj, _bkParamMax, 'parameter.max');
        final def = obj.props.containsKey(_bkParamDefault)
            ? _bF32(obj, _bkParamDefault, 'parameter.default')
            : 0.0;
        final axis = ParameterAxis(
          name: name,
          minValue: min,
          maxValue: max,
          defaultValue: def,
        );
        parameters.add(axis);
        paramsByName[name] = axis;
      case _bnbDeformer:
        flushPending();
        pendingId = _bStr(obj, _bkDefId, strings, 'deformer.id');
        pendingParent =
            _bStr(obj, _bkParent, strings, 'deformer.parent', def: '');
        pendingOrder = _bVaruint(obj, _bkDefOrder, def: 0);
        final kindStr = _bStr(obj, _bkDefKind, strings, 'deformer.kind');
        if (kindStr == 'warp') {
          pendingKind = DeformerKind.warp;
        } else if (kindStr == 'rotation') {
          pendingKind = DeformerKind.rotation;
        } else {
          throw FormatException(
              '.bnb deformer.kind must be warp or rotation: $kindStr');
        }
        deformerPending = true;
        geometryReady = false;
        blendPending = false;
        pendingBlendAxes = [];
        pendingKeyforms = [];
      case _bnbWarpLattice:
        if (!deformerPending || pendingKind != DeformerKind.warp) {
          throw const FormatException(
              '.bnb warpLattice without preceding warp deformer');
        }
        pendingWarp = WarpLattice(
          rows: _bVaruint(obj, _bkWarpRows, def: 2),
          cols: _bVaruint(obj, _bkWarpCols, def: 2),
          minX: _bF32(obj, _bkWarpMinX, 'warpLattice.minX'),
          minY: _bF32(obj, _bkWarpMinY, 'warpLattice.minY'),
          maxX: _bF32(obj, _bkWarpMaxX, 'warpLattice.maxX'),
          maxY: _bF32(obj, _bkWarpMaxY, 'warpLattice.maxY'),
          controlPoints: _bControlPoints(obj, strings),
        );
        geometryReady = true;
      case _bnbRotationDeformer:
        if (!deformerPending || pendingKind != DeformerKind.rotation) {
          throw const FormatException(
              '.bnb rotationDeformer without preceding rotation deformer');
        }
        pendingRotation = RotationDeformerData(
          pivotX: _bF32(obj, _bkRotPivotX, 'rotationDeformer.pivotX'),
          pivotY: _bF32(obj, _bkRotPivotY, 'rotationDeformer.pivotY'),
          angleDegrees:
              _bF32(obj, _bkRotAngle, 'rotationDeformer.angleDegrees'),
          scaleX: _bF32(obj, _bkRotScaleX, 'rotationDeformer.scaleX', def: 1.0),
          scaleY: _bF32(obj, _bkRotScaleY, 'rotationDeformer.scaleY', def: 1.0),
          opacity:
              _bF32(obj, _bkRotOpacity, 'rotationDeformer.opacity', def: 1.0),
        );
        geometryReady = true;
      case _bnbKeyformBlend:
        if (!deformerPending || !geometryReady) {
          throw const FormatException(
              '.bnb keyformBlend without preceding deformer geometry');
        }
        pendingBlendValueCount = _bVaruint(obj, _bkBlendValueCount, def: 0);
        pendingBlendAxes = _bBlendAxes(obj, strings, paramsByName);
        pendingKeyforms = [];
        blendPending = true;
      case _bnbKeyform:
        if (!blendPending) {
          throw const FormatException(
              '.bnb keyform without preceding keyformBlend');
        }
        final coordVals = _bF32Array(obj, _bkBlendCoords,
            pendingBlendAxes.length, 'keyform.coordinates');
        final values = _bF32Array(
            obj, _bkBlendValues, pendingBlendValueCount, 'keyform.values');
        final coordinates = [
          for (var i = 0; i < pendingBlendAxes.length; i++)
            ParameterSample(
                name: pendingBlendAxes[i].name, value: coordVals[i]),
        ];
        pendingKeyforms.add(Keyform(coordinates: coordinates, values: values));
      case _bnbAnimationClip:
        flushPending();
        flushAnimation();
        currentAnimationName =
            _bStr(obj, _bkName, strings, 'animationClip.name');
      case _bnbBoneTimeline:
        flushPending();
        if (currentAnimationName.isEmpty)
          throw const FormatException(
              '.bnb boneTimeline without animationClip');
        final boneIndex = _bVaruint(obj, _bkBoneIndex);
        if (boneIndex < 0 || boneIndex >= bones.length) {
          throw const FormatException(
              '.bnb boneTimeline.boneIndex is out of range');
        }
        final payload = obj.props[_bkTimelineKeys];
        if (payload == null)
          throw const FormatException(
              '.bnb boneTimeline.timelineKeys is required');
        currentBoneTimelines.add(_bBoneTimelineKeys(
          bones[boneIndex].name,
          _bBoneTimelineKind(
              _bRequiredVaruint(obj, _bkBoneTimelineKind, 'boneTimeline.kind')),
          payload,
          'boneTimeline.timelineKeys',
        ));
      case _bnbSlotTimeline:
        flushPending();
        if (currentAnimationName.isEmpty)
          throw const FormatException(
              '.bnb slotTimeline without animationClip');
        final slotIndex = _bVaruint(obj, _bkSlotIndex);
        if (slotIndex < 0 || slotIndex >= slots.length) {
          throw const FormatException(
              '.bnb slotTimeline.slotIndex is out of range');
        }
        final payload = obj.props[_bkTimelineKeys];
        if (payload == null)
          throw const FormatException(
              '.bnb slotTimeline.timelineKeys is required');
        currentSlotTimelines.add(_bSlotTimelineKeys(
          slots[slotIndex].name,
          _bSlotTimelineKind(
              _bRequiredVaruint(obj, _bkSlotTimelineKind, 'slotTimeline.kind')),
          payload,
          regions,
          'slotTimeline.timelineKeys',
        ));
      case _bnbStateMachine:
        flushPending();
        flushAnimation();
        flushMachine();
        currentMachineName = _bStr(obj, _bkName, strings, 'stateMachine.name');
      case _bnbStateMachineInput:
        flushPending();
        flushLayer();
        if (currentMachineName.isEmpty)
          throw const FormatException(
              '.bnb stateMachineInput without stateMachine');
        final kindTag = _bRequiredVaruint(
            obj, _bkStateMachineInputKind, 'stateMachineInput.kind');
        final name = _bStr(obj, _bkName, strings, 'stateMachineInput.name');
        switch (kindTag) {
          case 0:
            if (obj.props.containsKey(_bkInputDefaultNumber)) {
              throw const FormatException(
                  '.bnb bool input must not contain number default');
            }
            machineInputs.add(StateMachineInput(
              name: name,
              kind: StateMachineInputKind.bool_,
              defaultBool: _bBool(obj, _bkInputDefaultBool),
            ));
          case 1:
            if (obj.props.containsKey(_bkInputDefaultBool)) {
              throw const FormatException(
                  '.bnb number input must not contain bool default');
            }
            machineInputs.add(StateMachineInput(
              name: name,
              kind: StateMachineInputKind.number,
              defaultNumber: _bF32(
                  obj, _bkInputDefaultNumber, 'stateMachineInput.defaultNumber',
                  def: 0.0),
            ));
          case 2:
            if (obj.props.containsKey(_bkInputDefaultBool) ||
                obj.props.containsKey(_bkInputDefaultNumber)) {
              throw const FormatException(
                  '.bnb trigger input must not contain defaults');
            }
            machineInputs.add(StateMachineInput(
                name: name, kind: StateMachineInputKind.trigger));
          default:
            throw FormatException(
                '.bnb stateMachineInput.kind is invalid: $kindTag');
        }
      case _bnbStateMachineLayer:
        flushPending();
        flushLayer();
        if (currentMachineName.isEmpty)
          throw const FormatException(
              '.bnb stateMachineLayer without stateMachine');
        currentLayerName =
            _bStr(obj, _bkName, strings, 'stateMachineLayer.name');
        currentLayerInitialIndex = _bVaruint(obj, _bkInitialStateIndex);
      case _bnbStateMachineState:
        flushPending();
        flushTransition();
        if (currentLayerName.isEmpty)
          throw const FormatException('.bnb stateMachineState without layer');
        final stateName =
            _bStr(obj, _bkName, strings, 'stateMachineState.name');
        final kindTag = _bRequiredVaruint(
            obj, _bkStateMachineStateKind, 'stateMachineState.kind');
        switch (kindTag) {
          case 0:
            if (obj.props.containsKey(_bkStateBlendInputIndex)) {
              throw const FormatException(
                  '.bnb clip state must not contain blend input');
            }
            final clipIndex = _bRequiredVaruint(
                obj, _bkStateClipIndex, 'stateMachineState.clip');
            if (clipIndex < 0 || clipIndex >= animations.length) {
              throw const FormatException(
                  '.bnb stateMachineState.clip index is out of range');
            }
            currentLayerStates.add(StateMachineState(
              name: stateName,
              kind: StateMachineStateKind.clip,
              clipName: animations[clipIndex].name,
              loop: _bBool(obj, _bkStateLoop),
            ));
          case 1:
            if (obj.props.containsKey(_bkStateClipIndex) ||
                obj.props.containsKey(_bkStateLoop)) {
              throw const FormatException(
                  '.bnb blend1d state must not contain direct clip fields');
            }
            final inputIndex = _bRequiredVaruint(
                obj, _bkStateBlendInputIndex, 'stateMachineState.blendInput');
            if (inputIndex < 0 || inputIndex >= machineInputs.length) {
              throw const FormatException(
                  '.bnb stateMachineState.blendInput index is out of range');
            }
            currentLayerStates.add(StateMachineState(
              name: stateName,
              kind: StateMachineStateKind.blend1d,
              blendInput: machineInputs[inputIndex].name,
              blendClips: <StateMachineBlendClip>[],
            ));
          default:
            throw FormatException(
                '.bnb stateMachineState.kind is invalid: $kindTag');
        }
      case _bnbStateMachineBlendClip:
        flushPending();
        if (currentLayerStates.isEmpty ||
            currentLayerStates.last.kind != StateMachineStateKind.blend1d) {
          throw const FormatException(
              '.bnb stateMachineBlendClip without blend1d state');
        }
        final clipIndex = _bRequiredVaruint(
            obj, _bkBlendClipAnimationIndex, 'stateMachineBlendClip.animation');
        if (clipIndex < 0 || clipIndex >= animations.length) {
          throw const FormatException(
              '.bnb stateMachineBlendClip.animation index is out of range');
        }
        final previous = currentLayerStates.removeLast();
        currentLayerStates.add(StateMachineState(
          name: previous.name,
          kind: previous.kind,
          blendInput: previous.blendInput,
          blendClips: [
            ...previous.blendClips,
            StateMachineBlendClip(
              clipName: animations[clipIndex].name,
              value:
                  _bF32(obj, _bkBlendClipValue, 'stateMachineBlendClip.value'),
              loop: _bBool(obj, _bkBlendClipLoop),
            ),
          ],
        ));
      case _bnbStateMachineTransition:
        flushPending();
        flushTransition();
        if (currentLayerName.isEmpty)
          throw const FormatException(
              '.bnb stateMachineTransition without layer');
        pendingTransitionFrom = stateNameAt(
            currentLayerStates,
            _bRequiredVaruint(obj, _bkTransitionFromStateIndex,
                'stateMachineTransition.from'),
            'stateMachineTransition.from');
        pendingTransitionTo = stateNameAt(
            currentLayerStates,
            _bRequiredVaruint(
                obj, _bkTransitionToStateIndex, 'stateMachineTransition.to'),
            'stateMachineTransition.to');
      case _bnbStateMachineCondition:
        flushPending();
        if (pendingTransitionFrom.isEmpty)
          throw const FormatException(
              '.bnb stateMachineCondition without transition');
        final inputIndex = _bRequiredVaruint(
            obj, _bkConditionInputIndex, 'stateMachineCondition.input');
        if (inputIndex < 0 || inputIndex >= machineInputs.length) {
          throw const FormatException(
              '.bnb stateMachineCondition.input index is out of range');
        }
        final input = machineInputs[inputIndex];
        final kindTag = _bRequiredVaruint(
            obj, _bkStateMachineConditionKind, 'stateMachineCondition.kind');
        switch (kindTag) {
          case 0:
            if (obj.props.containsKey(_bkConditionNumberValue)) {
              throw const FormatException(
                  '.bnb bool condition must not contain number value');
            }
            pendingConditions.add(StateMachineCondition(
              input: input.name,
              kind: StateMachineConditionKind.boolEquals,
              boolValue: _bBool(obj, _bkConditionBoolValue, def: true),
            ));
          case 1:
            if (obj.props.containsKey(_bkConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberEquals,
                numberValue:
                    _bF32(obj, _bkConditionNumberValue, 'condition.number')));
          case 2:
            if (obj.props.containsKey(_bkConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberGreater,
                numberValue:
                    _bF32(obj, _bkConditionNumberValue, 'condition.number')));
          case 3:
            if (obj.props.containsKey(_bkConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberGreaterOrEqual,
                numberValue:
                    _bF32(obj, _bkConditionNumberValue, 'condition.number')));
          case 4:
            if (obj.props.containsKey(_bkConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberLess,
                numberValue:
                    _bF32(obj, _bkConditionNumberValue, 'condition.number')));
          case 5:
            if (obj.props.containsKey(_bkConditionBoolValue)) {
              throw const FormatException(
                  '.bnb number condition must not contain bool value');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name,
                kind: StateMachineConditionKind.numberLessOrEqual,
                numberValue:
                    _bF32(obj, _bkConditionNumberValue, 'condition.number')));
          case 6:
            if (obj.props.containsKey(_bkConditionBoolValue) ||
                obj.props.containsKey(_bkConditionNumberValue)) {
              throw const FormatException(
                  '.bnb trigger condition must not contain values');
            }
            pendingConditions.add(StateMachineCondition(
                input: input.name, kind: StateMachineConditionKind.triggerSet));
          default:
            throw FormatException(
                '.bnb stateMachineCondition.kind is invalid: $kindTag');
        }
      case _bnbStateMachineListener:
        flushPending();
        flushLayer();
        if (currentMachineName.isEmpty)
          throw const FormatException(
              '.bnb stateMachineListener without stateMachine');
        final listenerName =
            _bStr(obj, _bkName, strings, 'stateMachineListener.name');
        final layerIndex = _bRequiredVaruint(
            obj, _bkListenerLayerIndex, 'stateMachineListener.layer');
        if (layerIndex < 0 || layerIndex >= machineLayers.length) {
          throw const FormatException(
              '.bnb stateMachineListener.layer index is out of range');
        }
        final layer = machineLayers[layerIndex];
        final kindTag = _bRequiredVaruint(
            obj, _bkStateMachineListenerKind, 'stateMachineListener.kind');
        switch (kindTag) {
          case 0:
            if (obj.props.containsKey(_bkListenerFromStateIndex)) {
              throw const FormatException(
                  '.bnb enter listener must not contain from state');
            }
            machineListeners.add(StateMachineListener(
              name: listenerName,
              kind: StateMachineListenerKind.stateEnter,
              layer: layer.name,
              toState: stateNameAt(
                  layer.states,
                  _bRequiredVaruint(
                      obj, _bkListenerToStateIndex, 'stateMachineListener.to'),
                  'stateMachineListener.to'),
            ));
          case 1:
            if (obj.props.containsKey(_bkListenerToStateIndex)) {
              throw const FormatException(
                  '.bnb exit listener must not contain to state');
            }
            machineListeners.add(StateMachineListener(
              name: listenerName,
              kind: StateMachineListenerKind.stateExit,
              layer: layer.name,
              fromState: stateNameAt(
                  layer.states,
                  _bRequiredVaruint(obj, _bkListenerFromStateIndex,
                      'stateMachineListener.from'),
                  'stateMachineListener.from'),
            ));
          case 2:
            machineListeners.add(StateMachineListener(
              name: listenerName,
              kind: StateMachineListenerKind.transition_,
              layer: layer.name,
              fromState: stateNameAt(
                  layer.states,
                  _bRequiredVaruint(obj, _bkListenerFromStateIndex,
                      'stateMachineListener.from'),
                  'stateMachineListener.from'),
              toState: stateNameAt(
                  layer.states,
                  _bRequiredVaruint(
                      obj, _bkListenerToStateIndex, 'stateMachineListener.to'),
                  'stateMachineListener.to'),
            ));
          default:
            throw FormatException(
                '.bnb stateMachineListener.kind is invalid: $kindTag');
        }
    }
  }
  flushPending();
  flushAnimation();
  flushMachine();

  if (header == null)
    throw const FormatException('.bnb: missing skeleton object');
  return SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    clippingAttachments: clips,
    meshAttachments: meshes,
    ikConstraints: ikConstraints,
    transformConstraints: transformConstraints,
    physicsConstraints: physicsConstraints,
    parameters: parameters,
    deformers: deformers,
    animations: animations,
    stateMachines: stateMachines,
  );
}

/// Parse a bony binary (.bnb) byte buffer into a [SkeletonData].
///
/// Throws [FormatException] on any framing error, missing required field, or
/// structural validation failure (same rules as [loadBonyJson]).
SkeletonData loadBonyBnb(Uint8List bytes) {
  final c = _BnbCur(bytes);

  c._need(4, '.bnb fingerprint');
  if (c.data[0] != 0x42 ||
      c.data[1] != 0x4f ||
      c.data[2] != 0x4e ||
      c.data[3] != 0x59) {
    throw const FormatException('invalid .bnb fingerprint (expected BONY)');
  }
  c.pos = 4;

  final version = c.readVaruint();
  final major = (version >> 16) & 0xffff;
  if (major != 0)
    throw FormatException('unsupported .bnb major version: $major');

  final flags = c.readVaruint();
  if ((flags & ~0x3) != 0)
    throw const FormatException('unknown .bnb header flags');

  // ToC: varuint count then (propKey, u8 backingType) pairs.
  // We read it to advance past it; actual type info is in the payload lengths.
  final tocCount = c.readVaruint();
  for (var i = 0; i < tocCount; i++) {
    c.readVaruint(); // propKey — not used for decoding
    c._need(1, '.bnb ToC backingType');
    c.pos++; // backingType byte
  }

  final strings = (flags & 2) != 0 ? _bnbReadStrings(c) : <String>[];
  final objects = _bnbReadObjects(c);
  final data = _bnbDecode(objects, strings);
  _validate(data);
  return data;
}

// ===========================================================================
// JSON loader
// ===========================================================================

/// Parse a bony JSON string into a [SkeletonData].
///
/// Throws [FormatException] if required fields are missing, have the wrong
/// type, or fail structural validation (unknown references, duplicate names,
/// parent-before-child ordering).
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
    final llayer = _required<String>(lm['layer'], 'listener.layer');
    switch (lkind) {
      case 'stateEnter':
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.stateEnter,
          layer: llayer,
          toState: _required<String>(lm['toState'], 'listener.toState'),
        );
      case 'stateExit':
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.stateExit,
          layer: llayer,
          fromState: _required<String>(lm['fromState'], 'listener.fromState'),
        );
      case 'transition':
        return StateMachineListener(
          name: lname,
          kind: StateMachineListenerKind.transition_,
          layer: llayer,
          fromState: _required<String>(lm['fromState'], 'listener.fromState'),
          toState: _required<String>(lm['toState'], 'listener.toState'),
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

SkeletonData loadBonyJson(String jsonText) {
  final root = jsonDecode(jsonText);
  if (root is! Map<String, dynamic>) {
    throw const FormatException('bony JSON root must be an object');
  }

  final skelJson = root['skeleton'];
  if (skelJson is! Map<String, dynamic>) {
    throw const FormatException('missing required field: skeleton');
  }
  final header = SkeletonHeader(
    name: _required<String>(skelJson['name'], 'skeleton.name'),
    version: (skelJson['version'] as String?) ?? '0.1.0',
  );

  final bonesRaw = root['bones'];
  if (bonesRaw is! List<dynamic>) {
    throw const FormatException('missing required field: bones');
  }
  final bones =
      bonesRaw.map((b) => _parseBone(b as Map<String, dynamic>)).toList();

  final slots = ((root['slots'] as List<dynamic>?) ?? [])
      .map((s) => _parseSlot(s as Map<String, dynamic>))
      .toList();

  final regions = ((root['regions'] as List<dynamic>?) ?? [])
      .map((r) => _parseRegion(r as Map<String, dynamic>))
      .toList();

  final paths = ((root['paths'] as List<dynamic>?) ?? [])
      .map((p) => _parsePath(p as Map<String, dynamic>))
      .toList();

  final pathAttachments = ((root['pathAttachments'] as List<dynamic>?) ?? [])
      .map((pa) => _parsePathAttachment(pa as Map<String, dynamic>))
      .toList();

  final clippingAttachments =
      ((root['clippingAttachments'] as List<dynamic>?) ?? [])
          .map((c) => _parseClippingAttachment(c as Map<String, dynamic>))
          .toList();

  final meshAttachments =
      ((root['meshAttachments'] as List<dynamic>?) ?? [])
          .map((m) => _parseMeshAttachment(m as Map<String, dynamic>))
          .toList();

  final ikConstraints = ((root['ikConstraints'] as List<dynamic>?) ?? [])
      .map((ik) => _parseIk(ik as Map<String, dynamic>))
      .toList();

  final transformConstraints =
      ((root['transformConstraints'] as List<dynamic>?) ?? [])
          .map((tc) => _parseTransform(tc as Map<String, dynamic>))
          .toList();

  final physicsConstraints =
      ((root['physicsConstraints'] as List<dynamic>?) ?? [])
          .map((pc) => _parsePhysics(pc as Map<String, dynamic>))
          .toList();

  final animsRaw = root['animations'];
  final animations = animsRaw is List<dynamic>
      ? _parseAnimations(animsRaw)
      : const <AnimationClip>[];

  final paramsRaw = root['parameters'];
  final parameters = paramsRaw is List<dynamic>
      ? paramsRaw
          .map((p) => _parseParameter(p as Map<String, dynamic>))
          .toList()
      : const <ParameterAxis>[];

  final paramsByName = <String, ParameterAxis>{
    for (final p in parameters) p.name: p,
  };
  final deformersRaw = root['deformers'];
  final deformers = deformersRaw is List<dynamic>
      ? deformersRaw
          .map((d) => _parseDeformer(d as Map<String, dynamic>, paramsByName))
          .toList()
      : const <DeformerRecord>[];

  final smRaw = root['stateMachines'];
  final stateMachines = smRaw is List<dynamic>
      ? smRaw
          .map((sm) => _parseStateMachine(sm as Map<String, dynamic>))
          .toList()
      : const <StateMachineData>[];

  final data = SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    clippingAttachments: clippingAttachments,
    meshAttachments: meshAttachments,
    ikConstraints: ikConstraints,
    transformConstraints: transformConstraints,
    physicsConstraints: physicsConstraints,
    animations: animations,
    parameters: parameters,
    deformers: deformers,
    stateMachines: stateMachines,
  );
  _validate(data);
  return data;
}
