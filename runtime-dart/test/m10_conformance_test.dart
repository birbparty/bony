// Dart M10 conformance gate: numeric golden comparisons for M1, M8, and M5-IK.
//
// M1 (m1_rig.bony → m1_rig_t0.json): world transforms + draw batches.
//   The M1 loader test covers parsing; this file covers numeric golden parity.
//
// M8 (m8_rig.bony → m8_rig_t0.json): world transforms + draw batches at t=0.
//   The M8 state machine test covers runtime behaviour; this covers the
//   setup-pose golden (no state machine evaluation required at t=0).
//
// M5-IK (m5_ik_rig.bony → m5_ik_rig_t0.json): world transforms with IK
//   constraints evaluated at pose time (1-bone, 2-bone bendPositive:false, and
//   3-bone FABRIK mix:0.5). Non-vacuous: solved IK differs from the
//   unconstrained pose by a world delta of ~36, so matching the golden proves
//   real solving, not a no-op.
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:convert';
import 'dart:io';
import 'package:test/test.dart';
import 'package:bony/bony.dart';

const double _tol = 1e-4;

void _expectClose(double actual, double expected, String label) {
  expect(
    (actual - expected).abs(),
    lessThanOrEqualTo(_tol),
    reason: '$label: actual=$actual expected=$expected diff=${(actual - expected).abs()}',
  );
}

void _expectAffine(Affine2 actual, Map<String, dynamic> golden, String label) {
  _expectClose(actual.a,  (golden['a']  as num).toDouble(), '$label.a');
  _expectClose(actual.b,  (golden['b']  as num).toDouble(), '$label.b');
  _expectClose(actual.c,  (golden['c']  as num).toDouble(), '$label.c');
  _expectClose(actual.d,  (golden['d']  as num).toDouble(), '$label.d');
  _expectClose(actual.tx, (golden['tx'] as num).toDouble(), '$label.tx');
  _expectClose(actual.ty, (golden['ty'] as num).toDouble(), '$label.ty');
}

void _checkGolden(
  String rigName,
  String assetPath,
  String goldenPath,
) {
  group('$rigName golden (abs <= 1e-4)', () {
    late SkeletonData data;
    late List<Affine2> worlds;
    late List<DrawBatch> batches;
    late Map<String, dynamic> golden;

    setUpAll(() {
      data = loadBonyJson(File(assetPath).readAsStringSync());
      worlds = computeWorldTransforms(data);
      batches = buildDrawBatches(data);
      golden = jsonDecode(File(goldenPath).readAsStringSync())
          as Map<String, dynamic>;
    });

    test('format is bony.numeric-golden.v1', () {
      expect(golden['format'], 'bony.numeric-golden.v1');
    });

    test('skeleton name matches', () {
      expect(golden['skeleton'], data.header.name);
    });

    test('golden is the t=0 setup pose', () {
      expect((golden['time'] as num).toDouble(), 0.0);
    });

    test('bone count matches golden', () {
      expect(worlds, hasLength((golden['bones'] as List<dynamic>).length));
    });

    test('bone world matrices match golden', () {
      final goldenBones =
          (golden['bones'] as List<dynamic>).cast<Map<String, dynamic>>();
      final goldenByName = {
        for (final b in goldenBones) b['name'] as String: b
      };
      for (var i = 0; i < data.bones.length; i++) {
        final bone = data.bones[i];
        final gb = goldenByName[bone.name];
        expect(gb, isNotNull, reason: 'golden missing bone: ${bone.name}');
        _expectAffine(
          worlds[i],
          gb!['world'] as Map<String, dynamic>,
          'bones[${bone.name}].world',
        );
      }
    });

    test('draw batch count matches golden', () {
      expect(batches,
          hasLength((golden['drawBatches'] as List<dynamic>).length));
    });

    test('draw batch order matches golden', () {
      final goldenSlots = (golden['drawBatches'] as List<dynamic>)
          .cast<Map<String, dynamic>>()
          .map((gb) => gb['slot'] as String)
          .toList();
      expect(batches.map((b) => b.slot).toList(), goldenSlots,
          reason: 'draw order differs from golden');
    });

    test('draw batch metadata matches golden', () {
      final goldenBatches = (golden['drawBatches'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (var i = 0; i < goldenBatches.length; i++) {
        final gb = goldenBatches[i];
        final b = batches[i];
        expect(b.slot, gb['slot'], reason: 'batches[$i].slot');
        expect(b.bone, gb['bone'], reason: 'batches[$i].bone');
        expect(b.attachment, gb['attachment'], reason: 'batches[$i].attachment');
        expect(b.blendMode, gb['blendMode'], reason: 'batches[$i].blendMode');
        expect(b.texturePage, gb['texturePage'], reason: 'batches[$i].texturePage');
        expect(b.clipId, gb['clipId'], reason: 'batches[$i].clipId');
      }
    });

    test('draw batch world matrices match golden', () {
      final goldenBatches = (golden['drawBatches'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (var i = 0; i < goldenBatches.length; i++) {
        _expectAffine(
          batches[i].world,
          goldenBatches[i]['world'] as Map<String, dynamic>,
          'drawBatches[$i].world',
        );
      }
    });

    test('draw batch vertices match golden (abs <= 1e-4)', () {
      final goldenBatches = (golden['drawBatches'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (var i = 0; i < goldenBatches.length; i++) {
        final gverts = (goldenBatches[i]['vertices'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(batches[i].vertices, hasLength(gverts.length),
            reason: 'batches[$i].vertices count');
        for (var j = 0; j < gverts.length; j++) {
          final gv = gverts[j];
          final v = batches[i].vertices[j];
          final pfx = 'drawBatches[$i].vertices[$j]';
          _expectClose(v.x, (gv['x'] as num).toDouble(), '$pfx.x');
          _expectClose(v.y, (gv['y'] as num).toDouble(), '$pfx.y');
          _expectClose(v.u, (gv['u'] as num).toDouble(), '$pfx.u');
          _expectClose(v.v, (gv['v'] as num).toDouble(), '$pfx.v');
          _expectClose(v.r, (gv['r'] as num).toDouble(), '$pfx.r');
          _expectClose(v.g, (gv['g'] as num).toDouble(), '$pfx.g');
          _expectClose(v.b, (gv['b'] as num).toDouble(), '$pfx.b');
          _expectClose(v.a, (gv['a'] as num).toDouble(), '$pfx.a');
        }
      }
    });

    test('draw batch indices match golden exactly', () {
      final goldenBatches = (golden['drawBatches'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      for (var i = 0; i < goldenBatches.length; i++) {
        final gidx = (goldenBatches[i]['indices'] as List<dynamic>)
            .map((e) => (e as num).toInt())
            .toList();
        expect(batches[i].indices, gidx, reason: 'drawBatches[$i].indices');
      }
    });
  });
}

void main() {
  _checkGolden(
    'M1',
    '../conformance/assets/m1_rig.bony',
    '../conformance/goldens/m1_rig_t0.json',
  );

  _checkGolden(
    'M8',
    '../conformance/assets/m8_rig.bony',
    '../conformance/goldens/m8_rig_t0.json',
  );

  _checkGolden(
    'M5-IK',
    '../conformance/assets/m5_ik_rig.bony',
    '../conformance/goldens/m5_ik_rig_t0.json',
  );

  _checkGolden(
    'M5-Transform',
    '../conformance/assets/m5_transform_rig.bony',
    '../conformance/goldens/m5_transform_rig_t0.json',
  );
}
