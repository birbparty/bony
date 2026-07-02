## M6/M7 semantic .bnb encoder/decoder for the current SkeletonData model.

import std/[json, sets, strutils, tables]

import bony/anim/timelines
import bony/asset
import bony/binary/framing
import bony/generated/wire
import bony/model
import bony/deform/deformers
import bony/deform/keyforms
import bony/statemachine/core

const
  skeletonTypeKey = 1'u64
  boneTypeKey = 2'u64
  slotTypeKey = 1000'u64
  regionTypeKey = 1001'u64
  pathTypeKey = 4000'u64
  pathAttachmentTypeKey = 4001'u64
  ikConstraintTypeKey = 4002'u64
  transformConstraintTypeKey = 4003'u64
  physicsConstraintTypeKey = 4004'u64
  animationClipTypeKey = 2000'u64
  boneTimelineTypeKey = 2001'u64
  slotTimelineTypeKey = 2002'u64
  stateMachineTypeKey = 7000'u64
  stateMachineInputTypeKey = 7001'u64
  stateMachineLayerTypeKey = 7002'u64
  stateMachineStateTypeKey = 7003'u64
  stateMachineBlendClipTypeKey = 7004'u64
  stateMachineTransitionTypeKey = 7005'u64
  stateMachineConditionTypeKey = 7006'u64
  stateMachineListenerTypeKey = 7007'u64

  nameKey = 1'u64
  versionKey = 2'u64
  parentKey = 3'u64
  xKey = 1000'u64
  yKey = 1001'u64
  rotationKey = 1002'u64
  scaleXKey = 1003'u64
  scaleYKey = 1004'u64
  shearXKey = 1005'u64
  shearYKey = 1006'u64
  inheritRotationKey = 1007'u64
  inheritScaleKey = 1008'u64
  inheritReflectionKey = 1009'u64
  transformModeKey = 1010'u64
  boneKey = 1012'u64
  attachmentKey = 1013'u64
  widthKey = 1014'u64
  heightKey = 1015'u64
  targetKey = 4000'u64
  pathKey = 4001'u64
  orderKey = 4002'u64
  p0xKey = 4003'u64
  p0yKey = 4004'u64
  p1xKey = 4005'u64
  p1yKey = 4006'u64
  p2xKey = 4007'u64
  p2yKey = 4008'u64
  p3xKey = 4009'u64
  p3yKey = 4010'u64
  positionKey = 4011'u64
  translateMixKey = 4012'u64
  rotateMixKey = 4013'u64
  bonesKey = 4014'u64
  mixKey = 4015'u64
  bendPositiveKey = 4016'u64
  scaleMixKey = 4017'u64
  shearMixKey = 4018'u64
  inertiaKey = 4019'u64
  strengthKey = 4020'u64
  dampingKey = 4021'u64
  massKey = 4022'u64
  gravityKey = 4023'u64
  windKey = 4024'u64
  physicsMixKey = 4025'u64
  channelsKey = 4026'u64
  boneIndexKey = 2000'u64
  boneTimelineKindKey = 2001'u64
  slotIndexKey = 2002'u64
  slotTimelineKindKey = 2003'u64
  timelineKeysKey = 2004'u64
  stateMachineInputKindKey = 7000'u64
  inputDefaultBoolKey = 7001'u64
  inputDefaultNumberKey = 7002'u64
  initialStateIndexKey = 7010'u64
  stateMachineStateKindKey = 7020'u64
  stateClipIndexKey = 7021'u64
  stateLoopKey = 7022'u64
  stateBlendInputIndexKey = 7023'u64
  blendClipAnimationIndexKey = 7030'u64
  blendClipValueKey = 7031'u64
  blendClipLoopKey = 7032'u64
  transitionFromStateIndexKey = 7040'u64
  transitionToStateIndexKey = 7041'u64
  conditionInputIndexKey = 7050'u64
  stateMachineConditionKindKey = 7051'u64
  conditionBoolValueKey = 7052'u64
  conditionNumberValueKey = 7053'u64
  stateMachineListenerKindKey = 7060'u64
  listenerLayerIndexKey = 7061'u64
  listenerFromStateIndexKey = 7062'u64
  listenerToStateIndexKey = 7063'u64

  parameterTypeKey = 6000'u64
  deformerTypeKey = 6001'u64
  warpLatticeTypeKey = 6002'u64
  rotationDeformerTypeKey = 6003'u64
  keyformBlendTypeKey = 6004'u64
  keyformTypeKey = 6005'u64

  parameterMinKey = 6000'u64
  parameterMaxKey = 6001'u64
  parameterDefaultKey = 6002'u64
  deformerIdKey = 6010'u64
  deformerOrderKey = 6011'u64
  deformerKindKey = 6012'u64
  warpRowsKey = 6020'u64
  warpColsKey = 6021'u64
  warpMinXKey = 6022'u64
  warpMinYKey = 6023'u64
  warpMaxXKey = 6024'u64
  warpMaxYKey = 6025'u64
  warpControlPointsKey = 6026'u64
  rotationPivotXKey = 6030'u64
  rotationPivotYKey = 6031'u64
  rotationAngleDegreesKey = 6032'u64
  rotationScaleXKey = 6033'u64
  rotationScaleYKey = 6034'u64
  rotationOpacityKey = 6035'u64
  blendValueCountKey = 6040'u64
  blendAxesKey = 6041'u64
  blendCoordinatesKey = 6042'u64
  blendValuesKey = 6043'u64


proc defaultString(objectId, propertyId: string): string =
  for entry in bonyPropertyDefaults:
    if entry.objectId == objectId and entry.propertyId == propertyId:
      return parseJson(entry.value).getStr()
  raise newBonyLoadError(schemaViolation, "missing generated default for " & objectId & "." & propertyId)


proc defaultFloat(objectId, propertyId: string): float64 =
  for entry in bonyPropertyDefaults:
    if entry.objectId == objectId and entry.propertyId == propertyId:
      return parseJson(entry.value).getFloat()
  raise newBonyLoadError(schemaViolation, "missing generated default for " & objectId & "." & propertyId)


proc defaultBool(objectId, propertyId: string): bool =
  for entry in bonyPropertyDefaults:
    if entry.objectId == objectId and entry.propertyId == propertyId:
      return parseJson(entry.value).getBool()
  raise newBonyLoadError(schemaViolation, "missing generated default for " & objectId & "." & propertyId)


proc defaultInt(objectId, propertyId: string): int =
  for entry in bonyPropertyDefaults:
    if entry.objectId == objectId and entry.propertyId == propertyId:
      return entry.value.parseInt()
  raise newBonyLoadError(schemaViolation, "missing generated default for " & objectId & "." & propertyId)


proc transformModeName(mode: TransformMode): string =
  case mode
  of normal: "normal"
  of onlyTranslation: "onlyTranslation"
  of noRotationOrReflection: "noRotationOrReflection"
  of noScale: "noScale"
  of noScaleOrReflection: "noScaleOrReflection"


proc parseTransformMode(value: string): TransformMode =
  case value
  of "normal": normal
  of "onlyTranslation": onlyTranslation
  of "noRotationOrReflection": noRotationOrReflection
  of "noScale": noScale
  of "noScaleOrReflection": noScaleOrReflection
  else:
    raise newBonyLoadError(schemaViolation, ".bnb transformMode is invalid")


proc writeF32Payload(value: float64): seq[byte] =
  let stored = float32(quantizeF32(value))
  let bits = cast[uint32](stored)
  result.add byte(bits and 0xff'u32)
  result.add byte((bits shr 8) and 0xff'u32)
  result.add byte((bits shr 16) and 0xff'u32)
  result.add byte((bits shr 24) and 0xff'u32)


proc readF32Payload(payload: openArray[byte]; context: string): float64 =
  if payload.len != 4:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " f32 payload must be 4 bytes")
  let bits =
    uint32(payload[0]) or
    (uint32(payload[1]) shl 8) or
    (uint32(payload[2]) shl 16) or
    (uint32(payload[3]) shl 24)
  result = quantizeF32(float64(cast[float32](bits)), context)


proc writeF64Payload(value: float64; context: string): seq[byte] =
  let stored = requireFiniteF64(value, context)
  let bits = cast[uint64](stored)
  for shift in countup(0, 56, 8):
    result.add byte((bits shr shift) and 0xff'u64)


proc readF64Payload(payload: openArray[byte]; context: string): float64 =
  if payload.len != 8:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " f64 payload must be 8 bytes")
  let bits =
    uint64(payload[0]) or
    (uint64(payload[1]) shl 8) or
    (uint64(payload[2]) shl 16) or
    (uint64(payload[3]) shl 24) or
    (uint64(payload[4]) shl 32) or
    (uint64(payload[5]) shl 40) or
    (uint64(payload[6]) shl 48) or
    (uint64(payload[7]) shl 56)
  requireFiniteF64(cast[float64](bits), context)


proc writeBoolPayload(value: bool): seq[byte] =
  if value:
    @[1'u8]
  else:
    @[0'u8]


proc readBoolPayload(payload: openArray[byte]; context: string): bool =
  if payload.len != 1:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " bool payload must be 1 byte")
  case payload[0]
  of 0'u8: false
  of 1'u8: true
  else:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " bool payload must be 0 or 1")


proc writeVarintPayload(value: int): seq[byte] =
  result.writeVarint(int64(value))


proc readVarintPayload(payload: openArray[byte]; context: string): int =
  var index = 0
  let decoded = payload.readVarint(index)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " varint payload has trailing bytes")
  if decoded < int64(low(int)) or decoded > int64(high(int)):
    raise newBonyLoadError(numericOutOfRange, ".bnb " & context & " varint payload is out of range")
  int(decoded)


proc writeVaruintPayload(value: uint64): seq[byte] =
  result.writeVaruint(value)


proc readVaruintPayload(payload: openArray[byte]; context: string): uint64 =
  var index = 0
  let decoded = payload.readVaruint(index)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " varuint payload has trailing bytes")
  decoded


proc writeStringPayloadBytes(table: var BnbStringTable; value: string): seq[byte] =
  result.writeStringPayload(table, value)


proc addProperty(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  propertyKey: uint64;
  payload: seq[byte];
) =
  properties.add BnbPropertyRecord(propertyKey: propertyKey, payload: payload)
  toc[propertyKey] = propertyBackingTypeCode(propertyKey)


proc propertyMap(record: BnbObjectRecord; allowedKnownKeys: openArray[uint64]): Table[uint64, seq[byte]] =
  for property in record.properties:
    var allowed = false
    for key in allowedKnownKeys:
      if property.propertyKey == key:
        allowed = true
        break
    if property.propertyKey.isKnownPropertyKey and not allowed:
      raise newBonyLoadError(schemaViolation, ".bnb property is not valid for object type: " & $property.propertyKey)
    if allowed:
      result[property.propertyKey] = property.payload


proc readStringProperty(
  properties: Table[uint64, seq[byte]];
  table: BnbStringTable;
  propertyKey: uint64;
  context: string;
): string =
  if propertyKey notin properties:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " is required")
  readStringPayload(properties[propertyKey], table)


proc readOptionalStringProperty(
  properties: Table[uint64, seq[byte]];
  table: BnbStringTable;
  propertyKey: uint64;
  defaultValue: string;
): string =
  if propertyKey notin properties:
    return defaultValue
  readStringPayload(properties[propertyKey], table)


proc readFloatProperty(properties: Table[uint64, seq[byte]]; propertyKey: uint64; context: string): float64 =
  if propertyKey notin properties:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " is required")
  readF32Payload(properties[propertyKey], context)


