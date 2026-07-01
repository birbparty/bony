// Dart IK constraint load parity + solved-output (bony-me5.9, bony-7b7.7).
//
// IK EVALUATION IS LIVE in Dart: computeWorldTransforms now solves IK
// constraints at pose time (ports runtime-nim's applyRuntimeIk; see
// transform.dart:_applyRuntimeIk and the M5-IK golden gate in
// m10_conformance_test.dart). This file covers two things: (1) load parity —
// the model + JSON loader + .bnb loader carry IK constraint data through
// without error and in agreement, matching runtime-nim's on-load parity; and
// (2) solved output — the terminal bones of the 1-bone, 2-bone, and chain
// shapes are actually driven by the solver (matched against the committed
// golden and shown to be non-vacuous versus the unconstrained rest pose).
//
// The .bnb bytes below are produced by the Nim CLI (`bony json-to-bnb`) — the
// format authority — from the same skeleton as _ikJson. They are an in-test
// fixture, NOT a committed conformance asset. Regenerate with:
//   bony json-to-bnb <_ikJson>.bony out.bnb && base64 out.bnb

import 'dart:convert';
import 'dart:io';
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

  // Solved output: computeWorldTransforms now evaluates IK. These assert that
  // the terminal bones are actually driven by the solver — matched to the
  // committed golden and shown to differ non-vacuously from the unconstrained
  // rest pose (a no-op evaluation would leave them at their rest transforms).
  group('IK solved output (evaluation is live)', () {
    Map<String, int> _index(SkeletonData data) => {
          for (var i = 0; i < data.bones.length; i++) data.bones[i].name: i,
        };

    // Sum of |translation delta| + |rotation delta| between two world affines.
    double _worldDelta(Affine2 a, Affine2 b) =>
        (a.tx - b.tx).abs() +
        (a.ty - b.ty).abs() +
        (worldRotationDegrees(a) - worldRotationDegrees(b)).abs();

    test('the loaded 2-bone IK drives its terminal bone off the rest pose', () {
      // _ikJson: b0->b1 chain (both rest rotation 0, lying along +x) with a
      // goal above the x-axis and mix 0.3. Solving must rotate/translate the
      // terminal bone b1 away from its unconstrained rest transform.
      final data = loadBonyJson(_ikJson);
      final worlds = computeWorldTransforms(data);
      final index = _index(data);
      final b1Index = index['b1']!;
      final solved = worlds[b1Index];
      final rest = restWorldFor(data, b1Index, index, <int, Affine2>{});
      // Sanity: the rest pose is genuinely unrotated at (20, 0).
      expect(worldRotationDegrees(rest), closeTo(0.0, 1e-9));
      expect(rest.tx, closeTo(20.0, 1e-6));
      expect(rest.ty, closeTo(0.0, 1e-6));
      // Solved differs: IK actually ran (mix 0.3 => partial reach).
      expect(_worldDelta(solved, rest), greaterThan(1.0),
          reason: 'IK evaluation must move the terminal bone off rest');
    });

    group('m5_ik_rig terminals (1-bone, 2-bone, chain)', () {
      late SkeletonData data;
      late List<Affine2> worlds;
      late Map<String, int> index;
      late Map<String, Map<String, dynamic>> goldenWorld;

      setUpAll(() {
        data = loadBonyJson(
          File('../conformance/assets/m5_ik_rig.bony').readAsStringSync(),
        );
        worlds = computeWorldTransforms(data);
        index = _index(data);
        final golden = jsonDecode(
          File('../conformance/goldens/m5_ik_rig_t0.json').readAsStringSync(),
        ) as Map<String, dynamic>;
        goldenWorld = {
          for (final b in (golden['bones'] as List).cast<Map<String, dynamic>>())
            b['name'] as String: b['world'] as Map<String, dynamic>,
        };
      });

      // one_bone (1-bone), two_lower (2-bone tip), chain_c (chain tip).
      for (final terminal in const ['one_bone', 'two_lower', 'chain_c']) {
        test('$terminal solved world matches the golden (abs <= 1e-4)', () {
          final w = worlds[index[terminal]!];
          final g = goldenWorld[terminal]!;
          for (final e in <List<Object>>[
            ['a', w.a], ['b', w.b], ['c', w.c],
            ['d', w.d], ['tx', w.tx], ['ty', w.ty],
          ]) {
            final key = e[0] as String;
            final actual = e[1] as double;
            expect((actual - (g[key] as num).toDouble()).abs(),
                lessThanOrEqualTo(1e-4),
                reason: '$terminal.$key');
          }
        });

        test('$terminal is non-vacuously solved (differs from rest pose)', () {
          final solved = worlds[index[terminal]!];
          final rest =
              restWorldFor(data, index[terminal]!, index, <int, Affine2>{});
          expect(_worldDelta(solved, rest), greaterThan(5.0),
              reason: '$terminal must differ from the unconstrained pose');
        });
      }
    });
  });
}
