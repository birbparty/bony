## Immutable M1 SkeletonData model plus per-instance runtime shell.

import std/[algorithm, math, sets, tables]

type
  BonyLoadErrorKind* = enum
    schemaViolation,
    numericOutOfRange,
    duplicateKey,
    unknownRequiredReference,
    orderingViolation,
    cycleDetected,
    truncatedInput,
    malformedVarint,
    invalidBackingType,
    resourceLimitExceeded

  BonyLoadError* = object of CatchableError
    kind*: BonyLoadErrorKind

  SkeletonHeader* = object
    name: string
    version: string

  TransformMode* = enum
    normal,
    onlyTranslation,
    noRotationOrReflection,
    noScale,
    noScaleOrReflection

  ConstraintKind* = enum
    ckIk,
    ckTransform,
    ckPath,
    ckPhysics

  PhysicsChannel* = enum
    ## Channels a physics constraint may drive. Ordinals define the wire
    ## bitmask bit positions (pcX=bit0 .. pcShearX=bit4). Defined here (not in
    ## constraints/physics_constraints.nim, which imports this module) so
    ## PhysicsConstraintData can hold a set[PhysicsChannel].
    pcX,
    pcY,
    pcRotate,
    pcScaleX,
    pcShearX

  LocalTransform* = object
    x: float64
    y: float64
    rotation: float64
    scaleX: float64
    scaleY: float64
    shearX: float64
    shearY: float64
    inheritRotation: bool
    inheritScale: bool
    inheritReflection: bool
    transformMode: TransformMode

  BoneData* = object
    name: string
    parent: string
    local: LocalTransform

  SlotData* = object
    name: string
    bone: string
    attachment: string

  RegionAttachment* = object
    name: string
    width: float64
    height: float64

  PathAttachmentData* = object
    name: string
    p0x: float64
    p0y: float64
    p1x: float64
    p1y: float64
    p2x: float64
    p2y: float64
    p3x: float64
    p3y: float64

  ClipAttachmentData* = object
    name: string
    vertices: seq[float64]
    untilSlot: string

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

  MeshDelta* = object
    ## A single per-vertex mesh offset applied by a deform timeline. Relocated
    ## here from mesh/deform.nim so both anim/timelines.nim (the DeformTimeline
    ## record home) and the transient deform override on SkeletonData can name it
    ## without an import cycle (model.nim sits below timelines.nim).
    x*: float64
    y*: float64

  PathConstraintData* = object
    name: string
    bone: string
    target: string
    path: string
    order: int
    hasPosition: bool
    position: float64
    hasTranslateMix: bool
    translateMix: float64
    hasRotateMix: bool
    rotateMix: float64

  IkConstraintData* = object
    name: string
    bones: seq[string]
    target: string
    order: int
    hasMix: bool
    mix: float64
    hasBendPositive: bool
    bendPositive: bool

  TransformConstraintData* = object
    name: string
    bone: string
    target: string
    order: int
    hasTranslateMix: bool
    translateMix: float64
    hasRotateMix: bool
    rotateMix: float64
    hasScaleMix: bool
    scaleMix: float64
    hasShearMix: bool
    shearMix: float64

  PhysicsConstraintData* = object
    ## Loadable physics constraint record (format/load only; not yet evaluated).
    ## Mirrors TransformConstraintData: a constrained bone, a signed order, and
    ## the integrator inputs consumed by physicsParams/updatePhysicsConstraint.
    ## Physics springs off the bone's own animated target, so there is NO target
    ## bone field. Each param carries a has* presence flag so an explicitly
    ## present default round-trips (see transformConstraintData for the contract).
    name: string
    bone: string
    order: int
    channels: set[PhysicsChannel]
    hasInertia: bool
    inertia: float64
    hasStrength: bool
    strength: float64
    hasDamping: bool
    damping: float64
    hasMass: bool
    mass: float64
    hasGravity: bool
    gravity: float64
    hasWind: bool
    wind: float64
    hasMix: bool
    mix: float64

  ParameterAxis* = object
    name*: string
    minValue*: float64
    maxValue*: float64
    defaultValue*: float64

  ParameterSample* = object
    name*: string
    value*: float64

  DeformerPoint* = object
    x*: float64
    y*: float64

  WarpLattice* = object
    rows*: uint32
    cols*: uint32
    minX*: float64
    minY*: float64
    maxX*: float64
    maxY*: float64
    controlPoints*: seq[DeformerPoint]

  RotationDeformer* = object
    pivotX*: float64
    pivotY*: float64
    angleDegrees*: float64
    scaleX*: float64
    scaleY*: float64
    opacity*: float64

  DeformerKind* = enum
    warpDeformerKind,
    rotationDeformerKind

  Deformer* = object
    id*: string
    parent*: string
    order*: uint32
    case kind*: DeformerKind
    of warpDeformerKind:
      warp*: WarpLattice
    of rotationDeformerKind:
      rotation*: RotationDeformer

  Keyform* = object
    coordinates*: seq[ParameterSample]
    values*: seq[float64]

  KeyformBlend* = object
    axes*: seq[ParameterAxis]
    valueCount*: int
    keyforms*: seq[Keyform]

  DeformerRecord* = object
    deformer*: Deformer
    keyformBlend*: KeyformBlend

  ConstraintOrderEntry* = object
    kind*: ConstraintKind
    order*: int
    sourceIndex*: int

  DrawVertex* = object
    x*: float64
    y*: float64
    u*: float64
    v*: float64
    r*: float64
    g*: float64
    b*: float64
    a*: float64

  Affine2* = object
    a*: float64
    b*: float64
    c*: float64
    d*: float64
    tx*: float64
    ty*: float64

  DrawBatch* = object
    slot*: string
    bone*: string
    attachment*: string
    texturePage*: string
    blendMode*: string
    clipId*: string
    world*: Affine2
    vertices*: seq[DrawVertex]
    indices*: seq[uint16]

  SkeletonData* = object
    header: SkeletonHeader
    bones: seq[BoneData]
    slots: seq[SlotData]
    regions: seq[RegionAttachment]
    pathAttachments: seq[PathAttachmentData]
    clippingAttachments: seq[ClipAttachmentData]
    meshAttachments: seq[MeshAttachment]
    paths: seq[PathConstraintData]
    ikConstraints: seq[IkConstraintData]
    transformConstraints: seq[TransformConstraintData]
    physicsConstraints: seq[PhysicsConstraintData]
    parameters: seq[ParameterAxis]
    deformers: seq[DeformerRecord]

  SkeletonInstance* = object
    data: ref SkeletonData


