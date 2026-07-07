## M5 path constraint sampling primitives.
##
## This module locks the deterministic path math used by path constraints and
## path attachments. First-class skeleton constraint ordering and wire support
## are owned by the later M5 integration work.

import std/math

import bony/constraints/common

const
  pathArcLengthSamples* = 32
  pathEpsilon = 1e-12

type
  PathPoint* = object
    x*: float64
    y*: float64

  PathCubic* = object
    p0*: PathPoint
    p1*: PathPoint
    p2*: PathPoint
    p3*: PathPoint

  PathArcLengthTable* = object
    samples*: seq[PathPoint]
    distances*: seq[float64]
    totalLength*: float64

  PathConstraintSample* = object
    position*: PathPoint
    tangentAngle*: float64
    distance*: float64


proc pathPoint*(x, y: float64): PathPoint =
  PathPoint(x: requireFinite(x, "path.x"), y: requireFinite(y, "path.y"))


proc pathCubic*(p0, p1, p2, p3: PathPoint): PathCubic =
  PathCubic(
    p0: requirePoint(p0, "path.p0"),
    p1: requirePoint(p1, "path.p1"),
    p2: requirePoint(p2, "path.p2"),
    p3: requirePoint(p3, "path.p3"),
  )


proc evaluateCubicPath*(curve: PathCubic; u: float64): PathPoint =
  let safeCurve = pathCubic(curve.p0, curve.p1, curve.p2, curve.p3)
  let storedU = requireUnit(u, "path.u")
  let inverse = 1.0 - storedU
  let w0 = inverse * inverse * inverse
  let w1 = 3.0 * inverse * inverse * storedU
  let w2 = 3.0 * inverse * storedU * storedU
  let w3 = storedU * storedU * storedU
  PathPoint(
    x: w0 * safeCurve.p0.x + w1 * safeCurve.p1.x + w2 * safeCurve.p2.x + w3 * safeCurve.p3.x,
    y: w0 * safeCurve.p0.y + w1 * safeCurve.p1.y + w2 * safeCurve.p2.y + w3 * safeCurve.p3.y,
  )


proc cubicPathTangent*(curve: PathCubic; u: float64): PathPoint =
  let safeCurve = pathCubic(curve.p0, curve.p1, curve.p2, curve.p3)
  let storedU = requireUnit(u, "path.u")
  let inverse = 1.0 - storedU
  PathPoint(
    x: 3.0 * inverse * inverse * (safeCurve.p1.x - safeCurve.p0.x) +
      6.0 * inverse * storedU * (safeCurve.p2.x - safeCurve.p1.x) +
      3.0 * storedU * storedU * (safeCurve.p3.x - safeCurve.p2.x),
    y: 3.0 * inverse * inverse * (safeCurve.p1.y - safeCurve.p0.y) +
      6.0 * inverse * storedU * (safeCurve.p2.y - safeCurve.p1.y) +
      3.0 * storedU * storedU * (safeCurve.p3.y - safeCurve.p2.y),
  )


proc tangentAngle*(tangent: PathPoint; fallbackAngle = 0.0): float64 =
  let safeTangent = requirePoint(tangent, "path.tangent")
  let safeFallback = requireFinite(fallbackAngle, "path.fallbackAngle")
  if hypot(safeTangent.x, safeTangent.y) <= pathEpsilon:
    safeFallback
  else:
    radToDeg(arctan2(safeTangent.y, safeTangent.x))


proc buildPathArcLengthTable*(curve: PathCubic): PathArcLengthTable =
  let safeCurve = pathCubic(curve.p0, curve.p1, curve.p2, curve.p3)
  result.samples = newSeq[PathPoint](pathArcLengthSamples + 1)
  result.distances = newSeq[float64](pathArcLengthSamples + 1)
  result.samples[0] = safeCurve.p0
  result.distances[0] = 0.0
  var previous = safeCurve.p0
  for index in 1 .. pathArcLengthSamples:
    let current = evaluateCubicPath(safeCurve, float64(index) / float64(pathArcLengthSamples))
    result.samples[index] = current
    result.totalLength += pointDistance(previous, current)
    result.distances[index] = result.totalLength
    previous = current


proc samplePathByDistance*(curve: PathCubic; distance: float64): PathConstraintSample =
  let table = buildPathArcLengthTable(curve)
  let safeDistance = requireFinite(distance, "path.distance")
  let clampedDistance = max(0.0, min(table.totalLength, safeDistance))

  var sampleIndex = 0
  while sampleIndex + 1 < table.distances.len and table.distances[sampleIndex + 1] < clampedDistance:
    inc sampleIndex

  let nextIndex = min(sampleIndex + 1, table.distances.high)
  let startDistance = table.distances[sampleIndex]
  let endDistance = table.distances[nextIndex]
  let segmentMix =
    if endDistance - startDistance <= pathEpsilon:
      0.0
    else:
      (clampedDistance - startDistance) / (endDistance - startDistance)
  let startPoint = table.samples[sampleIndex]
  let endPoint = table.samples[nextIndex]
  let u = (float64(sampleIndex) + segmentMix) / float64(pathArcLengthSamples)
  result.position = PathPoint(
    x: lerp(startPoint.x, endPoint.x, segmentMix),
    y: lerp(startPoint.y, endPoint.y, segmentMix),
  )
  let segmentTangent = PathPoint(x: endPoint.x - startPoint.x, y: endPoint.y - startPoint.y)
  result.tangentAngle = tangentAngle(cubicPathTangent(curve, u), tangentAngle(segmentTangent))
  result.distance = clampedDistance


proc applyPathPositionConstraint*(current: PathPoint; curve: PathCubic; distance: float64; mix = 1.0): PathConstraintSample =
  let safeCurrent = requirePoint(current, "path.current")
  let safeMix = requireUnit(mix, "path.mix")
  let sampled = samplePathByDistance(curve, distance)
  result.position = PathPoint(
    x: lerp(safeCurrent.x, sampled.position.x, safeMix),
    y: lerp(safeCurrent.y, sampled.position.y, safeMix),
  )
  result.tangentAngle = sampled.tangentAngle
  result.distance = sampled.distance
