// .bony JSON loader: parse a bony JSON string into a SkeletonData.
//
// Defaults follow the values in the generated registry (bonyPropertyDefaults).

import 'dart:convert';
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
}

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

  final data = SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
  );
  _validate(data);
  return data;
}
