import 'dart:convert' show jsonDecode;

import 'deform.dart' show quantizeF32;
import 'generated/wire.dart' as wire;
import 'loader.dart' show validateBonyData;
import 'model.dart';
import 'physics_constraint.dart' show physicsChannelsToMask;

const double _maxSafeInteger = 9007199254740991.0;

/// Public writer failure type used by the canonical JSON writer.
final class BonyWriteException implements Exception {
  const BonyWriteException(this.message, [this.cause]);

  final String message;
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'BonyWriteException: $message'
      : 'BonyWriteException: $message ($cause)';
}

enum BonyWriterScalarKind {
  string,
  f32,
  f64,
  bool_,
  varint,
  varuint,
  bytes,
}

final class BonyWriterScalar {
  const BonyWriterScalar._(this.propertyId, this.kind, this.value);

  factory BonyWriterScalar.string(String propertyId, String value) =>
      BonyWriterScalar._(propertyId, BonyWriterScalarKind.string, value);

  factory BonyWriterScalar.f32(String propertyId, double value) =>
      BonyWriterScalar._(propertyId, BonyWriterScalarKind.f32, value);

  factory BonyWriterScalar.f64(String propertyId, double value) =>
      BonyWriterScalar._(propertyId, BonyWriterScalarKind.f64, value);

  factory BonyWriterScalar.bool(String propertyId, bool value) =>
      BonyWriterScalar._(propertyId, BonyWriterScalarKind.bool_, value);

  factory BonyWriterScalar.varint(String propertyId, int value) =>
      BonyWriterScalar._(propertyId, BonyWriterScalarKind.varint, value);

  factory BonyWriterScalar.varuint(String propertyId, int value) {
    if (value < 0) {
      throw RangeError.value(value, 'value', 'varuint must be non-negative');
    }
    return BonyWriterScalar._(propertyId, BonyWriterScalarKind.varuint, value);
  }

  factory BonyWriterScalar.bytes(String propertyId, List<int> value) =>
      BonyWriterScalar._(propertyId, BonyWriterScalarKind.bytes, value);

  final String propertyId;
  final BonyWriterScalarKind kind;
  final Object value;
}

String bonyCanonicalJsonString(String value) {
  final out = StringBuffer('"');
  for (var i = 0; i < value.length; i++) {
    final unit = value.codeUnitAt(i);
    switch (unit) {
      case 0x08:
        out.write(r'\b');
      case 0x09:
        out.write(r'\t');
      case 0x0a:
        out.write(r'\n');
      case 0x0c:
        out.write(r'\f');
      case 0x0d:
        out.write(r'\r');
      case 0x22:
        out.write(r'\"');
      case 0x5c:
        out.write(r'\\');
      default:
        if (unit < 0x20) {
          out.write(r'\u00');
          out.write(unit.toRadixString(16).padLeft(2, '0'));
        } else if (unit >= 0xd800 && unit <= 0xdbff) {
          if (i + 1 >= value.length) {
            throw const FormatException('unpaired high surrogate in string');
          }
          final next = value.codeUnitAt(i + 1);
          if (next < 0xdc00 || next > 0xdfff) {
            throw const FormatException('unpaired high surrogate in string');
          }
          out.writeCharCode(unit);
          out.writeCharCode(next);
          i++;
        } else if (unit >= 0xdc00 && unit <= 0xdfff) {
          throw const FormatException('unpaired low surrogate in string');
        } else {
          out.writeCharCode(unit);
        }
    }
  }
  out.write('"');
  return out.toString();
}

String bonyCanonicalNumber(double value) {
  if (!value.isFinite) {
    throw FormatException('canonical JSON number must be finite: $value');
  }
  if (value == 0.0) return '0';
  final abs = value.abs();
  if (value.truncateToDouble() == value && abs <= _maxSafeInteger) {
    return value.toInt().toString();
  }

  // Match the current Nim reference writer, which uses `$float64` after the
  // explicit integer/zero cases. The written contract says ECMAScript-style
  // exponent signs, but Dart writer parity is byte-for-byte against Nim.
  final asDart = value.toString();
  if (asDart.contains('e')) {
    final fixed = _fixedIfShortReferenceSpelling(value);
    return fixed ?? asDart;
  }
  if (abs >= 1e17) {
    final exponential = value.toStringAsExponential(0);
    if (double.parse(exponential) == value) return exponential;
  }
  return asDart;
}

String bonyCanonicalF32Number(double value) =>
    bonyCanonicalNumber(quantizeF32(value));

bool bonyShouldOmitDefault(String objectId, BonyWriterScalar scalar) {
  final defaultSpec = wire.bonyPropertyDefault(objectId, scalar.propertyId);
  if (defaultSpec == null || !defaultSpec.omitWhenDefault) return false;
  return bonyScalarMatchesDefault(scalar, defaultSpec);
}

bool bonyScalarMatchesDefault(
  BonyWriterScalar scalar,
  wire.BonyPropertyDefault defaultSpec,
) {
  final defaultValue = jsonDecode(defaultSpec.value);
  switch (defaultSpec.equality) {
    case 'exactString':
      return scalar.kind == BonyWriterScalarKind.string &&
          scalar.value == defaultValue;
    case 'exactBool':
      return scalar.kind == BonyWriterScalarKind.bool_ &&
          scalar.value == defaultValue;
    case 'exactInteger':
      return (scalar.kind == BonyWriterScalarKind.varint ||
              scalar.kind == BonyWriterScalarKind.varuint) &&
          scalar.value == defaultValue;
    case 'storedF32':
      return (scalar.kind == BonyWriterScalarKind.f32 ||
              scalar.kind == BonyWriterScalarKind.f64) &&
          quantizeF32(scalar.value as double) ==
              quantizeF32((defaultValue as num).toDouble());
    case 'exactBytes':
      if (scalar.kind != BonyWriterScalarKind.bytes) return false;
      final bytes = scalar.value as List<int>;
      if (defaultValue == '') return bytes.isEmpty;
      if (defaultValue is List) {
        return _listEquals(bytes, defaultValue.cast<int>());
      }
      return false;
    default:
      throw UnsupportedError(
          'unknown default equality: ${defaultSpec.equality}');
  }
}

final class BonyJsonBuffer {
  BonyJsonBuffer();

  final StringBuffer _buffer = StringBuffer();

  void write(String value) => _buffer.write(value);

  void addIndent(int indent) {
    _buffer.write('  ' * indent);
  }

  void addFieldPrefix(String key, int indent, FieldState state) {
    if (!state.first) _buffer.write(',\n');
    state.first = false;
    addIndent(indent);
    _buffer.write(bonyCanonicalJsonString(key));
    _buffer.write(': ');
  }

  void addStringField(String key, String value, int indent, FieldState state) {
    addFieldPrefix(key, indent, state);
    _buffer.write(bonyCanonicalJsonString(value));
  }

  void addNumberField(String key, double value, int indent, FieldState state) {
    addFieldPrefix(key, indent, state);
    _buffer.write(bonyCanonicalNumber(value));
  }

  void addF32Field(String key, double value, int indent, FieldState state) {
    addFieldPrefix(key, indent, state);
    _buffer.write(bonyCanonicalF32Number(value));
  }

  void addBoolField(String key, bool value, int indent, FieldState state) {
    addFieldPrefix(key, indent, state);
    _buffer.write(value ? 'true' : 'false');
  }

  void addIntField(String key, int value, int indent, FieldState state) {
    addFieldPrefix(key, indent, state);
    _buffer.write(value);
  }

  @override
  String toString() => _buffer.toString();
}

final class FieldState {
  FieldState();

  bool first = true;
}

