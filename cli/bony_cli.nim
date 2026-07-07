## Headless bony CLI harness core.

import std/[algorithm, json, math, os, parseutils, sets, strutils, tables]

import bony
import pixie

import atlas_packer
import auto_weights
import json_schema


proc usage(): string =
    "usage: bony json-to-bnb <input.bony> <output.bnb>\n" &
    "       bony bnb-to-json <input.bnb> <output.bony>\n" &
    "       bony import-lottie <input.json> <output.bony> --assets-dir images [--setup-only] [--origin center|top-left]\n" &
    "       bony import-dragonbones <input_ske.json> <output.bony> [--assets-dir images] [--setup-only] [--allow-multiple-armatures]\n" &
    "       bony golden-gen <input.bony|input.bnb> <output.json> [--t seconds] [--animation clip]\n" &
    "       bony golden-gen <input.bony|input.bnb> <output.json> --input-script <script.json> --sample <name-or-index>\n" &
    "       bony golden-gen <input.bony|input.bnb> <output.json> --state-machine <name> --input-script <script.json> --sample <name-or-index>\n" &
    "       bony play <input.bony|input.bnb> --out frame.png [--t seconds] [--width px] [--height px] [--origin center|top-left]\n" &
    "       bony play <input.bony|input.bnb> --state-machine <name> --input-script <script.json> --out frame.png [--width px] [--height px] [--origin center|top-left]\n" &
    "       bony pack-atlas <images-dir> --out-dir <dir> [--page-size 2048] [--padding 2]\n" &
    "       bony auto-weights <input.json> <output.json>"

type
  CliDiagnosticKind = enum
    cliSchemaViolation = "schemaViolation"
    cliUnsupportedFeature = "unsupportedFeature"
    cliInvalidReference = "invalidReference"
    cliCycleDetected = "cycleDetected"
    cliMissingAsset = "missingAsset"
    cliUnsupportedVersion = "unsupportedVersion"

  CliDiagnostic = object of CatchableError
    kind*: CliDiagnosticKind
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

  ScriptInputKind = enum
    scriptBoolInput,
    scriptNumberInput,
    scriptTriggerInput

  ScriptInput = object
    name: string
    kind: ScriptInputKind
    boolValue: bool
    numberValue: float64

  ScriptPointer = object
    kind: StateMachineListenerKind
    x: float64
    y: float64

  InputScriptSample = object
    name: string
    time: float64
    inputs: seq[ScriptInput]
    pointer: ScriptPointer
    hasPointer: bool

  InputScriptChild = object
    skeleton: string
    asset: string
    binaryAsset: string

  InputScript = object
    asset: string
    stateMachine: string
    activeSkin: string
    children: seq[InputScriptChild]
    samples: seq[InputScriptSample]

  StateMachineRunSample = object
    machine: string
    activeSkin: string
    sample: InputScriptSample
    runtime: StateMachineRuntime
    evaluated: EvaluatedStateMachine
    posedData: SkeletonData
    worlds: seq[Affine2]
    animationEvents: seq[DispatchedEvent]

  StateMachineGolden = object
    present: bool
    machine: string
    sample: string
    runtime: StateMachineRuntime
    evaluated: EvaluatedStateMachine

  RenderSlotState = object
    r: float64
    g: float64
    b: float64
    a: float64
    hasDark: bool
    darkR: float64
    darkG: float64
    darkB: float64
    hasSequence: bool
    sequenceIndex: uint32
    sequenceDelay: float64
    sequenceMode: SequenceMode


proc newCliDiagnostic(kind: CliDiagnosticKind; target, capability, message: string): ref CliDiagnostic =
  new(result)
  result.kind = kind
  result.target = target
  result.capability = capability
  result.msg = message


proc raiseCli(kind: CliDiagnosticKind; target, capability, message: string) =
  raise newCliDiagnostic(kind, target, capability, message)


proc cliMessage(exc: ref CliDiagnostic): string =
  result = $exc.kind
  if exc.target.len > 0:
    result.add " target=" & exc.target
  if exc.capability.len > 0:
    result.add " capability=" & exc.capability
  if exc.msg.len > 0:
    result.add " " & exc.msg


proc raiseLottie(kind: CliDiagnosticKind; target, capability, message: string) =
  raiseCli(kind, target, capability, message)


proc raiseDb(kind: CliDiagnosticKind; target, capability, message: string) =
  raiseCli(kind, target, capability, message)


proc raiseLottieSchema(target, capability, message: string) =
  raiseLottie(cliSchemaViolation, target, capability, message)


proc raiseDbSchema(target, capability, message: string) =
  raiseDb(cliSchemaViolation, target, capability, message)


proc raiseBonySchema(target, capability, message: string) =
  raise newBonyLoadError(schemaViolation, message)


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


proc parseNonNegativeIntArg(value, name: string): int =
  var parsed: int
  let consumed = parseInt(value, parsed)
  if consumed != value.len or parsed < 0:
    raise newBonyLoadError(schemaViolation, name & " must be a non-negative integer")
  parsed


proc requireSetupPoseTime(time: float64) =
  if time != 0.0:
    raise newBonyLoadError(
      schemaViolation,
      "--t is reserved until serialized animations are available; use --t 0 for setup-pose output",
    )


const validOrigins = ["center", "top-left"]
const originErrMsg = "origin must be center or top-left"


proc loadInputSkeleton(path: string): SkeletonData =
  if path.toLowerAscii.endsWith(".bnb"):
    loadBonyBnb(readBytes(path))
  else:
    loadBonyJson(readFile(path))


proc loadInputAsset(path: string): BonyAsset =
  if path.toLowerAscii.endsWith(".bnb"):
    loadBonyBnbAsset(readBytes(path))
  else:
    loadBonyJsonAsset(readFile(path))


proc applyViewportTransform(batches: seq[DrawBatch]; width, height: int): seq[DrawBatch] =
  # Translate world-space vertices to pixel space for `bony play` image output.
  # Transform: screen_x = world_x + width/2; screen_y = height/2 - world_y.
  # This places the skeleton origin at the viewport centre and flips y (world is
  # y-up; pixels are y-down). Rigs with geometry within ±width/2 and ±height/2
  # of the origin will be visible; larger or off-centre rigs may still clip.
  # For odd dimensions, width/2 and height/2 are 0.5-fractional (e.g. 127.5 for
  # width=255), which is harmless — vertices land at half-pixel offsets and the
  # rasterizer rounds to the nearest integer via the normal fill rule.
  #
  # INVARIANT: only `vertices` are rewritten to screen space; `batch.world` and
  # `clipId` remain in world space and must not be mixed with the transformed
  # vertices by any future consumer.
  let cx = float64(width) * 0.5
  let cy = float64(height) * 0.5
  result = batches
  for i in 0 ..< result.len:
    for j in 0 ..< result[i].vertices.len:
      result[i].vertices[j].x = result[i].vertices[j].x + cx
      result[i].vertices[j].y = cy - result[i].vertices[j].y


proc validateKeys(node: JsonNode; allowed: openArray[string]; target: string) =
  json_schema.validateKeys(node, allowed, target, raiseLottieSchema)


proc requireObject(node: JsonNode; target: string): JsonNode =
  json_schema.requireObject(node, target, raiseLottieSchema)


proc requireArray(node: JsonNode; target: string): JsonNode =
  json_schema.requireArray(node, target, raiseLottieSchema)


proc requireField(node: JsonNode; key, target: string): JsonNode =
  json_schema.requireField(node, key, target, raiseLottieSchema)


proc finiteNumber(node: JsonNode; target, capability: string): float64 =
  json_schema.requireNumber(node, target, capability, raiseLottieSchema)


proc positiveInt(node: JsonNode; target, capability: string): int =
  json_schema.requirePositiveInt(node, target, capability, raiseLottieSchema)


proc optionalString(node: JsonNode; key, defaultValue, target: string): string =
  json_schema.optionalString(node, key, defaultValue, target, raiseLottieSchema)


proc requiredString(node: JsonNode; key, target: string): string =
  let value = optionalString(node, key, "", target)
  if value.len == 0:
    raiseLottie(cliSchemaViolation, target, key, "expected non-empty string")
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
    raiseLottie(cliSchemaViolation, target, key, "expected string or integer")


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
        raiseLottie(cliUnsupportedFeature, target, capability, "animated channels are not supported in Tier 1")
    if node.elems.len != 2:
      raiseLottie(cliSchemaViolation, target, capability, "expected [x, y]")
    return (
      finiteNumber(node.elems[0], target, capability),
      finiteNumber(node.elems[1], target, capability),
    )
  raiseLottie(cliUnsupportedFeature, target, capability, "animated channels are not supported in Tier 1")


proc requireScalar(node: JsonNode; target, capability: string; defaultValue: float64): float64 =
  if node.isNil:
    return defaultValue
  if node.kind in {JInt, JFloat}:
    return finiteNumber(node, target, capability)
  raiseLottie(cliUnsupportedFeature, target, capability, "animated channels are not supported in Tier 1")


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
    raiseLottie(cliUnsupportedFeature, target, "opacity", "non-default opacity is not serializable in Tier 1")
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
      raiseLottie(cliSchemaViolation, target, "duplicateAsset", "duplicate asset id: " & id)
    let path = requiredString(asset, "path", target)
    if not path.pathIsSafeRelative:
      raiseLottie(cliSchemaViolation, target, "assetPath", "asset path must be safe and relative")
    if assetsDir.len > 0 and not fileExists(assetsDir / path):
      raiseLottie(cliInvalidReference, target, "assetPath", "missing external image file: " & path)
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
    raiseLottie(cliUnsupportedFeature, target, result.kind, "only image layers are supported in Tier 1")
  let blend = optionalString(layerObject, "blend", "normal", target)
  if blend != "normal":
    raiseLottie(cliUnsupportedFeature, target, "blend", "only normal blend is supported in Tier 1")
  let compIn = finiteNumber(requireField(composition, "ip", "composition"), "composition", "ip")
  let compOut = finiteNumber(requireField(composition, "op", "composition"), "composition", "op")
  let layerIn = if layerObject.hasKey("in"): finiteNumber(layerObject["in"], target, "in") else: compIn
  let layerOut = if layerObject.hasKey("out"): finiteNumber(layerObject["out"], target, "out") else: compOut
  if layerIn != compIn or layerOut != compOut:
    raiseLottie(cliUnsupportedFeature, target, "visibility", "visibility intervals are not supported in Tier 1")
  if layerObject.hasKey("shapes"):
    raiseLottie(cliUnsupportedFeature, target, "shape", "shape layers require Tier 2")

  let parent = optionalParentReference(layerObject, "parent", target)
  result.parent = parent.name
  result.parentIndex = parent.index
  result.parentIsIndex = parent.isIndex
  result.transform = parseTransform(if layerObject.hasKey("transform"): layerObject["transform"] else: nil, target)
  if not layerObject.hasKey("image"):
    raiseLottie(cliSchemaViolation, target, "image", "image layer requires image payload")
  let image = requireObject(layerObject["image"], target & ".image")
  validateKeys(image, ["asset", "anchor", "size"], target & ".image")
  result.imageAsset = requiredString(image, "asset", target & ".image")
  if result.imageAsset notin assets:
    raiseLottie(cliInvalidReference, target, "asset", "unknown image asset: " & result.imageAsset)
  let asset = assets[result.imageAsset]
  if image.hasKey("anchor"):
    let anchor = requireVector2(image["anchor"], target, "image.anchor", 0.0, 0.0)
    if anchor.x != 0.0 or anchor.y != 0.0:
      raiseLottie(cliUnsupportedFeature, target, "image.anchor", "image payload anchor is not supported in Tier 1")
  if image.hasKey("size"):
    let size = requireVector2(image["size"], target, "image.size", asset.width, asset.height)
    if size.x <= 0.0 or size.y <= 0.0:
      raiseLottie(cliSchemaViolation, target, "image.size", "image size must be positive")
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
    raiseLottie(cliSchemaViolation, "composition", "json", "invalid JSON: " & exc.msg)
  let compositionObject = requireObject(root, "composition")
  validateKeys(compositionObject, ["w", "h", "fr", "ip", "op", "assets", "layers"], "composition")
  result.width = positiveInt(requireField(compositionObject, "w", "composition"), "composition", "w")
  result.height = positiveInt(requireField(compositionObject, "h", "composition"), "composition", "h")
  result.frameRate = finiteNumber(requireField(compositionObject, "fr", "composition"), "composition", "fr")
  if result.frameRate <= 0.0:
    raiseLottie(cliSchemaViolation, "composition", "fr", "frame rate must be positive")
  result.inFrame = finiteNumber(requireField(compositionObject, "ip", "composition"), "composition", "ip")
  result.outFrame = finiteNumber(requireField(compositionObject, "op", "composition"), "composition", "op")
  if result.outFrame <= result.inFrame:
    raiseLottie(cliSchemaViolation, "composition", "duration", "op must be greater than ip")
  if not compositionObject.hasKey("layers"):
    raiseLottie(cliSchemaViolation, "composition", "layers", "layers are required")
  let assets = parseAssets(compositionObject, assetsDir)
  let layers = requireArray(compositionObject["layers"], "layers")
  var names = initHashSet[string]()
  for index, item in layers.elems:
    let layer = parseLayer(item, index, compositionObject, assets)
    if layer.name in names:
      raiseLottie(cliSchemaViolation, "layers[" & $index & "]", "duplicateName", "duplicate layer name: " & layer.name)
    names.incl(layer.name)
    result.layers.add layer
  if result.layers.len == 0:
    raiseLottie(cliSchemaViolation, "composition", "layers", "at least one layer is required")
  for index, layer in result.layers:
    if layer.parentIsIndex:
      if layer.parentIndex >= 0 and layer.parentIndex < result.layers.len:
        result.layers[index].parent = result.layers[layer.parentIndex].name
      else:
        raiseLottie(cliInvalidReference, "layers[" & $index & "]", "parent", "unknown parent index: " & $layer.parentIndex)
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
        raiseLottie(cliInvalidReference, "layers[" & $index & "]", "parent", "unknown parent: " & layer.parent)
  var parentByName = initTable[string, string]()
  for layer in result.layers:
    parentByName[layer.name] = layer.parent
  for layer in result.layers:
    var seen = initHashSet[string]()
    var current = layer.name
    while current.len > 0:
      if current in seen:
        raiseLottie(cliCycleDetected, layer.name, "parent", "parent graph contains a cycle")
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
    raiseLottie(cliCycleDetected, layer.name, "parent", "parent graph contains a cycle")
  visiting.incl layer.name
  if layer.parent.len > 0:
    if layer.parent notin nameToIndex:
      raiseLottie(cliInvalidReference, layer.name, "parent", "unknown parent: " & layer.parent)
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
      if origin notin validOrigins:
        raiseLottie(cliSchemaViolation, "cli", "origin", originErrMsg)
      index += 2
    of "--reject-shapes":
      index += 1
    of "--rasterize-shapes":
      raiseLottie(cliUnsupportedFeature, "cli", "rasterize-shapes", "shape rasterization requires Tier 2")
    of "--atlas-out":
      raiseLottie(cliUnsupportedFeature, "cli", "atlas", "atlas output requires Tier 2")
    else:
      quit(usage(), QuitFailure)
  if assetsDir.len == 0:
    raiseLottie(cliSchemaViolation, "cli", "assets-dir", "--assets-dir is required")
  let composition = parseLottieComposition(readFile(inputPath), assetsDir)
  let data = composition.toSkeletonData(origin)
  writeFile(outputPath, toBonyJson(data))



