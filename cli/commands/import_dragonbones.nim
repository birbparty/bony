## DragonBones Tier 1 importer command.

import std/[json, os, sets, strutils, tables]

import bony
import pixie

import ../argparse
import ../cli_common
import ../json_schema

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
    rejectUnsupportedFeature(target, "tweenEasing",
      "non-zero tweenEasing not supported in Tier 1")
  result.hasTweenEasing = hasTween
  result.tweenEasing = tween
  if node.hasKey("curve"):
    rejectUnsupportedFeature(target, "curve", "Bezier curve easing not supported in Tier 1")


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
    rejectUnsupportedFeature(target, "negativeScale", "negative scale not supported in Tier 1")


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
    rejectUnsupportedFeature(target, "mesh", "mesh displays not supported in Tier 1")
  of "boundingBox":
    rejectUnsupportedFeature(target, "boundingBox", "bounding-box displays not supported in Tier 1")
  else:
    rejectUnsupportedFeature(target, typStr, "display type not supported in Tier 1: " & typStr)
  if node.hasKey("transform"):
    if node["transform"].kind != JObject:
      raiseDb(cliSchemaViolation, target, "transform", "expected transform object")
    let t = parseDbTransform(node["transform"], target & ".transform")
    if t.x != 0.0 or t.y != 0.0 or t.skX != 0.0 or t.skY != 0.0 or
       t.scX != 1.0 or t.scY != 1.0:
      rejectUnsupportedFeature(target, "displayTransform",
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
    rejectUnsupportedFeature(target, "clockwise",
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
      rejectUnsupportedFeature(target, key,
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
    rejectUnsupportedFeature(target, "slot",
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
    rejectUnsupportedFeature(target, "displayIndex",
      "displayIndex -1 (hidden slot) not supported in Tier 1")
  result.displayIndex = di
  let blendMode = dbOptString(node, "blendMode", "normal", target)
  if blendMode != "normal":
    rejectUnsupportedFeature(target, "blendMode",
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
    rejectUnsupportedFeature(target, "type",
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
    rejectUnsupportedFeature("animation[" & anim.name & "]", "animation",
      "animation has no supported Tier 1 bone timelines")
  try:
    clips.add animationClip(data, anim.name, timelines)
  except BonyLoadError as exc:
    raiseDb(cliSchemaViolation, "animation[" & anim.name & "]", "animation", exc.msg)


proc dbAnimationsToClips(armature: DbArmature; data: SkeletonData): seq[AnimationClip] =
  for anim in armature.animations:
    addDbAnimationClip(armature, data, anim, result)


proc importDragonbones*(args: seq[string]; usageText: string) =
  if args.len < 2:
    quit(usageText, QuitFailure)
  let inputPath = args[0]
  let outputPath = args[1]
  var assetsDir = ""
  var setupOnly = false
  var allowMultipleArmatures = false
  var cursor = initArgCursor(args, usageText)
  cursor.index = 2
  while not cursor.done:
    case cursor.current
    of "--assets-dir":
      assetsDir = cursor.requireValue("--assets-dir")
    of "--setup-only":
      setupOnly = true
      cursor.advance()
    of "--allow-multiple-armatures":
      allowMultipleArmatures = true
      cursor.advance()
    else:
      cursor.failUsage()

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
