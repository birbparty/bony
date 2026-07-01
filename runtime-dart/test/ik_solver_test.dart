// Direct unit tests for the ported Dart IK solvers (runtime-dart/lib/src/ik.dart),
// characterizing the port of runtime-nim/src/bony/constraints/ik.nim BEFORE the
// evaluation-wiring bead. Expected values are hand-computed from the solver
// geometry (law-of-cosines / FABRIK), NOT captured from the Dart output and NOT
// derived by importing or shelling out to Nim — so a port bug surfaces here at
// the unit level rather than only as a conformance-golden mismatch.
//
// Points are built with the quantizing ikPoint(x, y) solver-input constructor
// (the test_smoke.nim parallel). All test coordinates are exactly representable
// in float32, so quantization is a no-op on the inputs.

import 'dart:math' as math;

import 'package:test/test.dart';
import 'package:bony/bony.dart';

void _expectPoint(IkPoint actual, double x, double y, String label,
    {double tol = 1e-6}) {
  expect(actual.x, closeTo(x, tol), reason: '$label.x');
  expect(actual.y, closeTo(y, tol), reason: '$label.y');
}

void main() {
  group('solveOneBoneIk', () {
    test('rotates to face a target straight up (target => 90deg)', () {
      // origin (0,0), length 5, currentRotation 0, target (0,10), mix 1.
      // targetRotation = atan2(10, 0) = 90deg; rotation = lerp(0, 90, 1) = 90.
      // endPoint = (0 + cos(90)*5, 0 + sin(90)*5) = (0, 5).
      final r = solveOneBoneIk(ikPoint(0, 0), 5.0, 0.0, ikPoint(0, 10));
      expect(r.rotation, closeTo(90.0, 1e-9));
      _expectPoint(r.endPoint, 0.0, 5.0, 'oneBone.end');
    });

    test('mix = 0 is identity on rotation (keeps current)', () {
      // lerp(current, target, 0) = current, regardless of target.
      final r =
          solveOneBoneIk(ikPoint(0, 0), 5.0, 33.0, ikPoint(0, 10), mix: 0.0);
      expect(r.rotation, closeTo(33.0, 1e-12));
      // Endpoint uses the (unchanged) current rotation of 33deg.
      _expectPoint(r.endPoint, 5.0 * math.cos(33.0 * math.pi / 180.0),
          5.0 * math.sin(33.0 * math.pi / 180.0), 'oneBone.mix0.end');
    });

    test('rejects non-finite and out-of-range inputs', () {
      expect(() => solveOneBoneIk(ikPoint(0, 0), -1.0, 0.0, ikPoint(1, 0)),
          throwsFormatException);
      expect(
          () => solveOneBoneIk(ikPoint(0, 0), 1.0, 0.0, ikPoint(1, 0), mix: 1.5),
          throwsFormatException);
    });
  });

  group('solveTwoBoneIk', () {
    // Both cases: origin (0,0), l1 = l2 = 1, current parent/child = 0,
    // target (1,1). d^2 = 2, so cos(child) = (2 - 1 - 1)/2 = 0 => |child| = 90deg.
    test('bendSign = -1 bends the elbow one way (reaches target)', () {
      // solvedChild = acos(0)*(-1) = -90. k1 = 1 + cos(-90) = 1, k2 = sin(-90) = -1.
      // solvedParent = atan2(1,1) - atan2(-1,1) = 45 - (-45) = 90.
      // mid = (cos90, sin90) = (0,1); childAbs = 90 + (-90) = 0; end = (0+cos0, 1+sin0) = (1,1).
      final r = solveTwoBoneIk(
          ikPoint(0, 0), 1.0, 1.0, 0.0, 0.0, ikPoint(1, 1), bendSign: -1.0);
      expect(r.parentRotation, closeTo(90.0, 1e-6));
      expect(r.childRotation, closeTo(-90.0, 1e-6));
      _expectPoint(r.midPoint, 0.0, 1.0, 'twoBone.neg.mid');
      _expectPoint(r.endPoint, 1.0, 1.0, 'twoBone.neg.end');
    });

    test('bendSign = +1 mirrors the elbow (also reaches target)', () {
      // solvedChild = acos(0)*(+1) = +90. k1 = 1 + cos(90) = 1, k2 = sin(90) = 1.
      // solvedParent = atan2(1,1) - atan2(1,1) = 0.
      // mid = (cos0, sin0) = (1,0); childAbs = 0 + 90 = 90; end = (1+cos90, 0+sin90) = (1,1).
      final r = solveTwoBoneIk(
          ikPoint(0, 0), 1.0, 1.0, 0.0, 0.0, ikPoint(1, 1), bendSign: 1.0);
      expect(r.parentRotation, closeTo(0.0, 1e-6));
      expect(r.childRotation, closeTo(90.0, 1e-6));
      _expectPoint(r.midPoint, 1.0, 0.0, 'twoBone.pos.mid');
      _expectPoint(r.endPoint, 1.0, 1.0, 'twoBone.pos.end');
    });

    test('childRotation is RELATIVE to parent (absolute = parent + child)', () {
      // Both bendSign cases above reach the same endpoint (1,1) but via opposite
      // elbows; verify the documented relative-child convention numerically:
      // neg: parent 90 + child -90 = 0 absolute for the child segment.
      final r = solveTwoBoneIk(
          ikPoint(0, 0), 1.0, 1.0, 0.0, 0.0, ikPoint(1, 1), bendSign: -1.0);
      final childAbs = r.parentRotation + r.childRotation;
      expect(childAbs, closeTo(0.0, 1e-6));
    });
  });

  group('solveChainIk', () {
    test('root past total length => straight line toward target', () {
      // points (0,0),(1,0),(2,0); lengths 1,1; target (0,10); rootToTarget 10 > 2.
      // angle = atan2(10,0) = 90; points walk straight up: (0,1),(0,2).
      // rotations (post-blend, mix 1) = [90, 90].
      final r = solveChainIk(
        <IkPoint>[ikPoint(0, 0), ikPoint(1, 0), ikPoint(2, 0)],
        <double>[1.0, 1.0],
        ikPoint(0, 10),
      );
      _expectPoint(r.points[0], 0.0, 0.0, 'chain.far.p0');
      _expectPoint(r.points[1], 0.0, 1.0, 'chain.far.p1');
      _expectPoint(r.points[2], 0.0, 2.0, 'chain.far.p2');
      expect(r.rotations, hasLength(2));
      expect(r.rotations[0], closeTo(90.0, 1e-6));
      expect(r.rotations[1], closeTo(90.0, 1e-6));
    });

    test('mix = 0.5 blends halfway between original and solved pose', () {
      // Solved (straight-line up) = (0,0),(0,1),(0,2); originals = (0,0),(1,0),(2,0).
      // Blend at 0.5: p1 = (0.5,0.5), p2 = (1,1). Rotations are taken AFTER the
      // blend: (0,0)->(0.5,0.5) = 45deg; (0.5,0.5)->(1,1) = 45deg.
      final r = solveChainIk(
        <IkPoint>[ikPoint(0, 0), ikPoint(1, 0), ikPoint(2, 0)],
        <double>[1.0, 1.0],
        ikPoint(0, 10),
        mix: 0.5,
      );
      _expectPoint(r.points[0], 0.0, 0.0, 'chain.mix.p0');
      _expectPoint(r.points[1], 0.5, 0.5, 'chain.mix.p1');
      _expectPoint(r.points[2], 1.0, 1.0, 'chain.mix.p2');
      expect(r.rotations[0], closeTo(45.0, 1e-6));
      expect(r.rotations[1], closeTo(45.0, 1e-6));
    });

    test('mix = 0 is identity (result equals the original points)', () {
      final original = <IkPoint>[ikPoint(0, 0), ikPoint(1, 0), ikPoint(2, 0)];
      final r = solveChainIk(original, <double>[1.0, 1.0], ikPoint(0, 10),
          mix: 0.0);
      for (var i = 0; i < original.length; i++) {
        _expectPoint(r.points[i], original[i].x, original[i].y, 'chain.id.p$i',
            tol: 1e-9);
      }
    });

    test('degenerate/collinear seed still converges to a reachable target', () {
      // All points coincident at the origin: segments have length 1 but zero
      // separation, triggering the bend-plane seeding branch. Target (1,0) is
      // reachable (rootToTarget 1 <= totalLength 2), so FABRIK must drive the
      // end effector onto the target within fabrikTolerance.
      final r = solveChainIk(
        <IkPoint>[ikPoint(0, 0), ikPoint(0, 0), ikPoint(0, 0)],
        <double>[1.0, 1.0],
        ikPoint(1, 0),
      );
      _expectPoint(r.points.first, 0.0, 0.0, 'chain.degen.root', tol: 1e-9);
      _expectPoint(r.points.last, 1.0, 0.0, 'chain.degen.end',
          tol: fabrikTolerance);
      expect(r.rotations, hasLength(2));
    });

    test('rejects malformed chains', () {
      expect(() => solveChainIk(<IkPoint>[ikPoint(0, 0)], <double>[], ikPoint(1, 0)),
          throwsFormatException);
      expect(
          () => solveChainIk(<IkPoint>[ikPoint(0, 0), ikPoint(1, 0)],
              <double>[1.0, 1.0], ikPoint(1, 0)),
          throwsFormatException);
      expect(
          () => solveChainIk(<IkPoint>[ikPoint(0, 0), ikPoint(1, 0)],
              <double>[-1.0], ikPoint(1, 0)),
          throwsFormatException);
    });
  });
}
