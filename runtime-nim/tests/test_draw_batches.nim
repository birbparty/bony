include smoke_support

spec "draw batch and raster smoke coverage":
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

  it "threads caller-supplied worlds into draw batches":
    # Mirrors the physics story path: a stateful stage advances bone worlds and
    # threads them into buildDrawBatches so draw-batch vertices reflect physics
    # rather than the pure world-transform pass. Two bones/slots lock the
    # parallel-index mapping: each slot's batch must pick up ITS bone's world,
    # so a mis-indexed lookup (or a revert to internal recomputation) fails here.
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[
        boneData("root", "", localTransform(x = 3.0, y = 0.0)),
        boneData("arm", "root", localTransform(x = 0.0, y = 0.0)),
      ],
      @[
        slotData("body", "root", "bodyRegion"),
        slotData("hand", "arm", "handRegion"),
      ],
      @[
        regionAttachment("bodyRegion", 8.0, 4.0),
        regionAttachment("handRegion", 8.0, 4.0),
      ]
    )
    var worlds = computeWorldTransforms(data)
    # Shift each bone world by a DISTINCT offset, as a physics stage would; each
    # batch's vertices must follow its own bone, proving worlds[i] <-> bones[i].
    worlds[0].tx = worlds[0].tx + 100.0
    worlds[0].ty = worlds[0].ty + 50.0
    worlds[1].tx = worlds[1].tx + 400.0
    worlds[1].ty = worlds[1].ty + 200.0
    let batches = buildDrawBatches(data, worlds)

    then:
      batches.len == 2
      # body slot -> root bone (worlds[0], base tx=3): pure pass would be (-1,-2).
      batches[0].slot == "body"
      closeTo(batches[0].world.tx, 103)
      closeTo(batches[0].world.ty, 50)
      closeTo(batches[0].vertices[0].x, 99)
      closeTo(batches[0].vertices[0].y, 48)
      closeTo(batches[0].vertices[2].x, 107)
      closeTo(batches[0].vertices[2].y, 52)
      # hand slot -> arm bone (worlds[1], base tx=3 inherited from root).
      batches[1].slot == "hand"
      closeTo(batches[1].world.tx, 403)
      closeTo(batches[1].world.ty, 200)
      closeTo(batches[1].vertices[0].x, 399)
      closeTo(batches[1].vertices[0].y, 198)
      closeTo(batches[1].vertices[2].x, 407)
      closeTo(batches[1].vertices[2].y, 202)

  it "renders draw batches with the software rasterizer":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "", localTransform(x = 1.0, y = 1.0))],
      @[slotData("body", "root", "bodyRegion")],
      @[regionAttachment("bodyRegion", 2.0, 2.0)]
    )
    let image = renderSoftware(buildDrawBatches(data), 3, 3)

    then:
      image[0, 0].a == 255
      image[0, 0].r == 255
      image[1, 1].a == 255
      image[2, 2].a == 0

  it "samples texture pages with the software rasterizer":
    let texture = newImage(2, 2)
    texture.fill(rgba(0, 0, 0, 0))
    texture[0, 0] = rgba(255, 0, 0, 255)
    let batch = DrawBatch(
      texturePage: "atlas",
      blendMode: "normal",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, u: 0.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 1.0, y: 0.0, u: 0.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 0.0, y: 1.0, u: 0.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )
    let image = renderSoftware(
      @[batch],
      softwareRasterOptions(1, 1, texturePages = @[softwareTexturePage("atlas", texture)])
    )

    then:
      image[0, 0].r == 255
      image[0, 0].g == 0
      image[0, 0].b == 0
      image[0, 0].a == 255

  it "does not double blend shared triangle edges":
    let batch = DrawBatch(
      blendMode: "normal",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 0.5),
        DrawVertex(x: 2.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 0.5),
        DrawVertex(x: 2.0, y: 2.0, r: 1.0, g: 1.0, b: 1.0, a: 0.5),
        DrawVertex(x: 0.0, y: 2.0, r: 1.0, g: 1.0, b: 1.0, a: 0.5),
      ],
      indices: @[0'u16, 1'u16, 2'u16, 2'u16, 3'u16, 0'u16],
    )
    let image = renderSoftware(@[batch], 2, 2)

    then:
      image[0, 0].a == 128
      image[0, 0].r == 128
      image[1, 0].a == 128
      image[1, 0].r == 128
      image[0, 1].a == 128
      image[0, 1].r == 128
      image[1, 1].a == 128
      image[1, 1].r == 128

  it "decodes premultiplied texture pages":
    let texture = newImage(1, 1)
    texture[0, 0] = rgba(128, 0, 0, 128)
    let batch = DrawBatch(
      texturePage: "atlas",
      blendMode: "normal",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, u: 0.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 1.0, y: 0.0, u: 0.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 0.0, y: 1.0, u: 0.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )
    let image = renderSoftware(
      @[batch],
      softwareRasterOptions(1, 1, texturePages = @[softwareTexturePage("atlas", texture, premultipliedAlpha = true)])
    )

    then:
      image[0, 0].r == 128
      image[0, 0].g == 0
      image[0, 0].b == 0
      image[0, 0].a == 128

  it "rejects invalid software rasterizer input":
    let batch = DrawBatch(
      texturePage: "missing",
      blendMode: "normal",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 1.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 0.0, y: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )
    let badBlend = DrawBatch(blendMode: "unknown")
    let badIndex = DrawBatch(
      blendMode: "normal",
      vertices: @[DrawVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0)],
      indices: @[0'u16, 1'u16, 2'u16],
    )

    then:
      raisesBonyLoadError(proc() = discard renderSoftware(@[batch], 1, 1), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard renderSoftware(@[badBlend], 1, 1), schemaViolation)
      raisesBonyLoadError(proc() = discard renderSoftware(@[badIndex], 1, 1), unknownRequiredReference)
      raisesBonyLoadError(
        proc() = discard renderSoftware(
          @[],
          softwareRasterOptions(
            1,
            1,
            texturePages = @[
              softwareTexturePage("atlas", newImage(1, 1)),
              softwareTexturePage("atlas", newImage(1, 1)),
            ],
          ),
        ),
        duplicateKey,
      )
      raisesBonyLoadError(proc() = discard softwareRasterOptions(0, 1), schemaViolation)

  it "writes software rasterizer images as PNG":
    let path = "/tmp/bony_software_rasterizer_test.png"
    if fileExists(path):
      removeFile(path)
    let image = renderSoftware(@[], softwareRasterOptions(1, 1, clear = rgba(1, 2, 3, 4)))
    image.writeFile(path)

    then:
      fileExists(path)
      getFileSize(path) > 0

    removeFile(path)

  it "viewport transform maps world origin to screen centre and flips y":
    # Pin the math used by `applyViewportTransform` (cli/bony_cli.nim) so a
    # future y-flip sign regression cannot hide behind a regenerated golden.
    # Inlined here because the proc lives in the CLI module, not the library.
    # Mapping: screen_x = world_x + cx;  screen_y = cy - world_y
    let w = 256
    let h = 256
    let cx = float64(w) * 0.5  # 128.0
    let cy = float64(h) * 0.5  # 128.0

    # Rig A: root at world (0, 0) with a 4×4 region.
    # After transform the region covers screen x=[126,130], y=[126,130].
    let rigA = skeletonData(
      skeletonHeader("vp-test-origin", "0.1.0"),
      @[boneData("root", "", localTransform())],
      @[slotData("body", "root", "sq")],
      @[regionAttachment("sq", 4.0, 4.0)],
    )
    var batchesA = buildDrawBatches(rigA)
    for i in 0 ..< batchesA.len:
      for j in 0 ..< batchesA[i].vertices.len:
        batchesA[i].vertices[j].x += cx
        batchesA[i].vertices[j].y = cy - batchesA[i].vertices[j].y
    let imgA = renderSoftware(batchesA, w, h)

    # Rig B: child bone at world (0, -60) — same geometry as m8 head.
    # After transform the region centre lands at screen (128, 188).
    let rigB = skeletonData(
      skeletonHeader("vp-test-neg-y", "0.1.0"),
      @[
        boneData("root", "", localTransform()),
        boneData("head", "root", localTransform(y = -60.0)),
      ],
      @[slotData("body", "head", "sq")],
      @[regionAttachment("sq", 4.0, 4.0)],
    )
    var batchesB = buildDrawBatches(rigB)
    for i in 0 ..< batchesB.len:
      for j in 0 ..< batchesB[i].vertices.len:
        batchesB[i].vertices[j].x += cx
        batchesB[i].vertices[j].y = cy - batchesB[i].vertices[j].y
    let imgB = renderSoftware(batchesB, w, h)

    then:
      # World (0, 0) → screen (128, 128): visible in rig A
      imgA[128, 128].a == 255
      # World (0, -60) → screen (128, 188): visible in rig B
      imgB[128, 188].a == 255
      # World (0, +60) → screen (128, 68): empty in rig B (bone is at y=-60, not +60)
      imgB[128, 68].a == 0

  it "plans naylib draw batches with color-only blend presets":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "")],
      @[slotData("body", "root", "bodyRegion")],
      @[regionAttachment("bodyRegion", 2.0, 2.0)]
    )
    var batches = buildDrawBatches(data)
    batches[0].texturePage = "atlas"
    let plan = buildNaylibRenderPlan(
      batches,
      naylibRenderOptions(texturePages = @[naylibTexturePage("atlas", 7'u32, premultipliedAlpha)])
    )

    then:
      plan.len == 3
      plan[0].kind == nropShader
      plan[0].shader == nskOneColor
      plan[1].kind == nropBlendPreset
      plan[1].blendPreset == nbpAlphaPremultiply
      plan[2].kind == nropDrawTriangles
      plan[2].textureId == 7'u32
      plan[2].triangleCount == 2
      plan[2].usesStencil == false

  it "plans naylib alpha-observed custom blend factors":
    let batch = DrawBatch(
      texturePage: "atlas",
      blendMode: "normal",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 1.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 0.0, y: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )
    let plan = buildNaylibRenderPlan(
      @[batch],
      naylibRenderOptions(texturePages = @[naylibTexturePage("atlas", 9'u32)], alphaObserved = true)
    )

    then:
      plan[1].kind == nropBlendSeparate
      plan[1].blendSeparate.srcRgb == nbfSrcAlpha
      plan[1].blendSeparate.dstRgb == nbfOneMinusSrcAlpha
      plan[1].blendSeparate.srcAlpha == nbfOne
      plan[1].blendSeparate.dstAlpha == nbfOneMinusSrcAlpha

  it "plans naylib additive and multiply custom paths":
    let batch = DrawBatch(
      blendMode: "additive",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 1.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 0.0, y: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )
    let additive = buildNaylibRenderPlan(@[batch], naylibRenderOptions())
    var multiplyBatch = batch
    multiplyBatch.blendMode = "multiply"
    let multiply = buildNaylibRenderPlan(@[multiplyBatch], naylibRenderOptions(alphaObserved = true))
    var pmaAdditiveBatch = batch
    pmaAdditiveBatch.texturePage = "atlas"
    let pmaAdditive = buildNaylibRenderPlan(
      @[pmaAdditiveBatch],
      naylibRenderOptions(texturePages = @[naylibTexturePage("atlas", 1'u32, premultipliedAlpha)])
    )
    var pmaMultiplyBatch = batch
    pmaMultiplyBatch.texturePage = "atlas"
    pmaMultiplyBatch.blendMode = "multiply"
    let pmaMultiply = buildNaylibRenderPlan(
      @[pmaMultiplyBatch],
      naylibRenderOptions(texturePages = @[naylibTexturePage("atlas", 1'u32, premultipliedAlpha)])
    )

    then:
      additive[1].kind == nropBlendSeparate
      additive[1].blendSeparate.srcRgb == nbfSrcAlpha
      additive[1].blendSeparate.dstRgb == nbfOne
      additive[1].blendSeparate.srcAlpha == nbfOne
      additive[1].blendSeparate.dstAlpha == nbfOne
      multiply[1].kind == nropShader
      multiply[1].shader == nskMultiplyPremultiply
      multiply[2].kind == nropBlendSeparate
      multiply[2].blendSeparate.srcRgb == nbfDstColor
      pmaAdditive[1].blendSeparate.srcRgb == nbfOne
      pmaMultiply[1].kind == nropShader
      pmaMultiply[2].kind == nropBlendSeparate

  it "plans naylib screen with destination-color factors":
    let batch = DrawBatch(
      blendMode: "screen",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 1.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 0.0, y: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )
    let straight = buildNaylibRenderPlan(@[batch], naylibRenderOptions())
    var pmaBatch = batch
    pmaBatch.texturePage = "atlas"
    let pma = buildNaylibRenderPlan(
      @[pmaBatch],
      naylibRenderOptions(texturePages = @[naylibTexturePage("atlas", 3'u32, premultipliedAlpha)])
    )

    then:
      straight[1].kind == nropShader
      straight[1].shader == nskScreen
      straight[2].kind == nropBlendSeparate
      straight[2].blendSeparate.srcRgb == nbfOneMinusDstColor
      straight[2].blendSeparate.dstRgb == nbfOne
      pma[1].pageAlphaMode == premultipliedAlpha

  it "plans naylib tint-black and geometry-side clipping":
    let batch = NaylibDrawBatch(
      texturePage: "atlas",
      blendMode: "normal",
      clipId: "clip-a",
      vertices: @[
        NaylibVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0, darkR: 0.25),
        NaylibVertex(x: 1.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0, darkR: 0.25),
        NaylibVertex(x: 0.0, y: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0, darkR: 0.25),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )
    let plan = buildNaylibRenderPlan(
      @[batch],
      naylibRenderOptions(texturePages = @[naylibTexturePage("atlas", 11'u32)])
    )

    then:
      plan[0].kind == nropShader
      plan[0].shader == nskTintBlack
      plan[0].requiresCustomVertexLayout == true
      plan[2].kind == nropDrawTriangles
      plan[2].clipId == "clip-a"
      plan[2].usesStencil == false

  it "rejects invalid naylib adapter input":
    let badBlend = DrawBatch(blendMode: "bogus")
    let emptyBlend = DrawBatch(blendMode: "")
    let missingPage = DrawBatch(
      texturePage: "missing",
      blendMode: "normal",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 1.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 0.0, y: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )

    then:
      raisesBonyLoadError(proc() = discard buildNaylibRenderPlan(@[badBlend]), schemaViolation)
      raisesBonyLoadError(proc() = discard buildNaylibRenderPlan(@[emptyBlend]), schemaViolation)
      raisesBonyLoadError(proc() = discard buildNaylibRenderPlan(@[missingPage]), unknownRequiredReference)
      raisesBonyLoadError(
        proc() = discard buildNaylibRenderPlan(
          newSeq[DrawBatch](),
          naylibRenderOptions(texturePages = @[
            naylibTexturePage("atlas", 1'u32),
            naylibTexturePage("atlas", 2'u32),
          ]),
        ),
        duplicateKey,
      )

  it "traces naylib bridge call sequencing without a GPU context":
    let batch = DrawBatch(
      blendMode: "normal",
      vertices: @[
        DrawVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 1.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
        DrawVertex(x: 0.0, y: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      ],
      indices: @[0'u16, 1'u16, 2'u16],
    )
    let calls = traceNaylibRenderPlan(buildNaylibRenderPlan(@[batch]))
    let emptyCalls = traceNaylibRenderPlan(buildNaylibRenderPlan(@[DrawBatch(blendMode: "normal")]))
    let tintPlan = buildNaylibRenderPlan(
      @[
        NaylibDrawBatch(
          blendMode: "normal",
          vertices: @[
            NaylibVertex(x: 0.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0, darkR: 0.5),
            NaylibVertex(x: 1.0, y: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0, darkR: 0.5),
            NaylibVertex(x: 0.0, y: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0, darkR: 0.5),
          ],
          indices: @[0'u16, 1'u16, 2'u16],
        )
      ],
      naylibRenderOptions(),
    )

    then:
      calls[0].kind == nckFlush
      calls[1].kind == nckShader
      calls[2].kind == nckFlush
      calls[3].kind == nckBlendPreset
      calls[4].kind == nckSetTexture
      calls[5].kind == nckVertex
      calls[8].kind == nckSetTexture
      calls[8].textureId == 0'u32
      calls[^2].kind == nckDisableShader
      calls[^1].kind == nckEndBlend
      emptyCalls.len == 2
      emptyCalls[0].kind == nckDisableShader
      raisesBonyLoadError(proc() = discard traceNaylibRenderPlan(tintPlan), schemaViolation)

  it "emits an unweighted mesh batch skinned through the slot bone":
    # A slot referencing a mesh must produce one DrawBatch whose world-space
    # vertices equal skinMeshVertices (FK through the slot bone), whose indices
    # equal the mesh triangles, and whose u,v equal the mesh uvs. Pins the mesh
    # dispatch that precedes the non-region guard in buildDrawBatches.
    let bones = @[boneData("root", "", localTransform(x = 3.0, y = 2.0))]
    let prelim = skeletonData(skeletonHeader("demo", "0.1.0"), bones)
    let mesh = unweightedMeshAttachment(
      prelim,
      "quad",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(-1.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(1.0, 2.0)],
    )
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      bones,
      @[slotData("body", "root", "quad")],
      meshAttachments = @[mesh],
    )
    let worlds = computeWorldTransforms(data)
    let expected = skinMeshVertices(data, worlds, "root", mesh)
    let batches = buildDrawBatches(data, worlds)
    let batch = batches.batchFor("body")

    then:
      batches.len == 1
      batch.slot == "body"
      batch.bone == "root"
      batch.attachment == "quad"
      batch.texturePage == ""
      batch.blendMode == "normal"
      batch.clipId == ""
      batch.indices == mesh.triangles
      batch.vertices.len == expected.len
      # Vertices match the hand-computed skinning within 1e-4, with uvs carried
      # straight from the mesh.
      closeWithin(batch.vertices[0].x, expected[0].x, 1e-4)
      closeWithin(batch.vertices[0].y, expected[0].y, 1e-4)
      closeWithin(batch.vertices[2].x, expected[2].x, 1e-4)
      closeWithin(batch.vertices[2].y, expected[2].y, 1e-4)
      closeWithin(batch.vertices[2].u, 1.0, 1e-4)
      closeWithin(batch.vertices[2].v, 1.0, 1e-4)
      # Uniform region color (v1 mesh has no per-vertex color).
      closeWithin(batch.vertices[0].r, 1.0, 1e-9)
      closeWithin(batch.vertices[0].a, 1.0, 1e-9)
      # Explicit FK positions: root translate (3,2) applied to each bind vertex.
      closeWithin(batch.vertices[0].x, 2.0, 1e-4)
      closeWithin(batch.vertices[0].y, 2.0, 1e-4)
      closeWithin(batch.vertices[2].x, 4.0, 1e-4)
      closeWithin(batch.vertices[2].y, 4.0, 1e-4)

  it "emits a weighted mesh batch via linear-blend skinning":
    # A weighted vertex shared across two posed bones must land at the blended
    # position, strictly different from either bone's FK of its own bind — proving
    # the blend is observable, not a single-bone passthrough.
    let bones = @[
      boneData("root", "", localTransform(x = 10.0)),
      boneData("child", "root", localTransform(y = 4.0)),
    ]
    let prelim = skeletonData(skeletonHeader("demo", "0.1.0"), bones)
    let mesh = weightedMeshAttachment(
      prelim,
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
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      bones,
      @[slotData("meshSlot", "root", "weighted")],
      meshAttachments = @[mesh],
    )
    let worlds = computeWorldTransforms(data)
    let expected = skinMeshVertices(data, worlds, "root", mesh)
    let batches = buildDrawBatches(data, worlds)
    let batch = batches.batchFor("meshSlot")

    then:
      batches.len == 1
      batch.attachment == "weighted"
      batch.indices == mesh.triangles
      batch.vertices.len == 1
      closeWithin(batch.vertices[0].x, expected[0].x, 1e-4)
      closeWithin(batch.vertices[0].y, expected[0].y, 1e-4)
      # Blended target: 0.25*root(2,0) + 0.75*child(0,2) = (10.5, 4.5).
      closeWithin(batch.vertices[0].x, quantizeF32(10.5), 1e-4)
      closeWithin(batch.vertices[0].y, quantizeF32(4.5), 1e-4)
      # Non-vacuous blend: differs from EITHER single bone's FK of its bind
      # (root FK of (2,0) = (12,0); child FK of (0,2) = (10,6)).
      not closeWithin(batch.vertices[0].x, 12.0, 1e-3)
      not closeWithin(batch.vertices[0].y, 6.0, 1e-3)

  it "clips mesh batches per-triangle in the clip pass":
    # A mesh slot inside a clip's covered range is clipped per-triangle: the clip
    # `mask` (x >= 0) cuts the single triangle (-1,-1),(1,-1),(1,1) whose left
    # vertex is outside, so the batch gains clipId, drops the left vertex, and
    # gains two new vertices on the x = 0 cut with interpolated uv.
    let bones = @[boneData("root", "")]
    let prelim = skeletonData(skeletonHeader("cliprig", "0.1.0"), bones)
    let mesh = unweightedMeshAttachment(
      prelim,
      "meshQuad",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(-1.0, -1.0), unweightedMeshVertex(1.0, -1.0), unweightedMeshVertex(1.0, 1.0)],
    )
    let data = skeletonData(
      skeletonHeader("cliprig", "0.1.0"),
      bones,
      @[
        slotData("clipSlot", "root", "mask"),
        slotData("meshSlot", "root", "meshQuad"),
      ],
      clippingAttachments = @[
        # A clip (x >= 0) that cuts the mesh's left vertex (x < 0).
        clipAttachmentData("mask", @[0.0, -3.0, 3.0, -3.0, 3.0, 3.0, 0.0, 3.0], "meshSlot"),
      ],
      meshAttachments = @[mesh],
    )
    let batches = buildDrawBatches(data)
    let batch = batches.batchFor("meshSlot")
    # Every clipped vertex is on or right of the x = 0 cut.
    var minX = 1e9
    var hasCut = false
    for v in batch.vertices:
      minX = min(minX, v.x)
      if closeWithin(v.x, 0.0, 1e-6) and closeWithin(v.y, 0.0, 1e-6):
        hasCut = true

    then:
      batch.attachment == "meshQuad"
      batch.clipId == "mask"
      # The clipped triangle becomes a 4-vertex fan (left vertex removed, two new
      # cut vertices added): indices [0,1,2, 0,2,3].
      batch.vertices.len == 4
      batch.indices == @[0'u16, 1'u16, 2'u16, 0'u16, 2'u16, 3'u16]
      minX >= -1e-6
      hasCut

  it "clips both a region and a mesh in the same clip range":
    # Both a region and a mesh sit inside one clip's covered range. Clipping is
    # per-batch and per-dispatch-arm: the region is clipped as a convex ring
    # while the mesh is clipped per-triangle, and BOTH gain clipId. Pins that the
    # mesh arm no longer bails out of the clip pass.
    let bones = @[boneData("root", "")]
    let prelim = skeletonData(skeletonHeader("cliprig", "0.1.0"), bones)
    let mesh = unweightedMeshAttachment(
      prelim,
      "meshQuad",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(-1.0, -1.0), unweightedMeshVertex(1.0, -1.0), unweightedMeshVertex(1.0, 1.0)],
    )
    let data = skeletonData(
      skeletonHeader("cliprig", "0.1.0"),
      bones,
      @[
        slotData("clipSlot", "root", "mask"),
        slotData("meshSlot", "root", "meshQuad"),
        slotData("regionSlot", "root", "body"),
      ],
      @[regionAttachment("body", 2.0, 2.0)],
      clippingAttachments = @[
        # Clip x >= 0: cuts the left half of both the mesh and the region.
        # untilSlot=regionSlot so both covered slots are in range.
        clipAttachmentData("mask", @[0.0, -3.0, 3.0, -3.0, 3.0, 3.0, 0.0, 3.0], "regionSlot"),
      ],
      meshAttachments = @[mesh],
    )
    let batches = buildDrawBatches(data)
    let meshBatch = batches.batchFor("meshSlot")
    let regionBatch = batches.batchFor("regionSlot")
    var meshMinX = 1e9
    for v in meshBatch.vertices:
      meshMinX = min(meshMinX, v.x)

    then:
      # Mesh: clipped per-triangle in the same range (clipId set, left vertex cut).
      meshBatch.clipId == "mask"
      meshBatch.vertices.len == 4
      meshMinX >= -1e-6
      # Region: clipped in the same range (clipId set, left half removed).
      regionBatch.clipId == "mask"
      regionBatch.vertices.len >= 3

  it "emits batches in slot draw order across mesh and region dispatch arms":
    # Interleaved region/mesh/region slots must emit in slot order, proving both
    # dispatch arms append to `result`/`batchSlotIndex` in the same pass without
    # reordering.
    let bones = @[boneData("root", "")]
    let prelim = skeletonData(skeletonHeader("demo", "0.1.0"), bones)
    let mesh = unweightedMeshAttachment(
      prelim,
      "midMesh",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(1.0, 1.0)],
    )
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      bones,
      @[
        slotData("regionA", "root", "bodyA"),
        slotData("meshB", "root", "midMesh"),
        slotData("regionC", "root", "bodyC"),
      ],
      @[regionAttachment("bodyA", 2.0, 2.0), regionAttachment("bodyC", 2.0, 2.0)],
      meshAttachments = @[mesh],
    )
    let batches = buildDrawBatches(data)

    then:
      batches.len == 3
      batches[0].slot == "regionA"
      batches[1].slot == "meshB"
      batches[1].attachment == "midMesh"
      batches[2].slot == "regionC"