proc readF64Property(properties: Table[uint64, seq[byte]]; propertyKey: uint64; context: string): float64 =
  if propertyKey notin properties:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " is required")
  readF64Payload(properties[propertyKey], context)


proc readOptionalFloatProperty(
  properties: Table[uint64, seq[byte]];
  propertyKey: uint64;
  defaultValue: float64;
  context: string;
): float64 =
  if propertyKey notin properties:
    return quantizeF32(defaultValue, context)
  readF32Payload(properties[propertyKey], context)


proc readOptionalBoolProperty(
  properties: Table[uint64, seq[byte]];
  propertyKey: uint64;
  defaultValue: bool;
  context: string;
): bool =
  if propertyKey notin properties:
    return defaultValue
  readBoolPayload(properties[propertyKey], context)


proc readOptionalIntProperty(
  properties: Table[uint64, seq[byte]];
  propertyKey: uint64;
  defaultValue: int;
  context: string;
): int =
  if propertyKey notin properties:
    return defaultValue
  readVarintPayload(properties[propertyKey], context)


proc addStringIfNeeded(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  table: var BnbStringTable;
  propertyKey: uint64;
  value: string;
  defaultValue: string;
  required = false;
) =
  if required or value != defaultValue:
    properties.addProperty(toc, propertyKey, writeStringPayloadBytes(table, value))


proc addFloatIfNeeded(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  propertyKey: uint64;
  value: float64;
  defaultValue: float64;
  required = false;
) =
  if required or quantizeF32(value) != quantizeF32(defaultValue):
    properties.addProperty(toc, propertyKey, writeF32Payload(value))


proc addF64Required(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  propertyKey: uint64;
  value: float64;
  context: string;
) =
  properties.addProperty(toc, propertyKey, writeF64Payload(value, context))


proc addBoolIfNeeded(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  propertyKey: uint64;
  value: bool;
  defaultValue: bool;
) =
  if value != defaultValue:
    properties.addProperty(toc, propertyKey, writeBoolPayload(value))


proc addIntIfNeeded(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  propertyKey: uint64;
  value: int;
  defaultValue: int;
  required = false;
) =
  if required or value != defaultValue:
    properties.addProperty(toc, propertyKey, writeVarintPayload(value))


proc writeControlPointsPayload(points: openArray[DeformerPoint]): seq[byte] =
  result.writeVaruint(uint64(points.len))
  for point in points:
    result.add writeF32Payload(point.x)
    result.add writeF32Payload(point.y)


proc readControlPointsPayload(payload: openArray[byte]): seq[DeformerPoint] =
  var index = 0
  let count = payload.readVaruint(index)
  for _ in 0'u64 ..< count:
    let x = readF32Payload(payload[index ..< index + 4], "warpControlPoints.x")
    index += 4
    let y = readF32Payload(payload[index ..< index + 4], "warpControlPoints.y")
    index += 4
    result.add DeformerPoint(x: x, y: y)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb warpControlPoints payload has trailing bytes")


proc writeBlendAxesPayload(axes: openArray[ParameterAxis]; table: var BnbStringTable): seq[byte] =
  result.writeVaruint(uint64(axes.len))
  for axis in axes:
    result.writeVaruint(table.intern(axis.name))


proc readBlendAxesPayload(
  payload: openArray[byte];
  table: BnbStringTable;
  paramsByName: Table[string, ParameterAxis];
): seq[ParameterAxis] =
  var index = 0
  let count = payload.readVaruint(index)
  for _ in 0'u64 ..< count:
    let nameIndex = payload.readVaruint(index)
    let axisName = table.stringAt(nameIndex)
    if axisName notin paramsByName:
      raise newBonyLoadError(unknownRequiredReference, ".bnb keyformBlend references unknown parameter: " & axisName)
    result.add paramsByName[axisName]
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb blendAxes payload has trailing bytes")


proc writeBonesPayload(bones: openArray[string]; table: var BnbStringTable): seq[byte] =
  ## Frozen IK bones layout (contract §2): varuint count followed by
  ## count * (varuint string-table index for the bone name), chain root->tip.
  ## Same string-table packing as blendAxes (key 6041); indices are string-table
  ## indices, NOT skeleton bone-order indices.
  result.writeVaruint(uint64(bones.len))
  for bone in bones:
    result.writeVaruint(table.intern(bone))


proc readBonesPayload(payload: openArray[byte]; table: BnbStringTable): seq[string] =
  var index = 0
  let count = payload.readVaruint(index)
  for _ in 0'u64 ..< count:
    let nameIndex = payload.readVaruint(index)
    result.add table.stringAt(nameIndex)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb ikConstraint bones payload has trailing bytes")


proc writeBlendF32sPayload(values: openArray[float64]): seq[byte] =
  for v in values:
    result.add writeF32Payload(v)


proc readBlendF32sPayload(payload: openArray[byte]; count: int; context: string): seq[float64] =
  if payload.len != count * 4:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " payload length mismatch")
  var index = 0
  for _ in 0 ..< count:
    result.add readF32Payload(payload[index ..< index + 4], context)
    index += 4


proc readOptionalUintProperty(
  properties: Table[uint64, seq[byte]];
  propertyKey: uint64;
  defaultValue: uint32;
  context: string;
): uint32 =
  if propertyKey notin properties:
    return defaultValue
  let val = readVaruintPayload(properties[propertyKey], context)
  if val > uint64(high(uint32)):
    raise newBonyLoadError(numericOutOfRange, ".bnb " & context & " varuint is out of uint32 range")
  uint32(val)


proc readRequiredUintProperty(
  properties: Table[uint64, seq[byte]];
  propertyKey: uint64;
  context: string;
): uint32 =
  if propertyKey notin properties:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " is required")
  let val = readVaruintPayload(properties[propertyKey], context)
  if val > uint64(high(uint32)):
    raise newBonyLoadError(numericOutOfRange, ".bnb " & context & " varuint is out of uint32 range")
  uint32(val)


proc addUintIfNeeded(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  propertyKey: uint64;
  value: uint64;
  defaultValue = 0'u64;
  required = false;
) =
  if required or value != defaultValue:
    properties.addProperty(toc, propertyKey, writeVaruintPayload(value))


proc writeF32To(result: var seq[byte]; value: float64) =
  result.add writeF32Payload(value)


proc readF32From(payload: openArray[byte]; index: var int; context: string): float64 =
  if index + 4 > payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " f32 payload is truncated")
  result = readF32Payload(payload[index ..< index + 4], context)
  index += 4


proc readBoolFrom(payload: openArray[byte]; index: var int; context: string): bool =
  if index >= payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " bool payload is truncated")
  result = readBoolPayload(payload[index ..< index + 1], context)
  inc index


proc curveTag(curve: TimelineCurve): uint64 =
  case curve.kind
  of linearCurve: 0
  of steppedCurve: 1
  of bezierCurve: 2


proc curveFromTag(tag: uint64; payload: openArray[byte]; index: var int; context: string): TimelineCurve =
  case tag
  of 0: linearTimelineCurve
  of 1: steppedTimelineCurve
  of 2:
    bezierTimelineCurve(
      payload.readF32From(index, context & ".c1x"),
      payload.readF32From(index, context & ".c1y"),
      payload.readF32From(index, context & ".c2x"),
      payload.readF32From(index, context & ".c2y"),
    )
  else:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " curve kind is invalid")


proc writeCurve(result: var seq[byte]; curve: TimelineCurve) =
  result.writeVaruint(curve.curveTag)
  if curve.kind == bezierCurve:
    result.writeF32To(curve.c1x)
    result.writeF32To(curve.c1y)
    result.writeF32To(curve.c2x)
    result.writeF32To(curve.c2y)


proc readCurve(payload: openArray[byte]; index: var int; context: string): TimelineCurve =
  curveFromTag(payload.readVaruint(index), payload, index, context)


proc boneTimelineKindTag(kind: BoneTimelineKind): uint64 = uint64(ord(kind))
proc slotTimelineKindTag(kind: SlotTimelineKind): uint64 = uint64(ord(kind))
proc inputKindTag(kind: StateMachineInputKind): uint64 = uint64(ord(kind))
proc stateKindTag(kind: StateMachineStateKind): uint64 = uint64(ord(kind))
proc conditionKindTag(kind: StateMachineConditionKind): uint64 = uint64(ord(kind))
proc listenerKindTag(kind: StateMachineListenerKind): uint64 = uint64(ord(kind))


proc boneTimelineKindFromTag(tag: uint64): BoneTimelineKind =
  if tag > uint64(ord(high(BoneTimelineKind))):
    raise newBonyLoadError(schemaViolation, ".bnb boneTimeline.kind is invalid")
  BoneTimelineKind(tag)


proc slotTimelineKindFromTag(tag: uint64): SlotTimelineKind =
  if tag > uint64(ord(high(SlotTimelineKind))):
    raise newBonyLoadError(schemaViolation, ".bnb slotTimeline.kind is invalid")
  SlotTimelineKind(tag)


proc inputKindFromTag(tag: uint64): StateMachineInputKind =
  if tag > uint64(ord(high(StateMachineInputKind))):
    raise newBonyLoadError(schemaViolation, ".bnb stateMachineInput.kind is invalid")
  StateMachineInputKind(tag)


proc stateKindFromTag(tag: uint64): StateMachineStateKind =
  if tag > uint64(ord(high(StateMachineStateKind))):
    raise newBonyLoadError(schemaViolation, ".bnb stateMachineState.kind is invalid")
  StateMachineStateKind(tag)


proc conditionKindFromTag(tag: uint64): StateMachineConditionKind =
  if tag > uint64(ord(high(StateMachineConditionKind))):
    raise newBonyLoadError(schemaViolation, ".bnb stateMachineCondition.kind is invalid")
  StateMachineConditionKind(tag)


proc listenerKindFromTag(tag: uint64): StateMachineListenerKind =
  if tag > uint64(ord(high(StateMachineListenerKind))):
    raise newBonyLoadError(schemaViolation, ".bnb stateMachineListener.kind is invalid")
  StateMachineListenerKind(tag)


proc sequenceModeTag(mode: SequenceMode): uint64 = uint64(ord(mode))


proc sequenceModeFromTag(tag: uint64): SequenceMode =
  if tag > uint64(ord(high(SequenceMode))):
    raise newBonyLoadError(schemaViolation, ".bnb sequence mode is invalid")
  SequenceMode(tag)


proc transformModeTag(mode: TransformMode): uint64 = uint64(ord(mode))


proc transformModeFromTag(tag: uint64): TransformMode =
  if tag > uint64(ord(high(TransformMode))):
    raise newBonyLoadError(schemaViolation, ".bnb inherit transformMode is invalid")
  TransformMode(tag)


proc writeTimelineKeys(timeline: BoneTimeline): seq[byte] =
  case timeline.kind
  of inheritTimeline:
    result.writeVaruint(uint64(timeline.inheritKeys.len))
    for key in timeline.inheritKeys:
      result.writeF32To(key.time)
      result.add writeBoolPayload(key.inheritRotation)
      result.add writeBoolPayload(key.inheritScale)
      result.add writeBoolPayload(key.inheritReflection)
      result.writeVaruint(key.transformMode.transformModeTag)
  of translateTimeline, scaleTimeline, shearTimeline:
    result.writeVaruint(uint64(timeline.vectorKeys.len))
    for key in timeline.vectorKeys:
      result.writeF32To(key.time)
      result.writeF32To(key.x)
      result.writeF32To(key.y)
      result.writeCurve(key.curveX)
      result.writeCurve(key.curveY)
  else:
    result.writeVaruint(uint64(timeline.scalarKeys.len))
    for key in timeline.scalarKeys:
      result.writeF32To(key.time)
      result.writeF32To(key.value)
      result.writeCurve(key.curve)


