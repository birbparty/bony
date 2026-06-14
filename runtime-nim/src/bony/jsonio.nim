## M1 .bony JSON loader/serializer.

import std/[json, math, sets, strutils]

import bony/generated/wire
import bony/model

const
  skeletonTypeId = "skeleton"
  boneTypeId = "bone"
  slotTypeId = "slot"
  pathTypeId = "path"


proc defaultFor(objectId, propertyId: string): string =
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


proc rejectDuplicateObjectKeys(text: string) =
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
      raise newBonyLoadError(schemaViolation, context & "." & key & " is not a known M1 field")


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


proc loadBonyJson*(text: string): SkeletonData =
  rejectDuplicateObjectKeys(text)

  let parsed =
    try:
      parseJson(text)
    except JsonParsingError as exc:
      raise newBonyLoadError(schemaViolation, "invalid JSON: " & exc.msg)

  let root = requireObject(parsed, "root")
  validateKnownKeys(root, ["skeleton", "bones", "slots", "regions", "pathAttachments", "paths"], "root")

  if not root.hasKey("skeleton"):
    raise newBonyLoadError(schemaViolation, "root.skeleton is required")
  let skeleton = requireObject(root["skeleton"], "skeleton")
  validateKnownKeys(skeleton, ["name", "version"], "skeleton")

  let loadedHeader = skeletonHeader(
    requiredString(skeleton, "name", "skeleton"),
    optionalString(skeleton, "version", defaultFor(skeletonTypeId, "version"), "skeleton"),
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
      ],
      context,
    )
    let inheritRotation = optionalBool(
      boneObject,
      "inheritRotation",
      defaultBool(boneTypeId, "inheritRotation"),
      context,
    )
    let inheritScale = optionalBool(boneObject, "inheritScale", defaultBool(boneTypeId, "inheritScale"), context)
    let inheritReflection = optionalBool(
      boneObject,
      "inheritReflection",
      defaultBool(boneTypeId, "inheritReflection"),
      context,
    )
    let mode = parseTransformMode(
      optionalString(boneObject, "transformMode", defaultFor(boneTypeId, "transformMode"), context),
      context,
    )
    loadedBones.add boneData(
      requiredString(boneObject, "name", context),
      optionalString(boneObject, "parent", defaultFor(boneTypeId, "parent"), context),
      localTransform(
        x = optionalFloat(boneObject, "x", defaultFloat(boneTypeId, "x"), context),
        y = optionalFloat(boneObject, "y", defaultFloat(boneTypeId, "y"), context),
        rotation = optionalFloat(boneObject, "rotation", defaultFloat(boneTypeId, "rotation"), context),
        scaleX = optionalFloat(boneObject, "scaleX", defaultFloat(boneTypeId, "scaleX"), context),
        scaleY = optionalFloat(boneObject, "scaleY", defaultFloat(boneTypeId, "scaleY"), context),
        shearX = optionalFloat(boneObject, "shearX", defaultFloat(boneTypeId, "shearX"), context),
        shearY = optionalFloat(boneObject, "shearY", defaultFloat(boneTypeId, "shearY"), context),
        inheritRotation = inheritRotation,
        inheritScale = inheritScale,
        inheritReflection = inheritReflection,
        transformMode = mode,
      ),
    )

  var loadedSlots: seq[SlotData] = @[]
  if root.hasKey("slots"):
    let slotsNode = requireArray(root["slots"], "slots")
    for index, slotNode in slotsNode.elems:
      let context = "slots[" & $index & "]"
      let slotObject = requireObject(slotNode, context)
      validateKnownKeys(slotObject, ["name", "bone", "attachment"], context)
      loadedSlots.add slotData(
        requiredString(slotObject, "name", context),
        requiredString(slotObject, "bone", context),
        optionalString(slotObject, "attachment", defaultFor(slotTypeId, "attachment"), context),
      )

  var loadedRegions: seq[RegionAttachment] = @[]
  if root.hasKey("regions"):
    let regionsNode = requireArray(root["regions"], "regions")
    for index, regionNode in regionsNode.elems:
      let context = "regions[" & $index & "]"
      let regionObject = requireObject(regionNode, context)
      validateKnownKeys(regionObject, ["name", "width", "height"], context)
      loadedRegions.add regionAttachment(
        requiredString(regionObject, "name", context),
        requiredFloat(regionObject, "width", context),
        requiredFloat(regionObject, "height", context),
      )

  var loadedPathAttachments: seq[PathAttachmentData] = @[]
  if root.hasKey("pathAttachments"):
    let pathAttachmentsNode = requireArray(root["pathAttachments"], "pathAttachments")
    for index, pathAttachmentNode in pathAttachmentsNode.elems:
      let context = "pathAttachments[" & $index & "]"
      let pathAttachmentObject = requireObject(pathAttachmentNode, context)
      validateKnownKeys(pathAttachmentObject, ["name", "p0x", "p0y", "p1x", "p1y", "p2x", "p2y", "p3x", "p3y"], context)
      loadedPathAttachments.add pathAttachmentData(
        requiredString(pathAttachmentObject, "name", context),
        requiredF64(pathAttachmentObject, "p0x", context),
        requiredF64(pathAttachmentObject, "p0y", context),
        requiredF64(pathAttachmentObject, "p1x", context),
        requiredF64(pathAttachmentObject, "p1y", context),
        requiredF64(pathAttachmentObject, "p2x", context),
        requiredF64(pathAttachmentObject, "p2y", context),
        requiredF64(pathAttachmentObject, "p3x", context),
        requiredF64(pathAttachmentObject, "p3y", context),
      )

  var loadedPaths: seq[PathConstraintData] = @[]
  if root.hasKey("paths"):
    let pathsNode = requireArray(root["paths"], "paths")
    for index, pathNode in pathsNode.elems:
      let context = "paths[" & $index & "]"
      let pathObject = requireObject(pathNode, context)
      validateKnownKeys(pathObject, ["name", "bone", "target", "path", "order"], context)
      loadedPaths.add pathConstraintData(
        requiredString(pathObject, "name", context),
        requiredString(pathObject, "bone", context),
        requiredString(pathObject, "target", context),
        requiredString(pathObject, "path", context),
        optionalInt(pathObject, "order", defaultInt(pathTypeId, "order"), context),
      )

  skeletonData(loadedHeader, loadedBones, loadedSlots, loadedRegions, loadedPathAttachments, loadedPaths)


