## M1 .bony JSON loader/serializer.

import std/[json, math, sets, strutils, tables]

import bony/generated/wire
import bony/model
import bony/deform/deformers
import bony/deform/keyforms
import bony/anim/timelines
import bony/statemachine/core

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
  validateKnownKeys(root, ["skeleton", "bones", "slots", "regions", "pathAttachments", "paths", "parameters", "deformers", "animations", "stateMachines"], "root")

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

  var loadedParameters: seq[ParameterAxis] = @[]
  if root.hasKey("parameters"):
    let parametersNode = requireArray(root["parameters"], "parameters")
    for index, paramNode in parametersNode.elems:
      let context = "parameters[" & $index & "]"
      let paramObject = requireObject(paramNode, context)
      validateKnownKeys(paramObject, ["name", "min", "max", "default"], context)
      loadedParameters.add ParameterAxis(
        name: requiredString(paramObject, "name", context),
        minValue: requiredFloat(paramObject, "min", context),
        maxValue: requiredFloat(paramObject, "max", context),
        defaultValue: optionalFloat(paramObject, "default", 0.0, context),
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

      let defId = requiredString(defObject, "id", context)
      let defParent = optionalString(defObject, "parent", "", context)
      let defOrder = uint32(optionalInt(defObject, "order", 0, context))
      let defKind = requiredString(defObject, "kind", context)

      var deformer: Deformer
      if defKind == "warp":
        if not defObject.hasKey("warp"):
          raise newBonyLoadError(schemaViolation, context & ".warp is required for kind=warp")
        let warpObject = requireObject(defObject["warp"], context & ".warp")
        validateKnownKeys(warpObject, ["rows", "cols", "minX", "minY", "maxX", "maxY", "controlPoints"], context & ".warp")
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
          rows: uint32(optionalInt(warpObject, "rows", 2, context & ".warp")),
          cols: uint32(optionalInt(warpObject, "cols", 2, context & ".warp")),
          minX: requiredFloat(warpObject, "minX", context & ".warp"),
          minY: requiredFloat(warpObject, "minY", context & ".warp"),
          maxX: requiredFloat(warpObject, "maxX", context & ".warp"),
          maxY: requiredFloat(warpObject, "maxY", context & ".warp"),
          controlPoints: controlPoints,
        )
        validateWarpLattice(lattice)
        deformer = Deformer(id: defId, parent: defParent, order: defOrder, kind: warpDeformerKind, warp: lattice)
      elif defKind == "rotation":
        if not defObject.hasKey("rotation"):
          raise newBonyLoadError(schemaViolation, context & ".rotation is required for kind=rotation")
        let rotObject = requireObject(defObject["rotation"], context & ".rotation")
        validateKnownKeys(rotObject, ["pivotX", "pivotY", "angleDegrees", "scaleX", "scaleY", "opacity"], context & ".rotation")
        let rotation = RotationDeformer(
          pivotX: requiredFloat(rotObject, "pivotX", context & ".rotation"),
          pivotY: requiredFloat(rotObject, "pivotY", context & ".rotation"),
          angleDegrees: requiredFloat(rotObject, "angleDegrees", context & ".rotation"),
          scaleX: optionalFloat(rotObject, "scaleX", 1.0, context & ".rotation"),
          scaleY: optionalFloat(rotObject, "scaleY", 1.0, context & ".rotation"),
          opacity: optionalFloat(rotObject, "opacity", 1.0, context & ".rotation"),
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

  result = skeletonData(loadedHeader, loadedBones, loadedSlots, loadedRegions, loadedPathAttachments, loadedPaths, loadedParameters, loadedDeformers)
  let loadedAnimClips = parseBonyAnimations(root, result)
  discard parseBonyStateMachines(root, result, loadedAnimClips)


proc parseBonyAnimations(root: JsonNode; data: SkeletonData): Table[string, AnimationClip] =
  if not root.hasKey("animations"):
    return initTable[string, AnimationClip]()
  let animsNode = requireArray(root["animations"], "animations")
  for animIndex, animNode in animsNode.elems:
    let ctx = "animations[" & $animIndex & "]"
    let aObj = requireObject(animNode, ctx)
    validateKnownKeys(aObj, ["name", "boneTimelines"], ctx)
    let animName = requiredString(aObj, "name", ctx)
    if animName.len == 0:
      raise newBonyLoadError(schemaViolation, ctx & ".name must not be empty")
    if result.hasKey(animName):
      raise newBonyLoadError(duplicateKey, "duplicate animation name: " & animName)
    var boneTimelines: seq[BoneTimeline] = @[]
    if aObj.hasKey("boneTimelines"):
      let btListNode = requireArray(aObj["boneTimelines"], ctx & ".boneTimelines")
      for btIndex, btNode in btListNode.elems:
        let btCtx = ctx & ".boneTimelines[" & $btIndex & "]"
        let btObj = requireObject(btNode, btCtx)
        validateKnownKeys(btObj, ["bone", "property", "keyframes"], btCtx)
        let bone = requiredString(btObj, "bone", btCtx)
        let propStr = requiredString(btObj, "property", btCtx)
        let tlKind =
          case propStr
          of "rotate": rotateTimeline
          of "translateX": translateXTimeline
          of "translateY": translateYTimeline
          of "scaleX": scaleXTimeline
          of "scaleY": scaleYTimeline
          of "shearX": shearXTimeline
          of "shearY": shearYTimeline
          else:
            raise newBonyLoadError(schemaViolation, btCtx & ".property unknown: " & propStr)
        let kfListNode = requireArray(btObj["keyframes"], btCtx & ".keyframes")
        var scalarKeys: seq[ScalarKeyframe] = @[]
        for kfIndex, kfNode in kfListNode.elems:
          let kfCtx = btCtx & ".keyframes[" & $kfIndex & "]"
          let kfObj = requireObject(kfNode, kfCtx)
          validateKnownKeys(kfObj, ["t", "value", "curve", "c1x", "c1y", "c2x", "c2y"], kfCtx)
          let kfTime = requiredF64(kfObj, "t", kfCtx)
          let kfValue = requiredFloat(kfObj, "value", kfCtx)
          let curve =
            if kfObj.hasKey("curve"):
              if kfObj["curve"].kind != JString:
                raise newBonyLoadError(schemaViolation, kfCtx & ".curve must be a string")
              let cs = kfObj["curve"].getStr()
              case cs
              of "linear": linearTimelineCurve
              of "stepped": steppedTimelineCurve
              of "bezier":
                let c1x = requiredF64(kfObj, "c1x", kfCtx)
                let c1y = requiredF64(kfObj, "c1y", kfCtx)
                let c2x = requiredF64(kfObj, "c2x", kfCtx)
                let c2y = requiredF64(kfObj, "c2y", kfCtx)
                bezierTimelineCurve(c1x, c1y, c2x, c2y)
              else:
                raise newBonyLoadError(schemaViolation, kfCtx & ".curve unknown: " & cs)
            else:
              linearTimelineCurve
          scalarKeys.add scalarKeyframe(kfTime, kfValue, curve)
        boneTimelines.add boneScalarTimeline(bone, tlKind, scalarKeys)
    result[animName] = animationClip(data, animName, boneTimelines)


proc parseBonyStateMachines(
  root: JsonNode;
  data: SkeletonData;
  clips: Table[string, AnimationClip];
): seq[StateMachine] =
  if not root.hasKey("stateMachines"):
    return @[]
  let smListNode = requireArray(root["stateMachines"], "stateMachines")
  var seenMachines = initHashSet[string]()
  for smIndex, smNode in smListNode.elems:
    let smCtx = "stateMachines[" & $smIndex & "]"
    let smObj = requireObject(smNode, smCtx)
    validateKnownKeys(smObj, ["name", "inputs", "layers", "listeners"], smCtx)
    let machineName = requiredString(smObj, "name", smCtx)
    if machineName in seenMachines:
      raise newBonyLoadError(duplicateKey, "duplicate state machine name: " & machineName)
    seenMachines.incl(machineName)
    var inputs: seq[StateMachineInput] = @[]
    if smObj.hasKey("inputs"):
      let inputsListNode = requireArray(smObj["inputs"], smCtx & ".inputs")
      for inIndex, inNode in inputsListNode.elems:
        let inCtx = smCtx & ".inputs[" & $inIndex & "]"
        let inObj = requireObject(inNode, inCtx)
        validateKnownKeys(inObj, ["name", "kind", "default"], inCtx)
        let inputName = requiredString(inObj, "name", inCtx)
        let kindStr = requiredString(inObj, "kind", inCtx)
        case kindStr
        of "bool":
          let dv = optionalBool(inObj, "default", false, inCtx)
          inputs.add stateMachineBoolInput(inputName, dv)
        of "number":
          let dv = optionalFloat(inObj, "default", 0.0, inCtx)
          inputs.add stateMachineNumberInput(inputName, dv)
        of "trigger":
          inputs.add stateMachineTriggerInput(inputName)
        else:
          raise newBonyLoadError(schemaViolation, inCtx & ".kind must be 'bool', 'number', or 'trigger'")
    var inputNames = initHashSet[string]()
    for inp in inputs:
      inputNames.incl(inp.name)
    if not smObj.hasKey("layers"):
      raise newBonyLoadError(schemaViolation, smCtx & ".layers is required")
    let layersListNode = requireArray(smObj["layers"], smCtx & ".layers")
    var layers: seq[StateMachineLayer] = @[]
    for layerIndex, layerNode in layersListNode.elems:
      let lCtx = smCtx & ".layers[" & $layerIndex & "]"
      let lObj = requireObject(layerNode, lCtx)
      validateKnownKeys(lObj, ["name", "states", "initialState", "transitions"], lCtx)
      let layerName = requiredString(lObj, "name", lCtx)
      let statesListNode = requireArray(lObj["states"], lCtx & ".states")
      var states: seq[StateMachineState] = @[]
      for stateIndex, stateNode in statesListNode.elems:
        let sCtx = lCtx & ".states[" & $stateIndex & "]"
        let sObj = requireObject(stateNode, sCtx)
        validateKnownKeys(sObj, ["name", "kind", "clip", "loop", "blendInput", "blendClips"], sCtx)
        let stateName = requiredString(sObj, "name", sCtx)
        let stateKindStr = requiredString(sObj, "kind", sCtx)
        case stateKindStr
        of "clip":
          let clipName = requiredString(sObj, "clip", sCtx)
          if clipName notin clips:
            raise newBonyLoadError(unknownRequiredReference, sCtx & ".clip references unknown animation: " & clipName)
          let loop = optionalBool(sObj, "loop", false, sCtx)
          states.add stateMachineState(stateName, clips[clipName], loop)
        of "blend1d":
          let blendInput = requiredString(sObj, "blendInput", sCtx)
          if blendInput notin inputNames:
            raise newBonyLoadError(unknownRequiredReference, sCtx & ".blendInput references unknown input: " & blendInput)
          let bcListNode = requireArray(sObj["blendClips"], sCtx & ".blendClips")
          var blendClips: seq[StateMachineBlendClip] = @[]
          for bcIndex, bcNode in bcListNode.elems:
            let bcCtx = sCtx & ".blendClips[" & $bcIndex & "]"
            let bcObj = requireObject(bcNode, bcCtx)
            validateKnownKeys(bcObj, ["clip", "value", "loop"], bcCtx)
            let bcClipName = requiredString(bcObj, "clip", bcCtx)
            if bcClipName notin clips:
              raise newBonyLoadError(unknownRequiredReference, bcCtx & ".clip references unknown animation: " & bcClipName)
            let bcValue = requiredFloat(bcObj, "value", bcCtx)
            let bcLoop = optionalBool(bcObj, "loop", false, bcCtx)
            blendClips.add stateMachineBlendClip(clips[bcClipName], bcValue, bcLoop)
          states.add stateMachineBlendState(stateName, blendInput, blendClips)
        else:
          raise newBonyLoadError(schemaViolation, sCtx & ".kind must be 'clip' or 'blend1d'")
      var stateNames = initHashSet[string]()
      for s in states:
        stateNames.incl(s.name)
      var transitions: seq[StateMachineTransition] = @[]
      if lObj.hasKey("transitions"):
        let transListNode = requireArray(lObj["transitions"], lCtx & ".transitions")
        for trIndex, trNode in transListNode.elems:
          let trCtx = lCtx & ".transitions[" & $trIndex & "]"
          let trObj = requireObject(trNode, trCtx)
          validateKnownKeys(trObj, ["fromState", "toState", "conditions"], trCtx)
          let fromState = requiredString(trObj, "fromState", trCtx)
          if fromState notin stateNames:
            raise newBonyLoadError(unknownRequiredReference, trCtx & ".fromState references unknown state: " & fromState)
          let toState = requiredString(trObj, "toState", trCtx)
          if toState notin stateNames:
            raise newBonyLoadError(unknownRequiredReference, trCtx & ".toState references unknown state: " & toState)
          let condListNode = requireArray(trObj["conditions"], trCtx & ".conditions")
          var conditions: seq[StateMachineCondition] = @[]
          for condIndex, condNode in condListNode.elems:
            let condCtx = trCtx & ".conditions[" & $condIndex & "]"
            let condObj = requireObject(condNode, condCtx)
            validateKnownKeys(condObj, ["input", "kind", "value"], condCtx)
            let condInput = requiredString(condObj, "input", condCtx)
            if condInput notin inputNames:
              raise newBonyLoadError(unknownRequiredReference, condCtx & ".input references unknown input: " & condInput)
            let condKindStr = requiredString(condObj, "kind", condCtx)
            case condKindStr
            of "boolEquals":
              let bv = optionalBool(condObj, "value", true, condCtx)
              conditions.add stateMachineBoolCondition(condInput, bv)
            of "numberEquals":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberEqualsCondition, nv)
            of "numberGreater":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberGreaterCondition, nv)
            of "numberGreaterOrEqual":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberGreaterOrEqualCondition, nv)
            of "numberLess":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberLessCondition, nv)
            of "numberLessOrEqual":
              let nv = requiredFloat(condObj, "value", condCtx)
              conditions.add stateMachineNumberCondition(condInput, numberLessOrEqualCondition, nv)
            of "triggerSet":
              conditions.add stateMachineTriggerCondition(condInput)
            else:
              raise newBonyLoadError(schemaViolation, condCtx & ".kind unknown: " & condKindStr)
          transitions.add stateMachineTransition(fromState, toState, conditions)
      let initialState = optionalString(lObj, "initialState", "", lCtx)
      layers.add stateMachineLayer(layerName, states, initialState, transitions)
    var layerStateMap = initTable[string, HashSet[string]]()
    for layer in layers:
      var ls = initHashSet[string]()
      for s in layer.states:
        ls.incl(s.name)
      layerStateMap[layer.name] = ls
    var listeners: seq[StateMachineListener] = @[]
    if smObj.hasKey("listeners"):
      let lstListNode = requireArray(smObj["listeners"], smCtx & ".listeners")
      for lstIndex, lstNode in lstListNode.elems:
        let lstCtx = smCtx & ".listeners[" & $lstIndex & "]"
        let lstObj = requireObject(lstNode, lstCtx)
        validateKnownKeys(lstObj, ["name", "kind", "layer", "fromState", "toState"], lstCtx)
        let lstName = requiredString(lstObj, "name", lstCtx)
        let lstKindStr = requiredString(lstObj, "kind", lstCtx)
        let lstLayer = requiredString(lstObj, "layer", lstCtx)
        if lstLayer notin layerStateMap:
          raise newBonyLoadError(unknownRequiredReference, lstCtx & ".layer references unknown layer: " & lstLayer)
        let lstStates = layerStateMap[lstLayer]
        case lstKindStr
        of "stateEnter":
          let toState = requiredString(lstObj, "toState", lstCtx)
          if toState notin lstStates:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".toState references unknown state: " & toState)
          listeners.add stateMachineStateEnterListener(lstName, lstLayer, toState)
        of "stateExit":
          let fromState = requiredString(lstObj, "fromState", lstCtx)
          if fromState notin lstStates:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".fromState references unknown state: " & fromState)
          listeners.add stateMachineStateExitListener(lstName, lstLayer, fromState)
        of "transition":
          let fromState = requiredString(lstObj, "fromState", lstCtx)
          if fromState notin lstStates:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".fromState references unknown state: " & fromState)
          let toState = requiredString(lstObj, "toState", lstCtx)
          if toState notin lstStates:
            raise newBonyLoadError(unknownRequiredReference, lstCtx & ".toState references unknown state: " & toState)
          listeners.add stateMachineTransitionListener(lstName, lstLayer, fromState, toState)
        else:
          raise newBonyLoadError(schemaViolation, lstCtx & ".kind must be 'stateEnter', 'stateExit', or 'transition'")
    result.add stateMachine(machineName, layers, inputs, listeners)


