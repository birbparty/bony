include smoke_support

spec "animation mixing smoke coverage":
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

  it "carries the winning deform channel through blend1D pose composition":
    # Regression (bony-353d): blend1D (sampleBlendPose -> blendedPose ->
    # addWeightedPose) silently dropped the deforms channel, so a blend state
    # playing a clip with a deform timeline rendered the static mesh. Deforms
    # resolve winner-take-by-track-weight (docs/deform-timeline-contract.md), so
    # the higher-weight clip's deform wins outright — never a linear blend of the
    # two sparse delta runs.
    let bones = @[boneData("root", "", localTransform(scaleX = 1.0, scaleY = 1.0))]
    let prelim = skeletonData(skeletonHeader("demo", "0.1.0"), bones)
    let mesh = unweightedMeshAttachment(
      prelim,
      "cloth",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(1.0, 1.0)],
    )
    var dataValue = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      bones,
      @[slotData("body", "root", "cloth")],
      meshAttachments = @[mesh],
    )
    let data = new SkeletonData
    data[] = dataValue
    let low = animationClip(
      data[],
      "low",
      deformTimelines = @[deformTimeline("default", "body", mesh,
        @[deformKeyframe(0.0, 0'u32, @[meshDelta(2.0, 0.0), meshDelta(0.0, 0.0), meshDelta(0.0, 0.0)])])],
    )
    let high = animationClip(
      data[],
      "high",
      deformTimelines = @[deformTimeline("default", "body", mesh,
        @[deformKeyframe(0.0, 0'u32, @[meshDelta(5.0, 0.0), meshDelta(0.0, 0.0), meshDelta(0.0, 0.0)])])],
    )
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineBlendState("move", "speed", @[stateMachineBlendClip(low, 0.0), stateMachineBlendClip(high, 1.0)])],
        ),
      ],
      @[stateMachineNumberInput("speed", 0.25)],
    )
    var lowWins = initStateMachineRuntime(machine)
    lowWins.setNumberInput("speed", 0.25)
    let lowEval = lowWins.evaluate(data)
    var highWins = initStateMachineRuntime(machine)
    highWins.setNumberInput("speed", 0.75)
    let highEval = highWins.evaluate(data)
    # Tie-break: t == 0.5 snaps to high (matches addWeightedPose's t >= 0.5 and
    # the Dart runtime's `t >= 0.5 ? hi : lo`).
    var tieWins = initStateMachineRuntime(machine)
    tieWins.setNumberInput("speed", 0.5)
    let tieEval = tieWins.evaluate(data)

    then:
      # t=0.25 -> low clip is the higher-weight winner (weight 0.75).
      lowEval.pose.deforms.len == 1
      lowEval.pose.deforms[0].slot == "body"
      lowEval.pose.deforms[0].attachment == "cloth"
      closeTo(lowEval.pose.deforms[0].deltas[0].x, 2.0)
      # t=0.75 -> high clip wins; deltas are the winner's outright, NOT blended
      # toward 2.0 (a weighted sum would land at 5*0.75 + 2*0.25 = 4.25).
      highEval.pose.deforms.len == 1
      closeTo(highEval.pose.deforms[0].deltas[0].x, 5.0)
      # t == 0.5 -> high wins the tie outright (5.0, not blended).
      tieEval.pose.deforms.len == 1
      closeTo(tieEval.pose.deforms[0].deltas[0].x, 5.0)

  it "carries deforms through multi-layer overlay pose aggregation":
    # Locks the pre-existing overlayPose deforms branch (bony-353d notes) — this
    # path was NOT changed by the blend1D fix, so this is a characterization test
    # for the overlay seam rather than a regression test for this bug. Two layers
    # each drive the same (slot, mesh) deform; the top layer wins outright in the
    # aggregated pose, and the base layer's deltas are fully replaced.
    let bones = @[boneData("root", "", localTransform(scaleX = 1.0, scaleY = 1.0))]
    let prelim = skeletonData(skeletonHeader("demo", "0.1.0"), bones)
    let mesh = unweightedMeshAttachment(
      prelim,
      "cloth",
      @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(1.0, 1.0)],
      @[0'u16, 1'u16, 2'u16],
      @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(1.0, 1.0)],
    )
    var dataValue = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      bones,
      @[slotData("body", "root", "cloth")],
      meshAttachments = @[mesh],
    )
    let data = new SkeletonData
    data[] = dataValue
    let baseClip = animationClip(
      data[],
      "baseDeform",
      deformTimelines = @[deformTimeline("default", "body", mesh,
        @[deformKeyframe(0.0, 0'u32, @[meshDelta(2.0, 0.0), meshDelta(0.0, 0.0), meshDelta(0.0, 0.0)])])],
    )
    let overlayClip = animationClip(
      data[],
      "overlayDeform",
      deformTimelines = @[deformTimeline("default", "body", mesh,
        @[deformKeyframe(0.0, 0'u32, @[meshDelta(7.0, 0.0), meshDelta(0.0, 0.0), meshDelta(0.0, 0.0)])])],
    )
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer("base", @[stateMachineState("hold", baseClip)]),
        stateMachineLayer("overlay", @[stateMachineState("hold", overlayClip)]),
      ],
    )
    let evaluated = initStateMachineRuntime(machine).evaluate(data)

    then:
      evaluated.layers.len == 2
      evaluated.layers[0].pose.deforms.len == 1
      closeTo(evaluated.layers[0].pose.deforms[0].deltas[0].x, 2.0)
      evaluated.layers[1].pose.deforms.len == 1
      closeTo(evaluated.layers[1].pose.deforms[0].deltas[0].x, 7.0)
      # Aggregated pose: top layer's deform wins outright, base is replaced.
      evaluated.pose.deforms.len == 1
      evaluated.pose.deforms[0].slot == "body"
      evaluated.pose.deforms[0].attachment == "cloth"
      closeTo(evaluated.pose.deforms[0].deltas[0].x, 7.0)

  it "threads every MixedPose channel through blend1D aggregation":
    # Completeness guard (bony-bna8): blend1D routes through sampleBlendPose ->
    # blendedPose -> addWeightedPose. A channel dropped by any of them (as deforms
    # was) surfaces here as an empty field. Both blend clips drive all 8 channels,
    # so the winner (t=0.75 -> high) must carry every one.
    let data = new SkeletonData
    data[] = allChannelFixture()
    let clip = allChannelClip(data[], "all")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineBlendState("move", "speed",
            @[stateMachineBlendClip(clip, 0.0), stateMachineBlendClip(clip, 1.0)])],
        ),
      ],
      @[stateMachineNumberInput("speed", 0.75)],
    )
    var rt = initStateMachineRuntime(machine)
    rt.setNumberInput("speed", 0.75)
    rt.update(0.0)
    let evaluated = rt.evaluate(data)

    then:
      droppedChannels(evaluated.pose) == newSeq[string]()

  it "blends asymmetric clips per-channel with setup-pose fallback":
    # bony-6dkk: the low and high blend clips drive DIFFERENT bones, so each
    # numeric channel is present in only one clip. blendedPose must union the
    # channels and fall back to the SETUP pose value for the side that lacks a
    # key (setupScalarValue/setupVectorValue) — the completeness guard uses
    # identical clips and never exercises these per-channel fallback branches.
    let bones = @[
      boneData("root", ""),
      boneData("a", "root", localTransform(x = 100.0, y = 200.0, rotation = 10.0)),
      boneData("b", "root", localTransform(x = 300.0, y = 400.0, rotation = 20.0)),
    ]
    var dataValue = skeletonData(skeletonHeader("demo", "0.1.0"), bones)
    let data = new SkeletonData
    data[] = dataValue
    let low = animationClip(
      data[],
      "low",
      @[
        boneScalarTimeline("a", rotateTimeline, @[scalarKeyframe(0.0, 40.0)]),
        boneVectorTimeline("a", translateTimeline, @[vector2Keyframe(0.0, 4.0, 6.0)]),
      ],
    )
    let high = animationClip(
      data[],
      "high",
      @[
        boneScalarTimeline("b", rotateTimeline, @[scalarKeyframe(0.0, 80.0)]),
        boneVectorTimeline("b", translateTimeline, @[vector2Keyframe(0.0, 10.0, 2.0)]),
      ],
    )
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer(
          "base",
          @[stateMachineBlendState("move", "speed",
            @[stateMachineBlendClip(low, 0.0), stateMachineBlendClip(high, 1.0)])],
        ),
      ],
      @[stateMachineNumberInput("speed", 0.5)],
    )
    var rt = initStateMachineRuntime(machine)
    rt.setNumberInput("speed", 0.5)
    let evaluated = rt.evaluate(data)

    then:
      # Union of both clips' channels (sorted a before b), not just the winner's.
      evaluated.pose.scalars.len == 2
      evaluated.pose.scalars[0].target == "a"
      evaluated.pose.scalars[1].target == "b"
      # a: keyed low=40, high falls back to setup rotation 10 -> 40 + (10-40)*0.5 = 25.
      closeTo(evaluated.pose.scalars[0].value, 25.0)
      # b: low falls back to setup rotation 20, keyed high=80 -> 20 + (80-20)*0.5 = 50.
      closeTo(evaluated.pose.scalars[1].value, 50.0)
      evaluated.pose.vectors.len == 2
      evaluated.pose.vectors[0].target == "a"
      evaluated.pose.vectors[1].target == "b"
      # a: keyed low=(4,6), high falls back to setup (100,200) -> (52,103).
      closeTo(evaluated.pose.vectors[0].x, 52.0)
      closeTo(evaluated.pose.vectors[0].y, 103.0)
      # b: low falls back to setup (300,400), keyed high=(10,2) -> (155,201).
      closeTo(evaluated.pose.vectors[1].x, 155.0)
      closeTo(evaluated.pose.vectors[1].y, 201.0)

  it "threads every MixedPose channel through multi-layer overlay aggregation":
    # Completeness guard (bony-bna8): the overlayPose seam aggregates layers. Two
    # layers each drive all 8 channels; none may drop from the aggregated pose.
    let data = new SkeletonData
    data[] = allChannelFixture()
    let clip = allChannelClip(data[], "all")
    let machine = stateMachine(
      "machine",
      @[
        stateMachineLayer("base", @[stateMachineState("hold", clip)]),
        stateMachineLayer("overlay", @[stateMachineState("hold", clip)]),
      ],
    )
    var rt = initStateMachineRuntime(machine)
    rt.update(0.0)
    let evaluated = rt.evaluate(data)

    then:
      droppedChannels(evaluated.pose) == newSeq[string]()
