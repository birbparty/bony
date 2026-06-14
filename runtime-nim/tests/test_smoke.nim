import std/strutils

import bddy
import bony

proc raisesBonyLoadError(input: string): bool =
  try:
    discard loadBonyJson(input)
    false
  except BonyLoadError:
    true


proc raisesBonyLoadError(input: string; kind: BonyLoadErrorKind): bool =
  try:
    discard loadBonyJson(input)
    false
  except BonyLoadError as exc:
    exc.kind == kind

proc closeTo(actual, expected: float64): bool =
  abs(actual - expected) <= 1e-9

proc transformFixture(childMode: TransformMode; parentScaleX = 2.0; parentScaleY = 3.0): SkeletonData =
  let (inheritRotation, inheritScale, inheritReflection) =
    case childMode
    of normal: (true, true, true)
    of onlyTranslation: (false, false, false)
    of noRotationOrReflection: (false, true, false)
    of noScale: (true, false, true)
    of noScaleOrReflection: (true, false, false)
  skeletonData(
    skeletonHeader("demo", "0.1.0"),
    @[
      boneData("root", "", localTransform(scaleX = parentScaleX, scaleY = parentScaleY)),
      boneData(
        "child",
        "root",
        localTransform(
          x = 1.0,
          inheritRotation = inheritRotation,
          inheritScale = inheritScale,
          inheritReflection = inheritReflection,
          transformMode = childMode,
        ),
      ),
    ],
  )

