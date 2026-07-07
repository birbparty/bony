## M1 .bony JSON loader/serializer.

import std/[algorithm, json, math, sequtils, sets, strutils, tables]

import bony/generated/wire
import bony/asset
import bony/model
import bony/wiremeta
import bony/mesh/attachments
import bony/deform/deformers
import bony/deform/keyforms
import bony/anim/timelines
import bony/statemachine/core

const
  skeletonTypeId = "skeleton"
  boneTypeId = "bone"
  slotTypeId = "slot"
  regionTypeId = "region"
  pathTypeId = "path"
  ikConstraintTypeId = "ikConstraint"
  transformConstraintTypeId = "transformConstraint"
  physicsConstraintTypeId = "physicsConstraint"
  pointAttachmentTypeId = "pointAttachment"
  boundingBoxAttachmentTypeId = "boundingBoxAttachment"
  clippingAttachmentTypeId = "clippingAttachment"
  meshAttachmentTypeId = "meshAttachment"


proc skipJsonWhitespace(text: string; index: var int) =
  while index < text.len and text[index] in {' ', '\t', '\r', '\n'}:
    inc index


proc readJsonString(text: string; index: var int): string =
  if index >= text.len or text[index] != '"':
    raise newBonyLoadError(schemaViolation, "expected JSON string")
  inc index
  while index < text.len:
    let ch = text[index]
    if ch == '"':
      inc index
      return result
    if ch == '\\':
      result.add(ch)
      inc index
      if index >= text.len:
        raise newBonyLoadError(schemaViolation, "unterminated JSON escape")
      result.add(text[index])
      inc index
    else:
      result.add(ch)
      inc index
  raise newBonyLoadError(schemaViolation, "unterminated JSON string")


proc rejectDuplicateObjectKeys*(text: string) =
  type JsonContext = object
    isObject: bool
    keys: HashSet[string]
    expectingKey: bool

  var stack: seq[JsonContext] = @[]
  var index = 0
  while index < text.len:
    skipJsonWhitespace(text, index)
    if index >= text.len:
      break
    case text[index]
    of '{':
      stack.add(JsonContext(isObject: true, keys: initHashSet[string](), expectingKey: true))
      inc index
    of '}':
      if stack.len > 0:
        discard stack.pop()
      inc index
    of '[':
      stack.add(JsonContext(isObject: false))
      inc index
    of ']':
      if stack.len > 0:
        discard stack.pop()
      inc index
    of ',':
      if stack.len > 0 and stack[^1].isObject:
        stack[^1].expectingKey = true
      inc index
    of '"':
      let token = readJsonString(text, index)
      if stack.len > 0 and stack[^1].isObject and stack[^1].expectingKey:
        var after = index
        skipJsonWhitespace(text, after)
        if after < text.len and text[after] == ':':
          if token in stack[^1].keys:
            raise newBonyLoadError(duplicateKey, "duplicate JSON object key: " & token)
          stack[^1].keys.incl(token)
          stack[^1].expectingKey = false
    else:
      inc index


proc requireObject(node: JsonNode; context: string): JsonNode =
  if node.kind != JObject:
    raise newBonyLoadError(schemaViolation, context & " must be an object")
  node


proc requireArray(node: JsonNode; context: string): JsonNode =
  if node.kind != JArray:
    raise newBonyLoadError(schemaViolation, context & " must be an array")
  node


proc optionalString(node: JsonNode; key, defaultValue, context: string): string =
  if not node.hasKey(key):
    return defaultValue
  let value = node[key]
  if value.kind != JString:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must be a string")
  value.getStr()


proc optionalFloat(node: JsonNode; key: string; defaultValue: float64; context: string): float64 =
  if not node.hasKey(key):
    return quantizeF32(defaultValue, context & "." & key)
  let value = node[key]
  if value.kind notin {JInt, JFloat}:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must be numeric")
  quantizeF32(value.getFloat(), context & "." & key)


proc requiredF64(node: JsonNode; key, context: string): float64 =
  if not node.hasKey(key):
    raise newBonyLoadError(schemaViolation, context & "." & key & " is required")
  let value = node[key]
  if value.kind notin {JInt, JFloat}:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must be numeric")
  requireFiniteF64(value.getFloat(), context & "." & key)


proc optionalInt(node: JsonNode; key: string; defaultValue: int; context: string): int =
  if not node.hasKey(key):
    return defaultValue
  let value = node[key]
  if value.kind != JInt:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must be an integer")
  value.getInt()


proc requiredFloat(node: JsonNode; key, context: string): float64 =
  if not node.hasKey(key):
    raise newBonyLoadError(schemaViolation, context & "." & key & " is required")
  optionalFloat(node, key, 0.0, context)


proc requiredInt(node: JsonNode; key, context: string): int =
  if not node.hasKey(key):
    raise newBonyLoadError(schemaViolation, context & "." & key & " is required")
  let value = node[key]
  if value.kind != JInt:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must be an integer")
  value.getInt()


proc optionalBool(node: JsonNode; key: string; defaultValue: bool; context: string): bool =
  if not node.hasKey(key):
    return defaultValue
  let value = node[key]
  if value.kind != JBool:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must be bool")
  value.getBool()


proc requiredString(node: JsonNode; key, context: string): string =
  if not node.hasKey(key):
    raise newBonyLoadError(schemaViolation, context & "." & key & " is required")
  optionalString(node, key, "", context)


type JsonScalarAlias = object
  jsonKey: string
  propertyId: string


proc jsonScalarAlias(jsonKey, propertyId: string): JsonScalarAlias =
  JsonScalarAlias(jsonKey: jsonKey, propertyId: propertyId)


proc scalarJsonKey(propertyId: string; aliases: openArray[JsonScalarAlias]): string =
  for alias in aliases:
    if alias.propertyId == propertyId:
      return alias.jsonKey
  propertyId


proc bonyScalarValueFromJson(value: JsonNode; spec: BonyScalarPropertySpec; context: string): BonyScalarValue =
  case spec.kind
  of bskString:
    if value.kind != JString:
      raise newBonyLoadError(schemaViolation, context & " must be a string")
    bonyStringValue(value.getStr())
  of bskF32:
    if value.kind notin {JInt, JFloat}:
      raise newBonyLoadError(schemaViolation, context & " must be numeric")
    bonyF32Value(quantizeF32(value.getFloat(), context))
  of bskF64:
    if value.kind notin {JInt, JFloat}:
      raise newBonyLoadError(schemaViolation, context & " must be numeric")
    bonyF64Value(requireFiniteF64(value.getFloat(), context))
  of bskBool:
    if value.kind != JBool:
      raise newBonyLoadError(schemaViolation, context & " must be bool")
    bonyBoolValue(value.getBool())
  of bskVarint:
    if value.kind != JInt:
      raise newBonyLoadError(schemaViolation, context & " must be an integer")
    bonyIntValue(value.getInt().int64)
  of bskVaruint:
    if value.kind != JInt:
      raise newBonyLoadError(schemaViolation, context & " must be an integer")
    let intValue = value.getInt()
    if intValue < 0:
      raise newBonyLoadError(schemaViolation, context & " must be non-negative")
    bonyUintValue(intValue.uint64)


proc jsonScalarsFromObject(
    node: JsonNode;
    specs: openArray[BonyScalarPropertySpec];
    context: string;
    aliases: openArray[JsonScalarAlias];
): seq[BonyJsonScalarProperty] =
  for spec in specs:
    let key = scalarJsonKey(spec.propertyId, aliases)
    if node.hasKey(key):
      result.add BonyJsonScalarProperty(
        propertyId: spec.propertyId,
        value: bonyScalarValueFromJson(node[key], spec, context & "." & key),
      )


type BonyJsonScalarDecoder = proc(
  properties: openArray[BonyJsonScalarProperty]
): seq[BonyJsonScalarProperty]


proc decodeJsonScalarsForLoad(
    decoder: BonyJsonScalarDecoder;
    properties: openArray[BonyJsonScalarProperty];
    context: string;
): seq[BonyJsonScalarProperty] =
  try:
    decoder(properties)
  except ValueError as exc:
    raise newBonyLoadError(schemaViolation, context & ": " & exc.msg)


proc decodeJsonScalarsFromObject(
    decoder: BonyJsonScalarDecoder;
    node: JsonNode;
    specs: openArray[BonyScalarPropertySpec];
    context: string;
    aliases: openArray[JsonScalarAlias];
): seq[BonyJsonScalarProperty] =
  decodeJsonScalarsForLoad(decoder, jsonScalarsFromObject(node, specs, context, aliases), context)


proc decodeJsonScalarsFromObject(
    decoder: BonyJsonScalarDecoder;
    node: JsonNode;
    specs: openArray[BonyScalarPropertySpec];
    context: string;
): seq[BonyJsonScalarProperty] =
  decodeJsonScalarsFromObject(decoder, node, specs, context, [])


proc scalarValue(properties: openArray[BonyJsonScalarProperty]; propertyId, context: string): BonyScalarValue =
  for property in properties:
    if property.propertyId == propertyId:
      return property.value
  raise newBonyLoadError(schemaViolation, context & "." & propertyId & " is required")


proc scalarString(properties: openArray[BonyJsonScalarProperty]; propertyId, context: string): string =
  scalarValue(properties, propertyId, context).stringValue


proc scalarFloat(properties: openArray[BonyJsonScalarProperty]; propertyId, context: string): float64 =
  scalarValue(properties, propertyId, context).floatValue


proc scalarBool(properties: openArray[BonyJsonScalarProperty]; propertyId, context: string): bool =
  scalarValue(properties, propertyId, context).boolValue


proc scalarInt(properties: openArray[BonyJsonScalarProperty]; propertyId, context: string): int =
  scalarValue(properties, propertyId, context).intValue.int


proc scalarUint(properties: openArray[BonyJsonScalarProperty]; propertyId, context: string): uint64 =
  scalarValue(properties, propertyId, context).uintValue