# ===== DragonBones Importer =====
# Clean-room implementation per docs/dragonbones-importer-design.md.
# DragonBones field names (skX, skY, scX, scY, etc.) are used only at the
# parser boundary and must not appear in bony runtime objects.

type
  DbTransform = object
    x: float64
    y: float64
    skX: float64  # degrees; DragonBones two-angle bone parameterization
    skY: float64  # degrees
    scX: float64
    scY: float64

  DbDisplayKind = enum
    dbkImage, dbkMesh, dbkBoundingBox, dbkUnsupported

  DbDisplay = object
    name: string
    kind: DbDisplayKind
    transform: DbTransform

  DbSkinSlotEntry = object
    slotName: string
    displays: seq[DbDisplay]

  DbSkin = object
    name: string
    slotEntries: seq[DbSkinSlotEntry]

  DbBoneEntry = object
    name: string
    parent: string
    transform: DbTransform

  DbSlotEntry = object
    name: string
    parent: string
    displayIndex: int
    blendMode: string

  DbFrameEase = object
    hasTweenEasing: bool
    tweenEasing: float64
    hasCurve: bool
    curve: seq[float64]

  DbTranslateFrame = object
    duration: int
    x: float64
    y: float64
    easing: DbFrameEase

  DbRotateFrame = object
    duration: int
    rotate: float64
    hasClockwise: bool
    clockwise: int
    easing: DbFrameEase

  DbScaleFrame = object
    duration: int
    x: float64
    y: float64
    easing: DbFrameEase

  DbBoneAnimationEntry = object
    name: string
    translateFrames: seq[DbTranslateFrame]
    rotateFrames: seq[DbRotateFrame]
    scaleFrames: seq[DbScaleFrame]

  DbAnimation = object
    name: string
    duration: int
    bones: seq[DbBoneAnimationEntry]

  DbArmature = object
    name: string
    frameRate: int
    bones: seq[DbBoneEntry]
    slots: seq[DbSlotEntry]
    skins: seq[DbSkin]
    animations: seq[DbAnimation]
    hasAnimation: bool


proc dbOptFloat(node: JsonNode; key: string; defaultVal: float64; target: string): float64 =
  if not node.hasKey(key):
    return defaultVal
  let v = node[key]
  json_schema.requireNumber(v, target, key, raiseDbSchema,
    message = "expected number for " & key,
    finiteMessage = key & " must be finite")


proc dbRequireString(node: JsonNode; key, target: string): string =
  let value = json_schema.requireField(node, key, target, raiseDbSchema)
  if value.kind != JString:
    raiseDb(cliSchemaViolation, target, key, "expected string for " & key)
  let s = value.getStr()
  if s.len == 0:
    raiseDb(cliSchemaViolation, target, key, "required field must be non-empty: " & key)
  s


proc dbOptString(node: JsonNode; key, defaultVal, target: string): string =
  json_schema.optionalString(node, key, defaultVal, target, raiseDbSchema,
    message = "expected string for " & key)


proc dbRequirePositiveInt(node: JsonNode; key, target: string): int =
  json_schema.requirePositiveInt(
    json_schema.requireField(node, key, target, raiseDbSchema),
    target,
    key,
    raiseDbSchema,
    message = "expected integer for " & key,
    positiveMessage = key & " must be positive",
  )


proc dbRequireNonNegativeInt(node: JsonNode; key, target: string): int =
  let value = json_schema.requireField(node, key, target, raiseDbSchema)
  if value.kind != JInt:
    raiseDb(cliSchemaViolation, target, key, "expected integer for " & key)
  let v = value.getInt()
  if v < 0:
    raiseDb(cliSchemaViolation, target, key, key & " must be non-negative")
  v


proc dbOptInt(node: JsonNode; key: string; defaultVal: int; target: string): int =
  if not node.hasKey(key):
    return defaultVal
  if node[key].kind != JInt:
    raiseDb(cliSchemaViolation, target, key, "expected integer for " & key)
  node[key].getInt()


proc dbOptNullableFloat(node: JsonNode; key: string; target: string): tuple[present: bool; value: float64] =
  if not node.hasKey(key):
    return (false, 0.0)
  let v = node[key]
  if v.kind == JNull:
    return (false, 0.0)
  let f = json_schema.requireNumber(v, target, key, raiseDbSchema,
    message = "expected number or null for " & key,
    finiteMessage = key & " must be finite")
  (true, f)


proc parseDbFrameEase(node: JsonNode; target: string): DbFrameEase =
  let (hasTween, tween) = dbOptNullableFloat(node, "tweenEasing", target)
  if hasTween and tween != 0.0:
    raiseDb(cliUnsupportedFeature, target, "tweenEasing",
      "non-zero tweenEasing not supported in Tier 1")
  result.hasTweenEasing = hasTween
  result.tweenEasing = tween
  if node.hasKey("curve"):
    if node["curve"].kind != JArray:
      raiseDb(cliSchemaViolation, target, "curve", "expected array for curve")
    if node["curve"].elems.len != 4:
      raiseDb(cliSchemaViolation, target, "curve", "curve must contain exactly four numbers")
    result.hasCurve = true
    for ci, item in node["curve"].elems:
      if item.kind notin {JInt, JFloat}:
        raiseDb(cliSchemaViolation, target & ".curve[" & $ci & "]", "curve",
          "expected number in curve")
      let f = item.getFloat()
      if classify(f) in {fcNan, fcInf, fcNegInf}:
        raiseDb(cliSchemaViolation, target & ".curve[" & $ci & "]", "curve",
          "curve value must be finite")
      result.curve.add f
    raiseDb(cliUnsupportedFeature, target, "curve", "Bezier curve easing not supported in Tier 1")


proc parseDbTransform(node: JsonNode; target: string): DbTransform =
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "transform", "expected object for TransformObject")
  for key in node.keys:
    if key notin ["x", "y", "skX", "skY", "scX", "scY"]:
      raiseDb(cliSchemaViolation, target, key, "unknown key in TransformObject: " & key)
  result.x = dbOptFloat(node, "x", 0.0, target)
  result.y = dbOptFloat(node, "y", 0.0, target)
  result.skX = dbOptFloat(node, "skX", 0.0, target)
  result.skY = dbOptFloat(node, "skY", 0.0, target)
  result.scX = dbOptFloat(node, "scX", 1.0, target)
  result.scY = dbOptFloat(node, "scY", 1.0, target)
  if result.scX == 0.0:
    raiseDb(cliSchemaViolation, target, "scX", "scX must not be zero")
  if result.scY == 0.0:
    raiseDb(cliSchemaViolation, target, "scY", "scY must not be zero")
  if result.scX < 0.0 or result.scY < 0.0:
    raiseDb(cliUnsupportedFeature, target, "negativeScale", "negative scale not supported in Tier 1")


proc parseDbDisplay(node: JsonNode; index: int; slotName: string): DbDisplay =
  let target = "skin.slot[" & slotName & "].display[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected display object")
  result.name = dbRequireString(node, "name", target)
  let typStr = dbOptString(node, "type", "image", target)
  case typStr
  of "image":
    result.kind = dbkImage
  of "mesh":
    raiseDb(cliUnsupportedFeature, target, "mesh", "mesh displays not supported in Tier 1")
  of "boundingBox":
    raiseDb(cliUnsupportedFeature, target, "boundingBox", "bounding-box displays not supported in Tier 1")
  else:
    raiseDb(cliUnsupportedFeature, target, typStr, "display type not supported in Tier 1: " & typStr)
  if node.hasKey("transform"):
    if node["transform"].kind != JObject:
      raiseDb(cliSchemaViolation, target, "transform", "expected transform object")
    let t = parseDbTransform(node["transform"], target & ".transform")
    if t.x != 0.0 or t.y != 0.0 or t.skX != 0.0 or t.skY != 0.0 or
       t.scX != 1.0 or t.scY != 1.0:
      raiseDb(cliUnsupportedFeature, target, "displayTransform",
        "non-identity display transform not supported in Tier 1")
    result.transform = t
  else:
    result.transform = DbTransform(scX: 1.0, scY: 1.0)


proc parseDbTranslateFrame(node: JsonNode; index: int; boneName, animName: string): DbTranslateFrame =
  let target = "animation[" & animName & "].bone[" & boneName & "].translateFrame[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected translateFrame object")
  for key in node.keys:
    if key notin ["duration", "x", "y", "tweenEasing", "curve"]:
      raiseDb(cliSchemaViolation, target, key, "unknown key in translateFrame: " & key)
  result.duration = dbRequireNonNegativeInt(node, "duration", target)
  result.x = dbOptFloat(node, "x", 0.0, target)
  result.y = dbOptFloat(node, "y", 0.0, target)
  result.easing = parseDbFrameEase(node, target)


proc parseDbRotateFrame(node: JsonNode; index: int; boneName, animName: string): DbRotateFrame =
  let target = "animation[" & animName & "].bone[" & boneName & "].rotateFrame[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected rotateFrame object")
  for key in node.keys:
    if key notin ["duration", "rotate", "clockwise", "tweenEasing", "curve"]:
      raiseDb(cliSchemaViolation, target, key, "unknown key in rotateFrame: " & key)
  result.duration = dbRequireNonNegativeInt(node, "duration", target)
  result.rotate = dbOptFloat(node, "rotate", 0.0, target)
  if node.hasKey("clockwise"):
    result.hasClockwise = true
    result.clockwise = dbOptInt(node, "clockwise", 0, target)
    if result.clockwise notin [0, 1]:
      raiseDb(cliSchemaViolation, target, "clockwise", "clockwise must be 0 or 1")
    raiseDb(cliUnsupportedFeature, target, "clockwise",
      "clockwise rotation hints not supported in Tier 1")
  result.easing = parseDbFrameEase(node, target)


