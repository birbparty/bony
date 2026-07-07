import std/[strutils, tables]

import bddy
import bony
import testutil

proc near(actual, expected: float64): bool =
  abs(actual - expected) <= 1e-6


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


proc requiredRuntimeFixture(): SkeletonData =
  let mesh = meshAttachmentData(
    "weighted_banner",
    @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
    @[0'u16, 1'u16, 2'u16],
    @[
      weightedMeshVertex(@[meshInfluence("gear", 0.0, 0.0, 1.0)]),
      weightedMeshVertex(@[meshInfluence("gear", 2.0, 0.0, 1.0)]),
      weightedMeshVertex(@[meshInfluence("gear", 0.0, 2.0, 1.0)]),
    ],
    true,
  )
  skeletonData(
    skeletonHeader("skin-required-runtime", "1.0.0"),
    @[
      boneData("root", ""),
      boneData("gear", "root", localTransform(x = 5.0), skinRequired = true),
    ],
    @[
      slotData("badge", "gear", "badge"),
      slotData("hit", "gear", "hit"),
      slotData("childHost", "gear", "child"),
      slotData("banner", "root", "banner"),
    ],
    @[regionAttachment("badge_region", 2.0, 2.0)],
    skins = @[
      skinData("default", @[
        skinEntryData("badge", "badge", "badge_region"),
        skinEntryData("hit", "hit", "hit_point"),
        skinEntryData("childHost", "child", "child_rig"),
        skinEntryData("banner", "banner", "weighted_banner"),
      ]),
      skinData("gearSkin", bones = @["gear"]),
    ],
    pointAttachments = @[pointAttachmentData("hit_point", 1.0, 0.0, 0.0)],
    nestedRigAttachments = @[nestedRigAttachmentData("child_rig", "child")],
    meshAttachments = @[mesh],
  )


proc childRuntimeFixture(): SkeletonData =
  skeletonData(
    skeletonHeader("child", "1.0.0"),
    @[boneData("root", "")],
    @[slotData("childSlot", "root", "child")],
    @[regionAttachment("child", 1.0, 1.0)],
  )


proc inactiveConstraintFixture(): SkeletonData =
  skeletonData(
    skeletonHeader("inactive-constraints", "1.0.0"),
    @[
      boneData("root", ""),
      boneData("ikBone", "root", localTransform(x = 1.0)),
      boneData("ikTarget", "root", localTransform(x = 1.0, y = 5.0)),
      boneData("copyBone", "root", localTransform(x = 2.0)),
      boneData("copyTarget", "root", localTransform(x = 8.0)),
      boneData("pathBone", "root", localTransform(x = 3.0)),
      boneData("pathTarget", "root"),
      boneData("laterBone", "root", localTransform(x = 4.0)),
      boneData("laterTarget", "root", localTransform(x = 11.0)),
    ],
    pathAttachments = @[
      pathAttachmentData("rail", 0.0, 0.0, 10.0, 0.0, 20.0, 0.0, 30.0, 0.0),
    ],
    ikConstraints = @[
      ikConstraintData("inactiveIk", "ikTarget", @["ikBone"], skinRequired = true),
    ],
    transformConstraints = @[
      transformConstraintData("inactiveTransform", "copyBone", "copyTarget",
        skinRequired = true, hasTranslateMix = true, translateMix = 1.0),
      transformConstraintData("laterActive", "laterBone", "laterTarget",
        order = 1, hasTranslateMix = true, translateMix = 1.0),
    ],
    paths = @[
      pathConstraintData("inactivePath", "pathBone", "pathTarget", "rail",
        skinRequired = true, hasPosition = true, position = 1.0,
        hasTranslateMix = true, translateMix = 1.0),
    ],
    skins = @[
      skinData("default"),
      skinData("constraintSkin",
        ikConstraints = @["inactiveIk"],
        transformConstraints = @["inactiveTransform"],
        pathConstraints = @["inactivePath"]),
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

    then:
      defaultBatch.slot == "body"
      defaultBatch.attachment == "body_default_region"
      closeTo(defaultBatch.vertices[0].x, -1.0)
      armorBatch.slot == "body"
      armorBatch.attachment == "body_armor_region"
      closeTo(armorBatch.vertices[0].x, -2.0)
      raisesBonyLoadError(proc() = discard buildDrawBatches(data, "missing"), unknownRequiredReference)

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

  it "computes active membership from default plus active skin":
    let data = requiredRuntimeFixture()
    let inactive = activeSkinMembership(data)
    let active = activeSkinMembership(data, "gearSkin")

    then:
      inactive.activeSkin == "default"
      inactive.bones == @[true, false]
      active.bones == @[true, true]

  it "suppresses inactive required slot content, helpers, nested hosts, and mesh influences":
    let data = requiredRuntimeFixture()
    let child = childRuntimeFixture()
    var children = initTable[string, SkeletonData]()
    children["child"] = child

    let inactiveWorlds = computeWorldTransforms(data)
    let activeWorlds = computeWorldTransforms(data, "gearSkin")
    let inactiveBatches = buildDrawBatches(data)
    let activeBatches = buildDrawBatches(data, "gearSkin")
    let inactiveNested = buildNestedDrawBatches(data, children)
    let activeNested = buildNestedDrawBatches(data, children, "gearSkin")
    let activePoint = worldPointAttachmentPose(data, activeWorlds, "hit", "hit", "gearSkin")

    then:
      inactiveBatches.len == 0
      activeBatches.len == 2
      activeBatches[0].slot == "badge"
      activeBatches[1].slot == "banner"
      inactiveNested.len == 0
      activeNested.len == 3
      near(activePoint.x, 6.0)
      raisesBonyLoadError(
        proc() = discard worldPointAttachmentPose(data, inactiveWorlds, "hit", "hit"),
        unknownRequiredReference)

  it "keeps inactive IK, transform, and path constraints as no-op cache entries":
    let data = inactiveConstraintFixture()
    let inactiveWorlds = computeWorldTransforms(data)
    let activeWorlds = computeWorldTransforms(data, "constraintSkin")

    then:
      near(inactiveWorlds[1].tx, 1.0)
      near(inactiveWorlds[1].ty, 0.0)
      near(inactiveWorlds[3].tx, 2.0)
      near(inactiveWorlds[5].tx, 3.0)
      near(inactiveWorlds[7].tx, 11.0)
      near(activeWorlds[3].tx, 8.0)
      near(activeWorlds[5].tx, 30.0)
      near(activeWorlds[7].tx, 11.0)

include smoke_support

spec "skin smoke coverage":
  it "uses default and explicit nested child skins":
    let child = skeletonData(
      skeletonHeader("child", "1.0.0"),
      @[boneData("root", "")],
      @[slotData("face", "root", "face")],
      @[regionAttachment("defaultFace", 2.0, 2.0), regionAttachment("fancyFace", 4.0, 2.0)],
      skins = @[
        skinData("default", @[skinEntryData("face", "face", "defaultFace")]),
        skinData("fancy", @[skinEntryData("face", "face", "fancyFace")]),
      ],
    )
    let host = skeletonData(
      skeletonHeader("host", "1.0.0"),
      @[boneData("root", "")],
      @[
        slotData("defaultSlot", "root", "nested_default"),
        slotData("fancySlot", "root", "nested_fancy"),
      ],
      nestedRigAttachments = @[
        nestedRigAttachmentData("nested_default", "faceRig"),
        nestedRigAttachmentData("nested_fancy", "faceRig", skin = "fancy"),
      ],
      skins = @[skinData("default", @[
        skinEntryData("defaultSlot", "nested_default", "nested_default"),
        skinEntryData("fancySlot", "nested_fancy", "nested_fancy"),
      ])],
    )
    var children = initTable[string, SkeletonData]()
    children["faceRig"] = child
    let batches = buildNestedDrawBatches(host, children)

    then:
      batches.len == 2
      batches[0].attachment == "defaultFace"
      closeTo(batches[0].vertices[0].x, -1.0)
      closeTo(batches[0].vertices[2].x, 1.0)
      batches[1].attachment == "fancyFace"
      closeTo(batches[1].vertices[0].x, -2.0)
      closeTo(batches[1].vertices[2].x, 2.0)
