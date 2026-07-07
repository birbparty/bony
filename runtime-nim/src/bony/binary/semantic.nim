## M6/M7 semantic .bnb encoder/decoder for the current SkeletonData model.

import std/[algorithm, sequtils, sets, tables]

import bony/anim/timelines
import bony/asset
import bony/binary/framing
import bony/generated/wire
import bony/model
import bony/wiremeta
import bony/mesh/attachments
import bony/deform/deformers
import bony/deform/keyforms
import bony/statemachine/core

const
  skeletonTypeKey = 1'u64
  boneTypeKey = 2'u64
  slotTypeKey = 1000'u64
  regionTypeKey = 1001'u64
  pointAttachmentTypeKey = 1002'u64
  boundingBoxAttachmentTypeKey = 1003'u64
  clippingAttachmentTypeKey = 3000'u64
  meshAttachmentTypeKey = 3001'u64
  skinTypeKey = 3003'u64
  skinEntryTypeKey = 3004'u64
  nestedRigAttachmentTypeKey = 3005'u64
  pathTypeKey = 4000'u64
  pathAttachmentTypeKey = 4001'u64
  ikConstraintTypeKey = 4002'u64
  transformConstraintTypeKey = 4003'u64
  physicsConstraintTypeKey = 4004'u64
  animationClipTypeKey = 2000'u64
  boneTimelineTypeKey = 2001'u64
  slotTimelineTypeKey = 2002'u64
  eventTimelineTypeKey = 2003'u64
  deformTimelineTypeKey = 3002'u64
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
  slotKey = 1011'u64
  boneKey = 1012'u64
  attachmentKey = 1013'u64
  widthKey = 1014'u64
  heightKey = 1015'u64
  texturePageKey = 8000'u64
  u0Key = 8001'u64
  v0Key = 8002'u64
  u1Key = 8003'u64
  v1Key = 8004'u64
  alphaModeKey = 8005'u64
  verticesKey = 3000'u64
  untilSlotKey = 3001'u64
  meshWeightedKey = 3002'u64
  meshVerticesKey = 3003'u64
  meshUvsKey = 3004'u64
  meshTrianglesKey = 3005'u64
  deformSkinKey = 3006'u64
  deformAttachmentKey = 3007'u64
  deformVertexCountKey = 3008'u64
  deformKeysKey = 3009'u64
  skinAttachmentKey = 3010'u64
  skinTargetKey = 3011'u64
  nestedSkeletonKey = 3012'u64
  nestedSkinKey = 3013'u64
  nestedAnimationKey = 3014'u64
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
  skinRequiredKey = 4027'u64
  skinBonesKey = 4028'u64
  skinIkConstraintsKey = 4029'u64
  skinTransformConstraintsKey = 4030'u64
  skinPathConstraintsKey = 4031'u64
  skinPhysicsConstraintsKey = 4032'u64
  boneIndexKey = 2000'u64
  boneTimelineKindKey = 2001'u64
  slotIndexKey = 2002'u64
  slotTimelineKindKey = 2003'u64
  timelineKeysKey = 2004'u64
  eventKeysKey = 2005'u64
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
  listenerSlotIndexKey = 7064'u64
  listenerHelperKindKey = 7065'u64
  listenerHelperTargetKey = 7066'u64
  listenerInputIndexKey = 7067'u64
  listenerBoolValueKey = 7068'u64
  listenerNumberValueKey = 7069'u64
  listenerHitRadiusKey = 7070'u64

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


func bnbScalarString(propertyKey: uint64; value: string): BonyBnbScalarProperty =
  BonyBnbScalarProperty(propertyKey: propertyKey, value: bonyStringValue(value))


func bnbScalarFloat(propertyKey: uint64; value: float64): BonyBnbScalarProperty =
  BonyBnbScalarProperty(propertyKey: propertyKey, value: bonyF32Value(value))


func bnbScalarF64(propertyKey: uint64; value: float64): BonyBnbScalarProperty =
  BonyBnbScalarProperty(propertyKey: propertyKey, value: bonyF64Value(value))


func bnbScalarBool(propertyKey: uint64; value: bool): BonyBnbScalarProperty =
  BonyBnbScalarProperty(propertyKey: propertyKey, value: bonyBoolValue(value))


func bnbScalarInt(propertyKey: uint64; value: int): BonyBnbScalarProperty =
  BonyBnbScalarProperty(propertyKey: propertyKey, value: bonyIntValue(value.int64))


func bnbScalarUint(propertyKey: uint64; value: uint64): BonyBnbScalarProperty =
  BonyBnbScalarProperty(propertyKey: propertyKey, value: bonyUintValue(value))


proc addBnbScalarProperty(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  table: var BnbStringTable;
  property: BonyBnbScalarProperty;
) =
  case property.value.kind
  of bskString:
    properties.addProperty(toc, property.propertyKey, writeStringPayloadBytes(table, property.value.stringValue))
  of bskF32:
    properties.addProperty(toc, property.propertyKey, writeF32Payload(property.value.floatValue))
  of bskF64:
    properties.addProperty(toc, property.propertyKey, writeF64Payload(property.value.floatValue, "scalar." & $property.propertyKey))
  of bskBool:
    properties.addProperty(toc, property.propertyKey, writeBoolPayload(property.value.boolValue))
  of bskVarint:
    if property.value.intValue < int64(low(int)) or property.value.intValue > int64(high(int)):
      raise newBonyLoadError(numericOutOfRange, ".bnb scalar varint is out of range: " & $property.propertyKey)
    properties.addProperty(toc, property.propertyKey, writeVarintPayload(property.value.intValue.int))
  of bskVaruint:
    properties.addProperty(toc, property.propertyKey, writeVaruintPayload(property.value.uintValue))


proc addBnbScalarProperties(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  table: var BnbStringTable;
  scalars: openArray[BonyBnbScalarProperty];
) =
  for scalar in scalars:
    properties.addBnbScalarProperty(toc, table, scalar)


proc bnbScalarIndex(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64): int =
  for index, property in properties:
    if property.propertyKey == propertyKey:
      return index
  -1


proc addBnbScalarPropertyIfPresent(
  properties: var seq[BnbPropertyRecord];
  toc: var Table[uint64, uint8];
  table: var BnbStringTable;
  scalars: openArray[BonyBnbScalarProperty];
  propertyKey: uint64;
) =
  let index = bnbScalarIndex(scalars, propertyKey)
  if index >= 0:
    properties.addBnbScalarProperty(toc, table, scalars[index])


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


proc bnbScalarValueFromPayload(
  payload: openArray[byte];
  spec: BonyScalarPropertySpec;
  table: BnbStringTable;
  context: string;
): BonyScalarValue =
  case spec.kind
  of bskString:
    bonyStringValue(readStringPayload(payload, table))
  of bskF32:
    bonyF32Value(readF32Payload(payload, context))
  of bskF64:
    bonyF64Value(readF64Payload(payload, context))
  of bskBool:
    bonyBoolValue(readBoolPayload(payload, context))
  of bskVarint:
    bonyIntValue(readVarintPayload(payload, context).int64)
  of bskVaruint:
    bonyUintValue(readVaruintPayload(payload, context))


proc bnbScalarsFromProperties(
  properties: Table[uint64, seq[byte]];
  specs: openArray[BonyScalarPropertySpec];
  table: BnbStringTable;
  context: string;
): seq[BonyBnbScalarProperty] =
  for spec in specs:
    if spec.propertyKey in properties:
      result.add BonyBnbScalarProperty(
        propertyKey: spec.propertyKey,
        value: bnbScalarValueFromPayload(properties[spec.propertyKey], spec, table, context & "." & spec.propertyId),
      )


type BonyBnbScalarDecoder = proc(
  properties: openArray[BonyBnbScalarProperty]
): seq[BonyBnbScalarProperty]


proc decodeBnbScalarsForLoad(
  decoder: BonyBnbScalarDecoder;
  properties: openArray[BonyBnbScalarProperty];
  context: string;
): seq[BonyBnbScalarProperty] =
  try:
    decoder(properties)
  except ValueError as exc:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & ": " & exc.msg)


proc decodeBnbScalarsFromProperties(
  decoder: BonyBnbScalarDecoder;
  properties: Table[uint64, seq[byte]];
  specs: openArray[BonyScalarPropertySpec];
  table: BnbStringTable;
  context: string;
): seq[BonyBnbScalarProperty] =
  decodeBnbScalarsForLoad(decoder, bnbScalarsFromProperties(properties, specs, table, context), context)


proc bnbScalarValue(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64; context: string): BonyScalarValue =
  for property in properties:
    if property.propertyKey == propertyKey:
      return property.value
  raise newBonyLoadError(schemaViolation, ".bnb " & context & " is required")


proc bnbScalarString(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64; context: string): string =
  bnbScalarValue(properties, propertyKey, context).stringValue


proc bnbScalarFloat(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64; context: string): float64 =
  bnbScalarValue(properties, propertyKey, context).floatValue


proc bnbScalarBool(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64; context: string): bool =
  bnbScalarValue(properties, propertyKey, context).boolValue


proc bnbScalarInt(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64; context: string): int =
  let value = bnbScalarValue(properties, propertyKey, context).intValue
  if value < int64(low(int)) or value > int64(high(int)):
    raise newBonyLoadError(numericOutOfRange, ".bnb " & context & " is out of range")
  value.int


proc bnbScalarUint(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64; context: string): uint64 =
  bnbScalarValue(properties, propertyKey, context).uintValue


proc bnbScalarUint32(properties: openArray[BonyBnbScalarProperty]; propertyKey: uint64; context: string): uint32 =
  let value = properties.bnbScalarUint(propertyKey, context)
  if value > uint64(high(uint32)):
    raise newBonyLoadError(numericOutOfRange, ".bnb " & context & " varuint is out of uint32 range")
  uint32(value)


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


proc writePolygonVerticesPayload(vertices: openArray[float64]): seq[byte] =
  ## Frozen polygon vertices layout (docs/helper-geometry-attachment-contract.md):
  ## varuint point count followed by count*(f32 x, f32 y) little-endian pairs.
  ## `vertices` is a flat [x0, y0, x1, y1, ...] list, so point count = len div 2.
  result.writeVaruint(uint64(vertices.len div 2))
  for value in vertices:
    result.add writeF32Payload(value)


proc readPolygonVerticesPayload(payload: openArray[byte]; context: string): seq[float64] =
  var index = 0
  let count = payload.readVaruint(index)
  for _ in 0'u64 ..< count:
    if index + 8 > payload.len:
      raise newBonyLoadError(schemaViolation, ".bnb " & context & " vertices payload is truncated")
    let x = readF32Payload(payload[index ..< index + 4], context & ".vertices.x")
    index += 4
    let y = readF32Payload(payload[index ..< index + 4], context & ".vertices.y")
    index += 4
    result.add x
    result.add y
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " vertices payload has trailing bytes")


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


