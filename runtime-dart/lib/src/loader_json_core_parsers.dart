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