proc newBonyLoadError*(kind: BonyLoadErrorKind; message: string): ref BonyLoadError =
  new(result)
  result.kind = kind
  result.msg = message


proc skeletonHeader*(name, version: string): SkeletonHeader =
  SkeletonHeader(name: name, version: version)


proc quantizeF32*(value: float64; context = "value"): float64 =
  if classify(value) in {fcNan, fcInf, fcNegInf}:
    raise newBonyLoadError(numericOutOfRange, context & " must be a finite f32 value")
  result = float64(float32(value))
  if classify(result) in {fcNan, fcInf, fcNegInf}:
    raise newBonyLoadError(numericOutOfRange, context & " must fit in f32")


proc meshDelta*(x, y: float64): MeshDelta =
  MeshDelta(x: quantizeF32(x, "deform.delta.x"), y: quantizeF32(y, "deform.delta.y"))


proc requireFiniteF64*(value: float64; context = "value"): float64 =
  if classify(value) in {fcNan, fcInf, fcNegInf}:
    raise newBonyLoadError(numericOutOfRange, context & " must be finite")
  value


const weightSumTolerance* = 1e-4


proc quantizeUnit*(value: float64; context: string): float64 =
  result = quantizeF32(value, context)
  if result < 0.0 or result > 1.0:
    raise newBonyLoadError(schemaViolation, context & " must be in 0..1")


# Mesh geometry/reference validator. Lives here (not mesh/attachments) because
# validateSkeletonData must call it on every loaded mesh, and model cannot import
# mesh/* (the validator once took SkeletonData, forming a cycle). It takes the
# bone list directly so both the load path and the mesh constructor share ONE
# impl of the (a)-(g) edge-case checks.
proc validateMeshAttachment*(bones: openArray[BoneData]; mesh: MeshAttachment) =
  if mesh.name.len == 0:
    raise newBonyLoadError(schemaViolation, "mesh name must not be empty")
  if mesh.vertices.len == 0:
    raise newBonyLoadError(schemaViolation, "mesh must contain at least one vertex")
  if mesh.uvs.len != mesh.vertices.len:
    raise newBonyLoadError(schemaViolation, "mesh uvs count must match vertex count")
  for uv in mesh.uvs:
    discard quantizeUnit(uv.u, "mesh.uv.u")
    discard quantizeUnit(uv.v, "mesh.uv.v")
  if mesh.triangles.len == 0 or mesh.triangles.len mod 3 != 0:
    raise newBonyLoadError(schemaViolation, "mesh triangles must contain index triplets")
  if mesh.hull > uint32(mesh.vertices.len):
    raise newBonyLoadError(schemaViolation, "mesh hull must not exceed vertex count")
  if mesh.edges.len mod 2 != 0:
    raise newBonyLoadError(schemaViolation, "mesh edges must contain index pairs")
  if mesh.parentMesh.len != 0:
    raise newBonyLoadError(schemaViolation, "linked mesh parent validation is not supported yet")
  if mesh.deformAttachment.len != 0 and mesh.deformAttachment != mesh.name:
    raise newBonyLoadError(schemaViolation, "mesh deformAttachment must match the mesh name")

  var boneNames = initHashSet[string]()
  for bone in bones:
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
      if vertex.influences.len == 0:
        raise newBonyLoadError(schemaViolation, "weighted mesh vertex must contain at least one influence")
      var sum = 0.0
      for influence in vertex.influences:
        if influence.bone.len == 0:
          raise newBonyLoadError(schemaViolation, "mesh influence bone must not be empty")
        discard quantizeF32(influence.bindX, "mesh.influence.bindX")
        discard quantizeF32(influence.bindY, "mesh.influence.bindY")
        let weight = quantizeF32(influence.weight, "mesh.influence.weight")
        if weight < 0.0:
          raise newBonyLoadError(schemaViolation, "mesh influence weight must be non-negative")
        if influence.bone notin boneNames:
          raise newBonyLoadError(unknownRequiredReference, "unknown mesh influence bone: " & influence.bone)
        sum += weight
      if abs(sum - 1.0) > weightSumTolerance:
        raise newBonyLoadError(schemaViolation, "weighted mesh vertex influences must sum to 1")
    elif vertex.influences.len != 0:
      raise newBonyLoadError(schemaViolation, "unweighted mesh vertex must not contain influences")


proc localTransform*(
  x = 0.0,
  y = 0.0,
  rotation = 0.0,
  scaleX = 1.0,
  scaleY = 1.0,
  shearX = 0.0,
  shearY = 0.0,
  inheritRotation = true,
  inheritScale = true,
  inheritReflection = true,
  transformMode = normal,
): LocalTransform =
  LocalTransform(
    x: quantizeF32(x, "local.x"),
    y: quantizeF32(y, "local.y"),
    rotation: quantizeF32(rotation, "local.rotation"),
    scaleX: quantizeF32(scaleX, "local.scaleX"),
    scaleY: quantizeF32(scaleY, "local.scaleY"),
    shearX: quantizeF32(shearX, "local.shearX"),
    shearY: quantizeF32(shearY, "local.shearY"),
    inheritRotation: inheritRotation,
    inheritScale: inheritScale,
    inheritReflection: inheritReflection,
    transformMode: transformMode,
  )


proc boneData*(name, parent: string; local = localTransform()): BoneData =
  BoneData(name: name, parent: parent, local: local)


proc slotData*(name, bone, attachment: string): SlotData =
  SlotData(name: name, bone: bone, attachment: attachment)


proc regionAttachment*(name: string; width, height: float64): RegionAttachment =
  RegionAttachment(
    name: name,
    width: quantizeF32(width, "region.width"),
    height: quantizeF32(height, "region.height"),
  )


