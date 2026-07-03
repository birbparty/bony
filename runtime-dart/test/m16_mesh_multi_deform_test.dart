// Dart M16 numeric gate: MULTIPLE ordered deformers on one mesh.
//
// Companion to m13/m14/m15. This exercises deformer composition on a mesh: a
// rotation (order 0) followed by a warp (order 1) that is PARENTED to the
// rotation, so the warp's lattice is carried through the parent's effective
// frame (transformFrame) before it deforms the already-rotated vertices. The
// warp box covers the whole mesh so every vertex is warped; the ordering and
// parent chaining make each vertex differ from its skinned position.
//
// This is the mesh analogue of m7's region deformer stack (root_rot ->
// head_warp parent chain), proving Nim and Dart compose ordered/parented
// deformers identically on a mesh vertex set. Compares Dart buildDrawBatches
// against the Nim-CLI golden within 1e-4.
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
      File('../conformance/assets/m16_mesh_multi_deform_rig.bony')
          .readAsStringSync(),
    );
    batches = buildDrawBatches(data);
    golden = jsonDecode(
      File('../conformance/goldens/m16_mesh_multi_deform_rig_t0.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('two deformers load: rotation (order 0) + warp parented to it', () {
    expect(data.deformers, hasLength(2));
    final rot = data.deformers.firstWhere((r) => r.deformer.id == 'mesh_rot');
    final warp = data.deformers.firstWhere((r) => r.deformer.id == 'mesh_warp');
    expect(rot.deformer.kind, DeformerKind.rotation);
    expect(warp.deformer.kind, DeformerKind.warp);
    expect(warp.deformer.parent, 'mesh_rot');
  });

  test('single mesh batch with a non-quad vertex count', () {
    expect(batches, hasLength(1));
    expect(batches.single.vertices, hasLength(5));
    expect(batches.single.slot, 'mesh_slot');
  });

  test('all batch vertices match golden (composed deformers)', () {
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
      expect(batch.indices, goldenIndices, reason: '$slotName indices mismatch');

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

  test('composition is non-vacuous: every vertex moved from its skinned pose', () {
    // Skinned positions before any deformer.
    const skinned = [
      [5.0, 5.0],
      [14.0, 0.0],
      [10.0, 4.0],
      [4.0, 10.0],
      [0.0, 14.0],
    ];
    final verts = batches.single.vertices;
    for (var i = 0; i < skinned.length; i++) {
      final dx = (verts[i].x - skinned[i][0]).abs();
      final dy = (verts[i].y - skinned[i][1]).abs();
      expect(dx > 0.1 || dy > 0.1, isTrue,
          reason: 'v$i should have been deformed away from skinned '
              '(${skinned[i][0]},${skinned[i][1]}) but is (${verts[i].x},${verts[i].y})');
    }
  });
}