proc writeTimelineKeys(timeline: SlotTimeline; regionIndexes: Table[string, int]): seq[byte] =
  case timeline.kind
  of attachmentTimeline:
    result.writeVaruint(uint64(timeline.attachmentKeys.len))
    for key in timeline.attachmentKeys:
      result.writeF32To(key.time)
      if key.attachment.len == 0:
        result.writeVaruint(0)
      else:
        if key.attachment notin regionIndexes:
          raise newBonyLoadError(unknownRequiredReference, ".bnb slot attachment timeline references unknown region: " & key.attachment)
        result.writeVaruint(uint64(regionIndexes[key.attachment] + 1))
  of rgbaTimeline, rgbTimeline, alphaTimeline:
    result.writeVaruint(uint64(timeline.colorKeys.len))
    for key in timeline.colorKeys:
      result.writeF32To(key.time)
      result.writeF32To(key.color.r)
      result.writeF32To(key.color.g)
      result.writeF32To(key.color.b)
      result.writeF32To(key.color.a)
      result.writeCurve(key.curve)
  of rgba2Timeline:
    result.writeVaruint(uint64(timeline.color2Keys.len))
    for key in timeline.color2Keys:
      result.writeF32To(key.time)
      result.writeF32To(key.color.light.r)
      result.writeF32To(key.color.light.g)
      result.writeF32To(key.color.light.b)
      result.writeF32To(key.color.light.a)
      result.writeF32To(key.color.darkR)
      result.writeF32To(key.color.darkG)
      result.writeF32To(key.color.darkB)
      result.writeCurve(key.curve)
  of sequenceTimeline:
    result.writeVaruint(uint64(timeline.sequenceKeys.len))
    for key in timeline.sequenceKeys:
      result.writeF32To(key.time)
      result.writeVaruint(uint64(key.index))
      result.writeF32To(key.delay)
      result.writeVaruint(key.mode.sequenceModeTag)


proc readBoneTimelineKeys(kind: BoneTimelineKind; payload: openArray[byte]; context: string): BoneTimeline =
  var index = 0
  let count = payload.readVaruint(index)
  if count == 0:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " must contain at least one key")
  case kind
  of inheritTimeline:
    var keys: seq[InheritKeyframe]
    for _ in 0'u64 ..< count:
      keys.add inheritKeyframe(
        payload.readF32From(index, context & ".time"),
        payload.readBoolFrom(index, context & ".inheritRotation"),
        payload.readBoolFrom(index, context & ".inheritScale"),
        payload.readBoolFrom(index, context & ".inheritReflection"),
        payload.readVaruint(index).transformModeFromTag,
      )
    result = boneInheritTimeline("__pending__", keys)
  of translateTimeline, scaleTimeline, shearTimeline:
    var keys: seq[Vector2Keyframe]
    for _ in 0'u64 ..< count:
      keys.add vector2Keyframe(
        payload.readF32From(index, context & ".time"),
        payload.readF32From(index, context & ".x"),
        payload.readF32From(index, context & ".y"),
        payload.readCurve(index, context & ".curveX"),
        payload.readCurve(index, context & ".curveY"),
      )
    result = boneVectorTimeline("__pending__", kind, keys)
  else:
    var keys: seq[ScalarKeyframe]
    for _ in 0'u64 ..< count:
      keys.add scalarKeyframe(
        payload.readF32From(index, context & ".time"),
        payload.readF32From(index, context & ".value"),
        payload.readCurve(index, context & ".curve"),
      )
    result = boneScalarTimeline("__pending__", kind, keys)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " has trailing bytes")


proc readSlotTimelineKeys(
  kind: SlotTimelineKind;
  payload: openArray[byte];
  regions: openArray[RegionAttachment];
  context: string;
): SlotTimeline =
  var index = 0
  let count = payload.readVaruint(index)
  if count == 0:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " must contain at least one key")
  case kind
  of attachmentTimeline:
    var keys: seq[AttachmentKeyframe]
    for _ in 0'u64 ..< count:
      let time = payload.readF32From(index, context & ".time")
      let tag = payload.readVaruint(index)
      if tag == 0:
        keys.add attachmentKeyframe(time, "")
      else:
        if tag - 1 >= uint64(regions.len):
          raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " attachment index is out of range")
        keys.add attachmentKeyframe(time, regions[int(tag - 1)].name)
    result = slotAttachmentTimeline("__pending__", keys)
  of rgbaTimeline, rgbTimeline, alphaTimeline:
    var keys: seq[ColorKeyframe]
    for _ in 0'u64 ..< count:
      keys.add colorKeyframe(
        payload.readF32From(index, context & ".time"),
        colorRgba(
          payload.readF32From(index, context & ".r"),
          payload.readF32From(index, context & ".g"),
          payload.readF32From(index, context & ".b"),
          payload.readF32From(index, context & ".a"),
        ),
        payload.readCurve(index, context & ".curve"),
      )
    result = slotColorTimeline("__pending__", kind, keys)
  of rgba2Timeline:
    var keys: seq[Color2Keyframe]
    for _ in 0'u64 ..< count:
      let time = payload.readF32From(index, context & ".time")
      let light = colorRgba(
        payload.readF32From(index, context & ".r"),
        payload.readF32From(index, context & ".g"),
        payload.readF32From(index, context & ".b"),
        payload.readF32From(index, context & ".a"),
      )
      keys.add color2Keyframe(
        time,
        colorRgba2(
          light,
          payload.readF32From(index, context & ".darkR"),
          payload.readF32From(index, context & ".darkG"),
          payload.readF32From(index, context & ".darkB"),
        ),
        payload.readCurve(index, context & ".curve"),
      )
    result = slotColor2Timeline("__pending__", keys)
  of sequenceTimeline:
    var keys: seq[SequenceKeyframe]
    for _ in 0'u64 ..< count:
      keys.add sequenceKeyframe(
        payload.readF32From(index, context & ".time"),
        uint32(payload.readVaruint(index)),
        payload.readF32From(index, context & ".delay"),
        payload.readVaruint(index).sequenceModeFromTag,
      )
    result = slotSequenceTimeline("__pending__", keys)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " has trailing bytes")


proc tocEntries(toc: Table[uint64, uint8]): seq[BnbTocEntry] =
  for propertyKey, backingTypeCode in toc:
    result.add BnbTocEntry(propertyKey: propertyKey, backingTypeCode: backingTypeCode)