proc parseDbScaleFrame(node: JsonNode; index: int; boneName, animName: string): DbScaleFrame =
  let target = "animation[" & animName & "].bone[" & boneName & "].scaleFrame[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected scaleFrame object")
  for key in node.keys:
    if key notin ["duration", "x", "y", "tweenEasing", "curve"]:
      raiseDb(cliSchemaViolation, target, key, "unknown key in scaleFrame: " & key)
  result.duration = dbRequireNonNegativeInt(node, "duration", target)
  result.x = dbOptFloat(node, "x", 1.0, target)
  result.y = dbOptFloat(node, "y", 1.0, target)
  result.easing = parseDbFrameEase(node, target)


proc parseDbBoneAnimationEntry(node: JsonNode; index: int; animName: string): DbBoneAnimationEntry =
  let target = "animation[" & animName & "].bone[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected bone animation object")
  for key in node.keys:
    if key notin ["name", "translateFrame", "rotateFrame", "scaleFrame"]:
      raiseDb(cliSchemaViolation, target, key, "unknown key in bone animation: " & key)
  result.name = dbRequireString(node, "name", target)
  if node.hasKey("translateFrame"):
    if node["translateFrame"].kind != JArray:
      raiseDb(cliSchemaViolation, target, "translateFrame", "expected translateFrame array")
    for fi, frame in node["translateFrame"].elems:
      result.translateFrames.add parseDbTranslateFrame(frame, fi, result.name, animName)
  if node.hasKey("rotateFrame"):
    if node["rotateFrame"].kind != JArray:
      raiseDb(cliSchemaViolation, target, "rotateFrame", "expected rotateFrame array")
    for fi, frame in node["rotateFrame"].elems:
      result.rotateFrames.add parseDbRotateFrame(frame, fi, result.name, animName)
  if node.hasKey("scaleFrame"):
    if node["scaleFrame"].kind != JArray:
      raiseDb(cliSchemaViolation, target, "scaleFrame", "expected scaleFrame array")
    for fi, frame in node["scaleFrame"].elems:
      result.scaleFrames.add parseDbScaleFrame(frame, fi, result.name, animName)


proc validateDbChannelDurations(
  channelName, target: string;
  animationDuration: int;
  durations: openArray[int];
) =
  if durations.len == 0:
    return
  if durations[^1] != 0:
    raiseDb(cliSchemaViolation, target, channelName,
      channelName & " must end with a zero-duration terminator frame")
  var total = 0
  for duration in durations:
    total += duration
  if total != animationDuration:
    raiseDb(cliSchemaViolation, target, channelName,
      channelName & " duration sum " & $total &
      " does not match animation duration " & $animationDuration)


proc validateDbAnimationChannels(anim: DbAnimation; boneNames: HashSet[string]) =
  var seenBones = initHashSet[string]()
  for bone in anim.bones:
    let target = "animation[" & anim.name & "].bone[" & bone.name & "]"
    if bone.name notin boneNames:
      raiseDb(cliInvalidReference, bone.name, "bone",
        "animation references unknown bone: " & bone.name)
    if bone.name in seenBones:
      # Duplicate entries would emit conflicting timelines for the same
      # target/kind, which the mixer resolves last-writer-wins — a silent drop.
      raiseDb(cliSchemaViolation, target, "bone",
        "duplicate bone entry in animation: " & bone.name)
    seenBones.incl(bone.name)

    var translateDurations: seq[int]
    for frame in bone.translateFrames:
      translateDurations.add frame.duration
    validateDbChannelDurations("translateFrame", target, anim.duration, translateDurations)

    var rotateDurations: seq[int]
    for frame in bone.rotateFrames:
      rotateDurations.add frame.duration
    validateDbChannelDurations("rotateFrame", target, anim.duration, rotateDurations)

    var scaleDurations: seq[int]
    for frame in bone.scaleFrames:
      scaleDurations.add frame.duration
    validateDbChannelDurations("scaleFrame", target, anim.duration, scaleDurations)


proc parseDbAnimation(node: JsonNode; index: int; boneNames: HashSet[string]): DbAnimation =
  let target = "animation[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected animation object")
  for key in node.keys:
    if key in ["fadeInTime", "playTimes", "blendType", "type", "frame", "ffd"]:
      raiseDb(cliUnsupportedFeature, target, key,
        "animation field not supported in Tier 1: " & key)
    if key notin ["name", "duration", "bone", "slot"]:
      raiseDb(cliSchemaViolation, target, key, "unknown key in animation: " & key)
  result.name = dbRequireString(node, "name", target)
  result.duration = dbRequireNonNegativeInt(node, "duration", target)
  if node.hasKey("bone"):
    if node["bone"].kind != JArray:
      raiseDb(cliSchemaViolation, target, "bone", "expected bone animation array")
    for bi, boneNode in node["bone"].elems:
      result.bones.add parseDbBoneAnimationEntry(boneNode, bi, result.name)
  if node.hasKey("slot") and node["slot"].kind != JArray:
    raiseDb(cliSchemaViolation, target, "slot", "expected slot animation array")
  if node.hasKey("slot") and node["slot"].elems.len > 0:
    raiseDb(cliUnsupportedFeature, target, "slot",
      "slot animation channels not supported in Tier 1")
  validateDbAnimationChannels(result, boneNames)


proc parseDbSkinSlotEntry(node: JsonNode; index: int; skinName: string): DbSkinSlotEntry =
  let target = "skin[" & skinName & "].slot[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected skin slot object")
  result.slotName = dbRequireString(node, "name", target)
  if node.hasKey("display"):
    if node["display"].kind != JArray:
      raiseDb(cliSchemaViolation, target, "display", "expected display array")
    for di, disp in node["display"].elems:
      result.displays.add parseDbDisplay(disp, di, result.slotName)


proc parseDbSkin(node: JsonNode; index: int): DbSkin =
  let target = "skin[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected skin object")
  result.name = dbOptString(node, "name", "", target)
  if node.hasKey("slot"):
    if node["slot"].kind != JArray:
      raiseDb(cliSchemaViolation, target, "slot", "expected slot array")
    for si, slotNode in node["slot"].elems:
      result.slotEntries.add parseDbSkinSlotEntry(slotNode, si, result.name)


proc parseDbSlot(node: JsonNode; index: int): DbSlotEntry =
  let target = "slot[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected slot object")
  result.name = dbRequireString(node, "name", target)
  result.parent = dbRequireString(node, "parent", target)
  let di = dbOptInt(node, "displayIndex", 0, target)
  if di < 0:
    raiseDb(cliUnsupportedFeature, target, "displayIndex",
      "displayIndex -1 (hidden slot) not supported in Tier 1")
  result.displayIndex = di
  let blendMode = dbOptString(node, "blendMode", "normal", target)
  if blendMode != "normal":
    raiseDb(cliUnsupportedFeature, target, "blendMode",
      "blend mode not supported in Tier 1: " & blendMode)
  result.blendMode = blendMode


proc parseDbBone(node: JsonNode; index: int): DbBoneEntry =
  let target = "bone[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected bone object")
  result.name = dbRequireString(node, "name", target)
  result.parent = dbOptString(node, "parent", "", target)
  if node.hasKey("transform"):
    if node["transform"].kind != JObject:
      raiseDb(cliSchemaViolation, target, "transform", "expected transform object")
    result.transform = parseDbTransform(node["transform"], target & ".transform")
  else:
    result.transform = DbTransform(scX: 1.0, scY: 1.0)


proc validateAndSortBones(bones: seq[DbBoneEntry]; armatureName: string): seq[DbBoneEntry] =
  # Two-pass validation: collect all names, then validate parents.
  var allNames = initHashSet[string]()
  for bone in bones:
    if bone.name in allNames:
      raiseDb(cliSchemaViolation, armatureName, "bone.name", "duplicate bone name: " & bone.name)
    allNames.incl(bone.name)

  for bone in bones:
    if bone.parent.len > 0 and bone.parent notin allNames:
      raiseDb(cliInvalidReference, bone.name, "parent", "unknown parent bone: " & bone.parent)

  # Count roots (bones with no parent).
  var roots: seq[string] = @[]
  for bone in bones:
    if bone.parent.len == 0:
      roots.add(bone.name)
  if roots.len == 0:
    raiseDb(cliSchemaViolation, armatureName, "root", "armature must have exactly one root bone")
  if roots.len > 1:
    raiseDb(cliSchemaViolation, armatureName, "root",
      "armature has multiple root bones: " & roots.join(", "))

  # Cycle check via path-following.
  var parentMap = initTable[string, string]()
  for bone in bones:
    parentMap[bone.name] = bone.parent
  for bone in bones:
    var seen = initHashSet[string]()
    var current = bone.name
    while current.len > 0:
      if current in seen:
        raiseDb(cliCycleDetected, bone.name, "parent", "bone parent chain contains a cycle")
      seen.incl(current)
      current = parentMap.getOrDefault(current, "")

  # Topological sort: emit bones in parent-before-child order for bony.
  var ordered: seq[DbBoneEntry] = @[]
  var emitted = initHashSet[string]()
  var pending = bones
  while pending.len > 0:
    let before = pending.len
    var next: seq[DbBoneEntry] = @[]
    for bone in pending:
      if bone.parent.len == 0 or bone.parent in emitted:
        ordered.add(bone)
        emitted.incl(bone.name)
      else:
        next.add(bone)
    pending = next
    if pending.len == before:
      raiseDb(cliCycleDetected, armatureName, "parent", "bone ordering cycle detected")
  ordered


proc parseDbArmature(node: JsonNode; index: int; parseAnimations = true): DbArmature =
  let target = "armature[" & $index & "]"
  if node.kind != JObject:
    raiseDb(cliSchemaViolation, target, "object", "expected armature object")
  result.name = dbRequireString(node, "name", target)
  result.frameRate = dbRequirePositiveInt(node, "frameRate", target)
  let typStr = dbRequireString(node, "type", target)
  if typStr != "Armature":
    raiseDb(cliUnsupportedFeature, target, "type",
      "armature type not supported: " & typStr & " (only \"Armature\" is supported)")
  if not node.hasKey("bone"):
    raiseDb(cliSchemaViolation, target, "bone", "missing required field: bone")
  if node["bone"].kind != JArray:
    raiseDb(cliSchemaViolation, target, "bone", "expected bone array")

  var rawBones: seq[DbBoneEntry] = @[]
  for bi, boneNode in node["bone"].elems:
    rawBones.add parseDbBone(boneNode, bi)
  if rawBones.len == 0:
    raiseDb(cliSchemaViolation, target, "bone", "armature must have at least one bone")
  result.bones = validateAndSortBones(rawBones, result.name)
  var boneNames = initHashSet[string]()
  for bone in result.bones:
    boneNames.incl(bone.name)

  if node.hasKey("slot") and node["slot"].kind == JArray:
    for si, slotNode in node["slot"].elems:
      let slotEntry = parseDbSlot(slotNode, si)
      # Validate slot parent references a bone.
      var found = false
      for bone in result.bones:
        if bone.name == slotEntry.parent:
          found = true
          break
      if not found:
        raiseDb(cliInvalidReference, slotEntry.name, "parent",
          "slot parent bone not found: " & slotEntry.parent)
      result.slots.add slotEntry

  if node.hasKey("skin") and node["skin"].kind == JArray:
    for ski, skinNode in node["skin"].elems:
      let skin = parseDbSkin(skinNode, ski)
      result.skins.add skin

  if node.hasKey("animation"):
    if node["animation"].kind != JArray:
      raiseDb(cliSchemaViolation, target, "animation", "expected animation array")
    result.hasAnimation = node["animation"].elems.len > 0
    if parseAnimations:
      # The bony JSON loader rejects duplicate animation names, so admitting
      # them here would write an output file our own tooling cannot load.
      var animNames = initHashSet[string]()
      for ai, animNode in node["animation"].elems:
        let anim = parseDbAnimation(animNode, ai, boneNames)
        if anim.name in animNames:
          raiseDb(cliSchemaViolation, "animation[" & anim.name & "]", "name",
            "duplicate animation name: " & anim.name)
        animNames.incl(anim.name)
        result.animations.add anim


proc parseDbSkeleton(text: string; parseAnimations = true): DbArmature =
  # Returns the first armature; caller handles multi-armature policy.
  var root: JsonNode
  try:
    root = parseJson(text)
  except JsonParsingError as exc:
    raiseDb(cliSchemaViolation, "skeleton", "json", "invalid JSON: " & exc.msg)
  if root.kind != JObject:
    raiseDb(cliSchemaViolation, "skeleton", "object", "expected top-level object")
  if not root.hasKey("version"):
    raiseDb(cliSchemaViolation, "skeleton", "version", "missing required field: version")
  if root["version"].kind != JString:
    raiseDb(cliSchemaViolation, "skeleton", "version", "version must be a string")
  let version = root["version"].getStr()
  if not version.startsWith("5."):
    raiseDb(cliUnsupportedVersion, "skeleton", "version",
      "unsupported DragonBones version: " & version & " (only 5.x is supported)")
  if not root.hasKey("armature"):
    raiseDb(cliSchemaViolation, "skeleton", "armature", "missing required field: armature")
  if root["armature"].kind != JArray:
    raiseDb(cliSchemaViolation, "skeleton", "armature", "armature must be an array")
  let armatures = root["armature"].elems
  if armatures.len == 0:
    raiseDb(cliSchemaViolation, "skeleton", "armature", "armature array must not be empty")
  # Return first armature; caller emits multipleArmatures diagnostic if needed.
  result = parseDbArmature(armatures[0], 0, parseAnimations)


