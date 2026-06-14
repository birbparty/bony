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

  it "encodes and rejects .bnb varints canonically":
    var bytes: seq[byte]
    bytes.writeVaruint(0)
    bytes.writeVaruint(127)
    bytes.writeVaruint(128)
    bytes.writeVaruint(624485)
    var index = 0

    then:
      bytes == @[0'u8, 127'u8, 128'u8, 1'u8, 229'u8, 142'u8, 38'u8]
      bytes.readVaruint(index) == 0
      bytes.readVaruint(index) == 127
      bytes.readVaruint(index) == 128
      bytes.readVaruint(index) == 624485

    bytes.setLen(0)
    bytes.writeVarint(-1)
    bytes.writeVarint(1)
    index = 0

    then:
      bytes.readVarint(index) == -1
      bytes.readVarint(index) == 1
      raisesBonyLoadError(proc() =
        var badIndex = 0
        discard readVaruint(@[128'u8, 0'u8], badIndex)
      , malformedVarint)
      raisesBonyLoadError(proc() =
        var badIndex = 0
        discard readVaruint(@[128'u8], badIndex)
      , truncatedInput)

  it "encodes .bnb headers and ToC entries":
    var bytes: seq[byte]
    bytes.writeHeader(flags = bnbStringTableFlag)
    bytes.writeToc(@[
      BnbTocEntry(propertyKey: 1000, backingTypeCode: backingTypeCode("f32")),
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
    ])
    var index = 0
    let header = bytes.readHeader(index)
    let toc = bytes.readToc(index)

    then:
      bytes[0 .. 3] == @[byte(ord('B')), byte(ord('O')), byte(ord('N')), byte(ord('Y'))]
      header.major == bnbMajorVersion
      header.minor == bnbMinorVersion
      header.flags == bnbStringTableFlag
      toc.len == 2
      toc[0].propertyKey == 1
      toc[1].propertyKey == 1000
      toc.backingTypeCodeFor(1) == backingTypeCode("string")
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeHeader(flags = 1'u64 shl 8)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.add bnbFingerprint
        bad.writeVaruint(packedVersion(bnbMajorVersion + 1, 0))
        bad.writeVaruint(0)
        var badIndex = 0
        discard bad.readHeader(badIndex)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.add bnbFingerprint
        bad.writeVaruint(packedVersion())
        bad.writeVaruint(1'u64 shl 8)
        var badIndex = 0
        discard bad.readHeader(badIndex)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeToc(@[
          BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
          BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
        ])
      , duplicateKey)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeToc(@[BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("f32"))])
      , invalidBackingType)

  it "reads .bnb length-prefixed property records":
    let toc = @[
      BnbTocEntry(propertyKey: 900000, backingTypeCode: 250'u8),
    ]
    var bytes: seq[byte]
    bytes.writePropertyRecord(900000, @[1'u8, 2'u8, 3'u8, 4'u8])
    bytes.writePropertyTerminator()
    var index = 0
    let record = bytes.readPropertyRecord(index, toc)
    let terminator = bytes.skipPropertyRecord(index, toc)

    then:
      record.propertyKey == 900000
      record.payload == @[1'u8, 2'u8, 3'u8, 4'u8]
      terminator == 0
      index == bytes.len
      raisesBonyLoadError(proc() =
        var badIndex = 0
        discard readPropertyRecord(bytes, badIndex, @[])
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad = @[1'u8, 4'u8, 1'u8, 2'u8]
        var badIndex = 0
        discard readPropertyRecord(bad, badIndex, @[BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string"))])
      , truncatedInput)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeVaruint(900000)
        bad.writeVaruint(bnbMaxPropertyPayloadBytes + 1)
        var badIndex = 0
        discard skipPropertyRecord(bad, badIndex, toc)
      , schemaViolation)

    bytes.setLen(0)
    bytes.writePropertyRecord(900000, @[5'u8, 6'u8, 7'u8])
    index = 0

    then:
      bytes.skipPropertyRecord(index, toc) == 900000
      index == bytes.len

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

  it "clips mesh triangles to a convex polygon":
    let vertices = @[
      SkinnedMeshVertex(x: -1.0, y: 0.0, u: 0.0, v: 0.0),
      SkinnedMeshVertex(x: 2.0, y: 0.0, u: 1.0, v: 0.0),
      SkinnedMeshVertex(x: 0.5, y: 2.0, u: 0.5, v: 1.0),
    ]
    let clipped = clipTrianglesToConvexPolygon(
      vertices,
      @[0'u16, 1'u16, 2'u16],
      @[clipVertex(0.0, 0.0), clipVertex(1.0, 0.0), clipVertex(1.0, 1.0), clipVertex(0.0, 1.0)],
    )
    var verticesInside = true
    for vertex in clipped.vertices:
      verticesInside = verticesInside and vertex.x >= -1e-9 and vertex.x <= 1.0 + 1e-9 and vertex.y >= -1e-9 and vertex.y <= 1.0 + 1e-9
    var indicesInRange = true
    for index in clipped.indices:
      indicesInRange = indicesInRange and int(index) < clipped.vertices.len

    then:
      clipped.vertices.len >= 3
      clipped.indices.len >= 3
      clipped.indices.len mod 3 == 0
      verticesInside
      indicesInRange

  it "clips clockwise polygons and fully excluded triangles":
    let vertices = @[
      SkinnedMeshVertex(x: -3.0, y: -3.0, u: 0.0, v: 0.0),
      SkinnedMeshVertex(x: -2.0, y: -3.0, u: 1.0, v: 0.0),
      SkinnedMeshVertex(x: -3.0, y: -2.0, u: 0.0, v: 1.0),
      SkinnedMeshVertex(x: -1.0, y: 0.0, u: 0.0, v: 0.0),
      SkinnedMeshVertex(x: 2.0, y: 0.0, u: 1.0, v: 0.0),
      SkinnedMeshVertex(x: 0.5, y: 2.0, u: 0.5, v: 1.0),
    ]
    let clip = @[clipVertex(0.0, 0.0), clipVertex(0.0, 1.0), clipVertex(1.0, 1.0), clipVertex(1.0, 0.0)]
    let empty = clipTrianglesToConvexPolygon(vertices, @[0'u16, 1'u16, 2'u16], clip)
    let clockwise = clipTrianglesToConvexPolygon(vertices, @[3'u16, 4'u16, 5'u16], clip)

    then:
      empty.vertices.len == 0
      empty.indices.len == 0
      clockwise.vertices.len >= 3
      clockwise.indices.len >= 3
      clockwise.indices.len mod 3 == 0

  it "rejects invalid convex clip inputs":
    let vertices = @[
      SkinnedMeshVertex(x: 0.0, y: 0.0),
      SkinnedMeshVertex(x: 1.0, y: 0.0),
      SkinnedMeshVertex(x: 0.0, y: 1.0),
    ]

    then:
      raisesBonyLoadError(
        proc() = discard clipTrianglesToConvexPolygon(vertices, @[], @[clipVertex(0.0, 0.0), clipVertex(1.0, 0.0), clipVertex(0.0, 1.0)]),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard clipTrianglesToConvexPolygon(vertices, @[0'u16, 1'u16], @[clipVertex(0.0, 0.0), clipVertex(1.0, 0.0), clipVertex(0.0, 1.0)]),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard clipTrianglesToConvexPolygon(vertices, @[0'u16, 1'u16, 2'u16], @[clipVertex(0.0, 0.0), clipVertex(2.0, 0.0), clipVertex(0.5, 0.5), clipVertex(0.0, 2.0)]),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard clipTrianglesToConvexPolygon(vertices, @[0'u16, 1'u16, 3'u16], @[clipVertex(0.0, 0.0), clipVertex(1.0, 0.0), clipVertex(0.0, 1.0)]),
        unknownRequiredReference,
      )
      raisesBonyLoadError(
        proc() = discard clipTrianglesToConvexPolygon(vertices, @[0'u16, 1'u16, 2'u16], @[ClipVertex(x: Inf, y: 0.0), clipVertex(1.0, 0.0), clipVertex(0.0, 1.0)]),
        numericOutOfRange,
      )
      raisesBonyLoadError(
        proc() = discard clipTrianglesToConvexPolygon(@[SkinnedMeshVertex(x: Inf, y: 0.0), vertices[1], vertices[2]], @[0'u16, 1'u16, 2'u16], @[clipVertex(0.0, 0.0), clipVertex(1.0, 0.0), clipVertex(0.0, 1.0)]),
        numericOutOfRange,
      )

  it "resolves attachment sequence frame names":
    let sequence = attachmentSequence(count = 5'u32, start = 12'u32, digits = 3'u32, setupIndex = 2'u32)
    let timeline = slotSequenceTimeline(
      "body",
      @[
        sequenceKeyframe(0.0, 0'u32, 0.1, sequenceLoop),
        sequenceKeyframe(1.0, 4'u32, 0.1, sequenceHold),
      ],
    )

    then:
      setupSequenceFrameName("walk_", sequence) == "walk_014"
      sampledSequenceFrameName("walk_", sequence, timeline.sampleSequence(0.35, sequence.count)) == "walk_015"
      sampledSequenceFrameName("walk_", sequence, timeline.sampleSequence(1.5, sequence.count)) == "walk_016"
      raisesBonyLoadError(proc() = discard attachmentSequence(count = 0'u32), schemaViolation)
      raisesBonyLoadError(proc() = discard attachmentSequence(count = 2'u32, start = high(uint32)), schemaViolation)
      raisesBonyLoadError(proc() = discard sequenceFrameName("walk_", AttachmentSequence(count: 0'u32), 0'u32), schemaViolation)
      raisesBonyLoadError(proc() = discard sequenceFrameName("walk_", AttachmentSequence(count: 1'u32, setupIndex: 1'u32), 0'u32), schemaViolation)
      raisesBonyLoadError(proc() = discard sequenceFrameName("walk_", AttachmentSequence(count: 2'u32, start: high(uint32)), 1'u32), schemaViolation)
      raisesBonyLoadError(proc() = discard sequenceFrameName("walk_", sequence, 5'u32), schemaViolation)

  it "applies warp and rotation deformers to skinned vertices":
    let lattice = warpLattice(
      2'u32,
      2'u32,
      0.0,
      0.0,
      1.0,
      1.0,
      @[deformerPoint(0.0, 0.0), deformerPoint(1.0, 0.0), deformerPoint(0.0, 1.0), deformerPoint(2.0, 1.0)],
    )
    let vertices = @[
      SkinnedMeshVertex(x: 0.5, y: 0.5, u: 0.25, v: 0.75),
      SkinnedMeshVertex(x: 2.0, y: 2.0, u: 0.0, v: 0.0),
    ]
    let warped = applyDeformers(vertices, @[warpDeformer("warp", lattice)])
    let rotated = applyDeformers(@[SkinnedMeshVertex(x: 1.0, y: 0.0)], @[rotationDeformerNode("rotate", rotationDeformer(0.0, 0.0, 90.0))])

    then:
      closeTo(warped[0].x, 0.75)
      closeTo(warped[0].y, 0.5)
      closeTo(warped[0].u, 0.25)
      closeTo(warped[0].v, 0.75)
      closeTo(warped[1].x, 2.0)
      closeTo(warped[1].y, 2.0)
      closeTo(rotated[0].x, 0.0)
      closeTo(rotated[0].y, 1.0)

  it "applies rotation deformer opacity as partial influence":
    let unchanged = applyDeformer(SkinnedMeshVertex(x: 1.0, y: 0.0), rotationDeformerNode("none", rotationDeformer(0.0, 0.0, 90.0, opacity = 0.0)))
    let halfway = applyDeformer(SkinnedMeshVertex(x: 1.0, y: 0.0), rotationDeformerNode("half", rotationDeformer(0.0, 0.0, 90.0, opacity = 0.5)))

    then:
      closeTo(unchanged.x, 1.0)
      closeTo(unchanged.y, 0.0)
      closeTo(halfway.x, 0.5)
      closeTo(halfway.y, 0.5)

  it "applies deformers by global order":
    let first = rotationDeformerNode("first", rotationDeformer(0.0, 0.0, 90.0), order = 0'u32)
    let second = rotationDeformerNode("second", rotationDeformer(0.0, 0.0, 90.0), order = 1'u32)
    let deformed = applyDeformers(@[SkinnedMeshVertex(x: 1.0, y: 0.0)], @[second, first])

    then:
      closeTo(deformed[0].x, -1.0)
      closeTo(deformed[0].y, 0.0)

  it "transforms child deformer frames through their parent":
    let parent = rotationDeformerNode("parent", rotationDeformer(0.0, 0.0, 90.0), order = 0'u32)
    let child = warpDeformer(
      "child",
      warpLattice(
        2'u32,
        2'u32,
        0.0,
        0.0,
        1.0,
        1.0,
        @[deformerPoint(0.0, 0.0), deformerPoint(1.0, 0.0), deformerPoint(0.0, 1.0), deformerPoint(2.0, 1.0)],
      ),
      parent = "parent",
      order = 1'u32,
    )
    let deformed = applyDeformers(@[SkinnedMeshVertex(x: 0.5, y: 0.5)], @[child, parent])

    then:
      closeTo(deformed[0].x, -0.5)
      closeTo(deformed[0].y, 0.75)

  it "preserves child warp setup coordinates under non-axis-aligned parents":
    let parent = rotationDeformerNode("parent", rotationDeformer(0.0, 0.0, 45.0), order = 0'u32)
    let child = warpDeformer(
      "child",
      warpLattice(
        2'u32,
        2'u32,
        0.0,
        0.0,
        1.0,
        1.0,
        @[deformerPoint(0.0, 0.0), deformerPoint(1.0, 0.0), deformerPoint(0.0, 1.0), deformerPoint(2.0, 1.0)],
      ),
      parent = "parent",
      order = 1'u32,
    )
    let deformed = applyDeformers(@[SkinnedMeshVertex(x: 0.5, y: 0.5)], @[child, parent])

    then:
      closeTo(deformed[0].x, 0.1767766922712326)
      closeTo(deformed[0].y, 0.8838834762573242)

  it "rejects invalid deformers and deformer trees":
    let lattice = warpLattice(
      2'u32,
      2'u32,
      0.0,
      0.0,
      1.0,
      1.0,
      @[deformerPoint(0.0, 0.0), deformerPoint(1.0, 0.0), deformerPoint(0.0, 1.0), deformerPoint(1.0, 1.0)],
    )
    let rotation = rotationDeformer(0.0, 0.0, 0.0)

    then:
      raisesBonyLoadError(
        proc() = discard warpLattice(1'u32, 2'u32, 0.0, 0.0, 1.0, 1.0, @[deformerPoint(0.0, 0.0), deformerPoint(1.0, 0.0)]),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard warpLattice(2'u32, 2'u32, 0.0, 0.0, 0.0, 1.0, @[deformerPoint(0.0, 0.0), deformerPoint(1.0, 0.0), deformerPoint(0.0, 1.0), deformerPoint(1.0, 1.0)]),
        schemaViolation,
      )
      raisesBonyLoadError(proc() = discard rotationDeformer(0.0, 0.0, 0.0, scaleX = 0.0), schemaViolation)
      raisesBonyLoadError(proc() = discard rotationDeformer(0.0, 0.0, 0.0, opacity = 2.0), schemaViolation)
      raisesBonyLoadError(proc() = validateWarpLattice(WarpLattice(rows: 2'u32, cols: 2'u32, minX: Inf, minY: 0.0, maxX: 1.0, maxY: 1.0, controlPoints: lattice.controlPoints)), numericOutOfRange)
      raisesBonyLoadError(proc() = validateDeformerTree(@[warpDeformer("dup", lattice, order = 0'u32), rotationDeformerNode("dup", rotation, order = 1'u32)]), duplicateKey)
      raisesBonyLoadError(proc() = validateDeformerTree(@[warpDeformer("a", lattice, order = 0'u32), rotationDeformerNode("b", rotation, order = 0'u32)]), schemaViolation)
      raisesBonyLoadError(proc() = validateDeformerTree(@[warpDeformer("child", lattice, parent = "missing")]), unknownRequiredReference)
      raisesBonyLoadError(proc() = validateDeformerTree(@[warpDeformer("child", lattice, parent = "parent", order = 0'u32), rotationDeformerNode("parent", rotation, order = 1'u32)]), orderingViolation)
      raisesBonyLoadError(proc() = validateDeformerTree(@[warpDeformer("a", lattice, parent = "b", order = 0'u32), rotationDeformerNode("b", rotation, parent = "a", order = 1'u32)]), cycleDetected)
      raisesBonyLoadError(proc() = discard applyDeformers(@[SkinnedMeshVertex(x: Inf, y: 0.0)], @[warpDeformer("warp", lattice)]), numericOutOfRange)
      raisesBonyLoadError(proc() = discard applyDeformer(SkinnedMeshVertex(x: Inf, y: 0.0), warpDeformer("warp", lattice)), numericOutOfRange)
      raisesBonyLoadError(proc() = discard applyDeformer(SkinnedMeshVertex(x: 0.0, y: 0.0), Deformer(id: "bad", kind: warpDeformerKind, warp: WarpLattice(rows: 2'u32, cols: 2'u32, minX: 0.0, minY: 0.0, maxX: 1.0, maxY: 1.0, controlPoints: @[]))), schemaViolation)
      raisesBonyLoadError(proc() = discard applyDeformer(SkinnedMeshVertex(x: 0.0, y: 0.0), Deformer(id: "bad", kind: warpDeformerKind, warp: WarpLattice(rows: 2'u32, cols: 2'u32, minX: 0.0, minY: 0.0, maxX: 0.0, maxY: 1.0, controlPoints: lattice.controlPoints))), schemaViolation)

  it "builds and updates named parameter axes":
    let angleX = parameterAxis("AngleX", minValue = -30.0, maxValue = 30.0, defaultValue = 0.0)
    let eyeOpen = parameterAxis("EyeOpen", minValue = 0.0, maxValue = 1.0, defaultValue = 1.0)
    var state = initParameterState(@[angleX, eyeOpen])
    state.setParameterValue("AngleX", 12.5)
    state.applyParameterSample(parameterSample(eyeOpen, 0.25))
    let sampled = state.samples

    then:
      angleX.name == "AngleX"
      closeTo(angleX.minValue, -30.0)
      closeTo(angleX.maxValue, 30.0)
      closeTo(angleX.defaultValue, 0.0)
      closeTo(state.getParameterValue("AngleX"), 12.5)
      closeTo(state.getParameterValue("EyeOpen"), 0.25)
      sampled.len == 2
      sampled[0].name == "AngleX"
      closeTo(sampled[0].value, 12.5)
      sampled[1].name == "EyeOpen"
      closeTo(sampled[1].value, 0.25)

    state.resetParameters()

    then:
      closeTo(state.getParameterValue("AngleX"), 0.0)
      closeTo(state.getParameterValue("EyeOpen"), 1.0)

  it "rejects invalid parameter axes and values":
    let angleX = parameterAxis("AngleX", minValue = -30.0, maxValue = 30.0, defaultValue = 0.0)

    then:
      raisesBonyLoadError(proc() = discard parameterAxis("", minValue = 0.0, maxValue = 1.0, defaultValue = 0.0), schemaViolation)
      raisesBonyLoadError(proc() = discard parameterAxis("Bad", minValue = 1.0, maxValue = 1.0, defaultValue = 1.0), schemaViolation)
      raisesBonyLoadError(proc() = discard parameterAxis("Bad", minValue = 0.0, maxValue = 1.0, defaultValue = 2.0), schemaViolation)
      raisesBonyLoadError(proc() = discard parameterAxis("Bad", minValue = Inf, maxValue = 1.0, defaultValue = 0.0), numericOutOfRange)
      raisesBonyLoadError(proc() = validateParameterAxis(ParameterAxis(name: "Bad", minValue: 0.0, maxValue: 1.0, defaultValue: Inf)), numericOutOfRange)
      raisesBonyLoadError(proc() = validateParameterAxes(@[angleX, parameterAxis("AngleX", minValue = -1.0, maxValue = 1.0, defaultValue = 0.0)]), duplicateKey)
      raisesBonyLoadError(proc() = discard parameterSample(angleX, 40.0), schemaViolation)
      raisesBonyLoadError(proc() = discard parameterSample(angleX, Inf), numericOutOfRange)

    var state = initParameterState(@[angleX])

    then:
      raisesBonyLoadError(proc() = state.setParameterValue("Missing", 0.0), unknownRequiredReference)
      raisesBonyLoadError(proc() = state.setParameterValue("AngleX", -40.0), schemaViolation)

  it "normalizes directly constructed parameter axes":
    let direct = ParameterAxis(name: "p", minValue: 0.0, maxValue: 0.2, defaultValue: 0.1)
    let sample = parameterSample(direct, 0.2)
    var state = initParameterState(@[direct])

    then:
      closeTo(sample.value, quantizeF32(0.2))
      closeTo(state.getParameterValue("p"), quantizeF32(0.1))
      closeTo(state.axes[0].defaultValue, quantizeF32(0.1))

    state.setParameterValue("p", 0.2)

    then:
      closeTo(state.getParameterValue("p"), quantizeF32(0.2))
      closeTo(state.samples[0].value, quantizeF32(0.2))

    state.resetParameters()

    then:
      closeTo(state.getParameterValue("p"), quantizeF32(0.1))

  it "validates directly constructed parameter samples":
    var state = initParameterState(@[parameterAxis("p", minValue = 0.0, maxValue = 1.0, defaultValue = 0.5)])

    then:
      raisesBonyLoadError(proc() = state.applyParameterSample(ParameterSample(name: "p", value: 2.0)), schemaViolation)
      raisesBonyLoadError(proc() = state.applyParameterSample(ParameterSample(name: "p", value: Inf)), numericOutOfRange)
      raisesBonyLoadError(proc() = state.applyParameterSample(ParameterSample(name: "missing", value: 0.0)), unknownRequiredReference)

  it "samples parameter timelines and applies them to state":
    let angle = parameterAxis("AngleX", minValue = -30.0, maxValue = 30.0, defaultValue = 0.0)
    let open = parameterAxis("EyeOpen", minValue = 0.0, maxValue = 1.0, defaultValue = 1.0)
    let linear = parameterTimeline(
      angle,
      @[
        scalarKeyframe(0.0, -30.0),
        scalarKeyframe(2.0, 30.0),
      ],
    )
    let stepped = parameterTimeline(
      open,
      @[
        scalarKeyframe(0.0, 1.0, steppedCurve),
        scalarKeyframe(1.0, 0.0),
      ],
    )
    let bezier = parameterTimeline(
      open,
      @[
        scalarKeyframe(0.0, 0.0, bezierTimelineCurve(0.25, 0.0, 0.75, 1.0)),
        scalarKeyframe(1.0, 1.0),
      ],
    )
    var state = initParameterState(@[angle, open])
    state.applyParameterTimeline(linear, 1.0)
    state.applyParameterTimeline(stepped, 0.75)

    then:
      linear.target == "AngleX"
      linear.keys.len == 2
      closeTo(linear.sampleParameterValue(0.0).value, -30.0)
      closeTo(linear.sampleParameterValue(1.0).value, 0.0)
      closeTo(linear.sampleParameterValue(3.0).value, 30.0)
      closeTo(stepped.sampleParameterValue(0.75).value, 1.0)
      closeTo(bezier.sampleParameterValue(0.5).value, 0.5)
      closeTo(state.getParameterValue("AngleX"), 0.0)
      closeTo(state.getParameterValue("EyeOpen"), 1.0)

    let undershoot = parameterTimeline(
      open,
      @[
        scalarKeyframe(0.0, 0.0, bezierTimelineCurve(0.25, -1.0, 0.75, -1.0)),
        scalarKeyframe(1.0, 1.0),
      ],
    )
    let overshoot = parameterTimeline(
      open,
      @[
        scalarKeyframe(0.0, 0.0, bezierTimelineCurve(0.25, 2.0, 0.75, 2.0)),
        scalarKeyframe(1.0, 1.0),
      ],
    )

    then:
      closeTo(undershoot.sampleParameterValue(0.5).value, 0.0)
      closeTo(overshoot.sampleParameterValue(0.5).value, 1.0)

  it "rejects invalid parameter timelines":
    let axis = parameterAxis("p", minValue = 0.0, maxValue = 1.0, defaultValue = 0.5)

    then:
      raisesBonyLoadError(proc() = discard parameterTimeline(axis, @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard parameterTimeline(axis, @[scalarKeyframe(1.0, 0.0), scalarKeyframe(0.0, 1.0)]), schemaViolation)
      raisesBonyLoadError(proc() = discard parameterTimeline(axis, @[scalarKeyframe(0.0, 2.0)]), schemaViolation)
      raisesBonyLoadError(proc() = discard parameterTimeline(axis, @[ScalarKeyframe(time: Inf, value: 0.0, curve: linearTimelineCurve)]), numericOutOfRange)
      raisesBonyLoadError(proc() = discard parameterTimeline(axis, @[ScalarKeyframe(time: 1.0, value: 0.0, curve: linearTimelineCurve), ScalarKeyframe(time: 1.0 + 1e-10, value: 1.0, curve: linearTimelineCurve)]), schemaViolation)
      raisesBonyLoadError(proc() = discard ParameterTimeline(target: "", axis: axis, keys: @[scalarKeyframe(0.0, 0.0)]).sampleParameterValue(0.0), schemaViolation)
      raisesBonyLoadError(proc() = discard ParameterTimeline(target: "other", axis: axis, keys: @[scalarKeyframe(0.0, 0.0)]).sampleParameterValue(0.0), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard parameterTimeline(axis, @[scalarKeyframe(0.0, 0.0)]).sampleParameterValue(-0.1), schemaViolation)

    var state = initParameterState(@[axis])

    then:
      raisesBonyLoadError(
        proc() = state.applyParameterTimeline(parameterTimeline(parameterAxis("missing", minValue = 0.0, maxValue = 1.0), @[scalarKeyframe(0.0, 0.0)]), 0.0),
        unknownRequiredReference,
      )

  it "samples one-dimensional keyform blends":
    let angle = parameterAxis("AngleX", minValue = -30.0, maxValue = 30.0, defaultValue = 0.0)
    let blend = keyformBlend(
      @[angle],
      @[
        keyform(@[parameterSample(angle, -30.0)], @[0.0, 10.0]),
        keyform(@[parameterSample(angle, 30.0)], @[60.0, 70.0]),
      ],
    )
    let values = sampleKeyformValues(blend, @[parameterSample(angle, 0.0)])

    then:
      closeTo(values[0], 30.0)
      closeTo(values[1], 40.0)

  it "samples two-dimensional keyform blends":
    let x = parameterAxis("AngleX", minValue = -1.0, maxValue = 1.0, defaultValue = 0.0)
    let y = parameterAxis("AngleY", minValue = -1.0, maxValue = 1.0, defaultValue = 0.0)
    let blend = keyformBlend(
      @[x, y],
      @[
        keyform(@[parameterSample(x, -1.0), parameterSample(y, -1.0)], @[0.0]),
        keyform(@[parameterSample(x, 1.0), parameterSample(y, -1.0)], @[10.0]),
        keyform(@[parameterSample(x, -1.0), parameterSample(y, 1.0)], @[20.0]),
        keyform(@[parameterSample(x, 1.0), parameterSample(y, 1.0)], @[30.0]),
      ],
    )
    let values = sampleKeyformValues(blend, @[parameterSample(x, 0.0), parameterSample(y, 0.0)])

    then:
      values.len == 1
      closeTo(values[0], 15.0)

  it "samples n-dimensional keyform point blends":
    let x = parameterAxis("x", minValue = 0.0, maxValue = 1.0, defaultValue = 0.0)
    let y = parameterAxis("y", minValue = 0.0, maxValue = 1.0, defaultValue = 0.0)
    let z = parameterAxis("z", minValue = 0.0, maxValue = 1.0, defaultValue = 0.0)
    var forms: seq[Keyform]
    for xi in 0 .. 1:
      for yi in 0 .. 1:
        for zi in 0 .. 1:
          let point = deformerPoint(float64(xi), float64(yi * 2 + zi * 4))
          forms.add pointKeyform(@[parameterSample(x, float64(xi)), parameterSample(y, float64(yi)), parameterSample(z, float64(zi))], @[point])
    let blend = keyformBlend(@[x, y, z], forms)
    let points = sampleKeyformPoints(blend, @[parameterSample(x, 0.5), parameterSample(y, 0.5), parameterSample(z, 0.5)])

    then:
      points.len == 1
      closeTo(points[0].x, 0.5)
      closeTo(points[0].y, 3.0)

  it "rejects invalid keyform blends":
    let x = parameterAxis("x", minValue = 0.0, maxValue = 1.0, defaultValue = 0.0)
    let y = parameterAxis("y", minValue = 0.0, maxValue = 1.0, defaultValue = 0.0)

    then:
      raisesBonyLoadError(proc() = discard keyform(@[], @[0.0]), schemaViolation)
      raisesBonyLoadError(proc() = discard keyform(@[parameterSample(x, 0.0)], @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard keyformBlend(@[], @[keyform(@[parameterSample(x, 0.0)], @[0.0])]), schemaViolation)
      raisesBonyLoadError(proc() = discard keyformBlend(@[x], @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard keyformBlend(@[x], @[keyform(@[parameterSample(x, 0.0)], @[0.0]), keyform(@[parameterSample(x, 1.0)], @[0.0, 1.0])]), schemaViolation)
      raisesBonyLoadError(proc() = discard keyformBlend(@[x], @[keyform(@[parameterSample(x, 0.0)], @[0.0]), keyform(@[parameterSample(x, 0.0)], @[1.0])]), duplicateKey)
      raisesBonyLoadError(proc() = discard keyformBlend(@[x, y], @[keyform(@[parameterSample(x, 0.0)], @[0.0])]), schemaViolation)
      raisesBonyLoadError(
        proc() = discard sampleKeyformValues(
          keyformBlend(@[x, y], @[
            keyform(@[parameterSample(x, 0.0), parameterSample(y, 0.0)], @[0.0]),
            keyform(@[parameterSample(x, 1.0), parameterSample(y, 0.0)], @[10.0]),
            keyform(@[parameterSample(x, 0.0), parameterSample(y, 1.0)], @[20.0]),
          ]),
          @[parameterSample(x, 0.5), parameterSample(y, 0.5)],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() = discard sampleKeyformValues(keyformBlend(@[x], @[keyform(@[parameterSample(x, 0.0)], @[0.0])]), @[ParameterSample(name: "x", value: Inf)]), numericOutOfRange)
      raisesBonyLoadError(proc() = discard sampleKeyformValues(keyformBlend(@[x], @[keyform(@[parameterSample(x, 0.0)], @[0.0])]), @[parameterSample(x, 0.0), parameterSample(x, 0.0)]), duplicateKey)
      raisesBonyLoadError(proc() = discard blendedPoints(@[0.0]), schemaViolation)

  it "handles high-dimensional degenerate keyform axes":
    var axes: seq[ParameterAxis]
    var coordinates: seq[ParameterSample]
    var samples: seq[ParameterSample]
    for index in 0 .. 69:
      let axis = parameterAxis("p" & $index, minValue = 0.0, maxValue = 1.0, defaultValue = 0.0)
      axes.add axis
      coordinates.add parameterSample(axis, 0.0)
      samples.add parameterSample(axis, 0.0)
    let values = sampleKeyformValues(keyformBlend(axes, @[keyform(coordinates, @[42.0])]), samples)

    then:
      values.len == 1
      closeTo(values[0], 42.0)

  it "rejects too many varying keyform axes":
    var axes: seq[ParameterAxis]
    var lows: seq[ParameterSample]
    var highs: seq[ParameterSample]
    var samples: seq[ParameterSample]
    for index in 0 .. 20:
      let axis = parameterAxis("v" & $index, minValue = 0.0, maxValue = 1.0, defaultValue = 0.5)
      axes.add axis
      lows.add parameterSample(axis, 0.0)
      highs.add parameterSample(axis, 1.0)
      samples.add parameterSample(axis, 0.5)

    then:
      raisesBonyLoadError(
        proc() = discard sampleKeyformValues(keyformBlend(axes, @[keyform(lows, @[0.0]), keyform(highs, @[1.0])]), samples),
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

  it "evaluates state-machine layers through current animation states":
    let data = animationFixture()
    var dataRef = new SkeletonData
    dataRef[] = data
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 10.0)])],
    )
    let blink = animationClip(
      data,
      "blink",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 90.0)])],
      slotTimelines = @[slotColorTimeline("body", alphaTimeline, @[colorKeyframe(0.0, colorRgba(1.0, 1.0, 1.0, 0.25))])],
    )
    let machine = stateMachine(
      "face",
      @[
        stateMachineLayer("base", @[stateMachineState("idle", idle, loop = true)]),
        stateMachineLayer("eyes", @[stateMachineState("blink", blink)]),
      ],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.update(0.5)
    let evaluated = runtime.evaluate(dataRef)

    then:
      evaluated.layers.len == 2
      evaluated.layers[0].layer == "base"
      evaluated.layers[0].state == "idle"
      closeTo(evaluated.layers[0].time, 0.5)
      closeTo(evaluated.layers[0].pose.scalars[0].value, 5.0)
      evaluated.layers[1].layer == "eyes"
      evaluated.layers[1].state == "blink"
      closeTo(evaluated.layers[1].pose.colors[0].color.a, 0.25)
      evaluated.pose.scalars.len == 1
      closeTo(evaluated.pose.scalars[0].value, 90.0)
      evaluated.pose.colors.len == 1
      closeTo(evaluated.pose.colors[0].color.a, 0.25)

  it "switches state-machine layer states and clamps non-looping time":
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
    let machine = stateMachine(
      "gesture",
      @[stateMachineLayer("base", @[stateMachineState("idle", idle), stateMachineState("wave", wave)], initialState = "idle")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.setState("base", "wave")
    runtime.update(2.0)
    let evaluated = runtime.evaluate()

    then:
      runtime.layers[0].currentState == "wave"
      closeTo(evaluated.layers[0].time, 1.0)
      closeTo(evaluated.layers[0].pose.scalars[0].value, 120.0)

  it "evaluates one-dimensional state-machine blend states":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[
        boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 10.0)]),
        boneVectorTimeline("root", translateTimeline, @[vector2Keyframe(0.0, 0.0, 0.0), vector2Keyframe(1.0, 10.0, 20.0)]),
      ],
    )
    let run = animationClip(
      data,
      "run",
      @[
        boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 100.0), scalarKeyframe(1.0, 120.0)]),
        boneVectorTimeline("root", translateTimeline, @[vector2Keyframe(0.0, 20.0, 40.0), vector2Keyframe(1.0, 30.0, 60.0)]),
      ],
    )
    let machine = stateMachine(
      "locomotion",
      @[
        stateMachineLayer(
          "base",
          @[
            stateMachineBlendState(
              "move",
              "speed",
              @[stateMachineBlendClip(run, 1.0), stateMachineBlendClip(idle, 0.0)],
            ),
          ],
        ),
      ],
      @[stateMachineNumberInput("speed", 0.25)],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.update(0.5)
    var evaluated = runtime.evaluate()

    then:
      evaluated.layers[0].state == "move"
      closeTo(evaluated.layers[0].time, 0.5)
      closeTo(evaluated.layers[0].pose.scalars[0].value, 31.25)
      closeTo(evaluated.layers[0].pose.vectors[0].x, 10.0)
      closeTo(evaluated.layers[0].pose.vectors[0].y, 20.0)

    runtime.setNumberInput("speed", 2.0)
    evaluated = runtime.evaluate()

    then:
      closeTo(evaluated.pose.scalars[0].value, 110.0)

  it "uses state-machine blend states with transitions":
    let data = animationFixture()
    let idle = animationClip(data, "idle", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0)])])
    let walk = animationClip(data, "walk", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 40.0)])])
    let run = animationClip(data, "run", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 100.0)])])
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[
            stateMachineState("idle", idle),
            stateMachineBlendState(
              "move",
              "speed",
              @[stateMachineBlendClip(walk, 0.0), stateMachineBlendClip(run, 1.0)],
            ),
          ],
          transitions = @[stateMachineTransition("idle", "move", @[stateMachineBoolCondition("moving")])],
        ),
      ],
      @[stateMachineBoolInput("moving"), stateMachineNumberInput("speed", 0.5)],
      listeners = @[stateMachineStateEnterListener("move-enter", "base", "move")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.setBoolInput("moving", true)
    runtime.update(0.0)
    let evaluated = runtime.evaluate()

    then:
      runtime.layers[0].currentState == "move"
      runtime.events.len == 1
      runtime.events[0].listener == "move-enter"
      closeTo(evaluated.pose.scalars[0].value, 70.0)

  it "blends missing state-machine blend channels from setup pose":
    var dataValue = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "", localTransform(rotation = 30.0, scaleX = 1.0, scaleY = 1.0))],
    )
    let data = new SkeletonData
    data[] = dataValue
    let keyed = animationClip(
      data[],
      "keyed",
      @[
        boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 10.0)]),
        boneVectorTimeline("root", scaleTimeline, @[vector2Keyframe(0.0, 2.0, 2.0)]),
      ],
    )
    let sparse = animationClip(data[], "sparse")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineBlendState("move", "blend", @[stateMachineBlendClip(keyed, 0.0), stateMachineBlendClip(sparse, 1.0)])],
        ),
      ],
      @[stateMachineNumberInput("blend", 0.5)],
    )
    let evaluated = initStateMachineRuntime(machine).evaluate(data)

    then:
      evaluated.pose.scalars.len == 1
      closeTo(evaluated.pose.scalars[0].value, 20.0)
      evaluated.pose.vectors.len == 1
      closeTo(evaluated.pose.vectors[0].x, 1.5)
      closeTo(evaluated.pose.vectors[0].y, 1.5)

  it "rejects invalid state-machine core data":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let layer = stateMachineLayer("base", @[stateMachineState("idle", idle)])
    let machine = stateMachine("machine", @[layer])

    then:
      raisesBonyLoadError(proc() = discard stateMachineState("", idle), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineLayer("", @[stateMachineState("idle", idle)]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineLayer("base", @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineLayer("base", @[stateMachineState("idle", idle), stateMachineState("idle", idle)]), duplicateKey)
      raisesBonyLoadError(proc() = discard stateMachineLayer("base", @[stateMachineState("idle", idle)], initialState = "missing"), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard stateMachine("", @[layer]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachine("machine", @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachine("machine", @[layer, layer]), duplicateKey)
      raisesBonyLoadError(proc() = discard StateMachineRuntime(machine: machine, layers: @[]).evaluate(), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineBlendClip(animationClip(data, ""), 0.0), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineBlendClip(idle, Inf), numericOutOfRange)
      raisesBonyLoadError(proc() = discard stateMachineBlendState("", "speed", @[stateMachineBlendClip(idle, 0.0)]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineBlendState("move", "", @[stateMachineBlendClip(idle, 0.0)]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineBlendState("move", "speed", @[]), schemaViolation)
      raisesBonyLoadError(proc() =
        discard stateMachineBlendState("move", "speed", @[
          stateMachineBlendClip(idle, 0.0),
          stateMachineBlendClip(idle, 0.0),
        ]),
        duplicateKey,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", @[stateMachineBlendState("move", "missing", @[stateMachineBlendClip(idle, 0.0)])])],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", @[stateMachineBlendState("move", "armed", @[stateMachineBlendClip(idle, 0.0)])])],
          @[stateMachineBoolInput("armed")],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachineLayer(
          "base",
          @[StateMachineState(name: "move", kind: blend1DState, clip: idle, blendInput: "speed", blendClips: @[stateMachineBlendClip(idle, 0.0)])],
        ),
        schemaViolation,
      )

    var runtime = initStateMachineRuntime(machine)
    let extraLayer = stateMachineLayer("base", @[stateMachineState("idle", idle), stateMachineState("wave", animationClip(data, "wave"))])

    then:
      raisesBonyLoadError(proc() = runtime.setState("missing", "idle"), unknownRequiredReference)
      raisesBonyLoadError(proc() = runtime.setState("base", "missing"), unknownRequiredReference)
      raisesBonyLoadError(proc() = runtime.update(-0.1), schemaViolation)
      raisesBonyLoadError(proc() =
        var direct = StateMachineRuntime(
          machine: machine,
          layers: @[StateMachineLayerRuntime(layer: extraLayer, currentState: "idle")],
        )
        direct.setState("base", "wave"),
        unknownRequiredReference,
      )

  it "stores typed state-machine inputs at runtime":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let machine = stateMachine(
      "machine",
      @[stateMachineLayer("base", @[stateMachineState("idle", idle)])],
      @[
        stateMachineBoolInput("armed", defaultValue = true),
        stateMachineNumberInput("speed", defaultValue = 0.25),
        stateMachineTriggerInput("jump"),
      ],
    )
    var runtime = initStateMachineRuntime(machine)

    then:
      runtime.machine.inputs.len == 3
      runtime.inputs.len == 3
      runtime.getBoolInput("armed")
      closeTo(runtime.getNumberInput("speed"), quantizeF32(0.25))
      not runtime.isTriggerSet("jump")

    runtime.setBoolInput("armed", false)
    runtime.setNumberInput("speed", 2.5)
    runtime.fireTrigger("jump")

    then:
      not runtime.getBoolInput("armed")
      closeTo(runtime.getNumberInput("speed"), 2.5)
      runtime.isTriggerSet("jump")

    runtime.clearTrigger("jump")

    then:
      not runtime.isTriggerSet("jump")

    runtime.setNumberInput("speed", 0.1)
    runtime.fireTrigger("jump")

    then:
      closeTo(runtime.getNumberInput("speed"), quantizeF32(0.1))
      runtime.consumeTrigger("jump")
      not runtime.isTriggerSet("jump")

    runtime.fireTrigger("jump")
    runtime.resetInputs()

    then:
      runtime.getBoolInput("armed")
      closeTo(runtime.getNumberInput("speed"), quantizeF32(0.25))
      not runtime.isTriggerSet("jump")

  it "rejects invalid state-machine typed inputs":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let layer = stateMachineLayer("base", @[stateMachineState("idle", idle)])
    let machine = stateMachine(
      "machine",
      @[layer],
      @[stateMachineBoolInput("armed"), stateMachineNumberInput("speed"), stateMachineTriggerInput("jump")],
    )

    then:
      raisesBonyLoadError(proc() = discard stateMachineBoolInput(""), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineNumberInput("bad", defaultValue = Inf), numericOutOfRange)
      raisesBonyLoadError(
        proc() = discard stateMachine(
          "machine",
          @[layer],
          @[StateMachineInput(name: "armed", kind: boolInput, defaultNumber: 1.0)],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(
        proc() = discard stateMachine(
          "machine",
          @[layer],
          @[StateMachineInput(name: "armed", kind: boolInput, defaultNumber: Inf)],
        ),
        numericOutOfRange,
      )
      raisesBonyLoadError(
        proc() = discard stateMachine(
          "machine",
          @[layer],
          @[StateMachineInput(name: "speed", kind: numberInput, defaultBool: true)],
        ),
        schemaViolation,
      )

    then:
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[layer],
          @[stateMachineBoolInput("dup"), stateMachineTriggerInput("dup")],
        ),
        duplicateKey,
      )
      raisesBonyLoadError(
        proc() = discard stateMachine(
          "machine",
          @[layer],
          @[StateMachineInput(name: "jump", kind: triggerInput, defaultBool: true)],
        ),
        schemaViolation,
      )

    var runtime = initStateMachineRuntime(machine)

    then:
      raisesBonyLoadError(proc() = discard runtime.getBoolInput("missing"), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard runtime.getBoolInput("speed"), schemaViolation)
      raisesBonyLoadError(proc() = runtime.setNumberInput("speed", Inf), numericOutOfRange)
      raisesBonyLoadError(proc() = runtime.fireTrigger("armed"), schemaViolation)
      raisesBonyLoadError(proc() =
        discard StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: numberInput, numberValue: Inf),
            StateMachineInputValue(name: "jump", kind: triggerInput),
          ],
        ).evaluate(),
        numericOutOfRange,
      )
      raisesBonyLoadError(proc() =
        discard StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[StateMachineInputValue(name: "armed", kind: boolInput)],
        ).evaluate(),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: boolInput),
            StateMachineInputValue(name: "jump", kind: triggerInput),
          ],
        ).evaluate(),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard StateMachineRuntime(
          machine: machine,
          layers: runtime.layers,
          inputs: @[
            StateMachineInputValue(name: "armed", kind: boolInput),
            StateMachineInputValue(name: "speed", kind: numberInput),
            StateMachineInputValue(name: "speed", kind: numberInput),
          ],
        ).evaluate(),
        duplicateKey,
      )

  it "evaluates state-machine transitions and typed conditions":
    let data = animationFixture()
    let idle = animationClip(data, "idle", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0)])])
    let wave = animationClip(data, "wave", @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 90.0)])])
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineState("idle", idle), stateMachineState("wave", wave)],
          transitions = @[
            stateMachineTransition(
              "idle",
              "wave",
              @[
                stateMachineBoolCondition("armed"),
                stateMachineNumberCondition("speed", numberGreaterOrEqualCondition, 1.0),
                stateMachineTriggerCondition("go"),
              ],
            ),
            stateMachineTransition("wave", "idle", @[stateMachineBoolCondition("armed", false)]),
          ],
        ),
      ],
      @[stateMachineBoolInput("armed"), stateMachineNumberInput("speed"), stateMachineTriggerInput("go")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.fireTrigger("go")
    runtime.update(0.25)

    then:
      runtime.layers[0].currentState == "idle"
      closeTo(runtime.layers[0].time, 0.25)
      runtime.isTriggerSet("go")

    runtime.setBoolInput("armed", true)
    runtime.setNumberInput("speed", 1.0)
    runtime.update(0.5)
    let evaluated = runtime.evaluate()

    then:
      runtime.layers[0].currentState == "wave"
      closeTo(runtime.layers[0].time, 0.0)
      not runtime.isTriggerSet("go")
      evaluated.layers[0].state == "wave"
      closeTo(evaluated.pose.scalars[0].value, 90.0)

    runtime.update(0.25)
    runtime.setBoolInput("armed", false)
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "idle"
      closeTo(runtime.layers[0].time, 0.0)

  it "uses first matching transition per state-machine layer":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let first = animationClip(data, "first")
    let second = animationClip(data, "second")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineState("idle", idle), stateMachineState("first", first), stateMachineState("second", second)],
          transitions = @[
            stateMachineTransition("idle", "first", @[stateMachineBoolCondition("armed")]),
            stateMachineTransition("idle", "second", @[stateMachineBoolCondition("armed")]),
          ],
        ),
      ],
      @[stateMachineBoolInput("armed")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.setBoolInput("armed", true)
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "first"

  it "lets one trigger drive transitions across multiple state-machine layers":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let wave = animationClip(data, "wave")
    let open = animationClip(data, "open")
    let blink = animationClip(data, "blink")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineState("idle", idle), stateMachineState("wave", wave)],
          transitions = @[stateMachineTransition("idle", "wave", @[stateMachineTriggerCondition("go")])],
        ),
        stateMachineLayer(
          "eyes",
          @[stateMachineState("open", open), stateMachineState("blink", blink)],
          transitions = @[stateMachineTransition("open", "blink", @[stateMachineTriggerCondition("go")])],
        ),
      ],
      @[stateMachineTriggerInput("go")],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.fireTrigger("go")
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "wave"
      runtime.layers[1].currentState == "blink"
      not runtime.isTriggerSet("go")

  it "emits state-machine listener events for matching transitions":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let wave = animationClip(data, "wave")
    let open = animationClip(data, "open")
    let blink = animationClip(data, "blink")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineState("idle", idle), stateMachineState("wave", wave)],
          transitions = @[stateMachineTransition("idle", "wave", @[stateMachineBoolCondition("armed")])],
        ),
        stateMachineLayer(
          "eyes",
          @[stateMachineState("open", open), stateMachineState("blink", blink)],
          transitions = @[stateMachineTransition("open", "blink", @[stateMachineBoolCondition("armed")])],
        ),
      ],
      @[stateMachineBoolInput("armed")],
      listeners = @[
        stateMachineStateExitListener("base-idle-exit", "base", "idle"),
        stateMachineTransitionListener("base-idle-wave", "base", "idle", "wave"),
        stateMachineStateEnterListener("base-wave-enter", "base", "wave"),
        stateMachineStateEnterListener("eyes-blink-enter", "eyes", "blink"),
      ],
    )
    var runtime = initStateMachineRuntime(machine)
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "idle"
      runtime.events.len == 0

    runtime.setBoolInput("armed", true)
    runtime.update(0.0)

    then:
      runtime.layers[0].currentState == "wave"
      runtime.layers[1].currentState == "blink"
      runtime.events.len == 4
      runtime.events[0].listener == "base-idle-exit"
      runtime.events[0].kind == stateExitListener
      runtime.events[0].layer == "base"
      runtime.events[0].fromState == "idle"
      runtime.events[0].toState == "wave"
      runtime.events[1].listener == "base-idle-wave"
      runtime.events[1].kind == transitionListener
      runtime.events[2].listener == "base-wave-enter"
      runtime.events[2].kind == stateEnterListener
      runtime.events[3].listener == "eyes-blink-enter"
      runtime.events[3].layer == "eyes"
      runtime.events[3].fromState == "open"
      runtime.events[3].toState == "blink"

    runtime.update(0.0)

    then:
      runtime.events.len == 0

  it "rejects invalid state-machine listeners":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let wave = animationClip(data, "wave")
    let states = @[stateMachineState("idle", idle), stateMachineState("wave", wave)]
    let layer = stateMachineLayer(
      "base",
      states,
      transitions = @[stateMachineTransition("idle", "wave", @[stateMachineBoolCondition("armed")])],
    )

    then:
      raisesBonyLoadError(proc() = discard stateMachineStateEnterListener("", "base", "wave"), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineTransitionListener("changed", "base", "idle", ""), schemaViolation)
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          stateMachineStateEnterListener("changed", "missing", "wave"),
        ]),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          stateMachineStateEnterListener("changed", "base", "missing"),
        ]),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          stateMachineStateEnterListener("changed", "base", "wave"),
          stateMachineStateExitListener("changed", "base", "idle"),
        ]),
        duplicateKey,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          stateMachineTransitionListener("changed", "base", "wave", "idle"),
        ]),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          StateMachineListener(
            name: "changed",
            kind: stateEnterListener,
            layer: "base",
            fromState: "idle",
            toState: "wave",
          ),
        ]),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine("machine", @[layer], @[stateMachineBoolInput("armed")], listeners = @[
          StateMachineListener(
            name: "changed",
            kind: stateExitListener,
            layer: "base",
            fromState: "idle",
            toState: "wave",
          ),
        ]),
        schemaViolation,
      )

  it "rejects invalid state-machine transitions and conditions":
    let data = animationFixture()
    let idle = animationClip(data, "idle")
    let wave = animationClip(data, "wave")
    let states = @[stateMachineState("idle", idle), stateMachineState("wave", wave)]

    then:
      raisesBonyLoadError(proc() = discard stateMachineTransition("", "wave", @[stateMachineBoolCondition("armed")]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineTransition("idle", "wave", @[]), schemaViolation)
      raisesBonyLoadError(proc() = discard stateMachineNumberCondition("speed", boolEqualsCondition, 1.0), schemaViolation)
      raisesBonyLoadError(proc() =
        discard stateMachineLayer(
          "base",
          states,
          transitions = @[stateMachineTransition("missing", "wave", @[stateMachineBoolCondition("armed")])],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", states, transitions = @[stateMachineTransition("idle", "wave", @[stateMachineBoolCondition("missing")])])],
        ),
        unknownRequiredReference,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", states, transitions = @[stateMachineTransition("idle", "wave", @[stateMachineBoolCondition("speed")])])],
          @[stateMachineNumberInput("speed")],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", states, transitions = @[stateMachineTransition("idle", "wave", @[stateMachineNumberCondition("armed", numberGreaterCondition, 0.0)])])],
          @[stateMachineBoolInput("armed")],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachine(
          "machine",
          @[stateMachineLayer("base", states, transitions = @[stateMachineTransition("idle", "wave", @[stateMachineTriggerCondition("armed")])])],
          @[stateMachineBoolInput("armed")],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachineTransition(
          "idle",
          "wave",
          @[StateMachineCondition(input: "armed", kind: boolEqualsCondition, numberValue: 1.0)],
        ),
        schemaViolation,
      )
      raisesBonyLoadError(proc() =
        discard stateMachineTransition(
          "idle",
          "wave",
          @[StateMachineCondition(input: "go", kind: triggerSetCondition, boolValue: true)],
        ),
        schemaViolation,
      )