proc buildObjectRecords(data: SkeletonData; table: var BnbStringTable; toc: var Table[uint64, uint8]): seq[BnbObjectRecord] =
  validateSkeletonData(data)

  var skeletonProperties: seq[BnbPropertyRecord]
  skeletonProperties.addStringIfNeeded(toc, table, nameKey, data.header.name, "", required = true)
  skeletonProperties.addStringIfNeeded(
    toc,
    table,
    versionKey,
    data.header.version,
    defaultString("skeleton", "version"),
  )
  result.add BnbObjectRecord(typeKey: skeletonTypeKey, properties: skeletonProperties)

  for bone in data.bones:
    let local = bone.local
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, bone.name, "", required = true)
    properties.addStringIfNeeded(toc, table, parentKey, bone.parent, defaultString("bone", "parent"))
    properties.addFloatIfNeeded(toc, xKey, local.x, defaultFloat("bone", "x"))
    properties.addFloatIfNeeded(toc, yKey, local.y, defaultFloat("bone", "y"))
    properties.addFloatIfNeeded(toc, rotationKey, local.rotation, defaultFloat("bone", "rotation"))
    properties.addFloatIfNeeded(toc, scaleXKey, local.scaleX, defaultFloat("bone", "scaleX"))
    properties.addFloatIfNeeded(toc, scaleYKey, local.scaleY, defaultFloat("bone", "scaleY"))
    properties.addFloatIfNeeded(toc, shearXKey, local.shearX, defaultFloat("bone", "shearX"))
    properties.addFloatIfNeeded(toc, shearYKey, local.shearY, defaultFloat("bone", "shearY"))
    properties.addBoolIfNeeded(toc, inheritRotationKey, local.inheritRotation, defaultBool("bone", "inheritRotation"))
    properties.addBoolIfNeeded(toc, inheritScaleKey, local.inheritScale, defaultBool("bone", "inheritScale"))
    properties.addBoolIfNeeded(
      toc,
      inheritReflectionKey,
      local.inheritReflection,
      defaultBool("bone", "inheritReflection"),
    )
    properties.addStringIfNeeded(
      toc,
      table,
      transformModeKey,
      transformModeName(local.transformMode),
      defaultString("bone", "transformMode"),
    )
    result.add BnbObjectRecord(typeKey: boneTypeKey, properties: properties)

  for slot in data.slots:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, slot.name, "", required = true)
    properties.addStringIfNeeded(toc, table, boneKey, slot.bone, "", required = true)
    properties.addStringIfNeeded(toc, table, attachmentKey, slot.attachment, defaultString("slot", "attachment"))
    result.add BnbObjectRecord(typeKey: slotTypeKey, properties: properties)

  for region in data.regions:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, region.name, "", required = true)
    properties.addFloatIfNeeded(toc, widthKey, region.width, 0.0, required = true)
    properties.addFloatIfNeeded(toc, heightKey, region.height, 0.0, required = true)
    result.add BnbObjectRecord(typeKey: regionTypeKey, properties: properties)

  for pathAttachment in data.pathAttachments:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, pathAttachment.name, "", required = true)
    properties.addF64Required(toc, p0xKey, pathAttachment.p0x, "pathAttachment.p0x")
    properties.addF64Required(toc, p0yKey, pathAttachment.p0y, "pathAttachment.p0y")
    properties.addF64Required(toc, p1xKey, pathAttachment.p1x, "pathAttachment.p1x")
    properties.addF64Required(toc, p1yKey, pathAttachment.p1y, "pathAttachment.p1y")
    properties.addF64Required(toc, p2xKey, pathAttachment.p2x, "pathAttachment.p2x")
    properties.addF64Required(toc, p2yKey, pathAttachment.p2y, "pathAttachment.p2y")
    properties.addF64Required(toc, p3xKey, pathAttachment.p3x, "pathAttachment.p3x")
    properties.addF64Required(toc, p3yKey, pathAttachment.p3y, "pathAttachment.p3y")
    result.add BnbObjectRecord(typeKey: pathAttachmentTypeKey, properties: properties)

  # IK section: canonical object-stream position is after attachments and before
  # paths (docs/binary-canonicalization.md). Emitted only when non-empty so
  # existing IK-free fixtures stay byte-identical. mix/bendPositive are
  # presence-gated (applyOnLoad:false) to stay symmetric with the JSON emitter;
  # order is value-gated (applyOnLoad:true).
  for ik in data.ikConstraints:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, ik.name, "", required = true)
    properties.addProperty(toc, bonesKey, writeBonesPayload(ik.bones, table))
    properties.addStringIfNeeded(toc, table, targetKey, ik.target, "", required = true)
    properties.addIntIfNeeded(toc, orderKey, ik.order, defaultInt("ikConstraint", "order"))
    properties.addFloatIfNeeded(toc, mixKey, ik.mix, defaultFloat("ikConstraint", "mix"), required = ik.hasMix)
    if ik.hasBendPositive:
      properties.addProperty(toc, bendPositiveKey, writeBoolPayload(ik.bendPositive))
    result.add BnbObjectRecord(typeKey: ikConstraintTypeKey, properties: properties)

  # Transform section: canonical object-stream position is after IK and before
  # paths, matching constraintKindRank (ckIk=0, ckTransform=1, ckPath=2). Emitted
  # only when non-empty so existing transform-free fixtures stay byte-identical.
  # The four mixes are presence-gated (applyOnLoad:false) to stay symmetric with
  # the JSON emitter; order is value-gated (applyOnLoad:true).
  for tc in data.transformConstraints:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, tc.name, "", required = true)
    properties.addStringIfNeeded(toc, table, boneKey, tc.bone, "", required = true)
    properties.addStringIfNeeded(toc, table, targetKey, tc.target, "", required = true)
    properties.addIntIfNeeded(toc, orderKey, tc.order, defaultInt("transformConstraint", "order"))
    properties.addFloatIfNeeded(toc, translateMixKey, tc.translateMix, defaultFloat("transformConstraint", "translateMix"), required = tc.hasTranslateMix)
    properties.addFloatIfNeeded(toc, rotateMixKey, tc.rotateMix, defaultFloat("transformConstraint", "rotateMix"), required = tc.hasRotateMix)
    properties.addFloatIfNeeded(toc, scaleMixKey, tc.scaleMix, defaultFloat("transformConstraint", "scaleMix"), required = tc.hasScaleMix)
    properties.addFloatIfNeeded(toc, shearMixKey, tc.shearMix, defaultFloat("transformConstraint", "shearMix"), required = tc.hasShearMix)
    result.add BnbObjectRecord(typeKey: transformConstraintTypeKey, properties: properties)

  for path in data.paths:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, path.name, "", required = true)
    properties.addStringIfNeeded(toc, table, boneKey, path.bone, "", required = true)
    properties.addStringIfNeeded(toc, table, targetKey, path.target, "", required = true)
    properties.addStringIfNeeded(toc, table, pathKey, path.path, "", required = true)
    properties.addIntIfNeeded(toc, orderKey, path.order, defaultInt("path", "order"))
    properties.addFloatIfNeeded(toc, positionKey, path.position, defaultFloat("path", "position"), required = path.hasPosition)
    properties.addFloatIfNeeded(toc, translateMixKey, path.translateMix, defaultFloat("path", "translateMix"), required = path.hasTranslateMix)
    properties.addFloatIfNeeded(toc, rotateMixKey, path.rotateMix, defaultFloat("path", "rotateMix"), required = path.hasRotateMix)
    result.add BnbObjectRecord(typeKey: pathTypeKey, properties: properties)

  # Physics section: canonical object-stream position is after paths and before
  # parameters (docs/binary-canonicalization.md), matching ckPhysics=3 in
  # constraintKindRank. Emitted only when non-empty so existing fixtures stay
  # byte-identical. The seven params are presence-gated (applyOnLoad:false); order
  # is value-gated; channels is a required varuint bitmask always emitted.
  for pc in data.physicsConstraints:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, pc.name, "", required = true)
    properties.addStringIfNeeded(toc, table, boneKey, pc.bone, "", required = true)
    properties.addIntIfNeeded(toc, orderKey, pc.order, defaultInt("physicsConstraint", "order"))
    properties.addProperty(toc, channelsKey, writeVaruintPayload(physicsChannelsToMask(pc.channels)))
    properties.addFloatIfNeeded(toc, inertiaKey, pc.inertia, defaultFloat("physicsConstraint", "inertia"), required = pc.hasInertia)
    properties.addFloatIfNeeded(toc, strengthKey, pc.strength, defaultFloat("physicsConstraint", "strength"), required = pc.hasStrength)
    properties.addFloatIfNeeded(toc, dampingKey, pc.damping, defaultFloat("physicsConstraint", "damping"), required = pc.hasDamping)
    properties.addFloatIfNeeded(toc, massKey, pc.mass, defaultFloat("physicsConstraint", "mass"), required = pc.hasMass)
    properties.addFloatIfNeeded(toc, gravityKey, pc.gravity, defaultFloat("physicsConstraint", "gravity"), required = pc.hasGravity)
    properties.addFloatIfNeeded(toc, windKey, pc.wind, defaultFloat("physicsConstraint", "wind"), required = pc.hasWind)
    properties.addFloatIfNeeded(toc, physicsMixKey, pc.mix, defaultFloat("physicsConstraint", "physicsMix"), required = pc.hasMix)
    result.add BnbObjectRecord(typeKey: physicsConstraintTypeKey, properties: properties)

  for param in data.parameters:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, param.name, "", required = true)
    properties.addProperty(toc, parameterMinKey, writeF32Payload(param.minValue))
    properties.addProperty(toc, parameterMaxKey, writeF32Payload(param.maxValue))
    if quantizeF32(param.defaultValue) != 0.0:
      properties.addProperty(toc, parameterDefaultKey, writeF32Payload(param.defaultValue))
    result.add BnbObjectRecord(typeKey: parameterTypeKey, properties: properties)

  for rec in data.deformers:
    let def = rec.deformer
    var defProperties: seq[BnbPropertyRecord]
    defProperties.addProperty(toc, deformerIdKey, writeStringPayloadBytes(table, def.id))
    if def.parent.len > 0:
      defProperties.addStringIfNeeded(toc, table, parentKey, def.parent, "")
    if def.order != 0'u32:
      defProperties.addProperty(toc, deformerOrderKey, writeVaruintPayload(uint64(def.order)))
    case def.kind
    of warpDeformerKind:
      defProperties.addProperty(toc, deformerKindKey, writeStringPayloadBytes(table, "warp"))
    of rotationDeformerKind:
      defProperties.addProperty(toc, deformerKindKey, writeStringPayloadBytes(table, "rotation"))
    result.add BnbObjectRecord(typeKey: deformerTypeKey, properties: defProperties)

    case def.kind
    of warpDeformerKind:
      let warp = def.warp
      var wProperties: seq[BnbPropertyRecord]
      if warp.rows != 2'u32:
        wProperties.addProperty(toc, warpRowsKey, writeVaruintPayload(uint64(warp.rows)))
      if warp.cols != 2'u32:
        wProperties.addProperty(toc, warpColsKey, writeVaruintPayload(uint64(warp.cols)))
      wProperties.addProperty(toc, warpMinXKey, writeF32Payload(warp.minX))
      wProperties.addProperty(toc, warpMinYKey, writeF32Payload(warp.minY))
      wProperties.addProperty(toc, warpMaxXKey, writeF32Payload(warp.maxX))
      wProperties.addProperty(toc, warpMaxYKey, writeF32Payload(warp.maxY))
      wProperties.addProperty(toc, warpControlPointsKey, writeControlPointsPayload(warp.controlPoints))
      result.add BnbObjectRecord(typeKey: warpLatticeTypeKey, properties: wProperties)
    of rotationDeformerKind:
      let rot = def.rotation
      var rProperties: seq[BnbPropertyRecord]
      rProperties.addProperty(toc, rotationPivotXKey, writeF32Payload(rot.pivotX))
      rProperties.addProperty(toc, rotationPivotYKey, writeF32Payload(rot.pivotY))
      rProperties.addProperty(toc, rotationAngleDegreesKey, writeF32Payload(rot.angleDegrees))
      if quantizeF32(rot.scaleX) != 1.0:
        rProperties.addProperty(toc, rotationScaleXKey, writeF32Payload(rot.scaleX))
      if quantizeF32(rot.scaleY) != 1.0:
        rProperties.addProperty(toc, rotationScaleYKey, writeF32Payload(rot.scaleY))
      if quantizeF32(rot.opacity) != 1.0:
        rProperties.addProperty(toc, rotationOpacityKey, writeF32Payload(rot.opacity))
      result.add BnbObjectRecord(typeKey: rotationDeformerTypeKey, properties: rProperties)

    let blend = rec.keyformBlend
    if blend.axes.len > 0 and blend.keyforms.len > 0:
      var bProperties: seq[BnbPropertyRecord]
      bProperties.addProperty(toc, blendValueCountKey, writeVaruintPayload(uint64(blend.valueCount)))
      bProperties.addProperty(toc, blendAxesKey, writeBlendAxesPayload(blend.axes, table))
      result.add BnbObjectRecord(typeKey: keyformBlendTypeKey, properties: bProperties)
      for kf in blend.keyforms:
        var kfProperties: seq[BnbPropertyRecord]
        var coordValues: seq[float64]
        for coord in kf.coordinates:
          coordValues.add coord.value
        kfProperties.addProperty(toc, blendCoordinatesKey, writeBlendF32sPayload(coordValues))
        kfProperties.addProperty(toc, blendValuesKey, writeBlendF32sPayload(kf.values))
        result.add BnbObjectRecord(typeKey: keyformTypeKey, properties: kfProperties)


proc indexByBoneName(data: SkeletonData): Table[string, int] =
  for index, bone in data.bones:
    result[bone.name] = index


proc indexBySlotName(data: SkeletonData): Table[string, int] =
  for index, slot in data.slots:
    result[slot.name] = index


proc indexByRegionName(data: SkeletonData): Table[string, int] =
  for index, region in data.regions:
    result[region.name] = index


proc indexByAnimationName(animations: openArray[AnimationClip]): Table[string, int] =
  for index, clip in animations:
    result[clip.name] = index


proc indexByInputName(inputs: openArray[StateMachineInput]): Table[string, int] =
  for index, input in inputs:
    result[input.name] = index


proc indexByLayerName(layers: openArray[StateMachineLayer]): Table[string, int] =
  for index, layer in layers:
    result[layer.name] = index


proc indexByStateName(states: openArray[StateMachineState]): Table[string, int] =
  for index, state in states:
    result[state.name] = index


proc requiredIndex(indexes: Table[string, int]; name, context: string): int =
  if name notin indexes:
    raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " references unknown name: " & name)
  indexes[name]


