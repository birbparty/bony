## M7 warp and rotation deformers for skinned mesh vertices.

import std/[algorithm, math, sets, tables]

import bony/mesh/skinning
import bony/model

const
  minLatticeAxis = 2
  deformerEpsilon = 1e-12

type
  DeformerPoint* = object
    x*: float64
    y*: float64

  WarpLattice* = object
    rows*: uint32
    cols*: uint32
    minX*: float64
    minY*: float64
    maxX*: float64
    maxY*: float64
    controlPoints*: seq[DeformerPoint]

  RotationDeformer* = object
    pivotX*: float64
    pivotY*: float64
    angleDegrees*: float64
    scaleX*: float64
    scaleY*: float64
    opacity*: float64

  DeformerKind* = enum
    warpDeformerKind,
    rotationDeformerKind

  Deformer* = object
    id*: string
    parent*: string
    order*: uint32
    case kind*: DeformerKind
    of warpDeformerKind:
      warp*: WarpLattice
    of rotationDeformerKind:
      rotation*: RotationDeformer


proc deformerPoint*(x, y: float64): DeformerPoint =
  DeformerPoint(x: quantizeF32(x, "deformer.point.x"), y: quantizeF32(y, "deformer.point.y"))


proc validatePoint(point: DeformerPoint; context: string) =
  discard quantizeF32(point.x, context & ".x")
  discard quantizeF32(point.y, context & ".y")


proc validateSkinnedVertex(vertex: SkinnedMeshVertex; index: int) =
  discard quantizeF32(vertex.x, "deformer.vertex[" & $index & "].x")
  discard quantizeF32(vertex.y, "deformer.vertex[" & $index & "].y")
  discard quantizeF32(vertex.u, "deformer.vertex[" & $index & "].u")
  discard quantizeF32(vertex.v, "deformer.vertex[" & $index & "].v")


proc validateWarpLattice*(lattice: WarpLattice) =
  if lattice.rows < minLatticeAxis or lattice.cols < minLatticeAxis:
    raise newBonyLoadError(schemaViolation, "warp lattice must be at least 2x2")
  let expected64 = uint64(lattice.rows) * uint64(lattice.cols)
  if expected64 > uint64(high(int)):
    raise newBonyLoadError(schemaViolation, "warp lattice control point count exceeds platform range")
  let expected = int(expected64)
  if lattice.controlPoints.len != expected:
    raise newBonyLoadError(schemaViolation, "warp lattice control point count must equal rows * cols")
  let minX = quantizeF32(lattice.minX, "warp.minX")
  let minY = quantizeF32(lattice.minY, "warp.minY")
  let maxX = quantizeF32(lattice.maxX, "warp.maxX")
  let maxY = quantizeF32(lattice.maxY, "warp.maxY")
  if maxX - minX <= deformerEpsilon or maxY - minY <= deformerEpsilon:
    raise newBonyLoadError(schemaViolation, "warp lattice bounds must have positive area")
  for index, point in lattice.controlPoints:
    validatePoint(point, "warp.controlPoint[" & $index & "]")


proc warpLattice*(
  rows, cols: uint32;
  minX, minY, maxX, maxY: float64;
  controlPoints: openArray[DeformerPoint];
): WarpLattice =
  result = WarpLattice(
    rows: rows,
    cols: cols,
    minX: quantizeF32(minX, "warp.minX"),
    minY: quantizeF32(minY, "warp.minY"),
    maxX: quantizeF32(maxX, "warp.maxX"),
    maxY: quantizeF32(maxY, "warp.maxY"),
    controlPoints: @controlPoints,
  )
  validateWarpLattice(result)


proc validateRotationDeformer*(rotation: RotationDeformer) =
  discard quantizeF32(rotation.pivotX, "rotationDeformer.pivotX")
  discard quantizeF32(rotation.pivotY, "rotationDeformer.pivotY")
  discard quantizeF32(rotation.angleDegrees, "rotationDeformer.angleDegrees")
  if quantizeF32(rotation.scaleX, "rotationDeformer.scaleX") <= 0.0:
    raise newBonyLoadError(schemaViolation, "rotation deformer scaleX must be positive")
  if quantizeF32(rotation.scaleY, "rotationDeformer.scaleY") <= 0.0:
    raise newBonyLoadError(schemaViolation, "rotation deformer scaleY must be positive")
  let opacity = quantizeF32(rotation.opacity, "rotationDeformer.opacity")
  if opacity < 0.0 or opacity > 1.0:
    raise newBonyLoadError(schemaViolation, "rotation deformer opacity must be in 0..1")


