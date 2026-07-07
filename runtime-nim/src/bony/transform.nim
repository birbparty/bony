## Transform facade plus helper geometry queries.

import std/math

import bony/mesh/draw_batches
import bony/model
import bony/transform/affine
import bony/transform/runtime_constraints

export draw_batches
export runtime_constraints

const helperGeometryTolerance* = 1e-4

type
  HelperPoint* = object
    x*: float64
    y*: float64

  HelperPointPose* = object
    x*: float64
    y*: float64
    rotation*: float64

proc helperPoint*(x, y: float64): HelperPoint =
  HelperPoint(x: x, y: y)


proc slotBoneWorld(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  activeSkin: string;
): Affine2 =
  let activation = activeSkinMembership(data, activeSkin)
  for slot in data.slots:
    if slot.name == slotName:
      for boneIndex, bone in data.bones:
        if bone.name == slot.bone:
          if boneIndex >= worlds.len:
            raise newBonyLoadError(schemaViolation, "helper query world transform count does not match skeleton bones")
          if not activation.bones[boneIndex]:
            raise newBonyLoadError(unknownRequiredReference, "helper query slot is inactive: " & slotName)
          return worlds[boneIndex]
      raise newBonyLoadError(unknownRequiredReference, "helper query slot references unknown bone: " & slot.bone)
  raise newBonyLoadError(unknownRequiredReference, "helper query references unknown slot: " & slotName)


proc slotBoneWorld(data: SkeletonData; worlds: openArray[Affine2]; slotName: string): Affine2 =
  data.slotBoneWorld(worlds, slotName, "default")


proc worldPointAttachmentPose*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  attachmentName: string;
  activeSkin = "default";
): HelperPointPose =
  let world = data.slotBoneWorld(worlds, slotName, activeSkin)
  let resolvedAttachment = data.resolveSkinAttachmentTarget(activeSkin, slotName, attachmentName)
  let targetAttachment =
    if data.skins.len > 0: resolvedAttachment
    else: attachmentName
  for point in data.pointAttachments:
    if point.name == targetAttachment:
      let pos = transformPoint(world, point.x, point.y)
      return HelperPointPose(
        x: pos.x,
        y: pos.y,
        rotation: worldRotationDegrees(world) + point.rotation,
      )
  raise newBonyLoadError(unknownRequiredReference, "unknown point attachment: " & attachmentName)


proc worldBoundingBoxAttachmentPolygon*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  attachmentName: string;
  activeSkin = "default";
): seq[HelperPoint] =
  let world = data.slotBoneWorld(worlds, slotName, activeSkin)
  let resolvedAttachment = data.resolveSkinAttachmentTarget(activeSkin, slotName, attachmentName)
  let targetAttachment =
    if data.skins.len > 0: resolvedAttachment
    else: attachmentName
  for box in data.boundingBoxAttachments:
    if box.name == targetAttachment:
      let vertices = box.vertices
      for index in countup(0, vertices.len - 2, 2):
        let pos = transformPoint(world, vertices[index], vertices[index + 1])
        result.add HelperPoint(x: pos.x, y: pos.y)
      return
  raise newBonyLoadError(unknownRequiredReference, "unknown bounding-box attachment: " & attachmentName)


proc distanceToSegment(point, a, b: HelperPoint): float64 =
  let dx = b.x - a.x
  let dy = b.y - a.y
  let lengthSquared = dx * dx + dy * dy
  if lengthSquared <= basisEpsilon:
    return hypot(point.x - a.x, point.y - a.y)
  let rawT = ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared
  let t = min(1.0, max(0.0, rawT))
  let px = a.x + dx * t
  let py = a.y + dy * t
  hypot(point.x - px, point.y - py)


proc pointInHelperPolygon*(
  point: HelperPoint;
  polygon: openArray[HelperPoint];
  tolerance = helperGeometryTolerance;
): bool =
  if polygon.len < 3:
    raise newBonyLoadError(schemaViolation, "helper polygon must contain at least three points")
  for index in 0 ..< polygon.len:
    let a = polygon[index]
    let b = polygon[(index + 1) mod polygon.len]
    if distanceToSegment(point, a, b) <= tolerance:
      return true

  var inside = false
  var previous = polygon[^1]
  for current in polygon:
    let crossesY = (current.y > point.y) != (previous.y > point.y)
    if crossesY:
      let xAtY = (previous.x - current.x) * (point.y - current.y) / (previous.y - current.y) + current.x
      if point.x < xAtY:
        inside = not inside
    previous = current
  inside


proc pointerHitsPointTarget*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  attachmentName: string;
  x, y, hitRadius: float64;
  activeSkin = "default";
): bool =
  if hitRadius < 0.0:
    raise newBonyLoadError(schemaViolation, "point helper hit radius must be non-negative")
  let pose = data.worldPointAttachmentPose(worlds, slotName, attachmentName, activeSkin)
  hypot(x - pose.x, y - pose.y) <= hitRadius


proc pointerHitsBoundingBoxTarget*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotName: string;
  attachmentName: string;
  x, y: float64;
  activeSkin = "default";
): bool =
  let polygon = data.worldBoundingBoxAttachmentPolygon(worlds, slotName, attachmentName, activeSkin)
  pointInHelperPolygon(HelperPoint(x: x, y: y), polygon)