proc optionalStringArray(node: JsonNode; key, context: string): seq[string] =
  if not node.hasKey(key):
    return @[]
  let arrayNode = requireArray(node[key], context & "." & key)
  for index, item in arrayNode.elems:
    let itemContext = context & "." & key & "[" & $index & "]"
    if item.kind != JString:
      raise newBonyLoadError(schemaViolation, itemContext & " must be a string")
    result.add item.getStr()


proc parseTransformMode(value: string; context: string): TransformMode =
  case value
  of "normal": normal
  of "onlyTranslation": onlyTranslation
  of "noRotationOrReflection": noRotationOrReflection
  of "noScale": noScale
  of "noScaleOrReflection": noScaleOrReflection
  else:
    raise newBonyLoadError(schemaViolation, context & ".transformMode is invalid")


proc transformModeName(mode: TransformMode): string =
  case mode
  of normal: "normal"
  of onlyTranslation: "onlyTranslation"
  of noRotationOrReflection: "noRotationOrReflection"
  of noScale: "noScale"
  of noScaleOrReflection: "noScaleOrReflection"


proc validateKnownKeys(node: JsonNode; allowed: openArray[string]; context: string) =
  for key in node.keys:
    var found = false
    for allowedKey in allowed:
      if key == allowedKey:
        found = true
        break
    if not found:
      raise newBonyLoadError(schemaViolation, context & "." & key & " is not a recognized field")


proc addIndent(output: var string; level: int) =
  for _ in 0 ..< level * 2:
    output.add ' '


proc addJsonString(output: var string; value: string) =
  const hex = "0123456789abcdef"
  output.add '"'
  for ch in value:
    case ch
    of '"':
      output.add "\\\""
    of '\\':
      output.add "\\\\"
    of '\b':
      output.add "\\b"
    of '\f':
      output.add "\\f"
    of '\n':
      output.add "\\n"
    of '\r':
      output.add "\\r"
    of '\t':
      output.add "\\t"
    else:
      let code = ord(ch)
      if code < 0x20:
        output.add "\\u00"
        output.add hex[(code shr 4) and 0xf]
        output.add hex[code and 0xf]
      else:
        output.add ch
  output.add '"'


proc canonicalNumber(value: float64): string =
  let finite = requireFiniteF64(value)
  if finite == 0.0:
    return "0"
  if finite == floor(finite) and abs(finite) <= 9007199254740991.0:
    return $int64(finite)
  $finite


proc addFieldPrefix(output: var string; key: string; indent: int; first: var bool) =
  if not first:
    output.add ",\n"
  first = false
  output.addIndent(indent)
  output.addJsonString(key)
  output.add ": "


proc addStringField(output: var string; key, value: string; indent: int; first: var bool) =
  output.addFieldPrefix(key, indent, first)
  output.addJsonString(value)


proc addNumberField(output: var string; key: string; value: float64; indent: int; first: var bool) =
  output.addFieldPrefix(key, indent, first)
  output.add canonicalNumber(value)


proc addIntField(output: var string; key: string; value: int; indent: int; first: var bool) =
  output.addFieldPrefix(key, indent, first)
  output.add $value


proc addBoolField(output: var string; key: string; value: bool; indent: int; first: var bool) =
  output.addFieldPrefix(key, indent, first)
  output.add (if value: "true" else: "false")


func jsonScalarString(propertyId, value: string): BonyJsonScalarProperty =
  BonyJsonScalarProperty(propertyId: propertyId, value: bonyStringValue(value))


func jsonScalarFloat(propertyId: string; value: float64): BonyJsonScalarProperty =
  BonyJsonScalarProperty(propertyId: propertyId, value: bonyF32Value(value))


func jsonScalarF64(propertyId: string; value: float64): BonyJsonScalarProperty =
  BonyJsonScalarProperty(propertyId: propertyId, value: bonyF64Value(value))


func jsonScalarBool(propertyId: string; value: bool): BonyJsonScalarProperty =
  BonyJsonScalarProperty(propertyId: propertyId, value: bonyBoolValue(value))


func jsonScalarInt(propertyId: string; value: int): BonyJsonScalarProperty =
  BonyJsonScalarProperty(propertyId: propertyId, value: bonyIntValue(value.int64))


func jsonScalarUint(propertyId: string; value: uint64): BonyJsonScalarProperty =
  BonyJsonScalarProperty(propertyId: propertyId, value: bonyUintValue(value))


proc jsonScalarIndex(properties: openArray[BonyJsonScalarProperty]; propertyId: string): int =
  for index, property in properties:
    if property.propertyId == propertyId:
      return index
  -1


proc addJsonScalarField(
    output: var string;
    properties: openArray[BonyJsonScalarProperty];
    propertyId, jsonKey: string;
    indent: int;
    first: var bool;
) =
  let index = jsonScalarIndex(properties, propertyId)
  if index < 0:
    return
  let property = properties[index]
  case property.value.kind
  of bskString:
    output.addStringField(jsonKey, property.value.stringValue, indent, first)
  of bskF32, bskF64:
    output.addNumberField(jsonKey, property.value.floatValue, indent, first)
  of bskBool:
    output.addBoolField(jsonKey, property.value.boolValue, indent, first)
  of bskVarint:
    output.addIntField(jsonKey, property.value.intValue.int, indent, first)
  of bskVaruint:
    output.addIntField(jsonKey, property.value.uintValue.int, indent, first)


proc addJsonScalarField(
    output: var string;
    properties: openArray[BonyJsonScalarProperty];
    propertyId: string;
    indent: int;
    first: var bool;
) =
  output.addJsonScalarField(properties, propertyId, propertyId, indent, first)


proc parseBonyAnimations(root: JsonNode; data: SkeletonData): Table[string, AnimationClip]
proc parseBonyStateMachines(
  root: JsonNode;
  data: SkeletonData;
  clips: Table[string, AnimationClip];
): seq[StateMachine]


