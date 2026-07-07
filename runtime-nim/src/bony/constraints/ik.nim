## M5 IK constraint solvers.

import std/math

import bony/constraints/common
import bony/model

const
  fabrikIterations* = 8
  fabrikTolerance* = 1e-4
  solverEpsilon = 1e-12

type
  IkPoint* = object
    x*: float64
    y*: float64

  OneBoneIkResult* = object
    rotation*: float64
    endPoint*: IkPoint

  TwoBoneIkResult* = object
    parentRotation*: float64
    childRotation*: float64
    midPoint*: IkPoint
    endPoint*: IkPoint

  ChainIkResult* = object
    points*: seq[IkPoint]
    ## Absolute segment angles in degrees, ordered like `points[0 ..^ 1]`.
    rotations*: seq[float64]


proc ikPoint*(x, y: float64): IkPoint =
  IkPoint(x: quantizeF32(x, "ik.x"), y: quantizeF32(y, "ik.y"))


proc clampUnit(value: float64): float64 =
  max(-1.0, min(1.0, value))


proc direction(fromPoint, toPoint: IkPoint; fallbackAngle: float64): tuple[x, y: float64] =
  let dx = toPoint.x - fromPoint.x
  let dy = toPoint.y - fromPoint.y
  let distance = hypot(dx, dy)
  if distance > solverEpsilon:
    (x: dx / distance, y: dy / distance)
  else:
    (x: cos(fallbackAngle), y: sin(fallbackAngle))


proc solveOneBoneIk*(
  origin: IkPoint;
  length: float64;
  currentRotation: float64;
  target: IkPoint;
  mix = 1.0;
): OneBoneIkResult =
  let safeOrigin = requirePoint(origin, "ik.origin")
  let safeTarget = requirePoint(target, "ik.target")
  let storedLength = requireNonNegative(length, "ik.length")
  let storedMix = requireUnit(mix, "ik.mix")
  let baseRotation = requireFinite(currentRotation, "ik.currentRotation")
  let targetRotation = radToDeg(arctan2(safeTarget.y - safeOrigin.y, safeTarget.x - safeOrigin.x))
  result.rotation = lerp(baseRotation, targetRotation, storedMix)
  let radians = degToRad(result.rotation)
  result.endPoint = IkPoint(
    x: safeOrigin.x + cos(radians) * storedLength,
    y: safeOrigin.y + sin(radians) * storedLength,
  )


proc solveTwoBoneIk*(
  origin: IkPoint;
  parentLength, childLength: float64;
  parentRotation, childRotation: float64;
  target: IkPoint;
  bendSign = 1.0;
  mix = 1.0;
): TwoBoneIkResult =
  let safeOrigin = requirePoint(origin, "ik.origin")
  let safeTarget = requirePoint(target, "ik.target")
  let l1 = requireNonNegative(parentLength, "ik.parentLength")
  let l2 = requireNonNegative(childLength, "ik.childLength")
  let storedMix = requireUnit(mix, "ik.mix")
  let currentParent = requireFinite(parentRotation, "ik.parentRotation")
  let currentChild = requireFinite(childRotation, "ik.childRotation")
  let safeBendSign = requireFinite(bendSign, "ik.bendSign")
  let sign =
    if safeBendSign < 0.0:
      -1.0
    else:
      1.0

  let tx = safeTarget.x - safeOrigin.x
  let ty = safeTarget.y - safeOrigin.y
  let d = hypot(tx, ty)
  let denominator = 2.0 * l1 * l2
  let solvedChild =
    if denominator <= solverEpsilon:
      0.0
    else:
      arccos(clampUnit((d * d - l1 * l1 - l2 * l2) / denominator)) * sign
  let k1 = l1 + l2 * cos(solvedChild)
  let k2 = l2 * sin(solvedChild)
  let solvedParent = arctan2(ty, tx) - arctan2(k2, k1)

  result.parentRotation = lerp(currentParent, radToDeg(solvedParent), storedMix)
  result.childRotation = lerp(currentChild, radToDeg(solvedChild), storedMix)

  let parentRadians = degToRad(result.parentRotation)
  let childRadians = degToRad(result.parentRotation + result.childRotation)
  result.midPoint = IkPoint(
    x: safeOrigin.x + cos(parentRadians) * l1,
    y: safeOrigin.y + sin(parentRadians) * l1,
  )
  result.endPoint = IkPoint(
    x: result.midPoint.x + cos(childRadians) * l2,
    y: result.midPoint.y + sin(childRadians) * l2,
  )


