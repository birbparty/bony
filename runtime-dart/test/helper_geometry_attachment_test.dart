import 'dart:typed_data' show ByteData, Endian, Uint8List;

import 'package:bony/bony.dart';
import 'package:test/test.dart';

void _writeVaruint(List<int> out, int value) {
  var v = value;
  while (v >= 0x80) {
    out.add((v & 0x7f) | 0x80);
    v >>= 7;
  }
  out.add(v);
}

void _writeString(List<int> out, String value) {
  final units = value.codeUnits;
  _writeVaruint(out, units.length);
  out.addAll(units);
}

void _writeProp(List<int> out, int key, List<int> payload) {
  _writeVaruint(out, key);
  _writeVaruint(out, payload.length);
  out.addAll(payload);
}

List<int> _str(int index) => [index];

List<int> _f32(double value) {
  final bd = ByteData(4)..setFloat32(0, value, Endian.little);
  return [
    bd.getUint8(0),
    bd.getUint8(1),
    bd.getUint8(2),
    bd.getUint8(3),
  ];
}

List<int> _polygon(List<double> vertices) {
  final out = <int>[];
  _writeVaruint(out, vertices.length ~/ 2);
  for (final value in vertices) {
    out.addAll(_f32(value));
  }
  return out;
}

Uint8List _helperBnb() {
  final out = <int>[
    0x42, 0x4f, 0x4e, 0x59, // BONY
    0x00, // version
    0x02, // string table present
    0x00, // empty ToC; Dart semantic loader uses property byte lengths.
  ];
  final strings = [
    'helperdemo',
    'root',
    'pointSlot',
    'muzzle',
    'boxSlot',
    'button_hit',
    'regionSlot',
    'visible',
  ];
  _writeVaruint(out, strings.length);
  for (final value in strings) {
    _writeString(out, value);
  }

  _writeVaruint(out, 1); // skeleton
  _writeProp(out, 1, _str(0)); // name
  out.add(0);

  _writeVaruint(out, 2); // bone
  _writeProp(out, 1, _str(1)); // name
  out.add(0);

  _writeVaruint(out, 1000); // slot: pointSlot -> muzzle
  _writeProp(out, 1, _str(2));
  _writeProp(out, 1012, _str(1));
  _writeProp(out, 1013, _str(3));
  out.add(0);

  _writeVaruint(out, 1000); // slot: boxSlot -> button_hit
  _writeProp(out, 1, _str(4));
  _writeProp(out, 1012, _str(1));
  _writeProp(out, 1013, _str(5));
  out.add(0);

  _writeVaruint(out, 1000); // slot: regionSlot -> visible
  _writeProp(out, 1, _str(6));
  _writeProp(out, 1012, _str(1));
  _writeProp(out, 1013, _str(7));
  out.add(0);

  _writeVaruint(out, 1001); // region
  _writeProp(out, 1, _str(7));
  _writeProp(out, 1014, _f32(10));
  _writeProp(out, 1015, _f32(6));
  out.add(0);

  _writeVaruint(out, 1002); // pointAttachment
  _writeProp(out, 1, _str(3));
  _writeProp(out, 1000, _f32(3.5));
  _writeProp(out, 1001, _f32(-2.25));
  _writeProp(out, 1002, _f32(45));
  out.add(0);

  _writeVaruint(out, 1003); // boundingBoxAttachment
  _writeProp(out, 1, _str(5));
  _writeProp(out, 3000, _polygon([-5, -4, 5, -4, 5, 4, -5, 4]));
  out.add(0);

  out.add(0); // object stream terminator
  return Uint8List.fromList(out);
}

const _helperJson = '''
{
  "skeleton": {"name": "helperdemo", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [
    {"name": "pointSlot", "bone": "root", "attachment": "muzzle"},
    {"name": "boxSlot", "bone": "root", "attachment": "button_hit"},
    {"name": "regionSlot", "bone": "root", "attachment": "visible"}
  ],
  "regions": [{"name": "visible", "width": 10, "height": 6}],
  "pointAttachments": [
    {"name": "muzzle", "x": 3.5, "y": -2.25, "rotation": 45}
  ],
  "boundingBoxAttachments": [
    {"name": "button_hit", "vertices": [-5, -4, 5, -4, 5, 4, -5, 4]}
  ]
}
''';

void main() {
  group('helper geometry attachments', () {
    test('loads from JSON and remains invisible to draw batches', () {
      final data = loadBonyJson(_helperJson);
      expect(data.pointAttachments, hasLength(1));
      expect(data.pointAttachments.single.name, 'muzzle');
      expect(data.pointAttachments.single.x, closeTo(3.5, 1e-9));
      expect(data.pointAttachments.single.y, closeTo(-2.25, 1e-9));
      expect(data.pointAttachments.single.rotation, closeTo(45, 1e-9));
      expect(data.boundingBoxAttachments, hasLength(1));
      expect(data.boundingBoxAttachments.single.vertices,
          [-5, -4, 5, -4, 5, 4, -5, 4]);

      final batches = buildDrawBatches(data);
      expect(batches, hasLength(1));
      expect(batches.single.slot, 'regionSlot');
      expect(batches.single.attachment, 'visible');
    });

    test('loads helper attachments from .bnb', () {
      final data = loadBonyBnb(_helperBnb());
      expect(data.pointAttachments, hasLength(1));
      expect(data.pointAttachments.single.name, 'muzzle');
      expect(data.pointAttachments.single.rotation, closeTo(45, 1e-9));
      expect(data.boundingBoxAttachments, hasLength(1));
      expect(data.boundingBoxAttachments.single.name, 'button_hit');
      expect(data.boundingBoxAttachments.single.vertices,
          [-5, -4, 5, -4, 5, 4, -5, 4]);
      expect(buildDrawBatches(data), hasLength(1));
    });

    test('rejects malformed helper records', () {
      final duplicatePoints = _helperJson.replaceFirst(
        '{"name": "muzzle", "x": 3.5, "y": -2.25, "rotation": 45}',
        '{"name": "muzzle", "x": 3.5, "y": -2.25, "rotation": 45}, {"name": "muzzle", "x": 0, "y": 0, "rotation": 0}',
      );
      final concaveBox = _helperJson.replaceFirst(
        '[-5, -4, 5, -4, 5, 4, -5, 4]',
        '[0, 0, 2, 0, 0.5, 0.5, 0, 2]',
      );
      final unknownSlot = _helperJson.replaceFirst(
          '"attachment": "muzzle"', '"attachment": "missing"');

      expect(
          () => loadBonyJson(duplicatePoints), throwsA(isA<FormatException>()));
      expect(() => loadBonyJson(concaveBox), throwsA(isA<FormatException>()));
      expect(() => loadBonyJson(unknownSlot), throwsA(isA<FormatException>()));
    });
  });
}