proc buildObjectRecords(asset: BonyAsset; table: var BnbStringTable; toc: var Table[uint64, uint8]): seq[BnbObjectRecord] =
  result = buildObjectRecords(asset.skeleton, table, toc)
  let boneIndexes = asset.skeleton.indexByBoneName()
  let slotIndexes = asset.skeleton.indexBySlotName()
  let regionIndexes = asset.skeleton.indexByRegionName()
  let animationIndexes = asset.animations.indexByAnimationName()

  for clip in asset.animations:
    var clipProperties: seq[BnbPropertyRecord]
    clipProperties.addStringIfNeeded(toc, table, nameKey, clip.name, "", required = true)
    result.add BnbObjectRecord(typeKey: animationClipTypeKey, properties: clipProperties)
    for timeline in clip.boneTimelines:
      if timeline.target notin boneIndexes:
        raise newBonyLoadError(unknownRequiredReference, ".bnb bone timeline references unknown bone: " & timeline.target)
      var properties: seq[BnbPropertyRecord]
      properties.addUintIfNeeded(toc, boneIndexKey, uint64(boneIndexes[timeline.target]), required = true)
      properties.addUintIfNeeded(toc, boneTimelineKindKey, timeline.kind.boneTimelineKindTag, required = true)
      properties.addProperty(toc, timelineKeysKey, timeline.writeTimelineKeys())
      result.add BnbObjectRecord(typeKey: boneTimelineTypeKey, properties: properties)
    for timeline in clip.slotTimelines:
      if timeline.target notin slotIndexes:
        raise newBonyLoadError(unknownRequiredReference, ".bnb slot timeline references unknown slot: " & timeline.target)
      var properties: seq[BnbPropertyRecord]
      properties.addUintIfNeeded(toc, slotIndexKey, uint64(slotIndexes[timeline.target]), required = true)
      properties.addUintIfNeeded(toc, slotTimelineKindKey, timeline.kind.slotTimelineKindTag, required = true)
      properties.addProperty(toc, timelineKeysKey, timeline.writeTimelineKeys(regionIndexes))
      result.add BnbObjectRecord(typeKey: slotTimelineTypeKey, properties: properties)

  for machine in asset.stateMachines:
    var machineProperties: seq[BnbPropertyRecord]
    machineProperties.addStringIfNeeded(toc, table, nameKey, machine.name, "", required = true)
    result.add BnbObjectRecord(typeKey: stateMachineTypeKey, properties: machineProperties)
    let inputIndexes = machine.inputs.indexByInputName()
    let layerIndexes = machine.layers.indexByLayerName()
    for input in machine.inputs:
      var properties: seq[BnbPropertyRecord]
      properties.addStringIfNeeded(toc, table, nameKey, input.name, "", required = true)
      properties.addUintIfNeeded(toc, stateMachineInputKindKey, input.kind.inputKindTag, required = true)
      case input.kind
      of boolInput:
        properties.addBoolIfNeeded(toc, inputDefaultBoolKey, input.defaultBool, defaultBool("stateMachineInput", "inputDefaultBool"))
      of numberInput:
        properties.addFloatIfNeeded(toc, inputDefaultNumberKey, input.defaultNumber, defaultFloat("stateMachineInput", "inputDefaultNumber"))
      of triggerInput:
        discard
      result.add BnbObjectRecord(typeKey: stateMachineInputTypeKey, properties: properties)

    for layer in machine.layers:
      let stateIndexes = layer.states.indexByStateName()
      var layerProperties: seq[BnbPropertyRecord]
      layerProperties.addStringIfNeeded(toc, table, nameKey, layer.name, "", required = true)
      layerProperties.addUintIfNeeded(toc, initialStateIndexKey, uint64(stateIndexes.requiredIndex(layer.initialState, "stateMachineLayer.initialState")), uint64(defaultInt("stateMachineLayer", "initialStateIndex")))
      result.add BnbObjectRecord(typeKey: stateMachineLayerTypeKey, properties: layerProperties)

      for state in layer.states:
        var stateProperties: seq[BnbPropertyRecord]
        stateProperties.addStringIfNeeded(toc, table, nameKey, state.name, "", required = true)
        stateProperties.addUintIfNeeded(toc, stateMachineStateKindKey, state.kind.stateKindTag, required = true)
        case state.kind
        of clipState:
          stateProperties.addUintIfNeeded(toc, stateClipIndexKey, uint64(animationIndexes.requiredIndex(state.clip.name, "stateMachineState.clip")), required = true)
          stateProperties.addBoolIfNeeded(toc, stateLoopKey, state.loop, defaultBool("stateMachineState", "stateLoop"))
        of blend1DState:
          stateProperties.addUintIfNeeded(toc, stateBlendInputIndexKey, uint64(inputIndexes.requiredIndex(state.blendInput, "stateMachineState.blendInput")), required = true)
        result.add BnbObjectRecord(typeKey: stateMachineStateTypeKey, properties: stateProperties)
        if state.kind == blend1DState:
          for blendClip in state.blendClips:
            var properties: seq[BnbPropertyRecord]
            properties.addUintIfNeeded(toc, blendClipAnimationIndexKey, uint64(animationIndexes.requiredIndex(blendClip.clip.name, "stateMachineBlendClip.animation")), required = true)
            properties.addFloatIfNeeded(toc, blendClipValueKey, blendClip.value, 0.0, required = true)
            properties.addBoolIfNeeded(toc, blendClipLoopKey, blendClip.loop, defaultBool("stateMachineBlendClip", "blendClipLoop"))
            result.add BnbObjectRecord(typeKey: stateMachineBlendClipTypeKey, properties: properties)

      for transition in layer.transitions:
        var transitionProperties: seq[BnbPropertyRecord]
        transitionProperties.addUintIfNeeded(toc, transitionFromStateIndexKey, uint64(stateIndexes.requiredIndex(transition.fromState, "stateMachineTransition.from")), required = true)
        transitionProperties.addUintIfNeeded(toc, transitionToStateIndexKey, uint64(stateIndexes.requiredIndex(transition.toState, "stateMachineTransition.to")), required = true)
        result.add BnbObjectRecord(typeKey: stateMachineTransitionTypeKey, properties: transitionProperties)
        for condition in transition.conditions:
          var properties: seq[BnbPropertyRecord]
          properties.addUintIfNeeded(toc, conditionInputIndexKey, uint64(inputIndexes.requiredIndex(condition.input, "stateMachineCondition.input")), required = true)
          properties.addUintIfNeeded(toc, stateMachineConditionKindKey, condition.kind.conditionKindTag, required = true)
          case condition.kind
          of boolEqualsCondition:
            properties.addBoolIfNeeded(toc, conditionBoolValueKey, condition.boolValue, defaultBool("stateMachineCondition", "conditionBoolValue"))
          of numberEqualsCondition, numberGreaterCondition, numberGreaterOrEqualCondition, numberLessCondition, numberLessOrEqualCondition:
            properties.addFloatIfNeeded(toc, conditionNumberValueKey, condition.numberValue, defaultFloat("stateMachineCondition", "conditionNumberValue"), required = true)
          of triggerSetCondition:
            discard
          result.add BnbObjectRecord(typeKey: stateMachineConditionTypeKey, properties: properties)

    for listener in machine.listeners:
      var properties: seq[BnbPropertyRecord]
      properties.addStringIfNeeded(toc, table, nameKey, listener.name, "", required = true)
      properties.addUintIfNeeded(toc, stateMachineListenerKindKey, listener.kind.listenerKindTag, required = true)
      let listenerLayerIndex = layerIndexes.requiredIndex(listener.layer, "stateMachineListener.layer")
      properties.addUintIfNeeded(toc, listenerLayerIndexKey, uint64(listenerLayerIndex), required = true)
      let layer = machine.layers[listenerLayerIndex]
      let stateIndexes = layer.states.indexByStateName()
      case listener.kind
      of stateEnterListener:
        properties.addUintIfNeeded(toc, listenerToStateIndexKey, uint64(stateIndexes.requiredIndex(listener.toState, "stateMachineListener.to")), required = true)
      of stateExitListener:
        properties.addUintIfNeeded(toc, listenerFromStateIndexKey, uint64(stateIndexes.requiredIndex(listener.fromState, "stateMachineListener.from")), required = true)
      of transitionListener:
        properties.addUintIfNeeded(toc, listenerFromStateIndexKey, uint64(stateIndexes.requiredIndex(listener.fromState, "stateMachineListener.from")), required = true)
        properties.addUintIfNeeded(toc, listenerToStateIndexKey, uint64(stateIndexes.requiredIndex(listener.toState, "stateMachineListener.to")), required = true)
      result.add BnbObjectRecord(typeKey: stateMachineListenerTypeKey, properties: properties)


proc writeBonyBnb*(output: var seq[byte]; data: SkeletonData; embeddedAtlas: openArray[byte] = []) =
  var table = initStringTable()
  var toc = initTable[uint64, uint8]()
  let records = buildObjectRecords(data, table, toc)
  var flags = bnbStringTableFlag
  if embeddedAtlas.len > 0:
    flags = flags or bnbEmbeddedAtlasFlag

  output.writeHeader(flags = flags)
  output.writeToc(toc.tocEntries)
  output.writeStringTable(table)
  for record in records:
    output.writeObjectRecord(record.typeKey, record.properties)
  output.writeObjectStreamTerminator()
  if embeddedAtlas.len > 0:
    output.writeEmbeddedAtlas(embeddedAtlas)


proc toBonyBnb*(data: SkeletonData; embeddedAtlas: openArray[byte] = []): seq[byte] =
  result.writeBonyBnb(data, embeddedAtlas)


proc writeBonyBnb*(output: var seq[byte]; asset: BonyAsset; embeddedAtlas: openArray[byte] = []) =
  var table = initStringTable()
  var toc = initTable[uint64, uint8]()
  let records = buildObjectRecords(asset, table, toc)
  var flags = bnbStringTableFlag
  if embeddedAtlas.len > 0:
    flags = flags or bnbEmbeddedAtlasFlag

  output.writeHeader(flags = flags)
  output.writeToc(toc.tocEntries)
  output.writeStringTable(table)
  for record in records:
    output.writeObjectRecord(record.typeKey, record.properties)
  output.writeObjectStreamTerminator()
  if embeddedAtlas.len > 0:
    output.writeEmbeddedAtlas(embeddedAtlas)


proc toBonyBnb*(asset: BonyAsset; embeddedAtlas: openArray[byte] = []): seq[byte] =
  result.writeBonyBnb(asset, embeddedAtlas)


proc emitPendingDeformer(
  loadedDeformers: var seq[DeformerRecord];
  pendingId: string;
  pendingParent: string;
  pendingOrder: uint32;
  pendingKind: DeformerKind;
  pendingWarp: WarpLattice;
  pendingRotation: RotationDeformer;
  pendingBlendAxes: seq[ParameterAxis];
  pendingKeyforms: seq[Keyform];
  hasBlend: bool;
) =
  var deformerObj: Deformer
  case pendingKind
  of warpDeformerKind:
    deformerObj = Deformer(id: pendingId, parent: pendingParent, order: pendingOrder, kind: warpDeformerKind, warp: pendingWarp)
    validateWarpLattice(pendingWarp)
  of rotationDeformerKind:
    deformerObj = Deformer(id: pendingId, parent: pendingParent, order: pendingOrder, kind: rotationDeformerKind, rotation: pendingRotation)
    validateRotationDeformer(pendingRotation)
  if hasBlend:
    let blend = keyformBlend(pendingBlendAxes, pendingKeyforms)
    loadedDeformers.add DeformerRecord(deformer: deformerObj, keyformBlend: blend)
  else:
    loadedDeformers.add DeformerRecord(deformer: deformerObj, keyformBlend: KeyformBlend())


