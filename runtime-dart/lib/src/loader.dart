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

// Type keys we recognize; everything else is skipped for forward compat.
const _bnbKnownTypes = {
  _bnbSkeleton, _bnbBone, _bnbSlot, _bnbRegion, _bnbPath, _bnbPathAttachment
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
    while (true) {
      final pk = c.readVaruint();
      if (pk == 0) break;
      final blen = c.readVaruint();
      props[pk] = c.readBytes(blen);
    }
    if (_bnbKnownTypes.contains(typeKey)) {
      out.add((typeKey: typeKey, props: props));
    }
  }
  return out;
}

// Property accessors — each creates a tiny cursor over the stored payload.
String _bStr(_BnbObj obj, int key, List<String> strings, String ctx, {String? def}) {
  final payload = obj.props[key];
  if (payload == null) {
    if (def != null) return def;
    throw FormatException('.bnb required property missing: $ctx');
  }
  return _BnbCur(payload).readStr(strings);
}

double _bF32(_BnbObj obj, int key, String ctx, {double? def}) {
  final payload = obj.props[key];
  if (payload == null) {
    if (def != null) return def;
    throw FormatException('.bnb required property missing: $ctx');
  }
  return _BnbCur(payload).readF32();
}

double _bF64(_BnbObj obj, int key, String ctx) {
  final payload = obj.props[key];
  if (payload == null) throw FormatException('.bnb required property missing: $ctx');
  return _BnbCur(payload).readF64();
}

bool _bBool(_BnbObj obj, int key, {bool def = false}) {
  final payload = obj.props[key];
  if (payload == null) return def;
  return _BnbCur(payload).readBool();
}

int _bVarint(_BnbObj obj, int key, {int def = 0}) {
  final payload = obj.props[key];
  if (payload == null) return def;
  return _BnbCur(payload).readVarint();
}

SkeletonData _bnbDecode(List<_BnbObj> objects, List<String> strings) {
  SkeletonHeader? header;
  final bones = <BoneData>[];
  final slots = <SlotData>[];
  final regions = <RegionAttachment>[];
  final paths = <PathConstraintData>[];
  final pathAttachments = <PathAttachment>[];

  for (final obj in objects) {
    switch (obj.typeKey) {
      case _bnbSkeleton:
        if (header != null) throw const FormatException('.bnb: multiple skeleton objects');
        header = SkeletonHeader(
          name: _bStr(obj, _bkName, strings, 'skeleton.name'),
          version: _bStr(obj, _bkVersion, strings, 'skeleton.version', def: '0.1.0'),
        );
      case _bnbBone:
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
        slots.add(SlotData(
          name: _bStr(obj, _bkName, strings, 'slot.name'),
          bone: _bStr(obj, _bkBone, strings, 'slot.bone'),
          attachment: _bStr(obj, _bkAttachment, strings, 'slot.attachment', def: ''),
        ));
      case _bnbRegion:
        regions.add(RegionAttachment(
          name: _bStr(obj, _bkName, strings, 'region.name'),
          width: _bF32(obj, _bkWidth, 'region.width'),
          height: _bF32(obj, _bkHeight, 'region.height'),
        ));
      case _bnbPath:
        paths.add(PathConstraintData(
          name: _bStr(obj, _bkName, strings, 'path.name'),
          bone: _bStr(obj, _bkBone, strings, 'path.bone'),
          target: _bStr(obj, _bkTarget, strings, 'path.target'),
          path: _bStr(obj, _bkPath, strings, 'path.path'),
          order: _bVarint(obj, _bkOrder, def: 0),
        ));
      case _bnbPathAttachment:
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
    }
  }

  if (header == null) throw const FormatException('.bnb: missing skeleton object');
  return SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
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

  final data = SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    animations: animations,
  );
  _validate(data);
  return data;
}