proc pathAttachmentData*(
  name: string;
  p0x, p0y, p1x, p1y, p2x, p2y, p3x, p3y: float64;
): PathAttachmentData =
  PathAttachmentData(
    name: name,
    p0x: requireFiniteF64(p0x, "pathAttachment.p0x"),
    p0y: requireFiniteF64(p0y, "pathAttachment.p0y"),
    p1x: requireFiniteF64(p1x, "pathAttachment.p1x"),
    p1y: requireFiniteF64(p1y, "pathAttachment.p1y"),
    p2x: requireFiniteF64(p2x, "pathAttachment.p2x"),
    p2y: requireFiniteF64(p2y, "pathAttachment.p2y"),
    p3x: requireFiniteF64(p3x, "pathAttachment.p3x"),
    p3y: requireFiniteF64(p3y, "pathAttachment.p3y"),
  )


proc clipAttachmentData*(
  name: string;
  vertices: openArray[float64];
  untilSlot = "";
): ClipAttachmentData =
  var quantized = newSeq[float64](vertices.len)
  for index, value in vertices:
    quantized[index] = quantizeF32(value, "clippingAttachment.vertices[" & $index & "]")
  ClipAttachmentData(name: name, vertices: quantized, untilSlot: untilSlot)


# Raw-value mesh constructor for loaders: assembles a MeshAttachment WITHOUT
# validating (mirrors clipAttachmentData). Loaders build seqs mid-parse and rely
# on skeletonData()/validateSkeletonData to run validateMeshAttachment once the
# whole skeleton is assembled.
proc meshAttachmentData*(
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
  MeshAttachment(
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


proc pathConstraintData*(
  name, bone, target, path: string;
  order = 0;
  hasPosition = false;
  position = 0.0;
  hasTranslateMix = false;
  translateMix = 1.0;
  hasRotateMix = false;
  rotateMix = 0.0;
): PathConstraintData =
  let storedPosition = quantizeF32(position, "path.position")
  let storedTranslateMix = quantizeF32(translateMix, "path.translateMix")
  let storedRotateMix = quantizeF32(rotateMix, "path.rotateMix")
  if storedPosition < 0.0 or storedPosition > 1.0:
    raise newBonyLoadError(schemaViolation, "path.position must be in [0, 1]")
  if storedTranslateMix < 0.0 or storedTranslateMix > 1.0:
    raise newBonyLoadError(schemaViolation, "path.translateMix must be in [0, 1]")
  if storedRotateMix < 0.0 or storedRotateMix > 1.0:
    raise newBonyLoadError(schemaViolation, "path.rotateMix must be in [0, 1]")
  PathConstraintData(
    name: name,
    bone: bone,
    target: target,
    path: path,
    order: order,
    hasPosition: hasPosition,
    position: storedPosition,
    hasTranslateMix: hasTranslateMix,
    translateMix: storedTranslateMix,
    hasRotateMix: hasRotateMix,
    rotateMix: storedRotateMix,
  )


proc ikConstraintData*(
  name, target: string;
  bones: seq[string];
  order = 0;
  hasMix = false;
  mix = 1.0;
  hasBendPositive = false;
  bendPositive = true;
): IkConstraintData =
  let storedMix = quantizeF32(mix, "ik.mix")
  if storedMix < 0.0 or storedMix > 1.0:
    raise newBonyLoadError(schemaViolation, "ik.mix must be in [0, 1]")
  IkConstraintData(
    name: name,
    bones: bones,
    target: target,
    order: order,
    hasMix: hasMix,
    mix: storedMix,
    hasBendPositive: hasBendPositive,
    bendPositive: bendPositive,
  )


proc transformConstraintData*(
  name, bone, target: string;
  order = 0;
  hasTranslateMix = false;
  translateMix = 1.0;
  hasRotateMix = false;
  rotateMix = 1.0;
  hasScaleMix = false;
  scaleMix = 1.0;
  hasShearMix = false;
  shearMix = 1.0;
): TransformConstraintData =
  ## Presence-flag contract (mirrors ikConstraintData/pathConstraintData): each
  ## mix value is stored as given, independent of its has* flag. Callers (the
  ## load path / serializer, bony-8i1.4) MUST set has*=true exactly when a value
  ## was explicitly present in the input and leave it at the 1.0 default when
  ## absent — a has*=false paired with a non-default value would be silently
  ## omitted by an omitWhenDefault serializer and corrupt the round-trip.
  let storedTranslateMix = quantizeF32(translateMix, "transformConstraint.translateMix")
  let storedRotateMix = quantizeF32(rotateMix, "transformConstraint.rotateMix")
  let storedScaleMix = quantizeF32(scaleMix, "transformConstraint.scaleMix")
  let storedShearMix = quantizeF32(shearMix, "transformConstraint.shearMix")
  for (mixName, mixValue) in {
    "translateMix": storedTranslateMix,
    "rotateMix": storedRotateMix,
    "scaleMix": storedScaleMix,
    "shearMix": storedShearMix,
  }:
    if mixValue < 0.0 or mixValue > 1.0:
      raise newBonyLoadError(schemaViolation, "transformConstraint." & mixName & " must be in [0, 1]")
  TransformConstraintData(
    name: name,
    bone: bone,
    target: target,
    order: order,
    hasTranslateMix: hasTranslateMix,
    translateMix: storedTranslateMix,
    hasRotateMix: hasRotateMix,
    rotateMix: storedRotateMix,
    hasScaleMix: hasScaleMix,
    scaleMix: storedScaleMix,
    hasShearMix: hasShearMix,
    shearMix: storedShearMix,
  )


proc physicsConstraintData*(
  name, bone: string;
  channels: set[PhysicsChannel];
  order = 0;
  hasInertia = false;
  inertia = 0.0;
  hasStrength = false;
  strength = 0.0;
  hasDamping = false;
  damping = 0.0;
  hasMass = false;
  mass = 1.0;
  hasGravity = false;
  gravity = 0.0;
  hasWind = false;
  wind = 0.0;
  hasMix = false;
  mix = 1.0;
): PhysicsConstraintData =
  ## Presence-flag contract mirrors transformConstraintData: each param is stored
  ## as given, f32-quantized (params are f32-backed per the physics contract), and
  ## the has* flag records explicit presence for round-trip fidelity. Param bounds
  ## replicate physicsParams (finite; mass non-negative; mix in [0, 1]) — model
  ## cannot import constraints/physics_constraints (that module imports model), so
  ## the bounds are single-sourced by the identical eval-time physicsParams call.
  if channels.card == 0:
    raise newBonyLoadError(schemaViolation, "physicsConstraint.channels must enable at least one channel")
  let storedInertia = quantizeF32(inertia, "physicsConstraint.inertia")
  let storedStrength = quantizeF32(strength, "physicsConstraint.strength")
  let storedDamping = quantizeF32(damping, "physicsConstraint.damping")
  let storedMass = quantizeF32(mass, "physicsConstraint.mass")
  let storedGravity = quantizeF32(gravity, "physicsConstraint.gravity")
  let storedWind = quantizeF32(wind, "physicsConstraint.wind")
  let storedMix = quantizeF32(mix, "physicsConstraint.physicsMix")
  if storedMass < 0.0:
    raise newBonyLoadError(schemaViolation, "physicsConstraint.mass must be non-negative")
  if storedMix < 0.0 or storedMix > 1.0:
    raise newBonyLoadError(schemaViolation, "physicsConstraint.physicsMix must be in [0, 1]")
  PhysicsConstraintData(
    name: name,
    bone: bone,
    order: order,
    channels: channels,
    hasInertia: hasInertia,
    inertia: storedInertia,
    hasStrength: hasStrength,
    strength: storedStrength,
    hasDamping: hasDamping,
    damping: storedDamping,
    hasMass: hasMass,
    mass: storedMass,
    hasGravity: hasGravity,
    gravity: storedGravity,
    hasWind: hasWind,
    wind: storedWind,
    hasMix: hasMix,
    mix: storedMix,
  )


proc name*(header: SkeletonHeader): string = header.name


proc version*(header: SkeletonHeader): string = header.version


proc name*(bone: BoneData): string = bone.name


proc parent*(bone: BoneData): string = bone.parent


proc local*(bone: BoneData): LocalTransform = bone.local


proc name*(slot: SlotData): string = slot.name


proc bone*(slot: SlotData): string = slot.bone


proc attachment*(slot: SlotData): string = slot.attachment


proc name*(region: RegionAttachment): string = region.name


proc width*(region: RegionAttachment): float64 = region.width


proc height*(region: RegionAttachment): float64 = region.height


proc name*(pathAttachment: PathAttachmentData): string = pathAttachment.name
proc p0x*(pathAttachment: PathAttachmentData): float64 = pathAttachment.p0x
proc p0y*(pathAttachment: PathAttachmentData): float64 = pathAttachment.p0y
proc p1x*(pathAttachment: PathAttachmentData): float64 = pathAttachment.p1x
proc p1y*(pathAttachment: PathAttachmentData): float64 = pathAttachment.p1y
proc p2x*(pathAttachment: PathAttachmentData): float64 = pathAttachment.p2x
proc p2y*(pathAttachment: PathAttachmentData): float64 = pathAttachment.p2y
proc p3x*(pathAttachment: PathAttachmentData): float64 = pathAttachment.p3x
proc p3y*(pathAttachment: PathAttachmentData): float64 = pathAttachment.p3y

proc name*(clip: ClipAttachmentData): string = clip.name
proc vertices*(clip: ClipAttachmentData): seq[float64] = clip.vertices
proc untilSlot*(clip: ClipAttachmentData): string = clip.untilSlot


proc name*(path: PathConstraintData): string = path.name
proc bone*(path: PathConstraintData): string = path.bone
proc target*(path: PathConstraintData): string = path.target
proc path*(path: PathConstraintData): string = path.path
proc order*(path: PathConstraintData): int = path.order
proc hasPosition*(path: PathConstraintData): bool = path.hasPosition
proc position*(path: PathConstraintData): float64 = path.position
proc hasTranslateMix*(path: PathConstraintData): bool = path.hasTranslateMix
proc translateMix*(path: PathConstraintData): float64 = path.translateMix
proc hasRotateMix*(path: PathConstraintData): bool = path.hasRotateMix
proc rotateMix*(path: PathConstraintData): float64 = path.rotateMix
proc runtimeEvaluable*(path: PathConstraintData): bool =
  path.hasPosition or path.hasTranslateMix or path.hasRotateMix


proc name*(ik: IkConstraintData): string = ik.name
proc bones*(ik: IkConstraintData): seq[string] = ik.bones
proc target*(ik: IkConstraintData): string = ik.target
proc order*(ik: IkConstraintData): int = ik.order
proc hasMix*(ik: IkConstraintData): bool = ik.hasMix
proc mix*(ik: IkConstraintData): float64 = ik.mix
proc hasBendPositive*(ik: IkConstraintData): bool = ik.hasBendPositive
proc bendPositive*(ik: IkConstraintData): bool = ik.bendPositive

proc runtimeEvaluable*(ik: IkConstraintData): bool =
  ## Constraint-only predicate, mirroring the path overload's purity (no
  ## skeleton access). Bone/target name resolution stays in the apply path,
  ## where boneIndexes() already raises/skips on unknown bones. An IK
  ## constraint contributes nothing when mix == 0 or it names no bones.
  ik.mix > 0.0 and ik.bones.len >= 1


proc name*(tc: TransformConstraintData): string = tc.name
proc bone*(tc: TransformConstraintData): string = tc.bone
proc target*(tc: TransformConstraintData): string = tc.target
proc order*(tc: TransformConstraintData): int = tc.order
proc hasTranslateMix*(tc: TransformConstraintData): bool = tc.hasTranslateMix
proc translateMix*(tc: TransformConstraintData): float64 = tc.translateMix
proc hasRotateMix*(tc: TransformConstraintData): bool = tc.hasRotateMix
proc rotateMix*(tc: TransformConstraintData): float64 = tc.rotateMix
proc hasScaleMix*(tc: TransformConstraintData): bool = tc.hasScaleMix
proc scaleMix*(tc: TransformConstraintData): float64 = tc.scaleMix
proc hasShearMix*(tc: TransformConstraintData): bool = tc.hasShearMix
proc shearMix*(tc: TransformConstraintData): float64 = tc.shearMix

proc runtimeEvaluable*(tc: TransformConstraintData): bool =
  ## Constraint-only predicate, mirroring the ik/path overloads. A transform
  ## constraint contributes nothing when every mix is zero (each channel blends
  ## the constrained pose fully toward itself). Used consistently in the
  ## detection gate, the update-cache read gating, and the apply guard.
  tc.translateMix > 0.0 or tc.rotateMix > 0.0 or tc.scaleMix > 0.0 or tc.shearMix > 0.0


proc name*(pc: PhysicsConstraintData): string = pc.name
proc bone*(pc: PhysicsConstraintData): string = pc.bone
proc order*(pc: PhysicsConstraintData): int = pc.order
proc channels*(pc: PhysicsConstraintData): set[PhysicsChannel] = pc.channels
proc hasInertia*(pc: PhysicsConstraintData): bool = pc.hasInertia
proc inertia*(pc: PhysicsConstraintData): float64 = pc.inertia
proc hasStrength*(pc: PhysicsConstraintData): bool = pc.hasStrength
proc strength*(pc: PhysicsConstraintData): float64 = pc.strength
proc hasDamping*(pc: PhysicsConstraintData): bool = pc.hasDamping
proc damping*(pc: PhysicsConstraintData): float64 = pc.damping
proc hasMass*(pc: PhysicsConstraintData): bool = pc.hasMass
proc mass*(pc: PhysicsConstraintData): float64 = pc.mass
proc hasGravity*(pc: PhysicsConstraintData): bool = pc.hasGravity
proc gravity*(pc: PhysicsConstraintData): float64 = pc.gravity
proc hasWind*(pc: PhysicsConstraintData): bool = pc.hasWind
proc wind*(pc: PhysicsConstraintData): float64 = pc.wind
proc hasMix*(pc: PhysicsConstraintData): bool = pc.hasMix
proc mix*(pc: PhysicsConstraintData): float64 = pc.mix

const physicsChannelMaskLimit = 1'u64 shl (ord(high(PhysicsChannel)) + 1)
  ## First bit value beyond the highest defined PhysicsChannel ordinal; any set
  ## bit at or above this is an unknown channel.

proc physicsChannelsToMask*(channels: set[PhysicsChannel]): uint64 =
  ## Pack an enabled-channel set into the wire bitmask (pcX=bit0 .. pcShearX=bit4).
  for channel in channels:
    result = result or (1'u64 shl ord(channel))

proc physicsChannelsFromMask*(mask: uint64; context = "physicsConstraint.channels"): set[PhysicsChannel] =
  ## Decode the wire bitmask into an enabled-channel set. Rejects unknown bits.
  ## Does NOT reject an empty set here; the "at least one channel" rule is checked
  ## by the record constructor / validator so the error names the constraint.
  if mask >= physicsChannelMaskLimit:
    raise newBonyLoadError(schemaViolation, context & " has unknown channel bits set")
  for channel in PhysicsChannel:
    if (mask and (1'u64 shl ord(channel))) != 0'u64:
      result.incl channel


proc x*(local: LocalTransform): float64 = local.x
proc y*(local: LocalTransform): float64 = local.y
proc rotation*(local: LocalTransform): float64 = local.rotation
proc scaleX*(local: LocalTransform): float64 = local.scaleX
proc scaleY*(local: LocalTransform): float64 = local.scaleY
proc shearX*(local: LocalTransform): float64 = local.shearX
proc shearY*(local: LocalTransform): float64 = local.shearY
proc inheritRotation*(local: LocalTransform): bool = local.inheritRotation
proc inheritScale*(local: LocalTransform): bool = local.inheritScale
proc inheritReflection*(local: LocalTransform): bool = local.inheritReflection
proc transformMode*(local: LocalTransform): TransformMode = local.transformMode


proc header*(data: SkeletonData): SkeletonHeader = data.header


proc bones*(data: SkeletonData): seq[BoneData] = data.bones


proc slots*(data: SkeletonData): seq[SlotData] = data.slots


proc regions*(data: SkeletonData): seq[RegionAttachment] = data.regions


proc pathAttachments*(data: SkeletonData): seq[PathAttachmentData] = data.pathAttachments


proc clippingAttachments*(data: SkeletonData): seq[ClipAttachmentData] = data.clippingAttachments


proc meshAttachments*(data: SkeletonData): seq[MeshAttachment] = data.meshAttachments


proc paths*(data: SkeletonData): seq[PathConstraintData] = data.paths


proc ikConstraints*(data: SkeletonData): seq[IkConstraintData] = data.ikConstraints


proc transformConstraints*(data: SkeletonData): seq[TransformConstraintData] = data.transformConstraints


proc physicsConstraints*(data: SkeletonData): seq[PhysicsConstraintData] = data.physicsConstraints


proc parameters*(data: SkeletonData): seq[ParameterAxis] = data.parameters


proc deformers*(data: SkeletonData): seq[DeformerRecord] = data.deformers


proc data*(instance: SkeletonInstance): ref SkeletonData = instance.data


proc modeForFlags*(inheritRotation, inheritScale, inheritReflection: bool): TransformMode =
  if inheritRotation and inheritScale and inheritReflection:
    normal
  elif (not inheritRotation) and (not inheritScale) and (not inheritReflection):
    onlyTranslation
  elif (not inheritRotation) and inheritScale and (not inheritReflection):
    noRotationOrReflection
  elif inheritRotation and (not inheritScale) and inheritReflection:
    noScale
  elif inheritRotation and (not inheritScale) and (not inheritReflection):
    noScaleOrReflection
  else:
    raise newBonyLoadError(schemaViolation, "invalid transform inherit flag triple")


proc checkDeformerAcyclic(
  id: string;
  parentById: Table[string, string];
  visiting, visited: var HashSet[string];
) =
  if id in visited:
    return
  if id in visiting:
    raise newBonyLoadError(cycleDetected, "deformer tree cycle detected")
  visiting.incl(id)
  let parent = parentById[id]
  if parent.len > 0:
    checkDeformerAcyclic(parent, parentById, visiting, visited)
  visiting.excl(id)
  visited.incl(id)


proc validateSkeletonData*(
  header: SkeletonHeader;
  bones: openArray[BoneData];
  slots: openArray[SlotData] = [];
  regions: openArray[RegionAttachment] = [];
  pathAttachments: openArray[PathAttachmentData] = [];
  paths: openArray[PathConstraintData] = [];
  parameters: openArray[ParameterAxis] = [];
  deformers: openArray[DeformerRecord] = [];
  ikConstraints: openArray[IkConstraintData] = [];
  transformConstraints: openArray[TransformConstraintData] = [];
  physicsConstraints: openArray[PhysicsConstraintData] = [];
  clippingAttachments: openArray[ClipAttachmentData] = [];
  meshAttachments: openArray[MeshAttachment] = [];
) =
  if header.name.len == 0:
    raise newBonyLoadError(schemaViolation, "skeleton.name must not be empty")

  var allNames = initHashSet[string]()
  var allRegionNames = initHashSet[string]()
  var allSlotNames = initHashSet[string]()
  for index, bone in bones:
    let context = "bones[" & $index & "]"
    if bone.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    discard modeForFlags(bone.local.inheritRotation, bone.local.inheritScale, bone.local.inheritReflection)
    if bone.local.transformMode != modeForFlags(
      bone.local.inheritRotation,
      bone.local.inheritScale,
      bone.local.inheritReflection,
    ):
      raise newBonyLoadError(schemaViolation, context & ".transformMode does not match inherit flags")
    if bone.name in allNames:
      raise newBonyLoadError(duplicateKey, "duplicate bone name: " & bone.name)
    allNames.incl(bone.name)

  var seen = initHashSet[string]()
  for index, bone in bones:
    if bone.parent.len > 0:
      if bone.parent notin allNames:
        raise newBonyLoadError(unknownRequiredReference, "unknown parent bone: " & bone.parent)
      if bone.parent notin seen:
        raise newBonyLoadError(orderingViolation, "bone parent must appear before child: " & bone.name)
    seen.incl(bone.name)

  for index, region in regions:
    let context = "regions[" & $index & "]"
    if region.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if region.width < 0 or region.height < 0:
      raise newBonyLoadError(schemaViolation, context & " dimensions must be non-negative")
    if region.name in allRegionNames:
      raise newBonyLoadError(duplicateKey, "duplicate region name: " & region.name)
    allRegionNames.incl(region.name)

  const clipAreaEpsilon = 1e-9
  var allClipNames = initHashSet[string]()
  for index, clip in clippingAttachments:
    let context = "clippingAttachments[" & $index & "]"
    if clip.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if clip.name in allClipNames:
      raise newBonyLoadError(duplicateKey, "duplicate clipping attachment name: " & clip.name)
    if clip.name in allRegionNames:
      raise newBonyLoadError(duplicateKey,
        "clipping attachment name collides with a region attachment name: " & clip.name)
    allClipNames.incl(clip.name)
    if clip.vertices.len < 6 or clip.vertices.len mod 2 != 0:
      raise newBonyLoadError(schemaViolation, context & ".vertices must contain at least three (x, y) pairs")
    for vIndex, value in clip.vertices:
      discard requireFiniteF64(value, context & ".vertices[" & $vIndex & "]")
    # Convex, non-zero-area invariants restated from mesh/clipping.nim
    # (validateConvexClip*): ≥3 vertices, non-zero signed area, uniform turn sign.
    let pointCount = clip.vertices.len div 2
    var area = 0.0
    for p in 0 ..< pointCount:
      let ax = clip.vertices[2 * p]
      let ay = clip.vertices[2 * p + 1]
      let nx = clip.vertices[2 * ((p + 1) mod pointCount)]
      let ny = clip.vertices[2 * ((p + 1) mod pointCount) + 1]
      area += ax * ny - nx * ay
    area = area * 0.5
    if abs(area) <= clipAreaEpsilon:
      raise newBonyLoadError(schemaViolation, context & ".vertices polygon area must be non-zero")
    let signValue = if area > 0.0: 1.0 else: -1.0
    for p in 0 ..< pointCount:
      let ax = clip.vertices[2 * p]
      let ay = clip.vertices[2 * p + 1]
      let bx = clip.vertices[2 * ((p + 1) mod pointCount)]
      let by = clip.vertices[2 * ((p + 1) mod pointCount) + 1]
      let cx = clip.vertices[2 * ((p + 2) mod pointCount)]
      let cy = clip.vertices[2 * ((p + 2) mod pointCount) + 1]
      let turn = (bx - ax) * (cy - by) - (by - ay) * (cx - bx)
      if turn * signValue < -clipAreaEpsilon:
        raise newBonyLoadError(schemaViolation, context & ".vertices must be convex in v1")

  # Mesh attachments: cross-collection unique non-empty names (must not collide
  # with region or clipping attachment names), then the shared (a)-(g) geometry
  # and bone-reference validation. Names join the slot->attachment accepted set
  # below so a slot may reference a mesh.
  var allMeshNames = initHashSet[string]()
  for index, mesh in meshAttachments:
    let context = "meshAttachments[" & $index & "]"
    if mesh.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if mesh.name in allMeshNames:
      raise newBonyLoadError(duplicateKey, "duplicate mesh attachment name: " & mesh.name)
    if mesh.name in allRegionNames:
      raise newBonyLoadError(duplicateKey,
        "mesh attachment name collides with a region attachment name: " & mesh.name)
    if mesh.name in allClipNames:
      raise newBonyLoadError(duplicateKey,
        "mesh attachment name collides with a clipping attachment name: " & mesh.name)
    allMeshNames.incl(mesh.name)
    validateMeshAttachment(bones, mesh)

  for index, slot in slots:
    let context = "slots[" & $index & "]"
    if slot.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if slot.name in allSlotNames:
      raise newBonyLoadError(duplicateKey, "duplicate slot name: " & slot.name)
    if slot.bone notin allNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown slot bone: " & slot.bone)
    if slot.attachment.len > 0 and slot.attachment notin allRegionNames and
        slot.attachment notin allClipNames and slot.attachment notin allMeshNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown slot attachment: " & slot.attachment)
    allSlotNames.incl(slot.name)

  # Clip range + no-overlap validation. A clip's range starts at the slot that
  # references it (via slot.attachment) and runs through untilSlot inclusive, or
  # to the end of draw order when untilSlot is empty. untilSlot must name a known
  # slot strictly after the clip's own slot (an at-or-before untilSlot, or an own
  # slot that is last, is a degenerate empty range). Ranges may not overlap: a
  # clip may not begin while another clip's range is still active.
  if clippingAttachments.len > 0:
    var slotIndexByName = initTable[string, int]()
    for index, slot in slots:
      slotIndexByName[slot.name] = index
    var clipByName = initTable[string, ClipAttachmentData]()
    for clip in clippingAttachments:
      clipByName[clip.name] = clip
      if clip.untilSlot.len > 0 and clip.untilSlot notin slotIndexByName:
        raise newBonyLoadError(unknownRequiredReference,
          "clipping attachment untilSlot names unknown slot: " & clip.untilSlot)
    let lastSlotIndex = slots.len - 1
    # Intervals are appended in draw order, so ownIndex is strictly ascending.
    var activeUntil = -1
    var activeName = ""
    for index, slot in slots:
      if slot.attachment.len == 0 or slot.attachment notin allClipNames:
        continue
      let clip = clipByName[slot.attachment]
      let ownIndex = index
      let endIndex =
        if clip.untilSlot.len > 0: slotIndexByName[clip.untilSlot]
        else: lastSlotIndex
      if endIndex <= ownIndex:
        raise newBonyLoadError(schemaViolation,
          "clipping attachment '" & slot.attachment & "' on slot '" & slot.name &
            "' has an empty range (untilSlot at or before the clip's own slot)")
      if ownIndex <= activeUntil:
        raise newBonyLoadError(schemaViolation,
          "clipping ranges overlap: '" & slot.attachment & "' begins while '" &
            activeName & "' is still active")
      activeUntil = endIndex
      activeName = slot.attachment

  var allPathAttachmentNames = initHashSet[string]()
  for index, pathAttachment in pathAttachments:
    let context = "pathAttachments[" & $index & "]"
    if pathAttachment.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if pathAttachment.name in allPathAttachmentNames:
      raise newBonyLoadError(duplicateKey, "duplicate path attachment name: " & pathAttachment.name)
    discard requireFiniteF64(pathAttachment.p0x, context & ".p0x")
    discard requireFiniteF64(pathAttachment.p0y, context & ".p0y")
    discard requireFiniteF64(pathAttachment.p1x, context & ".p1x")
    discard requireFiniteF64(pathAttachment.p1y, context & ".p1y")
    discard requireFiniteF64(pathAttachment.p2x, context & ".p2x")
    discard requireFiniteF64(pathAttachment.p2y, context & ".p2y")
    discard requireFiniteF64(pathAttachment.p3x, context & ".p3x")
    discard requireFiniteF64(pathAttachment.p3y, context & ".p3y")
    allPathAttachmentNames.incl(pathAttachment.name)

  var allPathNames = initHashSet[string]()
  for index, path in paths:
    let context = "paths[" & $index & "]"
    if path.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if path.name in allPathNames:
      raise newBonyLoadError(duplicateKey, "duplicate path constraint name: " & path.name)
    if path.bone notin allNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown path constraint bone: " & path.bone)
    if path.target notin allNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown path constraint target: " & path.target)
    if path.path notin allPathAttachmentNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown path constraint path: " & path.path)
    allPathNames.incl(path.name)

  var boneParentByName = initTable[string, string]()
  for bone in bones:
    boneParentByName[bone.name] = bone.parent

  var allIkNames = initHashSet[string]()
  for index, ik in ikConstraints:
    let context = "ikConstraints[" & $index & "]"
    if ik.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if ik.name in allIkNames:
      raise newBonyLoadError(duplicateKey, "duplicate ik constraint name: " & ik.name)
    if ik.bones.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".bones must not be empty")
    for boneName in ik.bones:
      if boneName notin allNames:
        raise newBonyLoadError(unknownRequiredReference, "unknown ik constraint bone: " & boneName)
    # The chain must be contiguous root->tip: each bone after the first is the
    # direct child of the preceding one. The solver FK-composes consecutive
    # origins, so a gapped chain has no well-defined geometry (and would surface
    # only as a confusing draw-time ordering error). Reject it cleanly here.
    for chainPos in 1 ..< ik.bones.len:
      if boneParentByName.getOrDefault(ik.bones[chainPos], "") != ik.bones[chainPos - 1]:
        raise newBonyLoadError(schemaViolation,
          context & ".bones must form a contiguous parent-to-child chain (root to tip): " &
          ik.bones[chainPos] & " is not a child of " & ik.bones[chainPos - 1])
    if ik.target notin allNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown ik constraint target: " & ik.target)
    allIkNames.incl(ik.name)

  var allTransformNames = initHashSet[string]()
  for index, tc in transformConstraints:
    let context = "transformConstraints[" & $index & "]"
    if tc.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if tc.name in allTransformNames:
      raise newBonyLoadError(duplicateKey, "duplicate transform constraint name: " & tc.name)
    if tc.bone notin allNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown transform constraint bone: " & tc.bone)
    if tc.target notin allNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown transform constraint target: " & tc.target)
    # Mixes are [0, 1] blend amounts (default 1.0); mirror requireMix in
    # constraints/transform_constraints.nim (finite, then range).
    for (mixName, mixValue) in {
      "translateMix": tc.translateMix,
      "rotateMix": tc.rotateMix,
      "scaleMix": tc.scaleMix,
      "shearMix": tc.shearMix,
    }:
      discard requireFiniteF64(mixValue, context & "." & mixName)
      if mixValue < 0.0 or mixValue > 1.0:
        raise newBonyLoadError(schemaViolation, context & "." & mixName & " must be in [0, 1]")
    allTransformNames.incl(tc.name)

  var allPhysicsNames = initHashSet[string]()
  for index, pc in physicsConstraints:
    let context = "physicsConstraints[" & $index & "]"
    if pc.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if pc.name in allPhysicsNames:
      raise newBonyLoadError(duplicateKey, "duplicate physics constraint name: " & pc.name)
    if pc.bone notin allNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown physics constraint bone: " & pc.bone)
    # Physics springs off the bone's own animated target, so there is NO target
    # bone reference to resolve (unlike ik/transform/path). Enabled-channel set
    # must be non-empty; params replicate physicsParams bounds (finite via
    # requireFiniteF64, mass non-negative, mix in [0, 1]).
    if pc.channels.card == 0:
      raise newBonyLoadError(schemaViolation, context & ".channels must enable at least one channel")
    for (paramName, paramValue) in {
      "inertia": pc.inertia,
      "strength": pc.strength,
      "damping": pc.damping,
      "mass": pc.mass,
      "gravity": pc.gravity,
      "wind": pc.wind,
      "physicsMix": pc.mix,
    }:
      discard requireFiniteF64(paramValue, context & "." & paramName)
    if pc.mass < 0.0:
      raise newBonyLoadError(schemaViolation, context & ".mass must be non-negative")
    if pc.mix < 0.0 or pc.mix > 1.0:
      raise newBonyLoadError(schemaViolation, context & ".physicsMix must be in [0, 1]")
    allPhysicsNames.incl(pc.name)

  var paramNames = initHashSet[string]()
  for index, param in parameters:
    let context = "parameters[" & $index & "]"
    if param.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if param.name in paramNames:
      raise newBonyLoadError(duplicateKey, "duplicate parameter name: " & param.name)
    paramNames.incl(param.name)
    if param.minValue >= param.maxValue:
      raise newBonyLoadError(schemaViolation, context & ": min must be less than max")
    if param.defaultValue < param.minValue or param.defaultValue > param.maxValue:
      raise newBonyLoadError(schemaViolation, context & ": default must be within min..max")

  var deformerIds = initHashSet[string]()
  var deformerOrders = initHashSet[uint32]()
  var deformerParentById = initTable[string, string]()
  var deformerOrderById = initTable[string, uint32]()
  for index, rec in deformers:
    let context = "deformers[" & $index & "]"
    if rec.deformer.id.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".id must not be empty")
    if rec.deformer.id in deformerIds:
      raise newBonyLoadError(duplicateKey, "duplicate deformer id: " & rec.deformer.id)
    if rec.deformer.order in deformerOrders:
      raise newBonyLoadError(schemaViolation, context & ": deformer order values must be unique")
    deformerIds.incl(rec.deformer.id)
    deformerOrders.incl(rec.deformer.order)
    deformerParentById[rec.deformer.id] = rec.deformer.parent
    deformerOrderById[rec.deformer.id] = rec.deformer.order

  for rec in deformers:
    let parent = rec.deformer.parent
    if parent.len > 0 and parent notin deformerIds:
      raise newBonyLoadError(unknownRequiredReference, "unknown deformer parent: " & parent)

  var dfVisiting = initHashSet[string]()
  var dfVisited = initHashSet[string]()
  for rec in deformers:
    checkDeformerAcyclic(rec.deformer.id, deformerParentById, dfVisiting, dfVisited)

  for rec in deformers:
    let parent = rec.deformer.parent
    if parent.len > 0 and deformerOrderById[parent] >= rec.deformer.order:
      raise newBonyLoadError(orderingViolation, "deformer parent must have an earlier global order")


proc skeletonData*(
  header: SkeletonHeader;
  bones: openArray[BoneData];
  slots: openArray[SlotData] = [];
  regions: openArray[RegionAttachment] = [];
  pathAttachments: openArray[PathAttachmentData] = [];
  paths: openArray[PathConstraintData] = [];
  parameters: openArray[ParameterAxis] = [];
  deformers: openArray[DeformerRecord] = [];
  ikConstraints: openArray[IkConstraintData] = [];
  transformConstraints: openArray[TransformConstraintData] = [];
  physicsConstraints: openArray[PhysicsConstraintData] = [];
  clippingAttachments: openArray[ClipAttachmentData] = [];
  meshAttachments: openArray[MeshAttachment] = [];
): SkeletonData =
  validateSkeletonData(
    header, bones, slots, regions, pathAttachments, paths, parameters, deformers, ikConstraints,
    transformConstraints, physicsConstraints, clippingAttachments, meshAttachments,
  )
  result.header = header
  result.bones = @bones
  result.slots = @slots
  result.regions = @regions
  result.pathAttachments = @pathAttachments
  result.clippingAttachments = @clippingAttachments
  result.meshAttachments = @meshAttachments
  result.paths = @paths
  result.parameters = @parameters
  result.deformers = @deformers
  result.ikConstraints = @ikConstraints
  result.transformConstraints = @transformConstraints
  result.physicsConstraints = @physicsConstraints


proc validateSkeletonData*(data: SkeletonData) =
  validateSkeletonData(
    data.header, data.bones, data.slots, data.regions, data.pathAttachments, data.paths,
    data.parameters, data.deformers, data.ikConstraints, data.transformConstraints,
    data.physicsConstraints, data.clippingAttachments, data.meshAttachments,
  )


proc constraintOrderEntry*(kind: ConstraintKind; order, sourceIndex: int): ConstraintOrderEntry =
  if sourceIndex < 0:
    raise newBonyLoadError(schemaViolation, "constraint sourceIndex must be non-negative")
  ConstraintOrderEntry(kind: kind, order: order, sourceIndex: sourceIndex)


proc constraintStageRank(kind: ConstraintKind): int =
  case kind
  of ckPhysics: 1
  else: 0


proc constraintKindRank(kind: ConstraintKind): int =
  case kind
  of ckIk: 0
  of ckTransform: 1
  of ckPath: 2
  of ckPhysics: 3


## Canonical sort order: stage (physics last) → order → kind (IK/transform/path/physics) → sourceIndex.
proc compareConstraintEntries*(left, right: ConstraintOrderEntry): int =
  result = cmp(constraintStageRank(left.kind), constraintStageRank(right.kind))
  if result != 0:
    return
  result = cmp(left.order, right.order)
  if result != 0:
    return
  result = cmp(constraintKindRank(left.kind), constraintKindRank(right.kind))
  if result != 0:
    return
  result = cmp(left.sourceIndex, right.sourceIndex)


proc canonicalConstraintOrder*(entries: openArray[ConstraintOrderEntry]): seq[ConstraintOrderEntry] =
  result = @entries
  result.sort(compareConstraintEntries)


proc newSkeletonInstance*(data: ref SkeletonData): SkeletonInstance =
  validateSkeletonData(data[])
  SkeletonInstance(data: data)
