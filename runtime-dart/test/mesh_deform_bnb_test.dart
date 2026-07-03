// Dart .bnb parity for the mesh-x-deformer rigs (m13/m14/m15/m16).
//
// The Nim conformance runner already checks each deform rig's .bnb decodes to
// the committed golden. This is the Dart-side twin (mirroring
// m12_mesh_bnb_test.dart): for every deform rig, loading from .bnb must produce
// draw batches identical to loading from .bony — i.e. the binary loader decodes
// meshes AND deformers such that buildDrawBatches (skinning + deformer re-map)
// yields the same deformed vertices. This guards the seam where a mesh record
// and a deformer record are both packed in one .bnb stream.
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:io';
import 'package:bony/bony.dart';
import 'package:test/test.dart';

class _Rig {
  const _Rig(this.stem, this.deformerCount);
  final String stem;
  final int deformerCount;
}

const _rigs = <_Rig>[
  _Rig('m13_mesh_deform_rig', 1),
  _Rig('m14_mesh_warp_rig', 1),
  _Rig('m15_mesh_unweighted_deform_rig', 1),
  _Rig('m16_mesh_multi_deform_rig', 2),
];

void main() {
  for (final rig in _rigs) {
    group('${rig.stem} .bnb parity', () {
      late SkeletonData fromJson;
      late SkeletonData fromBnb;

      setUpAll(() {
        fromJson = loadBonyJson(
            File('../conformance/assets/${rig.stem}.bony').readAsStringSync());
        fromBnb = loadBonyBnb(
            File('../conformance/assets/bnb/${rig.stem}.bnb').readAsBytesSync());
      });

      test('deformers load identically from .bony and .bnb', () {
        expect(fromJson.deformers, hasLength(rig.deformerCount));
        expect(fromBnb.deformers, hasLength(rig.deformerCount));
        for (var i = 0; i < fromJson.deformers.length; i++) {
          expect(fromBnb.deformers[i].deformer.id,
              fromJson.deformers[i].deformer.id,
              reason: 'deformer[$i].id');
          expect(fromBnb.deformers[i].deformer.kind,
              fromJson.deformers[i].deformer.kind,
              reason: 'deformer[$i].kind');
          expect(fromBnb.deformers[i].deformer.parent,
              fromJson.deformers[i].deformer.parent,
              reason: 'deformer[$i].parent');
        }
      });

      test('deformed draw batches are identical from .bony and .bnb', () {
        final ja = buildDrawBatches(fromJson);
        final jb = buildDrawBatches(fromBnb);
        expect(jb.length, ja.length);
        for (var i = 0; i < ja.length; i++) {
          expect(jb[i].slot, ja[i].slot, reason: 'batch $i slot');
          expect(jb[i].attachment, ja[i].attachment,
              reason: 'batch $i attachment');
          expect(jb[i].indices, ja[i].indices, reason: 'batch $i indices');
          expect(jb[i].vertices.length, ja[i].vertices.length,
              reason: 'batch $i vertex count');
          for (var v = 0; v < ja[i].vertices.length; v++) {
            expect(jb[i].vertices[v].x, closeTo(ja[i].vertices[v].x, 1e-4),
                reason: 'batch $i vertex $v x');
            expect(jb[i].vertices[v].y, closeTo(ja[i].vertices[v].y, 1e-4),
                reason: 'batch $i vertex $v y');
            expect(jb[i].vertices[v].u, closeTo(ja[i].vertices[v].u, 1e-4),
                reason: 'batch $i vertex $v u');
            expect(jb[i].vertices[v].v, closeTo(ja[i].vertices[v].v, 1e-4),
                reason: 'batch $i vertex $v v');
          }
        }
      });
    });
  }
}
