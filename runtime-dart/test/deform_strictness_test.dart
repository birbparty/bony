// Dart deform-runtime strictness parity with Nim (bony-9l8y).
//
// Nim's deform path fails loudly on structural violations; these tests pin the
// three Dart sites hardened to match:
//   1. buildDrawBatches raises (not silently skips) when a staged deform
//      override's length disagrees with the skinned vertex count.
//   2. sampleDeformDeltas raises a domain error (FormatException), NOT a raw
//      RangeError, for a directly-constructed timeline with an over-range offset.
//   3. sampleDeformDeltas runs the per-sample structural validate Nim runs.
// All are defensively-unreachable through the loader (which validates load-time),
// so they are exercised here with directly-constructed model objects.

import 'package:test/test.dart';
import 'package:bony/bony.dart';

// A minimal loaded skeleton: bone root, slot body showing the 3-vertex mesh
// `cloth`. Used to stage a mismatched deform override through buildDrawBatches.
const _meshFixture = '{"skeleton":{"name":"deformstrict"},'
    '"bones":[{"name":"root"}],'
    '"slots":[{"name":"body","bone":"root","attachment":"cloth"}],'
    '"meshAttachments":[{"name":"cloth","weighted":false,'
    '"vertices":[{"x":0,"y":0},{"x":50,"y":0},{"x":0,"y":50}],'
    '"uvs":[0,0,1,0,0,1],"triangles":[0,1,2]}]}';

DeformTimeline _timeline({
  String skin = 'default',
  String slot = 'body',
  String attachment = 'cloth',
  int vertexCount = 3,
  required List<DeformKeyframe> keys,
}) =>
    DeformTimeline(
      skin: skin,
      slot: slot,
      attachment: attachment,
      vertexCount: vertexCount,
      keys: keys,
    );

void main() {
  group('buildDrawBatches deform override strictness', () {
    late SkeletonData base;

    setUpAll(() {
      base = loadBonyJson(_meshFixture);
    });

    SkeletonData withOverride(DeformOverride o) => SkeletonData(
          header: base.header,
          bones: base.bones,
          slots: base.slots,
          regions: base.regions,
          paths: base.paths,
          pathAttachments: base.pathAttachments,
          meshAttachments: base.meshAttachments,
          deformOverrides: [o],
        );

    test('raises on a deform override whose length != skinned vertex count', () {
      // Mesh cloth has 3 vertices; a 2-delta override must fail loudly, matching
      // Nim's applyDeformDeltas schemaViolation instead of rendering static mesh.
      final data = withOverride(const DeformOverride(
        slot: 'body',
        attachment: 'cloth',
        deltas: [MeshDelta(x: 1, y: 0), MeshDelta(x: 0, y: 0)],
      ));
      expect(() => buildDrawBatches(data), throwsFormatException);
    });

    test('applies a correctly-sized override without raising', () {
      final data = withOverride(const DeformOverride(
        slot: 'body',
        attachment: 'cloth',
        deltas: [MeshDelta(x: 2, y: 0), MeshDelta(x: 0, y: 0), MeshDelta(x: 0, y: 0)],
      ));
      final batches = buildDrawBatches(data);
      final batch = batches.firstWhere((b) => b.slot == 'body');
      // vertex 0 offset by (2,0) after skinning at the identity root.
      expect((batch.vertices[0].x - 2.0).abs(), lessThanOrEqualTo(1e-4));
    });

    test('absent override for the slot/mesh is not an error', () {
      final batches = buildDrawBatches(base); // no overrides staged
      expect(batches.firstWhere((b) => b.slot == 'body'), isNotNull);
    });
  });

  group('sampleDeformDeltas structural validate parity', () {
    test('over-range offset raises FormatException, not RangeError', () {
      // offset 2 + 2 deltas = 4 > vertexCount 3. Before the fix this surfaced as
      // a raw RangeError from _expandDeformKey; now validate makes it a domain
      // error at the sample boundary, matching Nim's validateDeformTimeline.
      final timeline = _timeline(keys: const [
        DeformKeyframe(
          time: 0.0,
          offset: 2,
          deltas: [MeshDelta(x: 1, y: 0), MeshDelta(x: 1, y: 0)],
        ),
      ]);
      expect(() => sampleDeformDeltas(timeline, 0.0), throwsFormatException);
      expect(() => sampleDeformDeltas(timeline, 0.0),
          isNot(throwsA(isA<RangeError>())));
    });

    test('negative offset raises FormatException', () {
      final timeline = _timeline(keys: const [
        DeformKeyframe(time: 0.0, offset: -1, deltas: [MeshDelta(x: 1, y: 0)]),
      ]);
      expect(() => sampleDeformDeltas(timeline, 0.0), throwsFormatException);
    });

    test('empty keys raises FormatException', () {
      final timeline = _timeline(keys: const []);
      expect(() => sampleDeformDeltas(timeline, 0.0), throwsFormatException);
    });

    test('non-positive vertexCount raises FormatException', () {
      final timeline = _timeline(vertexCount: 0, keys: const [
        DeformKeyframe(time: 0.0, offset: 0, deltas: [MeshDelta(x: 1, y: 0)]),
      ]);
      expect(() => sampleDeformDeltas(timeline, 0.0), throwsFormatException);
    });

    test('non-strictly-increasing key times raise FormatException', () {
      final timeline = _timeline(keys: const [
        DeformKeyframe(time: 0.0, offset: 0, deltas: [MeshDelta(x: 1, y: 0)]),
        DeformKeyframe(time: 0.0, offset: 0, deltas: [MeshDelta(x: 2, y: 0)]),
      ]);
      expect(() => sampleDeformDeltas(timeline, 0.0), throwsFormatException);
    });

    test('empty skin/slot/attachment raise FormatException', () {
      final key = const DeformKeyframe(
          time: 0.0, offset: 0, deltas: [MeshDelta(x: 1, y: 0)]);
      expect(() => sampleDeformDeltas(_timeline(skin: '', keys: [key]), 0.0),
          throwsFormatException);
      expect(() => sampleDeformDeltas(_timeline(slot: '', keys: [key]), 0.0),
          throwsFormatException);
      expect(
          () => sampleDeformDeltas(_timeline(attachment: '', keys: [key]), 0.0),
          throwsFormatException);
    });

    test('a valid timeline still samples its dense deltas', () {
      final timeline = _timeline(keys: const [
        DeformKeyframe(time: 0.0, offset: 0, deltas: [MeshDelta(x: 2, y: 0)]),
      ]);
      final deltas = sampleDeformDeltas(timeline, 0.0);
      expect(deltas, hasLength(3));
      expect((deltas[0].x - 2.0).abs(), lessThanOrEqualTo(1e-4));
      expect(deltas[1].x, 0.0);
    });
  });
}