proc countArmatures(text: string): int =
  var root: JsonNode
  try:
    root = parseJson(text)
  except JsonParsingError:
    return 0
  if root.kind != JObject or not root.hasKey("armature"):
    return 0
  if root["armature"].kind != JArray:
    return 0
  root["armature"].elems.len


proc extraArmatureNames(text: string): seq[string] =
  var root: JsonNode
  try:
    root = parseJson(text)
  except JsonParsingError:
    return @[]
  if root.kind != JObject or not root.hasKey("armature"):
    return @[]
  if root["armature"].kind != JArray:
    return @[]
  let elems = root["armature"].elems
  if elems.len <= 1:
    return @[]
  for i in 1 ..< elems.len:
    let n = elems[i]
    if n.kind == JObject and n.hasKey("name") and n["name"].kind == JString:
      result.add(n["name"].getStr())
    else:
      result.add("armature[" & $i & "]")


proc dbTransformToLocal(t: DbTransform): LocalTransform =
  # Skew decomposition per docs/dragonbones-importer-design.md §Skew Decomposition.
  # rotation = -skY, shearX = 0 (canonical), shearY = skY - skX
  # x unchanged; y negated (Y-down → Y-up coordinate flip)
  let rotation = -t.skY       # degrees
  let shearY = t.skY - t.skX  # degrees
  localTransform(
    x = t.x,
    y = -t.y,
    rotation = rotation,
    scaleX = t.scX,
    scaleY = t.scY,
    shearX = 0.0,
    shearY = shearY,
  )


proc resolveImageDims(displayName, assetsDir: string): tuple[w, h: float64] =
  let ext = if '.' in displayName: "" else: ".png"
  let path = assetsDir / displayName & ext
  if not fileExists(path):
    raiseDb(cliMissingAsset, displayName, "assetPath", "image not found under --assets-dir: " & path)
  try:
    let img = decodeImage(readFile(path))
    result = (float64(img.width), float64(img.height))
  except PixieError:
    raiseDb(cliMissingAsset, displayName, "assetPath", "could not decode image: " & path)


proc armatureToSkeletonData(
  armature: DbArmature;
  assetsDir: string;
): SkeletonData =
  var bones: seq[BoneData] = @[]
  var slots: seq[SlotData] = @[]
  var regions: seq[RegionAttachment] = @[]
  var regionNames = initHashSet[string]()
  var regionDims = initTable[string, tuple[w, h: float64]]()

  # Build bones in topological order (already sorted by validateAndSortBones).
  for bone in armature.bones:
    bones.add boneData(bone.name, bone.parent, dbTransformToLocal(bone.transform))

  # Find default skin (empty name preferred, else first skin).
  var defaultSkin: DbSkin
  var hasSkin = false
  for skin in armature.skins:
    if skin.name == "" or (not hasSkin):
      defaultSkin = skin
      hasSkin = true
      if skin.name == "":
        break

  # Build slot/attachment lookup from skin.
  var skinSlotMap = initTable[string, DbSkinSlotEntry]()
  if hasSkin:
    for slotEntry in defaultSkin.slotEntries:
      skinSlotMap[slotEntry.slotName] = slotEntry

  # Build slots in draw order (as declared).
  for dbSlot in armature.slots:
    var attachmentName = ""
    if skinSlotMap.hasKey(dbSlot.name):
      let skinEntry = skinSlotMap[dbSlot.name]
      if skinEntry.displays.len > 0:
        let di = dbSlot.displayIndex
        if di >= skinEntry.displays.len:
          raiseDb(cliSchemaViolation, dbSlot.name, "displayIndex",
            "displayIndex " & $di & " out of range (display count: " & $skinEntry.displays.len & ")")
        let display = skinEntry.displays[di]
        attachmentName = display.name
        if attachmentName notin regionNames:
          var w, h: float64
          if assetsDir.len == 0:
            raiseDb(cliMissingAsset, display.name, "assetPath",
              "--assets-dir required to resolve image: " & display.name)
          else:
            (w, h) = resolveImageDims(display.name, assetsDir)
          regions.add regionAttachment(display.name, w, h)
          regionNames.incl(display.name)
          regionDims[display.name] = (w, h)
        else:
          let prev = regionDims[display.name]
          var w, h: float64
          if assetsDir.len > 0:
            (w, h) = resolveImageDims(display.name, assetsDir)
          if assetsDir.len > 0 and (w, h) != prev:
            raiseDb(cliSchemaViolation, display.name, "regionDims",
              "display name reused with conflicting dimensions: " & display.name)
    slots.add slotData(dbSlot.name, dbSlot.parent, attachmentName)

  let headerName = armature.name & " (DragonBones import)"
  skeletonData(skeletonHeader(headerName, "5.x"), bones, slots, regions)


proc dbFrameTime(frameOffset, frameRate: int): float64 =
  frameOffset.float64 / frameRate.float64


proc dbTimelineCurve(easing: DbFrameEase): TimelineCurve =
  if easing.hasTweenEasing:
    linearTimelineCurve
  else:
    steppedTimelineCurve


proc dbBoneMap(armature: DbArmature): Table[string, DbBoneEntry] =
  for bone in armature.bones:
    result[bone.name] = bone


proc ensureDbEmittableFrameTime(
  channelName, boneName, animName: string;
  frameIndex, frameCount, duration: int;
) =
  if duration == 0 and frameIndex != frameCount - 1:
    raiseDb(cliSchemaViolation, "animation[" & animName & "].bone[" & boneName & "]",
      channelName, channelName & " contains a zero-duration frame before the terminator")


proc dbTranslateTimeline(
  bone: DbBoneEntry;
  animName: string;
  frames: openArray[DbTranslateFrame];
  frameRate: int;
): BoneTimeline =
  let target = "animation[" & animName & "].bone[" & bone.name & "]"
  try:
    var keys: seq[Vector2Keyframe]
    var frameOffset = 0
    for index, frame in frames:
      ensureDbEmittableFrameTime("translateFrame", bone.name, animName, index, frames.len, frame.duration)
      let curve = dbTimelineCurve(frame.easing)
      keys.add vector2Keyframe(
        dbFrameTime(frameOffset, frameRate),
        bone.transform.x + frame.x,
        -(bone.transform.y + frame.y),
        curveX = curve,
        curveY = curve,
      )
      frameOffset += frame.duration
    result = boneVectorTimeline(bone.name, translateTimeline, keys)
  except BonyLoadError as exc:
    raiseDb(cliSchemaViolation, target, "translateFrame", exc.msg)


proc dbRotateTimeline(
  bone: DbBoneEntry;
  animName: string;
  frames: openArray[DbRotateFrame];
  frameRate: int;
): BoneTimeline =
  let target = "animation[" & animName & "].bone[" & bone.name & "]"
  try:
    var keys: seq[ScalarKeyframe]
    var frameOffset = 0
    for index, frame in frames:
      ensureDbEmittableFrameTime("rotateFrame", bone.name, animName, index, frames.len, frame.duration)
      keys.add scalarKeyframe(
        dbFrameTime(frameOffset, frameRate),
        -(bone.transform.skY + frame.rotate),
        curve = dbTimelineCurve(frame.easing),
      )
      frameOffset += frame.duration
    result = boneScalarTimeline(bone.name, rotateTimeline, keys)
  except BonyLoadError as exc:
    raiseDb(cliSchemaViolation, target, "rotateFrame", exc.msg)


proc dbScaleTimeline(
  bone: DbBoneEntry;
  animName: string;
  frames: openArray[DbScaleFrame];
  frameRate: int;
): BoneTimeline =
  let target = "animation[" & animName & "].bone[" & bone.name & "]"
  try:
    var keys: seq[Vector2Keyframe]
    var frameOffset = 0
    for index, frame in frames:
      ensureDbEmittableFrameTime("scaleFrame", bone.name, animName, index, frames.len, frame.duration)
      let curve = dbTimelineCurve(frame.easing)
      keys.add vector2Keyframe(
        dbFrameTime(frameOffset, frameRate),
        bone.transform.scX * frame.x,
        bone.transform.scY * frame.y,
        curveX = curve,
        curveY = curve,
      )
      frameOffset += frame.duration
    result = boneVectorTimeline(bone.name, scaleTimeline, keys)
  except BonyLoadError as exc:
    raiseDb(cliSchemaViolation, target, "scaleFrame", exc.msg)


proc addDbAnimationClip(
  armature: DbArmature;
  data: SkeletonData;
  anim: DbAnimation;
  clips: var seq[AnimationClip];
) =
  let bones = dbBoneMap(armature)
  var timelines: seq[BoneTimeline]
  for animBone in anim.bones:
    let bone = bones[animBone.name]
    if animBone.translateFrames.len > 0:
      timelines.add dbTranslateTimeline(bone, anim.name, animBone.translateFrames, armature.frameRate)
    if animBone.rotateFrames.len > 0:
      timelines.add dbRotateTimeline(bone, anim.name, animBone.rotateFrames, armature.frameRate)
    if animBone.scaleFrames.len > 0:
      timelines.add dbScaleTimeline(bone, anim.name, animBone.scaleFrames, armature.frameRate)

  if timelines.len == 0:
    raiseDb(cliUnsupportedFeature, "animation[" & anim.name & "]", "animation",
      "animation has no supported Tier 1 bone timelines")
  try:
    clips.add animationClip(data, anim.name, timelines)
  except BonyLoadError as exc:
    raiseDb(cliSchemaViolation, "animation[" & anim.name & "]", "animation", exc.msg)


proc dbAnimationsToClips(armature: DbArmature; data: SkeletonData): seq[AnimationClip] =
  for anim in armature.animations:
    addDbAnimationClip(armature, data, anim, result)


proc importDragonbones(args: seq[string]) =
  if args.len < 2:
    quit(usage(), QuitFailure)
  let inputPath = args[0]
  let outputPath = args[1]
  var assetsDir = ""
  var setupOnly = false
  var allowMultipleArmatures = false
  var index = 2
  while index < args.len:
    case args[index]
    of "--assets-dir":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      assetsDir = args[index + 1]
      index += 2
    of "--setup-only":
      setupOnly = true
      index += 1
    of "--allow-multiple-armatures":
      allowMultipleArmatures = true
      index += 1
    else:
      quit(usage(), QuitFailure)

  let text = readFile(inputPath)
  let armatureCount = countArmatures(text)
  if armatureCount > 1:
    let extra = extraArmatureNames(text)
    let msg = "bony: multipleArmatures ignored=" & extra.join(",")
    if not allowMultipleArmatures:
      quit(msg, QuitFailure)
    else:
      stderr.writeLine(msg)

  let armature = parseDbSkeleton(text, parseAnimations = not setupOnly)
  if setupOnly and armature.hasAnimation:
    stderr.writeLine("bony: --setup-only: animation suppressed for " & armature.name)
  let data = armatureToSkeletonData(armature, assetsDir)
  let animations = dbAnimationsToClips(armature, data)
  if animations.len > 0:
    writeFile(outputPath, toBonyJson(bonyAsset(data, animations)))
  else:
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


# `defaultParameterSamples`, `effectiveDeformers`, and
# `applyDeformersToDrawBatches` now live in the exported runtime module
# `bony/deform/drawbatch_deform` (re-exported via `bony`) so library consumers
# share the CLI's deformer-application stage. The CLI delegates to them below.


proc deformerJson(rec: DeformerRecord; samples: seq[ParameterSample]): JsonNode =
  result = newJObject()
  result["id"] = newJString(rec.deformer.id)
  if rec.deformer.parent.len > 0:
    result["parent"] = newJString(rec.deformer.parent)
  result["order"] = newJInt(int(rec.deformer.order))
  case rec.deformer.kind
  of warpDeformerKind:
    result["kind"] = newJString("warp")
    var pts: seq[DeformerPoint]
    if rec.keyformBlend.axes.len > 0 and rec.keyformBlend.keyforms.len > 0:
      pts = sampleKeyformPoints(rec.keyformBlend, samples)
    else:
      pts = rec.deformer.warp.controlPoints
    var cpArr = newJArray()
    for pt in pts:
      var cpNode = newJObject()
      cpNode["x"] = newJFloat(pt.x)
      cpNode["y"] = newJFloat(pt.y)
      cpArr.add cpNode
    result["controlPoints"] = cpArr
  of rotationDeformerKind:
    result["kind"] = newJString("rotation")
    let rot = rec.deformer.rotation
    var rotNode = newJObject()
    rotNode["pivotX"] = newJFloat(rot.pivotX)
    rotNode["pivotY"] = newJFloat(rot.pivotY)
    rotNode["angleDegrees"] = newJFloat(rot.angleDegrees)
    rotNode["scaleX"] = newJFloat(rot.scaleX)
    rotNode["scaleY"] = newJFloat(rot.scaleY)
    rotNode["opacity"] = newJFloat(rot.opacity)
    result["rotation"] = rotNode


