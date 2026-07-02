// Transform-constraint parity tests for the Dart runtime, mirroring the Nim
// reference (runtime-nim tests/test_smoke.nim transform-constraint cases) and
// the IK precedent tests. Covers the solver, the unified dispatch order
// (ckIk < ckTransform < ckPath), non-vacuous evaluation under identity and
// non-identity parents, and applyPose preservation (the bony-1c5 bug class).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:bony/bony.dart';

BoneData _bone(
  String name, {
  String parent = '',
  double x = 0,
  double y = 0,
  double rotation = 0,
  double scaleX = 1,
  double scaleY = 1,
  double shearY = 0,
}) =>
    BoneData(
      name: name,
      parent: parent,
      x: x,
      y: y,
      rotation: rotation,
      scaleX: scaleX,
      scaleY: scaleY,
      shearX: 0,
      shearY: shearY,
      inheritRotation: true,
      inheritScale: true,
      inheritReflection: true,
      transformMode: 'normal',
    );

TransformConstraintData _tc(
  String name,
  String bone,
  String target, {
  int order = 0,
  double? translateMix,
  double? rotateMix,
  double? scaleMix,
  double? shearMix,
}) =>
    TransformConstraintData(
      name: name,
      bone: bone,
      target: target,
      order: order,
      translateMix: translateMix,
      rotateMix: rotateMix,
      scaleMix: scaleMix,
      shearMix: shearMix,
    );

void _expectClose(double actual, double expected, String label,
    {double tol = 1e-6}) {
  expect((actual - expected).abs(), lessThanOrEqualTo(tol),
      reason: '$label: actual=$actual expected=$expected');
}

// Decompose an Affine2 the way affineToTransformPose does, for readable asserts.
({double rot, double sx, double sy, double shearY}) _decompose(Affine2 w) {
  final det = w.a * w.d - w.b * w.c;
  final sx = math.sqrt(w.a * w.a + w.b * w.b) * (det < 0 ? -1 : 1);
  final rot = math.atan2(w.b, w.a) * 180.0 / math.pi;
  final yAngle = math.atan2(w.d, w.c) * 180.0 / math.pi;
  final sy = math.sqrt(w.c * w.c + w.d * w.d);
  var shy = yAngle - rot - 90.0;
  while (shy < -180.0) {
    shy += 360.0;
  }
  while (shy > 180.0) {
    shy -= 360.0;
  }
  return (rot: rot, sx: sx, sy: sy, shearY: shy);
}

