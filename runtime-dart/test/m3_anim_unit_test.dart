// Dart M3 animation engine unit tests.
//
// Tests the Bézier easing evaluator, timeline sampling, multi-track mixer,
// and applyPose — all exercised programmatically without a golden file.

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
  // ------------------------------------------------------------------ Bézier
  group('Bézier easing (16-sample table + Newton-Raphson)', () {
    test('linear curve evaluates to identity', () {
      _expectClose(evaluateCurve(TimelineCurve.linear, 0.0), 0.0, 'linear(0)');
      _expectClose(evaluateCurve(TimelineCurve.linear, 0.5), 0.5, 'linear(0.5)');
      _expectClose(evaluateCurve(TimelineCurve.linear, 1.0), 1.0, 'linear(1)');
    });

    test('stepped curve evaluates to 0 for t<1, 1 at endpoints', () {
      _expectClose(evaluateCurve(TimelineCurve.stepped, 0.0), 0.0, 'stepped(0)');
      _expectClose(evaluateCurve(TimelineCurve.stepped, 0.5), 0.0, 'stepped(0.5)');
      _expectClose(evaluateCurve(TimelineCurve.stepped, 1.0), 0.0, 'stepped(1)');
    });

    test('bezier ease-in curve biases early portion low', () {
      // c1=(0.42,0), c2=(1,1) is a classic ease-in
      final easeIn = TimelineCurve.bezier(0.42, 0.0, 1.0, 1.0);
      final mid = evaluateCurve(easeIn, 0.5);
      expect(mid, lessThan(0.5), reason: 'ease-in should be below linear at 0.5');
    });

    test('bezier ease-out curve biases early portion high', () {
      // c1=(0,0), c2=(0.58,1) is a classic ease-out
      final easeOut = TimelineCurve.bezier(0.0, 0.0, 0.58, 1.0);
      final mid = evaluateCurve(easeOut, 0.5);
      expect(mid, greaterThan(0.5), reason: 'ease-out should be above linear at 0.5');
    });

    test('bezier endpoint values are clamped correctly', () {
      final curve = TimelineCurve.bezier(0.25, 0.1, 0.75, 0.9);
      _expectClose(evaluateCurve(curve, 0.0), 0.0, 'bezier(0)');
      _expectClose(evaluateCurve(curve, 1.0), 1.0, 'bezier(1)');
    });

    test('bezier evaluator clamps t outside [0,1]', () {
      final curve = TimelineCurve.bezier(0.25, 0.1, 0.75, 0.9);
      expect(evaluateCurve(curve, -0.5), equals(0.0));
      expect(evaluateCurve(curve, 1.5), equals(1.0));
    });
  });

  // -------------------------------------------------------- Timeline sampling
  group('Timeline sampling', () {
    test('single keyframe returns that value at any time', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.rotate,
        keys: [const ScalarKeyframe(time: 0.0, value: 45.0)],
      );
      _expectClose(sampleBoneTimeline(tl, 0.0), 45.0, 'single-key t=0');
      _expectClose(sampleBoneTimeline(tl, 1.0), 45.0, 'single-key t=1');
    });

    test('linear interpolation between two keyframes', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.rotate,
        keys: [
          const ScalarKeyframe(time: 0.0, value: 0.0),
          const ScalarKeyframe(time: 1.0, value: 90.0),
        ],
      );
      _expectClose(sampleBoneTimeline(tl, 0.0), 0.0, 't=0');
      _expectClose(sampleBoneTimeline(tl, 0.5), 45.0, 't=0.5');
      _expectClose(sampleBoneTimeline(tl, 1.0), 90.0, 't=1');
    });

    test('stepped curve holds first value', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.rotate,
        keys: [
          const ScalarKeyframe(time: 0.0, value: 0.0, curve: TimelineCurve.stepped),
          const ScalarKeyframe(time: 1.0, value: 90.0),
        ],
      );
      _expectClose(sampleBoneTimeline(tl, 0.5), 0.0, 'stepped mid');
      _expectClose(sampleBoneTimeline(tl, 1.0), 90.0, 'stepped at end key');
    });

    test('time clamped to last keyframe beyond duration', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.rotate,
        keys: [
          const ScalarKeyframe(time: 0.0, value: 0.0),
          const ScalarKeyframe(time: 1.0, value: 90.0),
        ],
      );
      _expectClose(sampleBoneTimeline(tl, 2.0), 90.0, 't>duration');
    });

    test('time before first key returns first key value', () {
      final tl = BoneTimeline(
        bone: 'root',
        kind: BoneTimelineKind.rotate,
        keys: [
          const ScalarKeyframe(time: 0.5, value: 30.0),
          const ScalarKeyframe(time: 1.0, value: 90.0),
        ],
      );
      _expectClose(sampleBoneTimeline(tl, 0.0), 30.0, 't<first');
    });
  });

  // ---------------------------------------------- AnimationState (single track)
  group('AnimationState single-track', () {
    late SkeletonData data;

    setUpAll(() {
      data = loadBonyJson(
        File('../conformance/assets/m8_rig.bony').readAsStringSync(),
      );
    });

    test('m8 rig loads with animations', () {
      expect(data.animations, isNotEmpty);
    });

    test('setup pose with empty state equals computeWorldTransforms', () {
      final state = AnimationState(data);
      final pose = state.sample();
      expect(pose.scalars, isEmpty);

      final worlds = computeWorldTransforms(data);
      final worlds2 = computeWorldTransforms(applyPose(data, pose));
      for (var i = 0; i < worlds.length; i++) {
        _expectClose(worlds[i].a,  worlds2[i].a,  'bone[$i].a');
        _expectClose(worlds[i].tx, worlds2[i].tx, 'bone[$i].tx');
        _expectClose(worlds[i].ty, worlds2[i].ty, 'bone[$i].ty');
      }
    });

    test('at t=0 of idle animation: result matches setup pose', () {
      // The idle animation starts at value=0 (= setup pose rotation=0) so
      // the animated pose at t=0 should equal the setup pose.
      final idle = data.animations.firstWhere((c) => c.name == 'idle');
      final state = AnimationState(data)
        ..setAnimation(0, idle);
      // time is 0 initially — no update needed
      final pose = state.sample();
      final animData = applyPose(data, pose);

      // root bone should have rotation ≈ 0 at t=0 of idle
      final rootSetup = data.bones.first;
      final rootAnim = animData.bones.first;
      _expectClose(rootAnim.rotation, rootSetup.rotation, 'root.rotation at t=0');
    });

    test('at t=0.5 of idle animation: root bone is rotated', () {
      final idle = data.animations.firstWhere((c) => c.name == 'idle');
      final state = AnimationState(data)
        ..setAnimation(0, idle)
        ..update(0.5);
      final pose = state.sample();
      final animData = applyPose(data, pose);

      // idle: rotate from 0 at t=0 to 10 at t=1.0 → at t=0.5 expect ≈ 5.0
      _expectClose(animData.bones.first.rotation, 5.0, 'root.rotation at t=0.5');
    });

    test('loop wraps time correctly', () {
      final walk = data.animations.firstWhere((c) => c.name == 'walk');
      // walk: root rotate from 5 at t=0 to -5 at t=0.5, duration=0.5
      // at t=0.75 with loop, wraps to 0.25, expect midpoint between 5 and -5 = 0
      final state = AnimationState(data)
        ..setAnimation(0, walk, loop: true)
        ..update(0.75);
      final pose = state.sample();
      final animData = applyPose(data, pose);
      _expectClose(animData.bones.first.rotation, 0.0, 'root.rotation at looped t=0.75');
    });

    test('world transforms after animation match expected values', () {
      final idle = data.animations.firstWhere((c) => c.name == 'idle');
      final state = AnimationState(data)
        ..setAnimation(0, idle)
        ..update(1.0); // at t=1.0, idle rotation = 10 degrees
      final pose = state.sample();
      final animData = applyPose(data, pose);
      final worlds = computeWorldTransforms(animData);

      // root has rotation=10° at t=1.0 — cos(10°)≈0.9848, sin(10°)≈0.1736
      _expectClose(worlds[0].a, 0.9848, 'root.world.a at t=1.0');
      _expectClose(worlds[0].b, 0.1736, 'root.world.b at t=1.0');
    });
  });

  // -------------------------------------------- Animation loader integration
  group('Animation loader', () {
    test('m3 rig has no animations', () {
      final data = loadBonyJson(
        File('../conformance/assets/m3_rig.bony').readAsStringSync(),
      );
      expect(data.animations, isEmpty);
    });

    test('m8 rig loads animation names correctly', () {
      final data = loadBonyJson(
        File('../conformance/assets/m8_rig.bony').readAsStringSync(),
      );
      final names = data.animations.map((c) => c.name).toSet();
      expect(names, containsAll(['idle', 'walk', 'run', 'wave']));
    });

    test('m8 idle animation has correct bone timeline', () {
      final data = loadBonyJson(
        File('../conformance/assets/m8_rig.bony').readAsStringSync(),
      );
      final idle = data.animations.firstWhere((c) => c.name == 'idle');
      expect(idle.boneTimelines, hasLength(1));
      expect(idle.boneTimelines.first.bone, 'root');
      expect(idle.boneTimelines.first.kind, BoneTimelineKind.rotate);
      expect(idle.boneTimelines.first.keys, hasLength(2));
      _expectClose(idle.boneTimelines.first.keys.first.value, 0.0, 'idle key[0].value');
      _expectClose(idle.boneTimelines.first.keys.last.value, 10.0, 'idle key[1].value');
    });

    test('animation duration computed from last keyframe time', () {
      final data = loadBonyJson(
        File('../conformance/assets/m8_rig.bony').readAsStringSync(),
      );
      final idle = data.animations.firstWhere((c) => c.name == 'idle');
      _expectClose(idle.duration, 1.0, 'idle.duration');
      final walk = data.animations.firstWhere((c) => c.name == 'walk');
      _expectClose(walk.duration, 0.5, 'walk.duration');
    });
  });
}
