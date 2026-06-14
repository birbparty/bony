## Headless bony CLI harness core.

import std/[json, math, os, parseutils, sets, strutils, tables]

import bony
import pixie


proc usage(): string =
  "usage: bony json-to-bnb <input.bony> <output.bnb>\n" &
    "       bony bnb-to-json <input.bnb> <output.bony>\n" &
    "       bony import-lottie <input.json> <output.bony> --assets-dir images [--setup-only] [--origin center|top-left]\n" &
    "       bony golden-gen <input.bony|input.bnb> <output.json> [--t seconds]\n" &
    "       bony play <input.bony|input.bnb> --out frame.png [--t seconds] [--width px] [--height px]\n" &
    "       bony play <input> --state-machine <name> --input-script <script.json> --out frame.png"

type
  LottieDiagnostic = object of CatchableError
    code*: string
    target*: string
    capability*: string

  LottieAsset = object
    id: string
    path: string
    width: float64
    height: float64

  LottieTransform = object
    anchorX: float64
    anchorY: float64
    positionX: float64
    positionY: float64
    scaleX: float64
    scaleY: float64
    rotation: float64

  LottieLayer = object
    name: string
    kind: string
    parent: string
    parentIndex: int
    parentIsIndex: bool
    imageAsset: string
    width: float64
    height: float64
    transform: LottieTransform

  LottieComposition = object
    width: int
    height: int
    frameRate: float64
    inFrame: float64
    outFrame: float64
    layers: seq[LottieLayer]


proc newLottieDiagnostic(code, target, capability, message: string): ref LottieDiagnostic =
  new(result)
  result.code = code
  result.target = target
  result.capability = capability
  result.msg = message


proc raiseLottie(code, target, capability, message: string) =
  raise newLottieDiagnostic(code, target, capability, message)


proc lottieMessage(exc: ref LottieDiagnostic): string =
  result = exc.code
  if exc.target.len > 0:
    result.add " target=" & exc.target
  if exc.capability.len > 0:
    result.add " capability=" & exc.capability
  if exc.msg.len > 0:
    result.add " " & exc.msg


proc readBytes(path: string): seq[byte] =
  let content = readFile(path)
  result = newSeq[byte](content.len)
  for index, ch in content:
    result[index] = byte(ord(ch))


proc writeBytes(path: string; bytes: openArray[byte]) =
  var content = newString(bytes.len)
  for index, value in bytes:
    content[index] = char(value)
  writeFile(path, content)


proc parseFloatArg(value, name: string): float64 =
  var parsed: float
  let consumed = parseFloat(value, parsed)
  if consumed != value.len:
    raise newBonyLoadError(schemaViolation, name & " must be a number")
  quantizeF32(parsed, name)


proc parsePositiveIntArg(value, name: string): int =
  var parsed: int
  let consumed = parseInt(value, parsed)
  if consumed != value.len or parsed <= 0:
    raise newBonyLoadError(schemaViolation, name & " must be a positive integer")
  parsed


proc requireSetupPoseTime(time: float64) =
  if time != 0.0:
    raise newBonyLoadError(
      schemaViolation,
      "--t is reserved until serialized animations are available; use --t 0 for setup-pose output",
    )


proc rejectStateMachineArgs(stateMachine, inputScript: string) =
  if stateMachine.len != 0 or inputScript.len != 0:
    raise newBonyLoadError(
      schemaViolation,
      "serialized state machines and input scripts are not available in the current .bony/.bnb model",
    )


proc loadInputSkeleton(path: string): SkeletonData =
  if path.toLowerAscii.endsWith(".bnb"):
    loadBonyBnb(readBytes(path))
  else:
    loadBonyJson(readFile(path))


proc validateKeys(node: JsonNode; allowed: openArray[string]; target: string) =
  if node.kind != JObject:
    raiseLottie("schemaViolation", target, "object", "expected object")
  for key in node.keys:
    var found = false
    for allowedKey in allowed:
      if key == allowedKey:
        found = true
        break
    if not found:
      raiseLottie("schemaViolation", target, "unknownKey", "unknown key: " & key)


proc requireObject(node: JsonNode; target: string): JsonNode =
  if node.kind != JObject:
    raiseLottie("schemaViolation", target, "object", "expected object")
  node


proc requireArray(node: JsonNode; target: string): JsonNode =
  if node.kind != JArray:
    raiseLottie("schemaViolation", target, "array", "expected array")
  node


