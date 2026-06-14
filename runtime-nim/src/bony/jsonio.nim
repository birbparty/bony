## M1 .bony JSON loader/serializer.

import std/[json, sets]

import bony/generated/wire
import bony/model

const
  skeletonTypeId = "skeleton"
  boneTypeId = "bone"


proc defaultFor(objectId, propertyId: string): string =
  for entry in bonyPropertyDefaults:
    if entry.objectId == objectId and entry.propertyId == propertyId:
      return parseJson(entry.value).getStr()
  raise newBonyLoadError(schemaViolation, "missing generated default for " & objectId & "." & propertyId)


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


proc requiredString(node: JsonNode; key, context: string): string =
  if not node.hasKey(key):
    raise newBonyLoadError(schemaViolation, context & "." & key & " is required")
  optionalString(node, key, "", context)


proc validateKnownKeys(node: JsonNode; allowed: openArray[string]; context: string) =
  for key in node.keys:
    var found = false
    for allowedKey in allowed:
      if key == allowedKey:
        found = true
        break
    if not found:
      raise newBonyLoadError(schemaViolation, context & "." & key & " is not a known M1 field")


proc loadBonyJson*(text: string): SkeletonData =
  let parsed =
    try:
      parseJson(text)
    except JsonParsingError as exc:
      raise newBonyLoadError(schemaViolation, "invalid JSON: " & exc.msg)

  let root = requireObject(parsed, "root")
  validateKnownKeys(root, ["skeleton", "bones"], "root")

  if not root.hasKey("skeleton"):
    raise newBonyLoadError(schemaViolation, "root.skeleton is required")
  let skeleton = requireObject(root["skeleton"], "skeleton")
  validateKnownKeys(skeleton, ["name", "version"], "skeleton")

  result.header = SkeletonHeader(
    name: requiredString(skeleton, "name", "skeleton"),
    version: optionalString(skeleton, "version", defaultFor(skeletonTypeId, "version"), "skeleton"),
  )

  let bonesNode =
    if root.hasKey("bones"): requireArray(root["bones"], "bones")
    else: newJArray()

  var seen = initHashSet[string]()
  for index, boneNode in bonesNode.elems:
    let context = "bones[" & $index & "]"
    let boneObject = requireObject(boneNode, context)
    validateKnownKeys(boneObject, ["name", "parent"], context)
    let bone = BoneData(
      name: requiredString(boneObject, "name", context),
      parent: optionalString(boneObject, "parent", defaultFor(boneTypeId, "parent"), context),
    )
    if bone.name.len == 0:
      raise newBonyLoadError(schemaViolation, context & ".name must not be empty")
    if bone.name in seen:
      raise newBonyLoadError(duplicateKey, "duplicate bone name: " & bone.name)
    if bone.parent.len > 0 and bone.parent notin seen:
      raise newBonyLoadError(orderingViolation, "bone parent must appear before child: " & bone.name)
    seen.incl(bone.name)
    result.bones.add(bone)


proc toBonyJson*(data: SkeletonData): string =
  var root = newJObject()
  var skeleton = newJObject()
  skeleton["name"] = newJString(data.header.name)
  if data.header.version != defaultFor(skeletonTypeId, "version"):
    skeleton["version"] = newJString(data.header.version)
  root["skeleton"] = skeleton

  var bones = newJArray()
  for bone in data.bones:
    var boneObject = newJObject()
    boneObject["name"] = newJString(bone.name)
    if bone.parent != defaultFor(boneTypeId, "parent"):
      boneObject["parent"] = newJString(bone.parent)
    bones.add(boneObject)
  root["bones"] = bones
  pretty(root) & "\n"
