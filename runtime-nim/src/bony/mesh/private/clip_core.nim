## Shared Sutherland-Hodgman clipping primitives for mesh-space and draw-batch
## clipping. Vertex-specific modules provide interpolation/quantization.

const clipEpsilon* = 1e-9

type
  ClipPoint* = object
    x*: float64
    y*: float64

  IntersectionHit = object
    parallel: bool
    t: float64


proc clipPoint*(x, y: float64): ClipPoint =
  ClipPoint(x: x, y: y)


proc crossZ*(ax, ay, bx, by: float64): float64 =
  ax * by - ay * bx


proc signedArea*[P](polygon: openArray[P]): float64 =
  for index, point in polygon:
    let next = polygon[(index + 1) mod polygon.len]
    result += point.x * next.y - next.x * point.y
  result * 0.5


proc inside*[V, P](point: V; a, b: P; orientation: float64): bool =
  let side = crossZ(b.x - a.x, b.y - a.y, point.x - a.x, point.y - a.y)
  if orientation > 0.0:
    side >= -clipEpsilon
  else:
    side <= clipEpsilon


proc vertexInsideClip*[V, P](vertex: V; clip: openArray[P]; orientation: float64): bool =
  ## True when a single vertex is inside every clip edge.
  for edgeIndex in 0 ..< clip.len:
    let a = clip[edgeIndex]
    let b = clip[(edgeIndex + 1) mod clip.len]
    if not inside(vertex, a, b, orientation):
      return false
  true


proc allInside*[V, P](subject: openArray[V]; clip: openArray[P]; orientation: float64): bool =
  ## True when every subject vertex is inside every clip edge.
  for vertex in subject:
    if not vertexInsideClip(vertex, clip, orientation):
      return false
  true


proc intersectionHit[V, P](start, finish: V; a, b: P): IntersectionHit =
  let rx = finish.x - start.x
  let ry = finish.y - start.y
  let sx = b.x - a.x
  let sy = b.y - a.y
  let denom = crossZ(rx, ry, sx, sy)
  if abs(denom) <= clipEpsilon:
    return IntersectionHit(parallel: true, t: 1.0)
  IntersectionHit(
    parallel: false,
    t: crossZ(a.x - start.x, a.y - start.y, sx, sy) / denom,
  )


proc clipConvex*[V, P](
  subject: openArray[V];
  clip: openArray[P];
  orientation: float64;
  lerp: proc(start, finish: V; t: float64; parallel: bool): V;
): seq[V] =
  ## Clip `subject` against a pre-validated convex `clip` polygon. Callers own
  ## `clip.len >= 3`, non-zero area, convexity validation, and must pass
  ## `signedArea(clip)` as `orientation`. `lerp` owns vertex-format-specific
  ## interpolation and output quantization, including near-parallel fallbacks.
  result = @subject
  for edgeIndex in 0 ..< clip.len:
    if result.len == 0:
      break
    let a = clip[edgeIndex]
    let b = clip[(edgeIndex + 1) mod clip.len]
    let input = result
    result = @[]
    var previous = input[^1]
    var previousInside = inside(previous, a, b, orientation)
    for current in input:
      let currentInside = inside(current, a, b, orientation)
      if currentInside:
        if not previousInside:
          let hit = intersectionHit(previous, current, a, b)
          result.add lerp(previous, current, hit.t, hit.parallel)
        result.add lerp(current, current, 1.0, false)
      elif previousInside:
        let hit = intersectionHit(previous, current, a, b)
        result.add lerp(previous, current, hit.t, hit.parallel)
      previous = current
      previousInside = currentInside
