## M4 clipping of `DrawBatch` geometry against a convex clip polygon:
## `clipDrawBatchPolygon` clips a region quad as one convex boundary ring, and
## `clipDrawBatchTriangles` clips a mesh triangle *soup* per-triangle.
##
## This module shares the Sutherland-Hodgman geometry with `mesh/clipping.nim`
## through `mesh/clip_core.nim`; only `DrawVertex` interpolation, color-channel
## quantization, and draw-batch-specific bookkeeping live here. The epsilon,
## orientation handling, fan re-triangulation (pivot on clipped vertex 0), and
## output-boundary `quantizeF32` match `docs/clipping-attachment-contract.md`.

import bony/mesh/clip_core
import bony/model

type
  ClipPoint* = clip_core.ClipPoint

  DrawBatchClip* = object
    ## `changed = false` means the subject is fully inside the clip polygon and
    ## the caller must keep the batch's original vertices/indices untouched.
    ## `changed = true` means the batch was clipped; `vertices`/`indices` are the
    ## new (possibly empty, when fully outside) fan-triangulated geometry.
    changed*: bool
    vertices*: seq[DrawVertex]
    indices*: seq[uint16]


proc clipPoint*(x, y: float64): ClipPoint =
  clip_core.clipPoint(x, y)


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


proc lerpDrawVertex(start, finish: DrawVertex; t: float64): DrawVertex =
  quantized(DrawVertex(
    x: start.x + (finish.x - start.x) * t,
    y: start.y + (finish.y - start.y) * t,
    u: start.u + (finish.u - start.u) * t,
    v: start.v + (finish.v - start.v) * t,
    r: start.r + (finish.r - start.r) * t,
    g: start.g + (finish.g - start.g) * t,
    b: start.b + (finish.b - start.b) * t,
    a: start.a + (finish.a - start.a) * t,
  ))


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
  let polygon = clipConvex(subject, clip, orientation, lerpDrawVertex)
  if polygon.len < 3:
    return DrawBatchClip(changed: true)
  result = DrawBatchClip(changed: true, vertices: polygon)
  for fanIndex in 1 ..< polygon.len - 1:
    result.indices.add 0'u16
    result.indices.add uint16(fanIndex)
    result.indices.add uint16(fanIndex + 1)


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
    let polygon = clipConvex(tri, clip, orientation, lerpDrawVertex)
    if polygon.len < 3:
      continue
    let base = uint16(result.vertices.len)
    for vtx in polygon:
      result.vertices.add vtx
    for fanIndex in 1 ..< polygon.len - 1:
      result.indices.add base
      result.indices.add base + uint16(fanIndex)
      result.indices.add base + uint16(fanIndex + 1)
