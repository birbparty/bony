part of 'transform.dart';

void _applyRuntimePathConstraint(
  SkeletonData data,
  PathConstraintData path,
  List<BoneData> locals,
  List<Affine2> worlds,
  List<bool> computed,
  Map<String, int> indexes,
  Map<String, PathAttachment> attachments,
) {
  if (!path.runtimeEvaluable) return;

  final boneIndex = indexes[path.bone]!;
  final targetIndex = indexes[path.target]!;
  if (!computed[targetIndex]) {
    throw FormatException(
        'runtime path target must be emitted before constraint: ${path.name}');
  }

  final parent = _resolveComputedParentWorld(
    data,
    boneIndex,
    worlds,
    computed,
    indexes,
    'runtime path',
    path.name,
  );

  final translateMix = path.translateMix ?? 1.0;
  final rotateMix = path.rotateMix ?? 0.0;
  final inverse = _inverseAffine(parent.parentWorld);
  if ((translateMix > 0.0 || rotateMix > 0.0) && inverse == null) {
    throw FormatException(
        'runtime path parent transform is singular: ${path.name}');
  }

  final curve = _pathCubicInWorld(attachments[path.path]!, worlds[targetIndex]);
  final table = _buildPathArcLengthTable(curve);
  final sample = _samplePathByDistance(
      curve, table, (path.position ?? 0.0) * table.totalLength);
  var local = locals[boneIndex];

  if (translateMix > 0.0) {
    final sampledLocal =
        _transformPoint(inverse!, sample.position.x, sample.position.y);
    local = _withLocal(
      local,
      x: local.x + (sampledLocal.x - local.x) * translateMix,
      y: local.y + (sampledLocal.y - local.y) * translateMix,
    );
  }

  if (rotateMix > 0.0) {
    final tangentAngleRadians = sample.tangentAngle * math.pi / 180.0;
    final tangentLocal = _transformVector(
      inverse!,
      math.cos(tangentAngleRadians),
      math.sin(tangentAngleRadians),
    );
    final targetRotation = _tangentAngle(tangentLocal, local.rotation);
    local = _withLocal(
      local,
      rotation: local.rotation +
          _shortestAngleDelta(local.rotation, targetRotation) * rotateMix,
    );
  }

  locals[boneIndex] = local;
  worlds[boneIndex] =
      _worldForBone(parent.parentWorld, local, parent.hasParent);
  computed[boneIndex] = true;
}

