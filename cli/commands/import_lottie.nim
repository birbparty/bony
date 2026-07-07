## Lottie Tier 1 importer command.

import std/[json, math, os, parseutils, sets, strutils, tables]

import bony

import ../argparse
import ../cli_common
import ../json_schema

type
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
        rejectUnsupportedFeature(target, capability, "animated channels are not supported in Tier 1")
    if node.elems.len != 2:
      raiseLottie(cliSchemaViolation, target, capability, "expected [x, y]")
    return (
      finiteNumber(node.elems[0], target, capability),
      finiteNumber(node.elems[1], target, capability),
    )
  rejectUnsupportedFeature(target, capability, "animated channels are not supported in Tier 1")


proc requireScalar(node: JsonNode; target, capability: string; defaultValue: float64): float64 =
  if node.isNil:
    return defaultValue
  if node.kind in {JInt, JFloat}:
    return finiteNumber(node, target, capability)
  rejectUnsupportedFeature(target, capability, "animated channels are not supported in Tier 1")


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
    rejectUnsupportedFeature(target, "opacity", "non-default opacity is not serializable in Tier 1")
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
    rejectUnsupportedFeature(target, result.kind, "only image layers are supported in Tier 1")
  let blend = optionalString(layerObject, "blend", "normal", target)
  if blend != "normal":
    rejectUnsupportedFeature(target, "blend", "only normal blend is supported in Tier 1")
  let compIn = finiteNumber(requireField(composition, "ip", "composition"), "composition", "ip")
  let compOut = finiteNumber(requireField(composition, "op", "composition"), "composition", "op")
  let layerIn = if layerObject.hasKey("in"): finiteNumber(layerObject["in"], target, "in") else: compIn
  let layerOut = if layerObject.hasKey("out"): finiteNumber(layerObject["out"], target, "out") else: compOut
  if layerIn != compIn or layerOut != compOut:
    rejectUnsupportedFeature(target, "visibility", "visibility intervals are not supported in Tier 1")
  if layerObject.hasKey("shapes"):
    rejectUnsupportedFeature(target, "shape", "shape layers require Tier 2")

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
      rejectUnsupportedFeature(target, "image.anchor", "image payload anchor is not supported in Tier 1")
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


proc importLottie*(args: seq[string]; usageText: string) =
  if args.len < 2:
    quit(usageText, QuitFailure)
  let inputPath = args[0]
  let outputPath = args[1]
  var assetsDir = ""
  var origin = "center"
  var cursor = initArgCursor(args, usageText)
  cursor.index = 2
  while not cursor.done:
    case cursor.current
    of "--assets-dir":
      assetsDir = cursor.requireValue("--assets-dir")
    of "--setup-only":
      cursor.advance()
    of "--origin":
      origin = cursor.requireValue("--origin")
      if origin notin validOrigins:
        raiseLottie(cliSchemaViolation, "cli", "origin", originErrMsg)
    of "--reject-shapes":
      cursor.advance()
    of "--rasterize-shapes":
      rejectUnsupportedFeature("cli", "rasterize-shapes", "shape rasterization requires Tier 2")
    of "--atlas-out":
      rejectUnsupportedFeature("cli", "atlas", "atlas output requires Tier 2")
    else:
      cursor.failUsage()
  if assetsDir.len == 0:
    raiseLottie(cliSchemaViolation, "cli", "assets-dir", "--assets-dir is required")
  let composition = parseLottieComposition(readFile(inputPath), assetsDir)
  let data = composition.toSkeletonData(origin)
  writeFile(outputPath, toBonyJson(data))