proc requireField(node: JsonNode; key, target: string): JsonNode =
  if not node.hasKey(key):
    raiseLottie("schemaViolation", target, key, "missing required field: " & key)
  node[key]


proc finiteNumber(node: JsonNode; target, capability: string): float64 =
  if node.kind notin {JInt, JFloat}:
    raiseLottie("schemaViolation", target, capability, "expected number")
  result = node.getFloat()
  if classify(result) in {fcNan, fcInf, fcNegInf}:
    raiseLottie("schemaViolation", target, capability, "expected finite number")


proc positiveInt(node: JsonNode; target, capability: string): int =
  if node.kind != JInt:
    raiseLottie("schemaViolation", target, capability, "expected integer")
  result = node.getInt()
  if result <= 0:
    raiseLottie("schemaViolation", target, capability, "expected positive integer")


proc optionalString(node: JsonNode; key, defaultValue, target: string): string =
  if not node.hasKey(key):
    return defaultValue
  if node[key].kind != JString:
    raiseLottie("schemaViolation", target, key, "expected string")
  node[key].getStr()


proc requiredString(node: JsonNode; key, target: string): string =
  let value = optionalString(node, key, "", target)
  if value.len == 0:
    raiseLottie("schemaViolation", target, key, "expected non-empty string")
  value


proc optionalParentReference(node: JsonNode; key, target: string): tuple[name: string, index: int, isIndex: bool] =
  result.index = -1
  if not node.hasKey(key):
    return
  case node[key].kind
  of JString:
    result.name = node[key].getStr()
  of JInt:
    result.index = node[key].getInt()
    result.isIndex = true
  else:
    raiseLottie("schemaViolation", target, key, "expected string or integer")


proc pathIsSafeRelative(path: string): bool =
  if path.len == 0 or path.isAbsolute:
    return false
  for part in path.split({'/', '\\'}):
    if part.len == 0 or part == "." or part == "..":
      return false
  true


proc requireVector2(node: JsonNode; target, capability: string; defaultX, defaultY: float64): tuple[x, y: float64] =
  if node.isNil:
    return (defaultX, defaultY)
  if node.kind == JArray:
    for item in node.elems:
      if item.kind in {JObject, JArray}:
        raiseLottie("unsupportedFeature", target, capability, "animated channels are not supported in Tier 1")
    if node.elems.len != 2:
      raiseLottie("schemaViolation", target, capability, "expected [x, y]")
    return (
      finiteNumber(node.elems[0], target, capability),
      finiteNumber(node.elems[1], target, capability),
    )
  raiseLottie("unsupportedFeature", target, capability, "animated channels are not supported in Tier 1")


proc requireScalar(node: JsonNode; target, capability: string; defaultValue: float64): float64 =
  if node.isNil:
    return defaultValue
  if node.kind in {JInt, JFloat}:
    return finiteNumber(node, target, capability)
  raiseLottie("unsupportedFeature", target, capability, "animated channels are not supported in Tier 1")


proc parseTransform(node: JsonNode; target: string): LottieTransform =
  result = LottieTransform(scaleX: 1.0, scaleY: 1.0)
  if node.isNil:
    return
  let transform = requireObject(node, target & ".transform")
  validateKeys(transform, ["anchor", "position", "scale", "rotation", "opacity"], target & ".transform")
  let anchor = requireVector2(if transform.hasKey("anchor"): transform["anchor"] else: nil, target, "anchor", 0.0, 0.0)
  let position = requireVector2(if transform.hasKey("position"): transform["position"] else: nil, target, "position", 0.0, 0.0)
  let scale = requireVector2(if transform.hasKey("scale"): transform["scale"] else: nil, target, "scale", 100.0, 100.0)
  let rotation = requireScalar(if transform.hasKey("rotation"): transform["rotation"] else: nil, target, "rotation", 0.0)
  let opacity = requireScalar(if transform.hasKey("opacity"): transform["opacity"] else: nil, target, "opacity", 100.0)
  if opacity != 100.0:
    raiseLottie("unsupportedFeature", target, "opacity", "non-default opacity is not serializable in Tier 1")
  result = LottieTransform(
    anchorX: anchor.x,
    anchorY: anchor.y,
    positionX: position.x,
    positionY: position.y,
    scaleX: scale.x / 100.0,
    scaleY: scale.y / 100.0,
    rotation: rotation,
  )


