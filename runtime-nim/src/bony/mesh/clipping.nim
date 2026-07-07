## M4 convex polygon clipping for skinned mesh triangles.

import bony/mesh/private/clip_core
import bony/mesh/skinning
import bony/model

type
  ClipVertex* = clip_core.ClipPoint

  ClippedMesh* = object
    vertices*: seq[SkinnedMeshVertex]
    indices*: seq[uint16]


proc clipVertex*(x, y: float64): ClipVertex =
  ClipVertex(x: quantizeF32(x, "clip.x"), y: quantizeF32(y, "clip.y"))


proc validateClipVertex(vertex: ClipVertex; index: int) =
  discard quantizeF32(vertex.x, "clip[" & $index & "].x")
  discard quantizeF32(vertex.y, "clip[" & $index & "].y")


proc validateSkinnedVertex(vertex: SkinnedMeshVertex; index: int) =
  discard quantizeF32(vertex.x, "clip.vertex[" & $index & "].x")
  discard quantizeF32(vertex.y, "clip.vertex[" & $index & "].y")
  discard quantizeF32(vertex.u, "clip.vertex[" & $index & "].u")
  discard quantizeF32(vertex.v, "clip.vertex[" & $index & "].v")


proc validateConvexClip*(vertices: openArray[ClipVertex]) =
  if vertices.len < 3:
    raise newBonyLoadError(schemaViolation, "clip polygon must contain at least three vertices")
  for index, vertex in vertices:
    validateClipVertex(vertex, index)
  let area = signedArea(vertices)
  if abs(area) <= clipEpsilon:
    raise newBonyLoadError(schemaViolation, "clip polygon area must be non-zero")
  let sign = if area > 0.0: 1.0 else: -1.0
  for index, vertex in vertices:
    let next = vertices[(index + 1) mod vertices.len]
    let following = vertices[(index + 2) mod vertices.len]
    let turn = crossZ(next.x - vertex.x, next.y - vertex.y, following.x - next.x, following.y - next.y)
    if turn * sign < -clipEpsilon:
      raise newBonyLoadError(schemaViolation, "clip polygon must be convex in v1")


proc lerpSkinnedVertex(start, finish: SkinnedMeshVertex; t: float64; parallel: bool): SkinnedMeshVertex =
  if parallel:
    return finish
  SkinnedMeshVertex(
    x: quantizeF32(start.x + (finish.x - start.x) * t, "clip.vertex.x"),
    y: quantizeF32(start.y + (finish.y - start.y) * t, "clip.vertex.y"),
    u: quantizeF32(start.u + (finish.u - start.u) * t, "clip.vertex.u"),
    v: quantizeF32(start.v + (finish.v - start.v) * t, "clip.vertex.v"),
  )


proc clipTrianglesToConvexPolygon*(
  vertices: openArray[SkinnedMeshVertex];
  indices: openArray[uint16];
  clip: openArray[ClipVertex];
): ClippedMesh =
  validateConvexClip(clip)
  if indices.len == 0 or indices.len mod 3 != 0:
    raise newBonyLoadError(schemaViolation, "clipped mesh indices must contain triangles")
  let orientation = signedArea(clip)
  for index in indices:
    if int(index) >= vertices.len:
      raise newBonyLoadError(unknownRequiredReference, "clipped mesh index out of range")
    validateSkinnedVertex(vertices[int(index)], int(index))

  for triangleStart in countup(0, indices.len - 1, 3):
    let polygon = @[
      vertices[int(indices[triangleStart])],
      vertices[int(indices[triangleStart + 1])],
      vertices[int(indices[triangleStart + 2])],
    ].clipConvex(clip, orientation, lerpSkinnedVertex)
    if polygon.len < 3:
      continue
    let base = result.vertices.len
    for vertex in polygon:
      if result.vertices.len > int(high(uint16)):
        raise newBonyLoadError(schemaViolation, "clipped mesh vertex count exceeds uint16 index range")
      result.vertices.add vertex
    for fanIndex in 1 ..< polygon.len - 1:
      result.indices.add uint16(base)
      result.indices.add uint16(base + fanIndex)
      result.indices.add uint16(base + fanIndex + 1)
