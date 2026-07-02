## M4 clipping of `DrawBatch` quads against a convex clip polygon.
##
## `DrawVertex` carries per-vertex color (r/g/b/a) that `SkinnedMeshVertex`
## lacks, so this restates the Sutherland-Hodgman convex-clip geometry from
## `mesh/clipping.nim` with r/g/b/a interpolation in addition to u/v. It is kept
## in its own module (rather than reusing `mesh/clipping.nim` directly) to avoid
## the `transform` -> `mesh/clipping` -> `mesh/skinning` -> `transform` import
## cycle, and so the public `clipTrianglesToConvexPolygon` signature and the
## shared `SkinnedMeshVertex` type stay untouched. The epsilon, orientation
## handling, edge-intersection math, fan re-triangulation (pivot on clipped
## vertex 0), and output-boundary `quantizeF32` all match `mesh/clipping.nim`
## and `docs/clipping-attachment-contract.md` exactly.

import bony/model

const clipEpsilon = 1e-9

type
  ClipPoint* = object
    x*: float64
    y*: float64

  DrawBatchClip* = object
    ## `changed = false` means the subject is fully inside the clip polygon and
    ## the caller must keep the batch's original vertices/indices untouched.
    ## `changed = true` means the batch was clipped; `vertices`/`indices` are the
    ## new (possibly empty, when fully outside) fan-triangulated geometry.
    changed*: bool
    vertices*: seq[DrawVertex]
    indices*: seq[uint16]


proc clipPoint*(x, y: float64): ClipPoint =
  ClipPoint(x: x, y: y)


proc crossZ(ax, ay, bx, by: float64): float64 =
  ax * by - ay * bx


proc signedArea(polygon: openArray[ClipPoint]): float64 =
  for index, point in polygon:
    let next = polygon[(index + 1) mod polygon.len]
    result += point.x * next.y - next.x * point.y
  result * 0.5


proc inside(point: DrawVertex; a, b: ClipPoint; orientation: float64): bool =
  let side = crossZ(b.x - a.x, b.y - a.y, point.x - a.x, point.y - a.y)
  if orientation > 0.0:
    side >= -clipEpsilon
  else:
    side <= clipEpsilon


proc quantized(vertex: DrawVertex): DrawVertex =
  DrawVertex(
    x: quantizeF32(vertex.x, "clip.batch.x"),
    y: quantizeF32(vertex.y, "clip.batch.y"),
    u: quantizeF32(vertex.u, "clip.batch.u"),
    v: quantizeF32(vertex.v, "clip.batch.v"),
    r: quantizeF32(vertex.r, "clip.batch.r"),
    g: quantizeF32(vertex.g, "clip.batch.g"),
    b: quantizeF32(vertex.b, "clip.batch.b"),
    a: quantizeF32(vertex.a, "clip.batch.a"),
  )


proc intersection(start, finish: DrawVertex; a, b: ClipPoint): DrawVertex =
  let rx = finish.x - start.x
  let ry = finish.y - start.y
  let sx = b.x - a.x
  let sy = b.y - a.y
  let denom = crossZ(rx, ry, sx, sy)
  if abs(denom) <= clipEpsilon:
    return quantized(finish)
  let t = crossZ(a.x - start.x, a.y - start.y, sx, sy) / denom
  quantized(DrawVertex(
    x: start.x + rx * t,
    y: start.y + ry * t,
    u: start.u + (finish.u - start.u) * t,
    v: start.v + (finish.v - start.v) * t,
    r: start.r + (finish.r - start.r) * t,
    g: start.g + (finish.g - start.g) * t,
    b: start.b + (finish.b - start.b) * t,
    a: start.a + (finish.a - start.a) * t,
  ))


proc clipSubject(subject: openArray[DrawVertex]; clip: openArray[ClipPoint];
                 orientation: float64): seq[DrawVertex] =
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
          result.add intersection(previous, current, a, b)
        result.add quantized(current)
      elif previousInside:
        result.add intersection(previous, current, a, b)
      previous = current
      previousInside = currentInside


proc allInside(subject: openArray[DrawVertex]; clip: openArray[ClipPoint];
               orientation: float64): bool =
  for edgeIndex in 0 ..< clip.len:
    let a = clip[edgeIndex]
    let b = clip[(edgeIndex + 1) mod clip.len]
    for vertex in subject:
      if not inside(vertex, a, b, orientation):
        return false
  true


proc clipDrawBatchPolygon*(subject: openArray[DrawVertex];
                           clip: openArray[ClipPoint]): DrawBatchClip =
  ## Clip a convex `DrawBatch` polygon (boundary order) against a convex clip
  ## polygon expressed in the same (world) space. A subject fully inside the clip
  ## is reported unchanged; otherwise the clipped polygon is fan-triangulated
  ## (pivot on vertex 0) with u/v and r/g/b/a interpolated at every clip-edge
  ## intersection and quantized at the output boundary. A subject fully outside
  ## yields an empty (0-vertex / 0-index) but `changed` result.
  if clip.len < 3 or subject.len < 3:
    return DrawBatchClip(changed: false)
  let orientation = signedArea(clip)
  if allInside(subject, clip, orientation):
    return DrawBatchClip(changed: false)
  let polygon = clipSubject(subject, clip, orientation)
  if polygon.len < 3:
    return DrawBatchClip(changed: true)
  result = DrawBatchClip(changed: true, vertices: polygon)
  for fanIndex in 1 ..< polygon.len - 1:
    result.indices.add 0'u16
    result.indices.add uint16(fanIndex)
    result.indices.add uint16(fanIndex + 1)
