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

proc raisesBonyLoadError(action: proc(); kind: BonyLoadErrorKind): bool =
  try:
    action()
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

proc animationFixture(): SkeletonData =
  skeletonData(
    skeletonHeader("demo", "0.1.0"),
    @[boneData("root", "")],
    @[slotData("body", "root", "")],
    @[regionAttachment("idle", 1.0, 1.0), regionAttachment("wave", 1.0, 1.0)],
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

  it "builds unweighted mesh attachments":
    let data = animationFixture()
    let mesh = unweightedMeshAttachment(
      data,
      "cloth",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0), meshUv(0.0, 1.0)],
      @[0'u16, 1'u16, 2'u16, 2'u16, 3'u16, 0'u16],
      @[
        unweightedMeshVertex(-1.0, -1.0),
        unweightedMeshVertex(1.0, -1.0),
        unweightedMeshVertex(1.0, 1.0),
        unweightedMeshVertex(-1.0, 1.0),
      ],
      hull = 4'u32,
      edges = @[0'u16, 1'u16, 1'u16, 2'u16, 2'u16, 3'u16, 3'u16, 0'u16],
    )

    then:
      mesh.name == "cloth"
      mesh.path == "cloth"
      mesh.weighted == false
      mesh.uvs.len == 4
      mesh.vertices.len == 4
      mesh.triangles.len == 6
      mesh.hull == 4'u32
      closeTo(mesh.vertices[2].x, 1.0)
      closeTo(mesh.vertices[2].y, 1.0)

  it "builds weighted mesh bind data":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[
        boneData("root", ""),
        boneData("child", "root", localTransform(x = 1.0)),
      ],
    )
    let mesh = weightedMeshAttachment(
      data,
      "weightedCloth",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.5, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[
        weightedMeshVertex(@[meshInfluence("root", -1.0, 0.0, 1.0)]),
        weightedMeshVertex(@[meshInfluence("child", 1.0, 0.0, 1.0)]),
        weightedMeshVertex(@[
          meshInfluence("root", 0.0, 1.0, 0.25),
          meshInfluence("child", 0.0, 1.0, 0.75),
        ]),
      ],
      path = "clothPage",
      deformAttachment = "weightedCloth",
    )

    then:
      mesh.weighted
      mesh.path == "clothPage"
      mesh.deformAttachment == "weightedCloth"
      mesh.vertices[2].influences.len == 2
      mesh.vertices[2].influences[0].bone == "root"
      closeTo(mesh.vertices[2].influences[1].weight, 0.75)

  it "rejects invalid mesh attachment data":
    let data = animationFixture()

    then:
      raisesBonyLoadError(
        proc() = discard unweightedMeshAttachment(
          data,
          "badUvs",
          @[meshUv(0.0, 0.0)],
          @[0'u16, 1'u16, 2'u16],
          @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard unweightedMeshAttachment(
          data,
          "badIndex",
          @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
          @[0'u16, 1'u16, 3'u16],
          @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(
        proc() = discard unweightedMeshAttachment(
          data,
          "badEdges",
          @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
          @[0'u16, 1'u16, 2'u16],
          @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
          edges = @[0'u16, 1'u16, 2'u16],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard weightedMeshAttachment(
          data,
          "badBone",
          @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
          @[0'u16, 1'u16, 2'u16],
          @[
            weightedMeshVertex(@[meshInfluence("missing", 0.0, 0.0, 1.0)]),
            weightedMeshVertex(@[meshInfluence("root", 1.0, 0.0, 1.0)]),
            weightedMeshVertex(@[meshInfluence("root", 0.0, 1.0, 1.0)]),
          ],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(
        proc() = discard weightedMeshVertex(@[
          meshInfluence("root", 0.0, 0.0, 0.25),
          meshInfluence("root", 1.0, 0.0, 0.25),
        ]),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = validateMeshAttachment(
          data,
          MeshAttachment(
            name: "directEmptyInfluences",
            path: "directEmptyInfluences",
            uvs: @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
            triangles: @[0'u16, 1'u16, 2'u16],
            vertices: @[
              MeshVertex(weighted: true, influences: @[]),
              weightedMeshVertex(@[meshInfluence("root", 1.0, 0.0, 1.0)]),
              weightedMeshVertex(@[meshInfluence("root", 0.0, 1.0, 1.0)]),
            ],
            weighted: true,
            deformAttachment: "directEmptyInfluences",
          ),
        ),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = validateMeshAttachment(
          data,
          MeshAttachment(
            name: "directBadWeight",
            path: "directBadWeight",
            uvs: @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
            triangles: @[0'u16, 1'u16, 2'u16],
            vertices: @[
              MeshVertex(weighted: true, influences: @[MeshInfluence(bone: "root", weight: -1.0)]),
              weightedMeshVertex(@[meshInfluence("root", 1.0, 0.0, 1.0)]),
              weightedMeshVertex(@[meshInfluence("root", 0.0, 1.0, 1.0)]),
            ],
            weighted: true,
            deformAttachment: "directBadWeight",
          ),
        ),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = validateMeshAttachment(
          data,
          MeshAttachment(
            name: "directBadUv",
            path: "directBadUv",
            uvs: @[MeshUv(u: 2.0, v: 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
            triangles: @[0'u16, 1'u16, 2'u16],
            vertices: @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
            deformAttachment: "directBadUv",
          ),
        ),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard weightedMeshAttachment(
          data,
          "linkedUnsupported",
          @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
          @[0'u16, 1'u16, 2'u16],
          @[
            weightedMeshVertex(@[meshInfluence("root", 0.0, 0.0, 1.0)]),
            weightedMeshVertex(@[meshInfluence("root", 1.0, 0.0, 1.0)]),
            weightedMeshVertex(@[meshInfluence("root", 0.0, 1.0, 1.0)]),
          ],
          parentMesh = "baseMesh",
        ),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard weightedMeshAttachment(
          data,
          "deformTargetUnsupported",
          @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
          @[0'u16, 1'u16, 2'u16],
          @[
            weightedMeshVertex(@[meshInfluence("root", 0.0, 0.0, 1.0)]),
            weightedMeshVertex(@[meshInfluence("root", 1.0, 0.0, 1.0)]),
            weightedMeshVertex(@[meshInfluence("root", 0.0, 1.0, 1.0)]),
          ],
          deformAttachment = "otherMesh",
        ),
        schemaViolation,
      )

  it "skins unweighted mesh vertices through the slot bone":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "", localTransform(x = 3.0, y = 2.0))],
      @[slotData("body", "root", "")],
    )
    let mesh = unweightedMeshAttachment(
      data,
      "quad",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(-1.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(1.0, 2.0)],
    )
    let vertices = skinMeshVertices(data, data.slots[0], mesh)

    then:
      vertices.len == 3
      closeTo(vertices[0].x, 2.0)
      closeTo(vertices[0].y, 2.0)
      closeTo(vertices[2].x, 4.0)
      closeTo(vertices[2].y, 4.0)
      closeTo(vertices[2].u, 1.0)
      closeTo(vertices[2].v, 1.0)

  it "skins weighted mesh vertices in influence order":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[
        boneData("root", "", localTransform(x = 10.0)),
        boneData("child", "root", localTransform(y = 4.0)),
      ],
    )
    let mesh = weightedMeshAttachment(
      data,
      "weighted",
      @[meshUv(0.5, 0.5)],
      @[0'u16, 0'u16, 0'u16],
      @[
        weightedMeshVertex(@[
          meshInfluence("root", 2.0, 0.0, 0.25),
          meshInfluence("child", 0.0, 2.0, 0.75),
        ]),
      ],
    )
    let vertices = skinMeshVertices(data, computeWorldTransforms(data), "root", mesh)

    then:
      vertices.len == 1
      closeTo(vertices[0].x, quantizeF32(10.5))
      closeTo(vertices[0].y, quantizeF32(4.5))

  it "skins weighted mesh vertices through full affine transforms":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "", localTransform(rotation = 90.0, scaleX = 2.0))],
    )
    let mesh = weightedMeshAttachment(
      data,
      "weightedAffine",
      @[meshUv(0.0, 0.0)],
      @[0'u16, 0'u16, 0'u16],
      @[weightedMeshVertex(@[meshInfluence("root", 1.0, 0.0, 1.0)])],
    )
    let vertices = skinMeshVertices(data, computeWorldTransforms(data), "root", mesh)

    then:
      closeTo(vertices[0].x, quantizeF32(0.0))
      closeTo(vertices[0].y, quantizeF32(2.0))

  it "uses caller-provided world transforms for mesh skinning":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "")],
    )
    let mesh = unweightedMeshAttachment(
      data,
      "manualWorld",
      @[meshUv(0.0, 0.0)],
      @[0'u16, 0'u16, 0'u16],
      @[unweightedMeshVertex(1.0, 1.0)],
    )
    let vertices = skinMeshVertices(data, @[Affine2(a: 1.0, d: 1.0, tx: 4.0, ty: 5.0)], "root", mesh)

    then:
      closeTo(vertices[0].x, 5.0)
      closeTo(vertices[0].y, 6.0)

  it "rejects unsupported mesh skinning modes and invalid world arrays":
    let data = animationFixture()
    let mesh = unweightedMeshAttachment(
      data,
      "tri",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
    )

    then:
      raisesBonyLoadError(
        proc() = discard skinMeshVertices(data, "root", mesh, dualQuaternionSkinningHook),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard skinMeshVertices(data, newSeq[Affine2](), "root", mesh),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard skinMeshVertices(data, "missing", mesh),
        unknownRequiredReference,
      )

  it "samples mesh deform timelines with offset expansion":
    let data = animationFixture()
    let mesh = unweightedMeshAttachment(
      data,
      "deformable",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(1.0, 1.0)],
    )
    let timeline = deformTimeline(
      "default",
      "body",
      mesh,
      @[
        deformKeyframe(0.0, 1'u32, @[meshDelta(2.0, 0.0)]),
        deformKeyframe(1.0, 0'u32, @[meshDelta(0.0, 1.0), meshDelta(4.0, 0.0), meshDelta(0.0, 2.0)]),
      ],
    )
    let start = sampleDeformDeltas(timeline, 0.0)
    let middle = sampleDeformDeltas(timeline, 0.5)

    then:
      start.len == 3
      closeTo(start[0].x, 0.0)
      closeTo(start[1].x, 2.0)
      closeTo(start[2].y, 0.0)
      closeTo(middle[0].y, 0.5)
      closeTo(middle[1].x, 3.0)
      closeTo(middle[2].y, 1.0)

  it "samples stepped and bezier mesh deform keys":
    let data = animationFixture()
    let mesh = unweightedMeshAttachment(
      data,
      "curveDeform",
      @[meshUv(0.0, 0.0)],
      @[0'u16, 0'u16, 0'u16],
      @[unweightedMeshVertex(0.0, 0.0)],
    )
    let stepped = deformTimeline(
      "default",
      "body",
      mesh,
      @[deformKeyframe(0.0, 0'u32, @[meshDelta(2.0, 0.0)], steppedCurve), deformKeyframe(1.0, 0'u32, @[meshDelta(6.0, 0.0)])],
    )
    let bezier = deformTimeline(
      "default",
      "body",
      mesh,
      @[deformKeyframe(0.0, 0'u32, @[meshDelta(0.0, 0.0)], bezierTimelineCurve(0.25, 0.0, 0.75, 1.0)), deformKeyframe(1.0, 0'u32, @[meshDelta(10.0, 0.0)])],
    )

    then:
      closeTo(sampleDeformDeltas(stepped, 0.5)[0].x, 2.0)
      closeTo(sampleDeformDeltas(bezier, 0.5)[0].x, 5.0)

  it "applies mesh deform deltas after skinning":
    let data = animationFixture()
    let mesh = unweightedMeshAttachment(
      data,
      "applyDeform",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
    )
    let timeline = deformTimeline(
      "default",
      "body",
      mesh,
      @[deformKeyframe(0.0, 0'u32, @[meshDelta(1.0, 0.0), meshDelta(0.0, 2.0), meshDelta(-1.0, -1.0)])],
    )
    let skinned = skinMeshVertices(data, "root", mesh)
    let deformed = applyDeformTimeline(skinned, mesh, timeline, 0.0)

    then:
      closeTo(deformed[0].x, 1.0)
      closeTo(deformed[1].y, 2.0)
      closeTo(deformed[2].x, -1.0)
      closeTo(deformed[2].y, 0.0)
      closeTo(deformed[1].u, skinned[1].u)

  it "rounds direct mesh deform key data at sample time":
    let timeline = DeformTimeline(
      skin: "default",
      slot: "body",
      attachment: "directDeform",
      vertexCount: 1,
      keys: @[DeformKeyframe(time: 0.0, offset: 0'u32, deltas: @[MeshDelta(x: 0.1, y: 0.2)])],
    )
    let sampled = sampleDeformDeltas(timeline, 0.0)

    then:
      closeTo(sampled[0].x, quantizeF32(0.1))
      closeTo(sampled[0].y, quantizeF32(0.2))

  it "rejects invalid direct mesh deform data":
    let timeline = DeformTimeline(
      skin: "default",
      slot: "body",
      attachment: "directBadDeform",
      vertexCount: 1,
      keys: @[DeformKeyframe(time: 0.0, offset: 0'u32, deltas: @[MeshDelta(x: Inf, y: 0.0)])],
    )

    then:
      raisesBonyLoadError(proc() = discard sampleDeformDeltas(timeline, 0.0), numericOutOfRange)

  it "rejects applying deform timelines to the wrong attachment":
    let data = animationFixture()
    let source = unweightedMeshAttachment(
      data,
      "sourceDeform",
      @[meshUv(0.0, 0.0)],
      @[0'u16, 0'u16, 0'u16],
      @[unweightedMeshVertex(0.0, 0.0)],
    )
    let target = unweightedMeshAttachment(
      data,
      "targetDeform",
      @[meshUv(0.0, 0.0)],
      @[0'u16, 0'u16, 0'u16],
      @[unweightedMeshVertex(0.0, 0.0)],
    )
    let timeline = deformTimeline(
      "default",
      "body",
      source,
      @[deformKeyframe(0.0, 0'u32, @[meshDelta(1.0, 0.0)])],
    )
    let skinned = skinMeshVertices(data, "root", target)

    then:
      raisesBonyLoadError(proc() = discard applyDeformTimeline(skinned, target, timeline, 0.0), schemaViolation)

  it "rejects invalid mesh deform timelines":
    let data = animationFixture()
    let mesh = unweightedMeshAttachment(
      data,
      "badDeform",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0)],
      @[0'u16, 1'u16, 1'u16],
      @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0)],
    )

    then:
      raisesBonyLoadError(
        proc() = discard deformTimeline("default", "body", mesh, @[deformKeyframe(0.0, 2'u32, @[meshDelta(1.0, 0.0)])]),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard deformTimeline("default", "body", mesh, @[deformKeyframe(1.0, 0'u32, @[meshDelta(1.0, 0.0)]), deformKeyframe(0.5, 0'u32, @[meshDelta(2.0, 0.0)])]),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard sampleDeformDeltas(deformTimeline("default", "body", mesh, @[deformKeyframe(0.0, 0'u32, @[meshDelta(1.0, 0.0)])]), -0.1),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard applyDeformDeltas(@[SkinnedMeshVertex(x: 0.0)], @[meshDelta(1.0, 0.0), meshDelta(2.0, 0.0)]),
        schemaViolation,
      )

  it "builds sorted scalar bone timelines and samples linearly":
    let timeline = boneScalarTimeline(
      "root",
      rotateTimeline,
      @[
        scalarKeyframe(0.0, 0.0),
        scalarKeyframe(1.0, 90.0),
      ],
    )
    let sampled = timeline.sample(0.5)

    then:
      timeline.target == "root"
      timeline.kind == rotateTimeline
      closeTo(sampled.time, 0.5)
      closeTo(sampled.value, 45)
      timeline.scalarKeys[1].time == quantizeF32(1.0)

  it "rejects unsorted timeline keyframes":
    then:
      raisesBonyLoadError(
        proc() =
          discard boneVectorTimeline(
            "root",
            translateTimeline,
            @[
              vector2Keyframe(1.0, 1.0, 2.0),
              vector2Keyframe(0.5, 3.0, 4.0),
            ],
          ),
        schemaViolation
      )

  it "samples vector bone timelines with independent stepped components":
    let timeline = boneVectorTimeline(
      "root",
      translateTimeline,
      @[
        vector2Keyframe(0.0, 0.0, 10.0, curveY = steppedCurve),
        vector2Keyframe(1.0, 10.0, 20.0),
      ],
    )
    let sampled = timeline.sampleVector(0.25)

    then:
      closeTo(sampled.x, 2.5)
      closeTo(sampled.y, 10.0)
      raisesBonyLoadError(proc() = discard timeline.sample(0.25), schemaViolation)

  it "samples inherit timelines as discrete flag changes":
    let timeline = boneInheritTimeline(
      "root",
      @[
        inheritKeyframe(0.0),
        inheritKeyframe(
          1.0,
          inheritRotation = false,
          inheritScale = false,
          inheritReflection = false,
          transformMode = onlyTranslation,
        ),
      ],
    )

    then:
      timeline.sampleInherit(0.5).transformMode == normal
      timeline.sampleInherit(1.5).transformMode == onlyTranslation
      raisesBonyLoadError(
        proc() =
          discard inheritKeyframe(0.0, inheritRotation = false, transformMode = onlyTranslation),
        schemaViolation
      )

  it "builds slot attachment and sequence timelines":
    let attachments = slotAttachmentTimeline(
      "body",
      @[
        attachmentKeyframe(0.0, "idle"),
        attachmentKeyframe(1.0, ""),
      ],
    )
    let sequence = slotSequenceTimeline(
      "body",
      @[
        sequenceKeyframe(0.0, 0'u32, 0.1, sequenceLoop),
        sequenceKeyframe(2.0, 4'u32, 0.2, sequenceHold),
      ],
    )

    then:
      attachments.sampleAttachment(0.25).attachment == "idle"
      attachments.sampleAttachment(1.0).attachment == ""
      sequence.sampleSequenceKey(1.0).mode == sequenceLoop
      sequence.sampleSequence(0.35, 5).index == 3'u32
      sequence.sampleSequence(2.5, 5).index == 4'u32

  it "builds slot color timelines and validates normalized channels":
    let rgba = slotColorTimeline(
      "body",
      rgbaTimeline,
      @[
        colorKeyframe(0.0, colorRgba(1.0, 0.0, 0.0, 1.0)),
        colorKeyframe(1.0, colorRgba(0.0, 0.0, 1.0, 0.5)),
      ],
    )
    let rgba2 = slotColor2Timeline(
      "body",
      @[
        color2Keyframe(0.0, colorRgba2(colorRgba(1.0, 1.0, 1.0, 1.0), 0.0, 0.0, 0.0)),
        color2Keyframe(1.0, colorRgba2(colorRgba(0.5, 0.5, 0.5, 1.0), 0.25, 0.5, 0.75)),
      ],
    )
    let sampled = rgba.sampleColor(0.5)
    let sampled2 = rgba2.sampleColor2(0.5)

    then:
      closeTo(sampled.color.r, 0.5)
      closeTo(sampled.color.b, 0.5)
      closeTo(sampled.color.a, 0.75)
      closeTo(sampled2.color.light.r, 0.75)
      closeTo(sampled2.color.darkB, 0.375)
      raisesBonyLoadError(proc() = discard colorRgba(1.1, 0.0, 0.0, 1.0), schemaViolation)

  it "builds animation clips with validated targets and computed duration":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "")],
      @[slotData("body", "root", "")],
      @[regionAttachment("idle", 1.0, 1.0), regionAttachment("wave", 1.0, 1.0)],
    )
    let clip = animationClip(
      data,
      "wave",
      @[
        boneScalarTimeline(
          "root",
          rotateTimeline,
          @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.25, 20.0)],
        ),
      ],
      @[
        slotAttachmentTimeline(
          "body",
          @[attachmentKeyframe(0.0, "idle"), attachmentKeyframe(2.0, "wave")],
        ),
      ],
    )

    then:
      clip.name == "wave"
      closeTo(clip.duration, 2.0)
      clip.boneTimelines.len == 1
      clip.slotTimelines.len == 1
      raisesBonyLoadError(
        proc() =
          discard animationClip(
            data,
            "bad",
            @[boneScalarTimeline("missing", rotateTimeline, @[scalarKeyframe(0.0, 0.0)])],
          ),
        unknownRequiredReference
      )
      raisesBonyLoadError(
        proc() =
          discard animationClip(
            data,
            "badAttachment",
            slotTimelines = @[
              slotAttachmentTimeline("body", @[attachmentKeyframe(0.0, "missing")]),
            ],
          ),
        unknownRequiredReference
      )

  it "evaluates fixed-table bezier curves":
    let symmetric = bezierTimelineCurve(0.25, 0.0, 0.75, 1.0)
    let easeIn = bezierTimelineCurve(0.42, 0.0, 1.0, 1.0)
    let stepped = scalarKeyframe(0.0, 10.0, steppedCurve)

    then:
      closeTo(symmetric.evaluate(0.0), 0.0)
      closeTo(symmetric.evaluate(0.5), 0.5)
      closeTo(symmetric.evaluate(1.0), 1.0)
      closeTo(symmetric.evaluate(-1.0), 0.0)
      closeTo(symmetric.evaluate(2.0), 1.0)
      easeIn.evaluate(0.25) < 0.25
      stepped.curve.kind == steppedCurve
      colorKeyframe(0.0, colorRgba(1.0, 1.0, 1.0, 1.0), linearCurve).curve.kind == linearCurve
      raisesBonyLoadError(proc() = discard bezierTimelineCurve(-0.1, 0.0, 1.0, 1.0), schemaViolation)
      raisesBonyLoadError(proc() = discard bezierTimelineCurve(0.0, 0.0, 1.1, 1.0), schemaViolation)
      raisesBonyLoadError(proc() = discard timelineCurve(bezierCurve), schemaViolation)

  it "samples bezier keyframes per component":
    let timeline = boneVectorTimeline(
      "root",
      translateTimeline,
      @[
        vector2Keyframe(
          0.0,
          0.0,
          0.0,
          curveX = bezierTimelineCurve(0.25, 0.0, 0.75, 1.0),
          curveY = steppedTimelineCurve,
        ),
        vector2Keyframe(1.0, 100.0, 100.0),
      ],
    )
    let sampled = timeline.sampleVector(0.5)

    then:
      closeTo(sampled.x, 50.0)
      closeTo(sampled.y, 0.0)

  it "builds event timelines with per-fire overrides":
    let data = animationFixture()
    let footstep = eventData(
      "footstep",
      intValue = 1'i32,
      floatValue = 0.5,
      stringValue = "left",
      audioPath = "step.wav",
      volume = 0.8,
      balance = -0.25,
    )
    let clip = animationClip(
      data,
      "walk",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.25, footstep, 2'i32, 0.75, "right"),
        eventKeyframe(0.5, footstep),
      ])],
    )
    let keys = clip.eventTimelines[0].keys

    then:
      closeTo(clip.duration, 0.5)
      keys.len == 2
      keys[0].event.name == "footstep"
      keys[0].event.intValue == 2'i32
      closeTo(keys[0].event.floatValue, 0.75)
      keys[0].event.stringValue == "right"
      keys[0].event.audioPath == "step.wav"
      closeTo(keys[0].event.volume, quantizeF32(0.8))
      closeTo(keys[0].event.balance, quantizeF32(-0.25))
      keys[1].event.intValue == 1'i32
      raisesBonyLoadError(proc() = discard eventTimeline(@[eventKeyframe(1.0, footstep), eventKeyframe(0.5, footstep)]), schemaViolation)

  it "dispatches animation events advanced by update":
    let data = animationFixture()
    let clip = animationClip(
      data,
      "events",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.25, eventData("first")),
        eventKeyframe(0.5, eventData("second")),
      ])],
    )
    var state = animationState(1)
    state.setAnimation(0, clip)
    state.update(0.3)

    then:
      state.events.len == 1
      state.events[0].trackIndex == 0
      state.events[0].event.name == "first"
      closeTo(state.events[0].time, 0.25)

    state.update(0.3)

    then:
      state.events.len == 1
      state.events[0].event.name == "second"

  it "dispatches events from multiple timelines chronologically":
    let data = animationFixture()
    let clip = animationClip(
      data,
      "orderedEvents",
      eventTimelines = @[
        eventTimeline(@[
          eventKeyframe(0.8, eventData("late")),
          eventKeyframe(0.8, eventData("sameTimeFirst")),
        ]),
        eventTimeline(@[
          eventKeyframe(0.2, eventData("early")),
          eventKeyframe(0.8, eventData("sameTimeSecond")),
        ]),
      ],
    )
    var state = animationState(1)
    state.setAnimation(0, clip)
    state.update(1.0)

    then:
      state.events.len == 4
      state.events[0].event.name == "early"
      state.events[1].event.name == "late"
      state.events[2].event.name == "sameTimeFirst"
      state.events[3].event.name == "sameTimeSecond"

  it "dispatches looped events across wrapped time":
    let data = animationFixture()
    let clip = animationClip(
      data,
      "loop",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.25, eventData("tap")),
        eventKeyframe(0.75, eventData("end")),
      ])],
    )
    var state = animationState(1)
    state.setAnimation(0, clip, loop = true)
    state.update(1.0)

    then:
      state.events.len == 3
      state.events[0].event.name == "tap"
      state.events[1].event.name == "end"
      state.events[2].event.name == "tap"
      closeTo(state.events[2].time, 1.0)

  it "gates incoming events by mix threshold during crossfade":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 0.0)])],
    )
    let attack = animationClip(
      data,
      "attack",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.2, eventData("tooEarly")),
        eventKeyframe(0.6, eventData("hit")),
      ])],
    )
    var state = animationState(1)
    state.setAnimation(0, idle)
    state.addAnimation(0, attack, delay = 0.1, mixDuration = 1.0)
    state.tracks[0].eventThreshold = 0.5
    state.update(0.1)
    state.update(0.4)

    then:
      state.events.len == 0

    state.update(0.2)

    then:
      state.events.len == 1
      state.events[0].event.name == "hit"

  it "does not dispatch pre-threshold events during a large crossfade update":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 0.0)])],
    )
    let attack = animationClip(
      data,
      "attack",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.2, eventData("tooEarly")),
        eventKeyframe(0.6, eventData("hit")),
      ])],
    )
    var state = animationState(1)
    state.setAnimation(0, idle)
    state.addAnimation(0, attack, delay = 0.1, mixDuration = 1.0)
    state.tracks[0].eventThreshold = 0.5
    state.update(0.75)

    then:
      state.events.len == 1
      state.events[0].event.name == "hit"

  it "mixes queued animation tracks with crossfade":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 10.0)])],
      @[slotAttachmentTimeline("body", @[attachmentKeyframe(0.0, "idle")])],
    )
    let wave = animationClip(
      data,
      "wave",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 100.0), scalarKeyframe(1.0, 120.0)])],
      @[slotAttachmentTimeline("body", @[attachmentKeyframe(0.0, "wave")])],
    )
    var state = animationState(1)
    state.setAnimation(0, idle)
    state.addAnimation(0, wave, delay = 0.5, mixDuration = 1.0)
    state.update(0.5)
    state.update(0.5)
    let pose = state.sample()

    then:
      pose.scalars.len == 1
      closeTo(pose.scalars[0].value, 57.5)
      pose.attachments.len == 1
      pose.attachments[0].attachment == "wave"

  it "applies track alpha and additive mix blend":
    let data = animationFixture()
    let base = animationClip(
      data,
      "base",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 10.0), scalarKeyframe(1.0, 20.0)])],
    )
    let additive = animationClip(
      data,
      "add",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 4.0), scalarKeyframe(1.0, 8.0)])],
    )
    var state = animationState(2)
    state.setAnimation(0, base)
    state.setAnimation(1, additive, blend = addMix)
    state.tracks[1].alpha = 0.5
    state.update(0.5)
    let pose = state.sample()

    then:
      pose.scalars.len == 1
      closeTo(pose.scalars[0].value, 18.0)

  it "uses setup pose baselines for replace mixing":
    var dataValue = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "", localTransform(scaleX = 1.0, scaleY = 1.0))],
    )
    let data = new SkeletonData
    data[] = dataValue
    let scaleUp = animationClip(
      data[],
      "scaleUp",
      @[boneVectorTimeline("root", scaleTimeline, @[vector2Keyframe(0.0, 2.0, 2.0)])],
    )
    var state = animationState(data, 1)
    state.setAnimation(0, scaleUp)
    state.tracks[0].alpha = 0.5
    let pose = state.sample()

    then:
      pose.vectors.len == 1
      closeTo(pose.vectors[0].x, 1.5)
      closeTo(pose.vectors[0].y, 1.5)

  it "gates discrete attachments by mix threshold":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      slotTimelines = @[slotAttachmentTimeline("body", @[attachmentKeyframe(0.0, "idle")])],
    )
    let wave = animationClip(
      data,
      "wave",
      slotTimelines = @[slotAttachmentTimeline("body", @[attachmentKeyframe(0.0, "wave")])],
    )
    var state = animationState(1)
    state.setAnimation(0, idle)
    state.addAnimation(0, wave, delay = 0.1, mixDuration = 1.0)
    state.tracks[0].mixAttachmentThreshold = 0.75
    state.update(0.1)
    state.update(0.2)
    let pose = state.sample()

    then:
      pose.attachments.len == 1
      pose.attachments[0].attachment == "idle"

  it "keeps queued crossfades frame-step independent":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 10.0)])],
    )
    let wave = animationClip(
      data,
      "wave",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 100.0), scalarKeyframe(1.0, 120.0)])],
    )
    var single = animationState(1)
    single.setAnimation(0, idle)
    single.addAnimation(0, wave, delay = 0.5, mixDuration = 1.0)
    single.update(0.75)
    let singlePose = single.sample()

    var split = animationState(1)
    split.setAnimation(0, idle)
    split.addAnimation(0, wave, delay = 0.5, mixDuration = 1.0)
    split.update(0.5)
    split.update(0.25)
    let splitPose = split.sample()

    then:
      closeTo(singlePose.scalars[0].value, splitPose.scalars[0].value)

  it "samples every existing timeline kind into mixed poses":
    let data = animationFixture()
    let clip = animationClip(
      data,
      "allKinds",
      @[
        boneInheritTimeline(
          "root",
          @[inheritKeyframe(
            0.0,
            inheritRotation = false,
            inheritScale = false,
            inheritReflection = false,
            transformMode = onlyTranslation,
          )],
        ),
      ],
      @[
        slotColorTimeline("body", rgbaTimeline, @[colorKeyframe(0.0, colorRgba(0.5, 0.25, 0.75, 1.0))]),
        slotColor2Timeline("body", @[color2Keyframe(0.0, colorRgba2(colorRgba(1.0, 1.0, 1.0, 1.0), 0.1, 0.2, 0.3))]),
        slotSequenceTimeline("body", @[sequenceKeyframe(0.0, 2'u32, 0.1, sequenceLoop)]),
      ],
    )
    var state = animationState(1)
    state.setAnimation(0, clip)
    let pose = state.sample()

    then:
      pose.inherits.len == 1
      pose.inherits[0].value.transformMode == onlyTranslation
      pose.colors.len == 1
      closeTo(pose.colors[0].color.g, 0.25)
      pose.colors2.len == 1
      closeTo(pose.colors2[0].color.darkB, quantizeF32(0.3))
      pose.sequences.len == 1
      pose.sequences[0].value.index == 2'u32

  it "returns mixed pose outputs in deterministic order":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("b", ""), boneData("a", "")],
    )
    let clip = animationClip(
      data,
      "ordered",
      @[
        boneScalarTimeline("b", rotateTimeline, @[scalarKeyframe(0.0, 2.0)]),
        boneScalarTimeline("a", rotateTimeline, @[scalarKeyframe(0.0, 1.0)]),
      ],
    )
    var state = animationState(1)
    state.setAnimation(0, clip)
    let pose = state.sample()

    then:
      pose.scalars.len == 2
      pose.scalars[0].target == "a"
      pose.scalars[1].target == "b"
