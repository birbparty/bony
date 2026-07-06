// Dart M20 skin conformance gate: first-class skin attachment-set loading,
// active-skin draw resolution, default fallback, and skin-resolved deform
// timelines from both .bony and .bnb assets.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show ByteData, Endian, Uint8List;

import 'package:bony/bony.dart';
import 'package:test/test.dart';

const double _tol = 1e-4;

void _expectClose(double actual, double expected, String label) {
  expect((actual - expected).abs(), lessThanOrEqualTo(_tol),
      reason: '$label: actual=$actual expected=$expected');
}

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
List<int> _bool(bool value) => [value ? 1 : 0];

List<int> _varuintPayload(int value) {
  final out = <int>[];
  _writeVaruint(out, value);
  return out;
}

List<int> _f64(double value) {
  final bytes = ByteData(8)..setFloat64(0, value, Endian.little);
  return bytes.buffer.asUint8List().toList();
}

List<int> _ikBonesPayload(int stringIndex) {
  final out = <int>[];
  _writeVaruint(out, 1);
  _writeVaruint(out, stringIndex);
  return out;
}

List<int> _indexListPayload(int sourceIndex) {
  final out = <int>[];
  _writeVaruint(out, 1);
  _writeVaruint(out, sourceIndex);
  return out;
}

Uint8List _skinRequiredBnb() {
  final out = <int>[
    0x42, 0x4f, 0x4e, 0x59,
    0x00,
    0x02,
    0x00,
  ];
  final strings = [
    'skin-required',
    'root',
    'gear',
    'rail',
    'aim',
    'copy',
    'follow',
    'spring',
    'default',
  ];
  _writeVaruint(out, strings.length);
  for (final value in strings) {
    _writeString(out, value);
  }

  _writeVaruint(out, 1);
  _writeProp(out, 1, _str(0));
  out.add(0);

  _writeVaruint(out, 2);
  _writeProp(out, 1, _str(1));
  out.add(0);

  _writeVaruint(out, 2);
  _writeProp(out, 1, _str(2));
  _writeProp(out, 3, _str(1));
  _writeProp(out, 4027, _bool(true));
  out.add(0);

  _writeVaruint(out, 4002);
  _writeProp(out, 1, _str(4));
  _writeProp(out, 4014, _ikBonesPayload(2));
  _writeProp(out, 4000, _str(1));
  _writeProp(out, 4027, _bool(true));
  out.add(0);

  _writeVaruint(out, 4003);
  _writeProp(out, 1, _str(5));
  _writeProp(out, 1012, _str(2));
  _writeProp(out, 4000, _str(1));
  _writeProp(out, 4027, _bool(true));
  out.add(0);

  _writeVaruint(out, 4001);
  _writeProp(out, 1, _str(3));
  for (final key in [4003, 4004, 4005, 4006, 4007, 4008, 4009, 4010]) {
    _writeProp(out, key, _f64(0));
  }
  out.add(0);

  _writeVaruint(out, 4000);
  _writeProp(out, 1, _str(6));
  _writeProp(out, 1012, _str(2));
  _writeProp(out, 4000, _str(1));
  _writeProp(out, 4001, _str(3));
  _writeProp(out, 4027, _bool(true));
  out.add(0);

  _writeVaruint(out, 4004);
  _writeProp(out, 1, _str(7));
  _writeProp(out, 1012, _str(2));
  _writeProp(out, 4027, _bool(true));
  _writeProp(out, 4026, _varuintPayload(1));
  out.add(0);

  _writeVaruint(out, 3003);
  _writeProp(out, 1, _str(8));
  _writeProp(out, 4028, _indexListPayload(1));
  _writeProp(out, 4029, _indexListPayload(0));
  _writeProp(out, 4030, _indexListPayload(0));
  _writeProp(out, 4031, _indexListPayload(0));
  _writeProp(out, 4032, _indexListPayload(0));
  out.add(0);

  out.add(0);
  return Uint8List.fromList(out);
}