void main() {
  group('transform constraint solver', () {
    final constrained = const Affine2(
        a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 40.0, ty: 0.0);
    // target: rotation 45, scaleX 2, shearY 30, translation (80, 60).
    final target = transformPoseToAffine(const TransformConstraintPose(
      x: 80.0,
      y: 60.0,
      rotation: 45.0,
      scaleX: 2.0,
      scaleY: 1.0,
      shearX: 0.0,
      shearY: 30.0,
    ));

    test('mix 0 on every channel is the identity (keeps the constrained pose)',
        () {
      final out = applyTransformConstraint(constrained, target,
          const TransformConstraintMix(
              translate: 0, rotate: 0, scale: 0, shear: 0));
      _expectClose(out.tx, 40.0, 'tx');
      _expectClose(out.ty, 0.0, 'ty');
      final d = _decompose(out);
      _expectClose(d.rot, 0.0, 'rot', tol: 1e-4);
      _expectClose(d.sx, 1.0, 'scaleX', tol: 1e-4);
      _expectClose(d.shearY, 0.0, 'shearY', tol: 1e-4);
    });

    test('mix 1 on every channel snaps fully to the target', () {
      final out = applyTransformConstraint(constrained, target,
          const TransformConstraintMix());
      _expectClose(out.a, target.a, 'a', tol: 1e-6);
      _expectClose(out.b, target.b, 'b', tol: 1e-6);
      _expectClose(out.c, target.c, 'c', tol: 1e-6);
      _expectClose(out.d, target.d, 'd', tol: 1e-6);
      _expectClose(out.tx, target.tx, 'tx', tol: 1e-6);
      _expectClose(out.ty, target.ty, 'ty', tol: 1e-6);
    });

    test('mix 0.5 blends every channel to the midpoint', () {
      final out = applyTransformConstraint(constrained, target,
          const TransformConstraintMix(
              translate: 0.5, rotate: 0.5, scale: 0.5, shear: 0.5));
      _expectClose(out.tx, 60.0, 'tx', tol: 1e-4);
      _expectClose(out.ty, 30.0, 'ty', tol: 1e-4);
      final d = _decompose(out);
      _expectClose(d.rot, 22.5, 'rot', tol: 1e-4);
      _expectClose(d.sx, 1.5, 'scaleX', tol: 1e-4);
      _expectClose(d.shearY, 15.0, 'shearY', tol: 1e-4);
    });

    test('rejects an out-of-range mix', () {
      expect(
          () => applyTransformConstraint(constrained, target,
              const TransformConstraintMix(scale: 1.5)),
          throwsFormatException);
    });

    test('rejects a non-finite target affine', () {
      final bad = Affine2(
          a: double.nan, b: 0, c: 0, d: 1, tx: 0, ty: 0);
      expect(() => affineToTransformPose(bad), throwsFormatException);
    });
  });

  group('transform constraint dispatch order', () {
    SkeletonData rig() => SkeletonData(
          header: const SkeletonHeader(name: 'ord', version: '1'),
          bones: [
            _bone('root'),
            _bone('ikBone', parent: 'root'),
            _bone('ikGoal', parent: 'root'),
            _bone('tcBone', parent: 'root'),
            _bone('tcGoal', parent: 'root'),
            _bone('pathBone', parent: 'root'),
            _bone('pathTarget', parent: 'root'),
          ],
          slots: const [],
          regions: const [],
          paths: [
            const PathConstraintData(
                name: 'p',
                bone: 'pathBone',
                target: 'pathTarget',
                path: 'curve',
                order: 0,
                translateMix: 0.5),
          ],
          pathAttachments: const [],
          ikConstraints: [
            const IkConstraintData(
                name: 'ik', bones: ['ikBone'], target: 'ikGoal', order: 0),
          ],
          transformConstraints: [
            _tc('tc', 'tcBone', 'tcGoal', translateMix: 0.5),
          ],
        );

    test('at equal order, dispatch is ckIk < ckTransform < ckPath', () {
      final order = debugRuntimeConstraintDispatchOrder(rig());
      expect(order.map((e) => e.kind).toList(), ['ik', 'transform', 'path'],
          reason: 'constraintKindRank tie-break: ik(0) < transform(1) < path(2)');
    });
  });

  group('transform constraint evaluation', () {
    test('transform-only rig fires the runtime pass (non-vacuous)', () {
      final data = SkeletonData(
        header: const SkeletonHeader(name: 't', version: '1'),
        bones: [
          _bone('root'),
          _bone('constrained', parent: 'root', x: 5),
          _bone('goal', parent: 'root', x: 11, y: 4),
        ],
        slots: const [],
        regions: const [],
        paths: const [],
        pathAttachments: const [],
        transformConstraints: [
          _tc('tc', 'constrained', 'goal', translateMix: 0.5),
        ],
      );
      final worlds = computeWorldTransforms(data);
      // constrained x=5 blended halfway to goal x=11 -> 8; y 0 -> 2.
      _expectClose(worlds[1].tx, 8.0, 'tx');
      _expectClose(worlds[1].ty, 2.0, 'ty');
    });

    test('mix=1 snaps constrained world to target under a non-identity parent',
        () {
      final data = SkeletonData(
        header: const SkeletonHeader(name: 't', version: '1'),
        bones: [
          _bone('root'),
          _bone('mid',
              parent: 'root', x: 3, y: -2, rotation: 40, scaleX: 1.7, scaleY: 0.8),
          _bone('constrained', parent: 'mid', x: 4, y: 1, rotation: 15),
          _bone('goal', parent: 'root', x: 10, y: 10, rotation: 30, scaleX: 1.3),
        ],
        slots: const [],
        regions: const [],
        paths: const [],
        pathAttachments: const [],
        transformConstraints: [
          _tc('tc', 'constrained', 'goal',
              translateMix: 1, rotateMix: 1, scaleMix: 1, shearMix: 1),
        ],
      );
      final worlds = computeWorldTransforms(data);
      // bone order: root=0, mid=1, constrained=2, goal=3.
      _expectClose(worlds[2].a, worlds[3].a, 'a', tol: 1e-4);
      _expectClose(worlds[2].b, worlds[3].b, 'b', tol: 1e-4);
      _expectClose(worlds[2].c, worlds[3].c, 'c', tol: 1e-4);
      _expectClose(worlds[2].d, worlds[3].d, 'd', tol: 1e-4);
      _expectClose(worlds[2].tx, worlds[3].tx, 'tx', tol: 1e-4);
      _expectClose(worlds[2].ty, worlds[3].ty, 'ty', tol: 1e-4);
    });
  });

  test('BNB-decoded m5_transform_rig matches the golden within 1e-4', () {
    // Exercises the .bnb transformConstraint decode branch (the JSON path is
    // covered by the m10 M5-Transform group). Both loaders must agree with the
    // committed golden.
    final bytes =
        File('../conformance/assets/bnb/m5_transform_rig.bnb').readAsBytesSync();
    final data = loadBonyBnb(Uint8List.fromList(bytes));
    expect(data.transformConstraints.length, 1);
    final worlds = computeWorldTransforms(data);
    final golden = jsonDecode(
            File('../conformance/goldens/m5_transform_rig_t0.json')
                .readAsStringSync()) as Map<String, dynamic>;
    final gByName = {
      for (final b in (golden['bones'] as List).cast<Map<String, dynamic>>())
        b['name'] as String: b['world'] as Map<String, dynamic>
    };
    for (var i = 0; i < data.bones.length; i++) {
      final w = worlds[i];
      final g = gByName[data.bones[i].name]!;
      _expectClose(w.a, (g['a'] as num).toDouble(), 'a', tol: 1e-4);
      _expectClose(w.b, (g['b'] as num).toDouble(), 'b', tol: 1e-4);
      _expectClose(w.c, (g['c'] as num).toDouble(), 'c', tol: 1e-4);
      _expectClose(w.d, (g['d'] as num).toDouble(), 'd', tol: 1e-4);
      _expectClose(w.tx, (g['tx'] as num).toDouble(), 'tx', tol: 1e-4);
      _expectClose(w.ty, (g['ty'] as num).toDouble(), 'ty', tol: 1e-4);
    }
  });

  test('applyPose preserves transformConstraints (bony-1c5 bug class)', () {
    final data = SkeletonData(
      header: const SkeletonHeader(name: 't', version: '1'),
      bones: [
        _bone('root'),
        _bone('constrained', parent: 'root', x: 5),
        _bone('goal', parent: 'root', x: 11, y: 4),
      ],
      slots: const [],
      regions: const [],
      paths: const [],
      pathAttachments: const [],
      transformConstraints: [
        _tc('tc', 'constrained', 'goal', translateMix: 0.5),
      ],
    );
    final posed = applyPose(data, const MixedPose(scalars: []));
    expect(posed.transformConstraints.length, 1,
        reason: 'applyPose must not drop transformConstraints');
    expect(posed.transformConstraints.first.name, 'tc');
    // And the constraint still evaluates on the posed skeleton.
    final worlds = computeWorldTransforms(posed);
    _expectClose(worlds[1].tx, 8.0, 'tx');
  });
}
