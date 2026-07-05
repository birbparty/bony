// Dart M20 skin conformance gate: first-class skin attachment-set loading,
// active-skin draw resolution, default fallback, and skin-resolved deform
// timelines from both .bony and .bnb assets.

import 'dart:convert';
import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

const double _tol = 1e-4;

void _expectClose(double actual, double expected, String label) {
  expect((actual - expected).abs(), lessThanOrEqualTo(_tol),
      reason: '$label: actual=$actual expected=$expected');
}

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
}
