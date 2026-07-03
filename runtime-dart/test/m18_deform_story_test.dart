// Dart M18 DEFORM-STORY conformance gate: state-machine-driven mesh-deform
// goldens (the first animated, nonzero-time mesh in the suite).
//
// Replays the `deform_story` state machine of m18_mesh_deform_anim_rig at the
// three input-script samples (rest t=0, mid t=0.5, end t=1.0). The single
// `mesh` layer plays the `wiggle` clip, whose clip-owned deform timeline offsets
// rim vertex 1 of the unweighted `panel` mesh. Each sample's pose is applied to
// the skeleton and fed to buildDrawBatches; the mesh_slot draw-batch vertices
// (x/y/u/v/colour) are matched to the committed goldens
// conformance/goldens/m18_deform_story_{rest,mid,end}.json within 1e-4.
//
// This exercises the full SM -> applyPose (deform override staged on the posed
// skeleton) -> buildDrawBatches (delta applied after skinning) path, and pins
// .bony-vs-.bnb parity for one sample. Tests run from runtime-dart/ so
// ../conformance/ resolves to repo root.

import 'dart:convert';
import 'dart:io';

import 'package:bony/bony.dart';
import 'package:test/test.dart';

const double _tol = 1e-4;

void _expectClose(double actual, double expected, String label) {
  expect((actual - expected).abs(), lessThanOrEqualTo(_tol),
      reason: '$label: actual=$actual expected=$expected');
}

const _samples = <({String name, double t})>[
  (name: 'rest', t: 0.0),
  (name: 'mid', t: 0.5),
  (name: 'end', t: 1.0),
];

// Drive the SM to absolute time t on a fresh runtime (each input-script sample
// is an independent absolute time), apply the resulting pose, and build draw
// batches against the posed skeleton (which now carries the deform override).
List<DrawBatch> _batchesAt(
    SkeletonData base, StateMachineData story, double t) {
  final rt = initStateMachineRuntime(story);
  rt.update(t);
  final evaluated = rt.evaluate(base);
  final posed = applyPose(base, evaluated.pose);
  return buildDrawBatches(posed);
}

DrawBatch _meshBatch(List<DrawBatch> batches) =>
    batches.firstWhere((b) => b.slot == 'mesh_slot');