proc loadBonyJson*(text: string): SkeletonData =
  rejectDuplicateObjectKeys(text)

  let parsed =
    try:
      parseJson(text)
    except JsonParsingError as exc:
      raise newBonyLoadError(schemaViolation, "invalid JSON: " & exc.msg)

  let root = requireObject(parsed, "root")
  validateKnownKeys(root, ["skeleton", "bones", "slots", "regions", "pointAttachments", "boundingBoxAttachments", "nestedRigAttachments", "clippingAttachments", "meshAttachments", "pathAttachments", "paths", "ikConstraints", "transformConstraints", "physicsConstraints", "skins", "parameters", "deformers", "animations", "stateMachines"], "root")

  if not root.hasKey("skeleton"):
    raise newBonyLoadError(schemaViolation, "root.skeleton is required")
  let skeleton = requireObject(root["skeleton"], "skeleton")
  validateKnownKeys(skeleton, ["name", "version"], "skeleton")
  let skeletonScalars = decodeJsonScalarsFromObject(
    decodeSkeletonJsonScalars, skeleton, bonySkeletonScalarSpecs, "skeleton")

  let loadedHeader = skeletonHeader(
    scalarString(skeletonScalars, "name", "skeleton"),
    scalarString(skeletonScalars, "version", "skeleton"),
  )

  if not root.hasKey("bones"):
    raise newBonyLoadError(schemaViolation, "root.bones is required")
  let bonesNode = requireArray(root["bones"], "bones")

  var loadedBones: seq[BoneData] = @[]
  for index, boneNode in bonesNode.elems:
    let context = "bones[" & $index & "]"
    let boneObject = requireObject(boneNode, context)
    validateKnownKeys(
      boneObject,
      [
        "name",
        "parent",
        "x",
        "y",
        "rotation",
        "scaleX",
        "scaleY",
        "shearX",
        "shearY",
        "inheritRotation",
        "inheritScale",
        "inheritReflection",
        "transformMode",
        "skinRequired",
      ],
      context,
    )
    let boneScalars = decodeJsonScalarsFromObject(
      decodeBoneJsonScalars, boneObject, bonyBoneScalarSpecs, context)
    let inheritRotation = scalarBool(boneScalars, "inheritRotation", context)
    let inheritScale = scalarBool(boneScalars, "inheritScale", context)
    let inheritReflection = scalarBool(boneScalars, "inheritReflection", context)
    let mode = parseTransformMode(scalarString(boneScalars, "transformMode", context), context)
    loadedBones.add boneData(
      scalarString(boneScalars, "name", context),
      scalarString(boneScalars, "parent", context),
      localTransform(
        x = scalarFloat(boneScalars, "x", context),
        y = scalarFloat(boneScalars, "y", context),
        rotation = scalarFloat(boneScalars, "rotation", context),
        scaleX = scalarFloat(boneScalars, "scaleX", context),
        scaleY = scalarFloat(boneScalars, "scaleY", context),
        shearX = scalarFloat(boneScalars, "shearX", context),
        shearY = scalarFloat(boneScalars, "shearY", context),
        inheritRotation = inheritRotation,
        inheritScale = inheritScale,
        inheritReflection = inheritReflection,
        transformMode = mode,
      ),
      skinRequired = scalarBool(boneScalars, "skinRequired", context),
    )

  var loadedSlots: seq[SlotData] = @[]
  if root.hasKey("slots"):
    let slotsNode = requireArray(root["slots"], "slots")
    for index, slotNode in slotsNode.elems:
      let context = "slots[" & $index & "]"
      let slotObject = requireObject(slotNode, context)
      validateKnownKeys(slotObject, ["name", "bone", "attachment"], context)
      let slotScalars = decodeJsonScalarsFromObject(
        decodeSlotJsonScalars, slotObject, bonySlotScalarSpecs, context)
      loadedSlots.add slotData(
        scalarString(slotScalars, "name", context),
        scalarString(slotScalars, "bone", context),
        scalarString(slotScalars, "attachment", context),
      )

  var loadedRegions: seq[RegionAttachment] = @[]
  if root.hasKey("regions"):
    let regionsNode = requireArray(root["regions"], "regions")
    for index, regionNode in regionsNode.elems:
      let context = "regions[" & $index & "]"
      let regionObject = requireObject(regionNode, context)
      validateKnownKeys(regionObject, ["name", "width", "height", "texturePage", "u0", "v0", "u1", "v1", "alphaMode"], context)
      let regionScalars = decodeJsonScalarsFromObject(
        decodeRegionJsonScalars, regionObject, bonyRegionScalarSpecs, context)
      loadedRegions.add regionAttachment(
        scalarString(regionScalars, "name", context),
        scalarFloat(regionScalars, "width", context),
        scalarFloat(regionScalars, "height", context),
        texturePage = scalarString(regionScalars, "texturePage", context),
        u0 = scalarFloat(regionScalars, "u0", context),
        v0 = scalarFloat(regionScalars, "v0", context),
        u1 = scalarFloat(regionScalars, "u1", context),
        v1 = scalarFloat(regionScalars, "v1", context),
        alphaMode = scalarString(regionScalars, "alphaMode", context),
      )

  var loadedPointAttachments: seq[PointAttachmentData] = @[]
  if root.hasKey("pointAttachments"):
    let pointAttachmentsNode = requireArray(root["pointAttachments"], "pointAttachments")
    for index, pointNode in pointAttachmentsNode.elems:
      let context = "pointAttachments[" & $index & "]"
      let pointObject = requireObject(pointNode, context)
      validateKnownKeys(pointObject, ["name", "x", "y", "rotation"], context)
      let pointScalars = decodeJsonScalarsFromObject(
        decodePointAttachmentJsonScalars, pointObject, bonyPointAttachmentScalarSpecs, context)
      loadedPointAttachments.add pointAttachmentData(
        scalarString(pointScalars, "name", context),
        scalarFloat(pointScalars, "x", context),
        scalarFloat(pointScalars, "y", context),
        scalarFloat(pointScalars, "rotation", context),
      )

  var loadedBoundingBoxAttachments: seq[BoundingBoxAttachmentData] = @[]
  if root.hasKey("boundingBoxAttachments"):
    let boxAttachmentsNode = requireArray(root["boundingBoxAttachments"], "boundingBoxAttachments")
    for index, boxNode in boxAttachmentsNode.elems:
      let context = "boundingBoxAttachments[" & $index & "]"
      let boxObject = requireObject(boxNode, context)
      validateKnownKeys(boxObject, ["name", "vertices"], context)
      let boxScalars = decodeJsonScalarsFromObject(
        decodeBoundingBoxAttachmentJsonScalars, boxObject, bonyBoundingBoxAttachmentScalarSpecs, context)
      if not boxObject.hasKey("vertices"):
        raise newBonyLoadError(schemaViolation, context & ".vertices is required")
      let verticesNode = requireArray(boxObject["vertices"], context & ".vertices")
      var boxVertices: seq[float64] = @[]
      for vertexIndex, vertexNode in verticesNode.elems:
        let vertexCtx = context & ".vertices[" & $vertexIndex & "]"
        if vertexNode.kind notin {JInt, JFloat}:
          raise newBonyLoadError(schemaViolation, vertexCtx & " must be numeric")
        boxVertices.add requireFiniteF64(vertexNode.getFloat(), vertexCtx)
      loadedBoundingBoxAttachments.add boundingBoxAttachmentData(
        scalarString(boxScalars, "name", context),
        boxVertices,
      )

  var loadedNestedRigAttachments: seq[NestedRigAttachmentData] = @[]
  if root.hasKey("nestedRigAttachments"):
    let nestedRigAttachmentsNode = requireArray(root["nestedRigAttachments"], "nestedRigAttachments")
    for index, nestedNode in nestedRigAttachmentsNode.elems:
      let context = "nestedRigAttachments[" & $index & "]"
      let nestedObject = requireObject(nestedNode, context)
      validateKnownKeys(nestedObject, ["name", "skeleton", "skin", "animation"], context)
      let nestedScalars = decodeJsonScalarsFromObject(
        decodeNestedRigAttachmentJsonScalars,
        nestedObject,
        bonyNestedRigAttachmentScalarSpecs,
        context,
        [
          jsonScalarAlias("skeleton", "nestedSkeleton"),
          jsonScalarAlias("skin", "nestedSkin"),
          jsonScalarAlias("animation", "nestedAnimation"),
        ],
      )
      loadedNestedRigAttachments.add nestedRigAttachmentData(
        scalarString(nestedScalars, "name", context),
        scalarString(nestedScalars, "nestedSkeleton", context),
        scalarString(nestedScalars, "nestedSkin", context),
        scalarString(nestedScalars, "nestedAnimation", context),
      )

  var loadedPathAttachments: seq[PathAttachmentData] = @[]
  if root.hasKey("pathAttachments"):
    let pathAttachmentsNode = requireArray(root["pathAttachments"], "pathAttachments")
    for index, pathAttachmentNode in pathAttachmentsNode.elems:
      let context = "pathAttachments[" & $index & "]"
      let pathAttachmentObject = requireObject(pathAttachmentNode, context)
      validateKnownKeys(pathAttachmentObject, ["name", "p0x", "p0y", "p1x", "p1y", "p2x", "p2y", "p3x", "p3y"], context)
      let pathAttachmentScalars = decodeJsonScalarsFromObject(
        decodePathAttachmentJsonScalars, pathAttachmentObject, bonyPathAttachmentScalarSpecs, context)
      loadedPathAttachments.add pathAttachmentData(
        scalarString(pathAttachmentScalars, "name", context),
        scalarFloat(pathAttachmentScalars, "p0x", context),
        scalarFloat(pathAttachmentScalars, "p0y", context),
        scalarFloat(pathAttachmentScalars, "p1x", context),
        scalarFloat(pathAttachmentScalars, "p1y", context),
        scalarFloat(pathAttachmentScalars, "p2x", context),
        scalarFloat(pathAttachmentScalars, "p2y", context),
        scalarFloat(pathAttachmentScalars, "p3x", context),
        scalarFloat(pathAttachmentScalars, "p3y", context),
      )

  var loadedClippingAttachments: seq[ClipAttachmentData] = @[]
  if root.hasKey("clippingAttachments"):
    let clippingAttachmentsNode = requireArray(root["clippingAttachments"], "clippingAttachments")
    for index, clipNode in clippingAttachmentsNode.elems:
      let context = "clippingAttachments[" & $index & "]"
      let clipObject = requireObject(clipNode, context)
      validateKnownKeys(clipObject, ["name", "vertices", "untilSlot"], context)
      let clipScalars = decodeJsonScalarsFromObject(
        decodeClippingAttachmentJsonScalars, clipObject, bonyClippingAttachmentScalarSpecs, context)
      if not clipObject.hasKey("vertices"):
        raise newBonyLoadError(schemaViolation, context & ".vertices is required")
      let verticesNode = requireArray(clipObject["vertices"], context & ".vertices")
      var clipVertices: seq[float64] = @[]
      for vertexIndex, vertexNode in verticesNode.elems:
        let vertexCtx = context & ".vertices[" & $vertexIndex & "]"
        if vertexNode.kind notin {JInt, JFloat}:
          raise newBonyLoadError(schemaViolation, vertexCtx & " must be numeric")
        clipVertices.add requireFiniteF64(vertexNode.getFloat(), vertexCtx)
      loadedClippingAttachments.add clipAttachmentData(
        scalarString(clipScalars, "name", context),
        clipVertices,
        scalarString(clipScalars, "untilSlot", context),
      )

  var loadedMeshAttachments: seq[MeshAttachment] = @[]
  if root.hasKey("meshAttachments"):
    let meshAttachmentsNode = requireArray(root["meshAttachments"], "meshAttachments")
    for index, meshNode in meshAttachmentsNode.elems:
      let context = "meshAttachments[" & $index & "]"
      let meshObject = requireObject(meshNode, context)
      validateKnownKeys(meshObject, ["name", "weighted", "vertices", "uvs", "triangles"], context)
      let meshScalars = decodeJsonScalarsFromObject(
        decodeMeshAttachmentJsonScalars,
        meshObject,
        bonyMeshAttachmentScalarSpecs,
        context,
        [jsonScalarAlias("weighted", "meshWeighted")],
      )
      # The JSON field "weighted" maps to the meshWeighted property key, not an
      # id-named field; its default comes from the generated meshWeighted default.
      let weighted = scalarBool(meshScalars, "meshWeighted", context)

      # vertices: array of {x, y} (unweighted) or {influences: [...]} (weighted).
      # Values are quantized/assembled validation-free here; the whole-skeleton
      # (a)-(g) checks (bone resolution, weighted-flag agreement, index range)
      # run later in validateSkeletonData via skeletonData().
      if not meshObject.hasKey("vertices"):
        raise newBonyLoadError(schemaViolation, context & ".vertices is required")
      let verticesNode = requireArray(meshObject["vertices"], context & ".vertices")
      var meshVertices: seq[MeshVertex] = @[]
      for vertexIndex, vertexNode in verticesNode.elems:
        let vertexCtx = context & ".vertices[" & $vertexIndex & "]"
        let vertexObject = requireObject(vertexNode, vertexCtx)
        if vertexObject.hasKey("influences"):
          validateKnownKeys(vertexObject, ["influences"], vertexCtx)
          let influencesNode = requireArray(vertexObject["influences"], vertexCtx & ".influences")
          var influences: seq[MeshInfluence] = @[]
          for infIndex, infNode in influencesNode.elems:
            let infCtx = vertexCtx & ".influences[" & $infIndex & "]"
            let infObject = requireObject(infNode, infCtx)
            validateKnownKeys(infObject, ["bone", "bindX", "bindY", "weight"], infCtx)
            influences.add meshInfluence(
              requiredString(infObject, "bone", infCtx),
              requiredF64(infObject, "bindX", infCtx),
              requiredF64(infObject, "bindY", infCtx),
              requiredF64(infObject, "weight", infCtx),
            )
          meshVertices.add weightedMeshVertex(influences)
        else:
          validateKnownKeys(vertexObject, ["x", "y"], vertexCtx)
          meshVertices.add unweightedMeshVertex(
            requiredF64(vertexObject, "x", vertexCtx),
            requiredF64(vertexObject, "y", vertexCtx),
          )

      # uvs: flat [u0, v0, u1, v1, ...] number list, one pair per vertex.
      if not meshObject.hasKey("uvs"):
        raise newBonyLoadError(schemaViolation, context & ".uvs is required")
      let uvsNode = requireArray(meshObject["uvs"], context & ".uvs")
      if uvsNode.elems.len mod 2 != 0:
        raise newBonyLoadError(schemaViolation, context & ".uvs must contain u,v pairs")
      var meshUvs: seq[MeshUv] = @[]
      var uvCursor = 0
      while uvCursor < uvsNode.elems.len:
        let uNode = uvsNode.elems[uvCursor]
        let vNode = uvsNode.elems[uvCursor + 1]
        let uCtx = context & ".uvs[" & $uvCursor & "]"
        let vCtx = context & ".uvs[" & $(uvCursor + 1) & "]"
        if uNode.kind notin {JInt, JFloat}:
          raise newBonyLoadError(schemaViolation, uCtx & " must be numeric")
        if vNode.kind notin {JInt, JFloat}:
          raise newBonyLoadError(schemaViolation, vCtx & " must be numeric")
        meshUvs.add meshUv(
          requireFiniteF64(uNode.getFloat(), uCtx),
          requireFiniteF64(vNode.getFloat(), vCtx),
        )
        uvCursor += 2

      # triangles: flat vertex-index list; each triple names one triangle.
      if not meshObject.hasKey("triangles"):
        raise newBonyLoadError(schemaViolation, context & ".triangles is required")
      let trianglesNode = requireArray(meshObject["triangles"], context & ".triangles")
      var triangles: seq[uint16] = @[]
      for triIndex, triNode in trianglesNode.elems:
        let triCtx = context & ".triangles[" & $triIndex & "]"
        if triNode.kind != JInt:
          raise newBonyLoadError(schemaViolation, triCtx & " must be an integer")
        let triVal = triNode.getInt()
        if triVal < 0 or triVal > int(high(uint16)):
          raise newBonyLoadError(schemaViolation, triCtx & " is out of range")
        triangles.add uint16(triVal)

      loadedMeshAttachments.add meshAttachmentData(
        scalarString(meshScalars, "name", context),
        meshUvs,
        triangles,
        meshVertices,
        weighted,
      )

  var loadedPaths: seq[PathConstraintData] = @[]
  if root.hasKey("paths"):
    let pathsNode = requireArray(root["paths"], "paths")
    for index, pathNode in pathsNode.elems:
      let context = "paths[" & $index & "]"
      let pathObject = requireObject(pathNode, context)
      validateKnownKeys(pathObject, ["name", "bone", "target", "path", "order", "skinRequired", "position", "translateMix", "rotateMix"], context)
      let pathScalars = decodeJsonScalarsFromObject(
        decodePathJsonScalars, pathObject, bonyPathScalarSpecs, context)
      loadedPaths.add pathConstraintData(
        scalarString(pathScalars, "name", context),
        scalarString(pathScalars, "bone", context),
        scalarString(pathScalars, "target", context),
        scalarString(pathScalars, "path", context),
        scalarInt(pathScalars, "order", context),
        skinRequired = scalarBool(pathScalars, "skinRequired", context),
        hasPosition = pathObject.hasKey("position"),
        position =
          if pathObject.hasKey("position"): scalarFloat(pathScalars, "position", context)
          else: defaultFloat(pathTypeId, "position"),
        hasTranslateMix = pathObject.hasKey("translateMix"),
        translateMix =
          if pathObject.hasKey("translateMix"): scalarFloat(pathScalars, "translateMix", context)
          else: defaultFloat(pathTypeId, "translateMix"),
        hasRotateMix = pathObject.hasKey("rotateMix"),
        rotateMix =
          if pathObject.hasKey("rotateMix"): scalarFloat(pathScalars, "rotateMix", context)
          else: defaultFloat(pathTypeId, "rotateMix"),
      )

  var loadedIkConstraints: seq[IkConstraintData] = @[]
  if root.hasKey("ikConstraints"):
    let ikConstraintsNode = requireArray(root["ikConstraints"], "ikConstraints")
    for index, ikNode in ikConstraintsNode.elems:
      let context = "ikConstraints[" & $index & "]"
      let ikObject = requireObject(ikNode, context)
      validateKnownKeys(ikObject, ["name", "bones", "target", "order", "skinRequired", "mix", "bendPositive"], context)
      let ikScalars = decodeJsonScalarsFromObject(
        decodeIkConstraintJsonScalars, ikObject, bonyIkConstraintScalarSpecs, context)
      if not ikObject.hasKey("bones"):
        raise newBonyLoadError(schemaViolation, context & ".bones is required")
      let bonesNode = requireArray(ikObject["bones"], context & ".bones")
      var ikBones: seq[string] = @[]
      for boneIndex, boneNameNode in bonesNode.elems:
        let boneCtx = context & ".bones[" & $boneIndex & "]"
        if boneNameNode.kind != JString:
          raise newBonyLoadError(schemaViolation, boneCtx & " must be a string")
        ikBones.add boneNameNode.getStr()
      loadedIkConstraints.add ikConstraintData(
        scalarString(ikScalars, "name", context),
        scalarString(ikScalars, "target", context),
        ikBones,
        order = scalarInt(ikScalars, "order", context),
        skinRequired = scalarBool(ikScalars, "skinRequired", context),
        hasMix = ikObject.hasKey("mix"),
        mix =
          if ikObject.hasKey("mix"): scalarFloat(ikScalars, "mix", context)
          else: defaultFloat(ikConstraintTypeId, "mix"),
        hasBendPositive = ikObject.hasKey("bendPositive"),
        bendPositive =
          if ikObject.hasKey("bendPositive"): scalarBool(ikScalars, "bendPositive", context)
          else: defaultBool(ikConstraintTypeId, "bendPositive"),
      )

  var loadedTransformConstraints: seq[TransformConstraintData] = @[]
  if root.hasKey("transformConstraints"):
    let transformConstraintsNode = requireArray(root["transformConstraints"], "transformConstraints")
    for index, tcNode in transformConstraintsNode.elems:
      let context = "transformConstraints[" & $index & "]"
      let tcObject = requireObject(tcNode, context)
      validateKnownKeys(tcObject, ["name", "bone", "target", "order", "skinRequired", "translateMix", "rotateMix", "scaleMix", "shearMix"], context)
      let tcScalars = decodeJsonScalarsFromObject(
        decodeTransformConstraintJsonScalars, tcObject, bonyTransformConstraintScalarSpecs, context)
      loadedTransformConstraints.add transformConstraintData(
        scalarString(tcScalars, "name", context),
        scalarString(tcScalars, "bone", context),
        scalarString(tcScalars, "target", context),
        order = scalarInt(tcScalars, "order", context),
        skinRequired = scalarBool(tcScalars, "skinRequired", context),
        hasTranslateMix = tcObject.hasKey("translateMix"),
        translateMix =
          if tcObject.hasKey("translateMix"): scalarFloat(tcScalars, "translateMix", context)
          else: defaultFloat(transformConstraintTypeId, "translateMix"),
        hasRotateMix = tcObject.hasKey("rotateMix"),
        rotateMix =
          if tcObject.hasKey("rotateMix"): scalarFloat(tcScalars, "rotateMix", context)
          else: defaultFloat(transformConstraintTypeId, "rotateMix"),
        hasScaleMix = tcObject.hasKey("scaleMix"),
        scaleMix =
          if tcObject.hasKey("scaleMix"): scalarFloat(tcScalars, "scaleMix", context)
          else: defaultFloat(transformConstraintTypeId, "scaleMix"),
        hasShearMix = tcObject.hasKey("shearMix"),
        shearMix =
          if tcObject.hasKey("shearMix"): scalarFloat(tcScalars, "shearMix", context)
          else: defaultFloat(transformConstraintTypeId, "shearMix"),
      )

  var loadedPhysicsConstraints: seq[PhysicsConstraintData] = @[]
  if root.hasKey("physicsConstraints"):
    let physicsConstraintsNode = requireArray(root["physicsConstraints"], "physicsConstraints")
    for index, pcNode in physicsConstraintsNode.elems:
      let context = "physicsConstraints[" & $index & "]"
      let pcObject = requireObject(pcNode, context)
      validateKnownKeys(pcObject, ["name", "bone", "order", "skinRequired", "channels", "inertia", "strength", "damping", "mass", "gravity", "wind", "physicsMix"], context)
      let pcScalars = decodeJsonScalarsFromObject(
        decodePhysicsConstraintJsonScalars, pcObject, bonyPhysicsConstraintScalarSpecs, context)
      let channelMask = pcScalars.scalarUint("channels", context)
      loadedPhysicsConstraints.add physicsConstraintData(
        scalarString(pcScalars, "name", context),
        scalarString(pcScalars, "bone", context),
        physicsChannelsFromMask(channelMask, context & ".channels"),
        order = scalarInt(pcScalars, "order", context),
        skinRequired = scalarBool(pcScalars, "skinRequired", context),
        hasInertia = pcObject.hasKey("inertia"),
        inertia =
          if pcObject.hasKey("inertia"): scalarFloat(pcScalars, "inertia", context)
          else: defaultFloat(physicsConstraintTypeId, "inertia"),
        hasStrength = pcObject.hasKey("strength"),
        strength =
          if pcObject.hasKey("strength"): scalarFloat(pcScalars, "strength", context)
          else: defaultFloat(physicsConstraintTypeId, "strength"),
        hasDamping = pcObject.hasKey("damping"),
        damping =
          if pcObject.hasKey("damping"): scalarFloat(pcScalars, "damping", context)
          else: defaultFloat(physicsConstraintTypeId, "damping"),
        hasMass = pcObject.hasKey("mass"),
        mass =
          if pcObject.hasKey("mass"): scalarFloat(pcScalars, "mass", context)
          else: defaultFloat(physicsConstraintTypeId, "mass"),
        hasGravity = pcObject.hasKey("gravity"),
        gravity =
          if pcObject.hasKey("gravity"): scalarFloat(pcScalars, "gravity", context)
          else: defaultFloat(physicsConstraintTypeId, "gravity"),
        hasWind = pcObject.hasKey("wind"),
        wind =
          if pcObject.hasKey("wind"): scalarFloat(pcScalars, "wind", context)
          else: defaultFloat(physicsConstraintTypeId, "wind"),
        hasMix = pcObject.hasKey("physicsMix"),
        mix =
          if pcObject.hasKey("physicsMix"): scalarFloat(pcScalars, "physicsMix", context)
          else: defaultFloat(physicsConstraintTypeId, "physicsMix"),
      )

  var loadedSkins: seq[SkinData] = @[]
  if root.hasKey("skins"):
    let skinsNode = requireArray(root["skins"], "skins")
    for skinIndex, skinNode in skinsNode.elems:
      let context = "skins[" & $skinIndex & "]"
      let skinObject = requireObject(skinNode, context)
      validateKnownKeys(skinObject, ["name", "entries", "bones", "ikConstraints", "transformConstraints", "pathConstraints", "physicsConstraints"], context)
      let skinScalars = decodeJsonScalarsFromObject(
        decodeSkinJsonScalars, skinObject, bonySkinScalarSpecs, context)
      var entries: seq[SkinEntryData] = @[]
      if skinObject.hasKey("entries"):
        let entriesNode = requireArray(skinObject["entries"], context & ".entries")
        for entryIndex, entryNode in entriesNode.elems:
          let entryContext = context & ".entries[" & $entryIndex & "]"
          let entryObject = requireObject(entryNode, entryContext)
          validateKnownKeys(entryObject, ["slot", "attachment", "target"], entryContext)
          let entryScalars = decodeJsonScalarsFromObject(
            decodeSkinEntryJsonScalars,
            entryObject,
            bonySkinEntryScalarSpecs,
            entryContext,
            [
              jsonScalarAlias("attachment", "skinAttachment"),
              jsonScalarAlias("target", "skinTarget"),
            ],
          )
          entries.add skinEntryData(
            scalarString(entryScalars, "slot", entryContext),
            scalarString(entryScalars, "skinAttachment", entryContext),
            scalarString(entryScalars, "skinTarget", entryContext),
          )
      loadedSkins.add skinData(
        scalarString(skinScalars, "name", context),
        entries,
        bones = optionalStringArray(skinObject, "bones", context),
        ikConstraints = optionalStringArray(skinObject, "ikConstraints", context),
        transformConstraints = optionalStringArray(skinObject, "transformConstraints", context),
        pathConstraints = optionalStringArray(skinObject, "pathConstraints", context),
        physicsConstraints = optionalStringArray(skinObject, "physicsConstraints", context),
      )

  var loadedParameters: seq[ParameterAxis] = @[]
  if root.hasKey("parameters"):
    let parametersNode = requireArray(root["parameters"], "parameters")
    for index, paramNode in parametersNode.elems:
      let context = "parameters[" & $index & "]"
      let paramObject = requireObject(paramNode, context)
      validateKnownKeys(paramObject, ["name", "min", "max", "default"], context)
      let paramScalars = decodeJsonScalarsFromObject(
        decodeParameterJsonScalars,
        paramObject,
        bonyParameterScalarSpecs,
        context,
        [
          jsonScalarAlias("min", "parameterMin"),
          jsonScalarAlias("max", "parameterMax"),
          jsonScalarAlias("default", "parameterDefault"),
        ],
      )
      loadedParameters.add ParameterAxis(
        name: scalarString(paramScalars, "name", context),
        minValue: scalarFloat(paramScalars, "parameterMin", context),
        maxValue: scalarFloat(paramScalars, "parameterMax", context),
        defaultValue: scalarFloat(paramScalars, "parameterDefault", context),
      )

  var loadedDeformers: seq[DeformerRecord] = @[]
  if root.hasKey("deformers"):
    var paramsByName = initTable[string, ParameterAxis]()
    for param in loadedParameters:
      paramsByName[param.name] = param

    let deformersNode = requireArray(root["deformers"], "deformers")
    for index, defNode in deformersNode.elems:
      let context = "deformers[" & $index & "]"
      let defObject = requireObject(defNode, context)
      validateKnownKeys(defObject, ["id", "parent", "order", "kind", "warp", "rotation", "keyformBlend"], context)

      let defScalars = decodeJsonScalarsFromObject(
        decodeDeformerJsonScalars,
        defObject,
        bonyDeformerScalarSpecs,
        context,
        [
          jsonScalarAlias("id", "deformerId"),
          jsonScalarAlias("order", "deformerOrder"),
          jsonScalarAlias("kind", "deformerKind"),
        ],
      )
      let defId = scalarString(defScalars, "deformerId", context)
      let defParent = scalarString(defScalars, "parent", context)
      let defOrder = uint32(scalarUint(defScalars, "deformerOrder", context))
      let defKind = scalarString(defScalars, "deformerKind", context)

      var deformer: Deformer
      if defKind == "warp":
        if not defObject.hasKey("warp"):
          raise newBonyLoadError(schemaViolation, context & ".warp is required for kind=warp")
        let warpObject = requireObject(defObject["warp"], context & ".warp")
        validateKnownKeys(warpObject, ["rows", "cols", "minX", "minY", "maxX", "maxY", "controlPoints"], context & ".warp")
        let warpScalars = decodeJsonScalarsFromObject(
          decodeWarpLatticeJsonScalars,
          warpObject,
          bonyWarpLatticeScalarSpecs,
          context & ".warp",
          [
            jsonScalarAlias("rows", "warpRows"),
            jsonScalarAlias("cols", "warpCols"),
            jsonScalarAlias("minX", "warpMinX"),
            jsonScalarAlias("minY", "warpMinY"),
            jsonScalarAlias("maxX", "warpMaxX"),
            jsonScalarAlias("maxY", "warpMaxY"),
          ],
        )
        if not warpObject.hasKey("controlPoints"):
          raise newBonyLoadError(schemaViolation, context & ".warp.controlPoints is required")
        let cpArrayNode = requireArray(warpObject["controlPoints"], context & ".warp.controlPoints")
        var controlPoints: seq[DeformerPoint]
        for cpIndex, cpNode in cpArrayNode.elems:
          let cpContext = context & ".warp.controlPoints[" & $cpIndex & "]"
          let cpObject = requireObject(cpNode, cpContext)
          validateKnownKeys(cpObject, ["x", "y"], cpContext)
          controlPoints.add DeformerPoint(
            x: requiredFloat(cpObject, "x", cpContext),
            y: requiredFloat(cpObject, "y", cpContext),
          )
        let lattice = WarpLattice(
          rows: uint32(scalarUint(warpScalars, "warpRows", context & ".warp")),
          cols: uint32(scalarUint(warpScalars, "warpCols", context & ".warp")),
          minX: scalarFloat(warpScalars, "warpMinX", context & ".warp"),
          minY: scalarFloat(warpScalars, "warpMinY", context & ".warp"),
          maxX: scalarFloat(warpScalars, "warpMaxX", context & ".warp"),
          maxY: scalarFloat(warpScalars, "warpMaxY", context & ".warp"),
          controlPoints: controlPoints,
        )
        validateWarpLattice(lattice)
        deformer = Deformer(id: defId, parent: defParent, order: defOrder, kind: warpDeformerKind, warp: lattice)
      elif defKind == "rotation":
        if not defObject.hasKey("rotation"):
          raise newBonyLoadError(schemaViolation, context & ".rotation is required for kind=rotation")
        let rotObject = requireObject(defObject["rotation"], context & ".rotation")
        validateKnownKeys(rotObject, ["pivotX", "pivotY", "angleDegrees", "scaleX", "scaleY", "opacity"], context & ".rotation")
        let rotScalars = decodeJsonScalarsFromObject(
          decodeRotationDeformerJsonScalars,
          rotObject,
          bonyRotationDeformerScalarSpecs,
          context & ".rotation",
          [
            jsonScalarAlias("pivotX", "rotationPivotX"),
            jsonScalarAlias("pivotY", "rotationPivotY"),
            jsonScalarAlias("angleDegrees", "rotationAngleDegrees"),
            jsonScalarAlias("scaleX", "rotationScaleX"),
            jsonScalarAlias("scaleY", "rotationScaleY"),
            jsonScalarAlias("opacity", "rotationOpacity"),
          ],
        )
        let rotation = RotationDeformer(
          pivotX: scalarFloat(rotScalars, "rotationPivotX", context & ".rotation"),
          pivotY: scalarFloat(rotScalars, "rotationPivotY", context & ".rotation"),
          angleDegrees: scalarFloat(rotScalars, "rotationAngleDegrees", context & ".rotation"),
          scaleX: scalarFloat(rotScalars, "rotationScaleX", context & ".rotation"),
          scaleY: scalarFloat(rotScalars, "rotationScaleY", context & ".rotation"),
          opacity: scalarFloat(rotScalars, "rotationOpacity", context & ".rotation"),
        )
        validateRotationDeformer(rotation)
        deformer = Deformer(id: defId, parent: defParent, order: defOrder, kind: rotationDeformerKind, rotation: rotation)
      else:
        raise newBonyLoadError(schemaViolation, context & ".kind must be 'warp' or 'rotation'")

      var blend = KeyformBlend()
      if defObject.hasKey("keyformBlend"):
        let blendObject = requireObject(defObject["keyformBlend"], context & ".keyformBlend")
        validateKnownKeys(blendObject, ["axes", "keyforms"], context & ".keyformBlend")
        if not blendObject.hasKey("axes"):
          raise newBonyLoadError(schemaViolation, context & ".keyformBlend.axes is required")
        if not blendObject.hasKey("keyforms"):
          raise newBonyLoadError(schemaViolation, context & ".keyformBlend.keyforms is required")
        let axesNode = requireArray(blendObject["axes"], context & ".keyformBlend.axes")
        var blendAxes: seq[ParameterAxis]
        for axisIndex, axisNameNode in axesNode.elems:
          let axisCtx = context & ".keyformBlend.axes[" & $axisIndex & "]"
          if axisNameNode.kind != JString:
            raise newBonyLoadError(schemaViolation, axisCtx & " must be a string")
          let axisName = axisNameNode.getStr()
          if axisName notin paramsByName:
            raise newBonyLoadError(unknownRequiredReference, "unknown parameter '" & axisName & "' in " & axisCtx)
          blendAxes.add paramsByName[axisName]
        let keyformsNode = requireArray(blendObject["keyforms"], context & ".keyformBlend.keyforms")
        var blendKeyforms: seq[Keyform]
        for kfIndex, kfNode in keyformsNode.elems:
          let kfContext = context & ".keyformBlend.keyforms[" & $kfIndex & "]"
          let kfObject = requireObject(kfNode, kfContext)
          validateKnownKeys(kfObject, ["coordinates", "values"], kfContext)
          if not kfObject.hasKey("coordinates"):
            raise newBonyLoadError(schemaViolation, kfContext & ".coordinates is required")
          if not kfObject.hasKey("values"):
            raise newBonyLoadError(schemaViolation, kfContext & ".values is required")
          let coordsNode = requireObject(kfObject["coordinates"], kfContext & ".coordinates")
          var coordinates: seq[ParameterSample]
          for axis in blendAxes:
            if not coordsNode.hasKey(axis.name):
              raise newBonyLoadError(schemaViolation, kfContext & ".coordinates missing axis: " & axis.name)
            let coordVal = coordsNode[axis.name]
            if coordVal.kind notin {JInt, JFloat}:
              raise newBonyLoadError(schemaViolation, kfContext & ".coordinates." & axis.name & " must be numeric")
            coordinates.add ParameterSample(
              name: axis.name,
              value: quantizeF32(coordVal.getFloat(), kfContext & ".coordinates." & axis.name),
            )
          let valuesNode = requireArray(kfObject["values"], kfContext & ".values")
          var kfValues: seq[float64]
          for valIndex, valNode in valuesNode.elems:
            if valNode.kind notin {JInt, JFloat}:
              raise newBonyLoadError(schemaViolation, kfContext & ".values[" & $valIndex & "] must be numeric")
            kfValues.add quantizeF32(valNode.getFloat(), kfContext & ".values[" & $valIndex & "]")
          blendKeyforms.add Keyform(coordinates: coordinates, values: kfValues)
        blend = keyformBlend(blendAxes, blendKeyforms)

      loadedDeformers.add DeformerRecord(deformer: deformer, keyformBlend: blend)

  result = skeletonData(
    loadedHeader, loadedBones, loadedSlots, loadedRegions, loadedPathAttachments, loadedPaths,
    loadedParameters, loadedDeformers, loadedIkConstraints, loadedTransformConstraints,
    loadedPhysicsConstraints, loadedClippingAttachments, loadedMeshAttachments, loadedSkins,
    loadedPointAttachments, loadedBoundingBoxAttachments, loadedNestedRigAttachments,
  )
  let loadedAnimClips = parseBonyAnimations(root, result)
  discard parseBonyStateMachines(root, result, loadedAnimClips)


