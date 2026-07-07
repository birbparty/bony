part of 'transform.dart';

/// One default [PhysicsConstraintState] per physics constraint (index = source
/// order in `data.physicsConstraints`). Mirrors the Nim `newPhysicsStates`:
/// default accumulator=0, inactive, channels un-initialized for lazy seeding on
/// the first [advancePhysics].
List<PhysicsConstraintState> newPhysicsStates(SkeletonData data) => [
      for (var i = 0; i < data.physicsConstraints.length; i++)
        PhysicsConstraintState(),
    ];

double _physicsChannelValue(BoneData bone, PhysicsChannel channel) {
  switch (channel) {
    case PhysicsChannel.x:
      return bone.x;
    case PhysicsChannel.y:
      return bone.y;
    case PhysicsChannel.rotate:
      return bone.rotation;
    case PhysicsChannel.scaleX:
      return bone.scaleX;
    case PhysicsChannel.shearX:
      return bone.shearX;
  }
}

BoneData _withPhysicsChannel(
    BoneData base, PhysicsChannel channel, double value) {
  // Mirror the Nim withPhysicsChannel, which routes the written channel through
  // localTransform's f32 quantization (the public output boundary). The other
  // channels are already f32 from load/applyPose, so quantizing only the newly
  // written value reproduces the reference's f32 boundary exactly.
  final v = quantizeF32(value);
  return base.copyWith(
    x: channel == PhysicsChannel.x ? v : base.x,
    y: channel == PhysicsChannel.y ? v : base.y,
    rotation: channel == PhysicsChannel.rotate ? v : base.rotation,
    scaleX: channel == PhysicsChannel.scaleX ? v : base.scaleX,
    shearX: channel == PhysicsChannel.shearX ? v : base.shearX,
  );
}

List<Affine2> _recomputeWorldsFromLocals(
  SkeletonData data,
  List<BoneData> locals,
  Map<String, int> byName,
  ActiveSkinMembership activation,
) {
  final result = _newWorldList(locals.length);
  for (var i = 0; i < locals.length; i++) {
    _emitBoneWorldAt(i, locals, result, byName, activation);
  }
  return result;
}

/// Stateful advance seam: bony's only time- and state-dependent pose entry
/// point, mirroring the Nim `advancePhysics`. Runs the pure world-transform/
/// constraint pass to produce the animated target pose, then the physics stage
/// (physics runs AFTER that pass, per docs/constraint-total-order.md), then
/// recomposes worlds from the physics-adjusted locals. `states` carries one
/// [PhysicsConstraintState] per constraint across frames (see
/// [newPhysicsStates]); `dt` is the non-negative frame delta and the ONLY time
/// source. With no physics constraints this is exactly [computeWorldTransforms].
///
/// NOTE: physics rigs in this slice carry no ik/transform/path constraints, so
/// the constraint-adjusted locals equal `data.bones` (the posed skeleton). A rig
/// that mixed physics with those constraints would need the adjusted locals
/// threaded here (as the Nim `computeWorldsAndLocals` does); that is out of
/// scope until such a rig exists.
List<Affine2> advancePhysics(
  SkeletonData data,
  List<PhysicsConstraintState> states,
  double dt, {
  String activeSkin = 'default',
}) {
  if (dt < 0.0) {
    throw const FormatException('physics advance dt must be non-negative');
  }
  final activation = data.activeSkinMembership(activeSkin);
  if (data.physicsConstraints.isEmpty) {
    return computeWorldTransforms(data, activeSkin: activeSkin);
  }
  if (states.length != data.physicsConstraints.length) {
    throw FormatException(
        'physics state count (${states.length}) does not match physics '
        'constraint count (${data.physicsConstraints.length})');
  }

  final byName = _boneIndexByName(data.bones);
  final computed = _computeWorldsAndLocals(data, activation);
  final locals = List<BoneData>.of(computed.locals);

  // Deterministic physics-stage order (docs/constraint-total-order.md): by
  // `order`, then source index. Mirrors buildPhysicsConstraintOrder.
  final order = List<int>.generate(data.physicsConstraints.length, (i) => i)
    ..sort((a, b) {
      final byOrder = data.physicsConstraints[a].order
          .compareTo(data.physicsConstraints[b].order);
      return byOrder != 0 ? byOrder : a.compareTo(b);
    });

  for (final sourceIndex in order) {
    final pc = data.physicsConstraints[sourceIndex];
    final boneIndex = byName[pc.bone]!;
    // Enabled channels in canonical (enum ordinal) order, mirroring Nim set
    // iteration.
    final inputs = <PhysicsChannelInput>[
      for (final channel in PhysicsChannel.values)
        if (pc.channels.contains(channel))
          physicsChannelInput(
              channel, _physicsChannelValue(locals[boneIndex], channel)),
    ];
    final params = physicsParams(
      inertia: pc.inertia ?? 0.0,
      strength: pc.strength ?? 0.0,
      damping: pc.damping ?? 0.0,
      mass: pc.mass ?? 1.0,
      gravity: pc.gravity ?? 0.0,
      wind: pc.wind ?? 0.0,
      mix: pc.physicsMix ?? 1.0,
    );
    final res = updatePhysicsConstraint(
      states[sourceIndex],
      params,
      inputs,
      dt,
      active: activation.physicsConstraints[sourceIndex],
    );
    if (!activation.physicsConstraints[sourceIndex]) continue;
    for (final output in res.outputs) {
      locals[boneIndex] =
          _withPhysicsChannel(locals[boneIndex], output.channel, output.value);
    }
  }

  return _recomputeWorldsFromLocals(data, locals, byName, activation);
}
