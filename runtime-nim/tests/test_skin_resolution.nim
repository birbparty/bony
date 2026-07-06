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

const skinRequiredJson = """{
  "skeleton": { "name": "skin-required", "version": "1.0.0" },
  "bones": [
    { "name": "root" },
    { "name": "gear", "parent": "root", "skinRequired": true }
  ],
  "pathAttachments": [
    { "name": "rail", "p0x": 0, "p0y": 0, "p1x": 1, "p1y": 0, "p2x": 2, "p2y": 0, "p3x": 3, "p3y": 0 }
  ],
  "ikConstraints": [
    { "name": "aim", "bones": ["gear"], "target": "root", "skinRequired": true }
  ],
  "transformConstraints": [
    { "name": "copy", "bone": "gear", "target": "root", "skinRequired": true }
  ],
  "paths": [
    { "name": "follow", "bone": "gear", "target": "root", "path": "rail", "skinRequired": true }
  ],
  "physicsConstraints": [
    { "name": "spring", "bone": "gear", "channels": 1, "skinRequired": true }
  ],
  "skins": [
    {
      "name": "default",
      "bones": ["gear"],
      "ikConstraints": ["aim"],
      "transformConstraints": ["copy"],
      "pathConstraints": ["follow"],
      "physicsConstraints": ["spring"]
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

  it "round-trips skinRequired flags and skin membership through JSON and BNB":
    let data = loadBonyJson(skinRequiredJson)
    let jsonText = toBonyJson(data)
    let fromJson = loadBonyJson(jsonText)
    let fromBnb = loadBonyBnb(toBonyBnb(data))

    then:
      data.bones[1].skinRequired
      data.ikConstraints[0].skinRequired
      data.transformConstraints[0].skinRequired
      data.paths[0].skinRequired
      data.physicsConstraints[0].skinRequired
      jsonText.contains("\"skinRequired\": true")
      jsonText.contains("\"bones\": [\"gear\"]")
      fromJson.skins[0].bones == @["gear"]
      fromJson.skins[0].ikConstraints == @["aim"]
      fromBnb.bones[1].skinRequired
      fromBnb.skins[0].transformConstraints == @["copy"]
      fromBnb.skins[0].pathConstraints == @["follow"]
      fromBnb.skins[0].physicsConstraints == @["spring"]

  it "rejects malformed skinRequired membership":
    let unknownRef = skinRequiredJson.replace(
      "\"name\": \"default\",\n      \"bones\": [\"gear\"]",
      "\"name\": \"default\",\n      \"bones\": [\"ghost\"]",
    )
    let duplicateRef = skinRequiredJson.replace(
      "\"name\": \"default\",\n      \"bones\": [\"gear\"]",
      "\"name\": \"default\",\n      \"bones\": [\"gear\", \"gear\"]",
    )
    let nonRequiredRef = skinRequiredJson.replace(
      "\"name\": \"default\",\n      \"bones\": [\"gear\"]",
      "\"name\": \"default\",\n      \"bones\": [\"root\"]",
    )
    let nonRequiredDescendant = skinRequiredJson.replace(
      "{ \"name\": \"gear\", \"parent\": \"root\", \"skinRequired\": true }",
      "{ \"name\": \"gear\", \"parent\": \"root\", \"skinRequired\": true }, { \"name\": \"leaf\", \"parent\": \"gear\" }",
    )
    let missingRequiredParent = skinRequiredJson.replace(
      "{ \"name\": \"root\" }",
      "{ \"name\": \"root\", \"skinRequired\": true }",
    )
    let requiredConstraintMissingDependency = skinRequiredJson
      .replace("\"bones\": [\"gear\"],\n      \"ikConstraints\"", "\"bones\": [],\n      \"ikConstraints\"")
    let nonRequiredConstraintWithInactiveDependency = skinRequiredJson
      .replace("\"name\": \"default\",\n      \"bones\": [\"gear\"]", "\"name\": \"default\",")
      .replace("\"skinRequired\": true }\n  ],\n  \"paths\"", "\"skinRequired\": false }\n  ],\n  \"paths\"")

    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(unknownRef), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard loadBonyJson(duplicateRef), duplicateKey)
      raisesBonyLoadError(proc() = discard loadBonyJson(nonRequiredRef), schemaViolation)
      raisesBonyLoadError(proc() = discard loadBonyJson(nonRequiredDescendant), schemaViolation)
      raisesBonyLoadError(proc() = discard loadBonyJson(missingRequiredParent), schemaViolation)
      raisesBonyLoadError(proc() = discard loadBonyJson(requiredConstraintMissingDependency), schemaViolation)
      raisesBonyLoadError(proc() = discard loadBonyJson(nonRequiredConstraintWithInactiveDependency), schemaViolation)
