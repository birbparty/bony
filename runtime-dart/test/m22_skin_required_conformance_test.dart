import 'dart:convert';
import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

const double _tol = 1e-4;

const _defaultSamples = <({String name, double t})>[
  (name: 'rest', t: 0.0),
  (name: 'late', t: 0.2),
];

const _variantSamples = <({String name, double t})>[
  (name: 'rest', t: 0.0),
  (name: 'active', t: 0.1),
  (name: 'settled', t: 0.2),
];

void _expectClose(double actual, double expected, String label) {
  expect((actual - expected).abs(), lessThanOrEqualTo(_tol),
      reason: '$label: actual=$actual expected=$expected');
}

void _expectAffine(
    Affine2 actual, Map<String, dynamic> expected, String label) {
  _expectClose(actual.a, (expected['a'] as num).toDouble(), '$label.a');
  _expectClose(actual.b, (expected['b'] as num).toDouble(), '$label.b');
  _expectClose(actual.c, (expected['c'] as num).toDouble(), '$label.c');
  _expectClose(actual.d, (expected['d'] as num).toDouble(), '$label.d');
  _expectClose(actual.tx, (expected['tx'] as num).toDouble(), '$label.tx');
  _expectClose(actual.ty, (expected['ty'] as num).toDouble(), '$label.ty');
}

Map<String, dynamic> _golden(String name) =>
    jsonDecode(File('../conformance/goldens/$name.json').readAsStringSync())
        as Map<String, dynamic>;

({
  Map<String, List<Affine2>> worlds,
  Map<String, List<DrawBatch>> batches,
}) _replay(
  SkeletonData base,
  String activeSkin,
  List<({String name, double t})> samples,
) {
  final story =
      base.stateMachines.firstWhere((s) => s.name == 'skin_required_story');
  final rt = initStateMachineRuntime(story);
  final states = newPhysicsStates(base);
  final worldsByName = <String, List<Affine2>>{};
  final batchesByName = <String, List<DrawBatch>>{};
  var previous = 0.0;
  for (final sample in samples) {
    final dt = sample.t - previous;
    rt.update(dt);
    final posed = applyPose(base, rt.evaluate(base).pose);
    worldsByName[sample.name] =
        advancePhysics(posed, states, dt, activeSkin: activeSkin);
    batchesByName[sample.name] =
        buildDrawBatches(posed, activeSkin: activeSkin);
    previous = sample.t;
  }
  return (worlds: worldsByName, batches: batchesByName);
}

void _expectGolden(
  SkeletonData data,
  List<Affine2> worlds,
  List<DrawBatch> batches,
  Map<String, dynamic> golden,
  String label,
) {
  expect(golden['format'], 'bony.numeric-golden.v1');
  expect(golden['skeleton'], data.header.name);

  final expectedBones =
      (golden['bones'] as List<dynamic>).cast<Map<String, dynamic>>();
  expect(worlds, hasLength(expectedBones.length), reason: '$label bone count');
  final expectedBoneByName = {
    for (final bone in expectedBones) bone['name'] as String: bone,
  };
  for (var index = 0; index < data.bones.length; index++) {
    final bone = data.bones[index];
    final expected = expectedBoneByName[bone.name];
    expect(expected, isNotNull, reason: '$label missing bone ${bone.name}');
    _expectAffine(worlds[index], expected!['world'] as Map<String, dynamic>,
        '$label ${bone.name}');
  }

  final expectedBatches =
      (golden['drawBatches'] as List<dynamic>).cast<Map<String, dynamic>>();
  expect(batches, hasLength(expectedBatches.length),
      reason: '$label draw batch count');
  for (var index = 0; index < expectedBatches.length; index++) {
    final expected = expectedBatches[index];
    final actual = batches[index];
    final batchLabel = '$label drawBatches[$index]';
    expect(actual.slot, expected['slot'], reason: '$batchLabel.slot');
    expect(actual.bone, expected['bone'], reason: '$batchLabel.bone');
    expect(actual.attachment, expected['attachment'],
        reason: '$batchLabel.attachment');
    expect(actual.blendMode, expected['blendMode'],
        reason: '$batchLabel.blendMode');
    expect(actual.texturePage, expected['texturePage'],
        reason: '$batchLabel.texturePage');
    expect(actual.clipId, expected['clipId'], reason: '$batchLabel.clipId');
    _expectAffine(
        actual.world, expected['world'] as Map<String, dynamic>, batchLabel);
    expect(actual.indices,
        (expected['indices'] as List<dynamic>).map((v) => (v as num).toInt()),
        reason: '$batchLabel.indices');

    final expectedVertices =
        (expected['vertices'] as List<dynamic>).cast<Map<String, dynamic>>();
    expect(actual.vertices, hasLength(expectedVertices.length),
        reason: '$batchLabel vertex count');
    for (var vertexIndex = 0;
        vertexIndex < expectedVertices.length;
        vertexIndex++) {
      final expectedVertex = expectedVertices[vertexIndex];
      final actualVertex = actual.vertices[vertexIndex];
      final vertexLabel = '$batchLabel.vertices[$vertexIndex]';
      _expectClose(actualVertex.x, (expectedVertex['x'] as num).toDouble(),
          '$vertexLabel.x');
      _expectClose(actualVertex.y, (expectedVertex['y'] as num).toDouble(),
          '$vertexLabel.y');
      _expectClose(actualVertex.u, (expectedVertex['u'] as num).toDouble(),
          '$vertexLabel.u');
      _expectClose(actualVertex.v, (expectedVertex['v'] as num).toDouble(),
          '$vertexLabel.v');
      _expectClose(actualVertex.r, (expectedVertex['r'] as num).toDouble(),
          '$vertexLabel.r');
      _expectClose(actualVertex.g, (expectedVertex['g'] as num).toDouble(),
          '$vertexLabel.g');
      _expectClose(actualVertex.b, (expectedVertex['b'] as num).toDouble(),
          '$vertexLabel.b');
      _expectClose(actualVertex.a, (expectedVertex['a'] as num).toDouble(),
          '$vertexLabel.a');
    }
  }
}

