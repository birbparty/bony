// World transform computation: M2 skeleton pose (t=0 setup pose only).
//
// Ports the Nim reference implementation in runtime-nim/src/bony/transform.nim.

import 'dart:math' as math;
import 'deform.dart';
import 'model.dart';

const double _basisEpsilon = 1e-12;
const int _pathArcLengthSamples = 32;

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

class _Point {
  const _Point(this.x, this.y);
  final double x, y;
}

class _Cubic {
  const _Cubic(this.p0, this.p1, this.p2, this.p3);
  final _Point p0, p1, p2, p3;
}

class _ArcLengthTable {
  const _ArcLengthTable(this.samples, this.distances, this.totalLength);
  final List<_Point> samples;
  final List<double> distances;
  final double totalLength;
}

class _PathSample {
  const _PathSample(this.position, this.tangentAngle, this.distance);
  final _Point position;
  final double tangentAngle;
  final double distance;
}

class _BoneGroupEntry {
  const _BoneGroupEntry(this.bones);
  final List<int> bones;
}

class _ConstraintEntry {
  const _ConstraintEntry(this.sourceIndex);
  final int sourceIndex;
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
  return BoneData(
    name: base.name,
    parent: base.parent,
    x: x ?? base.x,
    y: y ?? base.y,
    rotation: rotation ?? base.rotation,
    scaleX: base.scaleX,
    scaleY: base.scaleY,
    shearX: base.shearX,
    shearY: base.shearY,
    inheritRotation: base.inheritRotation,
    inheritScale: base.inheritScale,
    inheritReflection: base.inheritReflection,
    transformMode: base.transformMode,
  );
}

