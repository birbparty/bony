include smoke_support

spec "parameter and timeline smoke coverage":
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

  it "returns empty key lists for inactive timeline variants":
    let scalar = boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 10.0)])
    let vector = boneVectorTimeline("root", translateTimeline, @[vector2Keyframe(0.0, 1.0, 2.0)])
    let inherit = boneInheritTimeline("root", @[inheritKeyframe(0.0)])
    let attachment = slotAttachmentTimeline("body", @[attachmentKeyframe(0.0, "idle")])
    let color = slotColorTimeline("body", rgbaTimeline, @[colorKeyframe(0.0, colorRgba(1.0, 1.0, 1.0, 1.0))])
    let color2 = slotColor2Timeline(
      "body",
      @[color2Keyframe(0.0, colorRgba2(colorRgba(1.0, 1.0, 1.0, 1.0), 0.0, 0.0, 0.0))],
    )
    let sequence = slotSequenceTimeline("body", @[sequenceKeyframe(0.0, 0'u32, 0.1)])

    then:
      scalar.vectorKeys.len == 0
      scalar.inheritKeys.len == 0
      vector.scalarKeys.len == 0
      vector.inheritKeys.len == 0
      inherit.scalarKeys.len == 0
      inherit.vectorKeys.len == 0
      attachment.colorKeys.len == 0
      attachment.color2Keys.len == 0
      attachment.sequenceKeys.len == 0
      color.attachmentKeys.len == 0
      color.color2Keys.len == 0
      color.sequenceKeys.len == 0
      color2.attachmentKeys.len == 0
      color2.colorKeys.len == 0
      color2.sequenceKeys.len == 0
      sequence.attachmentKeys.len == 0
      sequence.colorKeys.len == 0
      sequence.color2Keys.len == 0

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