proc solveChainIk*(points: openArray[IkPoint]; lengths: openArray[float64]; target: IkPoint; mix = 1.0): ChainIkResult =
  if points.len < 2:
    raise newBonyLoadError(schemaViolation, "ik chain needs at least two points")
  if lengths.len != points.len - 1:
    raise newBonyLoadError(schemaViolation, "ik chain length count must equal point count minus one")
  let storedMix = requireUnit(mix, "ik.mix")
  let safeTarget = requirePoint(target, "ik.target")
  var safePoints = newSeq[IkPoint](points.len)
  for index, point in points:
    safePoints[index] = requirePoint(point, "ik.point[" & $index & "]")
  var totalLength = 0.0
  var solvedLengths = newSeq[float64](lengths.len)
  for index, length in lengths:
    solvedLengths[index] = requireNonNegative(length, "ik.length[" & $index & "]")
    totalLength += solvedLengths[index]

  let root = safePoints[0]
  result.points = safePoints
  let targetAngle = arctan2(safeTarget.y - root.y, safeTarget.x - root.x)
  let rootToTarget = pointDistance(root, safeTarget)
  if rootToTarget > totalLength:
    let angle = targetAngle
    for index in 1 ..< result.points.len:
      result.points[index] = IkPoint(
        x: result.points[index - 1].x + cos(angle) * solvedLengths[index - 1],
        y: result.points[index - 1].y + sin(angle) * solvedLengths[index - 1],
      )
  else:
    var hasDegenerateSegment = false
    for index in 0 ..< result.points.len - 1:
      if solvedLengths[index] > solverEpsilon and pointDistance(result.points[index], result.points[index + 1]) <= solverEpsilon:
        hasDegenerateSegment = true
        break
    if hasDegenerateSegment and rootToTarget > solverEpsilon:
      let ux = (safeTarget.x - root.x) / rootToTarget
      let uy = (safeTarget.y - root.y) / rootToTarget
      let bend = sqrt(max(totalLength * totalLength - rootToTarget * rootToTarget, 0.0)) * 0.5
      var walked = 0.0
      for index in 1 ..< result.points.len - 1:
        walked += solvedLengths[index - 1]
        let t = walked / totalLength
        let offset = sin(PI * t) * bend
        result.points[index] = IkPoint(
          x: root.x + (safeTarget.x - root.x) * t - uy * offset,
          y: root.y + (safeTarget.y - root.y) * t + ux * offset,
        )

    for _ in 0 ..< fabrikIterations:
      result.points[^1] = safeTarget
      for index in countdown(result.points.len - 2, 0):
        let next = result.points[index + 1]
        let current = result.points[index]
        let fallback = if index == 0: targetAngle else: arctan2(
          result.points[index].y - result.points[index - 1].y,
          result.points[index].x - result.points[index - 1].x,
        )
        let unit = direction(next, current, fallback)
        result.points[index] = IkPoint(
          x: next.x + unit.x * solvedLengths[index],
          y: next.y + unit.y * solvedLengths[index],
        )

      result.points[0] = root
      for index in 0 ..< result.points.len - 1:
        let current = result.points[index]
        let next = result.points[index + 1]
        let fallback = if index + 2 < result.points.len: arctan2(
          result.points[index + 2].y - result.points[index + 1].y,
          result.points[index + 2].x - result.points[index + 1].x,
        ) else: targetAngle
        let unit = direction(current, next, fallback)
        result.points[index + 1] = IkPoint(
          x: current.x + unit.x * solvedLengths[index],
          y: current.y + unit.y * solvedLengths[index],
        )

      if pointDistance(result.points[^1], safeTarget) <= fabrikTolerance:
        break

  for index, original in safePoints:
    result.points[index] = IkPoint(
      x: lerp(original.x, result.points[index].x, storedMix),
      y: lerp(original.y, result.points[index].y, storedMix),
    )
  for index in 0 ..< result.points.len - 1:
    let current = result.points[index]
    let next = result.points[index + 1]
    result.rotations.add radToDeg(arctan2(next.y - current.y, next.x - current.x))
