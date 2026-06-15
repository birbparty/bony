// Dart M5 numeric gate: constrained pose (8-bone rig with path constraints)
// vs committed M5 golden.
//
// The M5 rig has 8 bones and 3 path constraints. computeWorldTransforms()
// returns the unconstrained setup-pose hierarchy; path constraint application
// is deferred to the animated runtime (M5 Nim feature, not yet in Dart M5
// static gate). The golden at t=0 reflects the same unconstrained pose.
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

void main() {
  late SkeletonData data;
  late List<Affine2> worlds;
  late List<DrawBatch> batches;
  late Map<String, dynamic> golden;

  setUpAll(() {
    data = loadBonyJson(
      File('../conformance/assets/m5_rig.bony').readAsStringSync(),
    );
    worlds = computeWorldTransforms(data);
    batches = buildDrawBatches(data);
    golden = jsonDecode(
      File('../conformance/goldens/m5_rig_t0.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('M5 golden format metadata', () {
    test('format is bony.numeric-golden.v1', () {
      expect(golden['format'], 'bony.numeric-golden.v1');
    });
    test('skeleton name matches', () {
      expect(golden['skeleton'], data.header.name);
    });
  });

  group('M5 rig structure', () {
    test('loads 8 bones', () {
      expect(data.bones, hasLength(8));
    });
    test('loads 3 path constraints', () {
      expect(data.paths, hasLength(3));
    });
    test('loads 1 path attachment', () {
      expect(data.pathAttachments, hasLength(1));
    });
    test('path constraints reference valid bones and paths', () {
      final boneNames = data.bones.map((b) => b.name).toSet();
      final pathNames = data.pathAttachments.map((p) => p.name).toSet();
      for (final pc in data.paths) {
        expect(boneNames, contains(pc.bone),
            reason: 'path ${pc.name}: unknown bone ${pc.bone}');
        expect(boneNames, contains(pc.target),
            reason: 'path ${pc.name}: unknown target ${pc.target}');
        expect(pathNames, contains(pc.path),
            reason: 'path ${pc.name}: unknown path attachment ${pc.path}');
      }
    });
    test('has no animations', () {
      expect(data.animations, isEmpty);
    });
  });

  group('M5 world transforms (abs <= 1e-4)', () {
    test('all 8 bones are computed', () {
      expect(worlds, hasLength(data.bones.length));
    });

    test('all bone world matrices match golden', () {
      final goldenBones = (golden['bones'] as List<dynamic>)
          .cast<Map<String, dynamic>>();
      final goldenByName = {for (final b in goldenBones) b['name'] as String: b};

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
  });

  group('M5 draw batches (6-slot rig)', () {
    test('batch count matches golden drawBatches count', () {
      final goldenBatches = golden['drawBatches'] as List<dynamic>;
      expect(batches, hasLength(goldenBatches.length));
    });

    test('draw batch slot/bone/attachment/blendMode match golden', () {
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

    test('draw order matches slot declaration order in rig', () {
      for (var i = 0; i < batches.length; i++) {
        expect(batches[i].slot, data.slots[i].name, reason: 'batch[$i] slot order');
      }
    });
  });
}