void main() {
  group('M22 skinRequired activation conformance', () {
    late String assetText;
    late SkeletonData fromJson;
    late SkeletonData fromBnb;

    setUpAll(() {
      assetText = File('../conformance/assets/m22_skin_required_rig.bony')
          .readAsStringSync();
      fromJson = loadBonyJson(assetText);
      fromBnb = loadBonyBnb(
          File('../conformance/assets/bnb/m22_skin_required_rig.bnb')
              .readAsBytesSync());
    });

    test('active membership exposes default plus active skin', () {
      final variant = fromJson.activeSkinMembership('variant');
      expect(fromJson.skins[1].bones, ['shared_helper', 'variant_extra']);
      expect(variant.bones[1], isTrue);
      expect(variant.bones[2], isTrue);
      expect(fromJson.activeSkinMembership().bones[2], isFalse);
    });

    for (final source in ['bony', 'bnb']) {
      group(source, () {
        late SkeletonData data;
        late ({
          Map<String, List<Affine2>> worlds,
          Map<String, List<DrawBatch>> batches,
        }) defaultReplay;
        late ({
          Map<String, List<Affine2>> worlds,
          Map<String, List<DrawBatch>> batches,
        }) variantReplay;

        setUpAll(() {
          data = source == 'bony' ? fromJson : fromBnb;
          defaultReplay = _replay(data, 'default', _defaultSamples);
          variantReplay = _replay(data, 'variant', _variantSamples);
        });

        for (final sample in _defaultSamples) {
          test('default ${sample.name} matches golden', () {
            _expectGolden(
              data,
              defaultReplay.worlds[sample.name]!,
              defaultReplay.batches[sample.name]!,
              _golden('m22_skin_required_default_${sample.name}'),
              '$source default ${sample.name}',
            );
          });
        }

        for (final sample in _variantSamples) {
          test('variant ${sample.name} matches golden', () {
            _expectGolden(
              data,
              variantReplay.worlds[sample.name]!,
              variantReplay.batches[sample.name]!,
              _golden('m22_skin_required_variant_${sample.name}'),
              '$source variant ${sample.name}',
            );
          });
        }
      });
    }

    test('rejects malformed membership cases', () {
      expect(
        () => loadBonyJson(assetText.replaceFirst(
            '"bones": ["shared_helper"]', '"bones": ["ghost"]')),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(assetText.replaceFirst(
            '"physicsConstraints": ["skin_spring"]',
            '"physicsConstraints": ["skin_spring", "skin_spring"]')),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(assetText.replaceFirst(
            '"bones": ["shared_helper"]', '"bones": ["root"]')),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(assetText
            .replaceFirst('"bones": ["shared_helper"]', '"bones": []')
            .replaceFirst('"bones": ["shared_helper", "variant_extra"]',
                '"bones": ["variant_extra"]')),
        throwsFormatException,
      );
      expect(
        () => loadBonyJson(assetText.replaceFirst(
            '{"name": "copy_target", "parent": "root", "x": 90, "y": 30}',
            '{"name": "copy_target", "parent": "root", "x": 90, "y": 30, "skinRequired": true}')),
        throwsFormatException,
      );
    });
  });
}
