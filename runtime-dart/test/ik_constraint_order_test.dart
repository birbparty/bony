// Pins the canonical runtime-constraint dispatch order for the path+ik subset,
// which the committed goldens do NOT exercise (no golden rig mixes both kinds).
// The load-bearing rule (Nim compareConstraintEntries / constraintKindRank):
// order value, then kind rank where ckIk (0) precedes ckPath (2) on a tie, then
// source index. A dual-loop or a dropped kind-rank term would mis-order a tie
// and silently break a mixed rig — this test guards exactly that line.

import 'package:test/test.dart';
import 'package:bony/bony.dart';

BoneData _bone(String name, {String parent = ''}) => BoneData(
      name: name,
      parent: parent,
      x: 0,
      y: 0,
      rotation: 0,
      scaleX: 1,
      scaleY: 1,
      shearX: 0,
      shearY: 0,
      inheritRotation: true,
      inheritScale: true,
      inheritReflection: true,
      transformMode: 'normal',
    );

// A path constraint is runtimeEvaluable when any of position/translateMix/
// rotateMix is set; give it a position so it participates in the cache.
PathConstraintData _path(String name, String bone, String target, int order) =>
    PathConstraintData(
      name: name,
      bone: bone,
      target: target,
      path: 'p',
      order: order,
      position: 0.0,
    );

IkConstraintData _ik(String name, List<String> bones, String target, int order) =>
    IkConstraintData(name: name, bones: bones, target: target, order: order);

SkeletonData _rig({
  required List<PathConstraintData> paths,
  required List<IkConstraintData> iks,
}) =>
    SkeletonData(
      header: const SkeletonHeader(name: 'order-rig', version: '1'),
      bones: [
        _bone('root'),
        _bone('ik_bone', parent: 'root'),
        _bone('ik_target', parent: 'root'),
        _bone('path_bone', parent: 'root'),
        _bone('path_target', parent: 'root'),
      ],
      slots: const [],
      regions: const [],
      paths: paths,
      pathAttachments: const [],
      ikConstraints: iks,
    );

void main() {
  group('runtime constraint dispatch order', () {
    test('at equal order, IK dispatches before path', () {
      final data = _rig(
        paths: [_path('pc', 'path_bone', 'path_target', 0)],
        iks: [_ik('ic', ['ik_bone'], 'ik_target', 0)],
      );
      final order = debugRuntimeConstraintDispatchOrder(data);
      expect(order.map((e) => e.kind).toList(), ['ik', 'path'],
          reason: 'ckIk must precede ckPath at the same order value');
    });

    test('order value dominates the kind rank', () {
      // Path at order 0, IK at order 1: order wins, so path runs first even
      // though ik has the lower kind rank.
      final data = _rig(
        paths: [_path('pc', 'path_bone', 'path_target', 0)],
        iks: [_ik('ic', ['ik_bone'], 'ik_target', 1)],
      );
      final order = debugRuntimeConstraintDispatchOrder(data);
      expect(order.map((e) => e.kind).toList(), ['path', 'ik']);
    });

    test('same-kind ties break by source index', () {
      final data = _rig(
        paths: [
          _path('pc0', 'path_bone', 'path_target', 0),
          _path('pc1', 'path_target', 'path_bone', 0),
        ],
        iks: const [],
      );
      final order = debugRuntimeConstraintDispatchOrder(data);
      expect(order.map((e) => e.sourceIndex).toList(), [0, 1]);
    });

    test('IK-only rig dispatches its single IK constraint', () {
      final data = _rig(
        paths: const [],
        iks: [_ik('ic', ['ik_bone'], 'ik_target', 0)],
      );
      final order = debugRuntimeConstraintDispatchOrder(data);
      expect(order, hasLength(1));
      expect(order.single.kind, 'ik');
    });
  });
}
