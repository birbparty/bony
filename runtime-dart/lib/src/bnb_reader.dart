part of 'loader.dart';

const _bnbKnownTypes = {
  wire.bonyTypeKeySkeleton,
  wire.bonyTypeKeyBone,
  wire.bonyTypeKeySlot,
  wire.bonyTypeKeyRegion,
  wire.bonyTypeKeyPointAttachment,
  wire.bonyTypeKeyBoundingBoxAttachment,
  wire.bonyTypeKeyClippingAttachment,
  wire.bonyTypeKeyMeshAttachment,
  wire.bonyTypeKeyNestedRigAttachment,
  wire.bonyTypeKeySkin,
  wire.bonyTypeKeySkinEntry,
  wire.bonyTypeKeyPath,
  wire.bonyTypeKeyPathAttachment,
  wire.bonyTypeKeyIkConstraint,
  wire.bonyTypeKeyTransformConstraint,
  wire.bonyTypeKeyPhysicsConstraint,
  wire.bonyTypeKeyAnimationClip,
  wire.bonyTypeKeyBoneTimeline,
  wire.bonyTypeKeySlotTimeline,
  wire.bonyTypeKeyEventTimeline,
  wire.bonyTypeKeyDeformTimeline,
  wire.bonyTypeKeyParameter,
  wire.bonyTypeKeyDeformer,
  wire.bonyTypeKeyWarpLattice,
  wire.bonyTypeKeyRotationDeformer,
  wire.bonyTypeKeyKeyformBlend,
  wire.bonyTypeKeyKeyform,
  wire.bonyTypeKeyStateMachine,
  wire.bonyTypeKeyStateMachineInput,
  wire.bonyTypeKeyStateMachineLayer,
  wire.bonyTypeKeyStateMachineState,
  wire.bonyTypeKeyStateMachineBlendClip,
  wire.bonyTypeKeyStateMachineTransition,
  wire.bonyTypeKeyStateMachineCondition,
  wire.bonyTypeKeyStateMachineListener,
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
    final q = quantizeF32(v.toDouble());
    if (!q.isFinite) {
      throw const FormatException('.bnb f32 must be a finite f32 value');
    }
    return q;
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
    if (def != null) return quantizeF32(def);
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
  final payload = obj.props[wire.bonyPropertyKeyBones];
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

List<String> _bIndexList(_BnbObj obj, int key, List<String> names, String ctx) {
  final payload = obj.props[key];
  if (payload == null) return const [];
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final out = <String>[];
  for (var i = 0; i < count; i++) {
    final sourceIndex = c.readVaruint();
    if (sourceIndex < 0 || sourceIndex >= names.length) {
      throw FormatException('.bnb $ctx index is out of range');
    }
    out.add(names[sourceIndex]);
  }
  _bCheckExhausted(c, ctx);
  return out;
}

/// Decode a required polygon `vertices` payload: a varuint point
/// count followed by count * (f32 x, f32 y) little-endian pairs, returned as a
/// flat [x0, y0, x1, y1, ...] list. Matches runtime-nim's
/// writePolygonVerticesPayload / readPolygonVerticesPayload (semantic.nim),
/// including the trailing-bytes check.
List<double> _bPolygonVertices(_BnbObj obj, String ctx) {
  final payload = obj.props[wire.bonyPropertyKeyVertices];
  if (payload == null) {
    throw FormatException('.bnb $ctx.vertices is required');
  }
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  final out = <double>[];
  for (var i = 0; i < count; i++) {
    out.add(c.readF32());
    out.add(c.readF32());
  }
  _bCheckExhausted(c, '$ctx.vertices');
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
  final payload = obj.props[wire.bonyPropertyKeyMeshVertices];
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
  final payload = obj.props[wire.bonyPropertyKeyMeshUvs];
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
  final payload = obj.props[wire.bonyPropertyKeyMeshTriangles];
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
  final payload = obj.props[wire.bonyPropertyKeyWarpControlPoints];
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
  final payload = obj.props[wire.bonyPropertyKeyBlendAxes];
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

/// Decode a packed `deformKeys` bytes payload into deform keyframes. Mirrors the
/// Nim `readDeformKeys` layout (binary/semantic.nim): varuint count, then per
/// key f32 time, varuint offset, varuint deltaCount, deltaCount*(f32 x, f32 y),
/// curve. Delta values arrive f32 already (readF32).
/// Decodes a packed `eventKeys` payload (M3 propertyKey 2005) into event
/// keyframes. Byte layout is frozen by docs/event-timeline-contract.md "Packed
/// eventTimeline byte layout": per key — f32 time, varuint name-index, svarint
/// intValue, f32 floatValue, varuint stringValue-index, varuint audioPath-index,
/// f32 volume, f32 balance. Strings resolve through the global [strings] table
/// (row-major intern order name/stringValue/audioPath). No curve tail.
List<EventKeyframe> _bEventTimelineKeys(
    Uint8List payload, List<String> strings, String ctx) {
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  if (count == 0) {
    throw FormatException('.bnb $ctx must contain at least one key');
  }
  final keys = <EventKeyframe>[];
  for (var i = 0; i < count; i++) {
    final time = c.readF32();
    if (time < 0.0) {
      throw FormatException('.bnb $ctx.time must be non-negative');
    }
    final name = c.readStr(strings);
    if (name.isEmpty) {
      throw FormatException('.bnb $ctx.name must not be empty');
    }
    final intValue = c.readVarint();
    final floatValue = c.readF32();
    final stringValue = c.readStr(strings);
    final audioPath = c.readStr(strings);
    final volume = c.readF32();
    final balance = c.readF32();
    keys.add(EventKeyframe(
      time: time,
      event: EventData(
        name: name,
        intValue: intValue,
        floatValue: floatValue,
        stringValue: stringValue,
        audioPath: audioPath,
        volume: volume,
        balance: balance,
      ),
    ));
  }
  _bCheckExhausted(c, ctx);
  _ensureNonDecreasing(keys.map((k) => k.time).toList(), ctx);
  return keys;
}

List<DeformKeyframe> _bDeformTimelineKeys(
    Uint8List payload, int vertexCount, String ctx) {
  final c = _BnbCur(payload);
  final count = c.readVaruint();
  if (count == 0) {
    throw FormatException('.bnb $ctx must contain at least one key');
  }
  final keys = <DeformKeyframe>[];
  for (var i = 0; i < count; i++) {
    final time = c.readF32();
    final offset = c.readVaruint();
    if (offset < 0) {
      throw FormatException('.bnb $ctx.offset must be non-negative');
    }
    final deltaCount = c.readVaruint();
    if (deltaCount == 0) {
      throw FormatException('.bnb $ctx key must contain at least one delta');
    }
    final deltas = <MeshDelta>[];
    for (var d = 0; d < deltaCount; d++) {
      deltas.add(MeshDelta(x: c.readF32(), y: c.readF32()));
    }
    if (offset + deltas.length > vertexCount) {
      throw FormatException(
          '.bnb $ctx deform key range exceeds mesh vertex count');
    }
    keys.add(DeformKeyframe(
      time: time,
      offset: offset,
      deltas: deltas,
      curve: _bCurve(c, '$ctx.curve'),
    ));
  }
  _bCheckExhausted(c, ctx);
  _ensureStrictlyIncreasing(keys.map((k) => k.time).toList(), ctx);
  return keys;
}

double _animationDuration(
    List<BoneTimeline> boneTimelines, List<SlotTimeline> slotTimelines,
    [List<DeformTimeline> deformTimelines = const [],
    List<EventTimeline> eventTimelines = const []]) {
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
  for (final timeline in deformTimelines) {
    if (timeline.keys.isNotEmpty && timeline.keys.last.time > duration) {
      duration = timeline.keys.last.time;
    }
  }
  for (final timeline in eventTimelines) {
    if (timeline.keys.isNotEmpty && timeline.keys.last.time > duration) {
      duration = timeline.keys.last.time;
    }
  }
  return duration;
}
