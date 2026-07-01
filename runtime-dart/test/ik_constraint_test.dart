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
    {"name": "ik", "bones": ["b0", "b1"], "target": "goal", "order": 1, "mix": 0.5, "bendPositive": false}
  ]
}
''';

// Nim CLI (json-to-bnb) output for _ikJson. In-test fixture, not a conformance asset.
const _ikBnbBase64 =
    'Qk9OWQECCgEFAgUDBegHA+kHA6AfBaIfAq4fB68fA7AfBAcGaWtkYXJ0BTAuMi4wBHJvb3QCYjAC'
    'YjEEZ29hbAJpawEBAQACAQEAAgEBAgACAQEDAwEC6AcEAAAgQQACAQEEAwED6AcEAAAgQQACAQEF'
    'AwEC6AcEAACgQekHBAAAoEAAoh8BAQagHwEFoh8BAq4fAwIDBK8fBAAAAD+wHwEAAAA=';

void _expectPrimaryIk(IkConstraintData ik, String src) {
  expect(ik.name, 'ik', reason: '$src name');
  expect(ik.bones, ['b0', 'b1'], reason: '$src bones');
  expect(ik.target, 'goal', reason: '$src target');
  expect(ik.order, 1, reason: '$src order');
  expect(ik.mix, closeTo(0.5, 1e-6), reason: '$src mix');
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
    late IkConstraintData ik;

    setUpAll(() {
      final data = loadBonyJson('''
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
''');
      ik = data.ikConstraints.single;
    });

    test('absent optionals load as null/default', () {
      expect(ik.order, 0);
      expect(ik.mix, isNull);
      expect(ik.bendPositive, isNull);
    });

    test('runtimeEvaluable treats absent mix as the 1.0 default', () {
      expect(ik.runtimeEvaluable, isTrue);
    });
  });
}
