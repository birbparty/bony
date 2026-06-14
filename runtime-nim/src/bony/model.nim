## Immutable M1 SkeletonData model plus per-instance runtime shell.

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
    name*: string
    version*: string

  BoneData* = object
    name*: string
    parent*: string

  SkeletonData* = object
    header*: SkeletonHeader
    bones*: seq[BoneData]

  SkeletonInstance* = object
    data*: ref SkeletonData


proc newBonyLoadError*(kind: BonyLoadErrorKind; message: string): ref BonyLoadError =
  new(result)
  result.kind = kind
  result.msg = message


proc newSkeletonInstance*(data: ref SkeletonData): SkeletonInstance =
  SkeletonInstance(data: data)
