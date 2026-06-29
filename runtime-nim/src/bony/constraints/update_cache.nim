## M5 deterministic ordered constraint update cache.

import std/[algorithm, tables]

import bony/model

type
  ConstraintCacheDescriptor* = object
    kind*: ConstraintKind
    order*: int
    sourceIndex*: int
    writes*: seq[string]
    reads*: seq[string]
    active*: bool

  ConstraintCacheEntryKind* = enum
    ccekBoneGroup,
    ccekConstraint

  ConstraintUpdateCacheEntry* = object
    case kind*: ConstraintCacheEntryKind
    of ccekBoneGroup:
      bones*: seq[int]
    of ccekConstraint:
      constraint*: ConstraintOrderEntry
      active*: bool


proc constraintCacheDescriptor*(
  kind: ConstraintKind;
  order, sourceIndex: int;
  writes: openArray[string];
  reads: openArray[string] = [];
  active = true;
): ConstraintCacheDescriptor =
  discard constraintOrderEntry(kind, order, sourceIndex)
  ConstraintCacheDescriptor(kind: kind, order: order, sourceIndex: sourceIndex, writes: @writes, reads: @reads, active: active)


proc parentIndexes(bones: openArray[BoneData]): seq[int] =
  var indexes = initTable[string, int]()
  result = newSeq[int](bones.len)
  for index, bone in bones:
    if bone.parent.len == 0:
      result[index] = -1
    else:
      if bone.parent notin indexes:
        raise newBonyLoadError(orderingViolation, "bone parent must appear before child: " & bone.name)
      result[index] = indexes[bone.parent]
    indexes[bone.name] = index


proc boneIndexByName(bones: openArray[BoneData]): Table[string, int] =
  for index, bone in bones:
    result[bone.name] = index


proc writeBoneIndexes(byName: Table[string, int]; writes: openArray[string]): seq[int] =
  for boneName in writes:
    if boneName notin byName:
      raise newBonyLoadError(unknownRequiredReference, "unknown constraint write bone: " & boneName)
    result.add byName[boneName]


proc readBoneIndexes(byName: Table[string, int]; reads: openArray[string]): seq[int] =
  for boneName in reads:
    if boneName notin byName:
      raise newBonyLoadError(unknownRequiredReference, "unknown constraint read bone: " & boneName)
    result.add byName[boneName]


proc emitBoneGroup(result: var seq[ConstraintUpdateCacheEntry]; bones: seq[int]) =
  if bones.len > 0:
    result.add ConstraintUpdateCacheEntry(kind: ccekBoneGroup, bones: bones)


proc emitReadDependencies(
  result: var seq[ConstraintUpdateCacheEntry];
  bones: openArray[BoneData];
  parents: openArray[int];
  byName: Table[string, int];
  writeBlockers: openArray[int];
  emitted: var seq[bool];
  reads: openArray[string];
  itemIndex: int;
) =
  var group: seq[int]
  for readIndex in readBoneIndexes(byName, reads):
    var lineage: seq[int]
    var cursor = readIndex
    while cursor >= 0:
      lineage.add cursor
      cursor = parents[cursor]
    lineage.reverse()
    for index in lineage:
      if index != readIndex and writeBlockers[index] >= itemIndex:
        raise newBonyLoadError(
          orderingViolation,
          "constraint read bone ancestor cannot be emitted before later write: " & bones[readIndex].name,
        )
      if not emitted[index]:
        group.add index
        emitted[index] = true
  result.emitBoneGroup(group)


proc buildConstraintUpdateCache*(
  bones: openArray[BoneData];
  descriptors: openArray[ConstraintCacheDescriptor];
): seq[ConstraintUpdateCacheEntry] =
  let parents = parentIndexes(bones)
  let byName = boneIndexByName(bones)
  var sortedEntries: seq[tuple[order: ConstraintOrderEntry; descriptor: ConstraintCacheDescriptor]]
  for descriptor in descriptors:
    let order = constraintOrderEntry(descriptor.kind, descriptor.order, descriptor.sourceIndex)
    if descriptor.kind != ckPhysics:
      sortedEntries.add (order: order, descriptor: descriptor)
  sortedEntries.sort(proc(left, right: tuple[order: ConstraintOrderEntry; descriptor: ConstraintCacheDescriptor]): int =
    compareConstraintEntries(left.order, right.order)
  )

  var writeBlockers = newSeq[int](bones.len)
  for index in 0 ..< writeBlockers.len:
    writeBlockers[index] = -1
  for constraintIndex, item in sortedEntries:
    for boneIndex in writeBoneIndexes(byName, item.descriptor.writes):
      writeBlockers[boneIndex] = max(writeBlockers[boneIndex], constraintIndex)

  var releaseAfter = newSeq[int](bones.len)
  for index in 0 ..< releaseAfter.len:
    releaseAfter[index] = writeBlockers[index]
    if parents[index] >= 0:
      releaseAfter[index] = max(releaseAfter[index], releaseAfter[parents[index]])

  var emitted = newSeq[bool](bones.len)
  for itemIndex, item in sortedEntries:
    result.emitReadDependencies(
      bones,
      parents,
      byName,
      writeBlockers,
      emitted,
      item.descriptor.reads,
      itemIndex,
    )
    var group: seq[int]
    for index in 0 ..< bones.len:
      if not emitted[index] and releaseAfter[index] < itemIndex:
        group.add index
        emitted[index] = true
    result.emitBoneGroup(group)
    result.add ConstraintUpdateCacheEntry(kind: ccekConstraint, constraint: item.order, active: item.descriptor.active)

  var finalGroup: seq[int]
  for index in 0 ..< bones.len:
    if not emitted[index]:
      finalGroup.add index
  result.emitBoneGroup(finalGroup)


proc buildPhysicsConstraintOrder*(descriptors: openArray[ConstraintCacheDescriptor]): seq[ConstraintOrderEntry] =
  for descriptor in descriptors:
    let order = constraintOrderEntry(descriptor.kind, descriptor.order, descriptor.sourceIndex)
    if descriptor.kind == ckPhysics:
      result.add order
  result.sort(compareConstraintEntries)


proc buildPathConstraintUpdateCache*(data: SkeletonData): seq[ConstraintUpdateCacheEntry] =
  var descriptors: seq[ConstraintCacheDescriptor]
  for index, path in data.paths:
    let reads = if path.runtimeEvaluable: @[path.target] else: @[]
    descriptors.add constraintCacheDescriptor(ckPath, path.order, index, [path.bone], reads = reads)
  buildConstraintUpdateCache(data.bones, descriptors)
