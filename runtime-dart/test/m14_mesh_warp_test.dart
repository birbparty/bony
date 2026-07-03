// Dart M14 numeric gate: warp deformer self-scoping on a mesh attachment.
//
// Companion to m13 (rotation on a mesh). This pins the warp half of the
// mesh-x-deformer contract (bony-5pwj): a warp deformer applies to a mesh
// batch, and self-scopes via its setup bounds — a mesh vertex whose skinned
// (setup) position falls outside the lattice box is left UNCHANGED, while an
// in-bounds vertex is warped.
//
// The rig uses a pure-translation warp (all four 2x2 control points shifted by
// (+3,+2) off the lattice corners), so every in-bounds vertex moves by exactly
// (+3,+2) and every out-of-bounds vertex is identical to its skinned position.
// Skinned positions: v0=(5,5) v1=(14,0) v2=(10,4) v3=(4,10) v4=(0,14). The warp
// box is x in [8,15], y in [-1,5], which contains only v1 and v2.
//
// Loads m14_mesh_warp_rig.bony, builds draw batches, and compares against the
// Nim-CLI-generated golden within tolerance (abs <= 1e-4). A match proves Nim
// and Dart agree on warp-on-mesh output.
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
      File('../conformance/assets/m14_mesh_warp_rig.bony').readAsStringSync(),
    );
    batches = buildDrawBatches(data);
    golden = jsonDecode(
      File('../conformance/goldens/m14_mesh_warp_rig_t0.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  group('M14 rig loads a mesh and a warp deformer together', () {
    test('one mesh attachment present', () {
      expect(data.meshAttachments, hasLength(1));
      expect(data.meshAttachments.single.weighted, isTrue);
    });

    test('one warp deformer present', () {
      expect(data.deformers, hasLength(1));
      final rec = data.deformers.single;
      expect(rec.deformer.id, 'mesh_warp');
      expect(rec.deformer.kind, DeformerKind.warp);
    });
  });

  group('M14 draw batches vs golden (abs <= 1e-4)', () {
    test('single mesh batch with a non-quad vertex count', () {
      expect(batches, hasLength(1));
      expect(batches.single.vertices, hasLength(5));
      expect(batches.single.slot, 'mesh_slot');
    });

    test('all batch vertices match golden', () {
      final goldenBatches =
          (golden['drawBatches'] as List<dynamic>).cast<Map<String, dynamic>>();
      expect(batches, hasLength(goldenBatches.length));

      for (var bi = 0; bi < goldenBatches.length; bi++) {
        final gb = goldenBatches[bi];
        final batch = batches[bi];
        final slotName = gb['slot'] as String;
        expect(batch.slot, slotName, reason: 'batch[$bi] slot mismatch');

        final goldenVerts =
            (gb['vertices'] as List<dynamic>).cast<Map<String, dynamic>>();
        expect(batch.vertices, hasLength(goldenVerts.length),
            reason: '$slotName vertex count mismatch');

        final goldenIndices =
            (gb['indices'] as List<dynamic>).map((e) => e as int).toList();
        expect(batch.indices, goldenIndices,
            reason: '$slotName indices mismatch');

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

    test('warp self-scopes: in-bounds verts translate, out-of-bounds unchanged', () {
      final verts = batches.single.vertices;
      // v0 (5,5): outside the box (x<8) -> unchanged.
      _expectClose(verts[0].x, 5.0, 'v0.x (out of bounds)');
      _expectClose(verts[0].y, 5.0, 'v0.y (out of bounds)');
      // v1 (14,0): inside -> +3,+2.
      _expectClose(verts[1].x, 17.0, 'v1.x (in bounds, +3)');
      _expectClose(verts[1].y, 2.0, 'v1.y (in bounds, +2)');
      // v2 (10,4): inside -> +3,+2.
      _expectClose(verts[2].x, 13.0, 'v2.x (in bounds, +3)');
      _expectClose(verts[2].y, 6.0, 'v2.y (in bounds, +2)');
      // v3 (4,10): outside -> unchanged.
      _expectClose(verts[3].x, 4.0, 'v3.x (out of bounds)');
      _expectClose(verts[3].y, 10.0, 'v3.y (out of bounds)');
      // v4 (0,14): outside -> unchanged.
      _expectClose(verts[4].x, 0.0, 'v4.x (out of bounds)');
      _expectClose(verts[4].y, 14.0, 'v4.y (out of bounds)');
    });
  });
}
