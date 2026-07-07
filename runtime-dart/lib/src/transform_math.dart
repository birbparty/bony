part of 'transform.dart';

const double _basisEpsilon = 1e-12;
const _rootParent = Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
const _zeroAffine = Affine2(a: 0.0, b: 0.0, c: 0.0, d: 0.0, tx: 0.0, ty: 0.0);

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

// Inverse of a 2x2 linear part [[a, c], [b, d]] (column-major a/b, c/d); null if
// singular. Mirrors runtime-nim's inverseLinear.
_Lin2? _inverseLinear(_Lin2 m) {
  final det = m.a * m.d - m.c * m.b;
  if (det.abs() < _basisEpsilon) return null;
  return _Lin2(m.d / det, -m.b / det, -m.c / det, m.a / det);
}

class _Point {
  const _Point(this.x, this.y);
  final double x, y;
}

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

BoneData _withLocal(BoneData base, {double? x, double? y, double? rotation}) {
  return base.copyWith(x: x, y: y, rotation: rotation);
}

_Point _transformPoint(Affine2 world, double x, double y) => _Point(
      world.a * x + world.c * y + world.tx,
      world.b * x + world.d * y + world.ty,
    );

Affine2 _composeAffine(Affine2 parent, Affine2 child) => Affine2(
      a: parent.a * child.a + parent.c * child.b,
      b: parent.b * child.a + parent.d * child.b,
      c: parent.a * child.c + parent.c * child.d,
      d: parent.b * child.c + parent.d * child.d,
      tx: parent.a * child.tx + parent.c * child.ty + parent.tx,
      ty: parent.b * child.tx + parent.d * child.ty + parent.ty,
    );

DrawVertex _composeVertex(Affine2 parent, DrawVertex vertex) {
  final point = _transformPoint(parent, vertex.x, vertex.y);
  return DrawVertex(
    x: point.x,
    y: point.y,
    u: vertex.u,
    v: vertex.v,
    r: vertex.r,
    g: vertex.g,
    b: vertex.b,
    a: vertex.a,
  );
}

DrawBatch _composeBatch(Affine2 parent, DrawBatch batch) => DrawBatch(
      slot: batch.slot,
      bone: batch.bone,
      attachment: batch.attachment,
      blendMode: batch.blendMode,
      texturePage: batch.texturePage,
      clipId: batch.clipId,
      world: _composeAffine(parent, batch.world),
      vertices: [
        for (final vertex in batch.vertices) _composeVertex(parent, vertex)
      ],
      indices: List<int>.from(batch.indices),
    );

_Point _transformVector(Affine2 world, double x, double y) => _Point(
      world.a * x + world.c * y,
      world.b * x + world.d * y,
    );

Affine2? _inverseAffine(Affine2 world) {
  final det = world.a * world.d - world.b * world.c;
  if (det.abs() <= _basisEpsilon) return null;
  final invA = world.d / det;
  final invB = -world.b / det;
  final invC = -world.c / det;
  final invD = world.a / det;
  return Affine2(
    a: invA,
    b: invB,
    c: invC,
    d: invD,
    tx: -(invA * world.tx + invC * world.ty),
    ty: -(invB * world.tx + invD * world.ty),
  );
}

double _shortestAngleDelta(double fromAngle, double toAngle) {
  var delta = (toAngle - fromAngle) % 360.0;
  if (delta > 180.0) {
    delta -= 360.0;
  } else if (delta < -180.0) {
    delta += 360.0;
  }
  return delta;
}

// --- M5-IK evaluation helpers (mirror runtime-nim/src/bony/transform.nim) ---
//
// Kind-agnostic prep for the IK evaluation pass (`_applyRuntimeIk`, added in a
// later slice). Public so they can be unit-tested directly; all are pure.

/// World rotation of an affine transform, in degrees (transform.nim:349).
/// The world x-axis is (a, b), so the rotation is atan2(b, a).
double worldRotationDegrees(Affine2 world) =>
    radToDeg(math.atan2(world.b, world.a));

/// Euclidean distance between two IK points (transform.nim:353).
double ikDistance(IkPoint a, IkPoint b) => distance(a.x, a.y, b.x, b.y);
