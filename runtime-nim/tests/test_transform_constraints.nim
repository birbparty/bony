include smoke_support

spec "transform constraint smoke coverage":
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

  it "decomposes and recomposes transform constraint poses":
    let pose = TransformConstraintPose(
      x: 3.0,
      y: 4.0,
      rotation: 30.0,
      scaleX: 2.0,
      scaleY: 3.0,
      shearX: 0.0,
      shearY: 10.0,
    )
    let world = transformPoseToAffine(pose)
    let decoded = affineToTransformPose(world)
    let roundTrip = transformPoseToAffine(decoded)

    then:
      closeTo(decoded.x, 3.0)
      closeTo(decoded.y, 4.0)
      closeTo(decoded.rotation, 30.0)
      closeTo(decoded.scaleX, 2.0)
      closeTo(decoded.scaleY, 3.0)
      closeTo(decoded.shearY, 10.0)
      closeTo(roundTrip.a, world.a)
      closeTo(roundTrip.b, world.b)
      closeTo(roundTrip.c, world.c)
      closeTo(roundTrip.d, world.d)
      closeTo(roundTrip.tx, world.tx)
      closeTo(roundTrip.ty, world.ty)

  it "applies transform constraints per channel":
    let constrained = transformPoseToAffine(TransformConstraintPose(
      x: 0.0,
      y: 0.0,
      rotation: 0.0,
      scaleX: 1.0,
      scaleY: 1.0,
      shearX: 0.0,
      shearY: 0.0,
    ))
    let target = transformPoseToAffine(TransformConstraintPose(
      x: 10.0,
      y: 20.0,
      rotation: 90.0,
      scaleX: 3.0,
      scaleY: 5.0,
      shearX: 0.0,
      shearY: 30.0,
    ))
    let translated = affineToTransformPose(applyTransformConstraint(
      constrained,
      target,
      transformConstraintMix(translate = 0.5, rotate = 0.0, scale = 0.0, shear = 0.0),
    ))
    let rotatedScaled = affineToTransformPose(applyTransformConstraint(
      constrained,
      target,
      transformConstraintMix(translate = 0.0, rotate = 0.5, scale = 0.5, shear = 1.0),
    ))

    then:
      closeTo(translated.x, 5.0)
      closeTo(translated.y, 10.0)
      closeTo(translated.rotation, 0.0)
      closeTo(translated.scaleX, 1.0)
      closeTo(translated.scaleY, 1.0)
      closeTo(rotatedScaled.x, 0.0)
      closeTo(rotatedScaled.y, 0.0)
      closeTo(rotatedScaled.rotation, 45.0)
      closeTo(rotatedScaled.scaleX, 2.0)
      closeTo(rotatedScaled.scaleY, 3.0)
      closeTo(rotatedScaled.shearY, 30.0)
      raisesBonyLoadError(proc() =
        discard applyTransformConstraint(constrained, target, transformConstraintMix(translate = -0.1))
      , schemaViolation)
      raisesBonyLoadError(proc() =
        discard applyTransformConstraint(Affine2(a: NaN), target, transformConstraintMix())
      , numericOutOfRange)
      raisesBonyLoadError(proc() =
        discard transformPoseToAffine(TransformConstraintPose(scaleX: Inf))
      , numericOutOfRange)

  it "preserves transform constraint reflection and shortest angle mixes":
    let identity = transformPoseToAffine(TransformConstraintPose(
      x: 0.0,
      y: 0.0,
      rotation: 0.0,
      scaleX: 1.0,
      scaleY: 1.0,
      shearX: 0.0,
      shearY: 0.0,
    ))
    let reflectedTarget = transformPoseToAffine(TransformConstraintPose(
      x: 0.0,
      y: 0.0,
      rotation: 0.0,
      scaleX: -2.0,
      scaleY: 1.0,
      shearX: 0.0,
      shearY: 0.0,
    ))
    let reflectedScaleOnly = applyTransformConstraint(
      identity,
      reflectedTarget,
      transformConstraintMix(translate = 0.0, rotate = 0.0, scale = 1.0, shear = 0.0),
    )
    let reflectedFull = applyTransformConstraint(identity, reflectedTarget, transformConstraintMix())
    let wrappedRotation = affineToTransformPose(applyTransformConstraint(
      transformPoseToAffine(TransformConstraintPose(rotation: 170.0, scaleX: 1.0, scaleY: 1.0)),
      transformPoseToAffine(TransformConstraintPose(rotation: -170.0, scaleX: 1.0, scaleY: 1.0)),
      transformConstraintMix(translate = 0.0, rotate = 0.5, scale = 0.0, shear = 0.0),
    ))
    let wrappedShear = applyTransformConstraint(
      transformPoseToAffine(TransformConstraintPose(scaleX: 1.0, scaleY: 1.0, shearY: 170.0)),
      transformPoseToAffine(TransformConstraintPose(scaleX: 1.0, scaleY: 1.0, shearY: -170.0)),
      transformConstraintMix(translate = 0.0, rotate = 0.0, scale = 0.0, shear = 0.5),
    )

    then:
      closeTo(reflectedScaleOnly.a, -2.0)
      closeTo(reflectedScaleOnly.b, 0.0)
      closeTo(reflectedScaleOnly.c, 0.0)
      closeTo(reflectedScaleOnly.d, 1.0)
      closeTo(reflectedFull.a, reflectedTarget.a)
      closeTo(reflectedFull.b, reflectedTarget.b)
      closeTo(reflectedFull.c, reflectedTarget.c)
      closeTo(reflectedFull.d, reflectedTarget.d)
      closeTo(abs(wrappedRotation.rotation), 180.0)
      closeTo(wrappedShear.c, 0.0)
      closeTo(wrappedShear.d, -1.0)

  it "loads a transform constraint into SkeletonData with presence flags":
    let data = skeletonData(
      skeletonHeader("tc", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("constrained", "root", localTransform(x = 5.0, y = 0.0)),
        boneData("goal", "root", localTransform(x = 10.0, y = 10.0)),
      ],
      transformConstraints = @[
        transformConstraintData("tc", "constrained", "goal",
          order = 3,
          hasRotateMix = true, rotateMix = 0.25,
          hasScaleMix = true, scaleMix = 0.5),
      ],
    )
    then:
      data.transformConstraints.len == 1
      data.transformConstraints[0].name == "tc"
      data.transformConstraints[0].bone == "constrained"
      data.transformConstraints[0].target == "goal"
      data.transformConstraints[0].order == 3
      # Unset mixes keep their 1.0 default with presence flag false.
      data.transformConstraints[0].hasTranslateMix == false
      closeTo(data.transformConstraints[0].translateMix, 1.0)
      data.transformConstraints[0].hasRotateMix == true
      closeTo(data.transformConstraints[0].rotateMix, 0.25)
      data.transformConstraints[0].hasScaleMix == true
      closeTo(data.transformConstraints[0].scaleMix, 0.5)
      data.transformConstraints[0].hasShearMix == false
      closeTo(data.transformConstraints[0].shearMix, 1.0)

  it "rejects transform constraints with bad refs, duplicate names, or out-of-range mixes":
    proc buildWith(tcs: seq[TransformConstraintData]): SkeletonData =
      skeletonData(
        skeletonHeader("tc", "1.0.0"),
        @[boneData("root", ""), boneData("goal", "root", localTransform(x = 1.0))],
        transformConstraints = tcs,
      )
    then:
      # unknown constrained bone
      raisesBonyLoadError(
        proc() = discard buildWith(@[transformConstraintData("a", "missing", "goal")]),
        unknownRequiredReference)
      # unknown target
      raisesBonyLoadError(
        proc() = discard buildWith(@[transformConstraintData("a", "root", "missing")]),
        unknownRequiredReference)
      # duplicate name
      raisesBonyLoadError(
        proc() = discard buildWith(@[
          transformConstraintData("dup", "root", "goal"),
          transformConstraintData("dup", "goal", "root"),
        ]),
        duplicateKey)
      # mix above [0, 1] rejected at the record constructor
      raisesBonyLoadError(
        proc() = discard transformConstraintData("a", "root", "goal", hasScaleMix = true, scaleMix = 1.5),
        schemaViolation)
      # mix below [0, 1] rejected at the record constructor
      raisesBonyLoadError(
        proc() = discard transformConstraintData("a", "root", "goal", hasTranslateMix = true, translateMix = -0.01),
        schemaViolation)
      # non-finite mix rejected by quantizeF32 before the range check
      raisesBonyLoadError(
        proc() = discard transformConstraintData("a", "root", "goal", hasShearMix = true, shearMix = Inf),
        numericOutOfRange)

  it "round trips transform constraints through JSON and canonical .bnb":
    # A constraint with SOME mixes explicitly present and others omitted, to
    # prove presence-flag fidelity survives both codecs (a has*=false mix must
    # NOT be re-emitted, a present one must round-trip its value).
    let source = loadBonyJson("""
{
  "skeleton": {"name": "tcrt", "version": "1.0.0"},
  "bones": [
    {"name": "root"},
    {"name": "constrained", "parent": "root", "x": 5},
    {"name": "goal", "parent": "root", "x": 10, "y": 10}
  ],
  "transformConstraints": [
    {"name": "tc", "bone": "constrained", "target": "goal", "order": 2, "rotateMix": 0.25, "scaleMix": 0.5}
  ]
}
""")
    let json0 = toBonyJson(source)
    let bnbBytes = toBonyBnb(source)
    let decodedFromBnb = loadBonyBnb(bnbBytes)
    then:
      source.transformConstraints.len == 1
      # JSON<->BNB agree on the decoded model
      toBonyJson(decodedFromBnb) == json0
      # BNB is byte-stable across a JSON re-parse
      toBonyBnb(loadBonyJson(json0)) == bnbBytes
      # presence fidelity: omitted mixes stay absent (default 1.0, has*=false),
      # present mixes keep their value with has*=true
      decodedFromBnb.transformConstraints[0].hasTranslateMix == false
      decodedFromBnb.transformConstraints[0].hasRotateMix == true
      closeTo(decodedFromBnb.transformConstraints[0].rotateMix, 0.25)
      decodedFromBnb.transformConstraints[0].hasScaleMix == true
      closeTo(decodedFromBnb.transformConstraints[0].scaleMix, 0.5)
      decodedFromBnb.transformConstraints[0].hasShearMix == false
      decodedFromBnb.transformConstraints[0].order == 2
      # the emitted JSON omits the two absent mixes but keeps the present ones
      not json0.contains("translateMix")
      not json0.contains("shearMix")
      json0.contains("rotateMix")
      json0.contains("scaleMix")

  it "preserves transform constraint presence-flag boundaries across .bnb":
    # Boundary cases the has* machinery exists to protect (reviewer I1/I2):
    #  - an EXPLICIT default 1.0 mix must survive as has*=true (not collapse to
    #    has*=false), because addFloatIfNeeded(required=true) emits it and decode
    #    rebuilds has* from key presence;
    #  - all-omitted and all-present are the two extremes of the mix bitmap.
    proc rt(tc: TransformConstraintData): TransformConstraintData =
      let data = skeletonData(
        skeletonHeader("b", "1.0.0"),
        @[boneData("root", ""), boneData("goal", "root", localTransform(x = 1.0))],
        transformConstraints = @[tc],
      )
      loadBonyBnb(toBonyBnb(data)).transformConstraints[0]

    # explicit default 1.0 with presence set — must NOT collapse to has*=false
    let explicitDefault = rt(transformConstraintData("t", "root", "goal",
      hasTranslateMix = true, translateMix = 1.0))
    # all four mixes omitted
    let allOmitted = rt(transformConstraintData("t", "root", "goal"))
    # all four mixes explicitly present at non-default values (f32-exact so the
    # round-trip is bit-exact, not just close)
    let allPresent = rt(transformConstraintData("t", "root", "goal",
      hasTranslateMix = true, translateMix = 0.125,
      hasRotateMix = true, rotateMix = 0.25,
      hasScaleMix = true, scaleMix = 0.375,
      hasShearMix = true, shearMix = 0.5))
    then:
      explicitDefault.hasTranslateMix == true
      closeTo(explicitDefault.translateMix, 1.0)
      allOmitted.hasTranslateMix == false
      allOmitted.hasRotateMix == false
      allOmitted.hasScaleMix == false
      allOmitted.hasShearMix == false
      allPresent.hasTranslateMix == true
      allPresent.hasRotateMix == true
      allPresent.hasScaleMix == true
      allPresent.hasShearMix == true
      closeTo(allPresent.translateMix, 0.125)
      closeTo(allPresent.rotateMix, 0.25)
      closeTo(allPresent.scaleMix, 0.375)
      closeTo(allPresent.shearMix, 0.5)

  it "evaluates a transform constraint toward the target in the world pass":
    proc rig(tMix, rMix, sMix, shMix: float64): seq[Affine2] =
      let data = skeletonData(
        skeletonHeader("tc", "1.0.0"),
        @[
          boneData("root", ""),
          boneData("constrained", "root", localTransform(x = 5.0, y = 0.0)),
          boneData("goal", "root", localTransform(x = 10.0, y = 10.0, rotation = 30.0, scaleX = 2.0)),
        ],
        transformConstraints = @[transformConstraintData("tc", "constrained", "goal",
          hasTranslateMix = true, translateMix = tMix,
          hasRotateMix = true, rotateMix = rMix,
          hasScaleMix = true, scaleMix = sMix,
          hasShearMix = true, shearMix = shMix)],
      )
      computeWorldTransforms(data)
    let atZero = rig(0.0, 0.0, 0.0, 0.0)   # all mixes 0 => not runtimeEvaluable => plain FK
    let atOne = rig(1.0, 1.0, 1.0, 1.0)    # full snap => constrained world == goal world
    let partial = rig(0.5, 0.5, 0.5, 0.5)
    then:
      # mix 0: constrained keeps its unconstrained FK world (x=5 at origin)
      closeWithin(atZero[1].tx, 5.0, 1e-6)
      closeWithin(atZero[1].ty, 0.0, 1e-6)
      # mix 1: constrained bone's solved world matches the goal bone's world
      # (proves the world->local decomposition survives the trailing FK group)
      closeWithin(atOne[1].a, atOne[2].a, 1e-5)
      closeWithin(atOne[1].b, atOne[2].b, 1e-5)
      closeWithin(atOne[1].c, atOne[2].c, 1e-5)
      closeWithin(atOne[1].d, atOne[2].d, 1e-5)
      closeWithin(atOne[1].tx, atOne[2].tx, 1e-5)
      closeWithin(atOne[1].ty, atOne[2].ty, 1e-5)
      # partial mix is non-vacuous: strictly between unconstrained (5) and goal (10)
      partial[1].tx > 5.0 + 1e-3
      partial[1].tx < 10.0 - 1e-3

  it "solves a transform constraint under a non-identity (rotated+scaled) parent":
    # The high-risk decomposition case: the constrained bone's parent is rotated
    # AND non-uniformly scaled, so `inherited != identity` and the inherited^-1
    # inverse is actually exercised. At mix=1 the constrained world must still
    # equal the target world exactly (proves the inverse of worldForBone is right,
    # not just for identity parents).
    let data = skeletonData(
      skeletonHeader("tc", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("mid", "root", localTransform(x = 3.0, y = -2.0, rotation = 40.0, scaleX = 1.7, scaleY = 0.8)),
        boneData("constrained", "mid", localTransform(x = 4.0, y = 1.0, rotation = 15.0)),
        boneData("goal", "root", localTransform(x = 10.0, y = 10.0, rotation = 30.0, scaleX = 1.3)),
      ],
      transformConstraints = @[transformConstraintData("tc", "constrained", "goal",
        hasTranslateMix = true, translateMix = 1.0,
        hasRotateMix = true, rotateMix = 1.0,
        hasScaleMix = true, scaleMix = 1.0,
        hasShearMix = true, shearMix = 1.0)],
    )
    let worlds = computeWorldTransforms(data)
    # bone order: root=0, mid=1, constrained=2, goal=3
    then:
      closeWithin(worlds[2].a, worlds[3].a, 1e-4)
      closeWithin(worlds[2].b, worlds[3].b, 1e-4)
      closeWithin(worlds[2].c, worlds[3].c, 1e-4)
      closeWithin(worlds[2].d, worlds[3].d, 1e-4)
      closeWithin(worlds[2].tx, worlds[3].tx, 1e-4)
      closeWithin(worlds[2].ty, worlds[3].ty, 1e-4)

  it "coexists and orders transform between ik and path constraints":
    # ik, transform, and path constraints on the same rig must all evaluate; the
    # shared update cache orders them ckIk < ckTransform < ckPath. This locks in
    # that a transform constraint does not disturb the ik/path passes and is
    # itself non-vacuous alongside them.
    let data = skeletonData(
      skeletonHeader("mixed", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("ikBone", "root", localTransform(x = 4.0, y = 0.0)),
        boneData("ikGoal", "root", localTransform(x = 2.0, y = 3.0)),
        boneData("tcBone", "root", localTransform(x = 5.0, y = 0.0)),
        boneData("tcGoal", "root", localTransform(x = 9.0, y = 9.0, rotation = 20.0)),
      ],
      ikConstraints = @[ikConstraintData("ik", "ikGoal", @["ikBone"])],
      transformConstraints = @[transformConstraintData("tc", "tcBone", "tcGoal",
        hasTranslateMix = true, translateMix = 0.5,
        hasRotateMix = true, rotateMix = 0.5)],
    )
    let worlds = computeWorldTransforms(data)
    # bone order: root=0, ikBone=1, ikGoal=2, tcBone=3, tcGoal=4
    then:
      # transform constraint is non-vacuous (tcBone moved off its rest x=5 toward
      # tcGoal x=9) without throwing, alongside the ik pass.
      worlds[3].tx > 5.0 + 1e-3
      worlds[3].tx < 9.0 - 1e-3

  it "orders a real transform constraint between ik and path in the runtime cache":
    # Drive buildRuntimeConstraintUpdateCache from actual data.transformConstraints
    # (not hand-authored descriptors) so the update_cache descriptor loop is what
    # is under test. Same order value on all three -> tie broken by constraintKindRank
    # ckIk(0) < ckTransform(1) < ckPath(2).
    let data = skeletonData(
      skeletonHeader("ord", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("ikBone", "root", localTransform(x = 4.0)),
        boneData("ikGoal", "root", localTransform(x = 2.0, y = 3.0)),
        boneData("tcBone", "root", localTransform(x = 5.0)),
        boneData("tcGoal", "root", localTransform(x = 9.0, y = 9.0)),
        boneData("pathBone", "root", localTransform(x = 6.0)),
        boneData("pathTarget", "root", localTransform(x = 1.0)),
      ],
      pathAttachments = @[pathAttachmentData("curve", 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0)],
      paths = @[pathConstraintData("p", "pathBone", "pathTarget", "curve", hasTranslateMix = true, translateMix = 0.5)],
      ikConstraints = @[ikConstraintData("ik", "ikGoal", @["ikBone"])],
      transformConstraints = @[transformConstraintData("tc", "tcBone", "tcGoal", hasTranslateMix = true, translateMix = 0.5)],
    )
    let cache = buildRuntimeConstraintUpdateCache(data)
    var kindsInOrder: seq[ConstraintKind]
    for entry in cache:
      if entry.kind == ccekConstraint:
        kindsInOrder.add entry.constraint.kind
    then:
      kindsInOrder == @[ckIk, ckTransform, ckPath]

  it "fires the runtime pass for a transform-only skeleton":
    # A transform-only rig (no paths, no ik) must still enter the runtime
    # constraint path: buildRuntimeConstraintUpdateCache emits a ckTransform
    # constraint entry, and computeWorldTransforms produces the solved (non-FK)
    # world for the constrained bone.
    let data = skeletonData(
      skeletonHeader("tonly", "1.0.0"),
      @[
        boneData("root", ""),
        boneData("constrained", "root", localTransform(x = 5.0)),
        boneData("goal", "root", localTransform(x = 11.0, y = 4.0)),
      ],
      transformConstraints = @[transformConstraintData("tc", "constrained", "goal",
        hasTranslateMix = true, translateMix = 0.5)],
    )
    let cache = buildRuntimeConstraintUpdateCache(data)
    var transformEntries = 0
    for entry in cache:
      if entry.kind == ccekConstraint and entry.constraint.kind == ckTransform:
        inc transformEntries
    let worlds = computeWorldTransforms(data)
    then:
      # descriptor loop picked up the tc (emission is per-descriptor; the solved
      # world below is what proves the detection gate actually fired + evaluated).
      transformEntries == 1
      closeWithin(worlds[1].tx, 8.0, 1e-6)   # x: 5 blended halfway to goal x=11 -> 8
      closeWithin(worlds[1].ty, 2.0, 1e-6)   # y: 0 blended halfway to goal y=4  -> 2
