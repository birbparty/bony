## M4 per-vertex mesh deform timeline sampling.

import bony/anim/timelines
import bony/mesh/skinning
import bony/model

type
  MeshDelta* = object
    x*: float64
    y*: float64

  DeformKeyframe* = object
    time*: float64
    offset*: uint32
    deltas*: seq[MeshDelta]
    curve*: TimelineCurve

  DeformTimeline* = object
    skin*: string
    slot*: string
    attachment*: string
    vertexCount*: int
    keys*: seq[DeformKeyframe]


proc meshDelta*(x, y: float64): MeshDelta =
  MeshDelta(x: quantizeF32(x, "deform.delta.x"), y: quantizeF32(y, "deform.delta.y"))


proc deformKeyframe*(
  time: float64;
  offset: uint32;
  deltas: openArray[MeshDelta];
  curve = linearTimelineCurve;
): DeformKeyframe =
  DeformKeyframe(
    time: quantizeF32(time, "deform.key.time"),
    offset: offset,
    deltas: @deltas,
    curve: curve,
  )


proc deformKeyframe*(
  time: float64;
  offset: uint32;
  deltas: openArray[MeshDelta];
  curve: TimelineCurveKind;
): DeformKeyframe =
  deformKeyframe(time, offset, deltas, timelineCurve(curve))


proc validateDeformKey(key: DeformKeyframe; vertexCount: int) =
  let storedTime = quantizeF32(key.time, "deform.key.time")
  if storedTime < 0:
    raise newBonyLoadError(schemaViolation, "deform key time must be non-negative")
  if key.deltas.len == 0:
    raise newBonyLoadError(schemaViolation, "deform key must contain at least one delta")
  if int(key.offset) + key.deltas.len > vertexCount:
    raise newBonyLoadError(schemaViolation, "deform key range exceeds mesh vertex count")
  for delta in key.deltas:
    discard quantizeF32(delta.x, "deform.delta.x")
    discard quantizeF32(delta.y, "deform.delta.y")


proc validateDeformTimeline*(timeline: DeformTimeline) =
  if timeline.skin.len == 0:
    raise newBonyLoadError(schemaViolation, "deform timeline skin must not be empty")
  if timeline.slot.len == 0:
    raise newBonyLoadError(schemaViolation, "deform timeline slot must not be empty")
  if timeline.attachment.len == 0:
    raise newBonyLoadError(schemaViolation, "deform timeline attachment must not be empty")
  if timeline.vertexCount <= 0:
    raise newBonyLoadError(schemaViolation, "deform timeline vertex count must be positive")
  if timeline.keys.len == 0:
    raise newBonyLoadError(schemaViolation, "deform timeline must contain at least one keyframe")
  for index, key in timeline.keys:
    validateDeformKey(key, timeline.vertexCount)
    if index > 0 and timeline.keys[index - 1].time >= key.time:
      raise newBonyLoadError(schemaViolation, "deform key times must be strictly increasing")


proc deformTimeline*(
  skin, slot: string;
  mesh: MeshAttachment;
  keys: openArray[DeformKeyframe];
): DeformTimeline =
  result = DeformTimeline(
    skin: skin,
    slot: slot,
    attachment: mesh.deformAttachment,
    vertexCount: mesh.vertices.len,
    keys: @keys,
  )
  validateDeformTimeline(result)


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
