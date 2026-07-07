part of 'transform.dart';

Map<String, int> _boneIndexByName(List<BoneData> bones) {
  final byName = <String, int>{};
  for (var i = 0; i < bones.length; i++) {
    final bone = bones[i];
    if (bone.parent.isNotEmpty && !byName.containsKey(bone.parent)) {
      throw FormatException(
          'bone parent must appear before child: ${bone.name}');
    }
    byName[bone.name] = i;
  }
  return byName;
}

List<Affine2> _newWorldList(int length) =>
    List<Affine2>.filled(length, _zeroAffine);

({Affine2 parentWorld, bool hasParent}) _resolveComputedParentWorld(
  SkeletonData data,
  int boneIndex,
  List<Affine2> worlds,
  List<bool> computed,
  Map<String, int> indexes,
  String errorPrefix,
  String constraintName,
) {
  final parent = data.bones[boneIndex].parent;
  if (parent.isEmpty) {
    return (parentWorld: _rootParent, hasParent: false);
  }
  final parentIndex = indexes[parent]!;
  if (!computed[parentIndex]) {
    throw FormatException(
        '$errorPrefix parent must be emitted before constraint: $constraintName');
  }
  return (parentWorld: worlds[parentIndex], hasParent: true);
}

bool _emitBoneWorldAt(
  int index,
  List<BoneData> locals,
  List<Affine2> worlds,
  Map<String, int> byName,
  ActiveSkinMembership activation, {
  List<bool>? computed,
}) {
  if (!activation.bones[index]) return false;
  final bone = locals[index];
  if (bone.parent.isEmpty) {
    worlds[index] = _worldForBone(_rootParent, bone, false);
  } else {
    final parentIndex = byName[bone.parent]!;
    if (!activation.bones[parentIndex]) return false;
    if (computed != null && !computed[parentIndex]) {
      throw FormatException(
          'bone parent must appear before child: ${bone.name}');
    }
    worlds[index] = _worldForBone(worlds[parentIndex], bone, true);
  }
  computed?[index] = true;
  return true;
}

/// Rest-pose world transform of a bone, FK-composed over the UNMUTATED rest
/// locals (`data.bones[*]`), independent of any animated/constrained pose
/// (transform.nim:357). IK segment lengths and rest joint origins are derived
/// from this rest FK (contract §6), while the chain still anchors at the live
/// pivot at evaluation time. [indexes] maps bone name -> index into
/// `data.bones`; [memo] caches results so shared ancestors are composed once.
Affine2 restWorldFor(
  SkeletonData data,
  int boneIndex,
  Map<String, int> indexes,
  Map<int, Affine2> memo,
) {
  final cached = memo[boneIndex];
  if (cached != null) return cached;
  final bone = data.bones[boneIndex];
  final hasParent = bone.parent.isNotEmpty;
  var parentWorld = _rootParent;
  if (hasParent) {
    parentWorld = restWorldFor(data, indexes[bone.parent]!, indexes, memo);
  }
  final world = _worldForBone(parentWorld, bone, hasParent);
  memo[boneIndex] = world;
  return world;
}

({List<Affine2> worlds, List<BoneData> locals}) _computeWorldsAndLocals(
  SkeletonData data,
  ActiveSkinMembership activation,
) {
  final hasRuntimeConstraints = data.paths.any((p) => p.runtimeEvaluable) ||
      data.ikConstraints.any((c) => c.runtimeEvaluable) ||
      data.transformConstraints.any((t) => t.runtimeEvaluable);
  final byName = _boneIndexByName(data.bones);
  final attachments = <String, PathAttachment>{
    for (final attachment in data.pathAttachments) attachment.name: attachment,
  };
  final cache = hasRuntimeConstraints
      ? _buildRuntimeConstraintUpdateCache(data, byName, activation)
      : <Object>[
          _BoneGroupEntry(List<int>.generate(data.bones.length, (i) => i)),
        ];
  final result = _newWorldList(data.bones.length);
  final locals = data.bones.map((bone) => bone).toList();
  final computed = List<bool>.filled(data.bones.length, false);

  for (final entry in cache) {
    if (entry is _BoneGroupEntry) {
      for (final index in entry.bones) {
        _emitBoneWorldAt(index, locals, result, byName, activation,
            computed: computed);
      }
    } else if (entry is _ConstraintEntry) {
      if (!entry.active) continue;
      switch (entry.kind) {
        case _ConstraintKind.path:
          _applyRuntimePathConstraint(
            data,
            data.paths[entry.sourceIndex],
            locals,
            result,
            computed,
            byName,
            attachments,
          );
        case _ConstraintKind.ik:
          _applyRuntimeIk(
            data,
            data.ikConstraints[entry.sourceIndex],
            locals,
            result,
            computed,
            byName,
          );
        case _ConstraintKind.transform:
          _applyRuntimeTransformConstraint(
            data,
            data.transformConstraints[entry.sourceIndex],
            locals,
            result,
            computed,
            byName,
          );
        case _ConstraintKind.physics:
          // Physics is a separate stateful stage (advancePhysics); it is never
          // emitted into this cache, so this branch is unreachable.
          throw StateError(
              'physics constraints are evaluated in advancePhysics, '
              'not the world-transform pass');
      }
    }
  }
  return (worlds: result, locals: locals);
}

/// Compute the setup-pose world affine transform for every bone.
///
/// Returns one [Affine2] per bone, in the same order as [data.bones].
List<Affine2> computeWorldTransforms(
  SkeletonData data, {
  String activeSkin = 'default',
}) {
  return _computeWorldsAndLocals(data, data.activeSkinMembership(activeSkin))
      .worlds;
}