String writeBonyJson(SkeletonData data) {
  try {
    validateBonyData(data);
  } on FormatException catch (e) {
    throw BonyWriteException('invalid SkeletonData', e);
  } catch (e) {
    throw BonyWriteException('failed to validate SkeletonData', e);
  }

  try {
    final out = BonyJsonBuffer();
    final fields = FieldState();
    out.write('{\n');
    out.addFieldPrefix('skeleton', 1, fields);
    _appendSkeleton(out, data.header, 1);
    _addTopLevelList(out, 'bones', data.bones, 1, fields, _appendBone);
    _addTopLevelList(out, 'slots', data.slots, 1, fields, _appendSlot);
    _addTopLevelList(out, 'regions', data.regions, 1, fields, _appendRegion);
    _addTopLevelList(out, 'pointAttachments', data.pointAttachments, 1, fields,
        _appendPointAttachment,
        omitWhenEmpty: true);
    _addTopLevelList(
      out,
      'boundingBoxAttachments',
      data.boundingBoxAttachments,
      1,
      fields,
      _appendBoundingBoxAttachment,
      omitWhenEmpty: true,
    );
    _addTopLevelList(
      out,
      'nestedRigAttachments',
      data.nestedRigAttachments,
      1,
      fields,
      _appendNestedRigAttachment,
      omitWhenEmpty: true,
    );
    _addTopLevelList(out, 'paths', data.paths, 1, fields, _appendPathConstraint,
        omitWhenEmpty: true);
    _addTopLevelList(out, 'ikConstraints', data.ikConstraints, 1, fields,
        _appendIkConstraint,
        omitWhenEmpty: true);
    _addTopLevelList(
      out,
      'transformConstraints',
      data.transformConstraints,
      1,
      fields,
      _appendTransformConstraint,
      omitWhenEmpty: true,
    );
    _addTopLevelList(
      out,
      'physicsConstraints',
      data.physicsConstraints,
      1,
      fields,
      _appendPhysicsConstraint,
      omitWhenEmpty: true,
    );
    _addTopLevelList(out, 'pathAttachments', data.pathAttachments, 1, fields,
        _appendPathAttachment,
        omitWhenEmpty: true);
    _addTopLevelList(
      out,
      'clippingAttachments',
      data.clippingAttachments,
      1,
      fields,
      _appendClippingAttachment,
      omitWhenEmpty: true,
    );
    _addTopLevelList(out, 'meshAttachments', data.meshAttachments, 1, fields,
        _appendMeshAttachment,
        omitWhenEmpty: true);
    _addTopLevelList<SkinData>(
      out,
      'skins',
      bonyCanonicalOrderedSkins(data),
      1,
      fields,
      (out, skin, indent) {
        out.addIndent(indent);
        out.write(bonyCanonicalSkinJson(data, skin, indent: indent));
      },
      omitWhenEmpty: true,
    );
    _addTopLevelList(
        out, 'parameters', data.parameters, 1, fields, _appendParameter,
        omitWhenEmpty: true);
    _addTopLevelList<DeformerRecord>(
      out,
      'deformers',
      data.deformers,
      1,
      fields,
      (out, record, indent) {
        out.addIndent(indent);
        out.write(bonyCanonicalDeformerRecordJson(record, indent: indent));
      },
      omitWhenEmpty: true,
    );
    _addTopLevelList<AnimationClip>(
      out,
      'animations',
      data.animations,
      1,
      fields,
      (out, animation, indent) {
        out.addIndent(indent);
        out.write(bonyCanonicalAnimationClipJson(animation,
            setupSlots: data.slots, indent: indent));
      },
      omitWhenEmpty: true,
    );
    _addTopLevelList<StateMachineData>(
      out,
      'stateMachines',
      data.stateMachines,
      1,
      fields,
      (out, machine, indent) {
        out.addIndent(indent);
        out.write(bonyCanonicalStateMachineJson(machine, indent: indent));
      },
      omitWhenEmpty: true,
    );
    out.write('\n}\n');
    return out.toString();
  } catch (e) {
    if (e is BonyWriteException) rethrow;
    throw BonyWriteException('failed to write canonical .bony JSON', e);
  }
}

typedef _JsonItemWriter<T> = void Function(
  BonyJsonBuffer out,
  T value,
  int indent,
);

void _addTopLevelList<T>(
  BonyJsonBuffer out,
  String key,
  List<T> values,
  int indent,
  FieldState fields,
  _JsonItemWriter<T> writeItem, {
  bool omitWhenEmpty = false,
}) {
  if (omitWhenEmpty && values.isEmpty) return;
  out.addFieldPrefix(key, indent, fields);
  _appendList(out, values, indent, writeItem);
}

void _appendList<T>(
  BonyJsonBuffer out,
  List<T> values,
  int indent,
  _JsonItemWriter<T> writeItem,
) {
  out.write('[');
  if (values.isNotEmpty) {
    out.write('\n');
    for (var i = 0; i < values.length; i++) {
      if (i > 0) out.write(',\n');
      writeItem(out, values[i], indent + 1);
    }
    out.write('\n');
    out.addIndent(indent);
  }
  out.write(']');
}

void _appendNumberArray(BonyJsonBuffer out, List<double> values) {
  out.write('[');
  for (var i = 0; i < values.length; i++) {
    if (i > 0) out.write(', ');
    out.write(bonyCanonicalNumber(values[i]));
  }
  out.write(']');
}

