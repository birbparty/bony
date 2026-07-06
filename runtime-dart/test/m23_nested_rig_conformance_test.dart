import 'dart:convert';
import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

const double _tol = 1e-4;

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

Map<String, dynamic> _golden() =>
    jsonDecode(File('../conformance/goldens/m23_nested_rig_t0.json')
        .readAsStringSync()) as Map<String, dynamic>;

void _expectGolden(
  SkeletonData data,
  List<DrawBatch> batches,
  Map<String, dynamic> golden,
  String label,
) {
  expect(golden['format'], 'bony.numeric-golden.v1');
  expect(golden['skeleton'], data.header.name);

  final worlds = computeWorldTransforms(data);
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
  group('M23 nested rig composition conformance', () {
    late Map<String, dynamic> golden;
    late SkeletonData hostJson;
    late SkeletonData hostBnb;
    late SkeletonData childJson;
    late SkeletonData childBnb;

    setUpAll(() {
      golden = _golden();
      hostJson = loadBonyJson(
          File('../conformance/assets/m23_nested_rig.bony').readAsStringSync());
      hostBnb = loadBonyBnb(File('../conformance/assets/bnb/m23_nested_rig.bnb')
          .readAsBytesSync());
      childJson = loadBonyJson(
          File('../conformance/assets/m23_nested_child_rig.bony')
              .readAsStringSync());
      childBnb = loadBonyBnb(
          File('../conformance/assets/bnb/m23_nested_child_rig.bnb')
              .readAsBytesSync());
    });

    for (final source in ['bony', 'bnb']) {
      test('$source matches nested golden', () {
        final host = source == 'bony' ? hostJson : hostBnb;
        final child = source == 'bony' ? childJson : childBnb;
        final batches = buildNestedDrawBatches(host, {'childRig': child});
        _expectGolden(host, batches, golden, source);
      });
    }

    test('legacy draw-batch API does not compose nested rigs', () {
      final legacy = buildDrawBatches(hostJson);
      expect(legacy.map((b) => b.slot).toList(), ['under_slot', 'after_slot']);
      expect(legacy.any((b) => b.slot == 'face_slot'), isFalse);
    });

    test('golden exercises affine, child skin, draw order, and host clipping',
        () {
      final batches = buildNestedDrawBatches(hostJson, {'childRig': childJson});
      expect(batches.map((b) => b.slot).toList(),
          ['under_slot', 'face_slot', 'after_slot', 'face_slot']);
      expect(batches[1].attachment, 'wide_face');
      expect(batches[3].attachment, 'default_face');
      expect(batches[1].clipId, 'host_clip');
      expect(batches[3].clipId, '');
      expect(
          batches[1].vertices.any((v) => (v.x - 45.0).abs() <= _tol), isTrue);
      expect((batches[1].vertices[0].x + 16.0).abs(), greaterThan(1e-4));
    });
  });
}
