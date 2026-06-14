## M4 linear-blend skinning for mesh setup vertices.

import std/tables

import bony/mesh/attachments
import bony/model
import bony/transform

type
  MeshSkinningMethod* = enum
    linearBlendSkinning,
    dualQuaternionSkinningHook

  SkinnedMeshVertex* = object
    x*: float64
    y*: float64
    u*: float64
    v*: float64


proc transformPoint(world: Affine2; x, y: float64): tuple[x: float64, y: float64] =
  (
    x: world.a * x + world.c * y + world.tx,
    y: world.b * x + world.d * y + world.ty,
  )


proc boneIndexByName(data: SkeletonData): Table[string, int] =
  for index, bone in data.bones:
    result[bone.name] = index


proc skinMeshVertices*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotBone: string;
  mesh: MeshAttachment;
  skinningMethod = linearBlendSkinning;
): seq[SkinnedMeshVertex] =
  validateMeshAttachment(data, mesh)
  if skinningMethod != linearBlendSkinning:
    raise newBonyLoadError(schemaViolation, "dual-quaternion skinning is a reserved hook in v1")
  if worlds.len != data.bones.len:
    raise newBonyLoadError(schemaViolation, "world transform count must match bone count")

  let boneIndex = boneIndexByName(data)
  result = newSeq[SkinnedMeshVertex](mesh.vertices.len)
  for vertexIndex, vertex in mesh.vertices:
    let uv = mesh.uvs[vertexIndex]
    var x = 0.0
    var y = 0.0
    if vertex.weighted:
      for influence in vertex.influences:
        let transformed = worlds[boneIndex[influence.bone]].transformPoint(influence.bindX, influence.bindY)
        x += influence.weight * transformed.x
        y += influence.weight * transformed.y
    else:
      if slotBone notin boneIndex:
        raise newBonyLoadError(unknownRequiredReference, "unknown mesh slot bone: " & slotBone)
      let transformed = worlds[boneIndex[slotBone]].transformPoint(vertex.x, vertex.y)
      x = transformed.x
      y = transformed.y
    result[vertexIndex] = SkinnedMeshVertex(
      x: quantizeF32(x, "mesh.skinned.x"),
      y: quantizeF32(y, "mesh.skinned.y"),
      u: uv.u,
      v: uv.v,
    )


proc skinMeshVertices*(
  data: SkeletonData;
  slotBone: string;
  mesh: MeshAttachment;
  skinningMethod = linearBlendSkinning;
): seq[SkinnedMeshVertex] =
  skinMeshVertices(data, computeWorldTransforms(data), slotBone, mesh, skinningMethod)


proc skinMeshVertices*(
  data: SkeletonData;
  slot: SlotData;
  mesh: MeshAttachment;
  skinningMethod = linearBlendSkinning;
): seq[SkinnedMeshVertex] =
  skinMeshVertices(data, slot.bone, mesh, skinningMethod)
