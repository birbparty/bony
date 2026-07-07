part of 'transform.dart';

class _BoneGroupEntry {
  const _BoneGroupEntry(this.bones);
  final List<int> bones;
}

enum _ConstraintKind { ik, transform, path, physics }

// Canonical kind rank for tie-breaking constraints at equal `order` (Nim
// constraintKindRank, model.nim): ckIk=0 < ckTransform=1 < ckPath=2 <
// ckPhysics=3. Physics ranks last but is NOT dispatched in the world-transform
// pass — it runs in the separate stateful stage ([advancePhysics]); the rank is
// carried only for parity with the Nim ordering.
int _constraintKindRank(_ConstraintKind kind) => switch (kind) {
      _ConstraintKind.ik => 0,
      _ConstraintKind.transform => 1,
      _ConstraintKind.path => 2,
      _ConstraintKind.physics => 3,
    };

class _ConstraintEntry {
  const _ConstraintEntry(this.kind, this.sourceIndex, this.active);
  final _ConstraintKind kind;
  final int sourceIndex;
  final bool active;
}

List<Object> _buildRuntimeConstraintUpdateCache(
  SkeletonData data,
  Map<String, int> byName,
  ActiveSkinMembership activation,
) {
  final parents = List<int>.filled(data.bones.length, -1);
  final seen = <String, int>{};
  for (var index = 0; index < data.bones.length; index++) {
    final bone = data.bones[index];
    if (bone.parent.isNotEmpty) {
      final parentIndex = seen[bone.parent];
      if (parentIndex == null) {
        throw FormatException(
            'bone parent must appear before child: ${bone.name}');
      }
      parents[index] = parentIndex;
    }
    seen[bone.name] = index;
  }

  // Collect BOTH path and ik constraints into ONE ordered list (Nim
  // buildRuntimeConstraintUpdateCache, update_cache.nim:169). Sorting them
  // together by the canonical comparator is load-bearing: for the path+ik
  // subset both share stage rank 0, so sort by `order`, then kind rank
  // (ckIk before ckPath) on a tie, then sourceIndex. A dual-loop over paths
  // then IK would get the tie order wrong (an IK and a path both at order 0
  // must run IK first) and break the golden. Non-runtime constraints still
  // participate in ordering/write-blockers (reads empty; dispatch no-ops).
  // Nim's per-entry `active` flag is intentionally not carried: the dispatched
  // _applyRuntime* functions each re-check `runtimeEvaluable`, so the flag would
  // be redundant.
  final descriptors = <({
    _ConstraintKind kind,
    int order,
    int sourceIndex,
    List<String> writes,
    List<String> reads,
    bool active,
  })>[];
  for (var index = 0; index < data.paths.length; index++) {
    final path = data.paths[index];
    descriptors.add((
      kind: _ConstraintKind.path,
      order: path.order,
      sourceIndex: index,
      writes: <String>[path.bone],
      reads: path.runtimeEvaluable ? <String>[path.target] : const <String>[],
      active: activation.pathConstraints[index],
    ));
  }
  for (var index = 0; index < data.ikConstraints.length; index++) {
    final ik = data.ikConstraints[index];
    descriptors.add((
      kind: _ConstraintKind.ik,
      order: ik.order,
      sourceIndex: index,
      // An IK constraint WRITES its whole bone chain, not a single bone.
      writes: ik.bones,
      reads: ik.runtimeEvaluable ? <String>[ik.target] : const <String>[],
      active: activation.ikConstraints[index],
    ));
  }
  for (var index = 0; index < data.transformConstraints.length; index++) {
    final tc = data.transformConstraints[index];
    descriptors.add((
      kind: _ConstraintKind.transform,
      order: tc.order,
      sourceIndex: index,
      writes: <String>[tc.bone],
      reads: tc.runtimeEvaluable ? <String>[tc.target] : const <String>[],
      active: activation.transformConstraints[index],
    ));
  }
  descriptors.sort((a, b) {
    final byOrder = a.order.compareTo(b.order);
    if (byOrder != 0) return byOrder;
    final byKind =
        _constraintKindRank(a.kind).compareTo(_constraintKindRank(b.kind));
    if (byKind != 0) return byKind;
    return a.sourceIndex.compareTo(b.sourceIndex);
  });

  final writeBlockers = List<int>.filled(data.bones.length, -1);
  for (var itemIndex = 0; itemIndex < descriptors.length; itemIndex++) {
    for (final boneName in descriptors[itemIndex].writes) {
      final boneIndex = byName[boneName];
      if (boneIndex == null) {
        throw FormatException('unknown constraint write bone: $boneName');
      }
      writeBlockers[boneIndex] = math.max(writeBlockers[boneIndex], itemIndex);
    }
  }

  final releaseAfter = List<int>.filled(data.bones.length, -1);
  for (var index = 0; index < data.bones.length; index++) {
    releaseAfter[index] = writeBlockers[index];
    if (parents[index] >= 0) {
      releaseAfter[index] =
          math.max(releaseAfter[index], releaseAfter[parents[index]]);
    }
  }

  final result = <Object>[];
  final emitted = List<bool>.filled(data.bones.length, false);
  void emitBoneGroup(List<int> bones) {
    if (bones.isNotEmpty) result.add(_BoneGroupEntry(bones));
  }

  for (var itemIndex = 0; itemIndex < descriptors.length; itemIndex++) {
    final descriptor = descriptors[itemIndex];
    // Emit read dependencies: each read bone's unemitted ancestor lineage is
    // emitted before the constraint. Nim lists only the target as a read; the
    // chain root's EXTERNAL parent is deliberately NOT walked here — it is
    // enforced at runtime inside _applyRuntimeIk (ordering violation), not by
    // extra cache lineage.
    final readGroup = <int>[];
    for (final readName in descriptor.reads) {
      final readIndex = byName[readName];
      if (readIndex == null) {
        throw FormatException('unknown constraint read bone: $readName');
      }
      final lineage = <int>[];
      var cursor = readIndex;
      while (cursor >= 0) {
        lineage.add(cursor);
        cursor = parents[cursor];
      }
      for (final index in lineage.reversed) {
        if (index != readIndex && writeBlockers[index] >= itemIndex) {
          throw FormatException(
            'constraint read bone ancestor cannot be emitted before later write: ${data.bones[readIndex].name}',
          );
        }
        if (!emitted[index]) {
          readGroup.add(index);
          emitted[index] = true;
        }
      }
    }
    emitBoneGroup(readGroup);

    final group = <int>[];
    for (var index = 0; index < data.bones.length; index++) {
      if (!emitted[index] && releaseAfter[index] < itemIndex) {
        group.add(index);
        emitted[index] = true;
      }
    }
    emitBoneGroup(group);
    result.add(_ConstraintEntry(
        descriptor.kind, descriptor.sourceIndex, descriptor.active));
  }

  final finalGroup = <int>[];
  for (var index = 0; index < data.bones.length; index++) {
    if (!emitted[index]) finalGroup.add(index);
  }
  emitBoneGroup(finalGroup);
  return result;
}

/// Testing hook: the kind ('ik'/'path') and per-kind source index of each
/// runtime constraint, in the exact order [computeWorldTransforms] dispatches
/// it. Lets tests pin the canonical ordering — notably that ckIk precedes
/// ckPath at equal `order` — which the committed goldens do not exercise (no
/// golden rig mixes both constraint kinds).
List<({String kind, int sourceIndex})> debugRuntimeConstraintDispatchOrder(
    SkeletonData data) {
  final byName = _boneIndexByName(data.bones);
  final activation = data.activeSkinMembership();
  return [
    for (final entry
        in _buildRuntimeConstraintUpdateCache(data, byName, activation))
      if (entry is _ConstraintEntry)
        (
          kind: switch (entry.kind) {
            _ConstraintKind.ik => 'ik',
            _ConstraintKind.transform => 'transform',
            _ConstraintKind.path => 'path',
            // Physics never enters this cache (separate stage); unreachable.
            _ConstraintKind.physics => 'physics',
          },
          sourceIndex: entry.sourceIndex,
        ),
  ];
}
