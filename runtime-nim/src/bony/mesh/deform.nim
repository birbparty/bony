## M4 per-vertex mesh deform timeline sampling.
##
## The plain-data record types (`MeshDelta`, `DeformKeyframe`, `DeformTimeline`)
## and their constructors/validators were relocated up the import DAG so an
## `AnimationClip` can own deform timelines without a cycle: `MeshDelta` lives in
## `bony/model`, and `DeformKeyframe`/`DeformTimeline` (plus `deformKeyframe*`/
## `deformTimeline*`/`validateDeformTimeline*`) live in `bony/anim/timelines`.
## This module keeps the sampler/apply procs, which additionally depend on the
## skinned-mesh vertex type.

import bony/anim/timelines
import bony/mesh/skinning
import bony/model


proc zeroDeltas(vertexCount: int): seq[MeshDelta] =
  newSeq[MeshDelta](vertexCount)


proc writeKeyDeltas(output: var seq[MeshDelta]; key: DeformKeyframe) =
  for index, delta in key.deltas:
    output[int(key.offset) + index] = meshDelta(delta.x, delta.y)


proc expandedDeltas(key: DeformKeyframe; vertexCount: int): seq[MeshDelta] =
  result = zeroDeltas(vertexCount)
  result.writeKeyDeltas(key)


proc sampleDeformDeltas*(timeline: DeformTimeline; time: float64): seq[MeshDelta] =
  validateDeformTimeline(timeline)
  let storedTime = quantizeF32(time, "deform.sample.time")
  if storedTime < 0:
    raise newBonyLoadError(schemaViolation, "deform sample time must be non-negative")
  var index = 0
  while index < timeline.keys.len - 1 and storedTime >= timeline.keys[index + 1].time:
    inc index
  let current = timeline.keys[index]
  if index == timeline.keys.high or storedTime <= current.time:
    return expandedDeltas(current, timeline.vertexCount)

  let next = timeline.keys[index + 1]
  if current.curve.kind == steppedCurve:
    return expandedDeltas(current, timeline.vertexCount)

  let t = (storedTime - current.time) / (next.time - current.time)
  let eased = current.curve.evaluate(t)
  let a = expandedDeltas(current, timeline.vertexCount)
  let b = expandedDeltas(next, timeline.vertexCount)
  result = zeroDeltas(timeline.vertexCount)
  for vertexIndex in 0 ..< timeline.vertexCount:
    result[vertexIndex] = meshDelta(
      a[vertexIndex].x + (b[vertexIndex].x - a[vertexIndex].x) * eased,
      a[vertexIndex].y + (b[vertexIndex].y - a[vertexIndex].y) * eased,
    )


proc applyDeformDeltas*(
  vertices: openArray[SkinnedMeshVertex];
  deltas: openArray[MeshDelta];
): seq[SkinnedMeshVertex] =
  if vertices.len != deltas.len:
    raise newBonyLoadError(schemaViolation, "deform delta count must match skinned vertex count")
  result = newSeq[SkinnedMeshVertex](vertices.len)
  for index, vertex in vertices:
    result[index] = SkinnedMeshVertex(
      x: quantizeF32(vertex.x + deltas[index].x, "mesh.deformed.x"),
      y: quantizeF32(vertex.y + deltas[index].y, "mesh.deformed.y"),
      u: vertex.u,
      v: vertex.v,
    )


proc applyDeformTimeline*(
  vertices: openArray[SkinnedMeshVertex];
  mesh: MeshAttachment;
  timeline: DeformTimeline;
  time: float64;
): seq[SkinnedMeshVertex] =
  if mesh.deformAttachment != timeline.attachment:
    raise newBonyLoadError(schemaViolation, "deform timeline attachment does not match current mesh")
  if mesh.vertices.len != vertices.len:
    raise newBonyLoadError(schemaViolation, "deform mesh vertex count must match skinned vertex count")
  applyDeformDeltas(vertices, sampleDeformDeltas(timeline, time))