proc toBonyJson*(data: SkeletonData): string =
  validateSkeletonData(data)
  result.add "{\n"

  result.addIndent(1)
  result.add "\"skeleton\": {\n"
  var first = true
  result.addStringField("name", data.header.name, 2, first)
  if data.header.version != defaultFor(skeletonTypeId, "version"):
    result.addStringField("version", data.header.version, 2, first)
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
      result.addStringField("name", bone.name, 3, first)
      if bone.parent != defaultFor(boneTypeId, "parent"):
        result.addStringField("parent", bone.parent, 3, first)
      if local.x != defaultFloat(boneTypeId, "x"):
        result.addNumberField("x", local.x, 3, first)
      if local.y != defaultFloat(boneTypeId, "y"):
        result.addNumberField("y", local.y, 3, first)
      if local.rotation != defaultFloat(boneTypeId, "rotation"):
        result.addNumberField("rotation", local.rotation, 3, first)
      if local.scaleX != defaultFloat(boneTypeId, "scaleX"):
        result.addNumberField("scaleX", local.scaleX, 3, first)
      if local.scaleY != defaultFloat(boneTypeId, "scaleY"):
        result.addNumberField("scaleY", local.scaleY, 3, first)
      if local.shearX != defaultFloat(boneTypeId, "shearX"):
        result.addNumberField("shearX", local.shearX, 3, first)
      if local.shearY != defaultFloat(boneTypeId, "shearY"):
        result.addNumberField("shearY", local.shearY, 3, first)
      if local.inheritRotation != defaultBool(boneTypeId, "inheritRotation"):
        result.addBoolField("inheritRotation", local.inheritRotation, 3, first)
      if local.inheritScale != defaultBool(boneTypeId, "inheritScale"):
        result.addBoolField("inheritScale", local.inheritScale, 3, first)
      if local.inheritReflection != defaultBool(boneTypeId, "inheritReflection"):
        result.addBoolField("inheritReflection", local.inheritReflection, 3, first)
      if transformModeName(local.transformMode) != defaultFor(boneTypeId, "transformMode"):
        result.addStringField("transformMode", transformModeName(local.transformMode), 3, first)
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
      result.addStringField("name", slot.name, 3, first)
      result.addStringField("bone", slot.bone, 3, first)
      if slot.attachment != defaultFor(slotTypeId, "attachment"):
        result.addStringField("attachment", slot.attachment, 3, first)
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
      result.addStringField("name", region.name, 3, first)
      result.addNumberField("width", region.width, 3, first)
      result.addNumberField("height", region.height, 3, first)
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
      result.addStringField("name", path.name, 3, first)
      result.addStringField("bone", path.bone, 3, first)
      result.addStringField("target", path.target, 3, first)
      result.addStringField("path", path.path, 3, first)
      if path.order != defaultInt(pathTypeId, "order"):
        result.addIntField("order", path.order, 3, first)
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
      result.addStringField("name", pathAttachment.name, 3, first)
      result.addNumberField("p0x", pathAttachment.p0x, 3, first)
      result.addNumberField("p0y", pathAttachment.p0y, 3, first)
      result.addNumberField("p1x", pathAttachment.p1x, 3, first)
      result.addNumberField("p1y", pathAttachment.p1y, 3, first)
      result.addNumberField("p2x", pathAttachment.p2x, 3, first)
      result.addNumberField("p2y", pathAttachment.p2y, 3, first)
      result.addNumberField("p3x", pathAttachment.p3x, 3, first)
      result.addNumberField("p3y", pathAttachment.p3y, 3, first)
      result.add "\n"
      result.addIndent(2)
      result.add "}"
    result.add "\n"
    result.addIndent(1)
    result.add "]"

  result.add "\n}\n"