proc decodeSkeletonObjects(objects: openArray[BnbObjectRecord]; strings: BnbStringTable): SkeletonData =
  var hasSkeleton = false
  var headerValue: SkeletonHeader
  var bones: seq[BoneData]
  var slots: seq[SlotData]
  var regions: seq[RegionAttachment]
  var pathAttachments: seq[PathAttachmentData]
  var paths: seq[PathConstraintData]
  var ikConstraints: seq[IkConstraintData]
  var transformConstraints: seq[TransformConstraintData]
  var physicsConstraints: seq[PhysicsConstraintData]
  var loadedParameters: seq[ParameterAxis]
  var loadedDeformers: seq[DeformerRecord]

  var deformerPending = false
  var pendingId = ""
  var pendingParent = ""
  var pendingOrder = 0'u32
  var pendingKind = warpDeformerKind
  var pendingWarp = WarpLattice()
  var pendingRotation = RotationDeformer()
  var geometryReady = false
  var blendPending = false
  var pendingBlendValueCount = 0
  var pendingBlendAxes: seq[ParameterAxis] = @[]
  var pendingKeyforms: seq[Keyform] = @[]

  template flushPendingIfAny() =
    if deformerPending and geometryReady:
      emitPendingDeformer(loadedDeformers, pendingId, pendingParent, pendingOrder,
        pendingKind, pendingWarp, pendingRotation, pendingBlendAxes, pendingKeyforms, blendPending)
      deformerPending = false
      geometryReady = false
      blendPending = false
      pendingBlendAxes = @[]
      pendingKeyforms = @[]
    elif deformerPending:
      raise newBonyLoadError(schemaViolation, ".bnb deformer header has no following geometry record")

  for record in objects:
    case record.typeKey
    of skeletonTypeKey:
      if hasSkeleton:
        raise newBonyLoadError(duplicateKey, ".bnb contains multiple skeleton objects")
      let properties = record.propertyMap([nameKey, versionKey])
      headerValue = skeletonHeader(
        properties.readStringProperty(strings, nameKey, "skeleton.name"),
        properties.readOptionalStringProperty(strings, versionKey, defaultString("skeleton", "version")),
      )
      hasSkeleton = true
    of boneTypeKey:
      let properties = record.propertyMap([
        nameKey,
        parentKey,
        xKey,
        yKey,
        rotationKey,
        scaleXKey,
        scaleYKey,
        shearXKey,
        shearYKey,
        inheritRotationKey,
        inheritScaleKey,
        inheritReflectionKey,
        transformModeKey,
      ])
      let inheritRotation = properties.readOptionalBoolProperty(
        inheritRotationKey,
        defaultBool("bone", "inheritRotation"),
        "bone.inheritRotation",
      )
      let inheritScale = properties.readOptionalBoolProperty(
        inheritScaleKey,
        defaultBool("bone", "inheritScale"),
        "bone.inheritScale",
      )
      let inheritReflection = properties.readOptionalBoolProperty(
        inheritReflectionKey,
        defaultBool("bone", "inheritReflection"),
        "bone.inheritReflection",
      )
      bones.add boneData(
        properties.readStringProperty(strings, nameKey, "bone.name"),
        properties.readOptionalStringProperty(strings, parentKey, defaultString("bone", "parent")),
        localTransform(
          x = properties.readOptionalFloatProperty(xKey, defaultFloat("bone", "x"), "bone.x"),
          y = properties.readOptionalFloatProperty(yKey, defaultFloat("bone", "y"), "bone.y"),
          rotation = properties.readOptionalFloatProperty(rotationKey, defaultFloat("bone", "rotation"), "bone.rotation"),
          scaleX = properties.readOptionalFloatProperty(scaleXKey, defaultFloat("bone", "scaleX"), "bone.scaleX"),
          scaleY = properties.readOptionalFloatProperty(scaleYKey, defaultFloat("bone", "scaleY"), "bone.scaleY"),
          shearX = properties.readOptionalFloatProperty(shearXKey, defaultFloat("bone", "shearX"), "bone.shearX"),
          shearY = properties.readOptionalFloatProperty(shearYKey, defaultFloat("bone", "shearY"), "bone.shearY"),
          inheritRotation = inheritRotation,
          inheritScale = inheritScale,
          inheritReflection = inheritReflection,
          transformMode = parseTransformMode(
            properties.readOptionalStringProperty(strings, transformModeKey, defaultString("bone", "transformMode")),
          ),
        ),
      )
    of slotTypeKey:
      let properties = record.propertyMap([nameKey, boneKey, attachmentKey])
      slots.add slotData(
        properties.readStringProperty(strings, nameKey, "slot.name"),
        properties.readStringProperty(strings, boneKey, "slot.bone"),
        properties.readOptionalStringProperty(strings, attachmentKey, defaultString("slot", "attachment")),
      )
    of regionTypeKey:
      let properties = record.propertyMap([nameKey, widthKey, heightKey])
      regions.add regionAttachment(
        properties.readStringProperty(strings, nameKey, "region.name"),
        properties.readFloatProperty(widthKey, "region.width"),
        properties.readFloatProperty(heightKey, "region.height"),
      )
    of pathAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, p0xKey, p0yKey, p1xKey, p1yKey, p2xKey, p2yKey, p3xKey, p3yKey])
      pathAttachments.add pathAttachmentData(
        properties.readStringProperty(strings, nameKey, "pathAttachment.name"),
        properties.readF64Property(p0xKey, "pathAttachment.p0x"),
        properties.readF64Property(p0yKey, "pathAttachment.p0y"),
        properties.readF64Property(p1xKey, "pathAttachment.p1x"),
        properties.readF64Property(p1yKey, "pathAttachment.p1y"),
        properties.readF64Property(p2xKey, "pathAttachment.p2x"),
        properties.readF64Property(p2yKey, "pathAttachment.p2y"),
        properties.readF64Property(p3xKey, "pathAttachment.p3x"),
        properties.readF64Property(p3yKey, "pathAttachment.p3y"),
      )
    of pathTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, targetKey, pathKey, orderKey, positionKey, translateMixKey, rotateMixKey])
      paths.add pathConstraintData(
        properties.readStringProperty(strings, nameKey, "path.name"),
        properties.readStringProperty(strings, boneKey, "path.bone"),
        properties.readStringProperty(strings, targetKey, "path.target"),
        properties.readStringProperty(strings, pathKey, "path.path"),
        properties.readOptionalIntProperty(orderKey, defaultInt("path", "order"), "path.order"),
        hasPosition = positionKey in properties,
        position = properties.readOptionalFloatProperty(positionKey, defaultFloat("path", "position"), "path.position"),
        hasTranslateMix = translateMixKey in properties,
        translateMix = properties.readOptionalFloatProperty(translateMixKey, defaultFloat("path", "translateMix"), "path.translateMix"),
        hasRotateMix = rotateMixKey in properties,
        rotateMix = properties.readOptionalFloatProperty(rotateMixKey, defaultFloat("path", "rotateMix"), "path.rotateMix"),
      )
    of ikConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, bonesKey, targetKey, orderKey, mixKey, bendPositiveKey])
      if bonesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb ikConstraint.bones is required")
      ikConstraints.add ikConstraintData(
        properties.readStringProperty(strings, nameKey, "ikConstraint.name"),
        properties.readStringProperty(strings, targetKey, "ikConstraint.target"),
        readBonesPayload(properties[bonesKey], strings),
        order = properties.readOptionalIntProperty(orderKey, defaultInt("ikConstraint", "order"), "ikConstraint.order"),
        hasMix = mixKey in properties,
        mix = properties.readOptionalFloatProperty(mixKey, defaultFloat("ikConstraint", "mix"), "ikConstraint.mix"),
        hasBendPositive = bendPositiveKey in properties,
        bendPositive = properties.readOptionalBoolProperty(bendPositiveKey, defaultBool("ikConstraint", "bendPositive"), "ikConstraint.bendPositive"),
      )
    of transformConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, targetKey, orderKey, translateMixKey, rotateMixKey, scaleMixKey, shearMixKey])
      transformConstraints.add transformConstraintData(
        properties.readStringProperty(strings, nameKey, "transformConstraint.name"),
        properties.readStringProperty(strings, boneKey, "transformConstraint.bone"),
        properties.readStringProperty(strings, targetKey, "transformConstraint.target"),
        order = properties.readOptionalIntProperty(orderKey, defaultInt("transformConstraint", "order"), "transformConstraint.order"),
        hasTranslateMix = translateMixKey in properties,
        translateMix = properties.readOptionalFloatProperty(translateMixKey, defaultFloat("transformConstraint", "translateMix"), "transformConstraint.translateMix"),
        hasRotateMix = rotateMixKey in properties,
        rotateMix = properties.readOptionalFloatProperty(rotateMixKey, defaultFloat("transformConstraint", "rotateMix"), "transformConstraint.rotateMix"),
        hasScaleMix = scaleMixKey in properties,
        scaleMix = properties.readOptionalFloatProperty(scaleMixKey, defaultFloat("transformConstraint", "scaleMix"), "transformConstraint.scaleMix"),
        hasShearMix = shearMixKey in properties,
        shearMix = properties.readOptionalFloatProperty(shearMixKey, defaultFloat("transformConstraint", "shearMix"), "transformConstraint.shearMix"),
      )
    of physicsConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, orderKey, channelsKey, inertiaKey, strengthKey, dampingKey, massKey, gravityKey, windKey, physicsMixKey])
      if channelsKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb physicsConstraint.channels is required")
      let channelMask = readVaruintPayload(properties[channelsKey], "physicsConstraint.channels")
      physicsConstraints.add physicsConstraintData(
        properties.readStringProperty(strings, nameKey, "physicsConstraint.name"),
        properties.readStringProperty(strings, boneKey, "physicsConstraint.bone"),
        physicsChannelsFromMask(channelMask, "physicsConstraint.channels"),
        order = properties.readOptionalIntProperty(orderKey, defaultInt("physicsConstraint", "order"), "physicsConstraint.order"),
        hasInertia = inertiaKey in properties,
        inertia = properties.readOptionalFloatProperty(inertiaKey, defaultFloat("physicsConstraint", "inertia"), "physicsConstraint.inertia"),
        hasStrength = strengthKey in properties,
        strength = properties.readOptionalFloatProperty(strengthKey, defaultFloat("physicsConstraint", "strength"), "physicsConstraint.strength"),
        hasDamping = dampingKey in properties,
        damping = properties.readOptionalFloatProperty(dampingKey, defaultFloat("physicsConstraint", "damping"), "physicsConstraint.damping"),
        hasMass = massKey in properties,
        mass = properties.readOptionalFloatProperty(massKey, defaultFloat("physicsConstraint", "mass"), "physicsConstraint.mass"),
        hasGravity = gravityKey in properties,
        gravity = properties.readOptionalFloatProperty(gravityKey, defaultFloat("physicsConstraint", "gravity"), "physicsConstraint.gravity"),
        hasWind = windKey in properties,
        wind = properties.readOptionalFloatProperty(windKey, defaultFloat("physicsConstraint", "wind"), "physicsConstraint.wind"),
        hasMix = physicsMixKey in properties,
        mix = properties.readOptionalFloatProperty(physicsMixKey, defaultFloat("physicsConstraint", "physicsMix"), "physicsConstraint.physicsMix"),
      )
    of parameterTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, parameterMinKey, parameterMaxKey, parameterDefaultKey])
      let paramName = properties.readStringProperty(strings, nameKey, "parameter.name")
      let paramMin = properties.readFloatProperty(parameterMinKey, "parameter.min")
      let paramMax = properties.readFloatProperty(parameterMaxKey, "parameter.max")
      let paramDefault =
        if parameterDefaultKey in properties:
          readF32Payload(properties[parameterDefaultKey], "parameter.default")
        else:
          0.0
      loadedParameters.add ParameterAxis(
        name: paramName,
        minValue: paramMin,
        maxValue: paramMax,
        defaultValue: paramDefault,
      )
    of deformerTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([deformerIdKey, parentKey, deformerOrderKey, deformerKindKey])
      pendingId = readStringPayload(
        (if deformerIdKey in properties: properties[deformerIdKey] else: raise newBonyLoadError(schemaViolation, ".bnb deformer.id is required")),
        strings,
      )
      pendingParent = properties.readOptionalStringProperty(strings, parentKey, "")
      pendingOrder = properties.readOptionalUintProperty(deformerOrderKey, 0'u32, "deformer.order")
      let kindStr = readStringPayload(
        (if deformerKindKey in properties: properties[deformerKindKey] else: raise newBonyLoadError(schemaViolation, ".bnb deformer.kind is required")),
        strings,
      )
      case kindStr
      of "warp": pendingKind = warpDeformerKind
      of "rotation": pendingKind = rotationDeformerKind
      else: raise newBonyLoadError(schemaViolation, ".bnb deformer.kind must be 'warp' or 'rotation'")
      deformerPending = true
      geometryReady = false
      blendPending = false
      pendingBlendAxes = @[]
      pendingKeyforms = @[]
    of warpLatticeTypeKey:
      if not deformerPending or pendingKind != warpDeformerKind:
        raise newBonyLoadError(schemaViolation, ".bnb warpLattice record without preceding warp deformer")
      let properties = record.propertyMap([warpRowsKey, warpColsKey, warpMinXKey, warpMinYKey, warpMaxXKey, warpMaxYKey, warpControlPointsKey])
      let rows = properties.readOptionalUintProperty(warpRowsKey, 2'u32, "warpLattice.rows")
      let cols = properties.readOptionalUintProperty(warpColsKey, 2'u32, "warpLattice.cols")
      let minX = readF32Payload((if warpMinXKey in properties: properties[warpMinXKey] else: raise newBonyLoadError(schemaViolation, ".bnb warpLattice.minX is required")), "warpLattice.minX")
      let minY = readF32Payload((if warpMinYKey in properties: properties[warpMinYKey] else: raise newBonyLoadError(schemaViolation, ".bnb warpLattice.minY is required")), "warpLattice.minY")
      let maxX = readF32Payload((if warpMaxXKey in properties: properties[warpMaxXKey] else: raise newBonyLoadError(schemaViolation, ".bnb warpLattice.maxX is required")), "warpLattice.maxX")
      let maxY = readF32Payload((if warpMaxYKey in properties: properties[warpMaxYKey] else: raise newBonyLoadError(schemaViolation, ".bnb warpLattice.maxY is required")), "warpLattice.maxY")
      if warpControlPointsKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb warpLattice.controlPoints is required")
      let controlPoints = readControlPointsPayload(properties[warpControlPointsKey])
      pendingWarp = WarpLattice(rows: rows, cols: cols, minX: minX, minY: minY, maxX: maxX, maxY: maxY, controlPoints: controlPoints)
      geometryReady = true
    of rotationDeformerTypeKey:
      if not deformerPending or pendingKind != rotationDeformerKind:
        raise newBonyLoadError(schemaViolation, ".bnb rotationDeformer record without preceding rotation deformer")
      let properties = record.propertyMap([rotationPivotXKey, rotationPivotYKey, rotationAngleDegreesKey, rotationScaleXKey, rotationScaleYKey, rotationOpacityKey])
      let pivotX = readF32Payload((if rotationPivotXKey in properties: properties[rotationPivotXKey] else: raise newBonyLoadError(schemaViolation, ".bnb rotationDeformer.pivotX is required")), "rotationDeformer.pivotX")
      let pivotY = readF32Payload((if rotationPivotYKey in properties: properties[rotationPivotYKey] else: raise newBonyLoadError(schemaViolation, ".bnb rotationDeformer.pivotY is required")), "rotationDeformer.pivotY")
      let angleDeg = readF32Payload((if rotationAngleDegreesKey in properties: properties[rotationAngleDegreesKey] else: raise newBonyLoadError(schemaViolation, ".bnb rotationDeformer.angleDegrees is required")), "rotationDeformer.angleDegrees")
      let scaleX = readF32Payload(properties.getOrDefault(rotationScaleXKey, writeF32Payload(1.0)), "rotationDeformer.scaleX")
      let scaleY = readF32Payload(properties.getOrDefault(rotationScaleYKey, writeF32Payload(1.0)), "rotationDeformer.scaleY")
      let opacity = readF32Payload(properties.getOrDefault(rotationOpacityKey, writeF32Payload(1.0)), "rotationDeformer.opacity")
      pendingRotation = RotationDeformer(pivotX: pivotX, pivotY: pivotY, angleDegrees: angleDeg, scaleX: scaleX, scaleY: scaleY, opacity: opacity)
      geometryReady = true
    of keyformBlendTypeKey:
      if not deformerPending or not geometryReady:
        raise newBonyLoadError(schemaViolation, ".bnb keyformBlend record without preceding deformer geometry")
      let properties = record.propertyMap([blendValueCountKey, blendAxesKey])
      let valueCount = properties.readRequiredUintProperty(blendValueCountKey, "keyformBlend.valueCount")
      if blendAxesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb keyformBlend.axes is required")
      var paramMap = initTable[string, ParameterAxis]()
      for p in loadedParameters:
        paramMap[p.name] = p
      pendingBlendAxes = readBlendAxesPayload(properties[blendAxesKey], strings, paramMap)
      pendingBlendValueCount = int(valueCount)
      pendingKeyforms = @[]
      blendPending = true
    of keyformTypeKey:
      if not blendPending:
        raise newBonyLoadError(schemaViolation, ".bnb keyform record without preceding keyformBlend")
      let properties = record.propertyMap([blendCoordinatesKey, blendValuesKey])
      if blendCoordinatesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb keyform.coordinates is required")
      if blendValuesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb keyform.values is required")
      let coordFs = readBlendF32sPayload(properties[blendCoordinatesKey], pendingBlendAxes.len, "keyform.coordinates")
      let valueFs = readBlendF32sPayload(properties[blendValuesKey], pendingBlendValueCount, "keyform.values")
      var coordinates: seq[ParameterSample]
      for axisIndex, axis in pendingBlendAxes:
        coordinates.add ParameterSample(name: axis.name, value: coordFs[axisIndex])
      pendingKeyforms.add Keyform(coordinates: coordinates, values: valueFs)
    else:
      flushPendingIfAny()
      discard

  flushPendingIfAny()

  if not hasSkeleton:
    raise newBonyLoadError(schemaViolation, ".bnb skeleton object is required")
  skeletonData(headerValue, bones, slots, regions, pathAttachments, paths, loadedParameters, loadedDeformers, ikConstraints, transformConstraints, physicsConstraints)


proc withTarget(timeline: BoneTimeline; target: string): BoneTimeline =
  case timeline.kind
  of inheritTimeline:
    boneInheritTimeline(target, timeline.inheritKeys)
  of translateTimeline, scaleTimeline, shearTimeline:
    boneVectorTimeline(target, timeline.kind, timeline.vectorKeys)
  else:
    boneScalarTimeline(target, timeline.kind, timeline.scalarKeys)


proc withTarget(timeline: SlotTimeline; target: string): SlotTimeline =
  case timeline.kind
  of attachmentTimeline:
    slotAttachmentTimeline(target, timeline.attachmentKeys)
  of rgbaTimeline, rgbTimeline, alphaTimeline:
    slotColorTimeline(target, timeline.kind, timeline.colorKeys)
  of rgba2Timeline:
    slotColor2Timeline(target, timeline.color2Keys)
  of sequenceTimeline:
    slotSequenceTimeline(target, timeline.sequenceKeys)


proc decodeAnimationObjects(
  objects: openArray[BnbObjectRecord];
  strings: BnbStringTable;
  skeleton: SkeletonData;
): seq[AnimationClip] =
  var currentName = ""
  var currentBoneTimelines: seq[BoneTimeline]
  var currentSlotTimelines: seq[SlotTimeline]
  var seen = initHashSet[string]()

  template flushAnimation() =
    if currentName.len > 0:
      if currentName in seen:
        raise newBonyLoadError(duplicateKey, "duplicate animation name: " & currentName)
      seen.incl(currentName)
      result.add animationClip(skeleton, currentName, currentBoneTimelines, currentSlotTimelines)
      currentName = ""
      currentBoneTimelines = @[]
      currentSlotTimelines = @[]

  for record in objects:
    case record.typeKey
    of animationClipTypeKey:
      flushAnimation()
      let properties = record.propertyMap([nameKey])
      currentName = properties.readStringProperty(strings, nameKey, "animationClip.name")
    of boneTimelineTypeKey:
      if currentName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb boneTimeline record without animationClip")
      let properties = record.propertyMap([boneIndexKey, boneTimelineKindKey, timelineKeysKey])
      let boneIndex = int(properties.readRequiredUintProperty(boneIndexKey, "boneTimeline.boneIndex"))
      if boneIndex < 0 or boneIndex >= skeleton.bones.len:
        raise newBonyLoadError(unknownRequiredReference, ".bnb boneTimeline boneIndex is out of range")
      if timelineKeysKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb boneTimeline.timelineKeys is required")
      let kind = boneTimelineKindFromTag(properties.readRequiredUintProperty(boneTimelineKindKey, "boneTimeline.kind"))
      currentBoneTimelines.add readBoneTimelineKeys(kind, properties[timelineKeysKey], "boneTimeline.timelineKeys").withTarget(skeleton.bones[boneIndex].name)
    of slotTimelineTypeKey:
      if currentName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb slotTimeline record without animationClip")
      let properties = record.propertyMap([slotIndexKey, slotTimelineKindKey, timelineKeysKey])
      let slotIndex = int(properties.readRequiredUintProperty(slotIndexKey, "slotTimeline.slotIndex"))
      if slotIndex < 0 or slotIndex >= skeleton.slots.len:
        raise newBonyLoadError(unknownRequiredReference, ".bnb slotTimeline slotIndex is out of range")
      if timelineKeysKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb slotTimeline.timelineKeys is required")
      let kind = slotTimelineKindFromTag(properties.readRequiredUintProperty(slotTimelineKindKey, "slotTimeline.kind"))
      currentSlotTimelines.add readSlotTimelineKeys(kind, properties[timelineKeysKey], skeleton.regions, "slotTimeline.timelineKeys").withTarget(skeleton.slots[slotIndex].name)
    of stateMachineTypeKey:
      flushAnimation()
    else:
      discard
  flushAnimation()


proc animationByIndex(animations: openArray[AnimationClip]; index: uint32; context: string): AnimationClip =
  if int(index) >= animations.len:
    raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " animation index is out of range")
  animations[int(index)]


proc inputByIndex(inputs: openArray[StateMachineInput]; index: uint32; context: string): StateMachineInput =
  if int(index) >= inputs.len:
    raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " input index is out of range")
  inputs[int(index)]


proc stateNameByIndex(states: openArray[StateMachineState]; index: uint32; context: string): string =
  if int(index) >= states.len:
    raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " state index is out of range")
  states[int(index)].name