void _appendSkeleton(BonyJsonBuffer out, SkeletonHeader header, int indent) {
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(
    out,
    'skeleton',
    'name',
    BonyWriterScalar.string('name', header.name),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'skeleton',
    'version',
    BonyWriterScalar.string('version', header.version),
    indent + 1,
    fields,
  );
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendBone(BonyJsonBuffer out, BoneData bone, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'bone', 'name',
      BonyWriterScalar.string('name', bone.name), indent + 1, fields);
  _addScalarField(out, 'bone', 'parent',
      BonyWriterScalar.string('parent', bone.parent), indent + 1, fields);
  _addScalarField(
      out, 'bone', 'x', BonyWriterScalar.f32('x', bone.x), indent + 1, fields);
  _addScalarField(
      out, 'bone', 'y', BonyWriterScalar.f32('y', bone.y), indent + 1, fields);
  _addScalarField(out, 'bone', 'rotation',
      BonyWriterScalar.f32('rotation', bone.rotation), indent + 1, fields);
  _addScalarField(out, 'bone', 'scaleX',
      BonyWriterScalar.f32('scaleX', bone.scaleX), indent + 1, fields);
  _addScalarField(out, 'bone', 'scaleY',
      BonyWriterScalar.f32('scaleY', bone.scaleY), indent + 1, fields);
  _addScalarField(out, 'bone', 'shearX',
      BonyWriterScalar.f32('shearX', bone.shearX), indent + 1, fields);
  _addScalarField(out, 'bone', 'shearY',
      BonyWriterScalar.f32('shearY', bone.shearY), indent + 1, fields);
  _addScalarField(
      out,
      'bone',
      'inheritRotation',
      BonyWriterScalar.bool('inheritRotation', bone.inheritRotation),
      indent + 1,
      fields);
  _addScalarField(
      out,
      'bone',
      'inheritScale',
      BonyWriterScalar.bool('inheritScale', bone.inheritScale),
      indent + 1,
      fields);
  _addScalarField(
      out,
      'bone',
      'inheritReflection',
      BonyWriterScalar.bool('inheritReflection', bone.inheritReflection),
      indent + 1,
      fields);
  _addScalarField(
      out,
      'bone',
      'transformMode',
      BonyWriterScalar.string('transformMode', bone.transformMode),
      indent + 1,
      fields);
  _addScalarField(
      out,
      'bone',
      'skinRequired',
      BonyWriterScalar.bool('skinRequired', bone.skinRequired),
      indent + 1,
      fields);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendSlot(BonyJsonBuffer out, SlotData slot, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'slot', 'name',
      BonyWriterScalar.string('name', slot.name), indent + 1, fields);
  _addScalarField(out, 'slot', 'bone',
      BonyWriterScalar.string('bone', slot.bone), indent + 1, fields);
  _addScalarField(
      out,
      'slot',
      'attachment',
      BonyWriterScalar.string('attachment', slot.attachment),
      indent + 1,
      fields);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendRegion(BonyJsonBuffer out, RegionAttachment region, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'region', 'name',
      BonyWriterScalar.string('name', region.name), indent + 1, fields);
  _addScalarField(out, 'region', 'width',
      BonyWriterScalar.f32('width', region.width), indent + 1, fields);
  _addScalarField(out, 'region', 'height',
      BonyWriterScalar.f32('height', region.height), indent + 1, fields);
  _addScalarField(
      out,
      'region',
      'texturePage',
      BonyWriterScalar.string('texturePage', region.texturePage),
      indent + 1,
      fields);
  _addScalarField(out, 'region', 'u0', BonyWriterScalar.f32('u0', region.u0),
      indent + 1, fields);
  _addScalarField(out, 'region', 'v0', BonyWriterScalar.f32('v0', region.v0),
      indent + 1, fields);
  _addScalarField(out, 'region', 'u1', BonyWriterScalar.f32('u1', region.u1),
      indent + 1, fields);
  _addScalarField(out, 'region', 'v1', BonyWriterScalar.f32('v1', region.v1),
      indent + 1, fields);
  _addScalarField(
      out,
      'region',
      'alphaMode',
      BonyWriterScalar.string('alphaMode', region.alphaMode),
      indent + 1,
      fields);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendPointAttachment(
    BonyJsonBuffer out, PointAttachment point, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'pointAttachment', 'name',
      BonyWriterScalar.string('name', point.name), indent + 1, fields);
  _addScalarField(out, 'pointAttachment', 'x',
      BonyWriterScalar.f32('x', point.x), indent + 1, fields);
  _addScalarField(out, 'pointAttachment', 'y',
      BonyWriterScalar.f32('y', point.y), indent + 1, fields);
  _addScalarField(out, 'pointAttachment', 'rotation',
      BonyWriterScalar.f32('rotation', point.rotation), indent + 1, fields);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendBoundingBoxAttachment(
    BonyJsonBuffer out, BoundingBoxAttachment box, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'boundingBoxAttachment', 'name',
      BonyWriterScalar.string('name', box.name), indent + 1, fields);
  out.addFieldPrefix('vertices', indent + 1, fields);
  _appendNumberArray(out, box.vertices);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendNestedRigAttachment(
    BonyJsonBuffer out, NestedRigAttachment nested, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'nestedRigAttachment', 'name',
      BonyWriterScalar.string('name', nested.name), indent + 1, fields);
  _addScalarField(
      out,
      'nestedRigAttachment',
      'skeleton',
      BonyWriterScalar.string('nestedSkeleton', nested.skeleton),
      indent + 1,
      fields);
  _addScalarField(out, 'nestedRigAttachment', 'skin',
      BonyWriterScalar.string('nestedSkin', nested.skin), indent + 1, fields);
  _addScalarField(
      out,
      'nestedRigAttachment',
      'animation',
      BonyWriterScalar.string('nestedAnimation', nested.animation),
      indent + 1,
      fields);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendPathConstraint(
    BonyJsonBuffer out, PathConstraintData path, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'path', 'name',
      BonyWriterScalar.string('name', path.name), indent + 1, fields);
  _addScalarField(out, 'path', 'bone',
      BonyWriterScalar.string('bone', path.bone), indent + 1, fields);
  _addScalarField(out, 'path', 'target',
      BonyWriterScalar.string('target', path.target), indent + 1, fields);
  _addScalarField(out, 'path', 'path',
      BonyWriterScalar.string('path', path.path), indent + 1, fields);
  _addScalarField(out, 'path', 'order',
      BonyWriterScalar.varint('order', path.order), indent + 1, fields);
  _addScalarField(
      out,
      'path',
      'skinRequired',
      BonyWriterScalar.bool('skinRequired', path.skinRequired),
      indent + 1,
      fields);
  if (path.position != null) {
    out.addF32Field('position', path.position!, indent + 1, fields);
  }
  if (path.translateMix != null) {
    out.addF32Field('translateMix', path.translateMix!, indent + 1, fields);
  }
  if (path.rotateMix != null) {
    out.addF32Field('rotateMix', path.rotateMix!, indent + 1, fields);
  }
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendIkConstraint(BonyJsonBuffer out, IkConstraintData ik, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'ikConstraint', 'name',
      BonyWriterScalar.string('name', ik.name), indent + 1, fields);
  out.addFieldPrefix('bones', indent + 1, fields);
  out.write(bonyCanonicalStringArrayJson(ik.bones));
  _addScalarField(out, 'ikConstraint', 'target',
      BonyWriterScalar.string('target', ik.target), indent + 1, fields);
  _addScalarField(out, 'ikConstraint', 'order',
      BonyWriterScalar.varint('order', ik.order), indent + 1, fields);
  _addScalarField(
      out,
      'ikConstraint',
      'skinRequired',
      BonyWriterScalar.bool('skinRequired', ik.skinRequired),
      indent + 1,
      fields);
  if (ik.mix != null) out.addF32Field('mix', ik.mix!, indent + 1, fields);
  if (ik.bendPositive != null) {
    out.addBoolField('bendPositive', ik.bendPositive!, indent + 1, fields);
  }
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendTransformConstraint(
    BonyJsonBuffer out, TransformConstraintData tc, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'transformConstraint', 'name',
      BonyWriterScalar.string('name', tc.name), indent + 1, fields);
  _addScalarField(out, 'transformConstraint', 'bone',
      BonyWriterScalar.string('bone', tc.bone), indent + 1, fields);
  _addScalarField(out, 'transformConstraint', 'target',
      BonyWriterScalar.string('target', tc.target), indent + 1, fields);
  _addScalarField(out, 'transformConstraint', 'order',
      BonyWriterScalar.varint('order', tc.order), indent + 1, fields);
  _addScalarField(
      out,
      'transformConstraint',
      'skinRequired',
      BonyWriterScalar.bool('skinRequired', tc.skinRequired),
      indent + 1,
      fields);
  if (tc.translateMix != null) {
    out.addF32Field('translateMix', tc.translateMix!, indent + 1, fields);
  }
  if (tc.rotateMix != null) {
    out.addF32Field('rotateMix', tc.rotateMix!, indent + 1, fields);
  }
  if (tc.scaleMix != null) {
    out.addF32Field('scaleMix', tc.scaleMix!, indent + 1, fields);
  }
  if (tc.shearMix != null) {
    out.addF32Field('shearMix', tc.shearMix!, indent + 1, fields);
  }
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendPhysicsConstraint(
    BonyJsonBuffer out, PhysicsConstraintData pc, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'physicsConstraint', 'name',
      BonyWriterScalar.string('name', pc.name), indent + 1, fields);
  _addScalarField(out, 'physicsConstraint', 'bone',
      BonyWriterScalar.string('bone', pc.bone), indent + 1, fields);
  _addScalarField(out, 'physicsConstraint', 'order',
      BonyWriterScalar.varint('order', pc.order), indent + 1, fields);
  _addScalarField(
      out,
      'physicsConstraint',
      'skinRequired',
      BonyWriterScalar.bool('skinRequired', pc.skinRequired),
      indent + 1,
      fields);
  _addScalarField(
      out,
      'physicsConstraint',
      'channels',
      BonyWriterScalar.varuint('channels', physicsChannelsToMask(pc.channels)),
      indent + 1,
      fields);
  if (pc.inertia != null) {
    out.addF32Field('inertia', pc.inertia!, indent + 1, fields);
  }
  if (pc.strength != null) {
    out.addF32Field('strength', pc.strength!, indent + 1, fields);
  }
  if (pc.damping != null) {
    out.addF32Field('damping', pc.damping!, indent + 1, fields);
  }
  if (pc.mass != null) out.addF32Field('mass', pc.mass!, indent + 1, fields);
  if (pc.gravity != null) {
    out.addF32Field('gravity', pc.gravity!, indent + 1, fields);
  }
  if (pc.wind != null) out.addF32Field('wind', pc.wind!, indent + 1, fields);
  if (pc.physicsMix != null) {
    out.addF32Field('physicsMix', pc.physicsMix!, indent + 1, fields);
  }
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendPathAttachment(
    BonyJsonBuffer out, PathAttachment path, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'pathAttachment', 'name',
      BonyWriterScalar.string('name', path.name), indent + 1, fields);
  _addScalarField(out, 'pathAttachment', 'p0x',
      BonyWriterScalar.f64('p0x', path.p0x), indent + 1, fields);
  _addScalarField(out, 'pathAttachment', 'p0y',
      BonyWriterScalar.f64('p0y', path.p0y), indent + 1, fields);
  _addScalarField(out, 'pathAttachment', 'p1x',
      BonyWriterScalar.f64('p1x', path.p1x), indent + 1, fields);
  _addScalarField(out, 'pathAttachment', 'p1y',
      BonyWriterScalar.f64('p1y', path.p1y), indent + 1, fields);
  _addScalarField(out, 'pathAttachment', 'p2x',
      BonyWriterScalar.f64('p2x', path.p2x), indent + 1, fields);
  _addScalarField(out, 'pathAttachment', 'p2y',
      BonyWriterScalar.f64('p2y', path.p2y), indent + 1, fields);
  _addScalarField(out, 'pathAttachment', 'p3x',
      BonyWriterScalar.f64('p3x', path.p3x), indent + 1, fields);
  _addScalarField(out, 'pathAttachment', 'p3y',
      BonyWriterScalar.f64('p3y', path.p3y), indent + 1, fields);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendClippingAttachment(
    BonyJsonBuffer out, ClippingAttachment clip, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'clippingAttachment', 'name',
      BonyWriterScalar.string('name', clip.name), indent + 1, fields);
  out.addFieldPrefix('vertices', indent + 1, fields);
  _appendNumberArray(out, clip.vertices);
  _addScalarField(out, 'clippingAttachment', 'untilSlot',
      BonyWriterScalar.string('untilSlot', clip.untilSlot), indent + 1, fields);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendMeshAttachment(
    BonyJsonBuffer out, MeshAttachment mesh, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'meshAttachment', 'name',
      BonyWriterScalar.string('name', mesh.name), indent + 1, fields);
  _addScalarField(out, 'meshAttachment', 'weighted',
      BonyWriterScalar.bool('meshWeighted', mesh.weighted), indent + 1, fields);
  out.addFieldPrefix('vertices', indent + 1, fields);
  out.write(bonyCanonicalMeshVerticesJson(mesh.vertices, indent: indent + 1));
  out.addFieldPrefix('uvs', indent + 1, fields);
  out.write(bonyCanonicalMeshUvsJson(mesh.uvs));
  out.addFieldPrefix('triangles', indent + 1, fields);
  out.write(bonyCanonicalIntArrayJson(mesh.triangles));
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendParameter(BonyJsonBuffer out, ParameterAxis parameter, int indent) {
  out.addIndent(indent);
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(out, 'parameter', 'name',
      BonyWriterScalar.string('name', parameter.name), indent + 1, fields);
  _addScalarField(
      out,
      'parameter',
      'min',
      BonyWriterScalar.f32('parameterMin', parameter.minValue),
      indent + 1,
      fields);
  _addScalarField(
      out,
      'parameter',
      'max',
      BonyWriterScalar.f32('parameterMax', parameter.maxValue),
      indent + 1,
      fields);
  _addScalarField(
      out,
      'parameter',
      'default',
      BonyWriterScalar.f32('parameterDefault', parameter.defaultValue),
      indent + 1,
      fields);
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
}

List<SkinData> bonyCanonicalOrderedSkins(SkeletonData data) {
  final result = <SkinData>[];
  for (final skin in data.skins) {
    if (skin.name == 'default') {
      result.add(skin);
      break;
    }
  }
  for (final skin in data.skins) {
    if (skin.name != 'default') result.add(skin);
  }
  return result;
}

List<String> bonyCanonicalOrderedMembership(
  Iterable<String> refs,
  Iterable<String> orderedNames,
) {
  final refSet = refs.toSet();
  return [
    for (final name in orderedNames)
      if (refSet.contains(name)) name
  ];
}

List<SkinEntryData> bonyCanonicalSkinEntries(
  SkeletonData data,
  SkinData skin,
) {
  final slotOrder = <String, int>{
    for (var i = 0; i < data.slots.length; i++) data.slots[i].name: i,
  };
  return List<SkinEntryData>.from(skin.entries)
    ..sort((a, b) {
      final bySlot = (slotOrder[a.slot] ?? 0x7fffffff)
          .compareTo(slotOrder[b.slot] ?? 0x7fffffff);
      if (bySlot != 0) return bySlot;
      return a.attachment.compareTo(b.attachment);
    });
}

String bonyCanonicalStringArrayJson(Iterable<String> values) {
  final buffer = StringBuffer('[');
  var first = true;
  for (final value in values) {
    if (!first) buffer.write(', ');
    first = false;
    buffer.write(bonyCanonicalJsonString(value));
  }
  buffer.write(']');
  return buffer.toString();
}

String bonyCanonicalMeshVerticesJson(
  List<MeshVertex> vertices, {
  int indent = 0,
}) {
  final out = BonyJsonBuffer();
  out.write('[\n');
  for (var vertexIndex = 0; vertexIndex < vertices.length; vertexIndex++) {
    if (vertexIndex > 0) out.write(',\n');
    final vertex = vertices[vertexIndex];
    out.addIndent(indent + 1);
    if (vertex.weighted) {
      out.write('{"influences": [');
      for (var infIndex = 0; infIndex < vertex.influences.length; infIndex++) {
        if (infIndex > 0) out.write(', ');
        final influence = vertex.influences[infIndex];
        out.write('{"bone": ');
        out.write(bonyCanonicalJsonString(influence.bone));
        out.write(', "bindX": ');
        out.write(bonyCanonicalNumber(influence.bindX));
        out.write(', "bindY": ');
        out.write(bonyCanonicalNumber(influence.bindY));
        out.write(', "weight": ');
        out.write(bonyCanonicalNumber(influence.weight));
        out.write('}');
      }
      out.write(']}');
    } else {
      out.write('{"x": ');
      out.write(bonyCanonicalNumber(vertex.x));
      out.write(', "y": ');
      out.write(bonyCanonicalNumber(vertex.y));
      out.write('}');
    }
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
  return out.toString();
}

String bonyCanonicalMeshUvsJson(List<MeshUv> uvs) {
  final buffer = StringBuffer('[');
  for (var i = 0; i < uvs.length; i++) {
    if (i > 0) buffer.write(', ');
    buffer.write(bonyCanonicalNumber(uvs[i].u));
    buffer.write(', ');
    buffer.write(bonyCanonicalNumber(uvs[i].v));
  }
  buffer.write(']');
  return buffer.toString();
}

String bonyCanonicalIntArrayJson(List<int> values) {
  final buffer = StringBuffer('[');
  for (var i = 0; i < values.length; i++) {
    if (i > 0) buffer.write(', ');
    buffer.write(values[i]);
  }
  buffer.write(']');
  return buffer.toString();
}

String bonyCanonicalSkinJson(
  SkeletonData data,
  SkinData skin, {
  int indent = 0,
}) {
  final out = BonyJsonBuffer();
  out.write('{\n');
  final fields = FieldState();
  out.addStringField('name', skin.name, indent + 1, fields);
  _addStringArrayField(
    out,
    'bones',
    bonyCanonicalOrderedMembership(skin.bones, data.bones.map((b) => b.name)),
    indent + 1,
    fields,
  );
  _addStringArrayField(
    out,
    'ikConstraints',
    bonyCanonicalOrderedMembership(
      skin.ikConstraints,
      data.ikConstraints.map((c) => c.name),
    ),
    indent + 1,
    fields,
  );
  _addStringArrayField(
    out,
    'transformConstraints',
    bonyCanonicalOrderedMembership(
      skin.transformConstraints,
      data.transformConstraints.map((c) => c.name),
    ),
    indent + 1,
    fields,
  );
  _addStringArrayField(
    out,
    'pathConstraints',
    bonyCanonicalOrderedMembership(
      skin.pathConstraints,
      data.paths.map((c) => c.name),
    ),
    indent + 1,
    fields,
  );
  _addStringArrayField(
    out,
    'physicsConstraints',
    bonyCanonicalOrderedMembership(
      skin.physicsConstraints,
      data.physicsConstraints.map((c) => c.name),
    ),
    indent + 1,
    fields,
  );
  final entries = bonyCanonicalSkinEntries(data, skin);
  if (entries.isNotEmpty) {
    out.addFieldPrefix('entries', indent + 1, fields);
    out.write('[\n');
    for (var i = 0; i < entries.length; i++) {
      if (i > 0) out.write(',\n');
      final entry = entries[i];
      out.addIndent(indent + 2);
      out.write('{\n');
      final entryFields = FieldState();
      out.addStringField('slot', entry.slot, indent + 3, entryFields);
      out.addStringField(
          'attachment', entry.attachment, indent + 3, entryFields);
      out.addStringField('target', entry.target, indent + 3, entryFields);
      out.write('\n');
      out.addIndent(indent + 2);
      out.write('}');
    }
    out.write('\n');
    out.addIndent(indent + 1);
    out.write(']');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
  return out.toString();
}

String bonyBoneTimelineProperty(BoneTimelineKind kind) => switch (kind) {
      BoneTimelineKind.rotate => 'rotate',
      BoneTimelineKind.translateX => 'translateX',
      BoneTimelineKind.translateY => 'translateY',
      BoneTimelineKind.scaleX => 'scaleX',
      BoneTimelineKind.scaleY => 'scaleY',
      BoneTimelineKind.shearX => 'shearX',
      BoneTimelineKind.shearY => 'shearY',
      BoneTimelineKind.translate => 'translate',
      BoneTimelineKind.scale => 'scale',
      BoneTimelineKind.shear => 'shear',
      BoneTimelineKind.inherit => 'inherit',
    };

String bonySlotTimelineProperty(SlotTimelineKind kind) => switch (kind) {
      SlotTimelineKind.attachment => 'attachment',
      SlotTimelineKind.rgba => 'rgba',
      SlotTimelineKind.rgb => 'rgb',
      SlotTimelineKind.alpha => 'alpha',
      SlotTimelineKind.rgba2 => 'rgba2',
      SlotTimelineKind.sequence => 'sequence',
    };

String bonySequenceModeName(SequenceMode mode) => switch (mode) {
      SequenceMode.once => 'once',
      SequenceMode.loop => 'loop',
      SequenceMode.pingpong => 'pingpong',
      SequenceMode.reverse => 'reverse',
      SequenceMode.hold => 'hold',
    };

String bonyStateMachineInputKindName(StateMachineInputKind kind) =>
    switch (kind) {
      StateMachineInputKind.bool_ => 'bool',
      StateMachineInputKind.number => 'number',
      StateMachineInputKind.trigger => 'trigger',
    };

String bonyStateMachineConditionKindName(StateMachineConditionKind kind) =>
    switch (kind) {
      StateMachineConditionKind.boolEquals => 'boolEquals',
      StateMachineConditionKind.numberEquals => 'numberEquals',
      StateMachineConditionKind.numberGreater => 'numberGreater',
      StateMachineConditionKind.numberGreaterOrEqual => 'numberGreaterOrEqual',
      StateMachineConditionKind.numberLess => 'numberLess',
      StateMachineConditionKind.numberLessOrEqual => 'numberLessOrEqual',
      StateMachineConditionKind.triggerSet => 'triggerSet',
    };

String bonyStateMachineListenerKindName(StateMachineListenerKind kind) =>
    switch (kind) {
      StateMachineListenerKind.stateEnter => 'stateEnter',
      StateMachineListenerKind.stateExit => 'stateExit',
      StateMachineListenerKind.transition_ => 'transition',
      StateMachineListenerKind.pointerDown => 'pointerDown',
      StateMachineListenerKind.pointerUp => 'pointerUp',
      StateMachineListenerKind.pointerEnter => 'pointerEnter',
      StateMachineListenerKind.pointerExit => 'pointerExit',
      StateMachineListenerKind.pointerMove => 'pointerMove',
    };

String bonyPointerHelperTargetKindName(PointerHelperTargetKind kind) =>
    switch (kind) {
      PointerHelperTargetKind.point => 'point',
      PointerHelperTargetKind.boundingBox => 'boundingBox',
    };

String bonyCanonicalDeformerRecordJson(
  DeformerRecord record, {
  int indent = 0,
}) {
  final out = BonyJsonBuffer();
  final deformer = record.deformer;
  out.write('{\n');
  final fields = FieldState();
  out.addStringField('id', deformer.id, indent + 1, fields);
  _addScalarField(
    out,
    'deformer',
    'parent',
    BonyWriterScalar.string('parent', deformer.parent),
    indent + 1,
    fields,
  );
  out.addIntField('order', deformer.order, indent + 1, fields);
  out.addStringField(
    'kind',
    switch (deformer.kind) {
      DeformerKind.warp => 'warp',
      DeformerKind.rotation => 'rotation',
    },
    indent + 1,
    fields,
  );
  switch (deformer) {
    case WarpDeformer(:final warp):
      out.addFieldPrefix('warp', indent + 1, fields);
      out.write(_canonicalWarpJson(warp, indent + 1));
    case RotationDeformer(:final rotation):
      out.addFieldPrefix('rotation', indent + 1, fields);
      out.write(_canonicalRotationDeformerJson(rotation, indent + 1));
  }
  final blend = record.keyformBlend;
  if (blend.axes.isNotEmpty && blend.keyforms.isNotEmpty) {
    out.addFieldPrefix('keyformBlend', indent + 1, fields);
    out.write('{\n');
    out.addIndent(indent + 2);
    out.write('"axes": ');
    out.write(bonyCanonicalStringArrayJson(blend.axes.map((a) => a.name)));
    out.write(',\n');
    out.addIndent(indent + 2);
    out.write('"keyforms": [\n');
    for (var i = 0; i < blend.keyforms.length; i++) {
      if (i > 0) out.write(',\n');
      final keyform = blend.keyforms[i];
      out.addIndent(indent + 3);
      out.write('{\n');
      out.addIndent(indent + 4);
      out.write('"coordinates": {');
      for (var c = 0; c < keyform.coordinates.length; c++) {
        if (c > 0) out.write(', ');
        final coord = keyform.coordinates[c];
        out.write(bonyCanonicalJsonString(coord.name));
        out.write(': ');
        out.write(bonyCanonicalNumber(coord.value));
      }
      out.write('},\n');
      out.addIndent(indent + 4);
      out.write('"values": [');
      for (var v = 0; v < keyform.values.length; v++) {
        if (v > 0) out.write(', ');
        out.write(bonyCanonicalNumber(keyform.values[v]));
      }
      out.write(']\n');
      out.addIndent(indent + 3);
      out.write('}');
    }
    out.write('\n');
    out.addIndent(indent + 2);
    out.write(']\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
  return out.toString();
}

List<DrawOrderOffset> bonyCanonicalDrawOrderOffsets(
  DrawOrderKeyframe key,
  List<SlotData> setupSlots,
) {
  final slotOrder = <String, int>{
    for (var i = 0; i < setupSlots.length; i++) setupSlots[i].name: i,
  };
  return List<DrawOrderOffset>.from(key.offsets)
    ..sort((a, b) {
      final bySlot = (slotOrder[a.slot] ?? 0x7fffffff)
          .compareTo(slotOrder[b.slot] ?? 0x7fffffff);
      if (bySlot != 0) return bySlot;
      return a.slot.compareTo(b.slot);
    });
}

String bonyCanonicalAnimationClipJson(
  AnimationClip animation, {
  List<SlotData> setupSlots = const [],
  int indent = 0,
}) {
  final out = BonyJsonBuffer();
  out.write('{\n');
  final fields = FieldState();
  out.addStringField('name', animation.name, indent + 1, fields);
  if (animation.boneTimelines.isNotEmpty) {
    out.addFieldPrefix('boneTimelines', indent + 1, fields);
    _appendBoneTimelines(out, animation.boneTimelines, indent + 1);
  }
  if (animation.slotTimelines.isNotEmpty) {
    out.addFieldPrefix('slotTimelines', indent + 1, fields);
    _appendSlotTimelines(out, animation.slotTimelines, indent + 1);
  }
  if (animation.drawOrderTimeline case final timeline?) {
    out.addFieldPrefix('drawOrderTimeline', indent + 1, fields);
    _appendDrawOrderTimeline(out, timeline, setupSlots, indent + 1);
  }
  if (animation.deformTimelines.isNotEmpty) {
    out.addFieldPrefix('deformTimelines', indent + 1, fields);
    _appendDeformTimelines(out, animation.deformTimelines, indent + 1);
  }
  if (animation.eventTimelines.isNotEmpty) {
    out.addFieldPrefix('eventTimelines', indent + 1, fields);
    _appendEventTimelines(out, animation.eventTimelines, indent + 1);
  }
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
  return out.toString();
}

String bonyCanonicalStateMachineJson(
  StateMachineData machine, {
  int indent = 0,
}) {
  final out = BonyJsonBuffer();
  out.write('{\n');
  final fields = FieldState();
  out.addStringField('name', machine.name, indent + 1, fields);
  if (machine.inputs.isNotEmpty) {
    out.addFieldPrefix('inputs', indent + 1, fields);
    out.write('[\n');
    for (var i = 0; i < machine.inputs.length; i++) {
      if (i > 0) out.write(',\n');
      final input = machine.inputs[i];
      out.addIndent(indent + 2);
      out.write('{\n');
      final inputFields = FieldState();
      out.addStringField('name', input.name, indent + 3, inputFields);
      out.addStringField(
        'kind',
        bonyStateMachineInputKindName(input.kind),
        indent + 3,
        inputFields,
      );
      switch (input.kind) {
        case StateMachineInputKind.bool_:
          if (input.defaultBool) {
            out.addBoolField(
                'default', input.defaultBool, indent + 3, inputFields);
          }
        case StateMachineInputKind.number:
          if (input.defaultNumber != 0.0) {
            out.addF32Field(
                'default', input.defaultNumber, indent + 3, inputFields);
          }
        case StateMachineInputKind.trigger:
          break;
      }
      out.write('\n');
      out.addIndent(indent + 2);
      out.write('}');
    }
    out.write('\n');
    out.addIndent(indent + 1);
    out.write(']');
  }
  out.addFieldPrefix('layers', indent + 1, fields);
  _appendStateMachineLayers(out, machine.layers, indent + 1);
  if (machine.listeners.isNotEmpty) {
    out.addFieldPrefix('listeners', indent + 1, fields);
    _appendStateMachineListeners(
        out, machine.listeners, machine.inputs, indent + 1);
  }
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
  return out.toString();
}

void _addScalarField(
  BonyJsonBuffer out,
  String objectId,
  String jsonKey,
  BonyWriterScalar scalar,
  int indent,
  FieldState fields,
) {
  if (bonyShouldOmitDefault(objectId, scalar)) return;
  out.addFieldPrefix(jsonKey, indent, fields);
  _writeScalarValue(out, scalar);
}

void _writeScalarValue(BonyJsonBuffer out, BonyWriterScalar scalar) {
  switch (scalar.kind) {
    case BonyWriterScalarKind.string:
      out.write(bonyCanonicalJsonString(scalar.value as String));
    case BonyWriterScalarKind.f32:
      out.write(bonyCanonicalF32Number(scalar.value as double));
    case BonyWriterScalarKind.f64:
      out.write(bonyCanonicalNumber(scalar.value as double));
    case BonyWriterScalarKind.bool_:
      out.write((scalar.value as bool) ? 'true' : 'false');
    case BonyWriterScalarKind.varint:
    case BonyWriterScalarKind.varuint:
      out.write(scalar.value.toString());
    case BonyWriterScalarKind.bytes:
      final bytes = scalar.value as List<int>;
      out.write(bonyCanonicalIntArrayJson(bytes));
  }
}

void _addStringArrayField(
  BonyJsonBuffer out,
  String key,
  List<String> values,
  int indent,
  FieldState fields,
) {
  if (values.isEmpty) return;
  out.addFieldPrefix(key, indent, fields);
  out.write(bonyCanonicalStringArrayJson(values));
}

String _canonicalWarpJson(WarpLattice warp, int indent) {
  final out = BonyJsonBuffer();
  out.write('{\n');
  final fields = FieldState();
  out.addIntField('rows', warp.rows, indent + 1, fields);
  out.addIntField('cols', warp.cols, indent + 1, fields);
  _addScalarField(
    out,
    'warpLattice',
    'minX',
    BonyWriterScalar.f32('warpMinX', warp.minX),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'warpLattice',
    'minY',
    BonyWriterScalar.f32('warpMinY', warp.minY),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'warpLattice',
    'maxX',
    BonyWriterScalar.f32('warpMaxX', warp.maxX),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'warpLattice',
    'maxY',
    BonyWriterScalar.f32('warpMaxY', warp.maxY),
    indent + 1,
    fields,
  );
  out.addFieldPrefix('controlPoints', indent + 1, fields);
  out.write('[');
  for (var i = 0; i < warp.controlPoints.length; i++) {
    if (i > 0) out.write(', ');
    final cp = warp.controlPoints[i];
    out.write('{"x": ');
    out.write(bonyCanonicalNumber(cp.x));
    out.write(', "y": ');
    out.write(bonyCanonicalNumber(cp.y));
    out.write('}');
  }
  out.write(']\n');
  out.addIndent(indent);
  out.write('}');
  return out.toString();
}

String _canonicalRotationDeformerJson(
    RotationDeformerData rotation, int indent) {
  final out = BonyJsonBuffer();
  out.write('{\n');
  final fields = FieldState();
  _addScalarField(
    out,
    'rotationDeformer',
    'pivotX',
    BonyWriterScalar.f32('rotationPivotX', rotation.pivotX),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'rotationDeformer',
    'pivotY',
    BonyWriterScalar.f32('rotationPivotY', rotation.pivotY),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'rotationDeformer',
    'angleDegrees',
    BonyWriterScalar.f32('rotationAngleDegrees', rotation.angleDegrees),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'rotationDeformer',
    'scaleX',
    BonyWriterScalar.f32('rotationScaleX', rotation.scaleX),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'rotationDeformer',
    'scaleY',
    BonyWriterScalar.f32('rotationScaleY', rotation.scaleY),
    indent + 1,
    fields,
  );
  _addScalarField(
    out,
    'rotationDeformer',
    'opacity',
    BonyWriterScalar.f32('rotationOpacity', rotation.opacity),
    indent + 1,
    fields,
  );
  out.write('\n');
  out.addIndent(indent);
  out.write('}');
  return out.toString();
}

void _appendCurveFields(
  BonyJsonBuffer out,
  TimelineCurve curve,
  int indent,
  FieldState fields, {
  String key = 'curve',
}) {
  out.addStringField(
    key,
    switch (curve.kind) {
      TimelineCurveKind.linear => 'linear',
      TimelineCurveKind.stepped => 'stepped',
      TimelineCurveKind.bezier => 'bezier',
    },
    indent,
    fields,
  );
  if (curve.kind == TimelineCurveKind.bezier) {
    out.addF32Field('c1x', curve.c1x, indent, fields);
    out.addF32Field('c1y', curve.c1y, indent, fields);
    out.addF32Field('c2x', curve.c2x, indent, fields);
    out.addF32Field('c2y', curve.c2y, indent, fields);
  }
}

void _appendBoneTimelines(
  BonyJsonBuffer out,
  List<BoneTimeline> timelines,
  int indent,
) {
  out.write('[\n');
  for (var i = 0; i < timelines.length; i++) {
    if (i > 0) out.write(',\n');
    final timeline = timelines[i];
    out.addIndent(indent + 1);
    out.write('{\n');
    final fields = FieldState();
    out.addStringField('bone', timeline.bone, indent + 2, fields);
    out.addStringField('property', bonyBoneTimelineProperty(timeline.kind),
        indent + 2, fields);
    out.addFieldPrefix('keyframes', indent + 2, fields);
    out.write('[\n');
    switch (timeline.kind) {
      case BoneTimelineKind.inherit:
        _appendInheritKeyframes(out, timeline.inheritKeys, indent + 3);
      case BoneTimelineKind.translate:
      case BoneTimelineKind.scale:
      case BoneTimelineKind.shear:
        _appendVectorKeyframes(out, timeline.vectorKeys, indent + 3);
      default:
        _appendScalarKeyframes(out, timeline.scalarKeys, indent + 3);
    }
    out.write('\n');
    out.addIndent(indent + 2);
    out.write(']\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
}

void _appendScalarKeyframes(
  BonyJsonBuffer out,
  List<ScalarKeyframe> keys,
  int indent,
) {
  for (var i = 0; i < keys.length; i++) {
    if (i > 0) out.write(',\n');
    final key = keys[i];
    out.addIndent(indent);
    out.write('{\n');
    final fields = FieldState();
    out.addF32Field('t', key.time, indent + 1, fields);
    out.addF32Field('value', key.value, indent + 1, fields);
    _appendCurveFields(out, key.curve, indent + 1, fields);
    out.write('\n');
    out.addIndent(indent);
    out.write('}');
  }
}

void _appendVectorKeyframes(
  BonyJsonBuffer out,
  List<Vector2Keyframe> keys,
  int indent,
) {
  for (var i = 0; i < keys.length; i++) {
    if (i > 0) out.write(',\n');
    final key = keys[i];
    out.addIndent(indent);
    out.write('{\n');
    final fields = FieldState();
    out.addF32Field('t', key.time, indent + 1, fields);
    out.addF32Field('x', key.x, indent + 1, fields);
    out.addF32Field('y', key.y, indent + 1, fields);
    _appendCurveFields(out, key.curveX, indent + 1, fields, key: 'curveX');
    _appendCurveFields(out, key.curveY, indent + 1, fields, key: 'curveY');
    out.write('\n');
    out.addIndent(indent);
    out.write('}');
  }
}

void _appendInheritKeyframes(
  BonyJsonBuffer out,
  List<InheritKeyframe> keys,
  int indent,
) {
  for (var i = 0; i < keys.length; i++) {
    if (i > 0) out.write(',\n');
    final key = keys[i];
    out.addIndent(indent);
    out.write('{\n');
    final fields = FieldState();
    out.addF32Field('t', key.time, indent + 1, fields);
    out.addBoolField(
        'inheritRotation', key.inheritRotation, indent + 1, fields);
    out.addBoolField('inheritScale', key.inheritScale, indent + 1, fields);
    out.addBoolField(
        'inheritReflection', key.inheritReflection, indent + 1, fields);
    out.addStringField('transformMode', key.transformMode, indent + 1, fields);
    out.write('\n');
    out.addIndent(indent);
    out.write('}');
  }
}

void _appendSlotTimelines(
  BonyJsonBuffer out,
  List<SlotTimeline> timelines,
  int indent,
) {
  out.write('[\n');
  for (var i = 0; i < timelines.length; i++) {
    if (i > 0) out.write(',\n');
    final timeline = timelines[i];
    out.addIndent(indent + 1);
    out.write('{\n');
    final fields = FieldState();
    out.addStringField('slot', timeline.slot, indent + 2, fields);
    out.addStringField('property', bonySlotTimelineProperty(timeline.kind),
        indent + 2, fields);
    out.addFieldPrefix('keyframes', indent + 2, fields);
    out.write('[\n');
    switch (timeline.kind) {
      case SlotTimelineKind.attachment:
        _appendAttachmentKeyframes(out, timeline.attachmentKeys, indent + 3);
      case SlotTimelineKind.rgba:
      case SlotTimelineKind.rgb:
      case SlotTimelineKind.alpha:
        _appendColorKeyframes(out, timeline.colorKeys, indent + 3);
      case SlotTimelineKind.rgba2:
        _appendColor2Keyframes(out, timeline.color2Keys, indent + 3);
      case SlotTimelineKind.sequence:
        _appendSequenceKeyframes(out, timeline.sequenceKeys, indent + 3);
    }
    out.write('\n');
    out.addIndent(indent + 2);
    out.write(']\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
}

void _appendAttachmentKeyframes(
  BonyJsonBuffer out,
  List<AttachmentKeyframe> keys,
  int indent,
) {
  for (var i = 0; i < keys.length; i++) {
    if (i > 0) out.write(',\n');
    final key = keys[i];
    out.addIndent(indent);
    out.write('{\n');
    final fields = FieldState();
    out.addF32Field('t', key.time, indent + 1, fields);
    if (key.attachment.isNotEmpty) {
      out.addStringField('attachment', key.attachment, indent + 1, fields);
    }
    out.write('\n');
    out.addIndent(indent);
    out.write('}');
  }
}

void _appendColorKeyframes(
  BonyJsonBuffer out,
  List<ColorKeyframe> keys,
  int indent,
) {
  for (var i = 0; i < keys.length; i++) {
    if (i > 0) out.write(',\n');
    final key = keys[i];
    out.addIndent(indent);
    out.write('{\n');
    final fields = FieldState();
    out.addF32Field('t', key.time, indent + 1, fields);
    out.addF32Field('r', key.color.r, indent + 1, fields);
    out.addF32Field('g', key.color.g, indent + 1, fields);
    out.addF32Field('b', key.color.b, indent + 1, fields);
    out.addF32Field('a', key.color.a, indent + 1, fields);
    _appendCurveFields(out, key.curve, indent + 1, fields);
    out.write('\n');
    out.addIndent(indent);
    out.write('}');
  }
}

void _appendColor2Keyframes(
  BonyJsonBuffer out,
  List<Color2Keyframe> keys,
  int indent,
) {
  for (var i = 0; i < keys.length; i++) {
    if (i > 0) out.write(',\n');
    final key = keys[i];
    out.addIndent(indent);
    out.write('{\n');
    final fields = FieldState();
    out.addF32Field('t', key.time, indent + 1, fields);
    out.addF32Field('r', key.color.light.r, indent + 1, fields);
    out.addF32Field('g', key.color.light.g, indent + 1, fields);
    out.addF32Field('b', key.color.light.b, indent + 1, fields);
    out.addF32Field('a', key.color.light.a, indent + 1, fields);
    out.addF32Field('dr', key.color.darkR, indent + 1, fields);
    out.addF32Field('dg', key.color.darkG, indent + 1, fields);
    out.addF32Field('db', key.color.darkB, indent + 1, fields);
    _appendCurveFields(out, key.curve, indent + 1, fields);
    out.write('\n');
    out.addIndent(indent);
    out.write('}');
  }
}

void _appendSequenceKeyframes(
  BonyJsonBuffer out,
  List<SequenceKeyframe> keys,
  int indent,
) {
  for (var i = 0; i < keys.length; i++) {
    if (i > 0) out.write(',\n');
    final key = keys[i];
    out.addIndent(indent);
    out.write('{\n');
    final fields = FieldState();
    out.addF32Field('t', key.time, indent + 1, fields);
    out.addIntField('index', key.index, indent + 1, fields);
    out.addF32Field('delay', key.delay, indent + 1, fields);
    out.addStringField(
        'mode', bonySequenceModeName(key.mode), indent + 1, fields);
    out.write('\n');
    out.addIndent(indent);
    out.write('}');
  }
}

void _appendDrawOrderTimeline(
  BonyJsonBuffer out,
  DrawOrderTimeline timeline,
  List<SlotData> setupSlots,
  int indent,
) {
  out.write('{\n');
  final fields = FieldState();
  out.addFieldPrefix('keyframes', indent + 1, fields);
  out.write('[\n');
  for (var i = 0; i < timeline.keys.length; i++) {
    if (i > 0) out.write(',\n');
    final key = timeline.keys[i];
    final offsets = setupSlots.isEmpty
        ? key.offsets
        : bonyCanonicalDrawOrderOffsets(key, setupSlots);
    out.addIndent(indent + 2);
    out.write('{\n');
    final keyFields = FieldState();
    out.addF32Field('t', key.time, indent + 3, keyFields);
    out.addFieldPrefix('offsets', indent + 3, keyFields);
    out.write('[');
    if (offsets.isNotEmpty) {
      out.write('\n');
      for (var j = 0; j < offsets.length; j++) {
        if (j > 0) out.write(',\n');
        final offset = offsets[j];
        out.addIndent(indent + 4);
        out.write('{\n');
        final offsetFields = FieldState();
        out.addStringField('slot', offset.slot, indent + 5, offsetFields);
        out.addIntField('offset', offset.offset, indent + 5, offsetFields);
        out.write('\n');
        out.addIndent(indent + 4);
        out.write('}');
      }
      out.write('\n');
      out.addIndent(indent + 3);
    }
    out.write(']\n');
    out.addIndent(indent + 2);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent + 1);
  out.write(']\n');
  out.addIndent(indent);
  out.write('}');
}

void _appendDeformTimelines(
  BonyJsonBuffer out,
  List<DeformTimeline> timelines,
  int indent,
) {
  out.write('[\n');
  for (var i = 0; i < timelines.length; i++) {
    if (i > 0) out.write(',\n');
    final timeline = timelines[i];
    out.addIndent(indent + 1);
    out.write('{\n');
    final fields = FieldState();
    out.addStringField('skin', timeline.skin, indent + 2, fields);
    out.addStringField('slot', timeline.slot, indent + 2, fields);
    out.addStringField('attachment', timeline.attachment, indent + 2, fields);
    out.addIntField('vertexCount', timeline.vertexCount, indent + 2, fields);
    out.addFieldPrefix('keyframes', indent + 2, fields);
    out.write('[\n');
    for (var k = 0; k < timeline.keys.length; k++) {
      if (k > 0) out.write(',\n');
      final key = timeline.keys[k];
      out.addIndent(indent + 3);
      out.write('{\n');
      final keyFields = FieldState();
      out.addF32Field('t', key.time, indent + 4, keyFields);
      out.addIntField('offset', key.offset, indent + 4, keyFields);
      out.addFieldPrefix('deltas', indent + 4, keyFields);
      out.write('[\n');
      for (var d = 0; d < key.deltas.length; d++) {
        if (d > 0) out.write(',\n');
        final delta = key.deltas[d];
        out.addIndent(indent + 5);
        out.write('{\n');
        final deltaFields = FieldState();
        out.addF32Field('x', delta.x, indent + 6, deltaFields);
        out.addF32Field('y', delta.y, indent + 6, deltaFields);
        out.write('\n');
        out.addIndent(indent + 5);
        out.write('}');
      }
      out.write('\n');
      out.addIndent(indent + 4);
      out.write(']');
      _appendCurveFields(out, key.curve, indent + 4, keyFields);
      out.write('\n');
      out.addIndent(indent + 3);
      out.write('}');
    }
    out.write('\n');
    out.addIndent(indent + 2);
    out.write(']\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
}

void _appendEventTimelines(
  BonyJsonBuffer out,
  List<EventTimeline> timelines,
  int indent,
) {
  out.write('[\n');
  for (var i = 0; i < timelines.length; i++) {
    if (i > 0) out.write(',\n');
    final timeline = timelines[i];
    out.addIndent(indent + 1);
    out.write('{\n');
    final fields = FieldState();
    out.addFieldPrefix('keyframes', indent + 2, fields);
    out.write('[\n');
    for (var k = 0; k < timeline.keys.length; k++) {
      if (k > 0) out.write(',\n');
      final key = timeline.keys[k];
      final event = key.event;
      out.addIndent(indent + 3);
      out.write('{\n');
      final keyFields = FieldState();
      out.addF32Field('t', key.time, indent + 4, keyFields);
      out.addStringField('name', event.name, indent + 4, keyFields);
      if (event.intValue != 0) {
        out.addIntField('intValue', event.intValue, indent + 4, keyFields);
      }
      if (event.floatValue != 0.0) {
        out.addF32Field('floatValue', event.floatValue, indent + 4, keyFields);
      }
      if (event.stringValue.isNotEmpty) {
        out.addStringField(
            'stringValue', event.stringValue, indent + 4, keyFields);
      }
      if (event.audioPath.isNotEmpty) {
        out.addStringField('audioPath', event.audioPath, indent + 4, keyFields);
      }
      if (event.volume != 1.0) {
        out.addF32Field('volume', event.volume, indent + 4, keyFields);
      }
      if (event.balance != 0.0) {
        out.addF32Field('balance', event.balance, indent + 4, keyFields);
      }
      out.write('\n');
      out.addIndent(indent + 3);
      out.write('}');
    }
    out.write('\n');
    out.addIndent(indent + 2);
    out.write(']\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
}

void _appendStateMachineLayers(
  BonyJsonBuffer out,
  List<StateMachineLayer> layers,
  int indent,
) {
  out.write('[\n');
  for (var i = 0; i < layers.length; i++) {
    if (i > 0) out.write(',\n');
    final layer = layers[i];
    out.addIndent(indent + 1);
    out.write('{\n');
    final fields = FieldState();
    out.addStringField('name', layer.name, indent + 2, fields);
    if (layer.states.isNotEmpty && layer.initialState != layer.states[0].name) {
      out.addStringField(
          'initialState', layer.initialState, indent + 2, fields);
    }
    out.addFieldPrefix('states', indent + 2, fields);
    _appendStateMachineStates(out, layer.states, indent + 2);
    if (layer.transitions.isNotEmpty) {
      out.addFieldPrefix('transitions', indent + 2, fields);
      _appendStateMachineTransitions(out, layer.transitions, indent + 2);
    }
    out.write('\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
}

void _appendStateMachineStates(
  BonyJsonBuffer out,
  List<StateMachineState> states,
  int indent,
) {
  out.write('[\n');
  for (var i = 0; i < states.length; i++) {
    if (i > 0) out.write(',\n');
    final state = states[i];
    out.addIndent(indent + 1);
    out.write('{\n');
    final fields = FieldState();
    out.addStringField('name', state.name, indent + 2, fields);
    switch (state.kind) {
      case StateMachineStateKind.clip:
        out.addStringField('kind', 'clip', indent + 2, fields);
        out.addStringField('clip', state.clipName, indent + 2, fields);
        if (state.loop)
          out.addBoolField('loop', state.loop, indent + 2, fields);
      case StateMachineStateKind.blend1d:
        out.addStringField('kind', 'blend1d', indent + 2, fields);
        out.addStringField('blendInput', state.blendInput, indent + 2, fields);
        out.addFieldPrefix('blendClips', indent + 2, fields);
        out.write('[\n');
        for (var c = 0; c < state.blendClips.length; c++) {
          if (c > 0) out.write(',\n');
          final clip = state.blendClips[c];
          out.addIndent(indent + 3);
          out.write('{\n');
          final clipFields = FieldState();
          out.addStringField('clip', clip.clipName, indent + 4, clipFields);
          out.addF32Field('value', clip.value, indent + 4, clipFields);
          if (clip.loop) {
            out.addBoolField('loop', clip.loop, indent + 4, clipFields);
          }
          out.write('\n');
          out.addIndent(indent + 3);
          out.write('}');
        }
        out.write('\n');
        out.addIndent(indent + 2);
        out.write(']');
    }
    out.write('\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
}

void _appendStateMachineTransitions(
  BonyJsonBuffer out,
  List<StateMachineTransition> transitions,
  int indent,
) {
  out.write('[\n');
  for (var i = 0; i < transitions.length; i++) {
    if (i > 0) out.write(',\n');
    final transition = transitions[i];
    out.addIndent(indent + 1);
    out.write('{\n');
    final fields = FieldState();
    out.addStringField('fromState', transition.fromState, indent + 2, fields);
    out.addStringField('toState', transition.toState, indent + 2, fields);
    out.addFieldPrefix('conditions', indent + 2, fields);
    out.write('[\n');
    for (var c = 0; c < transition.conditions.length; c++) {
      if (c > 0) out.write(',\n');
      final condition = transition.conditions[c];
      out.addIndent(indent + 3);
      out.write('{\n');
      final conditionFields = FieldState();
      out.addStringField('input', condition.input, indent + 4, conditionFields);
      out.addStringField(
        'kind',
        bonyStateMachineConditionKindName(condition.kind),
        indent + 4,
        conditionFields,
      );
      switch (condition.kind) {
        case StateMachineConditionKind.boolEquals:
          if (!condition.boolValue) {
            out.addBoolField(
                'value', condition.boolValue, indent + 4, conditionFields);
          }
        case StateMachineConditionKind.numberEquals:
        case StateMachineConditionKind.numberGreater:
        case StateMachineConditionKind.numberGreaterOrEqual:
        case StateMachineConditionKind.numberLess:
        case StateMachineConditionKind.numberLessOrEqual:
          out.addF32Field(
              'value', condition.numberValue, indent + 4, conditionFields);
        case StateMachineConditionKind.triggerSet:
          break;
      }
      out.write('\n');
      out.addIndent(indent + 3);
      out.write('}');
    }
    out.write('\n');
    out.addIndent(indent + 2);
    out.write(']\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
}

void _appendStateMachineListeners(
  BonyJsonBuffer out,
  List<StateMachineListener> listeners,
  List<StateMachineInput> inputs,
  int indent,
) {
  final inputKinds = <String, StateMachineInputKind>{
    for (final input in inputs) input.name: input.kind,
  };
  out.write('[\n');
  for (var i = 0; i < listeners.length; i++) {
    if (i > 0) out.write(',\n');
    final listener = listeners[i];
    out.addIndent(indent + 1);
    out.write('{\n');
    final fields = FieldState();
    out.addStringField('name', listener.name, indent + 2, fields);
    out.addStringField(
      'kind',
      bonyStateMachineListenerKindName(listener.kind),
      indent + 2,
      fields,
    );
    switch (listener.kind) {
      case StateMachineListenerKind.stateEnter:
      case StateMachineListenerKind.stateExit:
      case StateMachineListenerKind.transition_:
        out.addStringField('layer', listener.layer, indent + 2, fields);
        if (listener.fromState.isNotEmpty) {
          out.addStringField(
              'fromState', listener.fromState, indent + 2, fields);
        }
        if (listener.toState.isNotEmpty) {
          out.addStringField('toState', listener.toState, indent + 2, fields);
        }
      case StateMachineListenerKind.pointerDown:
      case StateMachineListenerKind.pointerUp:
      case StateMachineListenerKind.pointerEnter:
      case StateMachineListenerKind.pointerExit:
      case StateMachineListenerKind.pointerMove:
        out.addStringField('slot', listener.slot, indent + 2, fields);
        out.addStringField(
          'targetKind',
          bonyPointerHelperTargetKindName(listener.targetKind),
          indent + 2,
          fields,
        );
        out.addStringField('target', listener.target, indent + 2, fields);
        switch (listener.targetKind) {
          case PointerHelperTargetKind.point:
            final hitRadius = listener.hitRadius;
            if (hitRadius == null) {
              throw FormatException(
                  'point pointer listener hitRadius is required: ${listener.name}');
            }
            out.addF32Field('hitRadius', hitRadius, indent + 2, fields);
          case PointerHelperTargetKind.boundingBox:
            if (listener.hitRadius != null) {
              throw FormatException(
                  'bounding-box pointer listener must not contain hitRadius: '
                  '${listener.name}');
            }
        }
        out.addStringField('input', listener.input, indent + 2, fields);
        final inputKind = inputKinds[listener.input];
        if (inputKind == null) {
          throw FormatException(
              'pointer listener references unknown input: ${listener.input}');
        }
        switch (inputKind) {
          case StateMachineInputKind.bool_:
            final value = listener.boolValue;
            if (value == null || listener.numberValue != null) {
              throw FormatException(
                  'bool pointer listener requires exactly one bool value: '
                  '${listener.name}');
            }
            out.addBoolField('value', value, indent + 2, fields);
          case StateMachineInputKind.number:
            final value = listener.numberValue;
            if (value == null || listener.boolValue != null) {
              throw FormatException(
                  'number pointer listener requires exactly one numeric value: '
                  '${listener.name}');
            }
            out.addF32Field('value', value, indent + 2, fields);
          case StateMachineInputKind.trigger:
            if (listener.boolValue != null || listener.numberValue != null) {
              throw FormatException(
                  'trigger pointer listener must not contain a value: '
                  '${listener.name}');
            }
        }
    }
    out.write('\n');
    out.addIndent(indent + 1);
    out.write('}');
  }
  out.write('\n');
  out.addIndent(indent);
  out.write(']');
}

String? _fixedIfShortReferenceSpelling(double value) {
  final abs = value.abs();
  if (abs < 1e-7 || abs >= 1e-6) return null;
  var fixed = value.toStringAsFixed(20);
  while (fixed.contains('.') && fixed.endsWith('0')) {
    fixed = fixed.substring(0, fixed.length - 1);
  }
  if (fixed.endsWith('.')) fixed = fixed.substring(0, fixed.length - 1);
  return double.parse(fixed) == value ? fixed : null;
}

bool _listEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
