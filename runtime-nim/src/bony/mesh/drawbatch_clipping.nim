## M4 clipping of `DrawBatch` geometry against a convex clip polygon:
## `clipDrawBatchPolygon` clips a region quad as one convex boundary ring, and
## `clipDrawBatchTriangles` clips a mesh triangle *soup* per-triangle.
##
## `DrawVertex` carries per-vertex color (r/g/b/a) that `SkinnedMeshVertex`
## lacks, so this restates the Sutherland-Hodgman convex-clip geometry from
## `mesh/clipping.nim` with r/g/b/a interpolation in addition to u/v. It is kept
## in its own module (rather than reusing `mesh/clipping.nim` directly) so the
## public `clipTrianglesToConvexPolygon` signature and the shared
## `SkinnedMeshVertex` type stay untouched — clipping `DrawVertex` batches needs
## the color channels this restatement adds. (Historically this split also
## avoided a `transform` -> `mesh/clipping` -> `mesh/skinning` -> `transform`
## import cycle; that cycle no longer exists — iteration 181 dropped the
## `mesh/skinning -> transform` edge so `skinning` imports only `bony/model` —
## but the `DrawVertex`-vs-`SkinnedMeshVertex` type difference above independently
## justifies the separate module.) The epsilon, orientation
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


proc vertexInsideClip(vertex: DrawVertex; clip: openArray[ClipPoint];
                      orientation: float64): bool =
  ## True when a single vertex is inside *every* clip edge (i.e. inside the whole
  ## convex clip polygon). Distinct from `allInside`, which tests every vertex of
  ## a subject.
  for edgeIndex in 0 ..< clip.len:
    let a = clip[edgeIndex]
    let b = clip[(edgeIndex + 1) mod clip.len]
    if not inside(vertex, a, b, orientation):
      return false
  true


proc clipDrawBatchTriangles*(subject: openArray[DrawVertex];
                             indices: openArray[uint16];
                             clip: openArray[ClipPoint]): DrawBatchClip =
  ## Clip a triangle-*soup* `DrawBatch` (an explicit `indices` triangle list —
  ## e.g. a skinned mesh) against a convex clip polygon in the same (world) space.
  ## Unlike `clipDrawBatchPolygon`, which reinterprets `subject` as a single
  ## convex boundary ring, this clips **each triangle independently** so shared /
  ## interior vertices and non-boundary index order are preserved.
  ##
  ## Every referenced triangle `(indices[i], indices[i+1], indices[i+2])` is
  ## Sutherland-Hodgman clipped against `clip`; each surviving clipped convex
  ## polygon is fan-triangulated (pivot on its own clipped vertex 0) and appended
  ## to the output with u/v and r/g/b/a interpolated at every clip-edge
  ## intersection and quantized at the output boundary. Triangles clipped away
  ## entirely contribute nothing.
  ##
  ## `changed = false` (caller keeps the original `vertices`/`indices`) iff every
  ## referenced vertex is inside the clip polygon — no triangle would be cut.
  ## Otherwise `changed = true` and `vertices`/`indices` are the freshly
  ## re-triangulated per-triangle geometry (each triangle emits its own vertices,
  ## so shared vertices are duplicated across the triangles that use them, exactly
  ## as the region fan path duplicates a clipped polygon's boundary). A batch
  ## entirely outside the clip yields an empty (0-vertex / 0-index) `changed`
  ## result.
  ##
  ## Output vertices are `uint16`-indexed to match `DrawBatch.indices`; a mesh
  ## whose clipped fan would exceed 65535 output vertices is out of scope for v1
  ## (no conformance rig approaches that bound).
  if clip.len < 3 or indices.len < 3:
    return DrawBatchClip(changed: false)
  let orientation = signedArea(clip)
  # Fully-inside fast path: if no referenced vertex crosses the clip, no triangle
  # is cut, so the caller must keep the original vertices/indices untouched.
  var anyOutside = false
  var triangle = 0
  while triangle + 2 < indices.len:
    for corner in 0 .. 2:
      if not vertexInsideClip(subject[indices[triangle + corner]], clip, orientation):
        anyOutside = true
        break
    if anyOutside:
      break
    triangle += 3
  if not anyOutside:
    return DrawBatchClip(changed: false)
  result = DrawBatchClip(changed: true)
  triangle = 0
  while triangle + 2 < indices.len:
    let tri = [
      subject[indices[triangle]],
      subject[indices[triangle + 1]],
      subject[indices[triangle + 2]],
    ]
    triangle += 3
    let polygon = clipSubject(tri, clip, orientation)
    if polygon.len < 3:
      continue
    let base = uint16(result.vertices.len)
    for vtx in polygon:
      result.vertices.add vtx
    for fanIndex in 1 ..< polygon.len - 1:
      result.indices.add base
      result.indices.add base + uint16(fanIndex)
      result.indices.add base + uint16(fanIndex + 1)
