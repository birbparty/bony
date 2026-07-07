include smoke_support

spec "mesh geometry smoke coverage":
  it "serializes M2 region and slot data":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "", localTransform(x = 3.0))],
      @[slotData("body", "root", "bodyRegion")],
      @[regionAttachment("bodyRegion", 8.0, 4.0)]
    )
    let output = toBonyJson(data)

    then:
      output.contains("\"x\": 3")
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
          data.bones,
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
          data.bones,
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
          data.bones,
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

  it "accepts a slot that references a mesh attachment":
    let data = skeletonData(
      skeletonHeader("meshrig", "0.1.0"),
      @[boneData("root", "")],
      @[slotData("body", "root", "cloth")],
      meshAttachments = @[triMeshFixture("cloth")],
    )
    then:
      data.meshAttachments.len == 1
      data.meshAttachments[0].name == "cloth"

  it "rejects a mesh attachment name that collides with a region name":
    then:
      raisesBonyLoadError(
        proc() = discard skeletonData(
          skeletonHeader("meshrig", "0.1.0"),
          @[boneData("root", "")],
          @[slotData("body", "root", "")],
          @[regionAttachment("shared", 1.0, 1.0)],
          meshAttachments = @[triMeshFixture("shared")],
        ),
        duplicateKey,
      )

  it "rejects a mesh attachment name that collides with a clipping attachment name":
    then:
      raisesBonyLoadError(
        proc() = discard skeletonData(
          skeletonHeader("meshrig", "0.1.0"),
          @[boneData("root", "")],
          @[slotData("body", "root", "")],
          clippingAttachments = @[clipAttachmentData("shared", @[0.0, 0.0, 2.0, 0.0, 0.0, 2.0])],
          meshAttachments = @[triMeshFixture("shared")],
        ),
        duplicateKey,
      )

  it "rejects a duplicate mesh attachment name":
    then:
      raisesBonyLoadError(
        proc() = discard skeletonData(
          skeletonHeader("meshrig", "0.1.0"),
          @[boneData("root", "")],
          @[slotData("body", "root", "cloth")],
          meshAttachments = @[triMeshFixture("cloth"), triMeshFixture("cloth")],
        ),
        duplicateKey,
      )

  it "runs validateMeshAttachment on every loaded mesh":
    # uvs.len != vertices.len must be rejected through the skeleton path,
    # proving the geometry validator is wired into validateSkeletonData.
    then:
      raisesBonyLoadError(
        proc() = discard skeletonData(
          skeletonHeader("meshrig", "0.1.0"),
          @[boneData("root", "")],
          @[slotData("body", "root", "cloth")],
          meshAttachments = @[
            meshAttachmentData(
              "cloth",
              @[meshUv(0.0, 0.0)],
              @[0'u16, 1'u16, 2'u16],
              @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
              false,
            )
          ],
        ),
        schemaViolation,
      )

  it "rejects a slot that references an unknown attachment name":
    then:
      raisesBonyLoadError(
        proc() = discard skeletonData(
          skeletonHeader("meshrig", "0.1.0"),
          @[boneData("root", "")],
          @[slotData("body", "root", "ghost")],
          meshAttachments = @[triMeshFixture("cloth")],
        ),
        unknownRequiredReference,
      )

  it "round trips an unweighted mesh attachment through JSON and .bnb":
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {
      "name": "cloth",
      "vertices": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 1}],
      "uvs": [0, 0, 1, 0, 0, 1],
      "triangles": [0, 1, 2]
    }
  ]
}
"""
    let fromJson = loadBonyJson(jsonText)
    let bnbBytes = toBonyBnb(fromJson)
    let fromBnb = loadBonyBnb(bnbBytes)
    then:
      fromJson.meshAttachments.len == 1
      fromJson.meshAttachments[0].name == "cloth"
      fromJson.meshAttachments[0].weighted == false
      fromJson.meshAttachments[0].vertices.len == 3
      fromJson.meshAttachments[0].vertices[1].weighted == false
      fromJson.meshAttachments[0].vertices[1].x == 1.0
      fromJson.meshAttachments[0].vertices[2].y == 1.0
      fromJson.meshAttachments[0].uvs.len == 3
      fromJson.meshAttachments[0].uvs[2].v == 1.0
      fromJson.meshAttachments[0].triangles == @[0'u16, 1'u16, 2'u16]
      # The default meshWeighted (false) is omitted from canonical output.
      not toBonyJson(fromJson).contains("\"weighted\"")
      # JSON and binary loaders agree on the parsed record.
      fromBnb.meshAttachments.len == 1
      fromBnb.meshAttachments[0].name == "cloth"
      fromBnb.meshAttachments[0].weighted == false
      fromBnb.meshAttachments[0].vertices[1].x == 1.0
      fromBnb.meshAttachments[0].uvs[2].v == 1.0
      fromBnb.meshAttachments[0].triangles == @[0'u16, 1'u16, 2'u16]
      # Canonical JSON output re-parses to an identical record, and .bnb bytes
      # are stable across a decode/encode round trip.
      toBonyJson(loadBonyJson(toBonyJson(fromJson))) == toBonyJson(fromJson)
      toBonyBnb(fromBnb) == bnbBytes

  it "round trips a weighted mesh attachment through JSON and .bnb":
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}, {"name": "tip", "parent": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {
      "name": "cloth",
      "weighted": true,
      "vertices": [
        {"influences": [{"bone": "root", "bindX": 0, "bindY": 0, "weight": 1}]},
        {"influences": [{"bone": "root", "bindX": 1, "bindY": 0, "weight": 0.5}, {"bone": "tip", "bindX": 1, "bindY": 0, "weight": 0.5}]},
        {"influences": [{"bone": "tip", "bindX": 0, "bindY": 1, "weight": 1}]}
      ],
      "uvs": [0, 0, 1, 0, 0, 1],
      "triangles": [0, 1, 2]
    }
  ]
}
"""
    let fromJson = loadBonyJson(jsonText)
    let bnbBytes = toBonyBnb(fromJson)
    let fromBnb = loadBonyBnb(bnbBytes)
    then:
      fromJson.meshAttachments.len == 1
      fromJson.meshAttachments[0].weighted == true
      fromJson.meshAttachments[0].vertices[0].weighted == true
      fromJson.meshAttachments[0].vertices[0].influences.len == 1
      fromJson.meshAttachments[0].vertices[0].influences[0].bone == "root"
      fromJson.meshAttachments[0].vertices[1].influences.len == 2
      fromJson.meshAttachments[0].vertices[1].influences[1].bone == "tip"
      fromJson.meshAttachments[0].vertices[1].influences[1].weight == 0.5
      # weighted:true differs from the default, so it survives the round trip.
      toBonyJson(fromJson).contains("\"weighted\": true")
      toBonyJson(loadBonyJson(toBonyJson(fromJson))) == toBonyJson(fromJson)
      # Binary loader agrees, incl. string-table-packed influence bone names.
      fromBnb.meshAttachments[0].weighted == true
      fromBnb.meshAttachments[0].vertices[1].influences.len == 2
      fromBnb.meshAttachments[0].vertices[1].influences[0].bone == "root"
      fromBnb.meshAttachments[0].vertices[1].influences[1].bone == "tip"
      fromBnb.meshAttachments[0].vertices[1].influences[1].weight == 0.5
      fromBnb.meshAttachments[0].vertices[2].influences[0].bone == "tip"
      # The JSON->model->JSON and .bnb decode/encode paths agree with the JSON load.
      toBonyJson(fromBnb) == toBonyJson(fromJson)
      toBonyBnb(fromBnb) == bnbBytes

  it "runs mesh geometry validation through the JSON load path":
    # A uvs/vertex-count mismatch supplied via JSON must be rejected by
    # validateSkeletonData, proving the JSON reader threads meshes into it.
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {
      "name": "cloth",
      "vertices": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 1}],
      "uvs": [0, 0],
      "triangles": [0, 1, 2]
    }
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), schemaViolation)

  it "rejects a mesh vertex that mixes unweighted and weighted keys":
    # {x,y,influences} is neither a valid unweighted nor weighted vertex; the
    # reader's per-branch key allowlist rejects it.
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {
      "name": "cloth",
      "vertices": [{"x": 0, "y": 0, "influences": []}, {"x": 1, "y": 0}, {"x": 0, "y": 1}],
      "uvs": [0, 0, 1, 0, 0, 1],
      "triangles": [0, 1, 2]
    }
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), schemaViolation)

  # ---- Load-validation rejection matrix (a)-(g), driven through loadBonyJson ----
  # Each fixture is a single unweighted/weighted mesh referenced by one slot; only
  # the failing property differs from a valid triangle mesh. Error kinds match
  # validateMeshAttachment / the mesh value ctors (see docs/mesh-attachment-contract.md).

  it "(a) rejects a mesh whose uvs length does not match the vertex count":
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {"name": "cloth",
     "vertices": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 1}],
     "uvs": [0, 0, 1, 0], "triangles": [0, 1, 2]}
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), schemaViolation)

  it "(b) rejects a mesh whose triangle count is not a multiple of three":
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {"name": "cloth",
     "vertices": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 1}],
     "uvs": [0, 0, 1, 0, 0, 1], "triangles": [0, 1]}
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), schemaViolation)

  it "(b) rejects a mesh with an out-of-range triangle index":
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {"name": "cloth",
     "vertices": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 1}],
     "uvs": [0, 0, 1, 0, 0, 1], "triangles": [0, 1, 3]}
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), unknownRequiredReference)

  it "(c) rejects a weighted mesh whose influence weights do not sum to one":
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {"name": "cloth", "weighted": true,
     "vertices": [
       {"influences": [{"bone": "root", "bindX": 0, "bindY": 0, "weight": 0.25}]},
       {"influences": [{"bone": "root", "bindX": 1, "bindY": 0, "weight": 1}]},
       {"influences": [{"bone": "root", "bindX": 0, "bindY": 1, "weight": 1}]}
     ],
     "uvs": [0, 0, 1, 0, 0, 1], "triangles": [0, 1, 2]}
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), schemaViolation)

  it "(d) rejects a weighted mesh whose influence names an unknown bone":
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {"name": "cloth", "weighted": true,
     "vertices": [
       {"influences": [{"bone": "ghost", "bindX": 0, "bindY": 0, "weight": 1}]},
       {"influences": [{"bone": "root", "bindX": 1, "bindY": 0, "weight": 1}]},
       {"influences": [{"bone": "root", "bindX": 0, "bindY": 1, "weight": 1}]}
     ],
     "uvs": [0, 0, 1, 0, 0, 1], "triangles": [0, 1, 2]}
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), unknownRequiredReference)

  it "(e) rejects an empty mesh with no vertices":
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {"name": "cloth", "vertices": [], "uvs": [], "triangles": []}
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), schemaViolation)

  it "(g) rejects a mesh whose weighted flag disagrees with its vertex shape":
    # weighted:true but the vertices are plain {x,y}: the reader builds unweighted
    # vertices, and validateMeshAttachment rejects the flag mismatch.
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {"name": "cloth", "weighted": true,
     "vertices": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 1}],
     "uvs": [0, 0, 1, 0, 0, 1], "triangles": [0, 1, 2]}
  ]
}
"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJson(jsonText), schemaViolation)

  it "(f) round trips an unreferenced mesh (present but inert) through JSON and .bnb":
    # A mesh in meshAttachments referenced by zero slots is valid and survives the
    # round trip unchanged (mirrors clipping's inert-clip allowance).
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "body", "bone": "root"}],
  "meshAttachments": [
    {"name": "cloth",
     "vertices": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 1}],
     "uvs": [0, 0, 1, 0, 0, 1], "triangles": [0, 1, 2]}
  ]
}
"""
    let fromJson = loadBonyJson(jsonText)
    let bnbBytes = toBonyBnb(fromJson)
    let fromBnb = loadBonyBnb(bnbBytes)
    then:
      fromJson.meshAttachments.len == 1
      fromJson.meshAttachments[0].name == "cloth"
      fromBnb.meshAttachments.len == 1
      toBonyJson(fromBnb) == toBonyJson(fromJson)
      toBonyBnb(fromBnb) == bnbBytes

  it "rejects every truncation of a weighted mesh .bnb without crashing":
    # Regression guard for the packed mesh-payload bounds checks: no truncation of
    # a valid weighted mesh .bnb may escape as a Nim Defect or be silently
    # accepted. A weighted mesh exercises the varuint influence counts, f32
    # bind/weight reads, and string-table bone indices in the vertices payload.
    let jsonText = """
{
  "skeleton": {"name": "meshrig", "version": "0.1.0"},
  "bones": [{"name": "root"}, {"name": "tip", "parent": "root"}],
  "slots": [{"name": "body", "bone": "root", "attachment": "cloth"}],
  "meshAttachments": [
    {
      "name": "cloth",
      "weighted": true,
      "vertices": [
        {"influences": [{"bone": "root", "bindX": 0, "bindY": 0, "weight": 1}]},
        {"influences": [{"bone": "root", "bindX": 1, "bindY": 0, "weight": 0.5}, {"bone": "tip", "bindX": 1, "bindY": 0, "weight": 0.5}]},
        {"influences": [{"bone": "tip", "bindX": 0, "bindY": 1, "weight": 1}]}
      ],
      "uvs": [0, 0, 1, 0, 0, 1],
      "triangles": [0, 1, 2]
    }
  ]
}
"""
    let bnbBytes = toBonyBnb(loadBonyJson(jsonText))
    var allTruncationsRejected = true
    for cut in 1 ..< bnbBytes.len:
      let prefix = bnbBytes[0 ..< cut]
      if not raisesAnyBonyLoadError(proc() = discard loadBonyBnb(prefix)):
        allTruncationsRejected = false
        break
    then:
      # Sanity: the full stream still loads.
      loadBonyBnb(bnbBytes).meshAttachments.len == 1
      allTruncationsRejected