include jsonio/decode


proc loadBonyJsonAnimations*(text: string): Table[string, AnimationClip] =
  let data = loadBonyJson(text)
  let root = requireObject(parseJson(text), "root")
  parseBonyAnimations(root, data)


proc loadBonyJsonStateMachines*(text: string): seq[StateMachine] =
  let data = loadBonyJson(text)
  let root = requireObject(parseJson(text), "root")
  let clips = parseBonyAnimations(root, data)
  parseBonyStateMachines(root, data, clips)


proc loadBonyJsonAsset*(text: string): BonyAsset =
  let data = loadBonyJson(text)
  let root = requireObject(parseJson(text), "root")
  let clips = parseBonyAnimations(root, data)
  var orderedClips: seq[AnimationClip] = @[]
  if root.hasKey("animations"):
    for animNode in requireArray(root["animations"], "animations").elems:
      let animName = requiredString(requireObject(animNode, "animations[]"), "name", "animations[]")
      orderedClips.add clips[animName]
  bonyAsset(data, orderedClips, parseBonyStateMachines(root, data, clips))


include jsonio/encode


proc orderedSkins(data: SkeletonData): seq[SkinData] =
  for skin in data.skins:
    if skin.name == "default":
      result.add skin
      break
  for skin in data.skins:
    if skin.name != "default":
      result.add skin


