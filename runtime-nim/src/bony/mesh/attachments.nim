## M4 mesh attachment setup geometry and bind data.

import bony/model

# The mesh record TYPES (MeshUv, MeshInfluence, MeshVertex, MeshAttachment), the
# raw meshAttachmentData constructor, the (a)-(g) validateMeshAttachment, and the
# quantizeUnit/weightSumTolerance helpers all live in bony/model: model cannot
# import mesh/* (cycle), yet validateSkeletonData must validate every loaded mesh,
# so the single shared impl lives in model. This module keeps the SkeletonData-
# validating convenience constructors used by tests and callers.


proc meshUv*(u, v: float64): MeshUv =
  MeshUv(u: quantizeUnit(u, "mesh.uv.u"), v: quantizeUnit(v, "mesh.uv.v"))


proc meshInfluence*(bone: string; bindX, bindY, weight: float64): MeshInfluence =
  if bone.len == 0:
    raise newBonyLoadError(schemaViolation, "mesh influence bone must not be empty")
  let storedWeight = quantizeF32(weight, "mesh.influence.weight")
  if storedWeight < 0.0:
    raise newBonyLoadError(schemaViolation, "mesh influence weight must be non-negative")
  MeshInfluence(
    bone: bone,
    bindX: quantizeF32(bindX, "mesh.influence.bindX"),
    bindY: quantizeF32(bindY, "mesh.influence.bindY"),
    weight: storedWeight,
  )


proc unweightedMeshVertex*(x, y: float64): MeshVertex =
  MeshVertex(weighted: false, x: quantizeF32(x, "mesh.vertex.x"), y: quantizeF32(y, "mesh.vertex.y"))


proc weightedMeshVertex*(influences: openArray[MeshInfluence]): MeshVertex =
  if influences.len == 0:
    raise newBonyLoadError(schemaViolation, "weighted mesh vertex must contain at least one influence")
  var sum = 0.0
  for influence in influences:
    sum += influence.weight
  if abs(sum - 1.0) > weightSumTolerance:
    raise newBonyLoadError(schemaViolation, "weighted mesh vertex influences must sum to 1")
  MeshVertex(weighted: true, influences: @influences)


proc meshAttachment*(
  data: SkeletonData;
  name: string;
  uvs: openArray[MeshUv];
  triangles: openArray[uint16];
  vertices: openArray[MeshVertex];
  weighted: bool;
  path = "";
  hull: uint32 = 0;
  edges: openArray[uint16] = [];
  parentMesh = "";
  inheritDeform = true;
  deformAttachment = "";
): MeshAttachment =
  ## Convenience constructor: assemble via the raw model ctor, then validate
  ## immediately against the skeleton's bones. Loaders that assemble mid-parse
  ## should call meshAttachmentData (no validation) and let validateSkeletonData
  ## validate once the whole skeleton exists.
  result = meshAttachmentData(
    name, uvs, triangles, vertices, weighted, path, hull, edges,
    parentMesh, inheritDeform, deformAttachment,
  )
  validateMeshAttachment(data.bones, result)


proc unweightedMeshAttachment*(
  data: SkeletonData;
  name: string;
  uvs: openArray[MeshUv];
  triangles: openArray[uint16];
  vertices: openArray[MeshVertex];
  path = "";
  hull: uint32 = 0;
  edges: openArray[uint16] = [];
): MeshAttachment =
  meshAttachment(data, name, uvs, triangles, vertices, false, path, hull, edges)


proc weightedMeshAttachment*(
  data: SkeletonData;
  name: string;
  uvs: openArray[MeshUv];
  triangles: openArray[uint16];
  vertices: openArray[MeshVertex];
  path = "";
  hull: uint32 = 0;
  edges: openArray[uint16] = [];
  parentMesh = "";
  inheritDeform = true;
  deformAttachment = "";
): MeshAttachment =
  meshAttachment(data, name, uvs, triangles, vertices, true, path, hull, edges, parentMesh, inheritDeform, deformAttachment)