proc rotationDeformer*(pivotX, pivotY, angleDegrees: float64; scaleX = 1.0; scaleY = 1.0; opacity = 1.0): RotationDeformer =
  result = RotationDeformer(
    pivotX: quantizeF32(pivotX, "rotationDeformer.pivotX"),
    pivotY: quantizeF32(pivotY, "rotationDeformer.pivotY"),
    angleDegrees: quantizeF32(angleDegrees, "rotationDeformer.angleDegrees"),
    scaleX: quantizeF32(scaleX, "rotationDeformer.scaleX"),
    scaleY: quantizeF32(scaleY, "rotationDeformer.scaleY"),
    opacity: quantizeF32(opacity, "rotationDeformer.opacity"),
  )
  validateRotationDeformer(result)


proc warpDeformer*(id: string; lattice: WarpLattice; parent = ""; order = 0'u32): Deformer =
  if id.len == 0:
    raise newBonyLoadError(schemaViolation, "deformer id must not be empty")
  validateWarpLattice(lattice)
  Deformer(id: id, parent: parent, order: order, kind: warpDeformerKind, warp: lattice)


proc rotationDeformerNode*(id: string; rotation: RotationDeformer; parent = ""; order = 0'u32): Deformer =
  if id.len == 0:
    raise newBonyLoadError(schemaViolation, "deformer id must not be empty")
  validateRotationDeformer(rotation)
  Deformer(id: id, parent: parent, order: order, kind: rotationDeformerKind, rotation: rotation)


proc validateDeformer(deformer: Deformer) =
  if deformer.id.len == 0:
    raise newBonyLoadError(schemaViolation, "deformer id must not be empty")
  case deformer.kind
  of warpDeformerKind:
    validateWarpLattice(deformer.warp)
  of rotationDeformerKind:
    validateRotationDeformer(deformer.rotation)


proc assertAcyclic(id: string; byId: Table[string, Deformer]; visiting, visited: var HashSet[string]) =
  if id in visited:
    return
  if id in visiting:
    raise newBonyLoadError(cycleDetected, "deformer tree must be acyclic")
  visiting.incl(id)
  let parent = byId[id].parent
  if parent.len != 0:
    if parent notin byId:
      raise newBonyLoadError(unknownRequiredReference, "unknown deformer parent: " & parent)
    assertAcyclic(parent, byId, visiting, visited)
  visiting.excl(id)
  visited.incl(id)


proc validateDeformerTree*(deformers: openArray[Deformer]) =
  var ids = initHashSet[string]()
  var orders = initHashSet[uint32]()
  var byId = initTable[string, Deformer]()
  for deformer in deformers:
    validateDeformer(deformer)
    if deformer.id in ids:
      raise newBonyLoadError(duplicateKey, "duplicate deformer id: " & deformer.id)
    if deformer.order in orders:
      raise newBonyLoadError(schemaViolation, "deformer global order values must be unique")
    ids.incl(deformer.id)
    orders.incl(deformer.order)
    byId[deformer.id] = deformer

  var visiting = initHashSet[string]()
  var visited = initHashSet[string]()
  for deformer in deformers:
    assertAcyclic(deformer.id, byId, visiting, visited)
  for deformer in deformers:
    if deformer.parent.len != 0 and byId[deformer.parent].order >= deformer.order:
      raise newBonyLoadError(orderingViolation, "deformer parent must have an earlier global order")


proc orderedDeformers(deformers: openArray[Deformer]): seq[Deformer] =
  validateDeformerTree(deformers)
  result = @deformers
  result.sort(proc(a, b: Deformer): int = cmp(a.order, b.order))


proc choose(n, k: int): float64 =
  if k < 0 or k > n:
    return 0.0
  var numerator = 1.0
  var denominator = 1.0
  let smaller = min(k, n - k)
  if smaller == 0:
    return 1.0
  for index in 1 .. smaller:
    numerator *= float64(n - smaller + index)
    denominator *= float64(index)
  numerator / denominator


proc bernstein(i, degree: int; t: float64): float64 =
  choose(degree, i) * pow(t, float64(i)) * pow(1.0 - t, float64(degree - i))


proc controlPoint(lattice: WarpLattice; row, col: int): DeformerPoint =
  lattice.controlPoints[row * int(lattice.cols) + col]


proc applyWarpAt(vertex: SkinnedMeshVertex; lattice: WarpLattice; u, v: float64): SkinnedMeshVertex =
  if u < 0.0 or u > 1.0 or v < 0.0 or v > 1.0:
    return vertex
  let rowDegree = int(lattice.rows) - 1
  let colDegree = int(lattice.cols) - 1
  var x = 0.0
  var y = 0.0
  for row in 0 .. rowDegree:
    let bv = bernstein(row, rowDegree, v)
    for col in 0 .. colDegree:
      let bu = bernstein(col, colDegree, u)
      let weight = bv * bu
      let point = lattice.controlPoint(row, col)
      x += weight * point.x
      y += weight * point.y
  SkinnedMeshVertex(x: quantizeF32(x, "mesh.warped.x"), y: quantizeF32(y, "mesh.warped.y"), u: vertex.u, v: vertex.v)


proc applyWarp(vertex: SkinnedMeshVertex; lattice: WarpLattice): SkinnedMeshVertex =
  applyWarpAt(vertex, lattice, (vertex.x - lattice.minX) / (lattice.maxX - lattice.minX), (vertex.y - lattice.minY) / (lattice.maxY - lattice.minY))


proc applyRotation(vertex: SkinnedMeshVertex; rotation: RotationDeformer): SkinnedMeshVertex =
  let angle = degToRad(rotation.angleDegrees)
  let cosAngle = cos(angle)
  let sinAngle = sin(angle)
  let localX = (vertex.x - rotation.pivotX) * rotation.scaleX
  let localY = (vertex.y - rotation.pivotY) * rotation.scaleY
  let rotatedX = rotation.pivotX + localX * cosAngle - localY * sinAngle
  let rotatedY = rotation.pivotY + localX * sinAngle + localY * cosAngle
  SkinnedMeshVertex(
    x: quantizeF32(vertex.x + (rotatedX - vertex.x) * rotation.opacity, "mesh.rotationDeformed.x"),
    y: quantizeF32(vertex.y + (rotatedY - vertex.y) * rotation.opacity, "mesh.rotationDeformed.y"),
    u: vertex.u,
    v: vertex.v,
  )


proc applyDeformer*(vertex: SkinnedMeshVertex; deformer: Deformer): SkinnedMeshVertex =
  validateSkinnedVertex(vertex, 0)
  validateDeformer(deformer)
  case deformer.kind
  of warpDeformerKind:
    applyWarp(vertex, deformer.warp)
  of rotationDeformerKind:
    applyRotation(vertex, deformer.rotation)


proc applyToPoint(point: DeformerPoint; deformer: Deformer): DeformerPoint =
  let vertex = applyDeformer(SkinnedMeshVertex(x: point.x, y: point.y), deformer)
  deformerPoint(vertex.x, vertex.y)


proc transformedBounds(lattice: WarpLattice; parent: Deformer): tuple[minX, minY, maxX, maxY: float64] =
  let corners = [
    applyToPoint(deformerPoint(lattice.minX, lattice.minY), parent),
    applyToPoint(deformerPoint(lattice.maxX, lattice.minY), parent),
    applyToPoint(deformerPoint(lattice.maxX, lattice.maxY), parent),
    applyToPoint(deformerPoint(lattice.minX, lattice.maxY), parent),
  ]
  result = (minX: corners[0].x, minY: corners[0].y, maxX: corners[0].x, maxY: corners[0].y)
  for index in 1 .. corners.high:
    result.minX = min(result.minX, corners[index].x)
    result.minY = min(result.minY, corners[index].y)
    result.maxX = max(result.maxX, corners[index].x)
    result.maxY = max(result.maxY, corners[index].y)


proc transformFrame(deformer, parent: Deformer): Deformer =
  case deformer.kind
  of warpDeformerKind:
    var points: seq[DeformerPoint]
    for point in deformer.warp.controlPoints:
      points.add applyToPoint(point, parent)
    let bounds = transformedBounds(deformer.warp, parent)
    result = warpDeformer(
      deformer.id,
      warpLattice(deformer.warp.rows, deformer.warp.cols, bounds.minX, bounds.minY, bounds.maxX, bounds.maxY, points),
      deformer.parent,
      deformer.order,
    )
  of rotationDeformerKind:
    let pivot = applyToPoint(deformerPoint(deformer.rotation.pivotX, deformer.rotation.pivotY), parent)
    result = rotationDeformerNode(
      deformer.id,
      rotationDeformer(pivot.x, pivot.y, deformer.rotation.angleDegrees, deformer.rotation.scaleX, deformer.rotation.scaleY, deformer.rotation.opacity),
      deformer.parent,
      deformer.order,
    )


proc applyDeformers*(vertices: openArray[SkinnedMeshVertex]; deformers: openArray[Deformer]): seq[SkinnedMeshVertex] =
  let ordered = orderedDeformers(deformers)
  for index, vertex in vertices:
    validateSkinnedVertex(vertex, index)
  let setup = @vertices
  result = @vertices
  var effectiveById = initTable[string, Deformer]()
  for deformer in ordered:
    let effective =
      if deformer.parent.len == 0:
        deformer
      else:
        deformer.transformFrame(effectiveById[deformer.parent])
    for index, vertex in result:
      case effective.kind
      of warpDeformerKind:
        let u = (setup[index].x - deformer.warp.minX) / (deformer.warp.maxX - deformer.warp.minX)
        let v = (setup[index].y - deformer.warp.minY) / (deformer.warp.maxY - deformer.warp.minY)
        result[index] = applyWarpAt(vertex, effective.warp, u, v)
      of rotationDeformerKind:
        result[index] = applyRotation(vertex, effective.rotation)
    effectiveById[deformer.id] = effective
