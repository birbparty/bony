// Dart M5-IK STORY conformance gate: state-machine-driven IK goldens.
//
// Replays the `ik_story` state machine of m5_ik_rig at the three input-script
// samples (rest t=0, reach_mid t=0.5, reach_end t=1.0). The `reach` layer's
// `target_slide` clip animates the chain IK target from (250,20) to (205,40);
// each sample's pose is applied to the skeleton and fed to
// computeWorldTransforms, which solves IK against the moved target. Bone world
// matrices are matched to the committed goldens
// conformance/goldens/m5_ik_story_{rest,reach_mid,reach_end}.json within 1e-4.
//
// This exercises the full SM -> applyPose -> computeWorldTransforms -> IK path,
// complementing the static setup-pose gate in m10_conformance_test.dart. Tests
// run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:bony/bony.dart';

const double _tol = 1e-4;

void _expectClose(double actual, double expected, String label) {
  expect((actual - expected).abs(), lessThanOrEqualTo(_tol),
      reason: '$label: actual=$actual expected=$expected');
}

void _expectAffine(Affine2 a, Map<String, dynamic> g, String label) {
  _expectClose(a.a, (g['a'] as num).toDouble(), '$label.a');
  _expectClose(a.b, (g['b'] as num).toDouble(), '$label.b');
  _expectClose(a.c, (g['c'] as num).toDouble(), '$label.c');
  _expectClose(a.d, (g['d'] as num).toDouble(), '$label.d');
  _expectClose(a.tx, (g['tx'] as num).toDouble(), '$label.tx');
  _expectClose(a.ty, (g['ty'] as num).toDouble(), '$label.ty');
}

double _worldAngleDeg(Affine2 w) => math.atan2(w.b, w.a) * 180.0 / math.pi;

const _samples = <({String name, double t})>[
  (name: 'rest', t: 0.0),
  (name: 'reach_mid', t: 0.5),
  (name: 'reach_end', t: 1.0),
];

void main() {
  late SkeletonData base;
  late StateMachineData story;

  setUpAll(() {
    base = loadBonyJson(
      File('../conformance/assets/m5_ik_rig.bony').readAsStringSync(),
    );
    story = base.stateMachines.firstWhere((s) => s.name == 'ik_story');
  });

  // Drive the SM to time t on a fresh runtime (each input-script sample is an
  // independent absolute time; the non-looping slide clip clamps at its 1.0
  // duration, so update(t) reaches the same pose the Nim cumulative replay
  // records), apply the resulting pose, and solve.
  ({
    SkeletonData posed,
    List<Affine2> worlds,
    EvaluatedStateMachine evaluated,
    StateMachineRuntime runtime,
  }) _sampleAt(double t) {
    final rt = initStateMachineRuntime(story);
    rt.update(t);
    final evaluated = rt.evaluate(base);
    final posed = applyPose(base, evaluated.pose);
    return (
      posed: posed,
      worlds: computeWorldTransforms(posed),
      evaluated: evaluated,
      runtime: rt,
    );
  }

  Map<String, dynamic> _loadGolden(String name) => jsonDecode(
        File('../conformance/goldens/m5_ik_story_$name.json').readAsStringSync(),
      ) as Map<String, dynamic>;

  for (final sample in _samples) {
    group('m5_ik_story ${sample.name} (t=${sample.t})', () {
      late List<Affine2> worlds;
      late SkeletonData posed;
      late EvaluatedStateMachine evaluated;
      late StateMachineRuntime runtime;
      late Map<String, dynamic> golden;
      late Map<String, Map<String, dynamic>> goldenWorld;

      setUpAll(() {
        final r = _sampleAt(sample.t);
        worlds = r.worlds;
        posed = r.posed;
        evaluated = r.evaluated;
        runtime = r.runtime;
        golden = _loadGolden(sample.name);
        goldenWorld = {
          for (final b in (golden['bones'] as List).cast<Map<String, dynamic>>())
            b['name'] as String: b['world'] as Map<String, dynamic>,
        };
      });

      test('golden metadata matches (format/skeleton/sample/time/sm)', () {
        expect(golden['format'], 'bony.numeric-golden.v1');
        expect(golden['skeleton'], base.header.name);
        expect(golden['sample'], sample.name);
        expect((golden['time'] as num).toDouble(), sample.t);
        expect(golden['stateMachine'], 'ik_story');
      });

      test('reach layer is in the slide state at time t with no events', () {
        final layer = evaluated.layers.firstWhere((l) => l.layer == 'reach');
        expect(layer.state, 'slide');
        expect(layer.time, closeTo(sample.t, 1e-9));
        expect(runtime.events, isEmpty);
        // Cross-check against the golden's own layer metadata + events.
        final gLayer =
            (golden['layers'] as List).first as Map<String, dynamic>;
        expect(gLayer['state'], layer.state);
        expect((gLayer['time'] as num).toDouble(), closeTo(layer.time, 1e-9));
        expect(golden['events'], isEmpty);
      });

      test('bone count matches golden', () {
        expect(worlds, hasLength((golden['bones'] as List).length));
      });

      test('every bone world matrix matches golden (abs <= 1e-4)', () {
        for (var i = 0; i < posed.bones.length; i++) {
          final name = posed.bones[i].name;
          final g = goldenWorld[name];
          expect(g, isNotNull, reason: 'golden missing bone: $name');
          _expectAffine(worlds[i], g!, 'bones[$name].world');
        }
      });

      test('animated IK target reached its golden world position', () {
        final index = {
          for (var i = 0; i < posed.bones.length; i++) posed.bones[i].name: i,
        };
        final ct = worlds[index['chain_target']!];
        final gct = goldenWorld['chain_target']!;
        _expectClose(ct.tx, (gct['tx'] as num).toDouble(), 'chain_target.tx');
        _expectClose(ct.ty, (gct['ty'] as num).toDouble(), 'chain_target.ty');
      });
    });
  }

  // Non-vacuity: the solved chain terminal must actually sweep as the target
  // slides (a dropped-IK or dropped-animation bug would leave it static).
  test('chain_c terminal angle sweeps monotonically across the story', () {
    final angles = <double>[];
    for (final s in _samples) {
      final r = _sampleAt(s.t);
      final ci = r.posed.bones.indexWhere((b) => b.name == 'chain_c');
      angles.add(_worldAngleDeg(r.worlds[ci]));
    }
    // ~31.7 -> ~56.3 -> ~65.6 per the rig design.
    expect(angles[0], closeTo(31.7, 0.5));
    expect(angles[1], closeTo(56.3, 0.5));
    expect(angles[2], closeTo(65.6, 0.5));
    expect(angles[1], greaterThan(angles[0]));
    expect(angles[2], greaterThan(angles[1]));
  });

  // Regression: applyPose must preserve IK constraints, or a posed skeleton
  // silently loses all IK (it previously dropped them, leaving the story
  // terminals at their unconstrained ~36-off positions).
  test('applyPose preserves ikConstraints on the posed skeleton', () {
    final rt = initStateMachineRuntime(story);
    rt.update(0.5);
    final posed = applyPose(base, rt.evaluate(base).pose);
    expect(posed.ikConstraints, hasLength(base.ikConstraints.length));
    expect(posed.ikConstraints.map((c) => c.name),
        base.ikConstraints.map((c) => c.name));
  });
}
