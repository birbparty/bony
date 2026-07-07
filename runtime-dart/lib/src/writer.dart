import 'dart:convert' show jsonDecode;

import 'deform.dart' show quantizeF32;
import 'generated/wire.dart' as wire;

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

  void addBoolField(String key, bool value, int indent, FieldState state) {
    addFieldPrefix(key, indent, state);
    _buffer.write(value ? 'true' : 'false');
  }

  @override
  String toString() => _buffer.toString();
}

final class FieldState {
  FieldState();

  bool first = true;
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
