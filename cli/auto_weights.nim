## Inverse-square bone-distance auto-weighting for mesh vertices.
##
## Given bone rest positions and mesh vertex world positions, assigns each
## vertex up to `maxInfluences` skin weights using the classic inverse-square
## distance heuristic:
##
##   raw_i = 1 / (dist(vertex, bone_i)^2 + epsilon)
##   weight_i = raw_i / sum(raw_j)
##
## then keeps the N heaviest influences and renormalizes so weights sum to 1.
##
## bind-space position for each influence:
##   bindX = vertexWorldX - boneWorldX
##   bindY = vertexWorldY - boneWorldY
##
## (Assumes bones have identity rotation at bind pose; holds for all current
## bony conformance rigs. A future v2 can accept full world transforms.)
##
## This is a clean-room implementation of standard textbook inverse-distance
## weighting (Shepard 1968). No third-party code or data.

import std/[algorithm, math]


const defaultEpsilon* = 1e-6
const defaultMaxInfluences* = 4


type
  AutoWeightsBone* = object
    name*: string
    worldX*: float64
    worldY*: float64

  AutoWeightsVertex* = object
    worldX*: float64
    worldY*: float64

  WeightedInfluence* = object
    bone*: string
    bindX*: float64
    bindY*: float64
    weight*: float64

  WeightedVertex* = object
    influences*: seq[WeightedInfluence]


proc autoWeightVertex*(
  bones: seq[AutoWeightsBone];
  vx, vy: float64;
  maxInfluences: int;
  epsilon: float64;
): WeightedVertex =
  if bones.len == 0:
    return

  var raw: seq[tuple[bone: int; w: float64]]
  for i, bone in bones:
    let dx = vx - bone.worldX
    let dy = vy - bone.worldY
    let d2 = dx * dx + dy * dy
    raw.add (bone: i, w: 1.0 / (d2 + epsilon))

  # Sort by weight descending, keep top N
  raw.sort proc(a, b: tuple[bone: int; w: float64]): int =
    if a.w > b.w: -1 elif a.w < b.w: 1 else: 0

  let keep = min(maxInfluences, raw.len)
  var total = 0.0
  for i in 0 ..< keep:
    total += raw[i].w

  for i in 0 ..< keep:
    let boneIndex = raw[i].bone
    let bone = bones[boneIndex]
    result.influences.add WeightedInfluence(
      bone: bone.name,
      bindX: vx - bone.worldX,
      bindY: vy - bone.worldY,
      weight: raw[i].w / total,
    )


proc autoWeightVertices*(
  bones: seq[AutoWeightsBone];
  vertices: seq[AutoWeightsVertex];
  maxInfluences = defaultMaxInfluences;
  epsilon = defaultEpsilon;
): seq[WeightedVertex] =
  result = newSeq[WeightedVertex](vertices.len)
  for i, v in vertices:
    result[i] = autoWeightVertex(bones, v.worldX, v.worldY, maxInfluences, epsilon)