proc sortedSkinEntries(data: SkeletonData; skin: SkinData): seq[SkinEntryData] =
  result = skin.entries
  var slotOrder = initTable[string, int]()
  for index, slot in data.slots:
    slotOrder[slot.name] = index
  result.sort(proc(a, b: SkinEntryData): int =
    result = cmp(slotOrder.getOrDefault(a.slot, high(int)), slotOrder.getOrDefault(b.slot, high(int)))
    if result == 0:
      result = cmp(a.attachment, b.attachment)
  )


proc orderedMembership(refs: openArray[string]; orderedNames: openArray[string]): seq[string] =
  var refSet = initHashSet[string]()
  for item in refs:
    refSet.incl(item)
  for name in orderedNames:
    if name in refSet:
      result.add name


proc addStringArrayField(output: var string; key: string; values: openArray[string]; indent: int; first: var bool) =
  if values.len == 0:
    return
  output.addFieldPrefix(key, indent, first)
  output.add "["
  for index, value in values:
    if index > 0:
      output.add ", "
    output.addJsonString(value)
  output.add "]"


proc appendSkinsJson(result: var string; data: SkeletonData; indent = 1) =
  result.addIndent(indent)
  result.add "\"skins\": ["
  if data.skins.len > 0:
    result.add "\n"
    let skins = orderedSkins(data)
    for skinIndex, skin in skins:
      if skinIndex > 0:
        result.add ",\n"
      result.addIndent(indent + 1)
      result.add "{\n"
      var first = true
      let skinScalars = encodeSkinJsonScalars([
        jsonScalarString("name", skin.name),
      ])
      result.addJsonScalarField(skinScalars, "name", indent + 2, first)
      result.addStringArrayField("bones", orderedMembership(skin.bones, data.bones.mapIt(it.name)), indent + 2, first)
      result.addStringArrayField(
        "ikConstraints",
        orderedMembership(skin.ikConstraints, data.ikConstraints.mapIt(it.name)),
        indent + 2,
        first,
      )
      result.addStringArrayField(
        "transformConstraints",
        orderedMembership(skin.transformConstraints, data.transformConstraints.mapIt(it.name)),
        indent + 2,
        first,
      )
      result.addStringArrayField(
        "pathConstraints",
        orderedMembership(skin.pathConstraints, data.paths.mapIt(it.name)),
        indent + 2,
        first,
      )
      result.addStringArrayField(
        "physicsConstraints",
        orderedMembership(skin.physicsConstraints, data.physicsConstraints.mapIt(it.name)),
        indent + 2,
        first,
      )
      let entries = sortedSkinEntries(data, skin)
      if entries.len > 0:
        result.addFieldPrefix("entries", indent + 2, first)
        result.add "[\n"
        for entryIndex, entry in entries:
          if entryIndex > 0:
            result.add ",\n"
          result.addIndent(indent + 3)
          result.add "{\n"
          var entryFirst = true
          let entryScalars = encodeSkinEntryJsonScalars([
            jsonScalarString("slot", entry.slot),
            jsonScalarString("skinAttachment", entry.attachment),
            jsonScalarString("skinTarget", entry.target),
          ])
          result.addJsonScalarField(entryScalars, "slot", indent + 4, entryFirst)
          result.addJsonScalarField(entryScalars, "skinAttachment", "attachment", indent + 4, entryFirst)
          result.addJsonScalarField(entryScalars, "skinTarget", "target", indent + 4, entryFirst)
          result.add "\n"
          result.addIndent(indent + 3)
          result.add "}"
        result.add "\n"
        result.addIndent(indent + 2)
        result.add "]"
      result.add "\n"
      result.addIndent(indent + 1)
      result.add "}"
    result.add "\n"
    result.addIndent(indent)
  result.add "]"


