## M4 mesh attachment setup geometry and bind data.

import std/sets

import bony/model

const weightSumTolerance = 1e-4

type
  MeshUv* = object
    u*: float64
    v*: float64

  MeshInfluence* = object
    bone*: string
    bindX*: float64
    bindY*: float64
    weight*: float64

  MeshVertex* = object
    weighted*: bool
    x*: float64
    y*: float64
    influences*: seq[MeshInfluence]

  MeshAttachment* = object
    name*: string
    path*: string
    uvs*: seq[MeshUv]
    triangles*: seq[uint16]
    vertices*: seq[MeshVertex]
    weighted*: bool
    hull*: uint32
    edges*: seq[uint16]
    parentMesh*: string
    inheritDeform*: bool
    deformAttachment*: string


proc quantizeUnit(value: float64; context: string): float64 =
  result = quantizeF32(value, context)
  if result < 0.0 or result > 1.0:
    raise newBonyLoadError(schemaViolation, context & " must be in 0..1")


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


proc validateMeshAttachment*(data: SkeletonData; mesh: MeshAttachment) =
  if mesh.name.len == 0:
    raise newBonyLoadError(schemaViolation, "mesh name must not be empty")
  if mesh.vertices.len == 0:
    raise newBonyLoadError(schemaViolation, "mesh must contain at least one vertex")
  if mesh.uvs.len != mesh.vertices.len:
    raise newBonyLoadError(schemaViolation, "mesh uvs count must match vertex count")
  if mesh.triangles.len == 0 or mesh.triangles.len mod 3 != 0:
    raise newBonyLoadError(schemaViolation, "mesh triangles must contain index triplets")
  if mesh.hull > uint32(mesh.vertices.len):
    raise newBonyLoadError(schemaViolation, "mesh hull must not exceed vertex count")

  var boneNames = initHashSet[string]()
  for bone in data.bones:
    boneNames.incl(bone.name)

  for index in mesh.triangles:
    if int(index) >= mesh.vertices.len:
      raise newBonyLoadError(unknownRequiredReference, "mesh triangle index out of range")
  for index in mesh.edges:
    if int(index) >= mesh.vertices.len:
      raise newBonyLoadError(unknownRequiredReference, "mesh edge index out of range")
  for vertex in mesh.vertices:
    if vertex.weighted != mesh.weighted:
      raise newBonyLoadError(schemaViolation, "mesh vertices must match mesh weighted flag")
    if vertex.weighted:
      for influence in vertex.influences:
        if influence.bone notin boneNames:
          raise newBonyLoadError(unknownRequiredReference, "unknown mesh influence bone: " & influence.bone)
    elif vertex.influences.len != 0:
      raise newBonyLoadError(schemaViolation, "unweighted mesh vertex must not contain influences")


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
  result = MeshAttachment(
    name: name,
    path: if path.len == 0: name else: path,
    uvs: @uvs,
    triangles: @triangles,
    vertices: @vertices,
    weighted: weighted,
    hull: hull,
    edges: @edges,
    parentMesh: parentMesh,
    inheritDeform: inheritDeform,
    deformAttachment: if deformAttachment.len == 0: name else: deformAttachment,
  )
  validateMeshAttachment(data, result)


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
