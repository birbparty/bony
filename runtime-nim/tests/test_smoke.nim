include smoke_support

proc ordinalEnumValues(id: string): seq[string] =
  for entry in bonyOrdinalEnums:
    if entry.id == id:
      return entry.values
  raise newException(ValueError, "missing generated ordinal enum: " & id)

spec "bony package":
  it "exposes version":
    then:
      bonyVersion == "0.1.0"

  it "exports generated registry metadata":
    then:
      bonyRegistryVersion == 1
      bonyBackingTypes.len == 8
      bonyBackingTypes[0].id == "varuint"
      bonyTypeKeys.len == 35
      bonyTypeKeys.anyIt(it.id == "pointAttachment" and it.key == 1002'u64)
      bonyTypeKeys.anyIt(it.id == "boundingBoxAttachment" and it.key == 1003'u64)
      bonyTypeKeys.anyIt(it.id == "skin" and it.key == 3003'u64)
      bonyTypeKeys.anyIt(it.id == "skinEntry" and it.key == 3004'u64)
      bonyTypeKeys.anyIt(it.id == "nestedRigAttachment" and it.key == 3005'u64)
      bonyPropertyKeys.len == 130
      bonyPropertyKeys.anyIt(it.id == "skinAttachment" and it.key == 3010'u64)
      bonyPropertyKeys.anyIt(it.id == "skinTarget" and it.key == 3011'u64)
      bonyPropertyKeys.anyIt(it.id == "nestedSkeleton" and it.key == 3012'u64)
      bonyPropertyKeys.anyIt(it.id == "nestedSkin" and it.key == 3013'u64)
      bonyPropertyKeys.anyIt(it.id == "nestedAnimation" and it.key == 3014'u64)
      bonyPropertyKeys.anyIt(it.id == "texturePage" and it.key == 8000'u64)
      bonyPropertyKeys.anyIt(it.id == "u0" and it.key == 8001'u64)
      bonyPropertyKeys.anyIt(it.id == "v0" and it.key == 8002'u64)
      bonyPropertyKeys.anyIt(it.id == "u1" and it.key == 8003'u64)
      bonyPropertyKeys.anyIt(it.id == "v1" and it.key == 8004'u64)
      bonyPropertyKeys.anyIt(it.id == "alphaMode" and it.key == 8005'u64)
      bonyPropertyKeys.anyIt(it.id == "skinRequired" and it.key == 4027'u64)
      bonyPropertyKeys.anyIt(it.id == "skinBones" and it.key == 4028'u64)
      bonyPropertyKeys.anyIt(it.id == "skinPhysicsConstraints" and it.key == 4032'u64)
      bonyPropertyKeys.anyIt(it.id == "listenerSlotIndex" and it.key == 7064'u64)
      bonyPropertyKeys.anyIt(it.id == "listenerHitRadius" and it.key == 7070'u64)
      bonyPropertyDefaults.len == 81
      bonyPropertyDefaults.anyIt(it.objectId == "region" and it.propertyId == "texturePage" and it.value == "\"\"")
      bonyPropertyDefaults.anyIt(it.objectId == "region" and it.propertyId == "u0" and it.value == "0.0")
      bonyPropertyDefaults.anyIt(it.objectId == "region" and it.propertyId == "v0" and it.value == "0.0")
      bonyPropertyDefaults.anyIt(it.objectId == "region" and it.propertyId == "u1" and it.value == "1.0")
      bonyPropertyDefaults.anyIt(it.objectId == "region" and it.propertyId == "v1" and it.value == "1.0")
      bonyPropertyDefaults.anyIt(it.objectId == "region" and it.propertyId == "alphaMode" and it.value == "\"straight\"")
      bonyRequiredProperties.len == 91
      bonyOrdinalEnums.len == 2
      ordinalEnumValues("physicsChannel") == @["x", "y", "rotate", "scaleX", "shearX"]
      ordinalEnumValues("deformerKind") == @["warp", "rotation"]

  it "keeps generated ordinal contracts aligned with runtime enums":
    var physicsChannels: seq[string]
    for channel in PhysicsChannel:
      physicsChannels.add case channel
        of pcX: "x"
        of pcY: "y"
        of pcRotate: "rotate"
        of pcScaleX: "scaleX"
        of pcShearX: "shearX"

    var deformerKinds: seq[string]
    for kind in DeformerKind:
      deformerKinds.add case kind
        of warpDeformerKind: "warp"
        of rotationDeformerKind: "rotation"

    then:
      physicsChannels == ordinalEnumValues("physicsChannel")
      ord(pcX) == 0
      ord(pcY) == 1
      ord(pcRotate) == 2
      ord(pcScaleX) == 3
      ord(pcShearX) == 4
      deformerKinds == ordinalEnumValues("deformerKind")

  it "exports generated scalar JSON and BNB codec helpers":
    let decoded = decodeBoneJsonScalars(@[
      BonyJsonScalarProperty(propertyId: "name", value: bonyStringValue("root")),
    ])
    let encoded = encodeBoneBnbScalars(@[
      BonyBnbScalarProperty(propertyKey: 1'u64, value: bonyStringValue("root")),
      BonyBnbScalarProperty(propertyKey: 1000'u64, value: bonyF32Value(0.0)),
      BonyBnbScalarProperty(propertyKey: 1001'u64, value: bonyF32Value(2.0)),
    ])
    then:
      decoded.anyIt(it.propertyId == "parent" and it.value.stringValue == "")
      decoded.anyIt(it.propertyId == "transformMode" and it.value.stringValue == "normal")
      encoded.anyIt(it.propertyKey == 1'u64)
      not encoded.anyIt(it.propertyKey == 1000'u64)
      encoded.anyIt(it.propertyKey == 1001'u64)
      bonyMeshAttachmentScalarSpecs.len == 2
      not bonyMeshAttachmentScalarSpecs.anyIt(it.propertyId == "meshVertices")

  it "rejects malformed generated scalar codec inputs":
    var duplicateJsonRejected = false
    try:
      discard encodeBoneJsonScalars(@[
        BonyJsonScalarProperty(propertyId: "name", value: bonyStringValue("root")),
        BonyJsonScalarProperty(propertyId: "name", value: bonyStringValue("again")),
      ])
    except ValueError:
      duplicateJsonRejected = true

    var duplicateBnbRejected = false
    try:
      discard encodeBoneBnbScalars(@[
        BonyBnbScalarProperty(propertyKey: 1'u64, value: bonyStringValue("root")),
        BonyBnbScalarProperty(propertyKey: 1'u64, value: bonyStringValue("again")),
      ])
    except ValueError:
      duplicateBnbRejected = true

    var packedOnlyScalarRejected = false
    try:
      discard encodeEventTimelineJsonScalars(@[
        BonyJsonScalarProperty(propertyId: "eventKeys", value: bonyStringValue("packed")),
      ])
    except ValueError:
      packedOnlyScalarRejected = true

    then:
      bonyEventTimelineScalarSpecs.len == 0
      duplicateJsonRejected
      duplicateBnbRejected
      packedOnlyScalarRejected
