## M4 linear-blend skinning for mesh setup vertices.

import std/tables

import bony/model

type
  MeshSkinningMethod* = enum
    linearBlendSkinning,
    dualQuaternionSkinningHook

  SkinnedMeshVertex* = object
    x*: float64
    y*: float64
    u*: float64
    v*: float64


## Skins mesh vertices using caller-provided world transforms.
## `worlds` must be ordered exactly like `data.bones`.
proc skinMeshVertices*(
  data: SkeletonData;
  worlds: openArray[Affine2];
  slotBone: string;
  mesh: MeshAttachment;
  skinningMethod = linearBlendSkinning;
): seq[SkinnedMeshVertex] =
  validateMeshAttachment(data.bones, mesh)
  if skinningMethod != linearBlendSkinning:
    raise newBonyLoadError(schemaViolation, "dual-quaternion skinning is a reserved hook in v1")
  if worlds.len != data.bones.len:
    raise newBonyLoadError(schemaViolation, "world transform count must match bone count")

  let boneIndex = boneIndexByName(data.bones)
  let slotBoneIndex =
    if mesh.weighted:
      -1
    elif slotBone in boneIndex:
      boneIndex[slotBone]
    else:
      raise newBonyLoadError(unknownRequiredReference, "unknown mesh slot bone: " & slotBone)
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
      let transformed = worlds[slotBoneIndex].transformPoint(vertex.x, vertex.y)
      x = transformed.x
      y = transformed.y
    result[vertexIndex] = SkinnedMeshVertex(
      x: quantizeF32(x, "mesh.skinned.x"),
      y: quantizeF32(y, "mesh.skinned.y"),
      u: quantizeF32(uv.u, "mesh.skinned.u"),
      v: quantizeF32(uv.v, "mesh.skinned.v"),
    )

# The two `computeWorldTransforms`-based convenience overloads live in
# `bony/transform` (which imports both `computeWorldTransforms` and this module),
# so `skinning` needs no dependency on `transform` and the former
# transform <-> skinning import cycle is gone.