proc writeIndexListPayload(
  refs: openArray[string];
  indexByName: Table[string, int];
  context: string;
): seq[byte] =
  result.writeVaruint(uint64(refs.len))
  for item in refs:
    if item notin indexByName:
      raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " references unknown name: " & item)
    result.writeVaruint(uint64(indexByName[item]))


proc readIndexListPayload(payload: openArray[byte]; names: openArray[string]; context: string): seq[string] =
  var index = 0
  let count = payload.readVaruint(index)
  for _ in 0'u64 ..< count:
    let sourceIndex = payload.readVaruint(index)
    if sourceIndex >= uint64(names.len):
      raise newBonyLoadError(unknownRequiredReference, ".bnb " & context & " index is out of range")
    result.add names[int(sourceIndex)]
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " payload has trailing bytes")


proc writeMeshVerticesPayload(
  vertices: openArray[MeshVertex]; weighted: bool; table: var BnbStringTable;
): seq[byte] =
  ## Frozen mesh vertices layout (docs/mesh-attachment-contract.md): varuint
  ## vertexCount, then per vertex, unweighted -> (f32 x, f32 y), or weighted ->
  ## varuint influenceCount then influenceCount*(varuint boneStringIndex, f32
  ## bindX, f32 bindY, f32 weight). Bone names use the same string-table packing
  ## as ikConstraint bones (key 4014).
  result.writeVaruint(uint64(vertices.len))
  for vertex in vertices:
    if weighted:
      result.writeVaruint(uint64(vertex.influences.len))
      for influence in vertex.influences:
        result.writeVaruint(table.intern(influence.bone))
        result.add writeF32Payload(influence.bindX)
        result.add writeF32Payload(influence.bindY)
        result.add writeF32Payload(influence.weight)
    else:
      result.add writeF32Payload(vertex.x)
      result.add writeF32Payload(vertex.y)


proc readMeshVerticesPayload(
  payload: openArray[byte]; weighted: bool; table: BnbStringTable;
): seq[MeshVertex] =
  var index = 0
  let count = payload.readVaruint(index)
  for _ in 0'u64 ..< count:
    if weighted:
      let influenceCount = payload.readVaruint(index)
      var influences: seq[MeshInfluence]
      for _ in 0'u64 ..< influenceCount:
        let boneIndex = payload.readVaruint(index)
        if index + 12 > payload.len:
          raise newBonyLoadError(schemaViolation, ".bnb meshAttachment vertices payload is truncated")
        let bindX = readF32Payload(payload[index ..< index + 4], "meshAttachment.vertices.bindX")
        index += 4
        let bindY = readF32Payload(payload[index ..< index + 4], "meshAttachment.vertices.bindY")
        index += 4
        let weight = readF32Payload(payload[index ..< index + 4], "meshAttachment.vertices.weight")
        index += 4
        influences.add meshInfluence(table.stringAt(boneIndex), bindX, bindY, weight)
      result.add weightedMeshVertex(influences)
    else:
      if index + 8 > payload.len:
        raise newBonyLoadError(schemaViolation, ".bnb meshAttachment vertices payload is truncated")
      let x = readF32Payload(payload[index ..< index + 4], "meshAttachment.vertices.x")
      index += 4
      let y = readF32Payload(payload[index ..< index + 4], "meshAttachment.vertices.y")
      index += 4
      result.add unweightedMeshVertex(x, y)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb meshAttachment vertices payload has trailing bytes")


proc writeMeshUvsPayload(uvs: openArray[MeshUv]): seq[byte] =
  ## Frozen mesh uvs layout: varuint count then count*(f32 u, f32 v).
  result.writeVaruint(uint64(uvs.len))
  for uv in uvs:
    result.add writeF32Payload(uv.u)
    result.add writeF32Payload(uv.v)


proc readMeshUvsPayload(payload: openArray[byte]): seq[MeshUv] =
  var index = 0
  let count = payload.readVaruint(index)
  for _ in 0'u64 ..< count:
    if index + 8 > payload.len:
      raise newBonyLoadError(schemaViolation, ".bnb meshAttachment uvs payload is truncated")
    let u = readF32Payload(payload[index ..< index + 4], "meshAttachment.uvs.u")
    index += 4
    let v = readF32Payload(payload[index ..< index + 4], "meshAttachment.uvs.v")
    index += 4
    result.add meshUv(u, v)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb meshAttachment uvs payload has trailing bytes")


proc writeMeshTrianglesPayload(triangles: openArray[uint16]): seq[byte] =
  ## Frozen mesh triangles layout: varuint count then count*(varuint vertexIndex).
  result.writeVaruint(uint64(triangles.len))
  for triangle in triangles:
    result.writeVaruint(uint64(triangle))


proc readMeshTrianglesPayload(payload: openArray[byte]): seq[uint16] =
  var index = 0
  let count = payload.readVaruint(index)
  for _ in 0'u64 ..< count:
    let value = payload.readVaruint(index)
    if value > uint64(high(uint16)):
      raise newBonyLoadError(schemaViolation, ".bnb meshAttachment triangle index out of range")
    result.add uint16(value)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb meshAttachment triangles payload has trailing bytes")


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


proc helperKindTag(kind: PointerHelperTargetKind): uint64 = uint64(ord(kind))


proc helperKindFromTag(tag: uint64): PointerHelperTargetKind =
  if tag > uint64(ord(high(PointerHelperTargetKind))):
    raise newBonyLoadError(schemaViolation, ".bnb stateMachineListener.helperKind is invalid")
  PointerHelperTargetKind(tag)


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


proc writeDeformKeys(timeline: DeformTimeline): seq[byte] =
  ## Packed `deformKeys` payload; layout frozen by
  ## docs/deform-timeline-contract.md#packed-deformtimeline-byte-layout-bnb.
  result.writeVaruint(uint64(timeline.keys.len))
  for key in timeline.keys:
    result.writeF32To(key.time)
    result.writeVaruint(uint64(key.offset))
    result.writeVaruint(uint64(key.deltas.len))
    for delta in key.deltas:
      result.writeF32To(delta.x)
      result.writeF32To(delta.y)
    result.writeCurve(key.curve)


proc readDeformKeys(payload: openArray[byte]; context: string): seq[DeformKeyframe] =
  var index = 0
  let count = payload.readVaruint(index)
  if count == 0:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " must contain at least one key")
  for _ in 0'u64 ..< count:
    let time = payload.readF32From(index, context & ".time")
    let offset = payload.readVaruint(index)
    let deltaCount = payload.readVaruint(index)
    if deltaCount == 0:
      raise newBonyLoadError(schemaViolation, ".bnb " & context & " key must contain at least one delta")
    var deltas: seq[MeshDelta]
    for _ in 0'u64 ..< deltaCount:
      deltas.add meshDelta(
        payload.readF32From(index, context & ".dx"),
        payload.readF32From(index, context & ".dy"),
      )
    result.add deformKeyframe(time, uint32(offset), deltas, payload.readCurve(index, context & ".curve"))
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " has trailing bytes")


proc writeEventKeys(timeline: EventTimeline; table: var BnbStringTable): seq[byte] =
  ## Packed `eventKeys` payload; layout frozen by
  ## docs/event-timeline-contract.md#packed-eventtimeline-byte-layout-bnb.
  ## Events are not interpolated, so there is NO curve tail. The three
  ## per-keyframe strings (name, stringValue, audioPath) intern into the global
  ## string table in that row-major field order; intValue is a zigzag svarint.
  result.writeVaruint(uint64(timeline.keys.len))
  for key in timeline.keys:
    let event = key.event
    result.writeF32To(key.time)
    result.writeVaruint(table.intern(event.name))
    result.writeVarint(int64(event.intValue))
    result.writeF32To(event.floatValue)
    result.writeVaruint(table.intern(event.stringValue))
    result.writeVaruint(table.intern(event.audioPath))
    result.writeF32To(event.volume)
    result.writeF32To(event.balance)