const _skinRequiredJson = '''
{
  "skeleton": { "name": "skin-required" },
  "bones": [
    { "name": "root" },
    { "name": "gear", "parent": "root", "skinRequired": true }
  ],
  "ikConstraints": [
    { "name": "aim", "bones": ["gear"], "target": "root", "skinRequired": true }
  ],
  "transformConstraints": [
    { "name": "copy", "bone": "gear", "target": "root", "skinRequired": true }
  ],
  "pathAttachments": [
    { "name": "rail", "p0x": 0, "p0y": 0, "p1x": 0, "p1y": 0, "p2x": 0, "p2y": 0, "p3x": 0, "p3y": 0 }
  ],
  "paths": [
    { "name": "follow", "bone": "gear", "target": "root", "path": "rail", "skinRequired": true }
  ],
  "physicsConstraints": [
    { "name": "spring", "bone": "gear", "channels": 1, "skinRequired": true }
  ],
  "skins": [
    {
      "name": "default",
      "bones": ["gear"],
      "ikConstraints": ["aim"],
      "transformConstraints": ["copy"],
      "pathConstraints": ["follow"],
      "physicsConstraints": ["spring"]
    }
  ]
}
''';

Map<String, dynamic> _jsonFile(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

List<DrawBatch> _batchesAt(SkeletonData base, String activeSkin) {
  final story = base.stateMachines.firstWhere((s) => s.name == 'skin_story');
  final rt = initStateMachineRuntime(story);
  rt.update(0.0);
  final posed = applyPose(base, rt.evaluate(base).pose);
  return buildDrawBatches(posed, activeSkin: activeSkin);
}

void _expectDrawBatchesMatchGolden(
  List<DrawBatch> batches,
  Map<String, dynamic> golden,
  String label,
) {
  final expected = golden['drawBatches'] as List<dynamic>;
  expect(batches, hasLength(expected.length), reason: '$label batch count');

  for (var i = 0; i < expected.length; i++) {
    final eb = expected[i] as Map<String, dynamic>;
    final batch = batches[i];
    final batchLabel = '$label batch $i';
    expect(batch.slot, eb['slot'], reason: '$batchLabel.slot');
    expect(batch.bone, eb['bone'], reason: '$batchLabel.bone');
    expect(batch.attachment, eb['attachment'],
        reason: '$batchLabel.attachment');
    expect(batch.blendMode, eb['blendMode'], reason: '$batchLabel.blendMode');
    expect(batch.texturePage, eb['texturePage'],
        reason: '$batchLabel.texturePage');
    expect(batch.clipId, eb['clipId'], reason: '$batchLabel.clipId');
    final ew = eb['world'] as Map<String, dynamic>;
    _expectClose(batch.world.a, (ew['a'] as num).toDouble(), '$batchLabel.a');
    _expectClose(batch.world.b, (ew['b'] as num).toDouble(), '$batchLabel.b');
    _expectClose(batch.world.c, (ew['c'] as num).toDouble(), '$batchLabel.c');
    _expectClose(batch.world.d, (ew['d'] as num).toDouble(), '$batchLabel.d');
    _expectClose(
        batch.world.tx, (ew['tx'] as num).toDouble(), '$batchLabel.tx');
    _expectClose(
        batch.world.ty, (ew['ty'] as num).toDouble(), '$batchLabel.ty');

    final expectedIndices =
        (eb['indices'] as List<dynamic>).map((v) => (v as num).toInt());
    expect(batch.indices, expectedIndices, reason: '$batchLabel.indices');

    final ev = eb['vertices'] as List<dynamic>;
    expect(batch.vertices, hasLength(ev.length),
        reason: '$batchLabel vertex count');
    for (var v = 0; v < ev.length; v++) {
      final e = ev[v] as Map<String, dynamic>;
      final got = batch.vertices[v];
      final vertexLabel = '$batchLabel vertex $v';
      _expectClose(got.x, (e['x'] as num).toDouble(), '$vertexLabel.x');
      _expectClose(got.y, (e['y'] as num).toDouble(), '$vertexLabel.y');
      _expectClose(got.u, (e['u'] as num).toDouble(), '$vertexLabel.u');
      _expectClose(got.v, (e['v'] as num).toDouble(), '$vertexLabel.v');
      _expectClose(got.r, (e['r'] as num).toDouble(), '$vertexLabel.r');
      _expectClose(got.g, (e['g'] as num).toDouble(), '$vertexLabel.g');
      _expectClose(got.b, (e['b'] as num).toDouble(), '$vertexLabel.b');
      _expectClose(got.a, (e['a'] as num).toDouble(), '$vertexLabel.a');
    }
  }
}

void main() {
  group('M20 skin attachment-set parity', () {
    late SkeletonData fromJson;
    late SkeletonData fromBnb;
    late Map<String, dynamic> defaultGolden;
    late Map<String, dynamic> variantGolden;

    setUpAll(() {
      fromJson = loadBonyJson(
          File('../conformance/assets/m20_skin_rig.bony').readAsStringSync());
      fromBnb = loadBonyBnb(
          File('../conformance/assets/bnb/m20_skin_rig.bnb').readAsBytesSync());
      defaultGolden =
          _jsonFile('../conformance/goldens/m20_skin_default_default.json');
      variantGolden =
          _jsonFile('../conformance/goldens/m20_skin_variant_variant.json');
    });

    test('loads skins from .bony and .bnb', () {
      for (final data in [fromJson, fromBnb]) {
        expect(data.skins.map((s) => s.name), ['default', 'armor']);
        expect(data.hasSkin('default'), isTrue);
        expect(data.hasSkin('armor'), isTrue);
        expect(data.skins.first.entries.map((e) => e.target), [
          'body_default_region',
          'badge_default_region',
          'patch_default_mesh',
        ]);
      }
    });

    for (final source in ['bony', 'bnb']) {
      test('$source default skin matches golden', () {
        final data = source == 'bony' ? fromJson : fromBnb;
        _expectDrawBatchesMatchGolden(
          _batchesAt(data, 'default'),
          defaultGolden,
          '$source default',
        );
      });

      test('$source armor skin matches golden with fallback and deform', () {
        final data = source == 'bony' ? fromJson : fromBnb;
        _expectDrawBatchesMatchGolden(
          _batchesAt(data, 'armor'),
          variantGolden,
          '$source armor',
        );
      });
    }

    test('active skin and fallback are non-vacuous', () {
      final defaultBatches = _batchesAt(fromJson, 'default');
      final armorBatches = _batchesAt(fromJson, 'armor');
      expect(defaultBatches[0].attachment, 'body_default_region');
      expect(armorBatches[0].attachment, 'body_armor_region');
      expect(defaultBatches[1].attachment, 'badge_default_region');
      expect(armorBatches[1].attachment, 'badge_default_region');
      expect(defaultBatches[2].attachment, 'patch_default_mesh');
      expect(armorBatches[2].attachment, 'patch_variant_mesh');
      _expectClose(defaultBatches[2].vertices[2].y, 8.0, 'default patch v2.y');
      _expectClose(armorBatches[2].vertices[2].y, 20.0, 'armor patch v2.y');
    });
  });

  group('skinRequired format surface', () {
    test('loads JSON and BNB metadata', () {
      final fromJson = loadBonyJson(_skinRequiredJson);
      final fromBnb = loadBonyBnb(_skinRequiredBnb());
      for (final data in [fromJson, fromBnb]) {
        expect(data.bones[1].skinRequired, isTrue);
        expect(data.ikConstraints.single.skinRequired, isTrue);
        expect(data.transformConstraints.single.skinRequired, isTrue);
        expect(data.paths.single.skinRequired, isTrue);
        expect(data.physicsConstraints.single.skinRequired, isTrue);
        expect(data.skins.single.bones, ['gear']);
        expect(data.skins.single.ikConstraints, ['aim']);
        expect(data.skins.single.transformConstraints, ['copy']);
        expect(data.skins.single.pathConstraints, ['follow']);
        expect(data.skins.single.physicsConstraints, ['spring']);
      }
    });

    test('rejects malformed membership', () {
      expect(
        () => loadBonyJson(
          _skinRequiredJson.replaceFirst(
              '"name": "default",\n      "bones": ["gear"]',
              '"name": "default",\n      "bones": ["ghost"]'),
        ),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(
          _skinRequiredJson.replaceFirst(
              '"name": "default",\n      "bones": ["gear"]',
              '"name": "default",\n      "bones": ["gear", "gear"]'),
        ),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(
          _skinRequiredJson.replaceFirst(
              '"name": "default",\n      "bones": ["gear"]',
              '"name": "default",\n      "bones": ["root"]'),
        ),
        throwsFormatException,
      );
    });
  });
}