proc validateBonyKeys(node: JsonNode; allowed: openArray[string]; context: string) =
  if node.kind != JObject:
    raise newBonyLoadError(schemaViolation, context & " must be an object")
  for key in node.keys:
    var found = false
    for allowedKey in allowed:
      if key == allowedKey:
        found = true
        break
    if not found:
      raise newBonyLoadError(schemaViolation, context & "." & key & " is not a recognized field")


proc requireScriptObject(node: JsonNode; context: string): JsonNode =
  json_schema.requireObject(node, context, raiseBonySchema,
    message = context & " must be an object")


proc requireScriptArray(node: JsonNode; context: string): JsonNode =
  json_schema.requireArray(node, context, raiseBonySchema,
    message = context & " must be an array")


proc scriptString(node: JsonNode; key, context: string; required = false): string =
  if not node.hasKey(key):
    if required:
      raise newBonyLoadError(schemaViolation, context & "." & key & " is required")
    return ""
  result = json_schema.optionalString(node, key, "", context, raiseBonySchema,
    message = context & "." & key & " must be a string")
  if required and result.len == 0:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must not be empty")


proc scriptTime(node: JsonNode; key, context: string): float64 =
  let value = json_schema.requireField(node, key, context, raiseBonySchema,
    message = context & "." & key & " is required")
  result = quantizeF32(
    json_schema.requireNumberType(value, context, key, raiseBonySchema,
      message = context & "." & key & " must be a number"),
    context & "." & key,
  )
  if result < 0:
    raise newBonyLoadError(schemaViolation, context & "." & key & " must be non-negative")


proc scriptFloat(node: JsonNode; key, context: string): float64 =
  let value = json_schema.requireField(node, key, context, raiseBonySchema,
    message = context & "." & key & " is required")
  quantizeF32(
    json_schema.requireNumberType(value, context, key, raiseBonySchema,
      message = context & "." & key & " must be a number"),
    context & "." & key,
  )


proc scriptSafeRelativeAsset(value, context: string) =
  if value.len == 0:
    raise newBonyLoadError(schemaViolation, context & " must not be empty")
  if value.isAbsolute or value.contains(".."):
    raise newBonyLoadError(schemaViolation, context & " must be a safe relative asset path")


proc parsePointerKind(value, context: string): StateMachineListenerKind =
  case value
  of "pointerDown": pointerDownListener
  of "pointerUp": pointerUpListener
  of "pointerEnter": pointerEnterListener
  of "pointerExit": pointerExitListener
  of "pointerMove": pointerMoveListener
  else:
    raise newBonyLoadError(schemaViolation, context & ".kind must be a pointer listener kind")


proc safeSampleName(name: string): bool =
  if name.len == 0:
    return false
  var hasNonDigit = false
  for ch in name:
    if not (ch in {'a'..'z', 'A'..'Z', '0'..'9', '_', '-', '.'}):
      return false
    if ch notin {'0'..'9'}:
      hasNonDigit = true
  if not hasNonDigit:
    return false
  true


proc parseInputScript(path: string): InputScript =
  let text = readFile(path)
  rejectDuplicateObjectKeys(text)
  let parsed =
    try:
      parseJson(text)
    except JsonParsingError as exc:
      raise newBonyLoadError(schemaViolation, "invalid input script JSON: " & exc.msg)

  let root = requireScriptObject(parsed, "inputScript")
  validateBonyKeys(root, ["format", "asset", "stateMachine", "activeSkin", "children", "samples"], "inputScript")
  if scriptString(root, "format", "inputScript", required = true) != "bony.input-script.v1":
    raise newBonyLoadError(schemaViolation, "inputScript.format must be bony.input-script.v1")
  result.asset = scriptString(root, "asset", "inputScript", required = true)
  scriptSafeRelativeAsset(result.asset, "inputScript.asset")
  result.stateMachine = scriptString(root, "stateMachine", "inputScript")
  result.activeSkin = scriptString(root, "activeSkin", "inputScript")
  if result.activeSkin.len == 0:
    result.activeSkin = "default"

  if root.hasKey("children"):
    let childrenObj = requireScriptObject(root["children"], "inputScript.children")
    for skeletonId, childNode in childrenObj.pairs:
      if skeletonId.len == 0:
        raise newBonyLoadError(schemaViolation, "inputScript.children key must not be empty")
      let childContext = "inputScript.children." & skeletonId
      let childObj = requireScriptObject(childNode, childContext)
      validateBonyKeys(childObj, ["asset", "binaryAsset"], childContext)
      let childAsset = scriptString(childObj, "asset", childContext, required = true)
      scriptSafeRelativeAsset(childAsset, childContext & ".asset")
      let childBinaryAsset = scriptString(childObj, "binaryAsset", childContext)
      if childBinaryAsset.len > 0:
        scriptSafeRelativeAsset(childBinaryAsset, childContext & ".binaryAsset")
      result.children.add InputScriptChild(
        skeleton: skeletonId,
        asset: childAsset,
        binaryAsset: childBinaryAsset,
      )

  if not root.hasKey("samples"):
    raise newBonyLoadError(schemaViolation, "inputScript.samples is required")
  let samplesNode = requireScriptArray(root["samples"], "inputScript.samples")
  if samplesNode.elems.len == 0:
    raise newBonyLoadError(schemaViolation, "inputScript.samples must not be empty")

  for sampleIndex, item in samplesNode.elems:
    let context = "inputScript.samples[" & $sampleIndex & "]"
    let sampleObj = requireScriptObject(item, context)
    validateBonyKeys(sampleObj, ["name", "t", "inputs", "pointer"], context)
    var sample = InputScriptSample(
      name: scriptString(sampleObj, "name", context),
      time: scriptTime(sampleObj, "t", context),
    )
    if sample.name.len > 0 and not sample.name.safeSampleName:
      raise newBonyLoadError(schemaViolation, context & ".name must contain only letters, digits, _, -, or . and must not be numeric-only")
    if sampleObj.hasKey("inputs"):
      let inputsObj = requireScriptObject(sampleObj["inputs"], context & ".inputs")
      for inputName, inputValue in inputsObj.pairs:
        if inputName.len == 0:
          raise newBonyLoadError(schemaViolation, context & ".inputs key must not be empty")
        case inputValue.kind
        of JBool:
          sample.inputs.add ScriptInput(name: inputName, kind: scriptBoolInput, boolValue: inputValue.getBool())
        of JInt, JFloat:
          sample.inputs.add ScriptInput(
            name: inputName,
            kind: scriptNumberInput,
            numberValue: quantizeF32(inputValue.getFloat(), context & ".inputs." & inputName),
          )
        of JString:
          if inputValue.getStr() != "fire":
            raise newBonyLoadError(schemaViolation, context & ".inputs." & inputName & " string value must be \"fire\"")
          sample.inputs.add ScriptInput(name: inputName, kind: scriptTriggerInput)
        else:
          raise newBonyLoadError(schemaViolation, context & ".inputs." & inputName & " must be bool, number, or \"fire\"")
    if sampleObj.hasKey("pointer"):
      let pointerObj = requireScriptObject(sampleObj["pointer"], context & ".pointer")
      validateBonyKeys(pointerObj, ["kind", "x", "y"], context & ".pointer")
      sample.pointer = ScriptPointer(
        kind: parsePointerKind(scriptString(pointerObj, "kind", context & ".pointer", required = true), context & ".pointer"),
        x: scriptFloat(pointerObj, "x", context & ".pointer"),
        y: scriptFloat(pointerObj, "y", context & ".pointer"),
      )
      sample.hasPointer = true
    result.samples.add sample


proc validateStateMachineScript(script: InputScript; machineName: string) =
  if machineName.len == 0:
    raise newBonyLoadError(schemaViolation, "state-machine execution requires --state-machine or inputScript.stateMachine")
  if script.children.len > 0:
    raise newBonyLoadError(schemaViolation, "inputScript.children is only valid for setup-pose scripts")
  var names = initHashSet[string]()
  var previousTime = 0.0
  for index, sample in script.samples:
    if sample.name.len == 0:
      raise newBonyLoadError(schemaViolation, "state-machine input-script samples require name")
    if sample.name in names:
      raise newBonyLoadError(duplicateKey, "duplicate input-script sample name: " & sample.name)
    names.incl(sample.name)
    if index > 0 and sample.time < previousTime:
      raise newBonyLoadError(schemaViolation, "state-machine input-script sample times must be non-decreasing")
    previousTime = sample.time


proc resolveStateMachineName(cliName: string; script: InputScript): string =
  result = cliName
  if result.len == 0:
    result = script.stateMachine
  elif script.stateMachine.len > 0 and script.stateMachine != result:
    raise newBonyLoadError(schemaViolation, "--state-machine does not match inputScript.stateMachine")


proc selectStateMachine(machines: openArray[StateMachine]; name: string): StateMachine =
  for machine in machines:
    if machine.name == name:
      return machine
  raise newBonyLoadError(unknownRequiredReference, "unknown state machine: " & name)


proc selectAnimation(animations: openArray[AnimationClip]; name: string): AnimationClip =
  for clip in animations:
    if clip.name == name:
      return clip
  raise newBonyLoadError(unknownRequiredReference, "unknown animation: " & name)


proc applyScriptInputs(runtime: var StateMachineRuntime; inputs: openArray[ScriptInput]) =
  for input in inputs:
    case input.kind
    of scriptBoolInput:
      runtime.setBoolInput(input.name, input.boolValue)
    of scriptNumberInput:
      runtime.setNumberInput(input.name, input.numberValue)
    of scriptTriggerInput:
      runtime.fireTrigger(input.name)


proc sampleMatches(sample: InputScriptSample; index: int; selector: string): bool =
  if selector.len == 0:
    return true
  var parsedIndex: int
  let consumed = parseInt(selector, parsedIndex)
  if consumed == selector.len:
    return index == parsedIndex
  sample.name == selector


proc regionNames(data: SkeletonData): HashSet[string] =
  result = initHashSet[string]()
  for region in data.regions:
    result.incl(region.name)


proc sequenceAttachmentName(attachment: string; index: uint32): string =
  if attachment.len == 0:
    return attachment
  var suffixStart = attachment.len
  while suffixStart > 0 and attachment[suffixStart - 1].isDigit:
    dec suffixStart
  let suffix =
    if suffixStart == attachment.len:
      $index
    else:
      align($index, attachment.len - suffixStart, '0')
  attachment[0 ..< suffixStart] & suffix


proc applySequencePose(data: SkeletonData; pose: MixedPose): SkeletonData =
  if pose.sequences.len == 0:
    return data

  var sequenceLookup = initTable[string, MixedSequence]()
  for value in pose.sequences:
    sequenceLookup[value.target] = value

  let knownRegions = data.regionNames()
  var slots: seq[SlotData]
  for slot in data.slots:
    var attachment = slot.attachment
    if slot.name in sequenceLookup:
      let sequence = sequenceLookup[slot.name]
      attachment = sequenceAttachmentName(attachment, sequence.value.index)
      if attachment.len > 0 and attachment notin knownRegions:
        raise newBonyLoadError(
          unknownRequiredReference,
          "unknown sequence frame attachment for slot " & slot.name & ": " & attachment,
        )
    slots.add slotData(slot.name, slot.bone, attachment)

  # Preserve meshAttachments/clippingAttachments AND the transient deform
  # override so a sequence-rebuilt pose still carries an animated mesh's deltas
  # through to buildDrawBatches (applySequencePose rebuilds SkeletonData a second
  # time after applyPose; without this the override would be silently dropped).
  skeletonData(
    data.header,
    data.bones,
    slots,
    data.regions,
    data.pathAttachments,
    data.paths,
    data.parameters,
    data.deformers,
    data.ikConstraints,
    data.transformConstraints,
    data.physicsConstraints,
    data.clippingAttachments,
    data.meshAttachments,
    data.skins,
  ).withDeformOverrides(data.deformOverrides)


proc applyRenderablePose(data: SkeletonData; pose: MixedPose): SkeletonData =
  data.applyPose(pose).applySequencePose(pose)