_Point _transformPoint(Affine2 world, double x, double y) => _Point(
      world.a * x + world.c * y + world.tx,
      world.b * x + world.d * y + world.ty,
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

double _distance(_Point a, _Point b) => math.sqrt(
      (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y),
    );

double _lerp(double a, double b, double mix) => a + (b - a) * mix;

_Point _evaluateCubic(_Cubic curve, double u) {
  final inverse = 1.0 - u;
  final w0 = inverse * inverse * inverse;
  final w1 = 3.0 * inverse * inverse * u;
  final w2 = 3.0 * inverse * u * u;
  final w3 = u * u * u;
  return _Point(
    w0 * curve.p0.x + w1 * curve.p1.x + w2 * curve.p2.x + w3 * curve.p3.x,
    w0 * curve.p0.y + w1 * curve.p1.y + w2 * curve.p2.y + w3 * curve.p3.y,
  );
}

_Point _cubicTangent(_Cubic curve, double u) {
  final inverse = 1.0 - u;
  return _Point(
    3.0 * inverse * inverse * (curve.p1.x - curve.p0.x) +
        6.0 * inverse * u * (curve.p2.x - curve.p1.x) +
        3.0 * u * u * (curve.p3.x - curve.p2.x),
    3.0 * inverse * inverse * (curve.p1.y - curve.p0.y) +
        6.0 * inverse * u * (curve.p2.y - curve.p1.y) +
        3.0 * u * u * (curve.p3.y - curve.p2.y),
  );
}

double _tangentAngle(_Point tangent, [double fallbackAngle = 0.0]) {
  if (math.sqrt(tangent.x * tangent.x + tangent.y * tangent.y) <=
      _basisEpsilon) {
    return fallbackAngle;
  }
  return math.atan2(tangent.y, tangent.x) * 180.0 / math.pi;
}

_ArcLengthTable _buildPathArcLengthTable(_Cubic curve) {
  final samples = List<_Point>.filled(
    _pathArcLengthSamples + 1,
    curve.p0,
    growable: false,
  );
  final distances = List<double>.filled(_pathArcLengthSamples + 1, 0.0);
  var previous = curve.p0;
  var total = 0.0;
  for (var index = 1; index <= _pathArcLengthSamples; index++) {
    final current = _evaluateCubic(curve, index / _pathArcLengthSamples);
    samples[index] = current;
    total += _distance(previous, current);
    distances[index] = total;
    previous = current;
  }
  return _ArcLengthTable(samples, distances, total);
}

_PathSample _samplePathByDistance(
    _Cubic curve, _ArcLengthTable table, double distance) {
  final clampedDistance = math.max(0.0, math.min(table.totalLength, distance));
  var sampleIndex = 0;
  while (sampleIndex + 1 < table.distances.length &&
      table.distances[sampleIndex + 1] < clampedDistance) {
    sampleIndex++;
  }
  final nextIndex = math.min(sampleIndex + 1, table.distances.length - 1);
  final startDistance = table.distances[sampleIndex];
  final endDistance = table.distances[nextIndex];
  final segmentMix = endDistance - startDistance <= _basisEpsilon
      ? 0.0
      : (clampedDistance - startDistance) / (endDistance - startDistance);
  final startPoint = table.samples[sampleIndex];
  final endPoint = table.samples[nextIndex];
  final u = (sampleIndex + segmentMix) / _pathArcLengthSamples;
  final segmentTangent =
      _Point(endPoint.x - startPoint.x, endPoint.y - startPoint.y);
  return _PathSample(
    _Point(_lerp(startPoint.x, endPoint.x, segmentMix),
        _lerp(startPoint.y, endPoint.y, segmentMix)),
    _tangentAngle(_cubicTangent(curve, u), _tangentAngle(segmentTangent)),
    clampedDistance,
  );
}

_Cubic _pathCubicInWorld(PathAttachment attachment, Affine2 targetWorld) {
  return _Cubic(
    _transformPoint(targetWorld, attachment.p0x, attachment.p0y),
    _transformPoint(targetWorld, attachment.p1x, attachment.p1y),
    _transformPoint(targetWorld, attachment.p2x, attachment.p2y),
    _transformPoint(targetWorld, attachment.p3x, attachment.p3y),
  );
}

List<Object> _buildPathConstraintUpdateCache(
    SkeletonData data, Map<String, int> byName) {
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

  final entries = [
    for (var index = 0; index < data.paths.length; index++)
      (order: data.paths[index].order, sourceIndex: index),
  ]..sort((a, b) {
      final byOrder = a.order.compareTo(b.order);
      return byOrder != 0 ? byOrder : a.sourceIndex.compareTo(b.sourceIndex);
    });

  final writeBlockers = List<int>.filled(data.bones.length, -1);
  for (var itemIndex = 0; itemIndex < entries.length; itemIndex++) {
    final boneIndex = byName[data.paths[entries[itemIndex].sourceIndex].bone]!;
    writeBlockers[boneIndex] = math.max(writeBlockers[boneIndex], itemIndex);
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

  for (var itemIndex = 0; itemIndex < entries.length; itemIndex++) {
    final path = data.paths[entries[itemIndex].sourceIndex];
    if (path.runtimeEvaluable) {
      final readIndex = byName[path.target]!;
      final lineage = <int>[];
      var cursor = readIndex;
      while (cursor >= 0) {
        lineage.add(cursor);
        cursor = parents[cursor];
      }
      final group = <int>[];
      for (final index in lineage.reversed) {
        if (index != readIndex && writeBlockers[index] >= itemIndex) {
          throw FormatException(
            'constraint read bone ancestor cannot be emitted before later write: ${data.bones[readIndex].name}',
          );
        }
        if (!emitted[index]) {
          group.add(index);
          emitted[index] = true;
        }
      }
      emitBoneGroup(group);
    }

    final group = <int>[];
    for (var index = 0; index < data.bones.length; index++) {
      if (!emitted[index] && releaseAfter[index] < itemIndex) {
        group.add(index);
        emitted[index] = true;
      }
    }
    emitBoneGroup(group);
    result.add(_ConstraintEntry(entries[itemIndex].sourceIndex));
  }

  final finalGroup = <int>[];
  for (var index = 0; index < data.bones.length; index++) {
    if (!emitted[index]) finalGroup.add(index);
  }
  emitBoneGroup(finalGroup);
  return result;
}

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

  final parent = data.bones[boneIndex].parent;
  final hasParent = parent.isNotEmpty;
  var parentWorld =
      const Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
  if (hasParent) {
    final parentIndex = indexes[parent]!;
    if (!computed[parentIndex]) {
      throw FormatException(
          'runtime path parent must be emitted before constraint: ${path.name}');
    }
    parentWorld = worlds[parentIndex];
  }

  final translateMix = path.translateMix ?? 1.0;
  final rotateMix = path.rotateMix ?? 0.0;
  final inverse = _inverseAffine(parentWorld);
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
  worlds[boneIndex] = _worldForBone(parentWorld, local, hasParent);
  computed[boneIndex] = true;
}

/// Compute the setup-pose world affine transform for every bone.
///
/// Returns one [Affine2] per bone, in the same order as [data.bones].
List<Affine2> computeWorldTransforms(SkeletonData data) {
  const rootParent = Affine2(a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0);
  final hasRuntimePaths = data.paths.any((p) => p.runtimeEvaluable);
  if (hasRuntimePaths) {
    final byName = <String, int>{};
    for (var i = 0; i < data.bones.length; i++) {
      byName[data.bones[i].name] = i;
    }
    final attachments = <String, PathAttachment>{
      for (final attachment in data.pathAttachments)
        attachment.name: attachment,
    };
    final cache = _buildPathConstraintUpdateCache(data, byName);
    final locals = data.bones.map((bone) => bone).toList();
    final result = List<Affine2>.filled(data.bones.length, rootParent);
    final computed = List<bool>.filled(data.bones.length, false);

    for (final entry in cache) {
      if (entry is _BoneGroupEntry) {
        for (final index in entry.bones) {
          final bone = locals[index];
          if (bone.parent.isEmpty) {
            result[index] = _worldForBone(rootParent, bone, false);
          } else {
            final parentIndex = byName[bone.parent]!;
            result[index] = _worldForBone(result[parentIndex], bone, true);
          }
          computed[index] = true;
        }
      } else if (entry is _ConstraintEntry) {
        _applyRuntimePathConstraint(
          data,
          data.paths[entry.sourceIndex],
          locals,
          result,
          computed,
          byName,
          attachments,
        );
      }
    }
    return result;
  }

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

/// Build draw batches for the setup pose, with M7 deformers applied at
/// default parameter values (mirroring the Nim CLI golden-gen pipeline).
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

  final baseBatches = <DrawBatch>[];
  for (final slot in data.slots) {
    if (slot.attachment.isEmpty) continue;
    final region = regionMap[slot.attachment];
    if (region == null) continue;

    final world = worlds[boneIndex[slot.bone]!];
    final hw = region.width * 0.5;
    final hh = region.height * 0.5;
    baseBatches.add(DrawBatch(
      slot: slot.name,
      bone: slot.bone,
      attachment: slot.attachment,
      blendMode: 'normal',
      texturePage: '',
      clipId: '',
      world: world,
      vertices: [
        _vertex(world, -hw, -hh, 0.0, 0.0),
        _vertex(world, hw, -hh, 1.0, 0.0),
        _vertex(world, hw, hh, 1.0, 1.0),
        _vertex(world, -hw, hh, 0.0, 1.0),
      ],
      indices: [0, 1, 2, 2, 3, 0],
    ));
  }

  if (data.deformers.isEmpty) return baseBatches;

  // Sample each parameter at its default value.
  final samples = data.parameters
      .map((p) => ParameterSample(name: p.name, value: p.defaultValue))
      .toList();
  final efDefs = effectiveDeformers(data.deformers, samples);
  if (efDefs.isEmpty) return baseBatches;

  // Apply deformers per batch — each batch uses its own vertices as setup.
  return baseBatches.map((batch) {
    final verts = batch.vertices;
    final positions = verts.map((v) => (x: v.x, y: v.y)).toList();
    final deformed = applyDeformers(positions, efDefs);
    return DrawBatch(
      slot: batch.slot,
      bone: batch.bone,
      attachment: batch.attachment,
      blendMode: batch.blendMode,
      texturePage: batch.texturePage,
      clipId: batch.clipId,
      world: batch.world,
      vertices: [
        for (var i = 0; i < verts.length; i++)
          DrawVertex(
            x: deformed[i].x,
            y: deformed[i].y,
            u: verts[i].u,
            v: verts[i].v,
            r: verts[i].r,
            g: verts[i].g,
            b: verts[i].b,
            a: verts[i].a,
          ),
      ],
      indices: batch.indices,
    );
  }).toList();
}
