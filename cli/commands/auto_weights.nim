## Auto-weighting command.

import std/[json, sets]

import bony

import ../auto_weights
import ../cli_common
import ../json_schema

proc autoWeightsCmd*(args: seq[string]; usageText: string) =
  if args.len != 2:
    quit(usageText, QuitFailure)
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
