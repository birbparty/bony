## M5 IK constraint solvers.

import std/math

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
    rotations*: seq[float64]


proc ikPoint*(x, y: float64): IkPoint =
  IkPoint(x: quantizeF32(x, "ik.x"), y: quantizeF32(y, "ik.y"))


proc requireFinite(value: float64; context: string): float64 =
  if classify(value) in {fcNan, fcInf, fcNegInf}:
    raise newBonyLoadError(numericOutOfRange, context & " must be finite")
  value


proc requireNonNegative(value: float64; context: string): float64 =
  result = requireFinite(value, context)
  if result < 0.0:
    raise newBonyLoadError(schemaViolation, context & " must be non-negative")


proc requireMix(value: float64): float64 =
  result = requireFinite(value, "ik.mix")
  if result < 0.0 or result > 1.0:
    raise newBonyLoadError(schemaViolation, "ik.mix must be in [0, 1]")


proc clampUnit(value: float64): float64 =
  max(-1.0, min(1.0, value))


proc lerp(a, b, mix: float64): float64 =
  a + (b - a) * mix


proc pointDistance(a, b: IkPoint): float64 =
  hypot(b.x - a.x, b.y - a.y)


proc solveOneBoneIk*(
  origin: IkPoint;
  length: float64;
  currentRotation: float64;
  target: IkPoint;
  mix = 1.0;
): OneBoneIkResult =
  let storedLength = requireNonNegative(length, "ik.length")
  let storedMix = requireMix(mix)
  let baseRotation = requireFinite(currentRotation, "ik.currentRotation")
  let targetRotation = radToDeg(arctan2(target.y - origin.y, target.x - origin.x))
  result.rotation = lerp(baseRotation, targetRotation, storedMix)
  let radians = degToRad(result.rotation)
  result.endPoint = IkPoint(
    x: origin.x + cos(radians) * storedLength,
    y: origin.y + sin(radians) * storedLength,
  )


proc solveTwoBoneIk*(
  origin: IkPoint;
  parentLength, childLength: float64;
  parentRotation, childRotation: float64;
  target: IkPoint;
  bendSign = 1.0;
  mix = 1.0;
): TwoBoneIkResult =
  let l1 = requireNonNegative(parentLength, "ik.parentLength")
  let l2 = requireNonNegative(childLength, "ik.childLength")
  let storedMix = requireMix(mix)
  let currentParent = requireFinite(parentRotation, "ik.parentRotation")
  let currentChild = requireFinite(childRotation, "ik.childRotation")
  let sign =
    if bendSign < 0.0:
      -1.0
    else:
      1.0

  let tx = target.x - origin.x
  let ty = target.y - origin.y
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
    x: origin.x + cos(parentRadians) * l1,
    y: origin.y + sin(parentRadians) * l1,
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
  let storedMix = requireMix(mix)
  var totalLength = 0.0
  var solvedLengths = newSeq[float64](lengths.len)
  for index, length in lengths:
    solvedLengths[index] = requireNonNegative(length, "ik.length[" & $index & "]")
    totalLength += solvedLengths[index]

  let root = points[0]
  result.points = @points
  if pointDistance(root, target) > totalLength:
    let angle = arctan2(target.y - root.y, target.x - root.x)
    for index in 1 ..< result.points.len:
      result.points[index] = IkPoint(
        x: result.points[index - 1].x + cos(angle) * solvedLengths[index - 1],
        y: result.points[index - 1].y + sin(angle) * solvedLengths[index - 1],
      )
  else:
    for _ in 0 ..< fabrikIterations:
      result.points[^1] = target
      for index in countdown(result.points.len - 2, 0):
        let next = result.points[index + 1]
        let current = result.points[index]
        let distance = max(pointDistance(current, next), solverEpsilon)
        let ratio = solvedLengths[index] / distance
        result.points[index] = IkPoint(
          x: next.x + (current.x - next.x) * ratio,
          y: next.y + (current.y - next.y) * ratio,
        )

      result.points[0] = root
      for index in 0 ..< result.points.len - 1:
        let current = result.points[index]
        let next = result.points[index + 1]
        let distance = max(pointDistance(current, next), solverEpsilon)
        let ratio = solvedLengths[index] / distance
        result.points[index + 1] = IkPoint(
          x: current.x + (next.x - current.x) * ratio,
          y: current.y + (next.y - current.y) * ratio,
        )

      if pointDistance(result.points[^1], target) <= fabrikTolerance:
        break

  for index, original in points:
    result.points[index] = IkPoint(
      x: lerp(original.x, result.points[index].x, storedMix),
      y: lerp(original.y, result.points[index].y, storedMix),
    )
  for index in 0 ..< result.points.len - 1:
    let current = result.points[index]
    let next = result.points[index + 1]
    result.rotations.add radToDeg(arctan2(next.y - current.y, next.x - current.x))
