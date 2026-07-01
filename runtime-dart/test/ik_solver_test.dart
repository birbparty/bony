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

// Every FABRIK-placed segment is constructed at exactly its stored length, so
// with mix = 1 the solved chain must preserve each bone length. This is the
// strongest non-circular check on the reaching loop: it holds for the correct
// solver regardless of the specific converged pose.
void _expectSegmentLengths(
    List<IkPoint> points, List<double> lengths, String label) {
  for (var i = 0; i < lengths.length; i++) {
    final dx = points[i + 1].x - points[i].x;
    final dy = points[i + 1].y - points[i].y;
    final len = math.sqrt(dx * dx + dy * dy);
    expect(len, closeTo(lengths[i], 1e-6), reason: '$label.segment[$i]');
  }
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

    test('zero-length bone hits the denominator<=epsilon guard (child = 0)', () {
      // l1 = 0 makes denominator = 2*l1*l2 = 0 <= epsilon, so the law-of-cosines
      // is skipped and solvedChild = 0. With target (1,0): k1 = 0 + 1*cos0 = 1,
      // k2 = 1*sin0 = 0, solvedParent = atan2(0,1) - atan2(0,1) = 0, so the
      // single non-zero bone points straight at the target: end = (1,0).
      final r = solveTwoBoneIk(
          ikPoint(0, 0), 0.0, 1.0, 0.0, 0.0, ikPoint(1, 0), bendSign: -1.0);
      expect(r.childRotation, closeTo(0.0, 1e-9));
      expect(r.parentRotation, closeTo(0.0, 1e-9));
      _expectPoint(r.endPoint, 1.0, 0.0, 'twoBone.zeroLen.end');
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

    test('non-degenerate reachable target exercises the FABRIK reaching loop',
        () {
      // Initial chain lies along +x: (0,0),(1,0),(2,0). Target (1, 0.5) is
      // strictly reachable (rootToTarget = sqrt(1.25) ~ 1.118 <= totalLength 2)
      // and is NOT satisfiable by the initial pose, so the backward/forward
      // reaching passes must actually iterate (this is the branch that all the
      // straight-line and degenerate tests skip). We assert the two invariants
      // that a correct FABRIK solve must satisfy without pinning the exact
      // converged interior joint: the end effector reaches the target, and every
      // bone length is preserved.
      final lengths = <double>[1.0, 1.0];
      final r = solveChainIk(
        <IkPoint>[ikPoint(0, 0), ikPoint(1, 0), ikPoint(2, 0)],
        lengths,
        ikPoint(1, 0.5),
      );
      _expectPoint(r.points.first, 0.0, 0.0, 'chain.fabrik.root', tol: 1e-9);
      _expectPoint(r.points.last, 1.0, 0.5, 'chain.fabrik.end',
          tol: fabrikTolerance);
      _expectSegmentLengths(r.points, lengths, 'chain.fabrik');
    });

    test('degenerate/collinear seed lands the interior joint on the analytic '
        'solution and reaches the target', () {
      // All points coincident at the origin: segments have length 1 but zero
      // separation, triggering the bend-plane seeding branch. Target (1,0) is
      // reachable (rootToTarget 1 <= totalLength 2). The seed is deterministic:
      //   ux=1, uy=0; bend = sqrt(4-1)/2 = sqrt(3)/2; at t=0.5 offset=bend, so
      //   interior = (0 + 1*0.5 - 0, 0 + 0 + 1*bend) = (0.5, sqrt(3)/2).
      // That point is already the exact 2-bone solution, so FABRIK holds it.
      // Asserting the interior guards the seeding math itself (root+end alone
      // are FABRIK-guaranteed regardless of a seeding bug).
      final lengths = <double>[1.0, 1.0];
      final r = solveChainIk(
        <IkPoint>[ikPoint(0, 0), ikPoint(0, 0), ikPoint(0, 0)],
        lengths,
        ikPoint(1, 0),
      );
      _expectPoint(r.points.first, 0.0, 0.0, 'chain.degen.root', tol: 1e-9);
      _expectPoint(r.points[1], 0.5, math.sqrt(3) / 2.0, 'chain.degen.mid');
      _expectPoint(r.points.last, 1.0, 0.0, 'chain.degen.end',
          tol: fabrikTolerance);
      _expectSegmentLengths(r.points, lengths, 'chain.degen');
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
