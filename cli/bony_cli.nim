## Headless bony CLI harness core.

import std/[json, os, parseutils, strutils]

import bony
import pixie


proc usage(): string =
  "usage: bony json-to-bnb <input.bony> <output.bnb>\n" &
    "       bony bnb-to-json <input.bnb> <output.bony>\n" &
    "       bony golden-gen <input.bony|input.bnb> <output.json> [--t seconds]\n" &
    "       bony play <input.bony|input.bnb> --out frame.png [--t seconds] [--width px] [--height px]\n" &
    "       bony play <input> --state-machine <name> --input-script <script.json> --out frame.png"


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


proc loadInputSkeleton(path: string): SkeletonData =
  if path.toLowerAscii.endsWith(".bnb"):
    loadBonyBnb(readBytes(path))
  else:
    loadBonyJson(readFile(path))


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
  if args.len notin {2, 4}:
    quit(usage(), QuitFailure)
  var time = 0.0
  if args.len == 4:
    if args[2] != "--t":
      quit(usage(), QuitFailure)
    time = parseFloatArg(args[3], "--t")
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
  if stateMachine.len != 0 or inputScript.len != 0:
    raise newBonyLoadError(
      schemaViolation,
      "serialized state machines and input scripts are not available in the current .bony/.bnb model",
    )
  discard time
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
    of "golden-gen":
      writeNumericGolden(args[1 .. ^1])
    of "play":
      renderSetupPose(args[1 .. ^1])
    else:
      quit(usage(), QuitFailure)
  except BonyLoadError as exc:
    quit("bony: " & exc.msg, QuitFailure)
  except OSError as exc:
    quit("bony: " & exc.msg, QuitFailure)


when isMainModule:
  main()
