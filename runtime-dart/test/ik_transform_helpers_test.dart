// Unit tests for the M5-IK evaluation helpers added to transform.dart
// (worldRotationDegrees, ikDistance, restWorldFor) — the kind-agnostic prep
// that _applyRuntimeIk will consume in a later slice. Expected values are
// hand-computed; restWorldFor is additionally checked against the invariant
// that, for an unconstrained skeleton, the rest FK equals the setup-pose FK
// produced by computeWorldTransforms (a strong, non-circular oracle).
//
// Tests run from runtime-dart/ so ../conformance/ resolves to repo root.

import 'dart:io';
import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:bony/bony.dart';

Affine2 _rot(double degrees) {
  final r = degrees * math.pi / 180.0;
  // World x-axis (a, b) carries the rotation; c/d/tx/ty are irrelevant here.
  return Affine2(
    a: math.cos(r),
    b: math.sin(r),
    c: -math.sin(r),
    d: math.cos(r),
    tx: 7.0,
    ty: -3.0,
  );
}

void main() {
  group('worldRotationDegrees', () {
    test('identity affine has zero rotation', () {
      const identity = Affine2(a: 1, b: 0, c: 0, d: 1, tx: 0, ty: 0);
      expect(worldRotationDegrees(identity), closeTo(0.0, 1e-12));
    });

    test('recovers the rotation angle across quadrants', () {
      expect(worldRotationDegrees(_rot(30.0)), closeTo(30.0, 1e-9));
      expect(worldRotationDegrees(_rot(120.0)), closeTo(120.0, 1e-9));
      expect(worldRotationDegrees(_rot(-45.0)), closeTo(-45.0, 1e-9));
      // atan2 wraps to (-180, 180]: 200deg reads back as -160.
      expect(worldRotationDegrees(_rot(200.0)), closeTo(-160.0, 1e-9));
    });
  });

  group('ikDistance', () {
    test('classic 3-4-5 triangle', () {
      expect(ikDistance(const IkPoint(0, 0), const IkPoint(3, 4)),
          closeTo(5.0, 1e-12));
    });

    test('coincident points are zero distance', () {
      expect(ikDistance(const IkPoint(1, 1), const IkPoint(1, 1)),
          closeTo(0.0, 1e-12));
    });

    test('is translation-invariant and symmetric', () {
      final d1 = ikDistance(const IkPoint(-2, -1), const IkPoint(1, 3));
      final d2 = ikDistance(const IkPoint(1, 3), const IkPoint(-2, -1));
      expect(d1, closeTo(5.0, 1e-12));
      expect(d2, closeTo(5.0, 1e-12));
    });
  });

  group('restWorldFor', () {
    late SkeletonData data;
    late List<Affine2> setupWorlds;
    late Map<String, int> indexes;

    setUpAll(() {
      // m2_rig has a bone hierarchy and NO runtime constraints, so its
      // setup-pose FK IS its rest FK — computeWorldTransforms is the oracle.
      data = loadBonyJson(
        File('../conformance/assets/m2_rig.bony').readAsStringSync(),
      );
      setupWorlds = computeWorldTransforms(data);
      indexes = <String, int>{
        for (var i = 0; i < data.bones.length; i++) data.bones[i].name: i,
      };
    });

    test('rig actually exercises parented bones (recursion is real)', () {
      expect(data.bones.length, greaterThan(1));
      expect(data.bones.any((b) => b.parent.isNotEmpty), isTrue);
    });

    test('oracle premise: m2_rig has no runtime-evaluable constraints', () {
      // The "rest FK == setup FK" oracle below is only valid when
      // computeWorldTransforms takes its unconstrained FK branch. Assert the
      // premise so a future asset change fails HERE with a clear reason rather
      // than corrupting the oracle silently.
      expect(data.paths.where((p) => p.runtimeEvaluable), isEmpty);
      expect(data.ikConstraints.where((c) => c.runtimeEvaluable), isEmpty);
    });

    test('rest FK equals the unconstrained setup-pose FK for every bone', () {
      final memo = <int, Affine2>{};
      for (var i = 0; i < data.bones.length; i++) {
        final rest = restWorldFor(data, i, indexes, memo);
        final setup = setupWorlds[i];
        expect(rest.a, closeTo(setup.a, 1e-9), reason: '${data.bones[i].name}.a');
        expect(rest.b, closeTo(setup.b, 1e-9), reason: '${data.bones[i].name}.b');
        expect(rest.c, closeTo(setup.c, 1e-9), reason: '${data.bones[i].name}.c');
        expect(rest.d, closeTo(setup.d, 1e-9), reason: '${data.bones[i].name}.d');
        expect(rest.tx, closeTo(setup.tx, 1e-9),
            reason: '${data.bones[i].name}.tx');
        expect(rest.ty, closeTo(setup.ty, 1e-9),
            reason: '${data.bones[i].name}.ty');
      }
    });

    test('memo caches: repeated calls return the identical instance', () {
      final memo = <int, Affine2>{};
      final first = restWorldFor(data, data.bones.length - 1, indexes, memo);
      final second = restWorldFor(data, data.bones.length - 1, indexes, memo);
      expect(identical(first, second), isTrue);
      // Every ancestor of the queried bone is now memoized.
      expect(memo.containsKey(data.bones.length - 1), isTrue);
    });
  });
}
