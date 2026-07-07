part of 'transform.dart';

const int _pathArcLengthSamples = 32;

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
  return radToDeg(math.atan2(tangent.y, tangent.x));
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
    total += distance(previous.x, previous.y, current.x, current.y);
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
    _Point(lerp(startPoint.x, endPoint.x, segmentMix),
        lerp(startPoint.y, endPoint.y, segmentMix)),
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