/// Evaluate one IK constraint and write its solved rotations back into the
/// chain bones (ports runtime-nim/src/bony/transform.nim:389-524). Geometry per
/// docs/ik-constraint-format-contract.md §3-§6: fixed segment lengths come from
/// the REST pose, but the chain anchors at the CURRENT (live) joint origins
/// (me5.13 current-pivot anchoring, §4) so a moved parent is tracked; the bones'
/// CURRENT world rotations feed the solver and the target's CURRENT world
/// position is the goal. `mix` is applied ONCE inside the solver, so mix=0 is
/// the current-pose identity. Output conventions differ per solver (1-bone and
/// chain return ABSOLUTE world angles; solveTwoBoneIk's child is RELATIVE to its
/// parent) but the absolute-angle write-back below normalizes them.
void _applyRuntimeIk(
  SkeletonData data,
  IkConstraintData ik,
  List<BoneData> locals,
  List<Affine2> worlds,
  List<bool> computed,
  Map<String, int> indexes,
) {
  if (!ik.runtimeEvaluable) return;

  final targetIndex = indexes[ik.target]!;
  if (!computed[targetIndex]) {
    throw FormatException(
        'runtime ik target must be emitted before constraint: ${ik.name}');
  }
  // Raw (non-quantized) IK points — mirrors Nim applyRuntimeIk; routing these
  // through ikPoint()'s quantization would diverge from the committed golden.
  final target = IkPoint(worlds[targetIndex].tx, worlds[targetIndex].ty);

  final chainIndexes = [for (final name in ik.bones) indexes[name]!];

  // Rest-pose geometry: fixed segment lengths and rest joint origins (§6).
  final restMemo = <int, Affine2>{};
  final restOrigins = <IkPoint>[];
  for (final boneIndex in chainIndexes) {
    final rw = restWorldFor(data, boneIndex, indexes, restMemo);
    restOrigins.add(IkPoint(rw.tx, rw.ty));
  }
  final targetRest = restWorldFor(data, targetIndex, indexes, restMemo);
  final targetRestPoint = IkPoint(targetRest.tx, targetRest.ty);

  // Current FK worlds of the chain, captured BEFORE mutating, composed from
  // bone[0]'s external parent forward so the solver sees current rotations.
  final currentWorlds = <Affine2>[];
  for (var i = 0; i < chainIndexes.length; i++) {
    final boneIndex = chainIndexes[i];
    final parent = data.bones[boneIndex].parent;
    final hasParent = parent.isNotEmpty;
    var parentWorld = _rootParent;
    if (hasParent) {
      if (i > 0 && parent == ik.bones[i - 1]) {
        parentWorld = currentWorlds[i - 1];
      } else {
        parentWorld = _resolveComputedParentWorld(
          data,
          boneIndex,
          worlds,
          computed,
          indexes,
          'runtime ik bone',
          ik.name,
        ).parentWorld;
      }
    }
    currentWorlds
        .add(_worldForBone(parentWorld, data.bones[boneIndex], hasParent));
  }

  // Live (current-pivot) joint origins (§4). Segment lengths stay rest-derived,
  // so the bones remain rigid regardless of the live pose.
  final currentOrigins = <IkPoint>[
    for (final w in currentWorlds) IkPoint(w.tx, w.ty),
  ];

  // ik.mix is already f32-quantized at load (loader.dart), so no re-quantization
  // is needed here; absent mix/bendPositive default to 1.0/true.
  final storedMix = ik.mix ?? 1.0;
  final bendSign = (ik.bendPositive ?? true) ? 1.0 : -1.0;

  // Solved ABSOLUTE world angle (degrees) per constrained bone, chain order.
  final solvedWorldAngles = List<double>.filled(ik.bones.length, 0.0);
  switch (ik.bones.length) {
    case 1:
      {
        final length = ikDistance(restOrigins[0], targetRestPoint);
        final currentRotation = worldRotationDegrees(currentWorlds[0]);
        final solved = solveOneBoneIk(
            currentOrigins[0], length, currentRotation, target,
            mix: storedMix);
        solvedWorldAngles[0] = solved.rotation;
      }
    case 2:
      {
        final parentLength = ikDistance(restOrigins[0], restOrigins[1]);
        final childLength = ikDistance(restOrigins[1], targetRestPoint);
        final parentRotation = worldRotationDegrees(currentWorlds[0]);
        // solveTwoBoneIk's child input is RELATIVE to the parent (current child
        // world rotation minus current parent world rotation).
        final childRotation =
            worldRotationDegrees(currentWorlds[1]) - parentRotation;
        final solved = solveTwoBoneIk(currentOrigins[0], parentLength,
            childLength, parentRotation, childRotation, target,
            bendSign: bendSign, mix: storedMix);
        solvedWorldAngles[0] = solved.parentRotation;
        solvedWorldAngles[1] = solved.parentRotation + solved.childRotation;
      }
    default:
      {
        final n = ik.bones.length;
        final lengths = List<double>.filled(n, 0.0);
        for (var i = 0; i < n - 1; i++) {
          lengths[i] = ikDistance(restOrigins[i], restOrigins[i + 1]);
        }
        lengths[n - 1] = ikDistance(restOrigins[n - 1], targetRestPoint);
        // Live input polyline: live joint origins plus the last bone's live tip
        // (its live origin advanced by the rest last-segment length along its
        // current world direction).
        final points = <IkPoint>[...currentOrigins];
        final lastRadians =
            worldRotationDegrees(currentWorlds[n - 1]) * math.pi / 180.0;
        points.add(IkPoint(
          currentOrigins[n - 1].x + math.cos(lastRadians) * lengths[n - 1],
          currentOrigins[n - 1].y + math.sin(lastRadians) * lengths[n - 1],
        ));
        final solved = solveChainIk(points, lengths, target, mix: storedMix);
        for (var i = 0; i < n; i++) {
          solvedWorldAngles[i] = solved.rotations[i];
        }
      }
  }

  // Sequential FK write-back: convert each solved absolute world angle to the
  // bone's LOCAL rotation against its (already re-worlded) parent, then re-world
  // the bone so it serves as the next chain bone's parent world.
  for (var i = 0; i < chainIndexes.length; i++) {
    final boneIndex = chainIndexes[i];
    final parent = data.bones[boneIndex].parent;
    final hasParent = parent.isNotEmpty;
    var parentWorld = _rootParent;
    if (hasParent) {
      if (i > 0 && parent == ik.bones[i - 1]) {
        parentWorld = worlds[chainIndexes[i - 1]];
      } else {
        parentWorld = worlds[indexes[parent]!];
      }
    }
    // A bone that does not inherit its parent's rotation has world rotation
    // equal to its own local rotation, so no parent angle is subtracted.
    final inheritsRotation = locals[boneIndex].inheritRotation;
    final parentRotation = (hasParent && inheritsRotation)
        ? worldRotationDegrees(parentWorld)
        : 0.0;
    final newLocal = _withLocal(locals[boneIndex],
        rotation: solvedWorldAngles[i] - parentRotation);
    locals[boneIndex] = newLocal;
    worlds[boneIndex] = _worldForBone(parentWorld, newLocal, hasParent);
    computed[boneIndex] = true;
  }
}

