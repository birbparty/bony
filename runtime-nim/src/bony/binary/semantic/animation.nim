proc withTarget(timeline: BoneTimeline; target: string): BoneTimeline =
  case timeline.kind
  of inheritTimeline:
    boneTimeline(target, inheritTimeline, timeline.inheritKeys)
  of translateTimeline, scaleTimeline, shearTimeline:
    boneTimeline(target, timeline.kind, timeline.vectorKeys)
  else:
    boneTimeline(target, timeline.kind, timeline.scalarKeys)


proc withTarget(timeline: SlotTimeline; target: string): SlotTimeline =
  case timeline.kind
  of attachmentTimeline:
    slotTimeline(target, attachmentTimeline, timeline.attachmentKeys)
  of rgbaTimeline, rgbTimeline, alphaTimeline:
    slotTimeline(target, timeline.kind, timeline.colorKeys)
  of rgba2Timeline:
    slotTimeline(target, rgba2Timeline, timeline.color2Keys)
  of sequenceTimeline:
    slotTimeline(target, sequenceTimeline, timeline.sequenceKeys)


proc decodeAnimationObjects(
  objects: openArray[BnbObjectRecord];
  strings: BnbStringTable;
  skeleton: SkeletonData;
): seq[AnimationClip] =
  var currentName = ""
  var currentBoneTimelines: seq[BoneTimeline]
  var currentSlotTimelines: seq[SlotTimeline]
  var currentEventTimelines: seq[EventTimeline]
  var currentDrawOrderTimeline = DrawOrderTimeline()
  var currentDeformTimelines: seq[DeformTimeline]
  var seen = initHashSet[string]()
  var meshesByName = initTable[string, MeshAttachment]()
  for mesh in skeleton.meshAttachments:
    meshesByName[mesh.name] = mesh

  template flushAnimation() =
    if currentName.len > 0:
      if currentName in seen:
        raise newBonyLoadError(duplicateKey, "duplicate animation name: " & currentName)
      seen.incl(currentName)
      result.add animationClip(
        skeleton, currentName, currentBoneTimelines, currentSlotTimelines,
        drawOrderTimeline = currentDrawOrderTimeline,
        eventTimelines = currentEventTimelines,
        deformTimelines = currentDeformTimelines)
      currentName = ""
      currentBoneTimelines = @[]
      currentSlotTimelines = @[]
      currentEventTimelines = @[]
      currentDrawOrderTimeline = DrawOrderTimeline()
      currentDeformTimelines = @[]

  for record in objects:
    case record.typeKey
    of animationClipTypeKey:
      flushAnimation()
      let properties = record.propertyMap([nameKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeAnimationClipBnbScalars, properties, bonyAnimationClipScalarSpecs, strings, "animationClip")
      currentName = scalars.bnbScalarString(nameKey, "animationClip.name")
    of boneTimelineTypeKey:
      if currentName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb boneTimeline record without animationClip")
      let properties = record.propertyMap([boneIndexKey, boneTimelineKindKey, timelineKeysKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeBoneTimelineBnbScalars, properties, bonyBoneTimelineScalarSpecs, strings, "boneTimeline")
      let boneIndex = int(scalars.bnbScalarUint32(boneIndexKey, "boneTimeline.boneIndex"))
      if boneIndex < 0 or boneIndex >= skeleton.bones.len:
        raise newBonyLoadError(unknownRequiredReference, ".bnb boneTimeline boneIndex is out of range")
      if timelineKeysKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb boneTimeline.timelineKeys is required")
      let kind = boneTimelineKindFromTag(scalars.bnbScalarUint32(boneTimelineKindKey, "boneTimeline.kind"))
      currentBoneTimelines.add readBoneTimelineKeys(kind, properties[timelineKeysKey], "boneTimeline.timelineKeys").withTarget(skeleton.bones[boneIndex].name)
    of slotTimelineTypeKey:
      if currentName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb slotTimeline record without animationClip")
      let properties = record.propertyMap([slotIndexKey, slotTimelineKindKey, timelineKeysKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSlotTimelineBnbScalars, properties, bonySlotTimelineScalarSpecs, strings, "slotTimeline")
      let slotIndex = int(scalars.bnbScalarUint32(slotIndexKey, "slotTimeline.slotIndex"))
      if slotIndex < 0 or slotIndex >= skeleton.slots.len:
        raise newBonyLoadError(unknownRequiredReference, ".bnb slotTimeline slotIndex is out of range")
      if timelineKeysKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb slotTimeline.timelineKeys is required")
      let kind = slotTimelineKindFromTag(scalars.bnbScalarUint32(slotTimelineKindKey, "slotTimeline.kind"))
      currentSlotTimelines.add readSlotTimelineKeys(kind, properties[timelineKeysKey], skeleton.regions, "slotTimeline.timelineKeys").withTarget(skeleton.slots[slotIndex].name)
    of eventTimelineTypeKey:
      if currentName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb eventTimeline record without animationClip")
      let properties = record.propertyMap([eventKeysKey])
      if eventKeysKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb eventTimeline.eventKeys is required")
      let keys = readEventKeys(properties[eventKeysKey], strings, "eventTimeline.eventKeys")
      currentEventTimelines.add eventTimeline(keys)
    of drawOrderTimelineTypeKey:
      if currentName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb drawOrderTimeline record without animationClip")
      if currentDrawOrderTimeline.keys.len > 0:
        raise newBonyLoadError(duplicateKey, ".bnb animationClip contains duplicate drawOrderTimeline records")
      let properties = record.propertyMap([drawOrderKeysKey])
      if drawOrderKeysKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb drawOrderTimeline.drawOrderKeys is required")
      currentDrawOrderTimeline = readDrawOrderKeys(properties[drawOrderKeysKey], skeleton.slots, "drawOrderTimeline.drawOrderKeys")
    of deformTimelineTypeKey:
      if currentName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb deformTimeline record without animationClip")
      let properties = record.propertyMap([deformSkinKey, slotKey, deformAttachmentKey, deformVertexCountKey, deformKeysKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeDeformTimelineBnbScalars, properties, bonyDeformTimelineScalarSpecs, strings, "deformTimeline")
      let skin = scalars.bnbScalarString(deformSkinKey, "deformTimeline.skin")
      let slot = scalars.bnbScalarString(slotKey, "deformTimeline.slot")
      let attachment = scalars.bnbScalarString(deformAttachmentKey, "deformTimeline.attachment")
      let vertexCount = int(scalars.bnbScalarUint32(deformVertexCountKey, "deformTimeline.vertexCount"))
      if deformKeysKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb deformTimeline.deformKeys is required")
      if not skeleton.hasSkin(skin):
        raise newBonyLoadError(unknownRequiredReference, ".bnb deformTimeline references unknown skin: " & skin)
      let resolvedAttachment = skeleton.resolveSkinAttachmentTarget(skin, slot, attachment)
      if resolvedAttachment.len == 0:
        raise newBonyLoadError(unknownRequiredReference,
          ".bnb deformTimeline does not resolve through skin lookup: " & skin & "/" & slot & "/" & attachment)
      if resolvedAttachment notin meshesByName:
        raise newBonyLoadError(unknownRequiredReference,
          ".bnb deformTimeline references non-mesh or unknown target: " & resolvedAttachment)
      let mesh = meshesByName[resolvedAttachment]
      if vertexCount != mesh.vertices.len:
        raise newBonyLoadError(schemaViolation, ".bnb deformTimeline vertex count does not match mesh: " & resolvedAttachment)
      let keys = readDeformKeys(properties[deformKeysKey], "deformTimeline.deformKeys")
      currentDeformTimelines.add deformTimeline(skin, slot, attachment, mesh, keys)
    of stateMachineTypeKey:
      flushAnimation()
    else:
      discard
  flushAnimation()
