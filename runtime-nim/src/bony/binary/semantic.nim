## M6/M7 semantic .bnb encoder/decoder for the current SkeletonData model.

import std/[json, strutils, tables]

import bony/binary/framing
import bony/generated/wire
import bony/model
import bony/deform/deformers
import bony/deform/keyforms
import bony/deform/parameters

const
  skeletonTypeKey = 1'u64
  boneTypeKey = 2'u64
  slotTypeKey = 1000'u64
  regionTypeKey = 1001'u64
  pathTypeKey = 4000'u64
  pathAttachmentTypeKey = 4001'u64

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
  let val = readVarintPayload(properties[propertyKey], context)
  if val < 0 or val > int(high(uint32)):
    raise newBonyLoadError(numericOutOfRange, ".bnb " & context & " varuint is out of uint32 range")
  uint32(val)


proc readRequiredUintProperty(
  properties: Table[uint64, seq[byte]];
  propertyKey: uint64;
  context: string;
): uint32 =
  if propertyKey notin properties:
    raise newBonyLoadError(schemaViolation, ".bnb " & context & " is required")
  let val = readVarintPayload(properties[propertyKey], context)
  if val < 0 or val > int(high(uint32)):
    raise newBonyLoadError(numericOutOfRange, ".bnb " & context & " varuint is out of uint32 range")
  uint32(val)


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

  for path in data.paths:
    var properties: seq[BnbPropertyRecord]
    properties.addStringIfNeeded(toc, table, nameKey, path.name, "", required = true)
    properties.addStringIfNeeded(toc, table, boneKey, path.bone, "", required = true)
    properties.addStringIfNeeded(toc, table, targetKey, path.target, "", required = true)
    properties.addStringIfNeeded(toc, table, pathKey, path.path, "", required = true)
    properties.addIntIfNeeded(toc, orderKey, path.order, defaultInt("path", "order"))
    result.add BnbObjectRecord(typeKey: pathTypeKey, properties: properties)

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
      defProperties.addProperty(toc, deformerOrderKey, writeVarintPayload(int(def.order)))
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
        wProperties.addProperty(toc, warpRowsKey, writeVarintPayload(int(warp.rows)))
      if warp.cols != 2'u32:
        wProperties.addProperty(toc, warpColsKey, writeVarintPayload(int(warp.cols)))
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
      bProperties.addProperty(toc, blendValueCountKey, writeVarintPayload(blend.valueCount))
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
      var paramMap = initTable[string, ParameterAxis]()
      for p in loadedParameters:
        paramMap[p.name] = p
      emitPendingDeformer(loadedDeformers, pendingId, pendingParent, pendingOrder,
        pendingKind, pendingWarp, pendingRotation, pendingBlendAxes, pendingKeyforms, blendPending)
      deformerPending = false
      geometryReady = false
      blendPending = false
      pendingBlendAxes = @[]
      pendingKeyforms = @[]

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
      let properties = record.propertyMap([nameKey, boneKey, targetKey, pathKey, orderKey])
      paths.add pathConstraintData(
        properties.readStringProperty(strings, nameKey, "path.name"),
        properties.readStringProperty(strings, boneKey, "path.bone"),
        properties.readStringProperty(strings, targetKey, "path.target"),
        properties.readStringProperty(strings, pathKey, "path.path"),
        properties.readOptionalIntProperty(orderKey, defaultInt("path", "order"), "path.order"),
      )
    of parameterTypeKey:
      flushPendingIfAny()
      let properties = record.propertyMap([nameKey, parameterMinKey, parameterMaxKey, parameterDefaultKey])
      let paramName = properties.readStringProperty(strings, nameKey, "parameter.name")
      let paramMin = readF32Payload(properties.getOrDefault(parameterMinKey, @[]), "parameter.min")
      let paramMax = readF32Payload(properties.getOrDefault(parameterMaxKey, @[]), "parameter.max")
      if parameterMinKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb parameter.min is required")
      if parameterMaxKey notin properties:
        raise newBonyLoadError(schemaViolation, ".bnb parameter.max is required")
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
  skeletonData(headerValue, bones, slots, regions, pathAttachments, paths, loadedParameters, loadedDeformers)


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