proc decodeStateMachineObjects(
  objects: openArray[BnbObjectRecord];
  strings: BnbStringTable;
  animations: openArray[AnimationClip];
): seq[StateMachine] =
  var machineName = ""
  var inputs: seq[StateMachineInput]
  var layers: seq[StateMachineLayer]
  var listeners: seq[StateMachineListener]
  var layerName = ""
  var layerInitialIndex = 0'u32
  var layerStates: seq[StateMachineState]
  var layerTransitions: seq[StateMachineTransition]
  var pendingTransitionFrom = ""
  var pendingTransitionTo = ""
  var pendingConditions: seq[StateMachineCondition]
  var seenMachines = initHashSet[string]()

  template flushTransition() =
    if pendingTransitionFrom.len > 0:
      layerTransitions.add stateMachineTransition(pendingTransitionFrom, pendingTransitionTo, pendingConditions)
      pendingTransitionFrom = ""
      pendingTransitionTo = ""
      pendingConditions = @[]

  template flushLayer() =
    if layerName.len > 0:
      flushTransition()
      layers.add stateMachineLayer(layerName, layerStates, stateNameByIndex(layerStates, layerInitialIndex, "stateMachineLayer.initialStateIndex"), layerTransitions)
      layerName = ""
      layerInitialIndex = 0'u32
      layerStates = @[]
      layerTransitions = @[]

  template flushMachine() =
    if machineName.len > 0:
      flushLayer()
      if machineName in seenMachines:
        raise newBonyLoadError(duplicateKey, "duplicate state machine name: " & machineName)
      seenMachines.incl(machineName)
      result.add stateMachine(machineName, layers, inputs, listeners)
      machineName = ""
      inputs = @[]
      layers = @[]
      listeners = @[]

  for record in objects:
    case record.typeKey
    of stateMachineTypeKey:
      flushMachine()
      let properties = record.propertyMap([nameKey])
      machineName = properties.readStringProperty(strings, nameKey, "stateMachine.name")
    of stateMachineInputTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineInput record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([nameKey, stateMachineInputKindKey, inputDefaultBoolKey, inputDefaultNumberKey])
      let name = properties.readStringProperty(strings, nameKey, "stateMachineInput.name")
      let kind = inputKindFromTag(properties.readRequiredUintProperty(stateMachineInputKindKey, "stateMachineInput.kind"))
      case kind
      of boolInput:
        if inputDefaultNumberKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb bool input must not contain number default")
        inputs.add stateMachineBoolInput(name, properties.readOptionalBoolProperty(inputDefaultBoolKey, defaultBool("stateMachineInput", "inputDefaultBool"), "stateMachineInput.defaultBool"))
      of numberInput:
        if inputDefaultBoolKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb number input must not contain bool default")
        inputs.add stateMachineNumberInput(name, properties.readOptionalFloatProperty(inputDefaultNumberKey, defaultFloat("stateMachineInput", "inputDefaultNumber"), "stateMachineInput.defaultNumber"))
      of triggerInput:
        if inputDefaultBoolKey in properties or inputDefaultNumberKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb trigger input must not contain defaults")
        inputs.add stateMachineTriggerInput(name)
    of stateMachineLayerTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineLayer record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([nameKey, initialStateIndexKey])
      layerName = properties.readStringProperty(strings, nameKey, "stateMachineLayer.name")
      layerInitialIndex = properties.readOptionalUintProperty(initialStateIndexKey, uint32(defaultInt("stateMachineLayer", "initialStateIndex")), "stateMachineLayer.initialStateIndex")
    of stateMachineStateTypeKey:
      if layerName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineState record without stateMachineLayer")
      flushTransition()
      let properties = record.propertyMap([nameKey, stateMachineStateKindKey, stateClipIndexKey, stateLoopKey, stateBlendInputIndexKey])
      let name = properties.readStringProperty(strings, nameKey, "stateMachineState.name")
      let kind = stateKindFromTag(properties.readRequiredUintProperty(stateMachineStateKindKey, "stateMachineState.kind"))
      case kind
      of clipState:
        if stateBlendInputIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb clip state must not contain blend input")
        let clip = animationByIndex(animations, properties.readRequiredUintProperty(stateClipIndexKey, "stateMachineState.clip"), "stateMachineState.clip")
        layerStates.add stateMachineState(name, clip, properties.readOptionalBoolProperty(stateLoopKey, defaultBool("stateMachineState", "stateLoop"), "stateMachineState.loop"))
      of blend1DState:
        if stateClipIndexKey in properties or stateLoopKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb blend1d state must not contain direct clip fields")
        let input = inputByIndex(inputs, properties.readRequiredUintProperty(stateBlendInputIndexKey, "stateMachineState.blendInput"), "stateMachineState.blendInput")
        layerStates.add StateMachineState(name: name, kind: blend1DState, blendInput: input.name)
    of stateMachineBlendClipTypeKey:
      if layerStates.len == 0 or layerStates[^1].kind != blend1DState:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineBlendClip record without blend1d state")
      let properties = record.propertyMap([blendClipAnimationIndexKey, blendClipValueKey, blendClipLoopKey])
      let clip = animationByIndex(animations, properties.readRequiredUintProperty(blendClipAnimationIndexKey, "stateMachineBlendClip.animation"), "stateMachineBlendClip.animation")
      let value = properties.readFloatProperty(blendClipValueKey, "stateMachineBlendClip.value")
      let loop = properties.readOptionalBoolProperty(blendClipLoopKey, defaultBool("stateMachineBlendClip", "blendClipLoop"), "stateMachineBlendClip.loop")
      layerStates[^1].blendClips.add stateMachineBlendClip(clip, value, loop)
    of stateMachineTransitionTypeKey:
      if layerName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineTransition record without stateMachineLayer")
      flushTransition()
      let properties = record.propertyMap([transitionFromStateIndexKey, transitionToStateIndexKey])
      pendingTransitionFrom = stateNameByIndex(layerStates, properties.readRequiredUintProperty(transitionFromStateIndexKey, "stateMachineTransition.from"), "stateMachineTransition.from")
      pendingTransitionTo = stateNameByIndex(layerStates, properties.readRequiredUintProperty(transitionToStateIndexKey, "stateMachineTransition.to"), "stateMachineTransition.to")
    of stateMachineConditionTypeKey:
      if pendingTransitionFrom.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineCondition record without stateMachineTransition")
      let properties = record.propertyMap([conditionInputIndexKey, stateMachineConditionKindKey, conditionBoolValueKey, conditionNumberValueKey])
      let input = inputByIndex(inputs, properties.readRequiredUintProperty(conditionInputIndexKey, "stateMachineCondition.input"), "stateMachineCondition.input")
      let kind = conditionKindFromTag(properties.readRequiredUintProperty(stateMachineConditionKindKey, "stateMachineCondition.kind"))
      case kind
      of boolEqualsCondition:
        if conditionNumberValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb bool condition must not contain number value")
        pendingConditions.add stateMachineBoolCondition(input.name, properties.readOptionalBoolProperty(conditionBoolValueKey, defaultBool("stateMachineCondition", "conditionBoolValue"), "stateMachineCondition.bool"))
      of numberEqualsCondition, numberGreaterCondition, numberGreaterOrEqualCondition, numberLessCondition, numberLessOrEqualCondition:
        if conditionBoolValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb number condition must not contain bool value")
        pendingConditions.add stateMachineNumberCondition(input.name, kind, properties.readFloatProperty(conditionNumberValueKey, "stateMachineCondition.number"))
      of triggerSetCondition:
        if conditionBoolValueKey in properties or conditionNumberValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb trigger condition must not contain values")
        pendingConditions.add stateMachineTriggerCondition(input.name)
    of stateMachineListenerTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineListener record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([nameKey, stateMachineListenerKindKey, listenerLayerIndexKey, listenerFromStateIndexKey, listenerToStateIndexKey])
      let name = properties.readStringProperty(strings, nameKey, "stateMachineListener.name")
      let kind = listenerKindFromTag(properties.readRequiredUintProperty(stateMachineListenerKindKey, "stateMachineListener.kind"))
      let layerIndex = int(properties.readRequiredUintProperty(listenerLayerIndexKey, "stateMachineListener.layer"))
      if layerIndex >= layers.len:
        raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.layer is out of range")
      let layer = layers[layerIndex]
      case kind
      of stateEnterListener:
        if listenerFromStateIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb enter listener must not contain from state")
        listeners.add stateMachineStateEnterListener(name, layer.name, stateNameByIndex(layer.states, properties.readRequiredUintProperty(listenerToStateIndexKey, "stateMachineListener.to"), "stateMachineListener.to"))
      of stateExitListener:
        if listenerToStateIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb exit listener must not contain to state")
        listeners.add stateMachineStateExitListener(name, layer.name, stateNameByIndex(layer.states, properties.readRequiredUintProperty(listenerFromStateIndexKey, "stateMachineListener.from"), "stateMachineListener.from"))
      of transitionListener:
        listeners.add stateMachineTransitionListener(
          name,
          layer.name,
          stateNameByIndex(layer.states, properties.readRequiredUintProperty(listenerFromStateIndexKey, "stateMachineListener.from"), "stateMachineListener.from"),
          stateNameByIndex(layer.states, properties.readRequiredUintProperty(listenerToStateIndexKey, "stateMachineListener.to"), "stateMachineListener.to"),
        )
    else:
      discard
  flushMachine()


