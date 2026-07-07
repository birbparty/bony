include smoke_support

spec "path constraint smoke coverage":
  it "loads, validates, orders, and round trips path constraints":
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
      "name": "target"
    }
  ],
  "regions": [
    {
      "name": "visual",
      "width": 1,
      "height": 1
    }
  ],
  "pathAttachments": [
    {
      "name": "curve",
      "p0x": 0,
      "p0y": 0,
      "p1x": 1.00000001,
      "p1y": 2,
      "p2x": 3,
      "p2y": 4,
      "p3x": 5,
      "p3y": 6
    }
  ],
  "paths": [
    {
      "name": "follow",
      "bone": "root",
      "target": "target",
      "path": "curve",
      "order": 7
    }
  ]
}
""")
    let decoded = loadBonyBnb(toBonyBnb(data))
    let ordered = canonicalConstraintOrder(@[
      constraintOrderEntry(ckPath, 3, 0),
      constraintOrderEntry(ckTransform, 3, 0),
      constraintOrderEntry(ckIk, 3, 0),
      constraintOrderEntry(ckPhysics, 1, 0),
      constraintOrderEntry(ckPath, 3, 2),
      constraintOrderEntry(ckPath, 3, 1),
      constraintOrderEntry(ckIk, -1, 0),
    ])

    then:
      data.paths.len == 1
      data.pathAttachments.len == 1
      data.pathAttachments[0].p1x == 1.00000001
      data.paths[0].name == "follow"
      data.paths[0].bone == "root"
      data.paths[0].target == "target"
      data.paths[0].path == "curve"
      data.paths[0].order == 7
      decoded.pathAttachments[0].p1x == 1.00000001
      decoded.paths[0].order == 7
      toBonyJson(decoded).contains("\"pathAttachments\"")
      toBonyJson(decoded).contains("\"paths\"")
      ordered.mapIt(it.kind) == @[ckIk, ckIk, ckTransform, ckPath, ckPath, ckPath, ckPhysics]
      ordered.mapIt(it.order) == @[-1, 3, 3, 3, 3, 3, 1]
      ordered.mapIt(it.sourceIndex) == @[0, 0, 0, 0, 1, 2, 0]
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root"}],"regions":[{"name":"curve","width":1,"height":1}],"paths":[{"name":"bad","bone":"missing","target":"root","path":"curve"}]}""",
        unknownRequiredReference
      )
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root"}],"regions":[{"name":"curve","width":1,"height":1}],"paths":[{"name":"bad","bone":"root","target":"missing","path":"curve"}]}""",
        unknownRequiredReference
      )
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root"}],"regions":[{"name":"curve","width":1,"height":1}],"paths":[{"name":"bad","bone":"root","target":"root","path":"curve"}]}""",
        unknownRequiredReference
      )
      raisesBonyLoadError(proc() =
        discard constraintOrderEntry(ckPath, 0, -1)
      , schemaViolation)

  it "resolves canonicalConstraintOrder tie at order=0 by sourceIndex":
    # Mirrors the M5 conformance rig: rider_follow and arm_follow are both
    # ckPath at order=0. sourceIndex must break the tie (rider_follow=0 first).
    let entries = @[
      constraintOrderEntry(ckPath, 0, 1),  # arm_follow (sourceIndex=1)
      constraintOrderEntry(ckPath, 0, 0),  # rider_follow (sourceIndex=0)
    ]
    let ordered = canonicalConstraintOrder(entries)

    then:
      ordered.len == 2
      ordered[0].kind == ckPath
      ordered[0].order == 0
      ordered[0].sourceIndex == 0  # rider_follow wins the tie
      ordered[1].sourceIndex == 1  # arm_follow follows

  it "builds deterministic ordered constraint update caches":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[
        boneData("root", ""),
        boneData("spine", "root"),
        boneData("hand", "spine"),
        boneData("fx", "root"),
      ],
      pathAttachments = @[pathAttachmentData("curve", 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0)],
      paths = @[pathConstraintData("follow", "hand", "root", "curve", order = 2)],
    )
    let cache = buildConstraintUpdateCache(data.bones, @[
      constraintCacheDescriptor(ckPath, 2, 0, ["hand"]),
      constraintCacheDescriptor(ckIk, 2, 0, ["spine"]),
      constraintCacheDescriptor(ckTransform, 2, 0, ["fx"], active = false),
      constraintCacheDescriptor(ckPath, 2, 1, ["fx"]),
      constraintCacheDescriptor(ckPhysics, -10, 0, ["root"]),
    ])
    let pathCache = buildRuntimeConstraintUpdateCache(data)
    let physicsOrder = buildPhysicsConstraintOrder(@[
      constraintCacheDescriptor(ckPhysics, 3, 2, ["root"]),
      constraintCacheDescriptor(ckPhysics, -1, 0, ["root"]),
      constraintCacheDescriptor(ckPhysics, 3, 1, ["root"]),
      constraintCacheDescriptor(ckPath, -10, 0, ["hand"]),
    ])
    let chainCache = buildConstraintUpdateCache(
      @[
        boneData("chain0", ""),
        boneData("chain1", "chain0"),
        boneData("chain2", "chain1"),
        boneData("chain3", "chain2"),
        boneData("side", ""),
      ],
      @[constraintCacheDescriptor(ckIk, 0, 0, ["chain0"])],
    )

    then:
      cache.len == 8
      cache[0].kind == ccekBoneGroup
      cache[0].bones == @[0]
      cache[1].kind == ccekConstraint
      cache[1].constraint.kind == ckIk
      cache[1].constraint.sourceIndex == 0
      cache[2].kind == ccekBoneGroup
      cache[2].bones == @[1]
      cache[3].kind == ccekConstraint
      cache[3].constraint.kind == ckTransform
      cache[3].active == false
      cache[4].constraint.kind == ckPath
      cache[4].constraint.sourceIndex == 0
      cache[5].bones == @[2]
      cache[6].constraint.kind == ckPath
      cache[6].constraint.sourceIndex == 1
      cache[7].bones == @[3]
      cache.allIt(it.kind != ccekConstraint or it.constraint.kind != ckPhysics)
      pathCache.len == 3
      pathCache[0].bones == @[0, 1, 3]
      pathCache[1].constraint.kind == ckPath
      pathCache[1].constraint.order == 2
      pathCache[2].bones == @[2]
      physicsOrder.mapIt(it.order) == @[-1, 3, 3]
      physicsOrder.mapIt(it.sourceIndex) == @[0, 1, 2]
      chainCache.len == 3
      chainCache[0].bones == @[4]
      chainCache[1].constraint.kind == ckIk
      chainCache[2].bones == @[0, 1, 2, 3]
      raisesBonyLoadError(proc() =
        discard buildConstraintUpdateCache(data.bones, @[constraintCacheDescriptor(ckPath, 0, 0, ["missing"])])
      , unknownRequiredReference)

  it "evaluates path constraint cubics with fixed arc-length samples":
    let curve = pathCubic(
      pathPoint(0.0, 0.0),
      pathPoint(30.25, 80.5),
      pathPoint(90.75, -20.125),
      pathPoint(130.5, 40.25),
    )
    let quarter = evaluateCubicPath(curve, 0.25)
    let middle = evaluateCubicPath(curve, 0.5)
    let tangent = cubicPathTangent(curve, 0.5)
    let table = buildPathArcLengthTable(curve)
    let halfDistance = samplePathByDistance(curve, table.totalLength * 0.5)
    let mixed = applyPathPositionConstraint(pathPoint(10.0, 20.0), curve, table.totalLength, 0.25)
    let precise = evaluateCubicPath(pathCubic(
      pathPoint(0.0, 0.0),
      pathPoint(1.00000001, 0.0),
      pathPoint(0.0, 0.0),
      pathPoint(0.0, 0.0),
    ), 0.5)
    let flatStart = samplePathByDistance(pathCubic(
      pathPoint(0.0, 0.0),
      pathPoint(0.0, 0.0),
      pathPoint(10.0, 10.0),
      pathPoint(10.0, 10.0),
    ), 0.0)
    let coincident = samplePathByDistance(pathCubic(
      pathPoint(2.0, 3.0),
      pathPoint(2.0, 3.0),
      pathPoint(2.0, 3.0),
      pathPoint(2.0, 3.0),
    ), 0.0)

    then:
      pathArcLengthSamples == 32
      table.samples.len == pathArcLengthSamples + 1
      table.distances.len == pathArcLengthSamples + 1
      closeTo(quarter.x, 27.5625)
      closeTo(quarter.y, 31.759765625)
      closeTo(middle.x, 61.6875)
      closeTo(middle.y, 27.671875)
      closeTo(tangent.x, 143.25)
      closeTo(tangent.y, -45.28125)
      closeTo(tangentAngle(tangent), -17.541718138895483)
      closeTo(table.totalLength, 155.88369415168393)
      closeTo(halfDistance.distance, table.totalLength * 0.5)
      closeTo(halfDistance.position.x, 61.13043750668265)
      closeTo(halfDistance.position.y, 27.843587919709595)
      closeTo(mixed.position.x, 40.125)
      closeTo(mixed.position.y, 25.0625)
      closeTo(precise.x, 0.37500000375)
      closeTo(flatStart.tangentAngle, 45.0)
      closeTo(coincident.tangentAngle, 0.0)
      closeTo(samplePathByDistance(curve, -10.0).distance, 0.0)
      closeTo(samplePathByDistance(curve, table.totalLength + 10.0).distance, table.totalLength)
      raisesBonyLoadError(proc() =
        discard evaluateCubicPath(curve, -0.1)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        discard pathCubic(PathPoint(x: NaN, y: 0.0), pathPoint(0.0, 0.0), pathPoint(1.0, 0.0), pathPoint(1.0, 1.0))
      , numericOutOfRange)
      raisesBonyLoadError(proc() =
        discard applyPathPositionConstraint(pathPoint(0.0, 0.0), curve, 0.0, 1.1)
      , schemaViolation)

  it "evaluates runtime-enabled path constraints in world transforms":
    let path = pathAttachmentData(
      "line",
      0.0, 0.0,
      3.3333333333333335, 0.0,
      6.666666666666667, 0.0,
      10.0, 0.0,
    )
    let base = skeletonData(
      skeletonHeader("paths", "0.1.0"),
      @[
        boneData("root", ""),
        boneData("follower", "root", localTransform(x = 2.0, y = 3.0, rotation = 90.0)),
      ],
      pathAttachments = @[path],
      paths = @[pathConstraintData("follow", "follower", "root", "line")],
    )
    let runtime = skeletonData(
      skeletonHeader("paths", "0.1.0"),
      @[
        boneData("root", ""),
        boneData("follower", "root", localTransform(x = 2.0, y = 3.0, rotation = 90.0)),
      ],
      pathAttachments = @[path],
      paths = @[
        pathConstraintData(
          "follow", "follower", "root", "line",
          hasPosition = true,
          position = 1.0,
          hasTranslateMix = true,
          translateMix = 1.0,
          hasRotateMix = true,
          rotateMix = 0.5,
        ),
      ],
    )
    let baseWorlds = computeWorldTransforms(base)
    let runtimeWorlds = computeWorldTransforms(runtime)

    then:
      closeTo(baseWorlds[1].tx, 2.0)
      closeTo(baseWorlds[1].ty, 3.0)
      closeTo(runtimeWorlds[1].tx, 10.0)
      closeTo(runtimeWorlds[1].ty, 0.0)
      closeTo(arctan2(runtimeWorlds[1].b, runtimeWorlds[1].a) * 180.0 / PI, 45.0)

  it "rejects runtime path constraints with singular active parent conversion":
    let path = pathAttachmentData("line", 0.0, 0.0, 3.0, 0.0, 6.0, 0.0, 9.0, 0.0)
    let data = skeletonData(
      skeletonHeader("paths", "0.1.0"),
      @[
        boneData("root", "", localTransform(scaleX = 0.0)),
        boneData("follower", "root"),
      ],
      pathAttachments = @[path],
      paths = @[
        pathConstraintData("follow", "follower", "root", "line", hasPosition = true, position = 0.5),
      ],
    )

    then:
      raisesBonyLoadError(proc() = discard computeWorldTransforms(data), schemaViolation)

  it "emits runtime path targets before later target-writing constraints":
    let path = pathAttachmentData(
      "line",
      0.0, 0.0,
      3.3333333333333335, 0.0,
      6.666666666666667, 0.0,
      10.0, 0.0,
    )
    let data = skeletonData(
      skeletonHeader("paths", "0.1.0"),
      @[
        boneData("root", ""),
        boneData("target", "root", localTransform(x = 5.0)),
        boneData("follower", "root"),
      ],
      pathAttachments = @[path],
      paths = @[
        pathConstraintData("follower_follow", "follower", "target", "line", hasPosition = true, position = 1.0),
        pathConstraintData("target_follow", "target", "root", "line", order = 1, hasPosition = true, position = 1.0),
      ],
    )
    let worlds = computeWorldTransforms(data)

    then:
      closeTo(worlds[2].tx, 15.0)
      closeTo(worlds[2].ty, 0.0)
      closeTo(worlds[1].tx, 10.0)
      closeTo(worlds[1].ty, 0.0)
