## Immutable M1 SkeletonData model plus per-instance runtime shell.

import std/[algorithm, math, sets]

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


proc pathConstraintData*(name, bone, target, path: string; order = 0): PathConstraintData =
  PathConstraintData(name: name, bone: bone, target: target, path: path, order: order)


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


proc validateSkeletonData*(
  header: SkeletonHeader;
  bones: openArray[BoneData];
  slots: openArray[SlotData] = [];
  regions: openArray[RegionAttachment] = [];
  pathAttachments: openArray[PathAttachmentData] = [];
  paths: openArray[PathConstraintData] = [];
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


proc skeletonData*(
  header: SkeletonHeader;
  bones: openArray[BoneData];
  slots: openArray[SlotData] = [];
  regions: openArray[RegionAttachment] = [];
  pathAttachments: openArray[PathAttachmentData] = [];
  paths: openArray[PathConstraintData] = [];
): SkeletonData =
  validateSkeletonData(header, bones, slots, regions, pathAttachments, paths)
  result.header = header
  result.bones = @bones
  result.slots = @slots
  result.regions = @regions
  result.pathAttachments = @pathAttachments
  result.paths = @paths


proc validateSkeletonData*(data: SkeletonData) =
  validateSkeletonData(data.header, data.bones, data.slots, data.regions, data.pathAttachments, data.paths)


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


proc canonicalConstraintOrder*(entries: openArray[ConstraintOrderEntry]): seq[ConstraintOrderEntry] =
  result = @entries
  result.sort(proc(left, right: ConstraintOrderEntry): int =
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
  )


proc newSkeletonInstance*(data: ref SkeletonData): SkeletonInstance =
  validateSkeletonData(data[])
  SkeletonInstance(data: data)
