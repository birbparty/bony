// Dart IK constraint load parity (bony-me5.9).
//
// IK EVALUATION is out of scope in Dart: IK solving is an M5 Nim runtime
// feature not yet ported to Dart (mirrors the path-constraint evaluation
// deferral noted in m5_constraint_test.dart). This gate proves only that the
// model + JSON loader + .bnb loader carry IK constraint data through without
// error and in agreement, matching runtime-nim's on-load parity.
//
// The .bnb bytes below are produced by the Nim CLI (`bony json-to-bnb`) — the
// format authority — from the same skeleton as _ikJson. They are an in-test
// fixture, NOT a committed conformance asset (IK conformance fixtures arrive in
// step 3, bony-grr). Regenerate with:
//   bony json-to-bnb <_ikJson>.bony out.bnb && base64 out.bnb

import 'dart:convert';
import 'dart:typed_data';
import 'package:test/test.dart';
import 'package:bony/bony.dart';

const _ikJson = '''
{
  "skeleton": {"name": "ikdart", "version": "0.2.0"},
  "bones": [
    {"name": "root"},
    {"name": "b0", "parent": "root", "x": 10},
    {"name": "b1", "parent": "b0", "x": 10},
    {"name": "goal", "parent": "root", "x": 20, "y": 5}
  ],
  "ikConstraints": [
    {"name": "ik", "bones": ["b0", "b1"], "target": "goal", "order": 1, "mix": 0.3, "bendPositive": false}
  ]
}
''';

// Nim CLI (json-to-bnb) output for _ikJson. In-test fixture, not a conformance
// asset. mix=0.3 is deliberately NOT f32-exact so the cross-loader parity check
// proves the JSON path quantizes mix to the same f32 the .bnb path carries.
const _ikBnbBase64 =
    'Qk9OWQECCgEFAgUDBegHA+kHA6AfBaIfAq4fB68fA7AfBAcGaWtkYXJ0BTAuMi4wBHJvb3QCYjAC'
    'YjEEZ29hbAJpawEBAQACAQEAAgEBAgACAQEDAwEC6AcEAAAgQQACAQEEAwED6AcEAAAgQQACAQEF'
    'AwEC6AcEAACgQekHBAAAoEAAoh8BAQagHwEFoh8BAq4fAwIDBK8fBJqZmT6wHwEAAAA=';

// Nim CLI output for an IK constraint that omits mix/order/bendPositive.
const _ikOmitBnbBase64 =
    'Qk9OWQECBAEFAwWgHwWuHwcFBWlrbWluBHJvb3QCYjAEZ29hbAJpawEBAQAAAgEBAQACAQECAwEB'
    'AAIBAQMDAQEAoh8BAQSgHwEDrh8CAQIAAA==';

// f32-quantized 0.3, matching quantizeF32(0.3).
final double _mixQuantized = (ByteData(4)..setFloat32(0, 0.3, Endian.little))
    .getFloat32(0, Endian.little);

void _expectPrimaryIk(IkConstraintData ik, String src) {
  expect(ik.name, 'ik', reason: '$src name');
  expect(ik.bones, ['b0', 'b1'], reason: '$src bones');
  expect(ik.target, 'goal', reason: '$src target');
  expect(ik.order, 1, reason: '$src order');
  expect(ik.mix, _mixQuantized, reason: '$src mix (must be f32-quantized 0.3)');
  expect(ik.bendPositive, isFalse, reason: '$src bendPositive');
}