proc readEventKeys(payload: openArray[byte]; table: BnbStringTable; context: string): seq[EventKeyframe] =
  var index = 0
  let count = payload.readVaruint(index)
  if count == 0:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " must contain at least one key")
  for _ in 0'u64 ..< count:
    let time = payload.readF32From(index, context & ".time")
    let name = table.stringAt(payload.readVaruint(index))
    let intValue = payload.readVarint(index)
    if intValue < int64(low(int32)) or intValue > int64(high(int32)):
      raise newBonyLoadError(numericOutOfRange, ".bnb " & context & ".intValue is out of int32 range")
    let floatValue = payload.readF32From(index, context & ".floatValue")
    let stringValue = table.stringAt(payload.readVaruint(index))
    let audioPath = table.stringAt(payload.readVaruint(index))
    let volume = payload.readF32From(index, context & ".volume")
    let balance = payload.readF32From(index, context & ".balance")
    let event = eventData(name, int32(intValue), floatValue, stringValue, audioPath, volume, balance)
    result.add eventKeyframe(time, event)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " has trailing bytes")


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
  skeletonProperties.addBnbScalarProperties(toc, table, encodeSkeletonBnbScalars([
    bnbScalarString(nameKey, data.header.name),
    bnbScalarString(versionKey, data.header.version),
  ]))
  result.add BnbObjectRecord(typeKey: skeletonTypeKey, properties: skeletonProperties)

  for bone in data.bones:
    let local = bone.local
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodeBoneBnbScalars([
      bnbScalarString(nameKey, bone.name),
      bnbScalarString(parentKey, bone.parent),
      bnbScalarFloat(xKey, local.x),
      bnbScalarFloat(yKey, local.y),
      bnbScalarFloat(rotationKey, local.rotation),
      bnbScalarFloat(scaleXKey, local.scaleX),
      bnbScalarFloat(scaleYKey, local.scaleY),
      bnbScalarFloat(shearXKey, local.shearX),
      bnbScalarFloat(shearYKey, local.shearY),
      bnbScalarBool(inheritRotationKey, local.inheritRotation),
      bnbScalarBool(inheritScaleKey, local.inheritScale),
      bnbScalarBool(inheritReflectionKey, local.inheritReflection),
      bnbScalarString(transformModeKey, transformModeName(local.transformMode)),
      bnbScalarBool(skinRequiredKey, bone.skinRequired),
    ]))
    result.add BnbObjectRecord(typeKey: boneTypeKey, properties: properties)

  for slot in data.slots:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodeSlotBnbScalars([
      bnbScalarString(nameKey, slot.name),
      bnbScalarString(boneKey, slot.bone),
      bnbScalarString(attachmentKey, slot.attachment),
    ]))
    result.add BnbObjectRecord(typeKey: slotTypeKey, properties: properties)

  for region in data.regions:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodeRegionBnbScalars([
      bnbScalarString(nameKey, region.name),
      bnbScalarFloat(widthKey, region.width),
      bnbScalarFloat(heightKey, region.height),
      bnbScalarString(texturePageKey, region.texturePage),
      bnbScalarFloat(u0Key, region.u0),
      bnbScalarFloat(v0Key, region.v0),
      bnbScalarFloat(u1Key, region.u1),
      bnbScalarFloat(v1Key, region.v1),
      bnbScalarString(alphaModeKey, region.alphaMode),
    ]))
    result.add BnbObjectRecord(typeKey: regionTypeKey, properties: properties)

  for point in data.pointAttachments:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodePointAttachmentBnbScalars([
      bnbScalarString(nameKey, point.name),
      bnbScalarFloat(xKey, point.x),
      bnbScalarFloat(yKey, point.y),
      bnbScalarFloat(rotationKey, point.rotation),
    ]))
    result.add BnbObjectRecord(typeKey: pointAttachmentTypeKey, properties: properties)

  for box in data.boundingBoxAttachments:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodeBoundingBoxAttachmentBnbScalars([
      bnbScalarString(nameKey, box.name),
    ]))
    properties.addProperty(toc, verticesKey, writePolygonVerticesPayload(box.vertices))
    result.add BnbObjectRecord(typeKey: boundingBoxAttachmentTypeKey, properties: properties)

  for pathAttachment in data.pathAttachments:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodePathAttachmentBnbScalars([
      bnbScalarString(nameKey, pathAttachment.name),
      bnbScalarF64(p0xKey, pathAttachment.p0x),
      bnbScalarF64(p0yKey, pathAttachment.p0y),
      bnbScalarF64(p1xKey, pathAttachment.p1x),
      bnbScalarF64(p1yKey, pathAttachment.p1y),
      bnbScalarF64(p2xKey, pathAttachment.p2x),
      bnbScalarF64(p2yKey, pathAttachment.p2y),
      bnbScalarF64(p3xKey, pathAttachment.p3x),
      bnbScalarF64(p3yKey, pathAttachment.p3y),
    ]))
    result.add BnbObjectRecord(typeKey: pathAttachmentTypeKey, properties: properties)

  # Clipping attachments: slot-bound convex-polygon masks. Emitted after helper
  # and path attachments. vertices packs as varuint count + f32 xy pairs;
  # untilSlot is value-gated (applyOnLoad:true, default "").
  for clip in data.clippingAttachments:
    var properties: seq[BnbPropertyRecord]
    let clipScalars = encodeClippingAttachmentBnbScalars([
      bnbScalarString(nameKey, clip.name),
      bnbScalarString(untilSlotKey, clip.untilSlot),
    ])
    properties.addBnbScalarPropertyIfPresent(toc, table, clipScalars, nameKey)
    properties.addProperty(toc, verticesKey, writePolygonVerticesPayload(clip.vertices))
    properties.addBnbScalarPropertyIfPresent(toc, table, clipScalars, untilSlotKey)
    result.add BnbObjectRecord(typeKey: clippingAttachmentTypeKey, properties: properties)

  # Mesh attachments: slot-bound deformable meshes. Emitted after clipping
  # attachments in registry property order [name, meshWeighted, meshVertices,
  # meshUvs, meshTriangles]. meshWeighted is value-gated (default false); the
  # packed vertices payload branches on it, and weighted influence bone names use
  # the same string-table packing as ikConstraint bones.
  for mesh in data.meshAttachments:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodeMeshAttachmentBnbScalars([
      bnbScalarString(nameKey, mesh.name),
      bnbScalarBool(meshWeightedKey, mesh.weighted),
    ]))
    properties.addProperty(toc, meshVerticesKey, writeMeshVerticesPayload(mesh.vertices, mesh.weighted, table))
    properties.addProperty(toc, meshUvsKey, writeMeshUvsPayload(mesh.uvs))
    properties.addProperty(toc, meshTrianglesKey, writeMeshTrianglesPayload(mesh.triangles))
    result.add BnbObjectRecord(typeKey: meshAttachmentTypeKey, properties: properties)

  for nested in data.nestedRigAttachments:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodeNestedRigAttachmentBnbScalars([
      bnbScalarString(nameKey, nested.name),
      bnbScalarString(nestedSkeletonKey, nested.skeleton),
      bnbScalarString(nestedSkinKey, nested.skin),
      bnbScalarString(nestedAnimationKey, nested.animation),
    ]))
    result.add BnbObjectRecord(typeKey: nestedRigAttachmentTypeKey, properties: properties)

  # IK section: canonical object-stream position is after attachments and before
  # paths (docs/binary-canonicalization.md). Emitted only when non-empty so
  # existing IK-free fixtures stay byte-identical. mix/bendPositive are
  # presence-gated (applyOnLoad:false) to stay symmetric with the JSON emitter;
  # order is value-gated (applyOnLoad:true).
  for ik in data.ikConstraints:
    var properties: seq[BnbPropertyRecord]
    let ikScalars = encodeIkConstraintBnbScalars([
      bnbScalarString(nameKey, ik.name),
      bnbScalarString(targetKey, ik.target),
      bnbScalarInt(orderKey, ik.order),
      bnbScalarBool(skinRequiredKey, ik.skinRequired),
    ])
    properties.addBnbScalarPropertyIfPresent(toc, table, ikScalars, nameKey)
    properties.addProperty(toc, bonesKey, writeBonesPayload(ik.bones, table))
    properties.addBnbScalarPropertyIfPresent(toc, table, ikScalars, targetKey)
    properties.addBnbScalarPropertyIfPresent(toc, table, ikScalars, orderKey)
    properties.addBnbScalarPropertyIfPresent(toc, table, ikScalars, skinRequiredKey)
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
    properties.addBnbScalarProperties(toc, table, encodeTransformConstraintBnbScalars([
      bnbScalarString(nameKey, tc.name),
      bnbScalarString(boneKey, tc.bone),
      bnbScalarString(targetKey, tc.target),
      bnbScalarInt(orderKey, tc.order),
      bnbScalarBool(skinRequiredKey, tc.skinRequired),
    ]))
    properties.addFloatIfNeeded(toc, translateMixKey, tc.translateMix, defaultFloat("transformConstraint", "translateMix"), required = tc.hasTranslateMix)
    properties.addFloatIfNeeded(toc, rotateMixKey, tc.rotateMix, defaultFloat("transformConstraint", "rotateMix"), required = tc.hasRotateMix)
    properties.addFloatIfNeeded(toc, scaleMixKey, tc.scaleMix, defaultFloat("transformConstraint", "scaleMix"), required = tc.hasScaleMix)
    properties.addFloatIfNeeded(toc, shearMixKey, tc.shearMix, defaultFloat("transformConstraint", "shearMix"), required = tc.hasShearMix)
    result.add BnbObjectRecord(typeKey: transformConstraintTypeKey, properties: properties)

  for path in data.paths:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodePathBnbScalars([
      bnbScalarString(nameKey, path.name),
      bnbScalarString(boneKey, path.bone),
      bnbScalarString(targetKey, path.target),
      bnbScalarString(pathKey, path.path),
      bnbScalarInt(orderKey, path.order),
      bnbScalarBool(skinRequiredKey, path.skinRequired),
    ]))
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
    properties.addBnbScalarProperties(toc, table, encodePhysicsConstraintBnbScalars([
      bnbScalarString(nameKey, pc.name),
      bnbScalarString(boneKey, pc.bone),
      bnbScalarInt(orderKey, pc.order),
      bnbScalarBool(skinRequiredKey, pc.skinRequired),
      bnbScalarUint(channelsKey, physicsChannelsToMask(pc.channels)),
    ]))
    properties.addFloatIfNeeded(toc, inertiaKey, pc.inertia, defaultFloat("physicsConstraint", "inertia"), required = pc.hasInertia)
    properties.addFloatIfNeeded(toc, strengthKey, pc.strength, defaultFloat("physicsConstraint", "strength"), required = pc.hasStrength)
    properties.addFloatIfNeeded(toc, dampingKey, pc.damping, defaultFloat("physicsConstraint", "damping"), required = pc.hasDamping)
    properties.addFloatIfNeeded(toc, massKey, pc.mass, defaultFloat("physicsConstraint", "mass"), required = pc.hasMass)
    properties.addFloatIfNeeded(toc, gravityKey, pc.gravity, defaultFloat("physicsConstraint", "gravity"), required = pc.hasGravity)
    properties.addFloatIfNeeded(toc, windKey, pc.wind, defaultFloat("physicsConstraint", "wind"), required = pc.hasWind)
    properties.addFloatIfNeeded(toc, physicsMixKey, pc.mix, defaultFloat("physicsConstraint", "physicsMix"), required = pc.hasMix)
    result.add BnbObjectRecord(typeKey: physicsConstraintTypeKey, properties: properties)

  proc orderedSkins(): seq[SkinData] =
    for skin in data.skins:
      if skin.name == "default":
        result.add skin
        break
    for skin in data.skins:
      if skin.name != "default":
        result.add skin

  proc sortedSkinEntries(skin: SkinData): seq[SkinEntryData] =
    result = skin.entries
    var slotOrder = initTable[string, int]()
    for index, slot in data.slots:
      slotOrder[slot.name] = index
    result.sort(proc(a, b: SkinEntryData): int =
      result = cmp(slotOrder.getOrDefault(a.slot, high(int)), slotOrder.getOrDefault(b.slot, high(int)))
      if result == 0:
        result = cmp(a.attachment, b.attachment)
    )

  proc indexByNames(names: openArray[string]): Table[string, int] =
    for index, name in names:
      result[name] = index

  let boneNameIndex = data.bones.mapIt(it.name).indexByNames()
  let ikNameIndex = data.ikConstraints.mapIt(it.name).indexByNames()
  let transformNameIndex = data.transformConstraints.mapIt(it.name).indexByNames()
  let pathNameIndex = data.paths.mapIt(it.name).indexByNames()
  let physicsNameIndex = data.physicsConstraints.mapIt(it.name).indexByNames()

  proc orderedRefs(refs: openArray[string]; indexByName: Table[string, int]): seq[string] =
    result = @refs
    result.sort(proc(a, b: string): int =
      cmp(indexByName.getOrDefault(a, high(int)), indexByName.getOrDefault(b, high(int)))
    )

  for skin in orderedSkins():
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodeSkinBnbScalars([
      bnbScalarString(nameKey, skin.name),
    ]))
    let skinBones = orderedRefs(skin.bones, boneNameIndex)
    if skinBones.len > 0:
      properties.addProperty(toc, skinBonesKey, writeIndexListPayload(skinBones, boneNameIndex, "skin.bones"))
    let skinIk = orderedRefs(skin.ikConstraints, ikNameIndex)
    if skinIk.len > 0:
      properties.addProperty(toc, skinIkConstraintsKey, writeIndexListPayload(skinIk, ikNameIndex, "skin.ikConstraints"))
    let skinTransform = orderedRefs(skin.transformConstraints, transformNameIndex)
    if skinTransform.len > 0:
      properties.addProperty(toc, skinTransformConstraintsKey, writeIndexListPayload(skinTransform, transformNameIndex, "skin.transformConstraints"))
    let skinPaths = orderedRefs(skin.pathConstraints, pathNameIndex)
    if skinPaths.len > 0:
      properties.addProperty(toc, skinPathConstraintsKey, writeIndexListPayload(skinPaths, pathNameIndex, "skin.pathConstraints"))
    let skinPhysics = orderedRefs(skin.physicsConstraints, physicsNameIndex)
    if skinPhysics.len > 0:
      properties.addProperty(toc, skinPhysicsConstraintsKey, writeIndexListPayload(skinPhysics, physicsNameIndex, "skin.physicsConstraints"))
    result.add BnbObjectRecord(typeKey: skinTypeKey, properties: properties)
    for entry in sortedSkinEntries(skin):
      var entryProperties: seq[BnbPropertyRecord]
      entryProperties.addBnbScalarProperties(toc, table, encodeSkinEntryBnbScalars([
        bnbScalarString(slotKey, entry.slot),
        bnbScalarString(skinAttachmentKey, entry.attachment),
        bnbScalarString(skinTargetKey, entry.target),
      ]))
      result.add BnbObjectRecord(typeKey: skinEntryTypeKey, properties: entryProperties)

  for param in data.parameters:
    var properties: seq[BnbPropertyRecord]
    properties.addBnbScalarProperties(toc, table, encodeParameterBnbScalars([
      bnbScalarString(nameKey, param.name),
      bnbScalarFloat(parameterMinKey, param.minValue),
      bnbScalarFloat(parameterMaxKey, param.maxValue),
      bnbScalarFloat(parameterDefaultKey, param.defaultValue),
    ]))
    result.add BnbObjectRecord(typeKey: parameterTypeKey, properties: properties)

  for rec in data.deformers:
    let def = rec.deformer
    var defProperties: seq[BnbPropertyRecord]
    let defKind =
      case def.kind
      of warpDeformerKind: "warp"
      of rotationDeformerKind: "rotation"
    defProperties.addBnbScalarProperties(toc, table, encodeDeformerBnbScalars([
      bnbScalarString(deformerIdKey, def.id),
      bnbScalarString(parentKey, def.parent),
      bnbScalarUint(deformerOrderKey, uint64(def.order)),
      bnbScalarString(deformerKindKey, defKind),
    ]))
    result.add BnbObjectRecord(typeKey: deformerTypeKey, properties: defProperties)

    case def.kind
    of warpDeformerKind:
      let warp = def.warp
      var wProperties: seq[BnbPropertyRecord]
      wProperties.addBnbScalarProperties(toc, table, encodeWarpLatticeBnbScalars([
        bnbScalarUint(warpRowsKey, uint64(warp.rows)),
        bnbScalarUint(warpColsKey, uint64(warp.cols)),
        bnbScalarFloat(warpMinXKey, warp.minX),
        bnbScalarFloat(warpMinYKey, warp.minY),
        bnbScalarFloat(warpMaxXKey, warp.maxX),
        bnbScalarFloat(warpMaxYKey, warp.maxY),
      ]))
      wProperties.addProperty(toc, warpControlPointsKey, writeControlPointsPayload(warp.controlPoints))
      result.add BnbObjectRecord(typeKey: warpLatticeTypeKey, properties: wProperties)
    of rotationDeformerKind:
      let rot = def.rotation
      var rProperties: seq[BnbPropertyRecord]
      rProperties.addBnbScalarProperties(toc, table, encodeRotationDeformerBnbScalars([
        bnbScalarFloat(rotationPivotXKey, rot.pivotX),
        bnbScalarFloat(rotationPivotYKey, rot.pivotY),
        bnbScalarFloat(rotationAngleDegreesKey, rot.angleDegrees),
        bnbScalarFloat(rotationScaleXKey, rot.scaleX),
        bnbScalarFloat(rotationScaleYKey, rot.scaleY),
        bnbScalarFloat(rotationOpacityKey, rot.opacity),
      ]))
      result.add BnbObjectRecord(typeKey: rotationDeformerTypeKey, properties: rProperties)

    let blend = rec.keyformBlend
    if blend.axes.len > 0 and blend.keyforms.len > 0:
      var bProperties: seq[BnbPropertyRecord]
      bProperties.addBnbScalarProperties(toc, table, encodeKeyformBlendBnbScalars([
        bnbScalarUint(blendValueCountKey, uint64(blend.valueCount)),
      ]))
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
    clipProperties.addBnbScalarProperties(toc, table, encodeAnimationClipBnbScalars([
      bnbScalarString(nameKey, clip.name),
    ]))
    result.add BnbObjectRecord(typeKey: animationClipTypeKey, properties: clipProperties)
    for timeline in clip.boneTimelines:
      if timeline.target notin boneIndexes:
        raise newBonyLoadError(unknownRequiredReference, ".bnb bone timeline references unknown bone: " & timeline.target)
      var properties: seq[BnbPropertyRecord]
      properties.addBnbScalarProperties(toc, table, encodeBoneTimelineBnbScalars([
        bnbScalarUint(boneIndexKey, uint64(boneIndexes[timeline.target])),
        bnbScalarUint(boneTimelineKindKey, timeline.kind.boneTimelineKindTag),
      ]))
      properties.addProperty(toc, timelineKeysKey, timeline.writeTimelineKeys())
      result.add BnbObjectRecord(typeKey: boneTimelineTypeKey, properties: properties)
    for timeline in clip.slotTimelines:
      if timeline.target notin slotIndexes:
        raise newBonyLoadError(unknownRequiredReference, ".bnb slot timeline references unknown slot: " & timeline.target)
      var properties: seq[BnbPropertyRecord]
      properties.addBnbScalarProperties(toc, table, encodeSlotTimelineBnbScalars([
        bnbScalarUint(slotIndexKey, uint64(slotIndexes[timeline.target])),
        bnbScalarUint(slotTimelineKindKey, timeline.kind.slotTimelineKindTag),
      ]))
      properties.addProperty(toc, timelineKeysKey, timeline.writeTimelineKeys(regionIndexes))
      result.add BnbObjectRecord(typeKey: slotTimelineTypeKey, properties: properties)
    for timeline in clip.deformTimelines:
      if timeline.slot notin slotIndexes:
        raise newBonyLoadError(unknownRequiredReference, ".bnb deform timeline references unknown slot: " & timeline.slot)
      var properties: seq[BnbPropertyRecord]
      properties.addBnbScalarProperties(toc, table, encodeDeformTimelineBnbScalars([
        bnbScalarString(deformSkinKey, timeline.skin),
        bnbScalarString(slotKey, timeline.slot),
        bnbScalarString(deformAttachmentKey, timeline.attachment),
        bnbScalarUint(deformVertexCountKey, uint64(timeline.vertexCount)),
      ]))
      properties.addProperty(toc, deformKeysKey, writeDeformKeys(timeline))
      result.add BnbObjectRecord(typeKey: deformTimelineTypeKey, properties: properties)
    for timeline in clip.eventTimelines:
      var properties: seq[BnbPropertyRecord]
      properties.addProperty(toc, eventKeysKey, writeEventKeys(timeline, table))
      result.add BnbObjectRecord(typeKey: eventTimelineTypeKey, properties: properties)

  for machine in asset.stateMachines:
    var machineProperties: seq[BnbPropertyRecord]
    machineProperties.addBnbScalarProperties(toc, table, encodeStateMachineBnbScalars([
      bnbScalarString(nameKey, machine.name),
    ]))
    result.add BnbObjectRecord(typeKey: stateMachineTypeKey, properties: machineProperties)
    let inputIndexes = machine.inputs.indexByInputName()
    let layerIndexes = machine.layers.indexByLayerName()
    for input in machine.inputs:
      var properties: seq[BnbPropertyRecord]
      var inputScalars = @[
        bnbScalarString(nameKey, input.name),
        bnbScalarUint(stateMachineInputKindKey, input.kind.inputKindTag),
      ]
      case input.kind
      of boolInput:
        inputScalars.add bnbScalarBool(inputDefaultBoolKey, input.defaultBool)
      of numberInput:
        inputScalars.add bnbScalarFloat(inputDefaultNumberKey, input.defaultNumber)
      of triggerInput:
        discard
      properties.addBnbScalarProperties(toc, table, encodeStateMachineInputBnbScalars(inputScalars))
      result.add BnbObjectRecord(typeKey: stateMachineInputTypeKey, properties: properties)

    for layer in machine.layers:
      let stateIndexes = layer.states.indexByStateName()
      var layerProperties: seq[BnbPropertyRecord]
      layerProperties.addBnbScalarProperties(toc, table, encodeStateMachineLayerBnbScalars([
        bnbScalarString(nameKey, layer.name),
        bnbScalarUint(initialStateIndexKey, uint64(stateIndexes.requiredIndex(layer.initialState, "stateMachineLayer.initialState"))),
      ]))
      result.add BnbObjectRecord(typeKey: stateMachineLayerTypeKey, properties: layerProperties)

      for state in layer.states:
        var stateProperties: seq[BnbPropertyRecord]
        var stateScalars = encodeStateMachineStateBnbScalars([
          bnbScalarString(nameKey, state.name),
          bnbScalarUint(stateMachineStateKindKey, state.kind.stateKindTag),
          bnbScalarBool(stateLoopKey, state.loop),
        ])
        stateProperties.addBnbScalarPropertyIfPresent(toc, table, stateScalars, nameKey)
        stateProperties.addBnbScalarPropertyIfPresent(toc, table, stateScalars, stateMachineStateKindKey)
        case state.kind
        of clipState:
          stateProperties.addBnbScalarProperty(toc, table,
            bnbScalarUint(stateClipIndexKey, uint64(animationIndexes.requiredIndex(state.clip.name, "stateMachineState.clip"))))
          stateProperties.addBnbScalarPropertyIfPresent(toc, table, stateScalars, stateLoopKey)
        of blend1DState:
          stateProperties.addBnbScalarProperty(toc, table,
            bnbScalarUint(stateBlendInputIndexKey, uint64(inputIndexes.requiredIndex(state.blendInput, "stateMachineState.blendInput"))))
        result.add BnbObjectRecord(typeKey: stateMachineStateTypeKey, properties: stateProperties)
        if state.kind == blend1DState:
          for blendClip in state.blendClips:
            var properties: seq[BnbPropertyRecord]
            properties.addBnbScalarProperties(toc, table, encodeStateMachineBlendClipBnbScalars([
              bnbScalarUint(blendClipAnimationIndexKey, uint64(animationIndexes.requiredIndex(blendClip.clip.name, "stateMachineBlendClip.animation"))),
              bnbScalarFloat(blendClipValueKey, blendClip.value),
              bnbScalarBool(blendClipLoopKey, blendClip.loop),
            ]))
            result.add BnbObjectRecord(typeKey: stateMachineBlendClipTypeKey, properties: properties)

      for transition in layer.transitions:
        var transitionProperties: seq[BnbPropertyRecord]
        transitionProperties.addBnbScalarProperties(toc, table, encodeStateMachineTransitionBnbScalars([
          bnbScalarUint(transitionFromStateIndexKey, uint64(stateIndexes.requiredIndex(transition.fromState, "stateMachineTransition.from"))),
          bnbScalarUint(transitionToStateIndexKey, uint64(stateIndexes.requiredIndex(transition.toState, "stateMachineTransition.to"))),
        ]))
        result.add BnbObjectRecord(typeKey: stateMachineTransitionTypeKey, properties: transitionProperties)
        for condition in transition.conditions:
          var properties: seq[BnbPropertyRecord]
          var conditionScalars = encodeStateMachineConditionBnbScalars([
            bnbScalarUint(conditionInputIndexKey, uint64(inputIndexes.requiredIndex(condition.input, "stateMachineCondition.input"))),
            bnbScalarUint(stateMachineConditionKindKey, condition.kind.conditionKindTag),
            bnbScalarBool(conditionBoolValueKey, condition.boolValue),
          ])
          properties.addBnbScalarPropertyIfPresent(toc, table, conditionScalars, conditionInputIndexKey)
          properties.addBnbScalarPropertyIfPresent(toc, table, conditionScalars, stateMachineConditionKindKey)
          case condition.kind
          of boolEqualsCondition:
            properties.addBnbScalarPropertyIfPresent(toc, table, conditionScalars, conditionBoolValueKey)
          of numberEqualsCondition, numberGreaterCondition, numberGreaterOrEqualCondition, numberLessCondition, numberLessOrEqualCondition:
            properties.addBnbScalarProperty(toc, table, bnbScalarFloat(conditionNumberValueKey, condition.numberValue))
          of triggerSetCondition:
            discard
          result.add BnbObjectRecord(typeKey: stateMachineConditionTypeKey, properties: properties)

    for listener in machine.listeners:
      var properties: seq[BnbPropertyRecord]
      let listenerScalars = encodeStateMachineListenerBnbScalars([
        bnbScalarString(nameKey, listener.name),
        bnbScalarUint(stateMachineListenerKindKey, listener.kind.listenerKindTag),
      ])
      properties.addBnbScalarProperties(toc, table, listenerScalars)
      case listener.kind
      of stateEnterListener:
        let listenerLayerIndex = layerIndexes.requiredIndex(listener.layer, "stateMachineListener.layer")
        properties.addBnbScalarProperty(toc, table, bnbScalarUint(listenerLayerIndexKey, uint64(listenerLayerIndex)))
        let stateIndexes = machine.layers[listenerLayerIndex].states.indexByStateName()
        properties.addBnbScalarProperty(toc, table,
          bnbScalarUint(listenerToStateIndexKey, uint64(stateIndexes.requiredIndex(listener.toState, "stateMachineListener.to"))))
      of stateExitListener:
        let listenerLayerIndex = layerIndexes.requiredIndex(listener.layer, "stateMachineListener.layer")
        properties.addBnbScalarProperty(toc, table, bnbScalarUint(listenerLayerIndexKey, uint64(listenerLayerIndex)))
        let stateIndexes = machine.layers[listenerLayerIndex].states.indexByStateName()
        properties.addBnbScalarProperty(toc, table,
          bnbScalarUint(listenerFromStateIndexKey, uint64(stateIndexes.requiredIndex(listener.fromState, "stateMachineListener.from"))))
      of transitionListener:
        let listenerLayerIndex = layerIndexes.requiredIndex(listener.layer, "stateMachineListener.layer")
        properties.addBnbScalarProperty(toc, table, bnbScalarUint(listenerLayerIndexKey, uint64(listenerLayerIndex)))
        let stateIndexes = machine.layers[listenerLayerIndex].states.indexByStateName()
        properties.addBnbScalarProperty(toc, table,
          bnbScalarUint(listenerFromStateIndexKey, uint64(stateIndexes.requiredIndex(listener.fromState, "stateMachineListener.from"))))
        properties.addBnbScalarProperty(toc, table,
          bnbScalarUint(listenerToStateIndexKey, uint64(stateIndexes.requiredIndex(listener.toState, "stateMachineListener.to"))))
      of pointerDownListener, pointerUpListener, pointerEnterListener, pointerExitListener, pointerMoveListener:
        properties.addBnbScalarProperty(toc, table,
          bnbScalarUint(listenerSlotIndexKey, uint64(slotIndexes.requiredIndex(listener.slot, "stateMachineListener.slot"))))
        properties.addBnbScalarProperty(toc, table,
          bnbScalarUint(listenerHelperKindKey, listener.targetKind.helperKindTag))
        properties.addBnbScalarProperty(toc, table,
          bnbScalarString(listenerHelperTargetKey, listener.target))
        properties.addBnbScalarProperty(toc, table,
          bnbScalarUint(listenerInputIndexKey, uint64(inputIndexes.requiredIndex(listener.input, "stateMachineListener.input"))))
        if listener.hasBoolValue:
          properties.addBnbScalarProperty(toc, table, bnbScalarBool(listenerBoolValueKey, listener.boolValue))
        if listener.hasNumberValue:
          properties.addBnbScalarProperty(toc, table, bnbScalarFloat(listenerNumberValueKey, listener.numberValue))
        if listener.hasHitRadius:
          properties.addBnbScalarProperty(toc, table, bnbScalarFloat(listenerHitRadiusKey, listener.hitRadius))
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
  var pointAttachments: seq[PointAttachmentData]
  var boundingBoxAttachments: seq[BoundingBoxAttachmentData]
  var nestedRigAttachments: seq[NestedRigAttachmentData]
  var pathAttachments: seq[PathAttachmentData]
  var clips: seq[ClipAttachmentData]
  var meshes: seq[MeshAttachment]
  var paths: seq[PathConstraintData]
  var ikConstraints: seq[IkConstraintData]
  var transformConstraints: seq[TransformConstraintData]
  var physicsConstraints: seq[PhysicsConstraintData]
  var skins: seq[SkinData]
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
  var currentSkinName = ""
  var currentSkinEntries: seq[SkinEntryData] = @[]
  var currentSkinBones: seq[string] = @[]
  var currentSkinIkConstraints: seq[string] = @[]
  var currentSkinTransformConstraints: seq[string] = @[]
  var currentSkinPathConstraints: seq[string] = @[]
  var currentSkinPhysicsConstraints: seq[string] = @[]

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

  template flushSkinIfAny() =
    if currentSkinName.len > 0:
      skins.add skinData(
        currentSkinName,
        currentSkinEntries,
        bones = currentSkinBones,
        ikConstraints = currentSkinIkConstraints,
        transformConstraints = currentSkinTransformConstraints,
        pathConstraints = currentSkinPathConstraints,
        physicsConstraints = currentSkinPhysicsConstraints,
      )
      currentSkinName = ""
      currentSkinEntries = @[]
      currentSkinBones = @[]
      currentSkinIkConstraints = @[]
      currentSkinTransformConstraints = @[]
      currentSkinPathConstraints = @[]
      currentSkinPhysicsConstraints = @[]

  proc boneNames(): seq[string] =
    for bone in bones:
      result.add bone.name

  proc ikNames(): seq[string] =
    for ik in ikConstraints:
      result.add ik.name

  proc transformNames(): seq[string] =
    for tc in transformConstraints:
      result.add tc.name

  proc pathNames(): seq[string] =
    for path in paths:
      result.add path.name

  proc physicsNames(): seq[string] =
    for pc in physicsConstraints:
      result.add pc.name

  for record in objects:
    case record.typeKey
    of skeletonTypeKey:
      if hasSkeleton:
        raise newBonyLoadError(duplicateKey, ".bnb contains multiple skeleton objects")
      let properties = record.propertyMap([nameKey, versionKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSkeletonBnbScalars, properties, bonySkeletonScalarSpecs, strings, "skeleton")
      headerValue = skeletonHeader(
        scalars.bnbScalarString(nameKey, "skeleton.name"),
        scalars.bnbScalarString(versionKey, "skeleton.version"),
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
        skinRequiredKey,
      ])
      let scalars = decodeBnbScalarsFromProperties(
        decodeBoneBnbScalars, properties, bonyBoneScalarSpecs, strings, "bone")
      let inheritRotation = scalars.bnbScalarBool(inheritRotationKey, "bone.inheritRotation")
      let inheritScale = scalars.bnbScalarBool(inheritScaleKey, "bone.inheritScale")
      let inheritReflection = scalars.bnbScalarBool(inheritReflectionKey, "bone.inheritReflection")
      bones.add boneData(
        scalars.bnbScalarString(nameKey, "bone.name"),
        scalars.bnbScalarString(parentKey, "bone.parent"),
        localTransform(
          x = scalars.bnbScalarFloat(xKey, "bone.x"),
          y = scalars.bnbScalarFloat(yKey, "bone.y"),
          rotation = scalars.bnbScalarFloat(rotationKey, "bone.rotation"),
          scaleX = scalars.bnbScalarFloat(scaleXKey, "bone.scaleX"),
          scaleY = scalars.bnbScalarFloat(scaleYKey, "bone.scaleY"),
          shearX = scalars.bnbScalarFloat(shearXKey, "bone.shearX"),
          shearY = scalars.bnbScalarFloat(shearYKey, "bone.shearY"),
          inheritRotation = inheritRotation,
          inheritScale = inheritScale,
          inheritReflection = inheritReflection,
          transformMode = parseTransformMode(scalars.bnbScalarString(transformModeKey, "bone.transformMode")),
        ),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "bone.skinRequired"),
      )
    of slotTypeKey:
      let properties = record.propertyMap([nameKey, boneKey, attachmentKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSlotBnbScalars, properties, bonySlotScalarSpecs, strings, "slot")
      slots.add slotData(
        scalars.bnbScalarString(nameKey, "slot.name"),
        scalars.bnbScalarString(boneKey, "slot.bone"),
        scalars.bnbScalarString(attachmentKey, "slot.attachment"),
      )
    of regionTypeKey:
      let properties = record.propertyMap([nameKey, widthKey, heightKey, texturePageKey, u0Key, v0Key, u1Key, v1Key, alphaModeKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeRegionBnbScalars, properties, bonyRegionScalarSpecs, strings, "region")
      regions.add regionAttachment(
        scalars.bnbScalarString(nameKey, "region.name"),
        scalars.bnbScalarFloat(widthKey, "region.width"),
        scalars.bnbScalarFloat(heightKey, "region.height"),
        texturePage = scalars.bnbScalarString(texturePageKey, "region.texturePage"),
        u0 = scalars.bnbScalarFloat(u0Key, "region.u0"),
        v0 = scalars.bnbScalarFloat(v0Key, "region.v0"),
        u1 = scalars.bnbScalarFloat(u1Key, "region.u1"),
        v1 = scalars.bnbScalarFloat(v1Key, "region.v1"),
        alphaMode = scalars.bnbScalarString(alphaModeKey, "region.alphaMode"),
      )
    of pointAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, xKey, yKey, rotationKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodePointAttachmentBnbScalars, properties, bonyPointAttachmentScalarSpecs, strings, "pointAttachment")
      pointAttachments.add pointAttachmentData(
        scalars.bnbScalarString(nameKey, "pointAttachment.name"),
        scalars.bnbScalarFloat(xKey, "pointAttachment.x"),
        scalars.bnbScalarFloat(yKey, "pointAttachment.y"),
        scalars.bnbScalarFloat(rotationKey, "pointAttachment.rotation"),
      )
    of boundingBoxAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, verticesKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeBoundingBoxAttachmentBnbScalars, properties, bonyBoundingBoxAttachmentScalarSpecs, strings, "boundingBoxAttachment")
      if verticesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb boundingBoxAttachment.vertices is required")
      boundingBoxAttachments.add boundingBoxAttachmentData(
        scalars.bnbScalarString(nameKey, "boundingBoxAttachment.name"),
        readPolygonVerticesPayload(properties[verticesKey], "boundingBoxAttachment"),
      )
    of pathAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, p0xKey, p0yKey, p1xKey, p1yKey, p2xKey, p2yKey, p3xKey, p3yKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodePathAttachmentBnbScalars, properties, bonyPathAttachmentScalarSpecs, strings, "pathAttachment")
      pathAttachments.add pathAttachmentData(
        scalars.bnbScalarString(nameKey, "pathAttachment.name"),
        scalars.bnbScalarFloat(p0xKey, "pathAttachment.p0x"),
        scalars.bnbScalarFloat(p0yKey, "pathAttachment.p0y"),
        scalars.bnbScalarFloat(p1xKey, "pathAttachment.p1x"),
        scalars.bnbScalarFloat(p1yKey, "pathAttachment.p1y"),
        scalars.bnbScalarFloat(p2xKey, "pathAttachment.p2x"),
        scalars.bnbScalarFloat(p2yKey, "pathAttachment.p2y"),
        scalars.bnbScalarFloat(p3xKey, "pathAttachment.p3x"),
        scalars.bnbScalarFloat(p3yKey, "pathAttachment.p3y"),
      )
    of clippingAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, verticesKey, untilSlotKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeClippingAttachmentBnbScalars, properties, bonyClippingAttachmentScalarSpecs, strings, "clippingAttachment")
      if verticesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb clippingAttachment.vertices is required")
      clips.add clipAttachmentData(
        scalars.bnbScalarString(nameKey, "clippingAttachment.name"),
        readPolygonVerticesPayload(properties[verticesKey], "clippingAttachment"),
        scalars.bnbScalarString(untilSlotKey, "clippingAttachment.untilSlot"),
      )
    of meshAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, meshWeightedKey, meshVerticesKey, meshUvsKey, meshTrianglesKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeMeshAttachmentBnbScalars, properties, bonyMeshAttachmentScalarSpecs, strings, "meshAttachment")
      if meshVerticesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb meshAttachment.meshVertices is required")
      if meshUvsKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb meshAttachment.meshUvs is required")
      if meshTrianglesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb meshAttachment.meshTriangles is required")
      # meshWeighted selects the vertices payload branch; it defaults to false and
      # is only present when non-default. The (a)-(g) whole-skeleton checks run
      # later in validateSkeletonData via skeletonData().
      let weighted = scalars.bnbScalarBool(meshWeightedKey, "meshAttachment.meshWeighted")
      meshes.add meshAttachmentData(
        scalars.bnbScalarString(nameKey, "meshAttachment.name"),
        readMeshUvsPayload(properties[meshUvsKey]),
        readMeshTrianglesPayload(properties[meshTrianglesKey]),
        readMeshVerticesPayload(properties[meshVerticesKey], weighted, strings),
        weighted,
      )
    of nestedRigAttachmentTypeKey:
      let properties = record.propertyMap([nameKey, nestedSkeletonKey, nestedSkinKey, nestedAnimationKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeNestedRigAttachmentBnbScalars, properties, bonyNestedRigAttachmentScalarSpecs, strings, "nestedRigAttachment")
      nestedRigAttachments.add nestedRigAttachmentData(
        scalars.bnbScalarString(nameKey, "nestedRigAttachment.name"),
        scalars.bnbScalarString(nestedSkeletonKey, "nestedRigAttachment.nestedSkeleton"),
        scalars.bnbScalarString(nestedSkinKey, "nestedRigAttachment.nestedSkin"),
        scalars.bnbScalarString(nestedAnimationKey, "nestedRigAttachment.nestedAnimation"),
      )
    of pathTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, targetKey, pathKey, orderKey, skinRequiredKey, positionKey, translateMixKey, rotateMixKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodePathBnbScalars, properties, bonyPathScalarSpecs, strings, "path")
      paths.add pathConstraintData(
        scalars.bnbScalarString(nameKey, "path.name"),
        scalars.bnbScalarString(boneKey, "path.bone"),
        scalars.bnbScalarString(targetKey, "path.target"),
        scalars.bnbScalarString(pathKey, "path.path"),
        scalars.bnbScalarInt(orderKey, "path.order"),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "path.skinRequired"),
        hasPosition = positionKey in properties,
        position =
          if positionKey in properties: scalars.bnbScalarFloat(positionKey, "path.position")
          else: defaultFloat("path", "position"),
        hasTranslateMix = translateMixKey in properties,
        translateMix =
          if translateMixKey in properties: scalars.bnbScalarFloat(translateMixKey, "path.translateMix")
          else: defaultFloat("path", "translateMix"),
        hasRotateMix = rotateMixKey in properties,
        rotateMix =
          if rotateMixKey in properties: scalars.bnbScalarFloat(rotateMixKey, "path.rotateMix")
          else: defaultFloat("path", "rotateMix"),
      )
    of ikConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, bonesKey, targetKey, orderKey, skinRequiredKey, mixKey, bendPositiveKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeIkConstraintBnbScalars, properties, bonyIkConstraintScalarSpecs, strings, "ikConstraint")
      if bonesKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb ikConstraint.bones is required")
      ikConstraints.add ikConstraintData(
        scalars.bnbScalarString(nameKey, "ikConstraint.name"),
        scalars.bnbScalarString(targetKey, "ikConstraint.target"),
        readBonesPayload(properties[bonesKey], strings),
        order = scalars.bnbScalarInt(orderKey, "ikConstraint.order"),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "ikConstraint.skinRequired"),
        hasMix = mixKey in properties,
        mix =
          if mixKey in properties: scalars.bnbScalarFloat(mixKey, "ikConstraint.mix")
          else: defaultFloat("ikConstraint", "mix"),
        hasBendPositive = bendPositiveKey in properties,
        bendPositive =
          if bendPositiveKey in properties: scalars.bnbScalarBool(bendPositiveKey, "ikConstraint.bendPositive")
          else: defaultBool("ikConstraint", "bendPositive"),
      )
    of transformConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, targetKey, orderKey, skinRequiredKey, translateMixKey, rotateMixKey, scaleMixKey, shearMixKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeTransformConstraintBnbScalars, properties, bonyTransformConstraintScalarSpecs, strings, "transformConstraint")
      transformConstraints.add transformConstraintData(
        scalars.bnbScalarString(nameKey, "transformConstraint.name"),
        scalars.bnbScalarString(boneKey, "transformConstraint.bone"),
        scalars.bnbScalarString(targetKey, "transformConstraint.target"),
        order = scalars.bnbScalarInt(orderKey, "transformConstraint.order"),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "transformConstraint.skinRequired"),
        hasTranslateMix = translateMixKey in properties,
        translateMix =
          if translateMixKey in properties: scalars.bnbScalarFloat(translateMixKey, "transformConstraint.translateMix")
          else: defaultFloat("transformConstraint", "translateMix"),
        hasRotateMix = rotateMixKey in properties,
        rotateMix =
          if rotateMixKey in properties: scalars.bnbScalarFloat(rotateMixKey, "transformConstraint.rotateMix")
          else: defaultFloat("transformConstraint", "rotateMix"),
        hasScaleMix = scaleMixKey in properties,
        scaleMix =
          if scaleMixKey in properties: scalars.bnbScalarFloat(scaleMixKey, "transformConstraint.scaleMix")
          else: defaultFloat("transformConstraint", "scaleMix"),
        hasShearMix = shearMixKey in properties,
        shearMix =
          if shearMixKey in properties: scalars.bnbScalarFloat(shearMixKey, "transformConstraint.shearMix")
          else: defaultFloat("transformConstraint", "shearMix"),
      )
    of physicsConstraintTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, boneKey, orderKey, skinRequiredKey, channelsKey, inertiaKey, strengthKey, dampingKey, massKey, gravityKey, windKey, physicsMixKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodePhysicsConstraintBnbScalars, properties, bonyPhysicsConstraintScalarSpecs, strings, "physicsConstraint")
      let channelMask = scalars.bnbScalarUint(channelsKey, "physicsConstraint.channels")
      physicsConstraints.add physicsConstraintData(
        scalars.bnbScalarString(nameKey, "physicsConstraint.name"),
        scalars.bnbScalarString(boneKey, "physicsConstraint.bone"),
        physicsChannelsFromMask(channelMask, "physicsConstraint.channels"),
        order = scalars.bnbScalarInt(orderKey, "physicsConstraint.order"),
        skinRequired = scalars.bnbScalarBool(skinRequiredKey, "physicsConstraint.skinRequired"),
        hasInertia = inertiaKey in properties,
        inertia =
          if inertiaKey in properties: scalars.bnbScalarFloat(inertiaKey, "physicsConstraint.inertia")
          else: defaultFloat("physicsConstraint", "inertia"),
        hasStrength = strengthKey in properties,
        strength =
          if strengthKey in properties: scalars.bnbScalarFloat(strengthKey, "physicsConstraint.strength")
          else: defaultFloat("physicsConstraint", "strength"),
        hasDamping = dampingKey in properties,
        damping =
          if dampingKey in properties: scalars.bnbScalarFloat(dampingKey, "physicsConstraint.damping")
          else: defaultFloat("physicsConstraint", "damping"),
        hasMass = massKey in properties,
        mass =
          if massKey in properties: scalars.bnbScalarFloat(massKey, "physicsConstraint.mass")
          else: defaultFloat("physicsConstraint", "mass"),
        hasGravity = gravityKey in properties,
        gravity =
          if gravityKey in properties: scalars.bnbScalarFloat(gravityKey, "physicsConstraint.gravity")
          else: defaultFloat("physicsConstraint", "gravity"),
        hasWind = windKey in properties,
        wind =
          if windKey in properties: scalars.bnbScalarFloat(windKey, "physicsConstraint.wind")
          else: defaultFloat("physicsConstraint", "wind"),
        hasMix = physicsMixKey in properties,
        mix =
          if physicsMixKey in properties: scalars.bnbScalarFloat(physicsMixKey, "physicsConstraint.physicsMix")
          else: defaultFloat("physicsConstraint", "physicsMix"),
      )
    of parameterTypeKey:
      flushSkinIfAny()
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, parameterMinKey, parameterMaxKey, parameterDefaultKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeParameterBnbScalars, properties, bonyParameterScalarSpecs, strings, "parameter")
      loadedParameters.add ParameterAxis(
        name: scalars.bnbScalarString(nameKey, "parameter.name"),
        minValue: scalars.bnbScalarFloat(parameterMinKey, "parameter.min"),
        maxValue: scalars.bnbScalarFloat(parameterMaxKey, "parameter.max"),
        defaultValue: scalars.bnbScalarFloat(parameterDefaultKey, "parameter.default"),
      )
    of skinTypeKey:
      flushPendingIfAny()
      flushSkinIfAny()
      let properties = record.propertyMap([
        nameKey,
        skinBonesKey,
        skinIkConstraintsKey,
        skinTransformConstraintsKey,
        skinPathConstraintsKey,
        skinPhysicsConstraintsKey,
      ])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSkinBnbScalars, properties, bonySkinScalarSpecs, strings, "skin")
      currentSkinName = scalars.bnbScalarString(nameKey, "skin.name")
      currentSkinEntries = @[]
      currentSkinBones =
        if skinBonesKey in properties: readIndexListPayload(properties[skinBonesKey], boneNames(), "skin.bones")
        else: @[]
      currentSkinIkConstraints =
        if skinIkConstraintsKey in properties: readIndexListPayload(properties[skinIkConstraintsKey], ikNames(), "skin.ikConstraints")
        else: @[]
      currentSkinTransformConstraints =
        if skinTransformConstraintsKey in properties: readIndexListPayload(properties[skinTransformConstraintsKey], transformNames(), "skin.transformConstraints")
        else: @[]
      currentSkinPathConstraints =
        if skinPathConstraintsKey in properties: readIndexListPayload(properties[skinPathConstraintsKey], pathNames(), "skin.pathConstraints")
        else: @[]
      currentSkinPhysicsConstraints =
        if skinPhysicsConstraintsKey in properties: readIndexListPayload(properties[skinPhysicsConstraintsKey], physicsNames(), "skin.physicsConstraints")
        else: @[]
    of skinEntryTypeKey:
      flushPendingIfAny()
      if currentSkinName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb skinEntry record without preceding skin")
      let properties = record.propertyMap([slotKey, skinAttachmentKey, skinTargetKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeSkinEntryBnbScalars, properties, bonySkinEntryScalarSpecs, strings, "skinEntry")
      currentSkinEntries.add skinEntryData(
        scalars.bnbScalarString(slotKey, "skinEntry.slot"),
        scalars.bnbScalarString(skinAttachmentKey, "skinEntry.skinAttachment"),
        scalars.bnbScalarString(skinTargetKey, "skinEntry.skinTarget"),
      )
    of deformerTypeKey:
      flushSkinIfAny()
      flushPendingIfAny()
      let properties = record.propertyMap([deformerIdKey, parentKey, deformerOrderKey, deformerKindKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeDeformerBnbScalars, properties, bonyDeformerScalarSpecs, strings, "deformer")
      pendingId = scalars.bnbScalarString(deformerIdKey, "deformer.id")
      pendingParent = scalars.bnbScalarString(parentKey, "deformer.parent")
      pendingOrder = scalars.bnbScalarUint32(deformerOrderKey, "deformer.order")
      let kindStr = scalars.bnbScalarString(deformerKindKey, "deformer.kind")
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
      let scalars = decodeBnbScalarsFromProperties(
        decodeWarpLatticeBnbScalars, properties, bonyWarpLatticeScalarSpecs, strings, "warpLattice")
      let rows = scalars.bnbScalarUint32(warpRowsKey, "warpLattice.rows")
      let cols = scalars.bnbScalarUint32(warpColsKey, "warpLattice.cols")
      let minX = scalars.bnbScalarFloat(warpMinXKey, "warpLattice.minX")
      let minY = scalars.bnbScalarFloat(warpMinYKey, "warpLattice.minY")
      let maxX = scalars.bnbScalarFloat(warpMaxXKey, "warpLattice.maxX")
      let maxY = scalars.bnbScalarFloat(warpMaxYKey, "warpLattice.maxY")
      if warpControlPointsKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb warpLattice.controlPoints is required")
      let controlPoints = readControlPointsPayload(properties[warpControlPointsKey])
      pendingWarp = WarpLattice(rows: rows, cols: cols, minX: minX, minY: minY, maxX: maxX, maxY: maxY, controlPoints: controlPoints)
      geometryReady = true
    of rotationDeformerTypeKey:
      if not deformerPending or pendingKind != rotationDeformerKind:
        raise newBonyLoadError(schemaViolation, ".bnb rotationDeformer record without preceding rotation deformer")
      let properties = record.propertyMap([rotationPivotXKey, rotationPivotYKey, rotationAngleDegreesKey, rotationScaleXKey, rotationScaleYKey, rotationOpacityKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeRotationDeformerBnbScalars, properties, bonyRotationDeformerScalarSpecs, strings, "rotationDeformer")
      let pivotX = scalars.bnbScalarFloat(rotationPivotXKey, "rotationDeformer.pivotX")
      let pivotY = scalars.bnbScalarFloat(rotationPivotYKey, "rotationDeformer.pivotY")
      let angleDeg = scalars.bnbScalarFloat(rotationAngleDegreesKey, "rotationDeformer.angleDegrees")
      let scaleX = scalars.bnbScalarFloat(rotationScaleXKey, "rotationDeformer.scaleX")
      let scaleY = scalars.bnbScalarFloat(rotationScaleYKey, "rotationDeformer.scaleY")
      let opacity = scalars.bnbScalarFloat(rotationOpacityKey, "rotationDeformer.opacity")
      pendingRotation = RotationDeformer(pivotX: pivotX, pivotY: pivotY, angleDegrees: angleDeg, scaleX: scaleX, scaleY: scaleY, opacity: opacity)
      geometryReady = true
    of keyformBlendTypeKey:
      if not deformerPending or not geometryReady:
        raise newBonyLoadError(schemaViolation, ".bnb keyformBlend record without preceding deformer geometry")
      let properties = record.propertyMap([blendValueCountKey, blendAxesKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeKeyformBlendBnbScalars, properties, bonyKeyformBlendScalarSpecs, strings, "keyformBlend")
      let valueCount = scalars.bnbScalarUint32(blendValueCountKey, "keyformBlend.valueCount")
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
      flushSkinIfAny()
      flushPendingIfAny()
      discard

  flushSkinIfAny()
  flushPendingIfAny()

  if not hasSkeleton:
    raise newBonyLoadError(schemaViolation, ".bnb skeleton object is required")
  skeletonData(
    headerValue, bones, slots, regions, pathAttachments, paths, loadedParameters, loadedDeformers,
    ikConstraints, transformConstraints, physicsConstraints, clips, meshes, skins,
    pointAttachments, boundingBoxAttachments, nestedRigAttachments,
  )


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
  var currentEventTimelines: seq[EventTimeline]
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
        eventTimelines = currentEventTimelines,
        deformTimelines = currentDeformTimelines)
      currentName = ""
      currentBoneTimelines = @[]
      currentSlotTimelines = @[]
      currentEventTimelines = @[]
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
  skeleton: SkeletonData;
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
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineBnbScalars, properties, bonyStateMachineScalarSpecs, strings, "stateMachine")
      machineName = scalars.bnbScalarString(nameKey, "stateMachine.name")
    of stateMachineInputTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineInput record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([nameKey, stateMachineInputKindKey, inputDefaultBoolKey, inputDefaultNumberKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineInputBnbScalars, properties, bonyStateMachineInputScalarSpecs, strings, "stateMachineInput")
      let name = scalars.bnbScalarString(nameKey, "stateMachineInput.name")
      let kind = inputKindFromTag(scalars.bnbScalarUint32(stateMachineInputKindKey, "stateMachineInput.kind"))
      case kind
      of boolInput:
        if inputDefaultNumberKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb bool input must not contain number default")
        inputs.add stateMachineBoolInput(
          name,
          if inputDefaultBoolKey in properties: scalars.bnbScalarBool(inputDefaultBoolKey, "stateMachineInput.defaultBool")
          else: defaultBool("stateMachineInput", "inputDefaultBool"),
        )
      of numberInput:
        if inputDefaultBoolKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb number input must not contain bool default")
        inputs.add stateMachineNumberInput(
          name,
          if inputDefaultNumberKey in properties: scalars.bnbScalarFloat(inputDefaultNumberKey, "stateMachineInput.defaultNumber")
          else: defaultFloat("stateMachineInput", "inputDefaultNumber"),
        )
      of triggerInput:
        if inputDefaultBoolKey in properties or inputDefaultNumberKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb trigger input must not contain defaults")
        inputs.add stateMachineTriggerInput(name)
    of stateMachineLayerTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineLayer record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([nameKey, initialStateIndexKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineLayerBnbScalars, properties, bonyStateMachineLayerScalarSpecs, strings, "stateMachineLayer")
      layerName = scalars.bnbScalarString(nameKey, "stateMachineLayer.name")
      layerInitialIndex = scalars.bnbScalarUint32(initialStateIndexKey, "stateMachineLayer.initialStateIndex")
    of stateMachineStateTypeKey:
      if layerName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineState record without stateMachineLayer")
      flushTransition()
      let properties = record.propertyMap([nameKey, stateMachineStateKindKey, stateClipIndexKey, stateLoopKey, stateBlendInputIndexKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineStateBnbScalars, properties, bonyStateMachineStateScalarSpecs, strings, "stateMachineState")
      let name = scalars.bnbScalarString(nameKey, "stateMachineState.name")
      let kind = stateKindFromTag(scalars.bnbScalarUint32(stateMachineStateKindKey, "stateMachineState.kind"))
      case kind
      of clipState:
        if stateBlendInputIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb clip state must not contain blend input")
        let clip = animationByIndex(
          animations,
          scalars.bnbScalarUint32(stateClipIndexKey, "stateMachineState.clip"),
          "stateMachineState.clip",
        )
        layerStates.add stateMachineState(
          name,
          clip,
          if stateLoopKey in properties: scalars.bnbScalarBool(stateLoopKey, "stateMachineState.loop")
          else: defaultBool("stateMachineState", "stateLoop"),
        )
      of blend1DState:
        if stateClipIndexKey in properties or stateLoopKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb blend1d state must not contain direct clip fields")
        let input = inputByIndex(
          inputs,
          scalars.bnbScalarUint32(stateBlendInputIndexKey, "stateMachineState.blendInput"),
          "stateMachineState.blendInput",
        )
        layerStates.add StateMachineState(name: name, kind: blend1DState, blendInput: input.name)
    of stateMachineBlendClipTypeKey:
      if layerStates.len == 0 or layerStates[^1].kind != blend1DState:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineBlendClip record without blend1d state")
      let properties = record.propertyMap([blendClipAnimationIndexKey, blendClipValueKey, blendClipLoopKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineBlendClipBnbScalars, properties, bonyStateMachineBlendClipScalarSpecs, strings, "stateMachineBlendClip")
      let clip = animationByIndex(
        animations,
        scalars.bnbScalarUint32(blendClipAnimationIndexKey, "stateMachineBlendClip.animation"),
        "stateMachineBlendClip.animation",
      )
      let value = scalars.bnbScalarFloat(blendClipValueKey, "stateMachineBlendClip.value")
      let loop = scalars.bnbScalarBool(blendClipLoopKey, "stateMachineBlendClip.loop")
      layerStates[^1].blendClips.add stateMachineBlendClip(clip, value, loop)
    of stateMachineTransitionTypeKey:
      if layerName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineTransition record without stateMachineLayer")
      flushTransition()
      let properties = record.propertyMap([transitionFromStateIndexKey, transitionToStateIndexKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineTransitionBnbScalars, properties, bonyStateMachineTransitionScalarSpecs, strings, "stateMachineTransition")
      pendingTransitionFrom = stateNameByIndex(
        layerStates,
        scalars.bnbScalarUint32(transitionFromStateIndexKey, "stateMachineTransition.from"),
        "stateMachineTransition.from",
      )
      pendingTransitionTo = stateNameByIndex(
        layerStates,
        scalars.bnbScalarUint32(transitionToStateIndexKey, "stateMachineTransition.to"),
        "stateMachineTransition.to",
      )
    of stateMachineConditionTypeKey:
      if pendingTransitionFrom.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineCondition record without stateMachineTransition")
      let properties = record.propertyMap([conditionInputIndexKey, stateMachineConditionKindKey, conditionBoolValueKey, conditionNumberValueKey])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineConditionBnbScalars, properties, bonyStateMachineConditionScalarSpecs, strings, "stateMachineCondition")
      let input = inputByIndex(
        inputs,
        scalars.bnbScalarUint32(conditionInputIndexKey, "stateMachineCondition.input"),
        "stateMachineCondition.input",
      )
      let kind = conditionKindFromTag(scalars.bnbScalarUint32(stateMachineConditionKindKey, "stateMachineCondition.kind"))
      case kind
      of boolEqualsCondition:
        if conditionNumberValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb bool condition must not contain number value")
        pendingConditions.add stateMachineBoolCondition(
          input.name,
          if conditionBoolValueKey in properties: scalars.bnbScalarBool(conditionBoolValueKey, "stateMachineCondition.bool")
          else: defaultBool("stateMachineCondition", "conditionBoolValue"),
        )
      of numberEqualsCondition, numberGreaterCondition, numberGreaterOrEqualCondition, numberLessCondition, numberLessOrEqualCondition:
        if conditionBoolValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb number condition must not contain bool value")
        pendingConditions.add stateMachineNumberCondition(
          input.name,
          kind,
          scalars.bnbScalarFloat(conditionNumberValueKey, "stateMachineCondition.number"),
        )
      of triggerSetCondition:
        if conditionBoolValueKey in properties or conditionNumberValueKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb trigger condition must not contain values")
        pendingConditions.add stateMachineTriggerCondition(input.name)
    of stateMachineListenerTypeKey:
      if machineName.len == 0:
        raise newBonyLoadError(schemaViolation, ".bnb stateMachineListener record without stateMachine")
      flushLayer()
      let properties = record.propertyMap([
        nameKey, stateMachineListenerKindKey, listenerLayerIndexKey, listenerFromStateIndexKey, listenerToStateIndexKey,
        listenerSlotIndexKey, listenerHelperKindKey, listenerHelperTargetKey, listenerInputIndexKey,
        listenerBoolValueKey, listenerNumberValueKey, listenerHitRadiusKey,
      ])
      let scalars = decodeBnbScalarsFromProperties(
        decodeStateMachineListenerBnbScalars, properties, bonyStateMachineListenerScalarSpecs, strings, "stateMachineListener")
      let name = scalars.bnbScalarString(nameKey, "stateMachineListener.name")
      let kind = listenerKindFromTag(scalars.bnbScalarUint32(stateMachineListenerKindKey, "stateMachineListener.kind"))
      case kind
      of stateEnterListener:
        let layerIndex = int(scalars.bnbScalarUint32(listenerLayerIndexKey, "stateMachineListener.layer"))
        if layerIndex >= layers.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.layer is out of range")
        let layer = layers[layerIndex]
        if listenerFromStateIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb enter listener must not contain from state")
        listeners.add stateMachineStateEnterListener(
          name,
          layer.name,
          stateNameByIndex(layer.states, scalars.bnbScalarUint32(listenerToStateIndexKey, "stateMachineListener.to"), "stateMachineListener.to"),
        )
      of stateExitListener:
        let layerIndex = int(scalars.bnbScalarUint32(listenerLayerIndexKey, "stateMachineListener.layer"))
        if layerIndex >= layers.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.layer is out of range")
        let layer = layers[layerIndex]
        if listenerToStateIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb exit listener must not contain to state")
        listeners.add stateMachineStateExitListener(
          name,
          layer.name,
          stateNameByIndex(layer.states, scalars.bnbScalarUint32(listenerFromStateIndexKey, "stateMachineListener.from"), "stateMachineListener.from"),
        )
      of transitionListener:
        let layerIndex = int(scalars.bnbScalarUint32(listenerLayerIndexKey, "stateMachineListener.layer"))
        if layerIndex >= layers.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.layer is out of range")
        let layer = layers[layerIndex]
        listeners.add stateMachineTransitionListener(
          name,
          layer.name,
          stateNameByIndex(layer.states, scalars.bnbScalarUint32(listenerFromStateIndexKey, "stateMachineListener.from"), "stateMachineListener.from"),
          stateNameByIndex(layer.states, scalars.bnbScalarUint32(listenerToStateIndexKey, "stateMachineListener.to"), "stateMachineListener.to"),
        )
      of pointerDownListener, pointerUpListener, pointerEnterListener, pointerExitListener, pointerMoveListener:
        if listenerLayerIndexKey in properties or listenerFromStateIndexKey in properties or listenerToStateIndexKey in properties:
          raise newBonyLoadError(schemaViolation, ".bnb pointer listener must not contain lifecycle fields")
        let slotIndex = int(scalars.bnbScalarUint32(listenerSlotIndexKey, "stateMachineListener.slot"))
        if slotIndex >= skeleton.slots.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.slot is out of range")
        let inputIndex = int(scalars.bnbScalarUint32(listenerInputIndexKey, "stateMachineListener.input"))
        if inputIndex >= inputs.len:
          raise newBonyLoadError(unknownRequiredReference, ".bnb stateMachineListener.input is out of range")
        let targetKind = helperKindFromTag(uint64(scalars.bnbScalarUint32(listenerHelperKindKey, "stateMachineListener.helperKind")))
        let target = scalars.bnbScalarString(listenerHelperTargetKey, "stateMachineListener.target")
        let input = inputs[inputIndex]
        var boolValue = false
        var hasBoolValue = false
        var numberValue = 0.0
        var hasNumberValue = false
        case input.kind
        of boolInput:
          if listenerBoolValueKey notin properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer bool listener value is required")
          if listenerNumberValueKey in properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer bool listener must not contain number value")
          boolValue = scalars.bnbScalarBool(listenerBoolValueKey, "stateMachineListener.boolValue")
          hasBoolValue = true
        of numberInput:
          if listenerBoolValueKey in properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer number listener must not contain bool value")
          numberValue = scalars.bnbScalarFloat(listenerNumberValueKey, "stateMachineListener.numberValue")
          hasNumberValue = true
        of triggerInput:
          if listenerBoolValueKey in properties or listenerNumberValueKey in properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer trigger listener must not contain values")
        var hitRadius = 0.0
        var hasHitRadius = false
        case targetKind
        of pointHelperTarget:
          hitRadius = scalars.bnbScalarFloat(listenerHitRadiusKey, "stateMachineListener.hitRadius")
          hasHitRadius = true
        of boundingBoxHelperTarget:
          if listenerHitRadiusKey in properties:
            raise newBonyLoadError(schemaViolation, ".bnb pointer bounding-box listener must not contain hitRadius")
        listeners.add stateMachinePointerListener(
          name, kind, skeleton.slots[slotIndex].name, targetKind, target, input.name,
          hitRadius = hitRadius,
          hasHitRadius = hasHitRadius,
          boolValue = boolValue,
          hasBoolValue = hasBoolValue,
          numberValue = numberValue,
          hasNumberValue = hasNumberValue,
        )
    else:
      discard
  flushMachine()


proc decodeAssetObjects(objects: openArray[BnbObjectRecord]; strings: BnbStringTable): BonyAsset =
  let skeleton = decodeSkeletonObjects(objects, strings)
  let animations = decodeAnimationObjects(objects, strings, skeleton)
  let machines = decodeStateMachineObjects(objects, strings, animations, skeleton)
  for machine in machines:
    validatePointerListenerTargets(skeleton, machine)
  bonyAsset(skeleton, animations, machines)


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