proc parseAssets(root: JsonNode; assetsDir: string): Table[string, LottieAsset] =
  result = initTable[string, LottieAsset]()
  if not root.hasKey("assets"):
    return
  let assets = requireArray(root["assets"], "assets")
  for index, item in assets.elems:
    let target = "assets[" & $index & "]"
    let asset = requireObject(item, target)
    validateKeys(asset, ["id", "path", "w", "h"], target)
    let id = requiredString(asset, "id", target)
    if id in result:
      raiseLottie("schemaViolation", target, "duplicateAsset", "duplicate asset id: " & id)
    let path = requiredString(asset, "path", target)
    if not path.pathIsSafeRelative:
      raiseLottie("schemaViolation", target, "assetPath", "asset path must be safe and relative")
    if assetsDir.len > 0 and not fileExists(assetsDir / path):
      raiseLottie("invalidReference", target, "assetPath", "missing external image file: " & path)
    result[id] = LottieAsset(
      id: id,
      path: path,
      width: float64(positiveInt(requireField(asset, "w", target), target, "w")),
      height: float64(positiveInt(requireField(asset, "h", target), target, "h")),
    )


proc layerName(layer: JsonNode; index: int): string =
  if layer.hasKey("name"):
    result = requiredString(layer, "name", "layers[" & $index & "]")
  else:
    result = "layer_" & $index


proc parseLayer(
  layer: JsonNode;
  index: int;
  composition: JsonNode;
  assets: Table[string, LottieAsset];
): LottieLayer =
  let target = "layers[" & $index & "]"
  let layerObject = requireObject(layer, target)
  validateKeys(layerObject, ["name", "kind", "parent", "in", "out", "blend", "transform", "image", "shapes"], target)

  result.name = layerObject.layerName(index)
  result.kind = requiredString(layerObject, "kind", target)
  if result.kind != "image":
    raiseLottie("unsupportedFeature", target, result.kind, "only image layers are supported in Tier 1")
  let blend = optionalString(layerObject, "blend", "normal", target)
  if blend != "normal":
    raiseLottie("unsupportedFeature", target, "blend", "only normal blend is supported in Tier 1")
  let compIn = finiteNumber(requireField(composition, "ip", "composition"), "composition", "ip")
  let compOut = finiteNumber(requireField(composition, "op", "composition"), "composition", "op")
  let layerIn = if layerObject.hasKey("in"): finiteNumber(layerObject["in"], target, "in") else: compIn
  let layerOut = if layerObject.hasKey("out"): finiteNumber(layerObject["out"], target, "out") else: compOut
  if layerIn != compIn or layerOut != compOut:
    raiseLottie("unsupportedFeature", target, "visibility", "visibility intervals are not supported in Tier 1")
  if layerObject.hasKey("shapes"):
    raiseLottie("unsupportedFeature", target, "shape", "shape layers require Tier 2")

  let parent = optionalParentReference(layerObject, "parent", target)
  result.parent = parent.name
  result.parentIndex = parent.index
  result.parentIsIndex = parent.isIndex
  result.transform = parseTransform(if layerObject.hasKey("transform"): layerObject["transform"] else: nil, target)
  if not layerObject.hasKey("image"):
    raiseLottie("schemaViolation", target, "image", "image layer requires image payload")
  let image = requireObject(layerObject["image"], target & ".image")
  validateKeys(image, ["asset", "anchor", "size"], target & ".image")
  result.imageAsset = requiredString(image, "asset", target & ".image")
  if result.imageAsset notin assets:
    raiseLottie("invalidReference", target, "asset", "unknown image asset: " & result.imageAsset)
  let asset = assets[result.imageAsset]
  if image.hasKey("anchor"):
    let anchor = requireVector2(image["anchor"], target, "image.anchor", 0.0, 0.0)
    if anchor.x != 0.0 or anchor.y != 0.0:
      raiseLottie("unsupportedFeature", target, "image.anchor", "image payload anchor is not supported in Tier 1")
  if image.hasKey("size"):
    let size = requireVector2(image["size"], target, "image.size", asset.width, asset.height)
    if size.x <= 0.0 or size.y <= 0.0:
      raiseLottie("schemaViolation", target, "image.size", "image size must be positive")
    result.width = size.x
    result.height = size.y
  else:
    result.width = asset.width
    result.height = asset.height


