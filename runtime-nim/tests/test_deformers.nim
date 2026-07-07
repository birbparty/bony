include smoke_support

spec "deformer smoke coverage":
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

  it "loads M7 parameters from JSON":
    let data = loadBonyJson("""
      {
        "skeleton": {"name": "m7-params"},
        "bones": [{"name": "root"}],
        "parameters": [
          {"name": "AngleX", "min": -30.0, "max": 30.0},
          {"name": "EyeOpen", "min": 0.0, "max": 1.0, "default": 1.0}
        ]
      }
    """)

    then:
      data.parameters.len == 2
      data.parameters[0].name == "AngleX"
      closeTo(data.parameters[0].minValue, -30.0)
      closeTo(data.parameters[0].maxValue, 30.0)
      closeTo(data.parameters[0].defaultValue, 0.0)
      data.parameters[1].name == "EyeOpen"
      closeTo(data.parameters[1].defaultValue, 1.0)

  it "loads M7 warp deformer from JSON":
    let data = loadBonyJson("""
      {
        "skeleton": {"name": "m7-warp"},
        "bones": [{"name": "root"}],
        "deformers": [
          {
            "id": "warp_face",
            "order": 0,
            "kind": "warp",
            "warp": {
              "rows": 2,
              "cols": 2,
              "minX": -100,
              "minY": -100,
              "maxX": 100,
              "maxY": 100,
              "controlPoints": [
                {"x": -100, "y": -100},
                {"x": 100, "y": -100},
                {"x": -100, "y": 100},
                {"x": 100, "y": 100}
              ]
            }
          }
        ]
      }
    """)

    then:
      data.deformers.len == 1
      data.deformers[0].deformer.id == "warp_face"
      data.deformers[0].deformer.kind == warpDeformerKind
      data.deformers[0].deformer.warp.rows == 2'u32
      data.deformers[0].deformer.warp.cols == 2'u32
      data.deformers[0].deformer.warp.controlPoints.len == 4

  it "loads M7 rotation deformer from JSON":
    let data = loadBonyJson("""
      {
        "skeleton": {"name": "m7-rot"},
        "bones": [{"name": "root"}],
        "deformers": [
          {
            "id": "rot_head",
            "order": 0,
            "kind": "rotation",
            "rotation": {
              "pivotX": 10.0,
              "pivotY": 20.0,
              "angleDegrees": 45.0
            }
          }
        ]
      }
    """)

    then:
      data.deformers.len == 1
      data.deformers[0].deformer.id == "rot_head"
      data.deformers[0].deformer.kind == rotationDeformerKind
      closeTo(data.deformers[0].deformer.rotation.angleDegrees, 45.0)
      closeTo(data.deformers[0].deformer.rotation.scaleX, 1.0)
      closeTo(data.deformers[0].deformer.rotation.opacity, 1.0)

  it "loads M7 deformer with keyformBlend from JSON":
    let data = loadBonyJson("""
      {
        "skeleton": {"name": "m7-kf"},
        "bones": [{"name": "root"}],
        "parameters": [
          {"name": "AngleX", "min": -30.0, "max": 30.0}
        ],
        "deformers": [
          {
            "id": "warp_face",
            "order": 0,
            "kind": "warp",
            "warp": {
              "rows": 2, "cols": 2,
              "minX": -10, "minY": -10, "maxX": 10, "maxY": 10,
              "controlPoints": [
                {"x": -10, "y": -10}, {"x": 10, "y": -10},
                {"x": -10, "y": 10},  {"x": 10, "y": 10}
              ]
            },
            "keyformBlend": {
              "axes": ["AngleX"],
              "keyforms": [
                {"coordinates": {"AngleX": -30.0}, "values": [-11.0, -11.0, 11.0, -11.0, -11.0, 11.0, 11.0, 11.0]},
                {"coordinates": {"AngleX": 30.0},  "values": [-9.0, -9.0, 9.0, -9.0, -9.0, 9.0, 9.0, 9.0]}
              ]
            }
          }
        ]
      }
    """)

    then:
      data.deformers[0].keyformBlend.axes.len == 1
      data.deformers[0].keyformBlend.axes[0].name == "AngleX"
      data.deformers[0].keyformBlend.keyforms.len == 2

  it "round-trips M7 parameters through toBonyJson":
    let original = skeletonData(
      skeletonHeader("m7-rt", "0.1.0"),
      @[boneData("root", "")],
      parameters = @[
        ParameterAxis(name: "AngleX", minValue: -30.0, maxValue: 30.0, defaultValue: 0.0),
        ParameterAxis(name: "EyeOpen", minValue: 0.0, maxValue: 1.0, defaultValue: 1.0),
      ],
    )
    let loaded = loadBonyJson(toBonyJson(original))

    then:
      loaded.parameters.len == 2
      loaded.parameters[0].name == "AngleX"
      loaded.parameters[1].name == "EyeOpen"
      closeTo(loaded.parameters[1].defaultValue, 1.0)

  it "round-trips M7 deformers through toBonyJson":
    let original = skeletonData(
      skeletonHeader("m7-def-rt", "0.1.0"),
      @[boneData("root", "")],
      deformers = @[
        DeformerRecord(
          deformer: Deformer(
            id: "warp_a", parent: "", order: 0'u32,
            kind: warpDeformerKind,
            warp: WarpLattice(
              rows: 2'u32, cols: 2'u32,
              minX: -5.0, minY: -5.0, maxX: 5.0, maxY: 5.0,
              controlPoints: @[
                DeformerPoint(x: -5.0, y: -5.0),
                DeformerPoint(x: 5.0,  y: -5.0),
                DeformerPoint(x: -5.0, y: 5.0),
                DeformerPoint(x: 5.0,  y: 5.0),
              ],
            ),
          ),
          keyformBlend: KeyformBlend(),
        ),
      ],
    )
    let loaded = loadBonyJson(toBonyJson(original))

    then:
      loaded.deformers.len == 1
      loaded.deformers[0].deformer.id == "warp_a"
      loaded.deformers[0].deformer.kind == warpDeformerKind
      loaded.deformers[0].deformer.warp.controlPoints.len == 4

  it "rejects duplicate M7 parameter names":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "dup-params"},
          "bones": [{"name": "root"}],
          "parameters": [
            {"name": "X", "min": 0.0, "max": 1.0},
            {"name": "X", "min": 0.0, "max": 1.0}
          ]
        }
      """, duplicateKey)

  it "rejects duplicate M7 deformer ids":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "dup-defs"},
          "bones": [{"name": "root"}],
          "deformers": [
            {"id": "d1", "order": 0, "kind": "rotation", "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0}},
            {"id": "d1", "order": 1, "kind": "rotation", "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0}}
          ]
        }
      """, duplicateKey)

  it "rejects unknown M7 deformer parent":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "unk-parent"},
          "bones": [{"name": "root"}],
          "deformers": [
            {"id": "d1", "parent": "ghost", "order": 0, "kind": "rotation",
             "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0}}
          ]
        }
      """, unknownRequiredReference)

  it "rejects M7 deformer tree cycle":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "cycle-defs"},
          "bones": [{"name": "root"}],
          "deformers": [
            {"id": "a", "parent": "b", "order": 0, "kind": "rotation",
             "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0}},
            {"id": "b", "parent": "a", "order": 1, "kind": "rotation",
             "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0}}
          ]
        }
      """, cycleDetected)

  it "rejects M7 keyformBlend with unknown parameter axis":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "unk-axis"},
          "bones": [{"name": "root"}],
          "deformers": [
            {
              "id": "d1", "order": 0, "kind": "rotation",
              "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0},
              "keyformBlend": {
                "axes": ["Ghost"],
                "keyforms": [{"coordinates": {"Ghost": 0.0}, "values": [0.0]}]
              }
            }
          ]
        }
      """, unknownRequiredReference)

  it "rejects M7 warp deformer with wrong control-point count":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-warp-count"},
          "bones": [{"name": "root"}],
          "deformers": [
            {
              "id": "w1", "order": 0, "kind": "warp",
              "warp": {
                "rows": 2, "cols": 2,
                "minX": -10, "minY": -10, "maxX": 10, "maxY": 10,
                "controlPoints": [{"x": 0, "y": 0}, {"x": 1, "y": 0}, {"x": 0, "y": 1}]
              }
            }
          ]
        }
      """, schemaViolation)

  it "rejects M7 warp deformer with degenerate bounds":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "degen-warp"},
          "bones": [{"name": "root"}],
          "deformers": [
            {
              "id": "w1", "order": 0, "kind": "warp",
              "warp": {
                "rows": 2, "cols": 2,
                "minX": 0, "minY": -10, "maxX": 0, "maxY": 10,
                "controlPoints": [
                  {"x": 0, "y": -10}, {"x": 0, "y": -10},
                  {"x": 0, "y": 10},  {"x": 0, "y": 10}
                ]
              }
            }
          ]
        }
      """, schemaViolation)

  it "rejects M7 rotation deformer with zero scaleX":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-scale"},
          "bones": [{"name": "root"}],
          "deformers": [
            {
              "id": "r1", "order": 0, "kind": "rotation",
              "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0, "scaleX": 0}
            }
          ]
        }
      """, schemaViolation)

  it "rejects M7 rotation deformer with opacity out of range":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-opacity"},
          "bones": [{"name": "root"}],
          "deformers": [
            {
              "id": "r1", "order": 0, "kind": "rotation",
              "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0, "opacity": 2.0}
            }
          ]
        }
      """, schemaViolation)

  it "rejects M7 deformer with parent order not earlier than child order":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-order"},
          "bones": [{"name": "root"}],
          "deformers": [
            {"id": "child", "parent": "parent", "order": 0, "kind": "rotation",
             "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0}},
            {"id": "parent", "parent": "", "order": 1, "kind": "rotation",
             "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0}}
          ]
        }
      """, orderingViolation)

  it "rejects M7 keyformBlend with mismatched value counts":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "bad-kf-count"},
          "bones": [{"name": "root"}],
          "parameters": [{"name": "X", "min": 0.0, "max": 1.0}],
          "deformers": [
            {
              "id": "d1", "order": 0, "kind": "rotation",
              "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0},
              "keyformBlend": {
                "axes": ["X"],
                "keyforms": [
                  {"coordinates": {"X": 0.0}, "values": [0.0, 1.0]},
                  {"coordinates": {"X": 1.0}, "values": [0.0]}
                ]
              }
            }
          ]
        }
      """, schemaViolation)

  it "rejects M7 keyformBlend with empty axes":
    then:
      raisesBonyLoadError("""
        {
          "skeleton": {"name": "empty-axes"},
          "bones": [{"name": "root"}],
          "deformers": [
            {
              "id": "d1", "order": 0, "kind": "rotation",
              "rotation": {"pivotX": 0, "pivotY": 0, "angleDegrees": 0},
              "keyformBlend": {
                "axes": [],
                "keyforms": [{"coordinates": {}, "values": [0.0]}]
              }
            }
          ]
        }
      """, schemaViolation)

  it "round-trips M7 parameters through BNB":
    let original = skeletonData(
      skeletonHeader("m7-bnb-params", "0.1.0"),
      @[boneData("root", "")],
      parameters = @[
        ParameterAxis(name: "AngleX", minValue: -30.0, maxValue: 30.0, defaultValue: 0.0),
        ParameterAxis(name: "EyeOpen", minValue: 0.0, maxValue: 1.0, defaultValue: 1.0),
      ],
    )
    let decoded = loadBonyBnb(toBonyBnb(original))

    then:
      decoded.parameters.len == 2
      decoded.parameters[0].name == "AngleX"
      closeTo(decoded.parameters[0].minValue, -30.0)
      closeTo(decoded.parameters[0].maxValue, 30.0)
      closeTo(decoded.parameters[0].defaultValue, 0.0)
      decoded.parameters[1].name == "EyeOpen"
      closeTo(decoded.parameters[1].defaultValue, 1.0)
      toBonyJson(decoded) == toBonyJson(original)
      toBonyBnb(decoded) == toBonyBnb(original)

  it "round-trips M7 warp deformer through BNB":
    let original = skeletonData(
      skeletonHeader("m7-bnb-warp", "0.1.0"),
      @[boneData("root", "")],
      deformers = @[
        DeformerRecord(
          deformer: Deformer(
            id: "warp_face", parent: "", order: 1'u32,
            kind: warpDeformerKind,
            warp: WarpLattice(
              rows: 2'u32, cols: 2'u32,
              minX: -50.0, minY: -50.0, maxX: 50.0, maxY: 50.0,
              controlPoints: @[
                DeformerPoint(x: -50.0, y: -50.0),
                DeformerPoint(x:  50.0, y: -50.0),
                DeformerPoint(x: -50.0, y:  50.0),
                DeformerPoint(x:  50.0, y:  50.0),
              ],
            ),
          ),
          keyformBlend: KeyformBlend(),
        ),
      ],
    )
    let decoded = loadBonyBnb(toBonyBnb(original))

    then:
      decoded.deformers.len == 1
      decoded.deformers[0].deformer.id == "warp_face"
      decoded.deformers[0].deformer.kind == warpDeformerKind
      decoded.deformers[0].deformer.order == 1'u32
      decoded.deformers[0].deformer.warp.rows == 2'u32
      decoded.deformers[0].deformer.warp.cols == 2'u32
      closeTo(decoded.deformers[0].deformer.warp.minX, -50.0)
      closeTo(decoded.deformers[0].deformer.warp.maxX, 50.0)
      decoded.deformers[0].deformer.warp.controlPoints.len == 4
      closeTo(decoded.deformers[0].deformer.warp.controlPoints[0].x, -50.0)
      toBonyJson(decoded) == toBonyJson(original)
      toBonyBnb(decoded) == toBonyBnb(original)

  it "round-trips M7 rotation deformer through BNB":
    let original = skeletonData(
      skeletonHeader("m7-bnb-rot", "0.1.0"),
      @[boneData("root", "")],
      deformers = @[
        DeformerRecord(
          deformer: Deformer(
            id: "rot_head", parent: "", order: 0'u32,
            kind: rotationDeformerKind,
            rotation: RotationDeformer(
              pivotX: 10.0, pivotY: 20.0, angleDegrees: 45.0,
              scaleX: 1.0, scaleY: 1.0, opacity: 0.75,
            ),
          ),
          keyformBlend: KeyformBlend(),
        ),
      ],
    )
    let decoded = loadBonyBnb(toBonyBnb(original))

    then:
      decoded.deformers.len == 1
      decoded.deformers[0].deformer.id == "rot_head"
      decoded.deformers[0].deformer.kind == rotationDeformerKind
      closeTo(decoded.deformers[0].deformer.rotation.pivotX, 10.0)
      closeTo(decoded.deformers[0].deformer.rotation.pivotY, 20.0)
      closeTo(decoded.deformers[0].deformer.rotation.angleDegrees, 45.0)
      closeTo(decoded.deformers[0].deformer.rotation.scaleX, 1.0)
      closeTo(decoded.deformers[0].deformer.rotation.opacity, 0.75)
      toBonyJson(decoded) == toBonyJson(original)
      toBonyBnb(decoded) == toBonyBnb(original)

  it "round-trips M7 deformer with keyformBlend through BNB":
    let axisAngleX = ParameterAxis(name: "AngleX", minValue: -30.0, maxValue: 30.0, defaultValue: 0.0)
    let original = skeletonData(
      skeletonHeader("m7-bnb-kf", "0.1.0"),
      @[boneData("root", "")],
      parameters = @[axisAngleX],
      deformers = @[
        DeformerRecord(
          deformer: Deformer(
            id: "warp_body", parent: "", order: 0'u32,
            kind: warpDeformerKind,
            warp: WarpLattice(
              rows: 2'u32, cols: 2'u32,
              minX: -10.0, minY: -10.0, maxX: 10.0, maxY: 10.0,
              controlPoints: @[
                DeformerPoint(x: -10.0, y: -10.0),
                DeformerPoint(x:  10.0, y: -10.0),
                DeformerPoint(x: -10.0, y:  10.0),
                DeformerPoint(x:  10.0, y:  10.0),
              ],
            ),
          ),
          keyformBlend: keyformBlend(
            @[axisAngleX],
            @[
              Keyform(
                coordinates: @[ParameterSample(name: "AngleX", value: -30.0)],
                values: @[-11.0, -11.0, 11.0, -11.0, -11.0, 11.0, 11.0, 11.0],
              ),
              Keyform(
                coordinates: @[ParameterSample(name: "AngleX", value: 30.0)],
                values: @[-9.0, -9.0, 9.0, -9.0, -9.0, 9.0, 9.0, 9.0],
              ),
            ],
          ),
        ),
      ],
    )
    let decoded = loadBonyBnb(toBonyBnb(original))

    then:
      decoded.parameters.len == 1
      decoded.parameters[0].name == "AngleX"
      decoded.deformers.len == 1
      decoded.deformers[0].deformer.id == "warp_body"
      decoded.deformers[0].keyformBlend.axes.len == 1
      decoded.deformers[0].keyformBlend.axes[0].name == "AngleX"
      decoded.deformers[0].keyformBlend.keyforms.len == 2
      closeTo(decoded.deformers[0].keyformBlend.keyforms[0].coordinates[0].value, -30.0)
      decoded.deformers[0].keyformBlend.keyforms[0].values.len == 8
      closeTo(decoded.deformers[0].keyformBlend.keyforms[0].values[0], -11.0)
      closeTo(decoded.deformers[0].keyformBlend.keyforms[1].coordinates[0].value, 30.0)
      toBonyJson(decoded) == toBonyJson(original)
      toBonyBnb(decoded) == toBonyBnb(original)

  it "rejects M7 BNB deformer header with no geometry record":
    proc buildOrphanDeformer(kind: string): seq[byte] =
      var table = initStringTable()
      var nameP, rootP, idP, kindP: seq[byte]
      nameP.writeStringPayload(table, "demo")
      rootP.writeStringPayload(table, "root")
      idP.writeStringPayload(table, "d1")
      kindP.writeStringPayload(table, kind)
      result.writeHeader(flags = bnbStringTableFlag)
      result.writeToc(@[
        BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
        BnbTocEntry(propertyKey: 6010, backingTypeCode: backingTypeCode("string")),
        BnbTocEntry(propertyKey: 6012, backingTypeCode: backingTypeCode("string")),
      ])
      result.writeStringTable(table)
      result.writeObjectRecord(1, @[BnbPropertyRecord(propertyKey: 1, payload: nameP)])
      result.writeObjectRecord(2, @[BnbPropertyRecord(propertyKey: 1, payload: rootP)])
      result.writeObjectRecord(6001, @[
        BnbPropertyRecord(propertyKey: 6010, payload: idP),
        BnbPropertyRecord(propertyKey: 6012, payload: kindP),
      ])
      result.writeObjectStreamTerminator()
    then:
      raisesBonyLoadError(proc() =
        discard loadBonyBnb(buildOrphanDeformer("warp"))
      , schemaViolation)
      raisesBonyLoadError(proc() =
        discard loadBonyBnb(buildOrphanDeformer("rotation"))
      , schemaViolation)

  it "rejects M7 BNB two consecutive deformer headers":
    proc buildDoubleDeformerHeader(): seq[byte] =
      var table = initStringTable()
      var nameP, rootP, id1P, id2P, kindP: seq[byte]
      nameP.writeStringPayload(table, "demo")
      rootP.writeStringPayload(table, "root")
      id1P.writeStringPayload(table, "d1")
      id2P.writeStringPayload(table, "d2")
      kindP.writeStringPayload(table, "warp")
      result.writeHeader(flags = bnbStringTableFlag)
      result.writeToc(@[
        BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
        BnbTocEntry(propertyKey: 6010, backingTypeCode: backingTypeCode("string")),
        BnbTocEntry(propertyKey: 6012, backingTypeCode: backingTypeCode("string")),
      ])
      result.writeStringTable(table)
      result.writeObjectRecord(1, @[BnbPropertyRecord(propertyKey: 1, payload: nameP)])
      result.writeObjectRecord(2, @[BnbPropertyRecord(propertyKey: 1, payload: rootP)])
      result.writeObjectRecord(6001, @[
        BnbPropertyRecord(propertyKey: 6010, payload: id1P),
        BnbPropertyRecord(propertyKey: 6012, payload: kindP),
      ])
      result.writeObjectRecord(6001, @[
        BnbPropertyRecord(propertyKey: 6010, payload: id2P),
        BnbPropertyRecord(propertyKey: 6012, payload: kindP),
      ])
      result.writeObjectStreamTerminator()
    then:
      raisesBonyLoadError(proc() =
        discard loadBonyBnb(buildDoubleDeformerHeader())
      , schemaViolation)
