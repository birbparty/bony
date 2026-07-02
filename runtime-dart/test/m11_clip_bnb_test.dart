import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

/// Exercises the Dart `.bnb` clipping-attachment decode path (the JSON path is
/// covered by the M11-Clip group in m10_conformance_test.dart). The binary
/// loader must decode the clipping record and clip draw batches identically to
/// the `.bony` loader.
void main() {
  group('M11 clip rig .bnb parity', () {
    late SkeletonData fromJson;
    late SkeletonData fromBnb;

    setUpAll(() {
      fromJson = loadBonyJson(
          File('../conformance/assets/m11_clip_rig.bony').readAsStringSync());
      fromBnb = loadBonyBnb(
          File('../conformance/assets/bnb/m11_clip_rig.bnb').readAsBytesSync());
    });

    test('clipping attachment loads identically from .bony and .bnb', () {
      expect(fromJson.clippingAttachments, hasLength(1));
      expect(fromBnb.clippingAttachments, hasLength(1));
      final a = fromJson.clippingAttachments.single;
      final b = fromBnb.clippingAttachments.single;
      expect(b.name, a.name);
      expect(b.untilSlot, a.untilSlot);
      expect(b.vertices, a.vertices);
    });

    test('draw batches clip identically from .bony and .bnb', () {
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

    test('covered batch is clipped and out-of-range batch is not', () {
      final batches = buildDrawBatches(fromBnb);
      final panel = batches.firstWhere((b) => b.slot == 'panel_slot');
      final outside = batches.firstWhere((b) => b.slot == 'outside_slot');
      expect(panel.clipId, 'clip_mask');
      expect(panel.vertices, hasLength(5)); // clipped pentagon
      expect(outside.clipId, '');
      expect(outside.vertices, hasLength(4)); // unclipped quad
    });
  });
}
