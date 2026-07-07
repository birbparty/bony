// .bony JSON loader and .bnb binary loader.
//
// Defaults follow the values in the generated registry (bonyPropertyDefaults).

import 'dart:convert';
import 'dart:typed_data' show Uint8List, ByteData, Endian;
import 'deform.dart' show quantizeF32;
import 'generated/wire.dart' as wire;
import 'model.dart';
import 'physics_constraint.dart' show physicsChannelsFromMask;

part 'loader_json_parsers.dart';
part 'loader_validation.dart';
part 'bnb_reader.dart';
part 'bnb_decoder.dart';

// ===========================================================================
// Binary (.bnb) loader
// ===========================================================================

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

  final slots = _parseList(root, 'slots', (item, _) => _parseSlot(item));
  final regions = _parseList(root, 'regions', (item, _) => _parseRegion(item));
  final pointAttachments = _parseList(
    root,
    'pointAttachments',
    (item, _) => _parsePointAttachment(item),
  );
  final boundingBoxAttachments = _parseList(
    root,
    'boundingBoxAttachments',
    (item, _) => _parseBoundingBoxAttachment(item),
  );
  final nestedRigAttachments = _parseList(
    root,
    'nestedRigAttachments',
    (item, _) => _parseNestedRigAttachment(item),
  );
  final paths = _parseList(root, 'paths', (item, _) => _parsePath(item));
  final pathAttachments = _parseList(
    root,
    'pathAttachments',
    (item, _) => _parsePathAttachment(item),
  );
  final clippingAttachments = _parseList(
    root,
    'clippingAttachments',
    (item, _) => _parseClippingAttachment(item),
  );
  final meshAttachments = _parseList(
    root,
    'meshAttachments',
    (item, _) => _parseMeshAttachment(item),
  );
  final ikConstraints =
      _parseList(root, 'ikConstraints', (item, _) => _parseIk(item));
  final transformConstraints = _parseList(
    root,
    'transformConstraints',
    (item, _) => _parseTransform(item),
  );
  final physicsConstraints = _parseList(
    root,
    'physicsConstraints',
    (item, _) => _parsePhysics(item),
  );
  final skins = _parseList(root, 'skins', _parseSkin);

  final preAnimationData = SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    pointAttachments: pointAttachments,
    boundingBoxAttachments: boundingBoxAttachments,
    nestedRigAttachments: nestedRigAttachments,
    clippingAttachments: clippingAttachments,
    meshAttachments: meshAttachments,
    ikConstraints: ikConstraints,
    transformConstraints: transformConstraints,
    physicsConstraints: physicsConstraints,
    skins: skins,
  );

  final animsRaw = root['animations'];
  final animations = animsRaw is List<dynamic>
      ? _parseAnimations(animsRaw, preAnimationData)
      : const <AnimationClip>[];

  final parameters =
      _parseList(root, 'parameters', (item, _) => _parseParameter(item));

  final paramsByName = <String, ParameterAxis>{
    for (final p in parameters) p.name: p,
  };
  final deformers = _parseList(
    root,
    'deformers',
    (item, _) => _parseDeformer(item, paramsByName),
  );
  final stateMachines =
      _parseList(root, 'stateMachines', (item, _) => _parseStateMachine(item));

  final data = SkeletonData(
    header: header,
    bones: bones,
    slots: slots,
    regions: regions,
    paths: paths,
    pathAttachments: pathAttachments,
    pointAttachments: pointAttachments,
    boundingBoxAttachments: boundingBoxAttachments,
    nestedRigAttachments: nestedRigAttachments,
    clippingAttachments: clippingAttachments,
    meshAttachments: meshAttachments,
    ikConstraints: ikConstraints,
    transformConstraints: transformConstraints,
    physicsConstraints: physicsConstraints,
    skins: skins,
    animations: animations,
    parameters: parameters,
    deformers: deformers,
    stateMachines: stateMachines,
  );
  _validate(data);
  return data;
}