void main() {
  late SkeletonData base;
  late StateMachineData story;

  setUpAll(() {
    base = loadBonyJson(
      File('../conformance/assets/m18_mesh_deform_anim_rig.bony')
          .readAsStringSync(),
    );
    story = base.stateMachines.firstWhere((s) => s.name == 'deform_story');
  });

  test('deform timeline loads onto the wiggle clip', () {
    final clip = base.animations.firstWhere((a) => a.name == 'wiggle');
    expect(clip.deformTimelines, hasLength(1));
    final dt = clip.deformTimelines.single;
    expect(dt.skin, 'default');
    expect(dt.slot, 'mesh_slot');
    expect(dt.attachment, 'panel');
    expect(dt.vertexCount, 5);
    expect(dt.keys, hasLength(3));
    // Rim vertex 1 is the animated offset; key 1 pushes it +30 in x.
    expect(dt.keys[1].offset, 1);
    expect(dt.keys[1].deltas.single.x, closeTo(30.0, _tol));
  });

  for (final sample in _samples) {
    group('m18_deform_story ${sample.name} (t=${sample.t})', () {
      late Map<String, dynamic> golden;
      late List<DrawBatch> batches;

      setUpAll(() {
        golden = jsonDecode(
          File('../conformance/goldens/m18_deform_story_${sample.name}.json')
              .readAsStringSync(),
        ) as Map<String, dynamic>;
        batches = _batchesAt(base, story, sample.t);
      });

      test('every draw-batch vertex matches the golden within 1e-4', () {
        final goldenBatches = golden['drawBatches'] as List<dynamic>;
        expect(batches, hasLength(goldenBatches.length));
        for (var i = 0; i < goldenBatches.length; i++) {
          final gb = goldenBatches[i] as Map<String, dynamic>;
          final batch = batches[i];
          expect(batch.slot, gb['slot'], reason: 'batch $i slot');
          final gv = gb['vertices'] as List<dynamic>;
          expect(batch.vertices, hasLength(gv.length),
              reason: 'batch $i vertex count');
          for (var v = 0; v < gv.length; v++) {
            final g = gv[v] as Map<String, dynamic>;
            final vert = batch.vertices[v];
            final label = '${sample.name} batch $i vertex $v';
            _expectClose(vert.x, (g['x'] as num).toDouble(), '$label.x');
            _expectClose(vert.y, (g['y'] as num).toDouble(), '$label.y');
            _expectClose(vert.u, (g['u'] as num).toDouble(), '$label.u');
            _expectClose(vert.v, (g['v'] as num).toDouble(), '$label.v');
            _expectClose(vert.r, (g['r'] as num).toDouble(), '$label.r');
            _expectClose(vert.g, (g['g'] as num).toDouble(), '$label.g');
            _expectClose(vert.b, (g['b'] as num).toDouble(), '$label.b');
            _expectClose(vert.a, (g['a'] as num).toDouble(), '$label.a');
          }
        }
      });
    });
  }

  test('non-vacuous: animated rim vertex sweeps x 50 -> 80 -> 56', () {
    final rest = _meshBatch(_batchesAt(base, story, 0.0)).vertices[1];
    final mid = _meshBatch(_batchesAt(base, story, 0.5)).vertices[1];
    final end = _meshBatch(_batchesAt(base, story, 1.0)).vertices[1];
    _expectClose(rest.x, 50.0, 'rest v1.x');
    _expectClose(mid.x, 80.0, 'mid v1.x');
    _expectClose(end.x, 56.0, 'end v1.x');
    // u/v carried through the deform unchanged.
    _expectClose(mid.u, 1.0, 'mid v1.u');
    _expectClose(mid.v, 0.5, 'mid v1.v');
  });

  // The three committed goldens sample exactly on the keyframe times, so they
  // never traverse the sampler's interpolation branch. Drive a fractional time
  // on the linear key0->key1 span (t=0.25 => eased 0.5 => v1 delta +15) to
  // exercise (and pin the f32-quantization of) that branch directly.
  test('interpolated sample at t=0.25 offsets rim vertex to x=65', () {
    final v1 = _meshBatch(_batchesAt(base, story, 0.25)).vertices[1];
    _expectClose(v1.x, 65.0, 't=0.25 v1.x');
    _expectClose(v1.y, 0.0, 't=0.25 v1.y');
    _expectClose(v1.u, 1.0, 't=0.25 v1.u');
    _expectClose(v1.v, 0.5, 't=0.25 v1.v');
  });

  test('.bony and .bnb produce identical animated vertices at mid', () {
    final fromJson = loadBonyJson(
      File('../conformance/assets/m18_mesh_deform_anim_rig.bony')
          .readAsStringSync(),
    );
    final fromBnb = loadBonyBnb(
      File('../conformance/assets/bnb/m18_mesh_deform_anim_rig.bnb')
          .readAsBytesSync(),
    );
    final storyJson =
        fromJson.stateMachines.firstWhere((s) => s.name == 'deform_story');
    final storyBnb =
        fromBnb.stateMachines.firstWhere((s) => s.name == 'deform_story');
    final ja = _meshBatch(_batchesAt(fromJson, storyJson, 0.5)).vertices;
    final jb = _meshBatch(_batchesAt(fromBnb, storyBnb, 0.5)).vertices;
    expect(jb, hasLength(ja.length));
    for (var v = 0; v < ja.length; v++) {
      _expectClose(jb[v].x, ja[v].x, 'bnb vertex $v.x');
      _expectClose(jb[v].y, ja[v].y, 'bnb vertex $v.y');
      _expectClose(jb[v].u, ja[v].u, 'bnb vertex $v.u');
      _expectClose(jb[v].v, ja[v].v, 'bnb vertex $v.v');
    }
  });
}
