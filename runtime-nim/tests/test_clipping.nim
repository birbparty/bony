include smoke_support

spec "clipping smoke coverage":
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

  it "round trips a clipping attachment through JSON and .bnb":
    let jsonText = """
{
  "skeleton": {"name": "clipdemo", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [
    {"name": "slotA", "bone": "root", "attachment": "mask"},
    {"name": "slotB", "bone": "root"},
    {"name": "slotC", "bone": "root"}
  ],
  "clippingAttachments": [
    {"name": "mask", "vertices": [0, 0, 2, 0, 2, 2, 0, 2], "untilSlot": "slotC"}
  ]
}
"""
    let fromJson = loadBonyJson(jsonText)
    let bnbBytes = toBonyBnb(fromJson)
    let fromBnb = loadBonyBnb(bnbBytes)

    then:
      # A slot whose attachment names a clip is accepted (no load error above).
      fromJson.clippingAttachments.len == 1
      fromJson.clippingAttachments[0].name == "mask"
      fromJson.clippingAttachments[0].vertices == @[0.0, 0.0, 2.0, 0.0, 2.0, 2.0, 0.0, 2.0]
      fromJson.clippingAttachments[0].untilSlot == "slotC"
      # JSON and binary loaders agree on the parsed record.
      fromBnb.clippingAttachments.len == 1
      fromBnb.clippingAttachments[0].name == fromJson.clippingAttachments[0].name
      fromBnb.clippingAttachments[0].vertices == fromJson.clippingAttachments[0].vertices
      fromBnb.clippingAttachments[0].untilSlot == fromJson.clippingAttachments[0].untilSlot
      # JSON canonical output round-trips and .bnb bytes are stable.
      toBonyJson(loadBonyJson(toBonyJson(fromJson))) == toBonyJson(fromJson)
      toBonyBnb(loadBonyJson(toBonyJson(fromBnb))) == bnbBytes

  it "accepts a clipping attachment with no untilSlot (clips to end of draw order)":
    let jsonText = """
{
  "skeleton": {"name": "clipdemo", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [
    {"name": "slotA", "bone": "root", "attachment": "mask"},
    {"name": "slotB", "bone": "root"}
  ],
  "clippingAttachments": [
    {"name": "mask", "vertices": [0, 0, 2, 0, 2, 2]}
  ]
}
"""
    let data = loadBonyJson(jsonText)
    then:
      data.clippingAttachments[0].untilSlot == ""
      data.clippingAttachments[0].vertices.len == 6

  it "rejects a non-convex clipping polygon":
    then:
      raisesBonyLoadError("""
{
  "skeleton": {"name": "d", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "s", "bone": "root", "attachment": "mask"}],
  "clippingAttachments": [{"name": "mask", "vertices": [0, 0, 2, 0, 0.5, 0.5, 0, 2]}]
}
""", schemaViolation)

  it "rejects a clipping polygon with fewer than three vertices":
    then:
      raisesBonyLoadError("""
{
  "skeleton": {"name": "d", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [{"name": "s", "bone": "root", "attachment": "mask"}],
  "clippingAttachments": [{"name": "mask", "vertices": [0, 0, 1, 1]}]
}
""", schemaViolation)

  it "rejects a clipping attachment whose untilSlot names an unknown slot":
    then:
      raisesBonyLoadError("""
{
  "skeleton": {"name": "d", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [
    {"name": "slotA", "bone": "root", "attachment": "mask"},
    {"name": "slotB", "bone": "root"}
  ],
  "clippingAttachments": [{"name": "mask", "vertices": [0, 0, 2, 0, 2, 2], "untilSlot": "nope"}]
}
""", unknownRequiredReference)

  it "rejects an untilSlot at or before the clip's own slot":
    then:
      raisesBonyLoadError("""
{
  "skeleton": {"name": "d", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [
    {"name": "slotA", "bone": "root"},
    {"name": "slotB", "bone": "root", "attachment": "mask"}
  ],
  "clippingAttachments": [{"name": "mask", "vertices": [0, 0, 2, 0, 2, 2], "untilSlot": "slotA"}]
}
""", schemaViolation)

  it "rejects a clipping attachment whose own slot is the last slot":
    then:
      raisesBonyLoadError("""
{
  "skeleton": {"name": "d", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [
    {"name": "slotA", "bone": "root"},
    {"name": "slotB", "bone": "root", "attachment": "mask"}
  ],
  "clippingAttachments": [{"name": "mask", "vertices": [0, 0, 2, 0, 2, 2]}]
}
""", schemaViolation)

  it "rejects overlapping clipping ranges":
    then:
      raisesBonyLoadError("""
{
  "skeleton": {"name": "d", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "slots": [
    {"name": "slotA", "bone": "root", "attachment": "m1"},
    {"name": "slotB", "bone": "root", "attachment": "m2"},
    {"name": "slotC", "bone": "root"},
    {"name": "slotD", "bone": "root"}
  ],
  "clippingAttachments": [
    {"name": "m1", "vertices": [0, 0, 2, 0, 2, 2], "untilSlot": "slotC"},
    {"name": "m2", "vertices": [0, 0, 2, 0, 2, 2], "untilSlot": "slotD"}
  ]
}
""", schemaViolation)

  it "rejects a clipping attachment name that collides with a region name":
    then:
      raisesBonyLoadError("""
{
  "skeleton": {"name": "d", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "regions": [{"name": "shared", "width": 2, "height": 2}],
  "slots": [
    {"name": "slotA", "bone": "root", "attachment": "shared"},
    {"name": "slotB", "bone": "root"}
  ],
  "clippingAttachments": [{"name": "shared", "vertices": [0, 0, 2, 0, 2, 2], "untilSlot": "slotB"}]
}
""", duplicateKey)

  it "sets clipId over the covered range and leaves other batches unclipped":
    # Clip covers x in [0,3]; range covers coveredSlot only (untilSlot=coveredSlot).
    let batches = buildDrawBatches(loadBonyJson(clipEvalRig("0, -3, 3, -3, 3, 3, 0, 3", "coveredSlot")))
    let covered = batches.batchFor("coveredSlot")
    let after = batches.batchFor("afterSlot")
    then:
      # clipSlot (a clip attachment) produces no draw batch.
      batches.len == 2
      covered.clipId == "mask"
      after.clipId == ""

  it "partially clips a covered batch and interpolates u at the clip edge":
    let batches = buildDrawBatches(loadBonyJson(clipEvalRig("0, -3, 3, -3, 3, 3, 0, 3", "coveredSlot")))
    let covered = batches.batchFor("coveredSlot")
    var minX = 1e9
    var edgeU = -1.0
    for v in covered.vertices:
      if v.x < minX: minX = v.x
      if closeTo(v.x, 0.0):
        edgeU = v.u
    then:
      # Left half (x < 0) removed; the new edge sits at x = 0 with u interpolated to 0.5.
      covered.vertices.len >= 3
      closeWithin(minX, 0.0, 1e-6)
      closeWithin(edgeU, 0.5, 1e-6)

  it "leaves a fully-inside covered batch unchanged except clipId":
    let batches = buildDrawBatches(loadBonyJson(clipEvalRig("-5, -5, 5, -5, 5, 5, -5, 5", "coveredSlot")))
    let covered = batches.batchFor("coveredSlot")
    var hasLeftCorner = false
    for v in covered.vertices:
      if closeTo(v.x, -1.0) and closeTo(v.y, -1.0): hasLeftCorner = true
    then:
      covered.clipId == "mask"
      covered.vertices.len == 4
      covered.indices == @[0'u16, 1'u16, 2'u16, 2'u16, 3'u16, 0'u16]
      hasLeftCorner

  it "empties a fully-outside covered batch but keeps its clipId and metadata":
    let batches = buildDrawBatches(loadBonyJson(clipEvalRig("10, 10, 12, 10, 12, 12, 10, 12", "coveredSlot")))
    let covered = batches.batchFor("coveredSlot")
    then:
      covered.clipId == "mask"
      covered.vertices.len == 0
      covered.indices.len == 0
      covered.slot == "coveredSlot"
      covered.bone == "root"

  it "clips to the end of draw order when untilSlot is empty":
    # Empty untilSlot => range covers every batch after the clip's own slot.
    let batches = buildDrawBatches(loadBonyJson(clipEvalRig("0, -3, 3, -3, 3, 3, 0, 3", "")))
    let covered = batches.batchFor("coveredSlot")
    let after = batches.batchFor("afterSlot")
    then:
      covered.clipId == "mask"
      after.clipId == "mask"

  it "does not touch a batch past untilSlot":
    let batches = buildDrawBatches(loadBonyJson(clipEvalRig("0, -3, 3, -3, 3, 3, 0, 3", "coveredSlot")))
    let after = batches.batchFor("afterSlot")
    var hasLeftCorner = false
    for v in after.vertices:
      if closeTo(v.x, -1.0): hasLeftCorner = true
    then:
      after.clipId == ""
      after.vertices.len == 4
      hasLeftCorner

  it "produces byte-identical clip output from the .bony and .bnb load paths":
    let text = clipEvalRig("0, -3, 3, -3, 3, 3, 0, 3", "coveredSlot")
    let fromJson = buildDrawBatches(loadBonyJson(text))
    let fromBnb = buildDrawBatches(loadBonyBnb(toBonyBnb(loadBonyJson(text))))
    let a = fromJson.batchFor("coveredSlot")
    let b = fromBnb.batchFor("coveredSlot")
    then:
      a.vertices == b.vertices
      a.indices == b.indices
      a.clipId == b.clipId

  it "interpolates r/g/b/a at a clip-edge intersection (direct DrawBatch clip)":
    # A quad with a distinct color per corner, clipped to the right half (x >= 0).
    let subject = @[
      DrawVertex(x: -1.0, y: -1.0, u: 0.0, v: 0.0, r: 1.0, g: 0.0, b: 0.0, a: 1.0),
      DrawVertex(x: 1.0, y: -1.0, u: 1.0, v: 0.0, r: 0.0, g: 1.0, b: 0.0, a: 1.0),
      DrawVertex(x: 1.0, y: 1.0, u: 1.0, v: 1.0, r: 0.0, g: 0.0, b: 1.0, a: 1.0),
      DrawVertex(x: -1.0, y: 1.0, u: 0.0, v: 1.0, r: 1.0, g: 1.0, b: 0.0, a: 1.0),
    ]
    # Clip to x >= 0.5 so the bottom-edge intersection sits at t = 0.75 along
    # red(BL)->green(BR), NOT the midpoint — this pins interpolation *direction*
    # (a t <-> 1-t swap would fail here).
    let clip = @[clipPoint(0.5, -3.0), clipPoint(3.0, -3.0), clipPoint(3.0, 3.0), clipPoint(0.5, 3.0)]
    let clipped = clipDrawBatchPolygon(subject, clip)
    # Bottom-edge intersection at (0.5,-1): t=0.75 => u=0.75, r=0.25, g=0.75, b=0.
    var bottom = DrawVertex(r: -1.0)
    for v in clipped.vertices:
      if closeTo(v.x, 0.5) and closeTo(v.y, -1.0): bottom = v
    then:
      clipped.changed
      clipped.vertices.len >= 3
      closeWithin(bottom.r, 0.25, 1e-6)
      closeWithin(bottom.g, 0.75, 1e-6)
      closeWithin(bottom.b, 0.0, 1e-6)
      closeWithin(bottom.u, 0.75, 1e-6)

  it "clips a triangle soup per-triangle, preserving a shared interior vertex":
    # A 4-triangle diamond fan sharing interior center vertex 0. The vertex list
    # (center, then the four rim points) is NOT a convex boundary ring, so
    # clipDrawBatchPolygon would mis-triangulate it. clipDrawBatchTriangles clips
    # each triangle independently: with clip x <= 20, the two triangles touching
    # the right rim vertex (50,0) are cut while the two left triangles pass
    # through unchanged.
    let subject = @[
      DrawVertex(x: 0.0, y: 0.0, u: 0.5, v: 0.5, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      DrawVertex(x: 50.0, y: 0.0, u: 1.0, v: 0.5, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      DrawVertex(x: 0.0, y: 50.0, u: 0.5, v: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      DrawVertex(x: -50.0, y: 0.0, u: 0.0, v: 0.5, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      DrawVertex(x: 0.0, y: -50.0, u: 0.5, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
    ]
    let indices = @[0'u16, 1, 2, 0, 2, 3, 0, 3, 4, 0, 4, 1]
    # Clip x <= 20 (a rectangle spanning that half-plane over the diamond).
    let clip = @[
      clipPoint(-100.0, -100.0), clipPoint(20.0, -100.0),
      clipPoint(20.0, 100.0), clipPoint(-100.0, 100.0),
    ]
    let clipped = clipDrawBatchTriangles(subject, indices, clip)
    # No output vertex sits right of the x = 20 cut; a cut vertex lands at (20,0).
    var maxX = -1e9
    var hasCutAtRim = false
    for v in clipped.vertices:
      maxX = max(maxX, v.x)
      if closeWithin(v.x, 20.0, 1e-5) and closeWithin(v.y, 0.0, 1e-5):
        hasCutAtRim = true
    # The rim vertex (50,0) that a convex-ring fan would keep is gone.
    var keptRightRim = false
    for v in clipped.vertices:
      if closeWithin(v.x, 50.0, 1e-5): keptRightRim = true

    then:
      clipped.changed
      maxX <= 20.0 + 1e-5
      hasCutAtRim
      not keptRightRim
      # indices are a multiple of 3 (well-formed triangle list) and non-empty.
      clipped.indices.len > 0
      clipped.indices.len mod 3 == 0

  it "keeps a fully-inside triangle soup unchanged (changed == false)":
    # Every referenced vertex inside the clip => no triangle is cut, so the caller
    # keeps its original vertices/indices.
    let subject = @[
      DrawVertex(x: 0.0, y: 0.0, u: 0.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      DrawVertex(x: 1.0, y: 0.0, u: 1.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      DrawVertex(x: 0.0, y: 1.0, u: 0.0, v: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
    ]
    let indices = @[0'u16, 1, 2]
    let clip = @[
      clipPoint(-10.0, -10.0), clipPoint(10.0, -10.0),
      clipPoint(10.0, 10.0), clipPoint(-10.0, 10.0),
    ]
    let clipped = clipDrawBatchTriangles(subject, indices, clip)

    then:
      not clipped.changed
      clipped.vertices.len == 0
      clipped.indices.len == 0

  it "empties a fully-outside triangle soup but reports changed":
    # Every triangle entirely outside the clip => changed == true with empty
    # geometry (mirrors the region fully-outside path).
    let subject = @[
      DrawVertex(x: 10.0, y: 10.0, u: 0.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      DrawVertex(x: 12.0, y: 10.0, u: 1.0, v: 0.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
      DrawVertex(x: 12.0, y: 12.0, u: 1.0, v: 1.0, r: 1.0, g: 1.0, b: 1.0, a: 1.0),
    ]
    let indices = @[0'u16, 1, 2]
    # Clip well to the left of the triangle (x <= 0).
    let clip = @[
      clipPoint(-10.0, -10.0), clipPoint(0.0, -10.0),
      clipPoint(0.0, 10.0), clipPoint(-10.0, 10.0),
    ]
    let clipped = clipDrawBatchTriangles(subject, indices, clip)

    then:
      clipped.changed
      clipped.vertices.len == 0
      clipped.indices.len == 0