spec "bony package":
  it "exposes version":
    then:
      bonyVersion == "0.1.0"

  it "exports generated registry metadata":
    then:
      bonyRegistryVersion == 1
      bonyBackingTypes.len == 7
      bonyBackingTypes[0].id == "varuint"
      bonyTypeKeys.len == 4
      bonyPropertyKeys.len == 19
      bonyPropertyDefaults.len == 14
      bonyRequiredProperties.len == 7

  it "loads .bony JSON and applies defaults":
    let data = loadBonyJson("""
{
  "skeleton": {
    "name": "demo"
  },
  "bones": [
    {
      "name": "root"
    },
    {
      "name": "child",
      "parent": "root"
    }
  ],
}
""")

    then:
      data.header.name == "demo"
      data.header.version == "0.1.0"
      data.bones.len == 2
      data.bones[0].parent == ""
      data.bones[1].parent == "root"

  it "serializes defaults by omission":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "")]
    )

    let output = toBonyJson(data)

    then:
      output.contains("\"name\": \"demo\"")
      not output.contains("\"version\"")
      not output.contains("\"parent\"")

  it "serializes minimal values canonically":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "")]
    )

    then:
      toBonyJson(data) == """{
  "skeleton": {
    "name": "demo"
  },
  "bones": [
    {
      "name": "root"
    }
  ],
  "slots": [],
  "regions": []
}
"""

  it "serializes non-default values canonically":
    let data = skeletonData(
      skeletonHeader("demo", "0.2.0"),
      @[boneData("root", ""), boneData("child", "root")]
    )

    then:
      toBonyJson(data) == """{
  "skeleton": {
    "name": "demo",
    "version": "0.2.0"
  },
  "bones": [
    {
      "name": "root"
    },
    {
      "name": "child",
      "parent": "root"
    }
  ],
  "slots": [],
  "regions": []
}
"""

  it "rejects duplicate bone names":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root"},{"name":"root"}],"slots":[],"regions":[]}""",
        duplicateKey
      )

  it "rejects child-before-parent order":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"child","parent":"root"},{"name":"root"}],"slots":[],"regions":[]}""",
        orderingViolation
      )

  it "wraps malformed JSON as a load error":
    then:
      raisesBonyLoadError("""{"skeleton":""")

  it "rejects duplicate JSON object keys":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo","name":"dupe"},"bones":[],"slots":[],"regions":[]}""",
        duplicateKey
      )

  it "requires top-level bones":
    then:
      raisesBonyLoadError("""{"skeleton":{"name":"demo"}}""")

  it "defaults missing M2 collections to empty":
    let data = loadBonyJson("""{"skeleton":{"name":"demo"},"bones":[]}""")

    then:
      data.slots.len == 0
      data.regions.len == 0

  it "requires non-empty names":
    then:
      raisesBonyLoadError("""{"skeleton":{"name":""},"bones":[],"slots":[],"regions":[]}""", schemaViolation)

  it "rejects missing parent references":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"child","parent":"missing"}],"slots":[],"regions":[]}""",
        unknownRequiredReference
      )

  it "rejects missing required fields":
    then:
      raisesBonyLoadError("""{"skeleton":{},"bones":[],"slots":[],"regions":[]}""", schemaViolation)
      raisesBonyLoadError("""{"skeleton":{"name":"demo"},"bones":[{}],"slots":[],"regions":[]}""", schemaViolation)

  it "rejects wrong field types and unknown fields":
    then:
      raisesBonyLoadError("""{"skeleton":{"name":7},"bones":[],"slots":[],"regions":[]}""", schemaViolation)
      raisesBonyLoadError("""{"skeleton":{"name":"demo"},"bones":[],"slots":[],"regions":[],"extra":true}""", schemaViolation)

  it "stores f32-backed numeric fields at f32 precision":
    let data = loadBonyJson("""{"skeleton":{"name":"demo"},"bones":[{"name":"root","x":0.1000000001}]}""")
    let expected = quantizeF32(0.1000000001)

    then:
      data.bones[0].local.x == expected
      toBonyJson(data).contains($expected)

  it "rejects f32-backed numeric overflow":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root","x":1e999}]}""",
        numericOutOfRange
      )

  it "computes world transforms in parent-first order":
    let data = loadBonyJson("""
{
  "skeleton": {
    "name": "demo"
  },
  "bones": [
    {
      "name": "root",
      "x": 10,
      "rotation": 90
    },
    {
      "name": "child",
      "parent": "root",
      "x": 2,
      "transformMode": "onlyTranslation",
      "inheritRotation": false,
      "inheritScale": false,
      "inheritReflection": false
    }
  ],
  "slots": [],
  "regions": []
}
""")
    let worlds = computeWorldTransforms(data)

    then:
      worlds.len == 2
      closeTo(worlds[0].tx, 10)
      closeTo(worlds[0].ty, 0)
      closeTo(worlds[1].tx, 10)
      closeTo(worlds[1].ty, 2)
      closeTo(worlds[1].a, 1)
      closeTo(worlds[1].d, 1)

  it "rejects invalid transform flag triples":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root","inheritRotation":false}],"slots":[],"regions":[]}""",
        schemaViolation
      )

  it "evaluates transform inheritance modes":
    let normalWorlds = computeWorldTransforms(transformFixture(normal))
    let translationWorlds = computeWorldTransforms(transformFixture(onlyTranslation))
    let noRotationWorlds = computeWorldTransforms(transformFixture(noRotationOrReflection))
    let noScaleWorlds = computeWorldTransforms(transformFixture(noScale))
    let noScaleReflectionWorlds = computeWorldTransforms(transformFixture(noScaleOrReflection))
    let reflectedNoScale = computeWorldTransforms(transformFixture(noScale, parentScaleX = -2.0))
    let reflectedNoScaleNoReflection = computeWorldTransforms(transformFixture(noScaleOrReflection, parentScaleX = -2.0))
    let degenerateWorlds = computeWorldTransforms(transformFixture(normal, parentScaleX = 0.0, parentScaleY = 2.0))

    then:
      closeTo(normalWorlds[1].tx, 2)
      closeTo(normalWorlds[1].a, 2)
      closeTo(normalWorlds[1].d, 3)
      closeTo(translationWorlds[1].tx, 2)
      closeTo(translationWorlds[1].a, 1)
      closeTo(translationWorlds[1].d, 1)
      closeTo(noRotationWorlds[1].a, 2)
      closeTo(noRotationWorlds[1].d, 3)
      closeTo(noScaleWorlds[1].a, 1)
      closeTo(noScaleWorlds[1].d, 1)
      closeTo(noScaleReflectionWorlds[1].a, 1)
      closeTo(noScaleReflectionWorlds[1].d, 1)
      closeTo(reflectedNoScale[1].a, -1)
      closeTo(reflectedNoScale[1].d, 1)
      closeTo(reflectedNoScaleNoReflection[1].a, -1)
      closeTo(reflectedNoScaleNoReflection[1].d, -1)
      closeTo(degenerateWorlds[1].a, 0)
      closeTo(degenerateWorlds[1].d, 2)

  it "rejects invalid M2 region data":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root"}],"regions":[{"name":"r","width":-1,"height":1}]}""",
        schemaViolation
      )

  it "emits draw batches in slot order":
    let data = loadBonyJson("""
{
  "skeleton": {
    "name": "demo"
  },
  "bones": [
    {
      "name": "root",
      "x": 3
    }
  ],
  "slots": [
    {
      "name": "body",
      "bone": "root",
      "attachment": "bodyRegion"
    }
  ],
  "regions": [
    {
      "name": "bodyRegion",
      "width": 8,
      "height": 4
    }
  ]
}
""")
    let batches = buildDrawBatches(data)

    then:
      batches.len == 1
      batches[0].slot == "body"
      batches[0].bone == "root"
      batches[0].attachment == "bodyRegion"
      closeTo(batches[0].world.tx, 3)
      batches[0].texturePage == ""
      batches[0].blendMode == "normal"
      batches[0].clipId == ""
      batches[0].vertices.len == 4
      batches[0].indices == @[0'u16, 1'u16, 2'u16, 2'u16, 3'u16, 0'u16]
      closeTo(batches[0].vertices[0].x, -1)
      closeTo(batches[0].vertices[0].y, -2)
      closeTo(batches[0].vertices[2].x, 7)
      closeTo(batches[0].vertices[2].y, 2)
      closeTo(batches[0].vertices[2].u, 1)
      closeTo(batches[0].vertices[2].v, 1)
      closeTo(batches[0].vertices[2].a, 1)

  it "serializes M2 region and slot data":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "", localTransform(x = 3.0))],
      @[slotData("body", "root", "bodyRegion")],
      @[regionAttachment("bodyRegion", 8.0, 4.0)]
    )
    let output = toBonyJson(data)

    then:
      output.contains("\"x\": 3.0")
      output.contains("\"slots\"")
      output.contains("\"regions\"")
