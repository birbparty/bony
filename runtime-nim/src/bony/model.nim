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
    paths: seq[PathConstraintData]
    ikConstraints: seq[IkConstraintData]
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


proc requireFiniteF64*(value: float64; context = "value"): float64 =
  if classify(value) in {fcNan, fcInf, fcNegInf}:
    raise newBonyLoadError(numericOutOfRange, context & " must be finite")
  value


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


proc paths*(data: SkeletonData): seq[PathConstraintData] = data.paths


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

  for index, slot in slots:
    let context = "slots[" & $index & "]"
    if slot.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if slot.name in allSlotNames:
      raise newBonyLoadError(duplicateKey, "duplicate slot name: " & slot.name)
    if slot.bone notin allNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown slot bone: " & slot.bone)
    if slot.attachment.len > 0 and slot.attachment notin allRegionNames:
      raise newBonyLoadError(unknownRequiredReference, "unknown slot attachment: " & slot.attachment)
    allSlotNames.incl(slot.name)

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
): SkeletonData =
  validateSkeletonData(header, bones, slots, regions, pathAttachments, paths, parameters, deformers)
  result.header = header
  result.bones = @bones
  result.slots = @slots
  result.regions = @regions
  result.pathAttachments = @pathAttachments
  result.paths = @paths
  result.parameters = @parameters
  result.deformers = @deformers


proc validateSkeletonData*(data: SkeletonData) =
  validateSkeletonData(
    data.header, data.bones, data.slots, data.regions, data.pathAttachments, data.paths,
    data.parameters, data.deformers,
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
