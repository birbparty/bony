## M6 semantic .bnb encoder/decoder for the current SkeletonData model.

import std/[json, strutils, tables]

import bony/binary/framing
import bony/generated/wire
import bony/model

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


proc decodeSkeletonObjects(objects: openArray[BnbObjectRecord]; strings: BnbStringTable): SkeletonData =
  var hasSkeleton = false
  var headerValue: SkeletonHeader
  var bones: seq[BoneData]
  var slots: seq[SlotData]
  var regions: seq[RegionAttachment]
  var pathAttachments: seq[PathAttachmentData]
  var paths: seq[PathConstraintData]

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
      let properties = record.propertyMap([nameKey, boneKey, targetKey, pathKey, orderKey])
      paths.add pathConstraintData(
        properties.readStringProperty(strings, nameKey, "path.name"),
        properties.readStringProperty(strings, boneKey, "path.bone"),
        properties.readStringProperty(strings, targetKey, "path.target"),
        properties.readStringProperty(strings, pathKey, "path.path"),
        properties.readOptionalIntProperty(orderKey, defaultInt("path", "order"), "path.order"),
      )
    else:
      discard

  if not hasSkeleton:
    raise newBonyLoadError(schemaViolation, ".bnb skeleton object is required")
  skeletonData(headerValue, bones, slots, regions, pathAttachments, paths)


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