proc toBonyJson*(data: SkeletonData): string =
  validateSkeletonData(data)
  result.add "{\n"

  result.addIndent(1)
  result.add "\"skeleton\": {\n"
  var first = true
  let skeletonScalars = encodeSkeletonJsonScalars([
    jsonScalarString("name", data.header.name),
    jsonScalarString("version", data.header.version),
  ])
  result.addJsonScalarField(skeletonScalars, "name", 2, first)
  result.addJsonScalarField(skeletonScalars, "version", 2, first)
  result.add "\n"
  result.addIndent(1)
  result.add "},\n"

  result.addIndent(1)
  result.add "\"bones\": ["
  if data.bones.len > 0:
    result.add "\n"
    for index, bone in data.bones:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      let local = bone.local
      first = true
      let boneScalars = encodeBoneJsonScalars([
        jsonScalarString("name", bone.name),
        jsonScalarString("parent", bone.parent),
        jsonScalarFloat("x", local.x),
        jsonScalarFloat("y", local.y),
        jsonScalarFloat("rotation", local.rotation),
        jsonScalarFloat("scaleX", local.scaleX),
        jsonScalarFloat("scaleY", local.scaleY),
        jsonScalarFloat("shearX", local.shearX),
        jsonScalarFloat("shearY", local.shearY),
        jsonScalarBool("inheritRotation", local.inheritRotation),
        jsonScalarBool("inheritScale", local.inheritScale),
        jsonScalarBool("inheritReflection", local.inheritReflection),
        jsonScalarString("transformMode", transformModeName(local.transformMode)),
        jsonScalarBool("skinRequired", bone.skinRequired),
      ])
      result.addJsonScalarField(boneScalars, "name", 3, first)
      result.addJsonScalarField(boneScalars, "parent", 3, first)
      result.addJsonScalarField(boneScalars, "x", 3, first)
      result.addJsonScalarField(boneScalars, "y", 3, first)
      result.addJsonScalarField(boneScalars, "rotation", 3, first)
      result.addJsonScalarField(boneScalars, "scaleX", 3, first)
      result.addJsonScalarField(boneScalars, "scaleY", 3, first)
      result.addJsonScalarField(boneScalars, "shearX", 3, first)
      result.addJsonScalarField(boneScalars, "shearY", 3, first)
      result.addJsonScalarField(boneScalars, "inheritRotation", 3, first)
      result.addJsonScalarField(boneScalars, "inheritScale", 3, first)
      result.addJsonScalarField(boneScalars, "inheritReflection", 3, first)
      result.addJsonScalarField(boneScalars, "transformMode", 3, first)
      result.addJsonScalarField(boneScalars, "skinRequired", 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
  result.add "],\n"

  result.addIndent(1)
  result.add "\"slots\": ["
  if data.slots.len > 0:
    result.add "\n"
    for index, slot in data.slots:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let slotScalars = encodeSlotJsonScalars([
        jsonScalarString("name", slot.name),
        jsonScalarString("bone", slot.bone),
        jsonScalarString("attachment", slot.attachment),
      ])
      result.addJsonScalarField(slotScalars, "name", 3, first)
      result.addJsonScalarField(slotScalars, "bone", 3, first)
      result.addJsonScalarField(slotScalars, "attachment", 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
  result.add "],\n"

  result.addIndent(1)
  result.add "\"regions\": ["
  if data.regions.len > 0:
    result.add "\n"
    for index, region in data.regions:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let regionScalars = encodeRegionJsonScalars([
        jsonScalarString("name", region.name),
        jsonScalarFloat("width", region.width),
        jsonScalarFloat("height", region.height),
        jsonScalarString("texturePage", region.texturePage),
        jsonScalarFloat("u0", region.u0),
        jsonScalarFloat("v0", region.v0),
        jsonScalarFloat("u1", region.u1),
        jsonScalarFloat("v1", region.v1),
        jsonScalarString("alphaMode", region.alphaMode),
      ])
      result.addJsonScalarField(regionScalars, "name", 3, first)
      result.addJsonScalarField(regionScalars, "width", 3, first)
      result.addJsonScalarField(regionScalars, "height", 3, first)
      result.addJsonScalarField(regionScalars, "texturePage", 3, first)
      result.addJsonScalarField(regionScalars, "u0", 3, first)
      result.addJsonScalarField(regionScalars, "v0", 3, first)
      result.addJsonScalarField(regionScalars, "u1", 3, first)
      result.addJsonScalarField(regionScalars, "v1", 3, first)
      result.addJsonScalarField(regionScalars, "alphaMode", 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
  result.add "]"

  if data.pointAttachments.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"pointAttachments\": [\n"
    for index, point in data.pointAttachments:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let pointScalars = encodePointAttachmentJsonScalars([
        jsonScalarString("name", point.name),
        jsonScalarFloat("x", point.x),
        jsonScalarFloat("y", point.y),
        jsonScalarFloat("rotation", point.rotation),
      ])
      result.addJsonScalarField(pointScalars, "name", 3, first)
      result.addJsonScalarField(pointScalars, "x", 3, first)
      result.addJsonScalarField(pointScalars, "y", 3, first)
      result.addJsonScalarField(pointScalars, "rotation", 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.boundingBoxAttachments.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"boundingBoxAttachments\": [\n"
    for index, box in data.boundingBoxAttachments:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let boxScalars = encodeBoundingBoxAttachmentJsonScalars([
        jsonScalarString("name", box.name),
      ])
      result.addJsonScalarField(boxScalars, "name", 3, first)
      result.addFieldPrefix("vertices", 3, first)
      result.add "["
      for vertexIndex, vertexValue in box.vertices:
        if vertexIndex > 0:
          result.add ", "
        result.add canonicalNumber(vertexValue)
      result.add "]"
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.nestedRigAttachments.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"nestedRigAttachments\": [\n"
    for index, nested in data.nestedRigAttachments:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let nestedScalars = encodeNestedRigAttachmentJsonScalars([
        jsonScalarString("name", nested.name),
        jsonScalarString("nestedSkeleton", nested.skeleton),
        jsonScalarString("nestedSkin", nested.skin),
        jsonScalarString("nestedAnimation", nested.animation),
      ])
      result.addJsonScalarField(nestedScalars, "name", 3, first)
      result.addJsonScalarField(nestedScalars, "nestedSkeleton", "skeleton", 3, first)
      result.addJsonScalarField(nestedScalars, "nestedSkin", "skin", 3, first)
      result.addJsonScalarField(nestedScalars, "nestedAnimation", "animation", 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.paths.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"paths\": [\n"
    for index, path in data.paths:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let pathScalars = encodePathJsonScalars([
        jsonScalarString("name", path.name),
        jsonScalarString("bone", path.bone),
        jsonScalarString("target", path.target),
        jsonScalarString("path", path.path),
        jsonScalarInt("order", path.order),
        jsonScalarBool("skinRequired", path.skinRequired),
      ])
      result.addJsonScalarField(pathScalars, "name", 3, first)
      result.addJsonScalarField(pathScalars, "bone", 3, first)
      result.addJsonScalarField(pathScalars, "target", 3, first)
      result.addJsonScalarField(pathScalars, "path", 3, first)
      result.addJsonScalarField(pathScalars, "order", 3, first)
      result.addJsonScalarField(pathScalars, "skinRequired", 3, first)
      if path.hasPosition:
        result.addNumberField("position", path.position, 3, first)
      if path.hasTranslateMix:
        result.addNumberField("translateMix", path.translateMix, 3, first)
      if path.hasRotateMix:
        result.addNumberField("rotateMix", path.rotateMix, 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.ikConstraints.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"ikConstraints\": [\n"
    for index, ik in data.ikConstraints:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let ikScalars = encodeIkConstraintJsonScalars([
        jsonScalarString("name", ik.name),
        jsonScalarString("target", ik.target),
        jsonScalarInt("order", ik.order),
        jsonScalarBool("skinRequired", ik.skinRequired),
      ])
      result.addJsonScalarField(ikScalars, "name", 3, first)
      result.addFieldPrefix("bones", 3, first)
      result.add "["
      for boneIndex, boneName in ik.bones:
        if boneIndex > 0:
          result.add ", "
        result.addJsonString(boneName)
      result.add "]"
      result.addJsonScalarField(ikScalars, "target", 3, first)
      result.addJsonScalarField(ikScalars, "order", 3, first)
      result.addJsonScalarField(ikScalars, "skinRequired", 3, first)
      if ik.hasMix:
        result.addNumberField("mix", ik.mix, 3, first)
      if ik.hasBendPositive:
        result.addBoolField("bendPositive", ik.bendPositive, 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.transformConstraints.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"transformConstraints\": [\n"
    for index, tc in data.transformConstraints:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let tcScalars = encodeTransformConstraintJsonScalars([
        jsonScalarString("name", tc.name),
        jsonScalarString("bone", tc.bone),
        jsonScalarString("target", tc.target),
        jsonScalarInt("order", tc.order),
        jsonScalarBool("skinRequired", tc.skinRequired),
      ])
      result.addJsonScalarField(tcScalars, "name", 3, first)
      result.addJsonScalarField(tcScalars, "bone", 3, first)
      result.addJsonScalarField(tcScalars, "target", 3, first)
      result.addJsonScalarField(tcScalars, "order", 3, first)
      result.addJsonScalarField(tcScalars, "skinRequired", 3, first)
      if tc.hasTranslateMix:
        result.addNumberField("translateMix", tc.translateMix, 3, first)
      if tc.hasRotateMix:
        result.addNumberField("rotateMix", tc.rotateMix, 3, first)
      if tc.hasScaleMix:
        result.addNumberField("scaleMix", tc.scaleMix, 3, first)
      if tc.hasShearMix:
        result.addNumberField("shearMix", tc.shearMix, 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.physicsConstraints.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"physicsConstraints\": [\n"
    for index, pc in data.physicsConstraints:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let pcScalars = encodePhysicsConstraintJsonScalars([
        jsonScalarString("name", pc.name),
        jsonScalarString("bone", pc.bone),
        jsonScalarInt("order", pc.order),
        jsonScalarBool("skinRequired", pc.skinRequired),
        jsonScalarUint("channels", physicsChannelsToMask(pc.channels)),
      ])
      result.addJsonScalarField(pcScalars, "name", 3, first)
      result.addJsonScalarField(pcScalars, "bone", 3, first)
      result.addJsonScalarField(pcScalars, "order", 3, first)
      result.addJsonScalarField(pcScalars, "skinRequired", 3, first)
      result.addJsonScalarField(pcScalars, "channels", 3, first)
      if pc.hasInertia:
        result.addNumberField("inertia", pc.inertia, 3, first)
      if pc.hasStrength:
        result.addNumberField("strength", pc.strength, 3, first)
      if pc.hasDamping:
        result.addNumberField("damping", pc.damping, 3, first)
      if pc.hasMass:
        result.addNumberField("mass", pc.mass, 3, first)
      if pc.hasGravity:
        result.addNumberField("gravity", pc.gravity, 3, first)
      if pc.hasWind:
        result.addNumberField("wind", pc.wind, 3, first)
      if pc.hasMix:
        result.addNumberField("physicsMix", pc.mix, 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.pathAttachments.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"pathAttachments\": [\n"
    for index, pathAttachment in data.pathAttachments:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let pathAttachmentScalars = encodePathAttachmentJsonScalars([
        jsonScalarString("name", pathAttachment.name),
        jsonScalarF64("p0x", pathAttachment.p0x),
        jsonScalarF64("p0y", pathAttachment.p0y),
        jsonScalarF64("p1x", pathAttachment.p1x),
        jsonScalarF64("p1y", pathAttachment.p1y),
        jsonScalarF64("p2x", pathAttachment.p2x),
        jsonScalarF64("p2y", pathAttachment.p2y),
        jsonScalarF64("p3x", pathAttachment.p3x),
        jsonScalarF64("p3y", pathAttachment.p3y),
      ])
      result.addJsonScalarField(pathAttachmentScalars, "name", 3, first)
      result.addJsonScalarField(pathAttachmentScalars, "p0x", 3, first)
      result.addJsonScalarField(pathAttachmentScalars, "p0y", 3, first)
      result.addJsonScalarField(pathAttachmentScalars, "p1x", 3, first)
      result.addJsonScalarField(pathAttachmentScalars, "p1y", 3, first)
      result.addJsonScalarField(pathAttachmentScalars, "p2x", 3, first)
      result.addJsonScalarField(pathAttachmentScalars, "p2y", 3, first)
      result.addJsonScalarField(pathAttachmentScalars, "p3x", 3, first)
      result.addJsonScalarField(pathAttachmentScalars, "p3y", 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.clippingAttachments.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"clippingAttachments\": [\n"
    for index, clip in data.clippingAttachments:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let clipScalars = encodeClippingAttachmentJsonScalars([
        jsonScalarString("name", clip.name),
        jsonScalarString("untilSlot", clip.untilSlot),
      ])
      result.addJsonScalarField(clipScalars, "name", 3, first)
      result.addFieldPrefix("vertices", 3, first)
      result.add "["
      for vertexIndex, vertexValue in clip.vertices:
        if vertexIndex > 0:
          result.add ", "
        result.add canonicalNumber(vertexValue)
      result.add "]"
      result.addJsonScalarField(clipScalars, "untilSlot", 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.meshAttachments.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"meshAttachments\": [\n"
    for index, mesh in data.meshAttachments:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let meshScalars = encodeMeshAttachmentJsonScalars([
        jsonScalarString("name", mesh.name),
        jsonScalarBool("meshWeighted", mesh.weighted),
      ])
      result.addJsonScalarField(meshScalars, "name", 3, first)
      result.addJsonScalarField(meshScalars, "meshWeighted", "weighted", 3, first)
      # vertices: one {x,y} or {influences:[...]} object per vertex.
      result.addFieldPrefix("vertices", 3, first)
      result.add "[\n"
      for vertexIndex, vertex in mesh.vertices:
        if vertexIndex > 0:
          result.add ",\n"
        result.addIndent(4)
        if vertex.weighted:
          result.add "{\"influences\": ["
          for infIndex, influence in vertex.influences:
            if infIndex > 0:
              result.add ", "
            result.add "{\"bone\": "
            result.addJsonString(influence.bone)
            result.add ", \"bindX\": " & canonicalNumber(influence.bindX)
            result.add ", \"bindY\": " & canonicalNumber(influence.bindY)
            result.add ", \"weight\": " & canonicalNumber(influence.weight)
            result.add "}"
          result.add "]}"
        else:
          result.add "{\"x\": " & canonicalNumber(vertex.x)
          result.add ", \"y\": " & canonicalNumber(vertex.y) & "}"
      result.add "\n"
      result.addIndent(3)
      result.add "]"
      # uvs: flat [u0, v0, ...] pairs.
      result.addFieldPrefix("uvs", 3, first)
      result.add "["
      for uvIndex, uv in mesh.uvs:
        if uvIndex > 0:
          result.add ", "
        result.add canonicalNumber(uv.u) & ", " & canonicalNumber(uv.v)
      result.add "]"
      # triangles: flat vertex-index list.
      result.addFieldPrefix("triangles", 3, first)
      result.add "["
      for triIndex, triangle in mesh.triangles:
        if triIndex > 0:
          result.add ", "
        result.add $triangle
      result.add "]"
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.skins.len > 0:
    result.add ",\n"
    result.appendSkinsJson(data)

  if data.parameters.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"parameters\": [\n"
    for index, param in data.parameters:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let paramScalars = encodeParameterJsonScalars([
        jsonScalarString("name", param.name),
        jsonScalarFloat("parameterMin", param.minValue),
        jsonScalarFloat("parameterMax", param.maxValue),
        jsonScalarFloat("parameterDefault", param.defaultValue),
      ])
      result.addJsonScalarField(paramScalars, "name", 3, first)
      result.addJsonScalarField(paramScalars, "parameterMin", "min", 3, first)
      result.addJsonScalarField(paramScalars, "parameterMax", "max", 3, first)
      result.addJsonScalarField(paramScalars, "parameterDefault", "default", 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  if data.deformers.len > 0:
    result.add ",\n"
    result.addIndent(1)
    result.add "\"deformers\": [\n"
    for index, rec in data.deformers:
      if index > 0:
        result.add ",\n"
      result.addIndent(2)
      result.add "{\n"
      first = true
      let deformerKind =
        case rec.deformer.kind
        of warpDeformerKind: "warp"
        of rotationDeformerKind: "rotation"
      let deformerScalars = encodeDeformerJsonScalars([
        jsonScalarString("deformerId", rec.deformer.id),
        jsonScalarString("parent", rec.deformer.parent),
        jsonScalarUint("deformerOrder", uint64(rec.deformer.order)),
        jsonScalarString("deformerKind", deformerKind),
      ])
      result.addJsonScalarField(deformerScalars, "deformerId", "id", 3, first)
      result.addJsonScalarField(deformerScalars, "parent", 3, first)
      result.addIntField("order", int(rec.deformer.order), 3, first)
      case rec.deformer.kind
      of warpDeformerKind:
        result.addJsonScalarField(deformerScalars, "deformerKind", "kind", 3, first)
        result.addFieldPrefix("warp", 3, first)
        result.add "{\n"
        var wfirst = true
        let warp = rec.deformer.warp
        let warpScalars = encodeWarpLatticeJsonScalars([
          jsonScalarUint("warpRows", uint64(warp.rows)),
          jsonScalarUint("warpCols", uint64(warp.cols)),
          jsonScalarFloat("warpMinX", warp.minX),
          jsonScalarFloat("warpMinY", warp.minY),
          jsonScalarFloat("warpMaxX", warp.maxX),
          jsonScalarFloat("warpMaxY", warp.maxY),
        ])
        result.addIntField("rows", int(warp.rows), 4, wfirst)
        result.addIntField("cols", int(warp.cols), 4, wfirst)
        result.addJsonScalarField(warpScalars, "warpMinX", "minX", 4, wfirst)
        result.addJsonScalarField(warpScalars, "warpMinY", "minY", 4, wfirst)
        result.addJsonScalarField(warpScalars, "warpMaxX", "maxX", 4, wfirst)
        result.addJsonScalarField(warpScalars, "warpMaxY", "maxY", 4, wfirst)
        result.addFieldPrefix("controlPoints", 4, wfirst)
        result.add "["
        for cpIndex, cp in warp.controlPoints:
          if cpIndex > 0:
            result.add ", "
          result.add "{\"x\": "
          result.add canonicalNumber(cp.x)
          result.add ", \"y\": "
          result.add canonicalNumber(cp.y)
          result.add "}"
        result.add "]\n"
        result.addIndent(3)
        result.add "}"
      of rotationDeformerKind:
        result.addJsonScalarField(deformerScalars, "deformerKind", "kind", 3, first)
        result.addFieldPrefix("rotation", 3, first)
        result.add "{\n"
        var rfirst = true
        let rot = rec.deformer.rotation
        let rotScalars = encodeRotationDeformerJsonScalars([
          jsonScalarFloat("rotationPivotX", rot.pivotX),
          jsonScalarFloat("rotationPivotY", rot.pivotY),
          jsonScalarFloat("rotationAngleDegrees", rot.angleDegrees),
          jsonScalarFloat("rotationScaleX", rot.scaleX),
          jsonScalarFloat("rotationScaleY", rot.scaleY),
          jsonScalarFloat("rotationOpacity", rot.opacity),
        ])
        result.addJsonScalarField(rotScalars, "rotationPivotX", "pivotX", 4, rfirst)
        result.addJsonScalarField(rotScalars, "rotationPivotY", "pivotY", 4, rfirst)
        result.addJsonScalarField(rotScalars, "rotationAngleDegrees", "angleDegrees", 4, rfirst)
        result.addJsonScalarField(rotScalars, "rotationScaleX", "scaleX", 4, rfirst)
        result.addJsonScalarField(rotScalars, "rotationScaleY", "scaleY", 4, rfirst)
        result.addJsonScalarField(rotScalars, "rotationOpacity", "opacity", 4, rfirst)
        result.add "\n"
        result.addIndent(3)
        result.add "}"
      if rec.keyformBlend.axes.len > 0 and rec.keyformBlend.keyforms.len > 0:
        result.add ",\n"
        result.addIndent(3)
        result.add "\"keyformBlend\": {\n"
        result.addIndent(4)
        result.add "\"axes\": ["
        for axisIndex, axis in rec.keyformBlend.axes:
          if axisIndex > 0:
            result.add ", "
          result.addJsonString(axis.name)
        result.add "],\n"
        result.addIndent(4)
        result.add "\"keyforms\": [\n"
        for kfIndex, kf in rec.keyformBlend.keyforms:
          if kfIndex > 0:
            result.add ",\n"
          result.addIndent(5)
          result.add "{\n"
          result.addIndent(6)
          result.add "\"coordinates\": {"
          for coordIndex, coord in kf.coordinates:
            if coordIndex > 0:
              result.add ", "
            result.addJsonString(coord.name)
            result.add ": "
            result.add canonicalNumber(coord.value)
          result.add "},\n"
          result.addIndent(6)
          result.add "\"values\": ["
          for valIndex, val in kf.values:
            if valIndex > 0:
              result.add ", "
            result.add canonicalNumber(val)
          result.add "]\n"
          result.addIndent(5)
          result.add "}"
        result.add "\n"
        result.addIndent(4)
        result.add "]\n"
        result.addIndent(3)
        result.add "}"
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  result.add "\n}\n"


proc toBonyJson*(asset: BonyAsset): string =
  result = toBonyJson(asset.skeleton)
  if asset.animations.len == 0 and asset.stateMachines.len == 0:
    return
  if result.endsWith("\n}\n"):
    result.setLen(result.len - 3)
  else:
    raise newBonyLoadError(schemaViolation, "static JSON serializer produced an unexpected suffix")
  if asset.animations.len > 0:
    result.add ",\n"
    result.appendAnimationsJson(asset.animations)
  if asset.stateMachines.len > 0:
    result.add ",\n"
    result.appendStateMachinesJson(asset.stateMachines)
  result.add "\n}\n"
