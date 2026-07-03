import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

/// Exercises the Dart `.bnb` mesh-attachment decode + skinning path (the JSON
/// path is covered by the M12-Mesh group in m10_conformance_test.dart). The
/// packed weighted-vertex payload (varuint influence counts + string-table bone
/// indices) is new and error-prone, so the binary loader must decode the mesh
/// record and skin draw batches identically to the `.bony` loader and the
/// committed golden.
void main() {
  group('M12 mesh rig .bnb parity', () {
    late SkeletonData fromJson;
    late SkeletonData fromBnb;

    setUpAll(() {
      fromJson = loadBonyJson(
          File('../conformance/assets/m12_mesh_rig.bony').readAsStringSync());
      fromBnb = loadBonyBnb(
          File('../conformance/assets/bnb/m12_mesh_rig.bnb').readAsBytesSync());
    });

    test('mesh attachment loads identically from .bony and .bnb', () {
      expect(fromJson.meshAttachments, hasLength(1));
      expect(fromBnb.meshAttachments, hasLength(1));
      final a = fromJson.meshAttachments.single;
      final b = fromBnb.meshAttachments.single;
      expect(b.name, a.name);
      expect(b.weighted, a.weighted);
      expect(b.triangles, a.triangles);
      expect(b.uvs.length, a.uvs.length);
      for (var i = 0; i < a.uvs.length; i++) {
        expect(b.uvs[i].u, closeTo(a.uvs[i].u, 1e-6), reason: 'uv[$i].u');
        expect(b.uvs[i].v, closeTo(a.uvs[i].v, 1e-6), reason: 'uv[$i].v');
      }
      expect(b.vertices.length, a.vertices.length);
      for (var i = 0; i < a.vertices.length; i++) {
        final av = a.vertices[i];
        final bv = b.vertices[i];
        expect(bv.weighted, av.weighted, reason: 'vertex[$i].weighted');
        if (av.weighted) {
          expect(bv.influences.length, av.influences.length,
              reason: 'vertex[$i].influences.length');
          for (var k = 0; k < av.influences.length; k++) {
            final ai = av.influences[k];
            final bi = bv.influences[k];
            expect(bi.bone, ai.bone, reason: 'vertex[$i].influence[$k].bone');
            expect(bi.bindX, closeTo(ai.bindX, 1e-6));
            expect(bi.bindY, closeTo(ai.bindY, 1e-6));
            expect(bi.weight, closeTo(ai.weight, 1e-6));
          }
        } else {
          expect(bv.x, closeTo(av.x, 1e-6), reason: 'vertex[$i].x');
          expect(bv.y, closeTo(av.y, 1e-6), reason: 'vertex[$i].y');
        }
      }
    });

    test('draw batches skin identically from .bony and .bnb', () {
      final ja = buildDrawBatches(fromJson);
      final jb = buildDrawBatches(fromBnb);
      expect(jb.length, ja.length);
      for (var i = 0; i < ja.length; i++) {
        expect(jb[i].attachment, ja[i].attachment, reason: 'batch $i attachment');
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

    test('.bnb mesh batch reproduces the committed skinned positions', () {
      final batches = buildDrawBatches(fromBnb);
      final mesh = batches.firstWhere((b) => b.slot == 'mesh_slot');
      expect(mesh.clipId, '');
      expect(mesh.indices, [0, 1, 2, 0, 2, 3]);
      expect(mesh.vertices, hasLength(4));
      // v0 shared 50/50 -> (5,5) (between boneA-FK (10,0) and boneB-FK (0,10));
      // v3 asymmetric 0.25/0.75 -> (4.5,9.5), distinct from an equal-average (7,7).
      expect(mesh.vertices[0].x, closeTo(5.0, 1e-4));
      expect(mesh.vertices[0].y, closeTo(5.0, 1e-4));
      expect(mesh.vertices[1].x, closeTo(14.0, 1e-4));
      expect(mesh.vertices[1].y, closeTo(0.0, 1e-4));
      expect(mesh.vertices[2].x, closeTo(0.0, 1e-4));
      expect(mesh.vertices[2].y, closeTo(14.0, 1e-4));
      expect(mesh.vertices[3].x, closeTo(4.5, 1e-4));
      expect(mesh.vertices[3].y, closeTo(9.5, 1e-4));
    });
  });
}
