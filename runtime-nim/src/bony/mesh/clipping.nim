## M4 convex polygon clipping for skinned mesh triangles.

import bony/mesh/skinning
import bony/model

const clipEpsilon = 1e-9

type
  ClipVertex* = object
    x*: float64
    y*: float64

  ClippedMesh* = object
    vertices*: seq[SkinnedMeshVertex]
    indices*: seq[uint16]


proc clipVertex*(x, y: float64): ClipVertex =
  ClipVertex(x: quantizeF32(x, "clip.x"), y: quantizeF32(y, "clip.y"))


proc clippedVertex(vertex: SkinnedMeshVertex): SkinnedMeshVertex =
  SkinnedMeshVertex(
    x: quantizeF32(vertex.x, "clip.vertex.x"),
    y: quantizeF32(vertex.y, "clip.vertex.y"),
    u: quantizeF32(vertex.u, "clip.vertex.u"),
    v: quantizeF32(vertex.v, "clip.vertex.v"),
  )


proc signedArea(vertices: openArray[ClipVertex]): float64 =
  for index, vertex in vertices:
    let next = vertices[(index + 1) mod vertices.len]
    result += vertex.x * next.y - next.x * vertex.y
  result * 0.5


proc cross(ax, ay, bx, by: float64): float64 =
  ax * by - ay * bx


proc validateConvexClip*(vertices: openArray[ClipVertex]) =
  if vertices.len < 3:
    raise newBonyLoadError(schemaViolation, "clip polygon must contain at least three vertices")
  let area = signedArea(vertices)
  if abs(area) <= clipEpsilon:
    raise newBonyLoadError(schemaViolation, "clip polygon area must be non-zero")
  let sign = if area > 0.0: 1.0 else: -1.0
  for index, vertex in vertices:
    let next = vertices[(index + 1) mod vertices.len]
    let following = vertices[(index + 2) mod vertices.len]
    let turn = cross(next.x - vertex.x, next.y - vertex.y, following.x - next.x, following.y - next.y)
    if turn * sign < -clipEpsilon:
      raise newBonyLoadError(schemaViolation, "clip polygon must be convex in v1")


proc inside(point: SkinnedMeshVertex; a, b: ClipVertex; orientation: float64): bool =
  let side = cross(b.x - a.x, b.y - a.y, point.x - a.x, point.y - a.y)
  if orientation > 0.0:
    side >= -clipEpsilon
  else:
    side <= clipEpsilon


proc intersection(start, finish: SkinnedMeshVertex; a, b: ClipVertex): SkinnedMeshVertex =
  let rx = finish.x - start.x
  let ry = finish.y - start.y
  let sx = b.x - a.x
  let sy = b.y - a.y
  let denom = cross(rx, ry, sx, sy)
  if abs(denom) <= clipEpsilon:
    return finish
  let t = cross(a.x - start.x, a.y - start.y, sx, sy) / denom
  SkinnedMeshVertex(
    x: quantizeF32(start.x + rx * t, "clip.vertex.x"),
    y: quantizeF32(start.y + ry * t, "clip.vertex.y"),
    u: quantizeF32(start.u + (finish.u - start.u) * t, "clip.vertex.u"),
    v: quantizeF32(start.v + (finish.v - start.v) * t, "clip.vertex.v"),
  )


proc clipPolygon(subject: seq[SkinnedMeshVertex]; clip: openArray[ClipVertex]; orientation: float64): seq[SkinnedMeshVertex] =
  result = subject
  for edgeIndex, a in clip:
    if result.len == 0:
      break
    let b = clip[(edgeIndex + 1) mod clip.len]
    let input = result
    result = @[]
    var previous = input[^1]
    var previousInside = previous.inside(a, b, orientation)
    for current in input:
      let currentInside = current.inside(a, b, orientation)
      if currentInside:
        if not previousInside:
          result.add intersection(previous, current, a, b)
        result.add clippedVertex(current)
      elif previousInside:
        result.add intersection(previous, current, a, b)
      previous = current
      previousInside = currentInside


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

  for triangleStart in countup(0, indices.len - 1, 3):
    let polygon = @[
      vertices[int(indices[triangleStart])],
      vertices[int(indices[triangleStart + 1])],
      vertices[int(indices[triangleStart + 2])],
    ].clipPolygon(clip, orientation)
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
