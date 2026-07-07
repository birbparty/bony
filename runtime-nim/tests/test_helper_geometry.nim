include smoke_support

spec "helper geometry smoke coverage":
  it "round trips helper geometry attachments through JSON and .bnb without drawing them":
    let jsonText = """
{
  "skeleton": {"name": "helperdemo", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [
    {"name": "pointSlot", "bone": "root", "attachment": "muzzle"},
    {"name": "boxSlot", "bone": "root", "attachment": "button_hit"},
    {"name": "regionSlot", "bone": "root", "attachment": "visible"}
  ],
  "regions": [{"name": "visible", "width": 10, "height": 6}],
  "pointAttachments": [
    {"name": "muzzle", "x": 3.5, "y": -2.25, "rotation": 45}
  ],
  "boundingBoxAttachments": [
    {"name": "button_hit", "vertices": [-5, -4, 5, -4, 5, 4, -5, 4]}
  ]
}
"""
    let fromJson = loadBonyJson(jsonText)
    let bnbBytes = toBonyBnb(fromJson)
    let fromBnb = loadBonyBnb(bnbBytes)
    let batches = buildDrawBatches(fromBnb)

    then:
      fromJson.pointAttachments.len == 1
      fromJson.pointAttachments[0].name == "muzzle"
      fromJson.pointAttachments[0].x == 3.5
      fromJson.pointAttachments[0].y == -2.25
      fromJson.pointAttachments[0].rotation == 45.0
      fromJson.boundingBoxAttachments.len == 1
      fromJson.boundingBoxAttachments[0].name == "button_hit"
      fromJson.boundingBoxAttachments[0].vertices == @[-5.0, -4.0, 5.0, -4.0, 5.0, 4.0, -5.0, 4.0]
      fromBnb.pointAttachments[0].name == fromJson.pointAttachments[0].name
      fromBnb.boundingBoxAttachments[0].vertices == fromJson.boundingBoxAttachments[0].vertices
      toBonyJson(loadBonyJson(toBonyJson(fromJson))) == toBonyJson(fromJson)
      toBonyBnb(loadBonyJson(toBonyJson(fromBnb))) == bnbBytes
      batches.len == 1
      batches[0].slot == "regionSlot"
      batches[0].attachment == "visible"

  it "rejects malformed helper geometry attachments":
    let duplicatePoints = """
{
  "skeleton": {"name": "helperdemo", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "pointAttachments": [
    {"name": "p", "x": 0, "y": 0, "rotation": 0},
    {"name": "p", "x": 1, "y": 1, "rotation": 0}
  ]
}
"""
    let concaveBox = """
{
  "skeleton": {"name": "helperdemo", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "boundingBoxAttachments": [
    {"name": "box", "vertices": [0, 0, 2, 0, 0.5, 0.5, 0, 2]}
  ]
}
"""
    let unknownSlot = """
{
  "skeleton": {"name": "helperdemo", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "slot", "bone": "root", "attachment": "missing_helper"}],
  "pointAttachments": [{"name": "p", "x": 0, "y": 0, "rotation": 0}]
}
"""

    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(duplicatePoints), duplicateKey)
      raisesBonyLoadError(proc() = discard loadBonyJson(concaveBox), schemaViolation)
      raisesBonyLoadError(proc() = discard loadBonyJson(unknownSlot), unknownRequiredReference)
