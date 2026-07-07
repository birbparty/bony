include smoke_support

spec "mesh deform timeline smoke coverage":
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

  it "round-trips a clip-owned deform timeline through JSON and BNB":
    const source = """{
  "skeleton": { "name": "deform-rt", "version": "1.0.0" },
  "bones": [ { "name": "root" } ],
  "slots": [ { "name": "cloth", "bone": "root", "attachment": "cloth_mesh" } ],
  "meshAttachments": [
    {
      "name": "cloth_mesh",
      "weighted": false,
      "vertices": [ { "x": 0.0, "y": 0.0 }, { "x": 4.0, "y": 0.0 }, { "x": 0.0, "y": 4.0 } ],
      "uvs": [ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 ],
      "triangles": [ 0, 1, 2 ]
    }
  ],
  "animations": [
    {
      "name": "wiggle",
      "deformTimelines": [
        {
          "skin": "default",
          "slot": "cloth",
          "attachment": "cloth_mesh",
          "vertexCount": 3,
          "keyframes": [
            { "t": 0.0, "offset": 0, "deltas": [ { "x": 1.0, "y": 0.0 }, { "x": 0.0, "y": 2.0 }, { "x": -1.0, "y": -1.0 } ] },
            { "t": 1.0, "offset": 1, "deltas": [ { "x": 3.0, "y": 0.0 }, { "x": 0.0, "y": 1.0 } ] }
          ]
        }
      ]
    }
  ]
}"""
    let fromJson = loadBonyJsonAsset(source)
    let fromBnb = loadBonyBnbAsset(toBonyBnb(fromJson))
    let jsonDeform = fromJson.animations[0].deformTimelines[0]
    let bnbDeform = fromBnb.animations[0].deformTimelines[0]

    # JSON- and BNB-loaded timelines must sample identically at several times.
    var samplesMatch = true
    for t in [0.0, 0.25, 0.5, 1.0]:
      let js = sampleDeformDeltas(jsonDeform, t)
      let bs = sampleDeformDeltas(bnbDeform, t)
      if js.len != bs.len:
        samplesMatch = false
      else:
        for i in 0 ..< js.len:
          if not closeTo(js[i].x, bs[i].x) or not closeTo(js[i].y, bs[i].y):
            samplesMatch = false

    then:
      fromJson.animations.len == 1
      fromJson.animations[0].deformTimelines.len == 1
      fromBnb.animations[0].deformTimelines.len == 1
      # Field parity from JSON.
      jsonDeform.skin == "default"
      jsonDeform.slot == "cloth"
      jsonDeform.attachment == "cloth_mesh"
      jsonDeform.vertexCount == 3
      jsonDeform.keys.len == 2
      # JSON emit is stable across a re-load.
      toBonyJson(loadBonyJsonAsset(toBonyJson(fromJson))) == toBonyJson(fromJson)
      # BNB decode reproduces the same record shape.
      bnbDeform.skin == jsonDeform.skin
      bnbDeform.slot == jsonDeform.slot
      bnbDeform.attachment == jsonDeform.attachment
      bnbDeform.vertexCount == jsonDeform.vertexCount
      bnbDeform.keys.len == jsonDeform.keys.len
      samplesMatch

  it "rejects a deform timeline whose slot/attachment pairing does not resolve":
    # slotA shows meshA, but the deform timeline targets meshB on slotA — the
    # (slot, attachment) pairing must be rejected at load (contract edge (g)).
    const badRig = """{
  "skeleton": { "name": "bad-deform", "version": "1.0.0" },
  "bones": [ { "name": "root" } ],
  "slots": [
    { "name": "slotA", "bone": "root", "attachment": "meshA" },
    { "name": "slotB", "bone": "root", "attachment": "meshB" }
  ],
  "meshAttachments": [
    { "name": "meshA", "weighted": false,
      "vertices": [ { "x": 0.0, "y": 0.0 }, { "x": 1.0, "y": 0.0 }, { "x": 0.0, "y": 1.0 } ],
      "uvs": [ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 ], "triangles": [ 0, 1, 2 ] },
    { "name": "meshB", "weighted": false,
      "vertices": [ { "x": 0.0, "y": 0.0 }, { "x": 1.0, "y": 0.0 }, { "x": 0.0, "y": 1.0 } ],
      "uvs": [ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 ], "triangles": [ 0, 1, 2 ] }
  ],
  "animations": [
    { "name": "wiggle", "deformTimelines": [
      { "skin": "default", "slot": "slotA", "attachment": "meshB", "vertexCount": 3,
        "keyframes": [ { "t": 0.0, "offset": 0, "deltas": [ { "x": 1.0, "y": 0.0 }, { "x": 0.0, "y": 1.0 }, { "x": 0.0, "y": 0.0 } ] } ] } ] } ]
}"""
    then:
      raisesBonyLoadError(proc() = discard loadBonyJsonAsset(badRig), unknownRequiredReference)

  it "animates a mesh via a clip deform timeline through the mixer and draw path":
    const rig = """{
  "skeleton": { "name": "deform-anim", "version": "1.0.0" },
  "bones": [ { "name": "root" } ],
  "slots": [
    { "name": "slotA", "bone": "root", "attachment": "meshA" },
    { "name": "slotB", "bone": "root", "attachment": "meshB" }
  ],
  "meshAttachments": [
    {
      "name": "meshA", "weighted": false,
      "vertices": [ { "x": 0.0, "y": 0.0 }, { "x": 4.0, "y": 0.0 }, { "x": 0.0, "y": 4.0 } ],
      "uvs": [ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 ], "triangles": [ 0, 1, 2 ]
    },
    {
      "name": "meshB", "weighted": false,
      "vertices": [ { "x": 1.0, "y": 1.0 }, { "x": 5.0, "y": 1.0 }, { "x": 1.0, "y": 5.0 } ],
      "uvs": [ 0.0, 0.0, 1.0, 0.0, 0.0, 1.0 ], "triangles": [ 0, 1, 2 ]
    }
  ],
  "animations": [
    {
      "name": "wiggle",
      "deformTimelines": [
        {
          "skin": "default", "slot": "slotA", "attachment": "meshA", "vertexCount": 3,
          "keyframes": [
            { "t": 0.0, "offset": 0, "deltas": [ { "x": 1.0, "y": 0.0 }, { "x": 0.0, "y": 2.0 }, { "x": -1.0, "y": -1.0 } ] },
            { "t": 1.0, "offset": 0, "deltas": [ { "x": 3.0, "y": 0.0 }, { "x": 0.0, "y": 4.0 }, { "x": -3.0, "y": -3.0 } ] }
          ]
        }
      ]
    }
  ]
}"""
    let asset = loadBonyJsonAsset(rig)
    let skel = asset.skeleton
    let clip = asset.animations[0]
    let deform = clip.deformTimelines[0]
    let base = buildDrawBatches(skel)  # setup pose, no override

    proc posedBatches(sampleTime: float64): seq[DrawBatch] =
      var dataRef = new(SkeletonData)
      dataRef[] = skel
      var state = animationState(dataRef, 1)
      state.setAnimation(0, clip)
      if sampleTime > 0.0:
        state.update(sampleTime)
      let posed = applyPose(skel, state.sample())
      buildDrawBatches(posed, computeWorldTransforms(posed))

    # (a) full mixer -> buildDrawBatches path: slotA mesh is offset by the
    # sampled deltas; assert the batch delta equals the direct sample.
    let atZero = posedBatches(0.0)
    let sampled0 = sampleDeformDeltas(deform, 0.0)
    var applyMatches = atZero[0].vertices.len == 3 and base[0].vertices.len == 3
    for i in 0 ..< 3:
      if not closeTo(atZero[0].vertices[i].x - base[0].vertices[i].x, sampled0[i].x) or
         not closeTo(atZero[0].vertices[i].y - base[0].vertices[i].y, sampled0[i].y):
        applyMatches = false

    # (c) the slotA override does not leak onto slotB's mesh batch.
    var noLeak = atZero[1].vertices.len == base[1].vertices.len
    for i in 0 ..< base[1].vertices.len:
      if not closeTo(atZero[1].vertices[i].x, base[1].vertices[i].x) or
         not closeTo(atZero[1].vertices[i].y, base[1].vertices[i].y):
        noLeak = false

    # (a) direct interpolation at the midpoint and endpoint.
    let half = sampleDeformDeltas(deform, 0.5)
    let finalDeltas = sampleDeformDeltas(deform, 1.0)

    # (a) drive the SAME interpolation through the full mixer -> buildDrawBatches
    # path at the midpoint and endpoint too, so the draw-path offset is exercised
    # at three distinct times (t=0.0/0.5/1.0), not only t=0: the batch's per-vertex
    # delta from base must equal the directly-sampled delta at each time.
    let atHalf = posedBatches(0.5)
    let atFinal = posedBatches(1.0)
    var drawPathInterpMatches =
      atHalf[0].vertices.len == 3 and atFinal[0].vertices.len == 3
    for i in 0 ..< 3:
      if not closeTo(atHalf[0].vertices[i].x - base[0].vertices[i].x, half[i].x) or
         not closeTo(atHalf[0].vertices[i].y - base[0].vertices[i].y, half[i].y) or
         not closeTo(atFinal[0].vertices[i].x - base[0].vertices[i].x, finalDeltas[i].x) or
         not closeTo(atFinal[0].vertices[i].y - base[0].vertices[i].y, finalDeltas[i].y):
        drawPathInterpMatches = false

    # (b) a stepped-curve deform key holds until the next key.
    let meshA = skel.meshAttachments[0]
    let stepped = deformTimeline("default", "slotA", meshA,
      @[deformKeyframe(0.0, 0'u32, @[meshDelta(2.0, 0.0), meshDelta(0.0, 0.0), meshDelta(0.0, 0.0)], steppedCurve),
        deformKeyframe(1.0, 0'u32, @[meshDelta(9.0, 0.0), meshDelta(0.0, 0.0), meshDelta(0.0, 0.0)])])
    let steppedMid = sampleDeformDeltas(stepped, 0.5)

    # (d) a deform-free clip leaves the mesh batches byte-identical to base.
    let plain = animationClip(skel, "plain",
      boneTimelines = @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0)])])
    var plainRef = new(SkeletonData)
    plainRef[] = skel
    var plainState = animationState(plainRef, 1)
    plainState.setAnimation(0, plain)
    let plainPosed = applyPose(skel, plainState.sample())
    let plainBatches = buildDrawBatches(plainPosed, computeWorldTransforms(plainPosed))
    var noDeformIdentical = plainPosed.deformOverrides.len == 0 and plainBatches.len == base.len
    for b in 0 ..< base.len:
      for i in 0 ..< base[b].vertices.len:
        if not closeTo(plainBatches[b].vertices[i].x, base[b].vertices[i].x) or
           not closeTo(plainBatches[b].vertices[i].y, base[b].vertices[i].y):
          noDeformIdentical = false

    then:
      applyMatches
      drawPathInterpMatches
      noLeak
      closeTo(half[0].x, 2.0)
      closeTo(half[1].y, 3.0)
      closeTo(half[2].x, -2.0)
      closeTo(finalDeltas[0].x, 3.0)
      closeTo(finalDeltas[1].y, 4.0)
      closeTo(finalDeltas[2].x, -3.0)
      # stepped holds the current key across the interval.
      closeTo(steppedMid[0].x, 2.0)
      noDeformIdentical

  it "buildDrawBatches leaves geometry undeformed; deformDrawBatches applies it":
    let data = rotationRig()
    let base = buildDrawBatches(data)
    let deformed = deformDrawBatches(data, base)
    # Base quad corners are the plain region positions (±1) — pinning that
    # buildDrawBatches did NOT apply the deformer (a double-apply regression would
    # move these).
    var baseIsPlainQuad = true
    let want = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)]
    for i in 0 ..< base[0].vertices.len:
      if not closeWithin(base[0].vertices[i].x, want[i][0], 1e-6) or
         not closeWithin(base[0].vertices[i].y, want[i][1], 1e-6):
        baseIsPlainQuad = false
    # The 90° rotation moves at least one vertex once the deform stage runs.
    var moved = false
    for i in 0 ..< base[0].vertices.len:
      if not closeWithin(base[0].vertices[i].x, deformed[0].vertices[i].x, 1e-6) or
         not closeWithin(base[0].vertices[i].y, deformed[0].vertices[i].y, 1e-6):
        moved = true
    then:
      base.len == 1
      deformed.len == 1
      baseIsPlainQuad
      deformed[0].vertices.len == base[0].vertices.len
      # u/v/color are preserved by the deform stage.
      closeWithin(deformed[0].vertices[0].u, base[0].vertices[0].u, 1e-9)
      closeWithin(deformed[0].vertices[0].r, base[0].vertices[0].r, 1e-9)
      moved

  it "effectiveDeformers samples a keyform-blended warp's control points":
    # Pins the warp + keyform-blend branch of effectiveDeformers: the resolved
    # warp's control points come from sampleKeyformPoints at the given samples,
    # not the record's raw controlPoints.
    let angle = ParameterAxis(name: "AngleX", minValue: -30.0, maxValue: 30.0, defaultValue: 0.0)
    let blend = keyformBlend(
      @[angle],
      @[
        keyform(@[parameterSample(angle, -30.0)], @[-5.0, -5.0, 5.0, -5.0, -5.0, 5.0, 5.0, 5.0]),
        keyform(@[parameterSample(angle, 30.0)], @[-1.0, -1.0, 1.0, -1.0, -1.0, 1.0, 1.0, 1.0]),
      ],
    )
    let data = skeletonData(
      skeletonHeader("keyform-warp", "0.1.0"),
      @[boneData("root", "")],
      parameters = @[angle],
      deformers = @[
        DeformerRecord(
          deformer: warpDeformer("warp",
            warpLattice(2'u32, 2'u32, -5.0, -5.0, 5.0, 5.0, @[
              DeformerPoint(x: -5.0, y: -5.0), DeformerPoint(x: 5.0, y: -5.0),
              DeformerPoint(x: -5.0, y: 5.0), DeformerPoint(x: 5.0, y: 5.0),
            ])),
          keyformBlend: blend,
        ),
      ],
    )
    let samples = defaultParameterSamples(data)
    let ef = effectiveDeformers(data, samples)
    let expected = sampleKeyformPoints(blend, samples)
    var matches = ef.len == 1 and ef[0].warp.controlPoints.len == expected.len
    if matches:
      for i in 0 ..< expected.len:
        if not closeWithin(ef[0].warp.controlPoints[i].x, expected[i].x, 1e-9) or
           not closeWithin(ef[0].warp.controlPoints[i].y, expected[i].y, 1e-9):
          matches = false
    then:
      ef.len == 1
      ef[0].kind == warpDeformerKind
      matches
      # At AngleX default 0 the blend midpoint differs from BOTH keyform extremes,
      # proving a genuine sample (not a raw-controlPoints passthrough).
      not closeWithin(ef[0].warp.controlPoints[0].x, -5.0, 1e-6)
      not closeWithin(ef[0].warp.controlPoints[0].x, -1.0, 1e-6)

  it "deformDrawBatches equals effectiveDeformers + applyDeformersToDrawBatches":
    let data = rotationRig()
    let base = buildDrawBatches(data)
    let samples = defaultParameterSamples(data)
    let composed = applyDeformersToDrawBatches(base, effectiveDeformers(data, samples))
    let oneCall = deformDrawBatches(data, base, samples)
    # And both match applying the deformer primitive directly to the batch verts.
    var skinned: seq[SkinnedMeshVertex]
    for v in base[0].vertices:
      skinned.add SkinnedMeshVertex(x: v.x, y: v.y, u: v.u, v: v.v)
    let direct = applyDeformers(skinned, effectiveDeformers(data, samples))
    var matchesDirect = true
    for i in 0 ..< direct.len:
      if not closeWithin(composed[0].vertices[i].x, direct[i].x, 1e-9) or
         not closeWithin(composed[0].vertices[i].y, direct[i].y, 1e-9):
        matchesDirect = false
    then:
      composed.len == oneCall.len
      closeWithin(composed[0].vertices[0].x, oneCall[0].vertices[0].x, 1e-9)
      closeWithin(composed[0].vertices[1].x, oneCall[0].vertices[1].x, 1e-9)
      closeWithin(composed[0].vertices[1].y, oneCall[0].vertices[1].y, 1e-9)
      matchesDirect

  it "applyDeformersToDrawBatches with no deformers returns batches unchanged":
    let data = rotationRig()
    let base = buildDrawBatches(data)
    let unchanged = applyDeformersToDrawBatches(base, @[])
    then:
      unchanged.len == base.len
      closeWithin(unchanged[0].vertices[0].x, base[0].vertices[0].x, 1e-12)
      closeWithin(unchanged[0].vertices[2].y, base[0].vertices[2].y, 1e-12)