proc parseLottieComposition(text, assetsDir: string): LottieComposition =
  var root: JsonNode
  try:
    root = parseJson(text)
  except JsonParsingError as exc:
    raiseLottie("schemaViolation", "composition", "json", "invalid JSON: " & exc.msg)
  let compositionObject = requireObject(root, "composition")
  validateKeys(compositionObject, ["w", "h", "fr", "ip", "op", "assets", "layers"], "composition")
  result.width = positiveInt(requireField(compositionObject, "w", "composition"), "composition", "w")
  result.height = positiveInt(requireField(compositionObject, "h", "composition"), "composition", "h")
  result.frameRate = finiteNumber(requireField(compositionObject, "fr", "composition"), "composition", "fr")
  if result.frameRate <= 0.0:
    raiseLottie("schemaViolation", "composition", "fr", "frame rate must be positive")
  result.inFrame = finiteNumber(requireField(compositionObject, "ip", "composition"), "composition", "ip")
  result.outFrame = finiteNumber(requireField(compositionObject, "op", "composition"), "composition", "op")
  if result.outFrame <= result.inFrame:
    raiseLottie("schemaViolation", "composition", "duration", "op must be greater than ip")
  if not compositionObject.hasKey("layers"):
    raiseLottie("schemaViolation", "composition", "layers", "layers are required")
  let assets = parseAssets(compositionObject, assetsDir)
  let layers = requireArray(compositionObject["layers"], "layers")
  var names = initHashSet[string]()
  for index, item in layers.elems:
    let layer = parseLayer(item, index, compositionObject, assets)
    if layer.name in names:
      raiseLottie("schemaViolation", "layers[" & $index & "]", "duplicateName", "duplicate layer name: " & layer.name)
    names.incl(layer.name)
    result.layers.add layer
  if result.layers.len == 0:
    raiseLottie("schemaViolation", "composition", "layers", "at least one layer is required")
  for index, layer in result.layers:
    if layer.parentIsIndex:
      if layer.parentIndex >= 0 and layer.parentIndex < result.layers.len:
        result.layers[index].parent = result.layers[layer.parentIndex].name
      else:
        raiseLottie("invalidReference", "layers[" & $index & "]", "parent", "unknown parent index: " & $layer.parentIndex)
      continue
    if layer.parent.len == 0:
      continue
    var found = false
    for candidate in result.layers:
      if candidate.name == layer.parent:
        found = true
        break
    if not found:
      var parentIndex: int
      if parseInt(layer.parent, parentIndex) == layer.parent.len and parentIndex >= 0 and parentIndex < result.layers.len:
        result.layers[index].parent = result.layers[parentIndex].name
      else:
        raiseLottie("invalidReference", "layers[" & $index & "]", "parent", "unknown parent: " & layer.parent)
  var parentByName = initTable[string, string]()
  for layer in result.layers:
    parentByName[layer.name] = layer.parent
  for layer in result.layers:
    var seen = initHashSet[string]()
    var current = layer.name
    while current.len > 0:
      if current in seen:
        raiseLottie("cycleDetected", layer.name, "parent", "parent graph contains a cycle")
      seen.incl current
      current = parentByName.getOrDefault(current, "")


proc appendLottieBone(
  index: int;
  composition: LottieComposition;
  nameToIndex: Table[string, int];
  visiting: var HashSet[string];
  emitted: var HashSet[string];
  bones: var seq[BoneData];
) =
  let layer = composition.layers[index]
  if layer.name in emitted:
    return
  if layer.name in visiting:
    raiseLottie("cycleDetected", layer.name, "parent", "parent graph contains a cycle")
  visiting.incl layer.name
  if layer.parent.len > 0:
    if layer.parent notin nameToIndex:
      raiseLottie("invalidReference", layer.name, "parent", "unknown parent: " & layer.parent)
    appendLottieBone(nameToIndex[layer.parent], composition, nameToIndex, visiting, emitted, bones)
  let parent = if layer.parent.len == 0: "composition" else: layer.parent
  let angle = degToRad(layer.transform.rotation)
  let anchorX = layer.transform.anchorX * layer.transform.scaleX
  let anchorY = layer.transform.anchorY * layer.transform.scaleY
  let x = layer.transform.positionX - (anchorX * cos(angle) - anchorY * sin(angle))
  let y = layer.transform.positionY - (anchorX * sin(angle) + anchorY * cos(angle))
  bones.add boneData(
    layer.name,
    parent,
    localTransform(
      x = x,
      y = y,
      rotation = layer.transform.rotation,
      scaleX = layer.transform.scaleX,
      scaleY = layer.transform.scaleY,
    ),
  )
  visiting.excl layer.name
  emitted.incl layer.name


