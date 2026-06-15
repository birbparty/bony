// .bony JSON loader and .bnb binary loader.
//
// Defaults follow the values in the generated registry (bonyPropertyDefaults).

import 'dart:convert';
import 'dart:typed_data' show Uint8List, ByteData, Endian;
import 'model.dart';

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

PathConstraintData _parsePath(Map<String, dynamic> j) {
  return PathConstraintData(
    name: _required<String>(j['name'], 'path.name'),
    bone: _required<String>(j['bone'], 'path.bone'),
    target: _required<String>(j['target'], 'path.target'),
    path: _required<String>(j['path'], 'path.path'),
    // JSON doesn't distinguish int from double; toInt() handles "order": 0.0.
    order: (j['order'] as num?)?.toInt() ?? 0,
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
    default:
      throw FormatException('$ctx.property unknown: $prop');
  }
}

ScalarKeyframe _parseKeyframe(Map<String, dynamic> j, String ctx) {
  final t = (j['t'] as num?)?.toDouble();
  if (t == null) throw FormatException('missing required field: $ctx.t');
  final value = (j['value'] as num?)?.toDouble();
  if (value == null) throw FormatException('missing required field: $ctx.value');
  final curveStr = j['curve'] as String?;
  final curve = curveStr == null || curveStr == 'linear'
      ? TimelineCurve.linear
      : curveStr == 'stepped'
          ? TimelineCurve.stepped
          : throw FormatException('$ctx.curve unknown: $curveStr');
  return ScalarKeyframe(time: t, value: value, curve: curve);
}

