// Dart M7 numeric gate: deformers + parameter axes + keyform blend vs golden.
//
// Loads m7_rig.bony, builds draw batches (which applies deformers at default
// parameter values), and compares vertex positions against the committed golden
// (conformance/goldens/m7_rig_t0.json) within tolerance (abs <= 1e-4).
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

void main() {
  late SkeletonData data;
  late List<DrawBatch> batches;
  late Map<String, dynamic> golden;

  setUpAll(() {
    data = loadBonyJson(
      File('../conformance/assets/m7_rig.bony').readAsStringSync(),
    );
    batches = buildDrawBatches(data);
    golden = jsonDecode(
      File('../conformance/goldens/m7_rig_t0.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('M7 golden format metadata', () {
    test('format is bony.numeric-golden.v1', () {
      expect(golden['format'], 'bony.numeric-golden.v1');
    });
    test('skeleton name matches', () {
      expect(golden['skeleton'], data.header.name);
    });
  });

  group('M7 parameter axes loaded', () {
    test('3 parameters present', () {
      expect(data.parameters, hasLength(3));
    });

    test('parameter names', () {
      final names = data.parameters.map((p) => p.name).toList();
      expect(names, containsAll(['AngleX', 'AngleY', 'EyeOpen']));
    });
  });

  group('M7 deformers loaded', () {
    test('3 deformer records present', () {
      expect(data.deformers, hasLength(3));
    });

    test('deformer ids', () {
      final ids = data.deformers.map((r) => r.deformer.id).toList();
      expect(ids, containsAll(['root_rot', 'head_warp', 'body_warp']));
    });

    test('root_rot is rotation kind', () {
      final rec = data.deformers.firstWhere((r) => r.deformer.id == 'root_rot');
      expect(rec.deformer.kind, DeformerKind.rotation);
    });

    test('head_warp is warp kind with keyformBlend', () {
      final rec = data.deformers.firstWhere((r) => r.deformer.id == 'head_warp');
      expect(rec.deformer.kind, DeformerKind.warp);
      expect(rec.keyformBlend.axes, isNotEmpty);
    });
  });

  group('M7 draw batches vs golden (abs <= 1e-4)', () {
    test('batch count matches golden', () {
      final goldenBatches = (golden['drawBatches'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      expect(batches, hasLength(goldenBatches.length));
    });

    test('all batch vertices match golden', () {
      final goldenBatches = (golden['drawBatches'] as List<dynamic>)
          .cast<Map<String, dynamic>>();

      for (var bi = 0; bi < goldenBatches.length; bi++) {
        final gb = goldenBatches[bi];
        final batch = batches[bi];
        final slotName = gb['slot'] as String;

        expect(batch.slot, slotName, reason: 'batch[$bi] slot mismatch');

        final goldenVerts = (gb['vertices'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        expect(batch.vertices, hasLength(goldenVerts.length),
            reason: '$slotName vertex count mismatch');

        for (var vi = 0; vi < goldenVerts.length; vi++) {
          final gv = goldenVerts[vi];
          final v = batch.vertices[vi];
          final prefix = '$slotName[v$vi]';
          _expectClose(v.x, (gv['x'] as num).toDouble(), '$prefix.x');
          _expectClose(v.y, (gv['y'] as num).toDouble(), '$prefix.y');
          _expectClose(v.u, (gv['u'] as num).toDouble(), '$prefix.u');
          _expectClose(v.v, (gv['v'] as num).toDouble(), '$prefix.v');
        }
      }
    });
  });
}
