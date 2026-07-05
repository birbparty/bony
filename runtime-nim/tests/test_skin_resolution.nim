import std/[strutils]

import bddy
import bony


proc raisesBonyLoadError(action: proc(); kind: BonyLoadErrorKind): bool =
  try:
    action()
    false
  except BonyLoadError as exc:
    exc.kind == kind


proc closeTo(actual, expected: float64): bool =
  abs(actual - expected) <= 1e-9


proc skinRegionFixture(): SkeletonData =
  skeletonData(
    skeletonHeader("skin-region", "1.0.0"),
    @[boneData("root", "")],
    @[slotData("body", "root", "body")],
    @[
      regionAttachment("body_default_region", 2.0, 2.0),
      regionAttachment("body_armor_region", 4.0, 4.0),
    ],
    skins = @[
      skinData("default", @[skinEntryData("body", "body", "body_default_region")]),
      skinData("armor", @[skinEntryData("body", "body", "body_armor_region")]),
    ],
  )


const skinnedMeshJson = """{
  "skeleton": { "name": "skin-mesh", "version": "1.0.0" },
  "bones": [ { "name": "root" } ],
  "slots": [ { "name": "cloth", "bone": "root", "attachment": "cloth" } ],
  "meshAttachments": [
    {
      "name": "cloth_mesh",
      "weighted": false,
      "vertices": [ { "x": 0.0, "y": 0.0 }, { "x": 4.0, "y": 0.0 }, { "x": 0.0, "y": 4.0 } ],
      "uvs": [ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 ],
      "triangles": [ 0, 1, 2 ]
    }
  ],
  "skins": [
    {
      "name": "default",
      "entries": [
        { "slot": "cloth", "attachment": "cloth", "target": "cloth_mesh" }
      ]
    },
    { "name": "armor" }
  ],
  "animations": [
    {
      "name": "wiggle",
      "deformTimelines": [
        {
          "skin": "armor",
          "slot": "cloth",
          "attachment": "cloth",
          "vertexCount": 3,
          "keyframes": [
            { "t": 0.0, "offset": 0, "deltas": [ { "x": 1.0, "y": 0.0 } ] }
          ]
        }
      ]
    }
  ]
}"""


spec "Nim skin attachment resolution":
  it "round-trips explicit skins through JSON and BNB":
    let data = loadBonyJson(skinnedMeshJson)
    let jsonText = toBonyJson(data)
    let assetText = toBonyJson(loadBonyJsonAsset(skinnedMeshJson))
    let fromBnb = loadBonyBnb(toBonyBnb(data))

    then:
      data.skins.len == 2
      data.skins[0].name == "default"
      data.skins[0].entries.len == 1
      data.resolveSkinAttachmentTarget("default", "cloth", "cloth") == "cloth_mesh"
      data.resolveSkinAttachmentTarget("armor", "cloth", "cloth") == "cloth_mesh"
      jsonText.contains("\"skins\"")
      assetText.find("\"skins\"") < assetText.find("\"animations\"")
      fromBnb.skins.len == 2
      fromBnb.skins[0].name == "default"
      fromBnb.resolveSkinAttachmentTarget("armor", "cloth", "cloth") == "cloth_mesh"

  it "resolves active skins for draw batches with default fallback":
    let data = skinRegionFixture()
    let defaultBatch = buildDrawBatches(data)[0]
    let armorBatch = buildDrawBatches(data, "armor")[0]
    let missingSkinBatch = buildDrawBatches(data, "missing")[0]

    then:
      defaultBatch.slot == "body"
      defaultBatch.attachment == "body_default_region"
      closeTo(defaultBatch.vertices[0].x, -1.0)
      armorBatch.slot == "body"
      armorBatch.attachment == "body_armor_region"
      closeTo(armorBatch.vertices[0].x, -2.0)
      missingSkinBatch.attachment == "body_default_region"

  it "accepts non-default deform timelines that resolve through skin fallback":
    let asset = loadBonyJsonAsset(skinnedMeshJson)
    let fromBnb = loadBonyBnbAsset(toBonyBnb(asset))
    let jsonTimeline = asset.animations[0].deformTimelines[0]
    let bnbTimeline = fromBnb.animations[0].deformTimelines[0]

    then:
      jsonTimeline.skin == "armor"
      jsonTimeline.slot == "cloth"
      jsonTimeline.attachment == "cloth"
      jsonTimeline.vertexCount == 3
      bnbTimeline.skin == "armor"
      bnbTimeline.attachment == "cloth"
      sampleDeformDeltas(bnbTimeline, 0.0)[0].x == 1.0

  it "rejects unresolved skin and deform bindings":
    let badSkin = skinnedMeshJson.replace("\"skin\": \"armor\"", "\"skin\": \"ghost\"")
    let badBinding = skinnedMeshJson.replace("\"attachment\": \"cloth\",\n          \"vertexCount\"", "\"attachment\": \"missing\",\n          \"vertexCount\"")

    then:
      raisesBonyLoadError(proc() = discard loadBonyJsonAsset(badSkin), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard loadBonyJsonAsset(badBinding), unknownRequiredReference)

  it "preserves skins when applying an animation pose":
    let data = skinRegionFixture()
    let posed = applyPose(data, MixedPose(
      attachments: @[MixedAttachment(target: "body", attachment: "body")],
    ))

    then:
      posed.skins.len == data.skins.len
      posed.resolveSkinAttachmentTarget("armor", "body", "body") == "body_armor_region"
