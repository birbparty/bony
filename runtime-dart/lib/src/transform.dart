// World transform computation: M2 skeleton pose (t=0 setup pose only).
//
// Ports the Nim reference implementation in runtime-nim/src/bony/transform.nim.

import 'dart:math' as math;
import 'model.dart';

const double _basisEpsilon = 1e-12;

// 2x2 linear (rotation/scale/shear) matrix — intermediate for parent factoring.
class _Lin2 {
  const _Lin2(this.a, this.b, this.c, this.d);
  final double a, b, c, d;

  _Lin2 mul(_Lin2 r) => _Lin2(
    a * r.a + c * r.b,
    b * r.a + d * r.b,
    a * r.c + c * r.d,
    b * r.c + d * r.d,
  );
}

const _identity = _Lin2(1.0, 0.0, 0.0, 1.0);

Affine2 _affine(_Lin2 m, double tx, double ty) =>
    Affine2(a: m.a, b: m.b, c: m.c, d: m.d, tx: tx, ty: ty);

// Convert bone local transform to a 2x2 linear matrix.
_Lin2 _localLinear(BoneData bone) {
  final xAngle = (bone.rotation + bone.shearX) * math.pi / 180.0;
  final yAngle = (bone.rotation + 90.0 + bone.shearY) * math.pi / 180.0;
  return _Lin2(
    math.cos(xAngle) * bone.scaleX,
    math.sin(xAngle) * bone.scaleX,
    math.cos(yAngle) * bone.scaleY,
    math.sin(yAngle) * bone.scaleY,
  );
}

// Decomposed factors from a parent Affine2 (rotation, reflection, scaleShear).
class _Factors {
  const _Factors(this.rotation, this.reflection, this.scaleShear);
  final _Lin2 rotation, reflection, scaleShear;
}

_Factors _factorParent(Affine2 p) {
  final sx = math.sqrt(p.a * p.a + p.b * p.b);
  if (sx > _basisEpsilon) {
    final det = p.a * p.d - p.b * p.c;
    final sign = det < 0.0 ? -1.0 : 1.0;
    final r0x = p.a / sx;
    final r0y = p.b / sx;
    final r1x = -r0y;
    final r1y = r0x;
    final k = r0x * p.c + r0y * p.d;
    final sy = sign * (r1x * p.c + r1y * p.d);
    return _Factors(
      _Lin2(r0x, r0y, r1x, r1y),
      _Lin2(1.0, 0.0, 0.0, sign),
      _Lin2(sx, 0.0, k, sy),
    );
  }
  final vy = math.sqrt(p.c * p.c + p.d * p.d);
  if (vy > _basisEpsilon) {
    final r1x = p.c / vy;
    final r1y = p.d / vy;
    final r0x = r1y;
    final r0y = -r1x;
    return _Factors(
      _Lin2(r0x, r0y, r1x, r1y),
      _identity,
      _Lin2(0.0, 0.0, 0.0, vy),
    );
  }
  return _Factors(_identity, _identity, _Lin2(0.0, 0.0, 0.0, 0.0));
}

Affine2 _worldForBone(Affine2 parent, BoneData bone, bool hasParent) {
  final local = _localLinear(bone);
  if (!hasParent) {
    return _affine(local, bone.x, bone.y);
  }

  final f = _factorParent(parent);
  var inherited = _identity;
  if (bone.inheritRotation) inherited = inherited.mul(f.rotation);
  if (bone.inheritReflection) inherited = inherited.mul(f.reflection);
  if (bone.inheritScale) inherited = inherited.mul(f.scaleShear);

  final worldLin = inherited.mul(local);
  final tx = parent.tx + parent.a * bone.x + parent.c * bone.y;
  final ty = parent.ty + parent.b * bone.x + parent.d * bone.y;
  return _affine(worldLin, tx, ty);
}

/// Compute the setup-pose world affine transform for every bone.
///
/// Returns one [Affine2] per bone, in the same order as [data.bones].
List<Affine2> computeWorldTransforms(SkeletonData data) {
  const rootParent = Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
  final result = List<Affine2>.filled(
    data.bones.length,
    rootParent,
  );
  final byName = <String, int>{};
  for (var i = 0; i < data.bones.length; i++) {
    final bone = data.bones[i];
    final parent =
        bone.parent.isEmpty ? rootParent : result[byName[bone.parent]!];
    result[i] = _worldForBone(parent, bone, bone.parent.isNotEmpty);
    byName[bone.name] = i;
  }
  return result;
}

DrawVertex _vertex(Affine2 world, double lx, double ly, double u, double v) {
  return DrawVertex(
    x: world.a * lx + world.c * ly + world.tx,
    y: world.b * lx + world.d * ly + world.ty,
    u: u,
    v: v,
    r: 1.0,
    g: 1.0,
    b: 1.0,
    a: 1.0,
  );
}

/// Build draw batches for the setup pose.
///
/// Each slot with a non-empty attachment that resolves to a region becomes one
/// [DrawBatch] with 4 vertices and 6 indices (two triangles).
List<DrawBatch> buildDrawBatches(SkeletonData data) {
  final worlds = computeWorldTransforms(data);
  final boneIndex = <String, int>{};
  for (var i = 0; i < data.bones.length; i++) {
    boneIndex[data.bones[i].name] = i;
  }
  final regionMap = <String, RegionAttachment>{
    for (final r in data.regions) r.name: r,
  };

  final result = <DrawBatch>[];
  for (final slot in data.slots) {
    if (slot.attachment.isEmpty) continue;
    final region = regionMap[slot.attachment];
    if (region == null) continue;

    final world = worlds[boneIndex[slot.bone]!];
    final hw = region.width * 0.5;
    final hh = region.height * 0.5;
    result.add(DrawBatch(
      slot: slot.name,
      bone: slot.bone,
      attachment: slot.attachment,
      blendMode: 'normal',
      texturePage: '',
      clipId: '',
      world: world,
      vertices: [
        _vertex(world, -hw, -hh, 0.0, 0.0),
        _vertex(world,  hw, -hh, 1.0, 0.0),
        _vertex(world,  hw,  hh, 1.0, 1.0),
        _vertex(world, -hw,  hh, 0.0, 1.0),
      ],
      indices: [0, 1, 2, 2, 3, 0],
    ));
  }
  return result;
}