proc decodeAssetObjects(objects: openArray[BnbObjectRecord]; strings: BnbStringTable): BonyAsset =
  let skeleton = decodeSkeletonObjects(objects, strings)
  let animations = decodeAnimationObjects(objects, strings, skeleton)
  bonyAsset(skeleton, animations, decodeStateMachineObjects(objects, strings, animations))


proc loadBonyBnb*(input: openArray[byte]): SkeletonData =
  var index = 0
  let header = input.readHeader(index)
  let toc = input.readToc(index)
  let strings =
    if (header.flags and bnbStringTableFlag) != 0:
      input.readStringTable(index)
    else:
      initStringTable()
  let objects = input.readObjectStream(index, toc)
  discard input.readEmbeddedAtlas(index, header)
  decodeSkeletonObjects(objects, strings)


proc loadBonyBnbAsset*(input: openArray[byte]): BonyAsset =
  var index = 0
  let header = input.readHeader(index)
  let toc = input.readToc(index)
  let strings =
    if (header.flags and bnbStringTableFlag) != 0:
      input.readStringTable(index)
    else:
      initStringTable()
  let objects = input.readObjectStream(index, toc)
  discard input.readEmbeddedAtlas(index, header)
  decodeAssetObjects(objects, strings)


proc readKnownObjectStream(input: openArray[byte]; index: var int; toc: openArray[BnbTocEntry]): seq[BnbObjectRecord] =
  var objectCount = 0'u64
  while true:
    let record = input.readObjectRecord(index, toc)
    if record.typeKey == 0:
      return
    if objectCount >= bnbMaxObjects:
      raise newBonyLoadError(resourceLimitExceeded, ".bnb object stream has too many objects")
    inc objectCount
    if not record.typeKey.isKnownTypeKey:
      raise newBonyLoadError(schemaViolation, ".bnb JSON conversion cannot preserve unknown object type: " & $record.typeKey)
    for property in record.properties:
      if not property.propertyKey.isKnownPropertyKey:
        raise newBonyLoadError(
          schemaViolation,
          ".bnb JSON conversion cannot preserve unknown property key: " & $property.propertyKey,
        )
    result.add record


proc loadKnownBonyBnb*(input: openArray[byte]): SkeletonData =
  var index = 0
  let header = input.readHeader(index)
  if (header.flags and bnbEmbeddedAtlasFlag) != 0:
    raise newBonyLoadError(schemaViolation, ".bnb JSON conversion cannot preserve embedded atlas bytes")
  let toc = input.readToc(index)
  let strings =
    if (header.flags and bnbStringTableFlag) != 0:
      input.readStringTable(index)
    else:
      initStringTable()
  let objects = input.readKnownObjectStream(index, toc)
  discard input.readEmbeddedAtlas(index, header)
  decodeSkeletonObjects(objects, strings)


proc loadKnownBonyBnbAsset*(input: openArray[byte]): BonyAsset =
  var index = 0
  let header = input.readHeader(index)
  if (header.flags and bnbEmbeddedAtlasFlag) != 0:
    raise newBonyLoadError(schemaViolation, ".bnb JSON conversion cannot preserve embedded atlas bytes")
  let toc = input.readToc(index)
  let strings =
    if (header.flags and bnbStringTableFlag) != 0:
      input.readStringTable(index)
    else:
      initStringTable()
  let objects = input.readKnownObjectStream(index, toc)
  discard input.readEmbeddedAtlas(index, header)
  decodeAssetObjects(objects, strings)