// Build a local BoneData from a decomposed pose, carrying the inherit flags and
// transformMode from the template (invariant under a transform constraint).
BoneData _boneFromPose(BoneData base, TransformConstraintPose pose) =>
    base.copyWith(
      x: pose.x,
      y: pose.y,
      rotation: pose.rotation,
      scaleX: pose.scaleX,
      scaleY: pose.scaleY,
      shearX: pose.shearX,
      shearY: pose.shearY,
    );

// Port of runtime-nim/src/bony/transform.nim applyRuntimeTransformConstraint.
// Blend the constrained bone's CURRENT world pose toward the target bone's world
// pose per channel, then write the result back as a LOCAL transform (inverting
// _worldForBone) so the trailing FK bone-group re-derivation reproduces it
// instead of overwriting it. The constrained bone is a WRITE target and so is
// not pre-emitted; its current world is FK-composed here.
void _applyRuntimeTransformConstraint(
  SkeletonData data,
  TransformConstraintData tc,
  List<BoneData> locals,
  List<Affine2> worlds,
  List<bool> computed,
  Map<String, int> indexes,
) {
  if (!tc.runtimeEvaluable) return;

  final boneIndex = indexes[tc.bone]!;
  final targetIndex = indexes[tc.target]!;
  if (!computed[targetIndex]) {
    throw FormatException(
        'runtime transform target must be emitted before constraint: ${tc.name}');
  }

  final parent = _resolveComputedParentWorld(
    data,
    boneIndex,
    worlds,
    computed,
    indexes,
    'runtime transform',
    tc.name,
  );

  final baseLocal = locals[boneIndex];
  final currentWorld =
      _worldForBone(parent.parentWorld, baseLocal, parent.hasParent);

  final mix = TransformConstraintMix(
    translate: tc.translateMix ?? 1.0,
    rotate: tc.rotateMix ?? 1.0,
    scale: tc.scaleMix ?? 1.0,
    shear: tc.shearMix ?? 1.0,
  );
  final solvedWorld =
      applyTransformConstraint(currentWorld, worlds[targetIndex], mix);

  BoneData newLocal;
  if (!parent.hasParent) {
    newLocal = _boneFromPose(baseLocal, affineToTransformPose(solvedWorld));
  } else {
    final f = _factorParent(parent.parentWorld);
    var inherited = _identity;
    if (baseLocal.inheritRotation) inherited = inherited.mul(f.rotation);
    if (baseLocal.inheritReflection) inherited = inherited.mul(f.reflection);
    if (baseLocal.inheritScale) inherited = inherited.mul(f.scaleShear);
    final inheritedInverse = _inverseLinear(inherited);
    final parentInverse = _inverseAffine(parent.parentWorld);
    if (inheritedInverse == null || parentInverse == null) {
      throw FormatException(
          'runtime transform parent transform is singular: ${tc.name}');
    }
    final solvedLinear =
        _Lin2(solvedWorld.a, solvedWorld.b, solvedWorld.c, solvedWorld.d);
    final localLinear = inheritedInverse.mul(solvedLinear);
    final localOrigin =
        _transformPoint(parentInverse, solvedWorld.tx, solvedWorld.ty);
    newLocal = _boneFromPose(
      baseLocal,
      affineToTransformPose(_affine(localLinear, localOrigin.x, localOrigin.y)),
    );
  }

  locals[boneIndex] = newLocal;
  worlds[boneIndex] =
      _worldForBone(parent.parentWorld, newLocal, parent.hasParent);
  computed[boneIndex] = true;
}