proc toSkeletonData(composition: LottieComposition; origin: string): SkeletonData =
  let offsetX = if origin == "center": -float64(composition.width) * 0.5 else: 0.0
  let offsetY = if origin == "center": -float64(composition.height) * 0.5 else: 0.0
  var bones: seq[BoneData] = @[boneData("composition", "", localTransform(x = offsetX, y = offsetY))]
  var slots: seq[SlotData] = @[]
  var regions: seq[RegionAttachment] = @[]
  var nameToIndex = initTable[string, int]()
  for index, layer in composition.layers:
    nameToIndex[layer.name] = index
  var visiting = initHashSet[string]()
  var emitted = initHashSet[string]()
  for index in 0 ..< composition.layers.len:
    appendLottieBone(index, composition, nameToIndex, visiting, emitted, bones)
  for layer in composition.layers:
    slots.add slotData(layer.name & "_slot", layer.name, layer.name)
    regions.add regionAttachment(layer.name, layer.width, layer.height)
  skeletonData(skeletonHeader("lottie-import", "0.1.0"), bones, slots, regions)


proc importLottie(args: seq[string]) =
  if args.len < 2:
    quit(usage(), QuitFailure)
  let inputPath = args[0]
  let outputPath = args[1]
  var assetsDir = ""
  var origin = "center"
  var index = 2
  while index < args.len:
    case args[index]
    of "--assets-dir":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      assetsDir = args[index + 1]
      index += 2
    of "--setup-only":
      index += 1
    of "--origin":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      origin = args[index + 1]
      if origin notin ["center", "top-left"]:
        raiseLottie("schemaViolation", "cli", "origin", "origin must be center or top-left")
      index += 2
    of "--reject-shapes":
      index += 1
    of "--rasterize-shapes":
      raiseLottie("unsupportedFeature", "cli", "rasterize-shapes", "shape rasterization requires Tier 2")
    of "--atlas-out":
      raiseLottie("unsupportedFeature", "cli", "atlas", "atlas output requires Tier 2")
    else:
      quit(usage(), QuitFailure)
  if assetsDir.len == 0:
    raiseLottie("schemaViolation", "cli", "assets-dir", "--assets-dir is required")
  let composition = parseLottieComposition(readFile(inputPath), assetsDir)
  let data = composition.toSkeletonData(origin)
  writeFile(outputPath, toBonyJson(data))


proc affineJson(world: Affine2): JsonNode =
  result = newJObject()
  result["a"] = newJFloat(world.a)
  result["b"] = newJFloat(world.b)
  result["c"] = newJFloat(world.c)
  result["d"] = newJFloat(world.d)
  result["tx"] = newJFloat(world.tx)
  result["ty"] = newJFloat(world.ty)


proc vertexJson(vertex: DrawVertex): JsonNode =
  result = newJObject()
  result["x"] = newJFloat(vertex.x)
  result["y"] = newJFloat(vertex.y)
  result["u"] = newJFloat(vertex.u)
  result["v"] = newJFloat(vertex.v)
  result["r"] = newJFloat(vertex.r)
  result["g"] = newJFloat(vertex.g)
  result["b"] = newJFloat(vertex.b)
  result["a"] = newJFloat(vertex.a)