proc executeStateMachineScript(
  assetPath, stateMachineName, scriptPath, selector: string;
): seq[StateMachineRunSample] =
  let script = parseInputScript(scriptPath)
  let assetName = extractFilename(assetPath)
  let scriptComparableAsset =
    if assetName.toLowerAscii.endsWith(".bnb"):
      assetName.changeFileExt(".bony")
    else:
      assetName
  if scriptComparableAsset != script.asset:
    raise newBonyLoadError(schemaViolation, "inputScript.asset does not match input asset")
  let machineName = resolveStateMachineName(stateMachineName, script)
  validateStateMachineScript(script, machineName)

  let asset =
    if assetPath.toLowerAscii.endsWith(".bnb"):
      loadBonyBnbAsset(readBytes(assetPath))
    else:
      loadBonyJsonAsset(readFile(assetPath))
  let data = asset.skeleton
  var dataRef = new(SkeletonData)
  dataRef[] = data
  var runtime = initStateMachineRuntime(selectStateMachine(asset.stateMachines, machineName))
  # Physics is bony's only stateful, time-dependent constraint: the story runner
  # is the single time driver, so its per-sample inter-sample delta is the dt the
  # physics stage advances by. `physicsStates` carries PhysicsConstraintState
  # across every sample (advanced even for unmatched samples) so a re-run that
  # selects a late sample reproduces the same continuous trajectory. With no
  # physics constraints advancePhysics is exactly computeWorldTransforms, so
  # existing (physics-free) story goldens are unchanged.
  var physicsStates = newPhysicsStates(data)
  # Event-timeline dispatch bridge (docs/event-timeline-contract.md "Dispatch
  # output channel"). The clip mixer's event dispatch is never reached along the
  # state-machine story path — the SM runner steps layer time and samples poses
  # directly, it never drives an AnimationState. So we mirror each layer's active
  # clip onto its own single-track AnimationState and advance that track by the
  # same per-sample delta the state machine is advanced by. `AnimationState.update`
  # resets its event list every call, so the events collected per sample are
  # exactly the events fired in that inter-sample window (the incremental,
  # reset-per-sample parity contract prompts 29/30 depend on) — never the
  # cumulative [0, t] window. A state transition reloads that layer's track (time
  # reset to 0), mirroring the SM layer-time reset.
  var layerAnimStates = newSeq[AnimationState](runtime.layers.len)
  for animState in layerAnimStates.mitems:
    animState = animationState()
  var layerLoadedStates = newSeq[string](runtime.layers.len)
  # Previous post-update layer time, per layer. Layer time is monotonic
  # non-decreasing (dt is non-negative and looping never resets it), so a
  # decrease can only mean a state transition reset layer time to 0 — including
  # a self-transition (A->A), which is legal and keeps the state name unchanged.
  # We detect that reset by time, not by name, so a self-transition still reloads
  # the mirrored track instead of silently desyncing it forever.
  var layerPrevTimes = newSeq[float64](runtime.layers.len)
  var previousTime = 0.0
  var matched = false
  for index, sample in script.samples:
    runtime.clearEvents()
    runtime.applyScriptInputs(sample.inputs)
    if sample.hasPointer:
      let pointerEvaluated = runtime.evaluate(dataRef)
      let pointerPosed = data.applyRenderablePose(pointerEvaluated.pose)
      if not pointerPosed.hasSkin(script.activeSkin):
        raise newBonyLoadError(unknownRequiredReference, "unknown active skin: " & script.activeSkin)
      let pointerWorlds = computeWorldTransforms(pointerPosed, script.activeSkin)
      runtime.dispatchPointerListeners(
        pointerPosed,
        pointerWorlds,
        script.activeSkin,
        sample.pointer.kind,
        sample.pointer.x,
        sample.pointer.y,
      )
    runtime.update(sample.time - previousTime, preserveEvents = true)
    let evaluated = runtime.evaluate(dataRef)
    let posed = data.applyRenderablePose(evaluated.pose)
    if not posed.hasSkin(script.activeSkin):
      raise newBonyLoadError(unknownRequiredReference, "unknown active skin: " & script.activeSkin)
    let worlds = advancePhysics(posed, physicsStates, sample.time - previousTime, script.activeSkin)
    var sampleEvents: seq[DispatchedEvent]
    for layerIndex in 0 ..< runtime.layers.len:
      let layerRt = runtime.layers[layerIndex]
      let active = layerRt.currentState()
      let layerTimeReset = layerRt.time < layerPrevTimes[layerIndex]
      layerPrevTimes[layerIndex] = layerRt.time
      if active.kind != clipState:
        # A 1D blend has no single owning clip; event dispatch across a blend is
        # out of scope for this slice. Disarm so a later clip re-entry reloads.
        layerLoadedStates[layerIndex] = ""
        continue
      # Reload the mirrored track on a state change OR a same-name layer-time
      # reset (self-transition). Note: a transition observed here is a hard cut —
      # the outgoing clip's events in this sample's partial pre-transition window
      # are intentionally NOT dispatched, matching the SM's instantaneous pose
      # evaluation and layer-time reset (the incremental parity contract prompts
      # 29/30 reproduce). Only the post-update active clip dispatches.
      if layerLoadedStates[layerIndex] != active.name or layerTimeReset:
        layerAnimStates[layerIndex].setAnimation(0, active.clip, active.loop)
        layerLoadedStates[layerIndex] = active.name
      # Advance this layer's track to the SM layer's post-update (raw) time. In
      # steady state this is the inter-sample step; right after a (re)load the
      # track sits at 0 and advances to the post-reset layer time.
      let amount = max(0.0, layerRt.time - layerAnimStates[layerIndex].tracks[0].current.time)
      layerAnimStates[layerIndex].update(amount)
      for dispatched in layerAnimStates[layerIndex].events:
        sampleEvents.add dispatched
    if sample.sampleMatches(index, selector):
      matched = true
      result.add StateMachineRunSample(
        machine: machineName,
        activeSkin: script.activeSkin,
        sample: sample,
        runtime: runtime,
        evaluated: evaluated,
        posedData: posed,
        worlds: worlds,
        animationEvents: sampleEvents,
      )
    previousTime = sample.time
  if not matched:
    raise newBonyLoadError(unknownRequiredReference, "unknown input-script sample: " & selector)


proc resolveInputScriptAssetPath(scriptPath, assetName: string): string =
  let scriptDir = parentDir(scriptPath)
  normalizedPath(scriptDir / ".." / "assets" / assetName)


proc validateSetupPoseScript(script: InputScript) =
  if script.stateMachine.len > 0:
    raise newBonyLoadError(schemaViolation, "setup-pose input scripts must not declare stateMachine")
  var names = initHashSet[string]()
  for index, sample in script.samples:
    if sample.time != 0.0:
      raise newBonyLoadError(schemaViolation, "setup-pose input-script samples require t=0")
    if sample.inputs.len > 0:
      raise newBonyLoadError(schemaViolation, "setup-pose input-script samples must not declare inputs")
    if sample.hasPointer:
      raise newBonyLoadError(schemaViolation, "setup-pose input-script samples must not declare pointer")
    if sample.name.len > 0:
      if sample.name in names:
        raise newBonyLoadError(duplicateKey, "duplicate input-script sample name: " & sample.name)
      names.incl(sample.name)


proc loadInputScriptChildren(
  scriptPath: string;
  script: InputScript;
  preferBinary: bool;
): NestedSkeletonMap =
  result = initTable[string, SkeletonData]()
  for child in script.children:
    let childAsset =
      if preferBinary:
        if child.binaryAsset.len == 0:
          raise newBonyLoadError(
            unknownRequiredReference,
            "missing binary child asset for nested skeleton: " & child.skeleton,
          )
        child.binaryAsset
      else:
        child.asset
    let path = resolveInputScriptAssetPath(scriptPath, childAsset)
    if not fileExists(path):
      raise newBonyLoadError(
        unknownRequiredReference,
        "nested child asset not found for " & child.skeleton & ": " & childAsset,
      )
    if path.toLowerAscii.endsWith(".bnb"):
      result[child.skeleton] = loadBonyBnb(readBytes(path))
    else:
      result[child.skeleton] = loadBonyJson(readFile(path))


proc executeSetupPoseScript(
  assetPath, scriptPath, selector: string;
): tuple[data: SkeletonData; time: float64; activeSkin: string; children: NestedSkeletonMap] =
  let script = parseInputScript(scriptPath)
  let assetName = extractFilename(assetPath)
  let scriptComparableAsset =
    if assetName.toLowerAscii.endsWith(".bnb"):
      assetName.changeFileExt(".bony")
    else:
      assetName
  if scriptComparableAsset != script.asset:
    raise newBonyLoadError(schemaViolation, "inputScript.asset does not match input asset")
  validateSetupPoseScript(script)

  var matched = false
  var selected = InputScriptSample()
  for index, sample in script.samples:
    if sample.sampleMatches(index, selector):
      if matched:
        raise newBonyLoadError(schemaViolation, "--sample must select exactly one input-script sample")
      matched = true
      selected = sample
  if not matched:
    raise newBonyLoadError(unknownRequiredReference, "unknown input-script sample: " & selector)

  let data = loadInputSkeleton(assetPath)
  let children = loadInputScriptChildren(scriptPath, script, assetPath.toLowerAscii.endsWith(".bnb"))
  (data: data, time: selected.time, activeSkin: script.activeSkin, children: children)


proc boneTimelineKindJson(kind: BoneTimelineKind): string =
  case kind
  of rotateTimeline: "rotate"
  of translateTimeline: "translate"
  of translateXTimeline: "translateX"
  of translateYTimeline: "translateY"
  of scaleTimeline: "scale"
  of scaleXTimeline: "scaleX"
  of scaleYTimeline: "scaleY"
  of shearTimeline: "shear"
  of shearXTimeline: "shearX"
  of shearYTimeline: "shearY"
  of inheritTimeline: "inherit"


proc slotTimelineKindJson(kind: SlotTimelineKind): string =
  case kind
  of attachmentTimeline: "attachment"
  of rgbaTimeline: "rgba"
  of rgbTimeline: "rgb"
  of alphaTimeline: "alpha"
  of rgba2Timeline: "rgba2"
  of sequenceTimeline: "sequence"


proc transformModeJson(mode: TransformMode): string =
  case mode
  of normal: "normal"
  of onlyTranslation: "onlyTranslation"
  of noRotationOrReflection: "noRotationOrReflection"
  of noScale: "noScale"
  of noScaleOrReflection: "noScaleOrReflection"


proc inputKindJson(kind: StateMachineInputKind): string =
  case kind
  of boolInput: "bool"
  of numberInput: "number"
  of triggerInput: "trigger"


proc listenerKindJson(kind: StateMachineListenerKind): string =
  case kind
  of stateEnterListener: "stateEnter"
  of stateExitListener: "stateExit"
  of transitionListener: "transition"
  of pointerDownListener: "pointerDown"
  of pointerUpListener: "pointerUp"
  of pointerEnterListener: "pointerEnter"
  of pointerExitListener: "pointerExit"
  of pointerMoveListener: "pointerMove"


proc pointerHelperTargetKindJson(kind: PointerHelperTargetKind): string =
  case kind
  of pointHelperTarget: "point"
  of boundingBoxHelperTarget: "boundingBox"


proc colorJson(color: timelines.ColorRgba): JsonNode =
  result = newJObject()
  result["r"] = newJFloat(color.r)
  result["g"] = newJFloat(color.g)
  result["b"] = newJFloat(color.b)
  result["a"] = newJFloat(color.a)


proc defaultRenderSlotStates(data: SkeletonData): Table[string, RenderSlotState] =
  result = initTable[string, RenderSlotState]()
  for slot in data.slots:
    result[slot.name] = RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0)


