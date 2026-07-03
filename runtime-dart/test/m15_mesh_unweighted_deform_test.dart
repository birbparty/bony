// Dart M15 numeric gate: an UNWEIGHTED mesh under a deformer.
//
// Companion to m13/m14 (weighted mesh + deformer). This covers the unweighted
// mesh path (vertices carry raw x/y and are FK-skinned through the slot bone,
// not blended across influences) composed with a rotation deformer. The slot
// bone is boneA (world +10 in x), so the unweighted vertices are FK-translated
// before the deformer runs — exercising skinning AND deform on the unweighted
// branch.
//
// Skinned (pre-deform) world positions: v0=(10,0) v1=(14,0) v2=(10,4)
// v3=(6,0) v4=(10,-4). The rotation pivots at (10,0) / 45 deg, so v0 (at the
// pivot) stays and the rest rotate.
//
// Compares Dart buildDrawBatches against the Nim-CLI golden within 1e-4.
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
      File('../conformance/assets/m15_mesh_unweighted_deform_rig.bony')
          .readAsStringSync(),
    );
    batches = buildDrawBatches(data);
    golden = jsonDecode(
      File('../conformance/goldens/m15_mesh_unweighted_deform_rig_t0.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  test('mesh is unweighted and one rotation deformer is present', () {
    expect(data.meshAttachments, hasLength(1));
    expect(data.meshAttachments.single.weighted, isFalse);
    expect(data.deformers, hasLength(1));
    expect(data.deformers.single.deformer.kind, DeformerKind.rotation);
  });

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

  test('unweighted FK + rotation is non-vacuous', () {
    final verts = batches.single.vertices;
    // v0 FK-skins to the rotation pivot (10,0) and must stay put.
    _expectClose(verts[0].x, 10.0, 'v0.x (at pivot)');
    _expectClose(verts[0].y, 0.0, 'v0.y (at pivot)');
    // v1 FK-skins to (14,0) then rotates 45 deg about (10,0) -> (12.828,2.828).
    _expectClose(verts[1].x, 12.8284271, 'v1.x (rotated)');
    _expectClose(verts[1].y, 2.8284271, 'v1.y (rotated)');
  });
}