void main() {
  group('IK constraint load parity (JSON + .bnb)', () {
    late SkeletonData fromJson;
    late SkeletonData fromBnb;

    setUpAll(() {
      fromJson = loadBonyJson(_ikJson);
      // base64.decode returns a Uint8List, which loadBonyBnb accepts directly.
      fromBnb = loadBonyBnb(base64.decode(_ikBnbBase64));
    });

    test('JSON loader parses one IK constraint', () {
      expect(fromJson.ikConstraints, hasLength(1));
      _expectPrimaryIk(fromJson.ikConstraints.single, 'json');
    });

    test('.bnb loader decodes one IK constraint', () {
      expect(fromBnb.ikConstraints, hasLength(1));
      _expectPrimaryIk(fromBnb.ikConstraints.single, 'bnb');
    });

    test('JSON and .bnb IK constraints agree (cross-loader parity)', () {
      final j = fromJson.ikConstraints.single;
      final b = fromBnb.ikConstraints.single;
      expect(b.name, j.name);
      expect(b.bones, j.bones);
      expect(b.target, j.target);
      expect(b.order, j.order);
      expect(b.mix, j.mix);
      expect(b.bendPositive, j.bendPositive);
    });

    test('runtimeEvaluable is true when mix > 0 and bones present', () {
      expect(fromJson.ikConstraints.single.runtimeEvaluable, isTrue);
    });
  });

  group('IK omit-default parity (mix/order/bendPositive absent)', () {
    const omitJson = '''
{
  "skeleton": {"name": "ikmin"},
  "bones": [
    {"name": "root"},
    {"name": "b0", "parent": "root"},
    {"name": "goal", "parent": "root"}
  ],
  "ikConstraints": [
    {"name": "ik", "bones": ["b0"], "target": "goal"}
  ]
}
''';
    late IkConstraintData fromJson;
    late IkConstraintData fromBnb;

    setUpAll(() {
      fromJson = loadBonyJson(omitJson).ikConstraints.single;
      fromBnb = loadBonyBnb(base64.decode(_ikOmitBnbBase64)).ikConstraints.single;
    });

    test('JSON: absent optionals load as null/default', () {
      expect(fromJson.order, 0);
      expect(fromJson.mix, isNull);
      expect(fromJson.bendPositive, isNull);
    });

    test('.bnb: absent optionals decode as null/default', () {
      expect(fromBnb.order, 0);
      expect(fromBnb.mix, isNull);
      expect(fromBnb.bendPositive, isNull);
      expect(fromBnb.bones, ['b0']);
      expect(fromBnb.target, 'goal');
    });

    test('runtimeEvaluable treats absent mix as the 1.0 default', () {
      expect(fromJson.runtimeEvaluable, isTrue);
      expect(fromBnb.runtimeEvaluable, isTrue);
    });
  });

  // Load-parity is not just decoding well-formed data: Dart must reject exactly
  // what runtime-nim rejects (model.nim IK validation). Each fixture below is a
  // skeleton Nim refuses to load; the Dart loader must throw too.
  group('IK validation parity (rejects what Nim rejects)', () {
    String skel(String ik) => '''
{
  "skeleton": {"name": "s"},
  "bones": [
    {"name": "root"},
    {"name": "b0", "parent": "root"},
    {"name": "b1", "parent": "b0"},
    {"name": "goal", "parent": "root"}
  ],
  "ikConstraints": [$ik]
}
''';

    test('unknown target is rejected', () {
      expect(
          () => loadBonyJson(
              skel('{"name": "ik", "bones": ["b0"], "target": "nope"}')),
          throwsA(isA<FormatException>()));
    });

    test('unknown bone is rejected', () {
      expect(
          () => loadBonyJson(
              skel('{"name": "ik", "bones": ["nope"], "target": "goal"}')),
          throwsA(isA<FormatException>()));
    });

    test('empty bones list is rejected', () {
      expect(
          () => loadBonyJson(
              skel('{"name": "ik", "bones": [], "target": "goal"}')),
          throwsA(isA<FormatException>()));
    });

    test('non-contiguous bone chain is rejected', () {
      // b0 and goal are both children of root, not a parent->child chain.
      expect(
          () => loadBonyJson(skel(
              '{"name": "ik", "bones": ["b0", "goal"], "target": "goal"}')),
          throwsA(isA<FormatException>()));
    });

    test('duplicate constraint name is rejected', () {
      expect(
          () => loadBonyJson(skel(
              '{"name": "ik", "bones": ["b0"], "target": "goal"}, '
              '{"name": "ik", "bones": ["b1"], "target": "goal"}')),
          throwsA(isA<FormatException>()));
    });

    test('mix outside [0, 1] is rejected', () {
      expect(
          () => loadBonyJson(skel(
              '{"name": "ik", "bones": ["b0"], "target": "goal", "mix": 2.0}')),
          throwsA(isA<FormatException>()));
    });

    test('contiguous chain b0->b1 is accepted', () {
      final data = loadBonyJson(
          skel('{"name": "ik", "bones": ["b0", "b1"], "target": "goal"}'));
      expect(data.ikConstraints.single.bones, ['b0', 'b1']);
    });
  });
}