proc renderSlotStates(data: SkeletonData; pose: MixedPose): Table[string, RenderSlotState] =
  result = data.defaultRenderSlotStates()
  for value in pose.colors:
    var state = result.getOrDefault(value.target, RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
    case value.kind
    of rgbTimeline:
      state.r = value.color.r
      state.g = value.color.g
      state.b = value.color.b
    of alphaTimeline:
      state.a = value.color.a
    of rgbaTimeline:
      state.r = value.color.r
      state.g = value.color.g
      state.b = value.color.b
      state.a = value.color.a
    else:
      discard
    result[value.target] = state

  for value in pose.colors2:
    var state = result.getOrDefault(value.target, RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
    state.r = value.color.light.r
    state.g = value.color.light.g
    state.b = value.color.light.b
    state.a = value.color.light.a
    state.hasDark = true
    state.darkR = value.color.darkR
    state.darkG = value.color.darkG
    state.darkB = value.color.darkB
    result[value.target] = state

  for value in pose.sequences:
    var state = result.getOrDefault(value.target, RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
    state.hasSequence = true
    state.sequenceIndex = value.value.index
    state.sequenceDelay = value.value.delay
    state.sequenceMode = value.value.mode
    result[value.target] = state


proc applyRenderSlotStates(batches: seq[DrawBatch]; states: Table[string, RenderSlotState]): seq[DrawBatch] =
  result = batches
  for batchIndex in 0 ..< result.len:
    if result[batchIndex].slot notin states:
      continue
    let state = states[result[batchIndex].slot]
    for vertexIndex in 0 ..< result[batchIndex].vertices.len:
      result[batchIndex].vertices[vertexIndex].r = state.r
      result[batchIndex].vertices[vertexIndex].g = state.g
      result[batchIndex].vertices[vertexIndex].b = state.b
      result[batchIndex].vertices[vertexIndex].a = state.a


proc poseJson(pose: MixedPose): JsonNode =
  result = newJObject()
  var scalars = newJArray()
  for value in pose.scalars:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["kind"] = newJString(boneTimelineKindJson(value.kind))
    node["value"] = newJFloat(value.value)
    scalars.add node
  result["scalars"] = scalars

  var vectors = newJArray()
  for value in pose.vectors:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["kind"] = newJString(boneTimelineKindJson(value.kind))
    node["x"] = newJFloat(value.x)
    node["y"] = newJFloat(value.y)
    vectors.add node
  result["vectors"] = vectors

  var attachments = newJArray()
  for value in pose.attachments:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["attachment"] = newJString(value.attachment)
    attachments.add node
  result["attachments"] = attachments

  var inherits = newJArray()
  for value in pose.inherits:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["inheritRotation"] = newJBool(value.value.inheritRotation)
    node["inheritScale"] = newJBool(value.value.inheritScale)
    node["inheritReflection"] = newJBool(value.value.inheritReflection)
    node["transformMode"] = newJString(transformModeJson(value.value.transformMode))
    inherits.add node
  result["inherits"] = inherits

  var colors = newJArray()
  for value in pose.colors:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["kind"] = newJString(slotTimelineKindJson(value.kind))
    node["color"] = colorJson(value.color)
    colors.add node
  result["colors"] = colors

  var colors2 = newJArray()
  for value in pose.colors2:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["light"] = colorJson(value.color.light)
    node["darkR"] = newJFloat(value.color.darkR)
    node["darkG"] = newJFloat(value.color.darkG)
    node["darkB"] = newJFloat(value.color.darkB)
    colors2.add node
  result["colors2"] = colors2

  var sequences = newJArray()
  for value in pose.sequences:
    var node = newJObject()
    node["target"] = newJString(value.target)
    node["index"] = newJInt(int(value.value.index))
    node["delay"] = newJFloat(value.value.delay)
    node["mode"] = newJString($value.value.mode)
    sequences.add node
  result["sequences"] = sequences


proc stateMachineInputsJson(runtime: StateMachineRuntime): JsonNode =
  result = newJArray()
  for value in runtime.inputs:
    var node = newJObject()
    node["name"] = newJString(value.name)
    node["kind"] = newJString(inputKindJson(value.kind))
    case value.kind
    of boolInput:
      node["value"] = newJBool(value.boolValue)
    of numberInput:
      node["value"] = newJFloat(value.numberValue)
    of triggerInput:
      node["value"] = newJBool(value.boolValue)
    result.add node


proc stateMachineLayersJson(evaluated: EvaluatedStateMachine): JsonNode =
  result = newJArray()
  for layer in evaluated.layers:
    var node = newJObject()
    node["name"] = newJString(layer.layer)
    node["state"] = newJString(layer.state)
    node["time"] = newJFloat(layer.time)
    node["pose"] = poseJson(layer.pose)
    result.add node


proc stateMachineEventsJson(runtime: StateMachineRuntime): JsonNode =
  result = newJArray()
  for event in runtime.events:
    var node = newJObject()
    node["listener"] = newJString(event.listener)
    node["kind"] = newJString(listenerKindJson(event.kind))
    if event.hasPointer:
      node["slot"] = newJString(event.slot)
      node["targetKind"] = newJString(pointerHelperTargetKindJson(event.targetKind))
      node["target"] = newJString(event.target)
      node["input"] = newJString(event.input)
      node["inputKind"] = newJString(inputKindJson(event.inputKind))
      case event.inputKind
      of boolInput:
        node["boolValue"] = newJBool(event.boolValue)
      of numberInput:
        node["numberValue"] = newJFloat(event.numberValue)
      of triggerInput:
        node["triggerValue"] = newJBool(event.triggerValue)
      node["pointerX"] = newJFloat(event.pointerX)
      node["pointerY"] = newJFloat(event.pointerY)
    else:
      node["layer"] = newJString(event.layer)
      node["fromState"] = newJString(event.fromState)
      node["toState"] = newJString(event.toState)
    result.add node


proc animationEventsJson(events: seq[DispatchedEvent]): JsonNode =
  ## Clip-dispatched events surfaced under the numeric golden's distinct
  ## `animationEvents` channel (docs/event-timeline-contract.md "Dispatch output
  ## channel"); flattens each DispatchedEvent + its EventData. Kept separate from
  ## the M8 state-machine listener `events` array.
  result = newJArray()
  for dispatched in events:
    var node = newJObject()
    node["name"] = newJString(dispatched.event.name)
    node["trackIndex"] = newJInt(dispatched.trackIndex)
    node["time"] = newJFloat(dispatched.time)
    node["intValue"] = newJInt(int(dispatched.event.intValue))
    node["floatValue"] = newJFloat(dispatched.event.floatValue)
    node["stringValue"] = newJString(dispatched.event.stringValue)
    node["audioPath"] = newJString(dispatched.event.audioPath)
    node["volume"] = newJFloat(dispatched.event.volume)
    node["balance"] = newJFloat(dispatched.event.balance)
    result.add node


proc numericGoldenJson(
    data: SkeletonData;
    time: float64;
    activeSkin = "default";
    state: StateMachineGolden = StateMachineGolden();
    physicsWorlds: seq[Affine2] = @[];
    animationEvents: seq[DispatchedEvent] = @[];
    children: NestedSkeletonMap = initTable[string, SkeletonData]();
): string =
  validateSkeletonData(data)
  if not data.hasSkin(activeSkin):
    raise newBonyLoadError(unknownRequiredReference, "unknown active skin: " & activeSkin)
  # The story runner advances the stateful physics stage and threads the
  # physics-adjusted bone worlds in via `physicsWorlds`; setup-pose callers pass
  # none and fall back to the pure world-transform pass. For a physics-free rig
  # the two are identical (advancePhysics == computeWorldTransforms).
  let worlds =
    if physicsWorlds.len == data.bones.len: physicsWorlds
    else: computeWorldTransforms(data)
  # Thread the (possibly physics-adjusted) worlds into the draw-batch build so
  # draw-batch vertices reflect the physics stage. For a physics-free rig these
  # worlds equal the pure pass, so setup-pose callers are unaffected.
  let baseBatches =
    if children.len > 0:
      buildNestedDrawBatches(data, worlds, children, activeSkin)
    else:
      buildDrawBatches(data, worlds, activeSkin)
  let samples = defaultParameterSamples(data)
  let efDefs = effectiveDeformers(data, samples)
  var batches = applyDeformersToDrawBatches(baseBatches, efDefs)
  let slotStates =
    if state.present:
      renderSlotStates(data, state.evaluated.pose)
    else:
      defaultRenderSlotStates(data)
  batches = applyRenderSlotStates(batches, slotStates)
  var root = newJObject()
  root["format"] = newJString("bony.numeric-golden.v1")
  root["skeleton"] = newJString(data.header.name)
  root["version"] = newJString(data.header.version)
  root["time"] = newJFloat(time)
  if state.present:
    root["stateMachine"] = newJString(state.machine)
    root["sample"] = newJString(state.sample)
    root["inputs"] = stateMachineInputsJson(state.runtime)
    root["layers"] = stateMachineLayersJson(state.evaluated)
    root["events"] = stateMachineEventsJson(state.runtime)
  # Distinct clip-dispatched-event channel; omitted when empty (setup-pose
  # callers, and story samples whose inter-sample window fired nothing).
  if animationEvents.len > 0:
    root["animationEvents"] = animationEventsJson(animationEvents)

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
    let slotState = slotStates.getOrDefault(slot.name, RenderSlotState(r: 1.0, g: 1.0, b: 1.0, a: 1.0))
    node["r"] = newJFloat(slotState.r)
    node["g"] = newJFloat(slotState.g)
    node["b"] = newJFloat(slotState.b)
    node["a"] = newJFloat(slotState.a)
    if slotState.hasDark:
      node["darkR"] = newJFloat(slotState.darkR)
      node["darkG"] = newJFloat(slotState.darkG)
      node["darkB"] = newJFloat(slotState.darkB)
    if slotState.hasSequence:
      node["sequenceIndex"] = newJInt(int(slotState.sequenceIndex))
      node["sequenceDelay"] = newJFloat(slotState.sequenceDelay)
      node["sequenceMode"] = newJString($slotState.sequenceMode)
    slots.add node
  root["slots"] = slots

  if data.deformers.len > 0:
    var defArray = newJArray()
    for rec in data.deformers:
      defArray.add deformerJson(rec, samples)
    root["deformers"] = defArray

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
  var timeSet = false
  var animationName = ""
  var stateMachine = ""
  var inputScript = ""
  var sampleSelector = ""
  var index = 2
  while index < args.len:
    case args[index]
    of "--t":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      time = parseFloatArg(args[index + 1], "--t")
      timeSet = true
      index += 2
    of "--animation":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      animationName = args[index + 1]
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
    of "--sample":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      sampleSelector = args[index + 1]
      index += 2
    else:
      quit(usage(), QuitFailure)
  if stateMachine.len != 0 or inputScript.len != 0 or sampleSelector.len != 0:
    if animationName.len != 0:
      raise newBonyLoadError(
        schemaViolation,
        "--animation cannot be combined with --state-machine, --input-script, or --sample",
      )
    if inputScript.len == 0:
      raise newBonyLoadError(schemaViolation, "golden-gen script execution requires --input-script")
    if sampleSelector.len == 0:
      raise newBonyLoadError(schemaViolation, "golden-gen script execution requires --sample")
    if timeSet:
      raise newBonyLoadError(schemaViolation, "--t cannot be combined with --input-script; use sample t values in the script")
    let parsedScript = parseInputScript(inputScript)
    if stateMachine.len != 0 or parsedScript.stateMachine.len != 0:
      let samples = executeStateMachineScript(args[0], stateMachine, inputScript, sampleSelector)
      if samples.len != 1:
        raise newBonyLoadError(schemaViolation, "--sample must select exactly one input-script sample")
      let sample = samples[0]
      writeFile(args[1], numericGoldenJson(
        sample.posedData,
        sample.sample.time,
        sample.activeSkin,
        StateMachineGolden(
          present: true,
          machine: sample.machine,
          sample: sample.sample.name,
          runtime: sample.runtime,
          evaluated: sample.evaluated,
        ),
        sample.worlds,
        sample.animationEvents,
      ))
    else:
      let setup = executeSetupPoseScript(args[0], inputScript, sampleSelector)
      writeFile(args[1], numericGoldenJson(
        setup.data,
        setup.time,
        setup.activeSkin,
        children = setup.children,
      ))
    return

  if animationName.len != 0:
    let asset = loadInputAsset(args[0])
    let clip = selectAnimation(asset.animations, animationName)
    var dataRef = new(SkeletonData)
    dataRef[] = asset.skeleton
    var animation = animationState(dataRef, 1)
    animation.setAnimation(0, clip)
    animation.update(time)
    let posed = asset.skeleton.applyRenderablePose(animation.sample())
    writeFile(args[1], numericGoldenJson(posed, time, animationEvents = animation.events))
    return

  requireSetupPoseTime(time)
  let data = loadInputSkeleton(args[0])
  writeFile(args[1], numericGoldenJson(data, time))


proc renderSetupPose(args: seq[string]) =
  if args.len < 3:
    quit(usage(), QuitFailure)

  let inputPath = args[0]
  var outputPath = ""
  var time = 0.0
  var timeSet = false
  var width = 256
  var height = 256
  var stateMachine = ""
  var inputScript = ""
  var origin = "center"
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
      timeSet = true
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
    of "--origin":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      origin = args[index + 1]
      if origin notin validOrigins:
        raise newBonyLoadError(schemaViolation, originErrMsg)
      index += 2
    else:
      quit(usage(), QuitFailure)

  if outputPath.len == 0:
    raise newBonyLoadError(schemaViolation, "play requires --out")
  if stateMachine.len != 0 or inputScript.len != 0:
    if inputScript.len == 0:
      raise newBonyLoadError(schemaViolation, "play state-machine execution requires --input-script")
    if timeSet:
      raise newBonyLoadError(schemaViolation, "--t cannot be combined with --input-script; use sample t values in the script")
    let samples = executeStateMachineScript(inputPath, stateMachine, inputScript, "")
    let sheetWidth = width * samples.len
    var sheet = newImage(sheetWidth, height)
    sheet.fill(rgba(0, 0, 0, 0))
    for sampleIndex, sample in samples:
      # Thread the physics-advanced worlds (see executeStateMachineScript) so the
      # rendered spritesheet reflects the physics stage, matching numericGoldenJson.
      let rawBatches = buildDrawBatches(sample.posedData, sample.worlds)
      let coloredBatches = applyRenderSlotStates(rawBatches, renderSlotStates(sample.posedData, sample.evaluated.pose))
      let batches = if origin == "center": applyViewportTransform(coloredBatches, width, height) else: coloredBatches
      let image = renderSoftware(batches, width, height)
      sheet.draw(image, translate(vec2((sampleIndex * width).float32, 0.0.float32)))
    sheet.writeFile(outputPath)
    return

  requireSetupPoseTime(time)
  let data = loadInputSkeleton(inputPath)
  let rawBatches = buildDrawBatches(data)
  let batches = if origin == "center": applyViewportTransform(rawBatches, width, height) else: rawBatches
  let image = renderSoftware(batches, width, height)
  image.writeFile(outputPath)


proc packAtlasCmd(args: seq[string]) =
  if args.len < 1:
    quit(usage(), QuitFailure)
  let imagesDir = args[0]
  var outDir = ""
  var pageSize = 2048
  var padding = 2
  var index = 1
  while index < args.len:
    case args[index]
    of "--out-dir":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      outDir = args[index + 1]
      index += 2
    of "--page-size":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      pageSize = parsePositiveIntArg(args[index + 1], "--page-size")
      index += 2
    of "--padding":
      if index + 1 >= args.len:
        quit(usage(), QuitFailure)
      padding = parseNonNegativeIntArg(args[index + 1], "--padding")
      index += 2
    else:
      quit(usage(), QuitFailure)

  if outDir.len == 0:
    raise newBonyLoadError(schemaViolation, "pack-atlas requires --out-dir")
  if not dirExists(imagesDir):
    raise newBonyLoadError(schemaViolation, "images-dir not found: " & imagesDir)
  if 2 * padding >= pageSize:
    raise newBonyLoadError(schemaViolation,
      "--padding " & $padding & " leaves no usable space in --page-size " & $pageSize)

  # Collect PNG files from images-dir
  var inputs: seq[AtlasInputImage] = @[]
  var seen = initHashSet[string]()
  for kind, path in walkDir(imagesDir):
    if kind == pcFile and path.toLowerAscii.endsWith(".png"):
      let name = changeFileExt(extractFilename(path), "")
      if name in seen:
        raise newBonyLoadError(schemaViolation,
          "duplicate region name '" & name & "' from: " & path)
      seen.incl(name)
      var img: Image
      try:
        img = decodeImage(readFile(path))
      except PixieError as exc:
        raise newBonyLoadError(schemaViolation,
          "failed to decode PNG '" & path & "': " & exc.msg)
      inputs.add AtlasInputImage(name: name, image: img)
  if inputs.len == 0:
    raise newBonyLoadError(schemaViolation, "no PNG images found in: " & imagesDir)

  # Sort by name for deterministic output independent of filesystem traversal order
  inputs.sort proc(a, b: AtlasInputImage): int = cmp(a.name, b.name)

  let packed = packAtlas(inputs, pageSize, padding)

  createDir(outDir)

  # Write page images
  var pagesJson = newJArray()
  for i, page in packed.pages:
    let pageName = "atlas_" & $i & ".png"
    let pagePath = outDir / pageName
    page.writeFile(pagePath)
    var pageNode = newJObject()
    pageNode["name"] = newJString(pageName)
    pageNode["width"] = newJInt(page.width)
    pageNode["height"] = newJInt(page.height)
    pagesJson.add pageNode

  # Build regions JSON with UV coordinates
  var regionsJson = newJArray()
  for region in packed.regions:
    let pageW = packed.pages[region.page].width
    let pageH = packed.pages[region.page].height
    var rNode = newJObject()
    rNode["name"] = newJString(region.name)
    rNode["page"] = newJInt(region.page)
    rNode["x"] = newJInt(region.x)
    rNode["y"] = newJInt(region.y)
    rNode["width"] = newJInt(region.width)
    rNode["height"] = newJInt(region.height)
    rNode["u0"] = newJFloat(atlasRegionU0(region, pageW))
    rNode["v0"] = newJFloat(atlasRegionV0(region, pageH))
    rNode["u1"] = newJFloat(atlasRegionU1(region, pageW))
    rNode["v1"] = newJFloat(atlasRegionV1(region, pageH))
    regionsJson.add rNode

  var root = newJObject()
  root["format"] = newJString("bony.atlas.v1")
  root["pageSize"] = newJInt(pageSize)
  root["padding"] = newJInt(padding)
  root["pages"] = pagesJson
  root["regions"] = regionsJson

  writeFile(outDir / "atlas.json", pretty(root) & "\n")
  echo "bony: packed ", inputs.len, " image(s) into ", packed.pages.len, " page(s) -> ", outDir


proc autoWeightsCmd(args: seq[string]) =
  if args.len != 2:
    quit(usage(), QuitFailure)
  let inputPath = args[0]
  let outputPath = args[1]

  var doc: JsonNode
  try:
    doc = parseJson(readFile(inputPath))
  except JsonParsingError as exc:
    raise newBonyLoadError(schemaViolation, "invalid JSON in " & inputPath & ": " & exc.msg)

  discard json_schema.requireObject(doc, "auto-weights input", raiseBonySchema,
    message = "auto-weights input must be a JSON object")

  let fmt = doc.getOrDefault("format")
  if fmt == nil or fmt.kind != JString or fmt.getStr() != "bony.auto-weights-input.v1":
    raise newBonyLoadError(schemaViolation,
      "auto-weights input must have format = \"bony.auto-weights-input.v1\"")

  # Parse bones
  let bonesNode = json_schema.requireArray(
    json_schema.requireField(doc, "bones", "auto-weights input", raiseBonySchema,
      message = "auto-weights input: bones must be a non-empty array"),
    "auto-weights input",
    raiseBonySchema,
    message = "auto-weights input: bones must be a non-empty array",
  )
  if bonesNode.elems.len == 0:
    raise newBonyLoadError(schemaViolation, "auto-weights input: bones must be a non-empty array")
  var bones: seq[AutoWeightsBone]
  for i, bn in bonesNode.elems:
    let ctx = "bones[" & $i & "]"
    let boneObj = json_schema.requireObject(bn, ctx, raiseBonySchema,
      message = ctx & " must be an object")
    let name = json_schema.requireField(boneObj, "name", ctx, raiseBonySchema,
      message = ctx & ".name must be a non-empty string")
    if name.kind != JString or name.getStr().len == 0:
      raise newBonyLoadError(schemaViolation, ctx & ".name must be a non-empty string")
    let wx = json_schema.requireNumberType(
      json_schema.requireField(boneObj, "worldX", ctx, raiseBonySchema,
        message = ctx & ".worldX must be a number"),
      ctx,
      "worldX",
      raiseBonySchema,
      message = ctx & ".worldX must be a number",
    )
    let wy = json_schema.requireNumberType(
      json_schema.requireField(boneObj, "worldY", ctx, raiseBonySchema,
        message = ctx & ".worldY must be a number"),
      ctx,
      "worldY",
      raiseBonySchema,
      message = ctx & ".worldY must be a number",
    )
    bones.add AutoWeightsBone(name: name.getStr(), worldX: wx, worldY: wy)

  # Validate unique bone names
  var boneNames = initHashSet[string]()
  for bone in bones:
    if bone.name in boneNames:
      raise newBonyLoadError(schemaViolation, "duplicate bone name: " & bone.name)
    boneNames.incl(bone.name)

  # Parse vertices
  let vertsNode = json_schema.requireArray(
    json_schema.requireField(doc, "vertices", "auto-weights input", raiseBonySchema,
      message = "auto-weights input: vertices must be a non-empty array"),
    "auto-weights input",
    raiseBonySchema,
    message = "auto-weights input: vertices must be a non-empty array",
  )
  if vertsNode.elems.len == 0:
    raise newBonyLoadError(schemaViolation, "auto-weights input: vertices must be a non-empty array")
  var verts: seq[AutoWeightsVertex]
  for i, vn in vertsNode.elems:
    let ctx = "vertices[" & $i & "]"
    let vertObj = json_schema.requireObject(vn, ctx, raiseBonySchema,
      message = ctx & " must be an object")
    let vx = json_schema.requireNumberType(
      json_schema.requireField(vertObj, "x", ctx, raiseBonySchema,
        message = ctx & ".x must be a number"),
      ctx,
      "x",
      raiseBonySchema,
      message = ctx & ".x must be a number",
    )
    let vy = json_schema.requireNumberType(
      json_schema.requireField(vertObj, "y", ctx, raiseBonySchema,
        message = ctx & ".y must be a number"),
      ctx,
      "y",
      raiseBonySchema,
      message = ctx & ".y must be a number",
    )
    verts.add AutoWeightsVertex(worldX: vx, worldY: vy)

  # Parse optional parameters
  var maxInfluences = defaultMaxInfluences
  var epsilon = defaultEpsilon
  let maxInfNode = doc.getOrDefault("maxInfluences")
  if maxInfNode != nil:
    let parsedMaxInfluences = json_schema.requirePositiveInt(
      maxInfNode,
      "auto-weights input",
      "maxInfluences",
      raiseBonySchema,
      message = "maxInfluences must be an integer in 1..255",
      positiveMessage = "maxInfluences must be an integer in 1..255",
    )
    if parsedMaxInfluences > 255:
      raise newBonyLoadError(schemaViolation, "maxInfluences must be an integer in 1..255")
    maxInfluences = parsedMaxInfluences
  let epsNode = doc.getOrDefault("epsilon")
  if epsNode != nil:
    let parsedEpsilon = json_schema.requireNumberType(
      epsNode,
      "auto-weights input",
      "epsilon",
      raiseBonySchema,
      message = "epsilon must be a positive number",
    )
    if parsedEpsilon <= 0.0:
      raise newBonyLoadError(schemaViolation, "epsilon must be a positive number")
    epsilon = parsedEpsilon

  let weighted = autoWeightVertices(bones, verts, maxInfluences, epsilon)

  var vertsJson = newJArray()
  for wv in weighted:
    var inflArr = newJArray()
    for inf in wv.influences:
      var infNode = newJObject()
      infNode["bone"] = newJString(inf.bone)
      infNode["bindX"] = newJFloat(inf.bindX)
      infNode["bindY"] = newJFloat(inf.bindY)
      infNode["weight"] = newJFloat(inf.weight)
      inflArr.add infNode
    var vNode = newJObject()
    vNode["influences"] = inflArr
    vertsJson.add vNode

  var root = newJObject()
  root["format"] = newJString("bony.auto-weights-output.v1")
  root["vertices"] = vertsJson

  writeFile(outputPath, pretty(root) & "\n")
  echo "bony: wrote weights for ", verts.len, " vertices across ", bones.len, " bones -> ", outputPath


proc main() =
  let args = commandLineParams()
  if args.len == 0:
    quit(usage(), QuitFailure)

  try:
    case args[0]
    of "json-to-bnb":
      if args.len != 3:
        quit(usage(), QuitFailure)
      writeBytes(args[2], toBonyBnb(loadBonyJsonAsset(readFile(args[1]))))
    of "bnb-to-json":
      if args.len != 3:
        quit(usage(), QuitFailure)
      writeFile(args[2], toBonyJson(loadKnownBonyBnbAsset(readBytes(args[1]))))
    of "import-lottie":
      importLottie(args[1 .. ^1])
    of "import-dragonbones":
      importDragonbones(args[1 .. ^1])
    of "golden-gen":
      writeNumericGolden(args[1 .. ^1])
    of "play":
      renderSetupPose(args[1 .. ^1])
    of "pack-atlas":
      packAtlasCmd(args[1 .. ^1])
    of "auto-weights":
      autoWeightsCmd(args[1 .. ^1])
    else:
      quit(usage(), QuitFailure)
  except CliDiagnostic as exc:
    quit("bony: " & exc.cliMessage, QuitFailure)
  except BonyLoadError as exc:
    quit("bony: " & exc.msg, QuitFailure)
  except IOError as exc:
    quit("bony: " & exc.msg, QuitFailure)
  except OSError as exc:
    quit("bony: " & exc.msg, QuitFailure)


# bonyExcludeMain lets tests `include` this module to unit-test its private procs
# (e.g. applySequencePose) without running the CLI entry point.
when isMainModule and not defined(bonyExcludeMain):
  main()
