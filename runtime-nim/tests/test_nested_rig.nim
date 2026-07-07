include smoke_support

spec "nested rig smoke coverage":
  it "loads and round trips nested rig attachments through JSON and .bnb":
    let jsonText = """
{
  "skeleton": { "name": "host", "version": "1.0.0" },
  "bones": [{ "name": "root" }],
  "slots": [{ "name": "nestedSlot", "bone": "root", "attachment": "nested_face" }],
  "nestedRigAttachments": [
    {
      "name": "nested_face",
      "skeleton": "faceRig",
      "skin": "neutral",
      "animation": "blink"
    }
  ],
  "skins": [
    {
      "name": "default",
      "entries": [
        { "slot": "nestedSlot", "attachment": "nested_face", "target": "nested_face" }
      ]
    }
  ]
}
"""
    let fromJson = loadBonyJson(jsonText)
    let bnbBytes = toBonyBnb(fromJson)
    let fromBnb = loadBonyBnb(bnbBytes)
    then:
      fromJson.nestedRigAttachments.len == 1
      fromBnb.nestedRigAttachments.len == 1
      fromJson.nestedRigAttachments[0].name == "nested_face"
      fromJson.nestedRigAttachments[0].skeleton == "faceRig"
      fromJson.nestedRigAttachments[0].skin == "neutral"
      fromJson.nestedRigAttachments[0].animation == "blink"
      fromBnb.nestedRigAttachments[0].name == "nested_face"
      fromBnb.nestedRigAttachments[0].skeleton == "faceRig"
      fromBnb.nestedRigAttachments[0].skin == "neutral"
      fromBnb.nestedRigAttachments[0].animation == "blink"
      buildDrawBatches(fromJson).len == 0
      toBonyJson(fromBnb) == toBonyJson(fromJson)
      toBonyBnb(loadBonyJson(toBonyJson(fromBnb))) == bnbBytes

  it "rejects malformed nested rig attachments":
    let base = """
{
  "skeleton": { "name": "host" },
  "bones": [{ "name": "root" }],
  "slots": [{ "name": "nestedSlot", "bone": "root", "attachment": "nested_face" }],
  "nestedRigAttachments": [REPLACE]
}
"""
    then:
      raisesBonyLoadError(base.replace("REPLACE", """{ "name": "", "skeleton": "faceRig" }"""), schemaViolation)
      raisesBonyLoadError(base.replace("REPLACE", """{ "name": "nested_face", "skeleton": "" }"""), schemaViolation)
      raisesBonyLoadError(base.replace("REPLACE", """{ "name": "nested_face", "skeleton": "a" }, { "name": "nested_face", "skeleton": "b" }"""), duplicateKey)
      raisesBonyLoadError("""
{
  "skeleton": { "name": "host" },
  "bones": [{ "name": "root" }],
  "slots": [{ "name": "nestedSlot", "bone": "root", "attachment": "shared" }],
  "regions": [{ "name": "shared", "width": 1, "height": 1 }],
  "nestedRigAttachments": [{ "name": "shared", "skeleton": "faceRig" }]
}
""", duplicateKey)

  it "composes host-resolved nested rig setup draw batches":
    let host = skeletonData(
      skeletonHeader("host", "1.0.0"),
      @[boneData("root", "", localTransform(x = 10.0, y = 20.0))],
      @[slotData("nestedSlot", "root", "nested_face")],
      nestedRigAttachments = @[nestedRigAttachmentData("nested_face", "faceRig")],
    )
    let child = skeletonData(
      skeletonHeader("child", "1.0.0"),
      @[boneData("root", "", localTransform(x = 1.0))],
      @[slotData("childSlot", "root", "face")],
      @[regionAttachment("face", 2.0, 2.0)],
    )
    var children = initTable[string, SkeletonData]()
    children["faceRig"] = child
    let childOnly = buildDrawBatches(child)
    let batches = buildNestedDrawBatches(host, children)

    then:
      buildDrawBatches(host).len == 0
      childOnly.len == 1
      batches.len == 1
      batches[0].slot == "childSlot"
      batches[0].bone == "root"
      batches[0].attachment == "face"
      closeTo(batches[0].world.tx, 11.0)
      closeTo(batches[0].world.ty, 20.0)
      closeTo(batches[0].vertices[0].x, 10.0)
      closeTo(batches[0].vertices[0].y, 19.0)
      closeTo(batches[0].vertices[2].x, 12.0)
      closeTo(batches[0].vertices[2].y, 21.0)
      abs(batches[0].vertices[0].x - childOnly[0].vertices[0].x) > 1e-4

  it "rejects missing child skeletons, unknown child skins, and nested cycles":
    let missingHost = skeletonData(
      skeletonHeader("host", "1.0.0"),
      @[boneData("root", "")],
      @[slotData("nestedSlot", "root", "nested_face")],
      nestedRigAttachments = @[nestedRigAttachmentData("nested_face", "faceRig")],
    )
    let missingSkinHost = skeletonData(
      skeletonHeader("host", "1.0.0"),
      @[boneData("root", "")],
      @[slotData("nestedSlot", "root", "nested_face")],
      nestedRigAttachments = @[nestedRigAttachmentData("nested_face", "faceRig", skin = "missing")],
    )
    let plainChild = skeletonData(
      skeletonHeader("child", "1.0.0"),
      @[boneData("root", "")],
      @[slotData("childSlot", "root", "face")],
      @[regionAttachment("face", 2.0, 2.0)],
    )
    let recursiveChild = skeletonData(
      skeletonHeader("recursive", "1.0.0"),
      @[boneData("root", "")],
      @[slotData("selfSlot", "root", "nested_self")],
      nestedRigAttachments = @[nestedRigAttachmentData("nested_self", "faceRig")],
    )
    var emptyChildren = initTable[string, SkeletonData]()
    var plainChildren = initTable[string, SkeletonData]()
    plainChildren["faceRig"] = plainChild
    var recursiveChildren = initTable[string, SkeletonData]()
    recursiveChildren["faceRig"] = recursiveChild

    then:
      raisesBonyLoadError(
        proc() = discard buildNestedDrawBatches(missingHost, emptyChildren),
        unknownRequiredReference)
      raisesBonyLoadError(
        proc() = discard buildNestedDrawBatches(missingSkinHost, plainChildren),
        unknownRequiredReference)
      raisesBonyLoadError(
        proc() = discard buildNestedDrawBatches(missingHost, recursiveChildren),
        cycleDetected)

  it "clips composed nested child batches through host clipping ranges":
    let child = skeletonData(
      skeletonHeader("child", "1.0.0"),
      @[boneData("root", "")],
      @[slotData("childSlot", "root", "face")],
      @[regionAttachment("face", 4.0, 4.0)],
    )
    let host = skeletonData(
      skeletonHeader("host", "1.0.0"),
      @[boneData("root", "")],
      @[
        slotData("clipSlot", "root", "host_clip"),
        slotData("nestedSlot", "root", "nested_face"),
      ],
      clippingAttachments = @[
        clipAttachmentData("host_clip", @[0.0, -10.0, 100.0, -10.0, 100.0, 10.0, 0.0, 10.0]),
      ],
      nestedRigAttachments = @[nestedRigAttachmentData("nested_face", "faceRig")],
    )
    var children = initTable[string, SkeletonData]()
    children["faceRig"] = child
    let batches = buildNestedDrawBatches(host, children)

    then:
      batches.len == 1
      batches[0].clipId == "host_clip"
      batches[0].vertices.len >= 4
      batches[0].indices.len >= 6
      batches[0].vertices.allIt(it.x >= -1e-9)
      batches[0].vertices.anyIt(closeWithin(it.x, 0.0, 1e-9))
