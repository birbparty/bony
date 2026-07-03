import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

/// Exercises the Dart `.bnb` mesh + clipping combined decode + per-triangle clip
/// path (the JSON path is covered by the M17-MeshClip group in
/// m10_conformance_test.dart). A mesh whose slot falls inside a clip's covered
/// range must clip per-triangle identically from the `.bony` and `.bnb` load
/// paths, and reproduce the committed cut geometry.
void main() {
  group('M17 mesh-clip rig .bnb parity', () {
    late SkeletonData fromJson;
    late SkeletonData fromBnb;

    setUpAll(() {
      fromJson = loadBonyJson(
          File('../conformance/assets/m17_mesh_clip_rig.bony').readAsStringSync());
      fromBnb = loadBonyBnb(
          File('../conformance/assets/bnb/m17_mesh_clip_rig.bnb').readAsBytesSync());
    });

    test('mesh + clip records load identically from .bony and .bnb', () {
      expect(fromBnb.meshAttachments.map((m) => m.name),
          fromJson.meshAttachments.map((m) => m.name));
      expect(fromBnb.clippingAttachments.map((c) => c.name),
          fromJson.clippingAttachments.map((c) => c.name));
    });

    test('mesh batch clips per-triangle identically from .bony and .bnb', () {
      final ja = buildDrawBatches(fromJson);
      final jb = buildDrawBatches(fromBnb);
      expect(jb.length, ja.length);
      for (var i = 0; i < ja.length; i++) {
        expect(jb[i].clipId, ja[i].clipId, reason: 'batch $i clipId');
        expect(jb[i].indices, ja[i].indices, reason: 'batch $i indices');
        expect(jb[i].vertices.length, ja[i].vertices.length,
            reason: 'batch $i vertex count');
        for (var v = 0; v < ja[i].vertices.length; v++) {
          expect(jb[i].vertices[v].x, closeTo(ja[i].vertices[v].x, 1e-4));
          expect(jb[i].vertices[v].y, closeTo(ja[i].vertices[v].y, 1e-4));
          expect(jb[i].vertices[v].u, closeTo(ja[i].vertices[v].u, 1e-4));
          expect(jb[i].vertices[v].v, closeTo(ja[i].vertices[v].v, 1e-4));
        }
      }
    });

    test('.bnb mesh batch reproduces the committed per-triangle cut', () {
      final batches = buildDrawBatches(fromBnb);
      final mesh = batches.firstWhere((b) => b.slot == 'mesh_slot');
      // Now clipped in v2 (was unclipped in v1): clipId set, cut at x = 20.
      expect(mesh.clipId, 'clip_mask');
      // 4 triangles -> 2 pass-through (3 verts each) + 2 clipped (4 verts each) =
      // 14 vertices, 18 indices.
      expect(mesh.vertices, hasLength(14));
      expect(mesh.indices, hasLength(18));
      // No vertex sits right of the x = 20 cut, and the right rim vertex (50,0)
      // that a convex-ring clip would keep is gone.
      final maxX =
          mesh.vertices.map((v) => v.x).reduce((a, b) => a > b ? a : b);
      expect(maxX, lessThanOrEqualTo(20.0 + 1e-4));
      expect(mesh.vertices.any((v) => (v.x - 50.0).abs() < 1e-4), isFalse);
      // A cut vertex lands at (20,0) with u interpolated 0.4 along v0->v1 -> 0.7.
      final cut = mesh.vertices
          .where((v) => (v.x - 20.0).abs() < 1e-4 && v.y.abs() < 1e-4);
      expect(cut, isNotEmpty);
      expect(cut.first.u, closeTo(0.7, 1e-4));
    });
  });
}
