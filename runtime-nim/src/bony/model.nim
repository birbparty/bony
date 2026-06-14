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

  BoneData* = object
    name: string
    parent: string

  SkeletonData* = object
    header: SkeletonHeader
    bones: seq[BoneData]

  SkeletonInstance* = object
    data: ref SkeletonData


proc newBonyLoadError*(kind: BonyLoadErrorKind; message: string): ref BonyLoadError =
  new(result)
  result.kind = kind
  result.msg = message


proc skeletonHeader*(name, version: string): SkeletonHeader =
  SkeletonHeader(name: name, version: version)


proc boneData*(name, parent: string): BoneData =
  BoneData(name: name, parent: parent)


proc name*(header: SkeletonHeader): string = header.name


proc version*(header: SkeletonHeader): string = header.version


proc name*(bone: BoneData): string = bone.name


proc parent*(bone: BoneData): string = bone.parent


proc header*(data: SkeletonData): SkeletonHeader = data.header


proc bones*(data: SkeletonData): seq[BoneData] = data.bones


proc data*(instance: SkeletonInstance): ref SkeletonData = instance.data


proc validateSkeletonData*(header: SkeletonHeader; bones: openArray[BoneData]) =
  if header.name.len == 0:
    raise newBonyLoadError(schemaViolation, "skeleton.name must not be empty")

  var allNames = initHashSet[string]()
  for index, bone in bones:
    let context = "bones[" & $index & "]"
    if bone.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
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


proc skeletonData*(header: SkeletonHeader; bones: openArray[BoneData]): SkeletonData =
  validateSkeletonData(header, bones)
  result.header = header
  result.bones = @bones


proc validateSkeletonData*(data: SkeletonData) =
  validateSkeletonData(data.header, data.bones)


proc newSkeletonInstance*(data: ref SkeletonData): SkeletonInstance =
  validateSkeletonData(data[])
  SkeletonInstance(data: data)