List<AnimationClip> _parseAnimations(List<dynamic> anims) {
  final result = <AnimationClip>[];
  final seen = <String>{};
  for (var ai = 0; ai < anims.length; ai++) {
    final anim = anims[ai] as Map<String, dynamic>;
    final ctx = 'animations[$ai]';
    final name = _required<String>(anim['name'], '$ctx.name');
    if (!seen.add(name)) throw FormatException('duplicate animation name: $name');

    var duration = 0.0;
    final boneTimelines = <BoneTimeline>[];
    final btList = anim['boneTimelines'] as List<dynamic>? ?? const [];
    for (var bi = 0; bi < btList.length; bi++) {
      final bt = btList[bi] as Map<String, dynamic>;
      final btCtx = '$ctx.boneTimelines[$bi]';
      final bone = _required<String>(bt['bone'], '$btCtx.bone');
      final prop = _required<String>(bt['property'], '$btCtx.property');
      final kind = _parseBoneTimelineKind(prop, btCtx);
      final kfList = _required<List<dynamic>>(bt['keyframes'], '$btCtx.keyframes');
      if (kfList.isEmpty) throw FormatException('$btCtx.keyframes must not be empty');
      final keys = <ScalarKeyframe>[];
      for (var ki = 0; ki < kfList.length; ki++) {
        keys.add(_parseKeyframe(kfList[ki] as Map<String, dynamic>, '$btCtx.keyframes[$ki]'));
      }
      // Validate strictly increasing times.
      for (var ki = 1; ki < keys.length; ki++) {
        if (keys[ki].time <= keys[ki - 1].time) {
          throw FormatException('$btCtx.keyframes: times must be strictly increasing');
        }
      }
      boneTimelines.add(BoneTimeline(bone: bone, kind: kind, keys: keys));
      if (keys.last.time > duration) duration = keys.last.time;
    }
    result.add(AnimationClip(name: name, duration: duration, boneTimelines: boneTimelines));
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
    final cpRaw = _required<List<dynamic>>(wj['controlPoints'], 'warp.controlPoints');
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
    final rj = _required<Map<String, dynamic>>(j['rotation'], 'deformer.rotation');
    deformerData = DeformerData(
      id: id,
      parent: parent,
      order: order,
      kind: DeformerKind.rotation,
      rotation: RotationDeformerData(
        pivotX: _required<num>(rj['pivotX'], 'rotation.pivotX').toDouble(),
        pivotY: _required<num>(rj['pivotY'], 'rotation.pivotY').toDouble(),
        angleDegrees: _required<num>(rj['angleDegrees'], 'rotation.angleDegrees').toDouble(),
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
    return DeformerRecord(deformer: deformerData, keyformBlend: const KeyformBlend());
  }

  final axisNames = _required<List<dynamic>>(kbj['axes'], 'keyformBlend.axes');
  final axes = axisNames.map((n) {
    final name = n as String;
    final axis = paramsByName[name];
    if (axis == null) throw FormatException('keyformBlend references unknown parameter: $name');
    return axis;
  }).toList();

  final kfList = _required<List<dynamic>>(kbj['keyforms'], 'keyformBlend.keyforms');
  final keyforms = kfList.map((kf) {
    final kfm = kf as Map<String, dynamic>;
    final coordMap = _required<Map<String, dynamic>>(kfm['coordinates'], 'keyform.coordinates');
    final coordinates = axes.map((a) {
      final v = coordMap[a.name];
      if (v == null) throw FormatException('keyform missing coordinate: ${a.name}');
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
    keyformBlend: KeyformBlend(axes: axes, valueCount: valueCount, keyforms: keyforms),
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

  final slotNames = <String>{};
  for (var i = 0; i < data.slots.length; i++) {
    final s = data.slots[i];
    final ctx = 'slots[$i]';
    if (s.name.isEmpty) throw FormatException('$ctx.name must not be empty');
    if (!boneNames.contains(s.bone)) {
      throw FormatException('unknown slot bone: ${s.bone}');
    }
    if (s.attachment.isNotEmpty && !regionNames.contains(s.attachment)) {
      throw FormatException('unknown slot attachment: ${s.attachment}');
    }
    if (!slotNames.add(s.name)) {
      throw FormatException('duplicate slot name: ${s.name}');
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

  for (var ai = 0; ai < data.animations.length; ai++) {
    final anim = data.animations[ai];
    final ctx = 'animations[$ai](${anim.name})';
    for (var bi = 0; bi < anim.boneTimelines.length; bi++) {
      final tl = anim.boneTimelines[bi];
      if (!boneNames.contains(tl.bone)) {
        throw FormatException('$ctx.boneTimelines[$bi]: unknown bone: ${tl.bone}');
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
const int _bnbPath = 4000;
const int _bnbPathAttachment = 4001;
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
  _bnbSkeleton, _bnbBone, _bnbSlot, _bnbRegion, _bnbPath, _bnbPathAttachment,
  _bnbParameter, _bnbDeformer, _bnbWarpLattice, _bnbRotationDeformer,
  _bnbKeyformBlend, _bnbKeyform,
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
      if (pos >= data.length) throw const FormatException('truncated .bnb varuint');
      if (pos - start >= 10) throw const FormatException('.bnb varuint too long');
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
    if (b != 0 && b != 1) throw FormatException('.bnb bool must be 0 or 1, got $b');
    return b == 1;
  }

  String readStr(List<String> strings) {
    final idx = readVaruint();
    if (idx >= strings.length) {
      throw FormatException('.bnb string index $idx out of range (${strings.length})');
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
        throw FormatException('.bnb duplicate property key $pk in type $typeKey object');
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
    throw FormatException('.bnb $ctx payload has ${c.data.length - c.pos} trailing bytes');
  }
}

String _bStr(_BnbObj obj, int key, List<String> strings, String ctx, {String? def}) {
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
  if (payload == null) throw FormatException('.bnb required property missing: $ctx');
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

// Parse warpControlPoints payload: varuint count, then count*(f32 x, f32 y) pairs.
List<DeformerPoint> _bControlPoints(_BnbObj obj, List<String> strings) {
  final payload = obj.props[_bkWarpControlPoints];
  if (payload == null) throw const FormatException('.bnb warpLattice.controlPoints is required');
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
  if (payload == null) throw const FormatException('.bnb keyformBlend.axes is required');
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final axes = <ParameterAxis>[];
  for (var i = 0; i < count; i++) {
    final name = c.readStr(strings);
    final axis = paramsByName[name];
    if (axis == null) {
      throw FormatException('.bnb keyformBlend references unknown parameter: $name');
    }
    axes.add(axis);
  }
  _bCheckExhausted(c, 'blendAxes');
  return axes;
}

// Parse a flat array of n f32 values from a property payload.
List<double> _bF32Array(_BnbObj obj, int key, int count, String ctx) {
  final payload = obj.props[key];
  if (payload == null) throw FormatException('.bnb required property missing: $ctx');
  if (payload.length != count * 4) {
    throw FormatException('.bnb $ctx payload length mismatch: expected ${count * 4}, got ${payload.length}');
  }
  final c = _BnbCur(payload);
  final result = <double>[];
  for (var i = 0; i < count; i++) {
    result.add(c.readF32());
  }
  return result;
}

SkeletonData _bnbDecode(List<_BnbObj> objects, List<String> strings) {
  SkeletonHeader? header;
  final bones = <BoneData>[];
  final slots = <SlotData>[];
  final regions = <RegionAttachment>[];
  final paths = <PathConstraintData>[];
  final pathAttachments = <PathAttachment>[];
  final parameters = <ParameterAxis>[];
  final deformers = <DeformerRecord>[];

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
      throw const FormatException('.bnb deformer header has no following geometry record');
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

  for (final obj in objects) {
    switch (obj.typeKey) {
      case _bnbSkeleton:
        flushPending();
        if (header != null) throw const FormatException('.bnb: multiple skeleton objects');
        header = SkeletonHeader(
          name: _bStr(obj, _bkName, strings, 'skeleton.name'),
          version: _bStr(obj, _bkVersion, strings, 'skeleton.version', def: '0.1.0'),
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
          transformMode: _bStr(obj, _bkTransformMode, strings, 'bone.transformMode', def: 'normal'),
        ));
      case _bnbSlot:
        flushPending();
        slots.add(SlotData(
          name: _bStr(obj, _bkName, strings, 'slot.name'),
          bone: _bStr(obj, _bkBone, strings, 'slot.bone'),
          attachment: _bStr(obj, _bkAttachment, strings, 'slot.attachment', def: ''),
        ));
      case _bnbRegion:
        flushPending();
        regions.add(RegionAttachment(
          name: _bStr(obj, _bkName, strings, 'region.name'),
          width: _bF32(obj, _bkWidth, 'region.width'),
          height: _bF32(obj, _bkHeight, 'region.height'),
        ));
      case _bnbPath:
        flushPending();
        paths.add(PathConstraintData(
          name: _bStr(obj, _bkName, strings, 'path.name'),
          bone: _bStr(obj, _bkBone, strings, 'path.bone'),
          target: _bStr(obj, _bkTarget, strings, 'path.target'),
          path: _bStr(obj, _bkPath, strings, 'path.path'),
          order: _bVarint(obj, _bkOrder, def: 0),
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
        pendingParent = _bStr(obj, _bkParent, strings, 'deformer.parent', def: '');
        pendingOrder = _bVaruint(obj, _bkDefOrder, def: 0);
        final kindStr = _bStr(obj, _bkDefKind, strings, 'deformer.kind');
        if (kindStr == 'warp') {
          pendingKind = DeformerKind.warp;
        } else if (kindStr == 'rotation') {
          pendingKind = DeformerKind.rotation;
        } else {
          throw FormatException('.bnb deformer.kind must be warp or rotation: $kindStr');
        }
        deformerPending = true;
        geometryReady = false;
        blendPending = false;
        pendingBlendAxes = [];
        pendingKeyforms = [];
      case _bnbWarpLattice:
        if (!deformerPending || pendingKind != DeformerKind.warp) {
          throw const FormatException('.bnb warpLattice without preceding warp deformer');
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
          throw const FormatException('.bnb rotationDeformer without preceding rotation deformer');
        }
        pendingRotation = RotationDeformerData(
          pivotX: _bF32(obj, _bkRotPivotX, 'rotationDeformer.pivotX'),
          pivotY: _bF32(obj, _bkRotPivotY, 'rotationDeformer.pivotY'),
          angleDegrees: _bF32(obj, _bkRotAngle, 'rotationDeformer.angleDegrees'),
          scaleX: _bF32(obj, _bkRotScaleX, 'rotationDeformer.scaleX', def: 1.0),
          scaleY: _bF32(obj, _bkRotScaleY, 'rotationDeformer.scaleY', def: 1.0),
          opacity: _bF32(obj, _bkRotOpacity, 'rotationDeformer.opacity', def: 1.0),
        );
        geometryReady = true;
      case _bnbKeyformBlend:
        if (!deformerPending || !geometryReady) {
          throw const FormatException('.bnb keyformBlend without preceding deformer geometry');
        }
        pendingBlendValueCount = _bVaruint(obj, _bkBlendValueCount, def: 0);
        pendingBlendAxes = _bBlendAxes(obj, strings, paramsByName);
        pendingKeyforms = [];
        blendPending = true;
      case _bnbKeyform:
        if (!blendPending) {
          throw const FormatException('.bnb keyform without preceding keyformBlend');
        }
        final coordVals = _bF32Array(obj, _bkBlendCoords, pendingBlendAxes.length, 'keyform.coordinates');
        final values = _bF32Array(obj, _bkBlendValues, pendingBlendValueCount, 'keyform.values');
        final coordinates = [
          for (var i = 0; i < pendingBlendAxes.length; i++)
            ParameterSample(name: pendingBlendAxes[i].name, value: coordVals[i]),
        ];
        pendingKeyforms.add(Keyform(coordinates: coordinates, values: values));
    }
  }
  flushPending();

  if (header == null) throw const FormatException('.bnb: missing skeleton object');
  return SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    parameters: parameters,
    deformers: deformers,
  );
}

/// Parse a bony binary (.bnb) byte buffer into a [SkeletonData].
///
/// Throws [FormatException] on any framing error, missing required field, or
/// structural validation failure (same rules as [loadBonyJson]).
SkeletonData loadBonyBnb(Uint8List bytes) {
  final c = _BnbCur(bytes);

  c._need(4, '.bnb fingerprint');
  if (c.data[0] != 0x42 || c.data[1] != 0x4f ||
      c.data[2] != 0x4e || c.data[3] != 0x59) {
    throw const FormatException('invalid .bnb fingerprint (expected BONY)');
  }
  c.pos = 4;

  final version = c.readVaruint();
  final major = (version >> 16) & 0xffff;
  if (major != 0) throw FormatException('unsupported .bnb major version: $major');

  final flags = c.readVaruint();
  if ((flags & ~0x3) != 0) throw const FormatException('unknown .bnb header flags');

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

  final data = SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    animations: animations,
    parameters: parameters,
    deformers: deformers,
  );
  _validate(data);
  return data;
}