proc numericGoldenJson(data: SkeletonData; time: float64): string =
  validateSkeletonData(data)
  let worlds = computeWorldTransforms(data)
  let batches = buildDrawBatches(data)
  var root = newJObject()
  root["format"] = newJString("bony.numeric-golden.v1")
  root["skeleton"] = newJString(data.header.name)
  root["version"] = newJString(data.header.version)
  root["time"] = newJFloat(time)

  var bones = newJArray()
  let boneData = data.bones
  for index, bone in boneData:
    var node = newJObject()
    node["name"] = newJString(bone.name)
    node["parent"] = newJString(bone.parent)
    node["world"] = affineJson(worlds[index])
    bones.add node
  root["bones"] = bones

  var slots = newJArray()
  for slot in data.slots:
    var node = newJObject()
    node["name"] = newJString(slot.name)
    node["bone"] = newJString(slot.bone)
    node["attachment"] = newJString(slot.attachment)
    node["r"] = newJFloat(1.0)
    node["g"] = newJFloat(1.0)
    node["b"] = newJFloat(1.0)
    node["a"] = newJFloat(1.0)
    slots.add node
  root["slots"] = slots

  var drawBatches = newJArray()
  for batch in batches:
    var node = newJObject()
    node["slot"] = newJString(batch.slot)
    node["bone"] = newJString(batch.bone)
    node["attachment"] = newJString(batch.attachment)
    node["texturePage"] = newJString(batch.texturePage)
    node["blendMode"] = newJString(batch.blendMode)
    node["clipId"] = newJString(batch.clipId)
    node["world"] = affineJson(batch.world)
    var vertices = newJArray()
    for vertex in batch.vertices:
      vertices.add vertexJson(vertex)
    node["vertices"] = vertices
    var indices = newJArray()
    for index in batch.indices:
      indices.add newJInt(int(index))
    node["indices"] = indices
    drawBatches.add node
  root["drawBatches"] = drawBatches
  pretty(root) & "\n"


proc writeNumericGolden(args: seq[string]) =
  if args.len < 2:
    quit(usage(), QuitFailure)
  var time = 0.0
  var stateMachine = ""
  var inputScript = ""
  var index = 2
  while index < args.len:
    case args[index]
    of "--t":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      time = parseFloatArg(args[index + 1], "--t")
      index += 2
    of "--state-machine":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      stateMachine = args[index + 1]
      index += 2
    of "--input-script":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      inputScript = args[index + 1]
      index += 2
    else:
      quit(usage(), QuitFailure)
  rejectStateMachineArgs(stateMachine, inputScript)
  requireSetupPoseTime(time)
  let data = loadInputSkeleton(args[0])
  writeFile(args[1], numericGoldenJson(data, time))


proc renderSetupPose(args: seq[string]) =
  if args.len < 3:
    quit(usage(), QuitFailure)

  let inputPath = args[0]
  var outputPath = ""
  var time = 0.0
  var width = 256
  var height = 256
  var stateMachine = ""
  var inputScript = ""
  var index = 1
  while index < args.len:
    case args[index]
    of "--out":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      outputPath = args[index + 1]
      index += 2
    of "--t":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      time = parseFloatArg(args[index + 1], "--t")
      index += 2
    of "--width":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      width = parsePositiveIntArg(args[index + 1], "--width")
      index += 2
    of "--height":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      height = parsePositiveIntArg(args[index + 1], "--height")
      index += 2
    of "--state-machine":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      stateMachine = args[index + 1]
      index += 2
    of "--input-script":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      inputScript = args[index + 1]
      index += 2
    else:
      quit(usage(), QuitFailure)

  if outputPath.len == 0:
    raise newBonyLoadError(schemaViolation, "play requires --out")
  rejectStateMachineArgs(stateMachine, inputScript)
  requireSetupPoseTime(time)
  let data = loadInputSkeleton(inputPath)
  let image = renderSoftware(buildDrawBatches(data), width, height)
  image.writeFile(outputPath)


proc main() =
  let args = commandLineParams()
  if args.len == 0:
    quit(usage(), QuitFailure)

  try:
    case args[0]
    of "json-to-bnb":
      if args.len != 3:
        quit(usage(), QuitFailure)
      writeBytes(args[2], toBonyBnb(loadBonyJson(readFile(args[1]))))
    of "bnb-to-json":
      if args.len != 3:
        quit(usage(), QuitFailure)
      writeFile(args[2], toBonyJson(loadKnownBonyBnb(readBytes(args[1]))))
    of "import-lottie":
      importLottie(args[1 .. ^1])
    of "golden-gen":
      writeNumericGolden(args[1 .. ^1])
    of "play":
      renderSetupPose(args[1 .. ^1])
    else:
      quit(usage(), QuitFailure)
  except LottieDiagnostic as exc:
    quit("bony: " & exc.lottieMessage, QuitFailure)
  except BonyLoadError as exc:
    quit("bony: " & exc.msg, QuitFailure)
  except OSError as exc:
    quit("bony: " & exc.msg, QuitFailure)


when isMainModule:
  main()
