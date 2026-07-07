import 'package:bony/src/writer.dart';
import 'package:test/test.dart';

void main() {
  group('canonical JSON strings', () {
    test('escapes only required characters', () {
      expect(
        bonyCanonicalJsonString('quote" slash/ backslash\\ café'),
        r'"quote\" slash/ backslash\\ café"',
      );
      expect(
        bonyCanonicalJsonString('\b\f\n\r\t\u0001'),
        r'"\b\f\n\r\t\u0001"',
      );
    });

    test('rejects unpaired UTF-16 surrogates', () {
      expect(
        () => bonyCanonicalJsonString(String.fromCharCode(0xd800)),
        throwsFormatException,
      );
      expect(
        () => bonyCanonicalJsonString(String.fromCharCode(0xdc00)),
        throwsFormatException,
      );
    });
  });

  group('canonical JSON numbers', () {
    test('matches current Nim reference spellings for important boundaries',
        () {
      expect(bonyCanonicalNumber(0.0), '0');
      expect(bonyCanonicalNumber(-0.0), '0');
      expect(bonyCanonicalNumber(1.0), '1');
      expect(bonyCanonicalNumber(1.5), '1.5');
      expect(bonyCanonicalNumber(0.000001), '0.000001');
      expect(bonyCanonicalNumber(0.0000001), '0.0000001');
      expect(bonyCanonicalNumber(1e-8), '1e-8');
      expect(bonyCanonicalNumber(1e20), '1e+20');
      expect(bonyCanonicalNumber(-1e20), '-1e+20');
      expect(bonyCanonicalNumber(9007199254740991.0), '9007199254740991');
      expect(bonyCanonicalNumber(9007199254740992.0), '9007199254740992.0');
    });

    test('rejects non-finite values', () {
      expect(() => bonyCanonicalNumber(double.nan), throwsFormatException);
      expect(() => bonyCanonicalNumber(double.infinity), throwsFormatException);
      expect(
        () => bonyCanonicalNumber(double.negativeInfinity),
        throwsFormatException,
      );
    });

    test('uses f32 quantization boundary', () {
      expect(bonyCanonicalF32Number(1.00000001), '1');
      expect(bonyCanonicalF32Number(-0.0), '0');
    });
  });

  group('default omission helpers', () {
    test('matches scalar defaults from generated metadata', () {
      expect(
        bonyShouldOmitDefault('bone', BonyWriterScalar.string('parent', '')),
        isTrue,
      );
      expect(
        bonyShouldOmitDefault('bone', BonyWriterScalar.f32('x', -0.0)),
        isTrue,
      );
      expect(
        bonyShouldOmitDefault(
          'bone',
          BonyWriterScalar.f32('scaleX', 1.00000001),
        ),
        isTrue,
      );
      expect(
        bonyShouldOmitDefault(
          'bone',
          BonyWriterScalar.bool('inheritRotation', true),
        ),
        isTrue,
      );
      expect(
        bonyShouldOmitDefault('path', BonyWriterScalar.varint('order', 0)),
        isTrue,
      );
      expect(
        bonyShouldOmitDefault('skin', BonyWriterScalar.bytes('skinBones', [])),
        isTrue,
      );
    });

    test('keeps non-default values and properties without omission defaults',
        () {
      expect(
        bonyShouldOmitDefault('bone', BonyWriterScalar.string('name', 'root')),
        isFalse,
      );
      expect(
        bonyShouldOmitDefault('bone', BonyWriterScalar.f32('x', 2)),
        isFalse,
      );
      expect(
        bonyShouldOmitDefault(
          'bone',
          BonyWriterScalar.bool('inheritRotation', false),
        ),
        isFalse,
      );
    });
  });

  test('BonyJsonBuffer emits indented field prefixes deterministically', () {
    final buffer = BonyJsonBuffer();
    final fields = FieldState();

    buffer.addStringField('name', 'a/bé', 1, fields);
    buffer.addNumberField('x', -0.0, 1, fields);
    buffer.addBoolField('visible', true, 1, fields);

    expect(
        buffer.toString(), '  "name": "a/bé",\n  "x": 0,\n  "visible": true');
  });
}