proc loadBonyJsonStateMachines*(text: string): seq[StateMachine] =
  let data = loadBonyJson(text)
  let root = requireObject(parseJson(text), "root")
  let clips = parseBonyAnimations(root, data)
  parseBonyStateMachines(root, data, clips)


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
      result.addStringField("name", param.name, 3, first)
      result.addNumberField("min", param.minValue, 3, first)
      result.addNumberField("max", param.maxValue, 3, first)
      if param.defaultValue != 0.0:
        result.addNumberField("default", param.defaultValue, 3, first)
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
      result.addStringField("id", rec.deformer.id, 3, first)
      if rec.deformer.parent.len > 0:
        result.addStringField("parent", rec.deformer.parent, 3, first)
      result.addIntField("order", int(rec.deformer.order), 3, first)
      case rec.deformer.kind
      of warpDeformerKind:
        result.addStringField("kind", "warp", 3, first)
        result.addFieldPrefix("warp", 3, first)
        result.add "{\n"
        var wfirst = true
        let warp = rec.deformer.warp
        result.addIntField("rows", int(warp.rows), 4, wfirst)
        result.addIntField("cols", int(warp.cols), 4, wfirst)
        result.addNumberField("minX", warp.minX, 4, wfirst)
        result.addNumberField("minY", warp.minY, 4, wfirst)
        result.addNumberField("maxX", warp.maxX, 4, wfirst)
        result.addNumberField("maxY", warp.maxY, 4, wfirst)
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
        result.addStringField("kind", "rotation", 3, first)
        result.addFieldPrefix("rotation", 3, first)
        result.add "{\n"
        var rfirst = true
        let rot = rec.deformer.rotation
        result.addNumberField("pivotX", rot.pivotX, 4, rfirst)
        result.addNumberField("pivotY", rot.pivotY, 4, rfirst)
        result.addNumberField("angleDegrees", rot.angleDegrees, 4, rfirst)
        if rot.scaleX != 1.0:
          result.addNumberField("scaleX", rot.scaleX, 4, rfirst)
        if rot.scaleY != 1.0:
          result.addNumberField("scaleY", rot.scaleY, 4, rfirst)
        if rot.opacity != 1.0:
          result.addNumberField("opacity", rot.opacity, 4, rfirst)
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
