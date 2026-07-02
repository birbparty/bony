// Dart M5-PHYSICS STORY conformance gate: state-machine-driven physics goldens.
//
// Reproduces the Nim-authored physics story goldens
// conformance/goldens/m5_physics_story_{rest,excited,settled}.json in Dart.
//
// Physics is bony's only stateful, time-dependent constraint. Unlike the pure
// IK story (m5_ik_story_test.dart), the physics story CANNOT be sampled with a
// fresh runtime per absolute time: the spring offset depends on the frame
// history. So this test mirrors the Nim CLI story runner exactly — one
// StateMachineRuntime advanced by the inter-sample delta, and one
// PhysicsConstraintState per constraint carried across every sample, advanced
// by that same delta via advancePhysics. The pendulum's `bob_spring` (a
// critically-damped rotate spring) is excited by the `swing` clip's target step
// and settles across rest (t=0) -> excited (t=0.1) -> settled (t=0.2).
//
// Both the .bony (JSON) and the .bnb (binary) loaders are exercised; both must
// reproduce every golden within 1e-4. Tests run from runtime-dart/ so
// ../conformance/ resolves to repo root.

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
  (name: 'excited', t: 0.1),
  (name: 'settled', t: 0.2),
];

Map<String, dynamic> _loadGolden(String name) => jsonDecode(
      File('../conformance/goldens/m5_physics_story_$name.json')
          .readAsStringSync(),
    ) as Map<String, dynamic>;

// Replay the whole story on one runtime + one carried physics state, returning
// the per-sample physics-advanced world matrices keyed by sample name. Mirrors
// the Nim CLI runStateMachineSamples loop (advance every sample, by dt).
Map<String, List<Affine2>> _replay(SkeletonData base) {
  final story = base.stateMachines.firstWhere((s) => s.name == 'physics_story');
  final rt = initStateMachineRuntime(story);
  final states = newPhysicsStates(base);
  final out = <String, List<Affine2>>{};
  var prevTime = 0.0;
  for (final sample in _samples) {
    final dt = sample.t - prevTime;
    rt.update(dt);
    final evaluated = rt.evaluate(base);
    final posed = applyPose(base, evaluated.pose);
    out[sample.name] = advancePhysics(posed, states, dt);
    prevTime = sample.t;
  }
  return out;
}

void main() {
  late SkeletonData baseJson;

  setUpAll(() {
    baseJson = loadBonyJson(
      File('../conformance/assets/m5_physics_rig.bony').readAsStringSync(),
    );
  });

  // Run the full parity gate against both the JSON and the binary loaders; the
  // binary loader must decode the physics record identically.
  for (final loader in const ['bony', 'bnb']) {
    group('m5_physics_story via .$loader loader', () {
      late SkeletonData base;
      late Map<String, List<Affine2>> worldsByName;

      setUpAll(() {
        base = loader == 'bony'
            ? baseJson
            : loadBonyBnb(
                File('../conformance/assets/bnb/m5_physics_rig.bnb')
                    .readAsBytesSync(),
              );
        worldsByName = _replay(base);
      });

      test('physics constraint survived the load', () {
        expect(base.physicsConstraints, hasLength(1));
        final pc = base.physicsConstraints.single;
        expect(pc.name, 'bob_spring');
        expect(pc.bone, 'pendulum');
        expect(pc.channels, contains(PhysicsChannel.rotate));
      });

      for (final sample in _samples) {
        group('${sample.name} (t=${sample.t})', () {
          late Map<String, dynamic> golden;
          late Map<String, Map<String, dynamic>> goldenWorld;
          late List<Affine2> worlds;

          setUpAll(() {
            golden = _loadGolden(sample.name);
            goldenWorld = {
              for (final b
                  in (golden['bones'] as List).cast<Map<String, dynamic>>())
                b['name'] as String: b['world'] as Map<String, dynamic>,
            };
            worlds = worldsByName[sample.name]!;
          });

          test('golden metadata matches (format/skeleton/sample/time/sm)', () {
            expect(golden['format'], 'bony.numeric-golden.v1');
            expect(golden['skeleton'], base.header.name);
            expect(golden['sample'], sample.name);
            // Golden time is f32-quantized (e.g. 0.1 -> 0.10000000149...), so
            // compare within f32 precision rather than exact double equality.
            expect((golden['time'] as num).toDouble(), closeTo(sample.t, 1e-6));
            expect(golden['stateMachine'], 'physics_story');
          });

          test('bone count matches golden', () {
            expect(worlds, hasLength((golden['bones'] as List).length));
          });

          test('every bone world matrix matches golden (abs <= 1e-4)', () {
            for (var i = 0; i < base.bones.length; i++) {
              final name = base.bones[i].name;
              final g = goldenWorld[name];
              expect(g, isNotNull, reason: 'golden missing bone: $name');
              _expectAffine(worlds[i], g!, 'bones[$name].world');
            }
          });
        });
      }
    });
  }

  // Non-vacuity + settling: the pendulum world angle must actually move each
  // sample (a dropped-physics or dropped-advance bug would leave it static at
  // the target), and the inter-sample deltas exceed 1e-4 while converging.
  test('pendulum world angle is non-vacuous and settling across the story', () {
    final worldsByName = _replay(baseJson);
    final pi = baseJson.bones.indexWhere((b) => b.name == 'pendulum');
    final rest = _worldAngleDeg(worldsByName['rest']![pi]);
    final excited = _worldAngleDeg(worldsByName['excited']![pi]);
    final settled = _worldAngleDeg(worldsByName['settled']![pi]);
    // ~0 -> ~14.29 -> ~28.34 per the rig design (README M5 physics section).
    expect(rest, closeTo(0.0, 0.5));
    expect(excited, closeTo(14.289967, 0.5));
    expect(settled, closeTo(28.336548, 0.5));
    // Monotone toward the 45-degree target; each step well above tolerance.
    expect(excited - rest, greaterThan(1e-4));
    expect(settled - excited, greaterThan(1e-4));
    // Settling: the spring never overshoots its 45-degree target.
    expect(settled, lessThan(45.0));
  });

  // Regression: applyPose must preserve physicsConstraints, or a posed skeleton
  // silently loses all physics (the bony-1c5/cz7 constraint-drop bug class).
  test('applyPose preserves physicsConstraints on the posed skeleton', () {
    final story =
        baseJson.stateMachines.firstWhere((s) => s.name == 'physics_story');
    final rt = initStateMachineRuntime(story);
    rt.update(0.1);
    final posed = applyPose(baseJson, rt.evaluate(baseJson).pose);
    expect(posed.physicsConstraints, hasLength(baseJson.physicsConstraints.length));
    expect(posed.physicsConstraints.map((c) => c.name),
        baseJson.physicsConstraints.map((c) => c.name));
  });
}
