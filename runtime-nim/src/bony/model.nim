## Immutable M1 SkeletonData model plus per-instance runtime shell.

import std/sets

type
  BonyLoadErrorKind* = enum
    schemaViolation,
    duplicateKey,
    unknownRequiredReference,
    orderingViolation,
    cycleDetected

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
    world*: Affine2
    width*: float64
    height*: float64

  SkeletonData* = object
    header: SkeletonHeader
    bones: seq[BoneData]
    slots: seq[SlotData]
    regions: seq[RegionAttachment]

  SkeletonInstance* = object
    data: ref SkeletonData


proc newBonyLoadError*(kind: BonyLoadErrorKind; message: string): ref BonyLoadError =
  new(result)
  result.kind = kind
  result.msg = message


proc skeletonHeader*(name, version: string): SkeletonHeader =
  SkeletonHeader(name: name, version: version)


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
    x: x,
    y: y,
    rotation: rotation,
    scaleX: scaleX,
    scaleY: scaleY,
    shearX: shearX,
    shearY: shearY,
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
  RegionAttachment(name: name, width: width, height: height)


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


proc skeletonData*(
  header: SkeletonHeader;
  bones: openArray[BoneData];
  slots: openArray[SlotData] = [];
  regions: openArray[RegionAttachment] = [];
): SkeletonData =
  validateSkeletonData(header, bones, slots, regions)
  result.header = header
  result.bones = @bones
  result.slots = @slots
  result.regions = @regions


proc validateSkeletonData*(data: SkeletonData) =
  validateSkeletonData(data.header, data.bones, data.slots, data.regions)


proc newSkeletonInstance*(data: ref SkeletonData): SkeletonInstance =
  validateSkeletonData(data[])
  SkeletonInstance(data: data)
