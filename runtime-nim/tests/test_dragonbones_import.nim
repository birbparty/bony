include smoke_support

spec "dragonbones import smoke coverage":
  it "imports a minimal DragonBones _ske.json and round-trips through .bnb":
    let cliPath = "/tmp/bony_cli_harness_db_smoke"
    let skePath = "/tmp/bony_cli_harness_ske.json"
    let dbOutPath = "/tmp/bony_cli_harness_db_out.bony"
    let dbStaticNoAnimOutPath = "/tmp/bony_cli_harness_db_static_no_anim.bony"
    let dbBnbPath = "/tmp/bony_cli_harness_db_out.bnb"
    let dbRoundTripPath = "/tmp/bony_cli_harness_db_roundtrip.bony"
    let dbRejectMeshPath = "/tmp/bony_cli_harness_db_reject_mesh.json"
    let dbRejectMeshOutPath = "/tmp/bony_cli_harness_db_reject_mesh.bony"
    let dbRejectBadParentPath = "/tmp/bony_cli_harness_db_reject_parent.json"
    let dbRejectBadParentOutPath = "/tmp/bony_cli_harness_db_reject_parent.bony"
    let dbRejectDisplayXformPath = "/tmp/bony_cli_harness_db_reject_disp_xform.json"
    let dbRejectDisplayXformOutPath = "/tmp/bony_cli_harness_db_reject_disp_xform.bony"
    let dbAnimatedPath = "/tmp/bony_cli_harness_db_animated.json"
    let dbAnimatedOutPath = "/tmp/bony_cli_harness_db_animated.bony"
    let dbAnimatedPreserveOutPath = "/tmp/bony_cli_harness_db_animated_preserve.bony"
    let dbAnimatedBnbPath = "/tmp/bony_cli_harness_db_animated.bnb"
    let dbAnimatedRoundTripPath = "/tmp/bony_cli_harness_db_animated_roundtrip.bony"
    let dbAnimatedGoldenPath = "/tmp/bony_cli_harness_db_animated_golden.json"
    let dbAnimatedBnbGoldenPath = "/tmp/bony_cli_harness_db_animated_bnb_golden.json"
    let dbAnimatedSlideGoldenPath = "/tmp/bony_cli_harness_db_animated_slide_golden.json"
    let dbAnimatedRejectedGoldenPath = "/tmp/bony_cli_harness_db_animated_rejected_golden.json"
    let dbAnimatedUnknownGoldenPath = "/tmp/bony_cli_harness_db_animated_unknown_golden.json"
    let dbUnsupportedAnimPath = "/tmp/bony_cli_harness_db_unsupported_anim.json"
    let dbUnsupportedAnimOutPath = "/tmp/bony_cli_harness_db_unsupported_anim.bony"
    let dbSetupOnlySkipsAnimPath = "/tmp/bony_cli_harness_db_setup_skips_anim.json"
    let dbSetupOnlySkipsAnimOutPath = "/tmp/bony_cli_harness_db_setup_skips_anim.bony"
    let dbZeroDurationAnimPath = "/tmp/bony_cli_harness_db_zero_duration_anim.json"
    let dbZeroDurationAnimOutPath = "/tmp/bony_cli_harness_db_zero_duration_anim.bony"
    for path in [cliPath, skePath, dbOutPath, dbStaticNoAnimOutPath, dbBnbPath, dbRoundTripPath,
                 dbRejectMeshPath, dbRejectMeshOutPath,
                 dbRejectBadParentPath, dbRejectBadParentOutPath,
                 dbRejectDisplayXformPath, dbRejectDisplayXformOutPath,
                 dbAnimatedPath, dbAnimatedOutPath, dbAnimatedPreserveOutPath,
                 dbAnimatedBnbPath, dbAnimatedRoundTripPath, dbAnimatedGoldenPath,
                 dbAnimatedBnbGoldenPath, dbAnimatedSlideGoldenPath, dbAnimatedRejectedGoldenPath,
                 dbAnimatedUnknownGoldenPath,
                 dbUnsupportedAnimPath, dbUnsupportedAnimOutPath,
                 dbSetupOnlySkipsAnimPath, dbSetupOnlySkipsAnimOutPath,
                 dbZeroDurationAnimPath, dbZeroDurationAnimOutPath]:
      if fileExists(path):
        removeFile(path)

    let compileResult = execCmdEx(
      "nim c --path:" & repoPath("runtime-nim", "src") & " -o:" & cliPath & " " & repoPath("cli", "bony_cli.nim"),
      options = {poStdErrToStdOut},
    )

    proc dbArmatureJson(
      animationJson: string;
      boneJson = """[{"name": "root"}]""";
      extraArmatureFields = "";
    ): string =
      """{
  "version": "5.6.300.1",
  "name": "db_anim_reject",
  "armature": [
    {
      "type": "Armature",
      "frameRate": 24,
      "name": "reject_arm",
      "bone": """ & boneJson & extraArmatureFields & """,
      "animation": [""" & animationJson & """]
    }
  ]
}
"""

    var dbRejectMatrixFailures: seq[string]
    proc recordDbReject(
      name, inputJson, codeFragment, targetFragment, capabilityFragment: string;
      setupOnly = false;
    ) =
      let inputPath = "/tmp/bony_cli_harness_db_matrix_" & name & ".json"
      let outputPath = "/tmp/bony_cli_harness_db_matrix_" & name & ".bony"
      if fileExists(inputPath):
        removeFile(inputPath)
      if fileExists(outputPath):
        removeFile(outputPath)
      writeFile(inputPath, inputJson)
      writeFile(outputPath, "sentinel output")
      var args = @["import-dragonbones", inputPath, outputPath]
      if setupOnly:
        args.add "--setup-only"
      let rejected = runProcess(cliPath, args)
      let outputUnchanged = fileExists(outputPath) and readFile(outputPath) == "sentinel output"
      if fileExists(inputPath):
        removeFile(inputPath)
      if fileExists(outputPath):
        removeFile(outputPath)
      if rejected.exitCode == 0 or
         not rejected.output.contains(codeFragment) or
         not rejected.output.contains(targetFragment) or
         not rejected.output.contains(capabilityFragment) or
         rejected.output.contains("Traceback") or
         not outputUnchanged:
        dbRejectMatrixFailures.add name & ": " & rejected.output

    # Minimal valid 5.x _ske.json with unsorted child-before-parent bones and
    # one slot (no assets needed for a setup-only, no-skin import).
    writeFile(skePath, """{
  "version": "5.6.300.1",
  "name": "db_test",
  "armature": [
    {
      "type": "Armature",
      "frameRate": 30,
      "name": "hero",
      "bone": [
        {"name": "root"},
        {"name": "arm", "parent": "torso", "transform": {"x": 20, "y": -5, "skX": -15, "skY": -10}},
        {"name": "torso", "parent": "root", "transform": {"x": 0, "y": 10, "skX": 5, "skY": 5, "scX": 1, "scY": 1}}
      ],
      "slot": [
        {"name": "body_slot", "parent": "torso"}
      ]
    }
  ]
}
""")
    # --setup-only: no assets dir needed; no skin defined, so no attachment lookup.
    let importDb = runProcess(cliPath, ["import-dragonbones", skePath, dbOutPath, "--setup-only"])
    let importedStaticAsset =
      if fileExists(dbOutPath): loadBonyJsonAsset(readFile(dbOutPath))
      else: bonyAsset(skeletonData(skeletonHeader("err", "0"), @[boneData("err", "")]))
    let importDbStaticPreserved = runProcess(cliPath, ["import-dragonbones", skePath, dbStaticNoAnimOutPath])
    let preservedStaticAsset =
      if fileExists(dbStaticNoAnimOutPath): loadBonyJsonAsset(readFile(dbStaticNoAnimOutPath))
      else: bonyAsset(skeletonData(skeletonHeader("err", "0"), @[boneData("err", "")]))
    let dbJsonToBnb = runProcess(cliPath, ["json-to-bnb", dbOutPath, dbBnbPath])
    let dbBnbToJson = runProcess(cliPath, ["bnb-to-json", dbBnbPath, dbRoundTripPath])
    let imported =
      if fileExists(dbRoundTripPath): loadBonyJson(readFile(dbRoundTripPath))
      else: skeletonData(skeletonHeader("err", "0"), @[boneData("err", "")])

    # Reject: mesh display (unsupportedFeature).
    writeFile(dbRejectMeshPath, """{
  "version": "5.6.300.1",
  "name": "db_mesh",
  "armature": [
    {
      "type": "Armature",
      "frameRate": 24,
      "name": "mesh_arm",
      "bone": [{"name": "root"}],
      "slot": [{"name": "slot1", "parent": "root"}],
      "skin": [{"name": "", "slot": [
        {"name": "slot1", "display": [{"name": "mesh_disp", "type": "mesh"}]}
      ]}]
    }
  ]
}
""")
    let rejectedMesh = runProcess(
      cliPath,
      ["import-dragonbones", dbRejectMeshPath, dbRejectMeshOutPath, "--setup-only"],
    )
    let rejectedMeshLeftPartial = fileExists(dbRejectMeshOutPath)

    # Reject: slot parent references non-existent bone (invalidReference).
    writeFile(dbRejectBadParentPath, """{
  "version": "5.6.300.1",
  "name": "db_bad_parent",
  "armature": [
    {
      "type": "Armature",
      "frameRate": 24,
      "name": "bad_arm",
      "bone": [{"name": "root"}],
      "slot": [{"name": "slot1", "parent": "ghost"}]
    }
  ]
}
""")
    let rejectedBadParent = runProcess(
      cliPath,
      ["import-dragonbones", dbRejectBadParentPath, dbRejectBadParentOutPath, "--setup-only"],
    )
    let rejectedBadParentLeftPartial = fileExists(dbRejectBadParentOutPath)

    # Reject: non-identity display transform (unsupportedFeature).
    writeFile(dbRejectDisplayXformPath, """{
  "version": "5.6.300.1",
  "name": "db_disp_xform",
  "armature": [
    {
      "type": "Armature",
      "frameRate": 24,
      "name": "xform_arm",
      "bone": [{"name": "root"}],
      "slot": [{"name": "slot1", "parent": "root"}],
      "skin": [{"name": "", "slot": [
        {"name": "slot1", "display": [
          {"name": "img", "type": "image", "transform": {"x": 10, "y": 5}}
        ]}
      ]}]
    }
  ]
}
""")
    let rejectedDisplayXform = runProcess(
      cliPath,
      ["import-dragonbones", dbRejectDisplayXformPath, dbRejectDisplayXformOutPath, "--setup-only"],
    )
    let rejectedDisplayXformLeftPartial = fileExists(dbRejectDisplayXformOutPath)

    # Static setup-only imports should be quiet; animated setup-only imports
    # currently suppress animation with an explicit diagnostic.
    writeFile(dbAnimatedPath, """{
  "version": "5.6.300.1",
  "name": "db_anim",
  "armature": [
    {
      "type": "Armature",
      "frameRate": 24,
      "name": "animated_arm",
      "bone": [
        {"name": "root", "transform": {"x": 10, "y": 20, "skX": 10, "skY": 30, "scX": 2, "scY": 3}},
        {"name": "child", "parent": "root", "transform": {"x": 1, "y": 2, "skX": 5, "skY": 6, "scX": 1.5, "scY": 2.5}}
      ],
      "animation": [
        {"name": "all_channels", "duration": 24, "bone": [
          {"name": "root", "translateFrame": [
            {"duration": 12, "x": 5, "y": -2, "tweenEasing": 0},
            {"duration": 12, "x": 7, "y": 4, "tweenEasing": null},
            {"duration": 0}
          ], "rotateFrame": [
            {"duration": 24, "rotate": 15, "tweenEasing": 0},
            {"duration": 0}
          ], "scaleFrame": [
            {"duration": 24, "x": 1.5, "y": 0.5, "tweenEasing": 0},
            {"duration": 0}
          ]}
        ]},
        {"name": "slide_only", "duration": 12, "bone": [
          {"name": "child", "translateFrame": [
            {"duration": 12, "x": 4, "y": -3, "tweenEasing": 0},
            {"duration": 0}
          ]}
        ]}
      ]
    }
  ]
}
""")
    let importedAnimated = runProcess(
      cliPath,
      ["import-dragonbones", dbAnimatedPath, dbAnimatedOutPath, "--setup-only"],
    )
    let setupOnlyAnimatedAsset =
      if fileExists(dbAnimatedOutPath): loadBonyJsonAsset(readFile(dbAnimatedOutPath))
      else: bonyAsset(skeletonData(skeletonHeader("err", "0"), @[boneData("err", "")]))
    let importedAnimatedPreserved = runProcess(
      cliPath,
      ["import-dragonbones", dbAnimatedPath, dbAnimatedPreserveOutPath],
    )
    let preservedAnimatedJson =
      if fileExists(dbAnimatedPreserveOutPath): readFile(dbAnimatedPreserveOutPath)
      else: ""
    let preservedAnimatedAsset =
      if preservedAnimatedJson.len > 0: loadBonyJsonAsset(preservedAnimatedJson)
      else: bonyAsset(skeletonData(skeletonHeader("err", "0"), @[boneData("err", "")]))
    let preservedAnimatedCanonical =
      if preservedAnimatedJson.len > 0: toBonyJson(loadBonyJsonAsset(preservedAnimatedJson))
      else: ""
    let dbAnimatedJsonToBnb = runProcess(cliPath, ["json-to-bnb", dbAnimatedPreserveOutPath, dbAnimatedBnbPath])
    let dbAnimatedBnbToJson = runProcess(cliPath, ["bnb-to-json", dbAnimatedBnbPath, dbAnimatedRoundTripPath])
    let roundTrippedAnimatedAsset =
      if fileExists(dbAnimatedRoundTripPath): loadBonyJsonAsset(readFile(dbAnimatedRoundTripPath))
      else: bonyAsset(skeletonData(skeletonHeader("err", "0"), @[boneData("err", "")]))
    let animatedGolden = runProcess(
      cliPath,
      ["golden-gen", dbAnimatedPreserveOutPath, dbAnimatedGoldenPath, "--animation", "all_channels", "--t", "0.5"],
    )
    let animatedBnbGolden = runProcess(
      cliPath,
      ["golden-gen", dbAnimatedBnbPath, dbAnimatedBnbGoldenPath, "--animation", "all_channels", "--t", "0.5"],
    )
    let animatedSlideGolden = runProcess(
      cliPath,
      ["golden-gen", dbAnimatedPreserveOutPath, dbAnimatedSlideGoldenPath, "--animation", "slide_only", "--t", "0.25"],
    )
    let animatedGoldenWithoutContext = runProcess(
      cliPath,
      ["golden-gen", dbAnimatedPreserveOutPath, dbAnimatedRejectedGoldenPath, "--t", "0.5"],
    )
    let animatedGoldenUnknownClip = runProcess(
      cliPath,
      ["golden-gen", dbAnimatedPreserveOutPath, dbAnimatedUnknownGoldenPath, "--animation", "missing_clip", "--t", "0.5"],
    )
    let animatedGoldenJson =
      if fileExists(dbAnimatedGoldenPath): parseJson(readFile(dbAnimatedGoldenPath))
      else: newJObject()
    let animatedBnbGoldenJson =
      if fileExists(dbAnimatedBnbGoldenPath): parseJson(readFile(dbAnimatedBnbGoldenPath))
      else: newJObject()
    let animatedSlideGoldenJson =
      if fileExists(dbAnimatedSlideGoldenPath): parseJson(readFile(dbAnimatedSlideGoldenPath))
      else: newJObject()

    var allChannelsName = ""
    var allChannelsDuration = -1.0
    var allChannelsTimelineCount = -1
    var translateTarget = ""
    var translateTimes: seq[float64]
    var translateXs: seq[float64]
    var translateYs: seq[float64]
    var translateCurveX: seq[TimelineCurveKind]
    var translateCurveY: seq[TimelineCurveKind]
    var rotateTarget = ""
    var rotateTimes: seq[float64]
    var rotateValues: seq[float64]
    var rotateCurves: seq[TimelineCurveKind]
    var scaleTarget = ""
    var scaleTimes: seq[float64]
    var scaleXs: seq[float64]
    var scaleYs: seq[float64]
    var scaleCurveX: seq[TimelineCurveKind]
    var scaleCurveY: seq[TimelineCurveKind]
    var slideName = ""
    var slideDuration = -1.0
    var slideTimelineCount = -1
    var slideTarget = ""
    var slideTimes: seq[float64]
    var slideXs: seq[float64]
    var slideYs: seq[float64]
    var slideBoneRestX = 0.0
    var slideBoneRestY = 0.0
    var slideBoneRestRotation = 0.0
    var slideBoneRestScaleX = 0.0
    var slideBoneRestScaleY = 0.0
    var rtAllChannelsName = ""
    var rtAllChannelsDuration = -1.0
    var rtAllChannelsTimelineCount = -1
    var rtTranslateTarget = ""
    var rtTranslateTimes: seq[float64]
    var rtTranslateXs: seq[float64]
    var rtTranslateYs: seq[float64]
    var rtRotateTarget = ""
    var rtRotateTimes: seq[float64]
    var rtRotateValues: seq[float64]
    var rtScaleTarget = ""
    var rtScaleTimes: seq[float64]
    var rtScaleXs: seq[float64]
    var rtScaleYs: seq[float64]
    var rtSlideName = ""
    var rtSlideDuration = -1.0
    var rtSlideTimelineCount = -1
    var rtSlideTarget = ""
    var rtSlideTimes: seq[float64]
    var rtSlideXs: seq[float64]
    var rtSlideYs: seq[float64]
    var animatedGoldenBoneCount = -1
    var animatedGoldenTime = -1.0
    var animatedGoldenRootTx = -9999.0
    var animatedGoldenRootTy = -9999.0
    var animatedGoldenChildA = -9999.0
    var animatedGoldenChildB = -9999.0
    var animatedGoldenChildC = -9999.0
    var animatedGoldenChildD = -9999.0
    var animatedGoldenChildTx = -9999.0
    var animatedGoldenChildTy = -9999.0
    var animatedBnbGoldenBoneCount = -1
    var animatedBnbGoldenTime = -1.0
    var animatedBnbGoldenRootTx = -9999.0
    var animatedBnbGoldenRootTy = -9999.0
    var animatedBnbGoldenChildA = -9999.0
    var animatedBnbGoldenChildB = -9999.0
    var animatedBnbGoldenChildC = -9999.0
    var animatedBnbGoldenChildD = -9999.0
    var animatedBnbGoldenChildTx = -9999.0
    var animatedBnbGoldenChildTy = -9999.0
    var animatedSlideGoldenBoneCount = -1
    var animatedSlideGoldenTime = -1.0
    var animatedSlideGoldenRootA = -9999.0
    var animatedSlideGoldenRootB = -9999.0
    var animatedSlideGoldenRootC = -9999.0
    var animatedSlideGoldenRootD = -9999.0
    var animatedSlideGoldenRootTx = -9999.0
    var animatedSlideGoldenRootTy = -9999.0
    var animatedSlideGoldenChildA = -9999.0
    var animatedSlideGoldenChildB = -9999.0
    var animatedSlideGoldenChildC = -9999.0
    var animatedSlideGoldenChildD = -9999.0
    var animatedSlideGoldenChildTx = -9999.0
    var animatedSlideGoldenChildTy = -9999.0
    if animatedGoldenJson.hasKey("time"):
      animatedGoldenTime = animatedGoldenJson["time"].getFloat()
    if animatedGoldenJson.hasKey("bones") and animatedGoldenJson["bones"].kind == JArray:
      animatedGoldenBoneCount = animatedGoldenJson["bones"].elems.len
      for bone in animatedGoldenJson["bones"].elems:
        if bone.hasKey("name") and bone["name"].getStr() == "root":
          animatedGoldenRootTx = bone["world"]["tx"].getFloat()
          animatedGoldenRootTy = bone["world"]["ty"].getFloat()
        elif bone.hasKey("name") and bone["name"].getStr() == "child":
          animatedGoldenChildA = bone["world"]["a"].getFloat()
          animatedGoldenChildB = bone["world"]["b"].getFloat()
          animatedGoldenChildC = bone["world"]["c"].getFloat()
          animatedGoldenChildD = bone["world"]["d"].getFloat()
          animatedGoldenChildTx = bone["world"]["tx"].getFloat()
          animatedGoldenChildTy = bone["world"]["ty"].getFloat()
    if animatedBnbGoldenJson.hasKey("time"):
      animatedBnbGoldenTime = animatedBnbGoldenJson["time"].getFloat()
    if animatedBnbGoldenJson.hasKey("bones") and animatedBnbGoldenJson["bones"].kind == JArray:
      animatedBnbGoldenBoneCount = animatedBnbGoldenJson["bones"].elems.len
      for bone in animatedBnbGoldenJson["bones"].elems:
        if bone.hasKey("name") and bone["name"].getStr() == "root":
          animatedBnbGoldenRootTx = bone["world"]["tx"].getFloat()
          animatedBnbGoldenRootTy = bone["world"]["ty"].getFloat()
        elif bone.hasKey("name") and bone["name"].getStr() == "child":
          animatedBnbGoldenChildA = bone["world"]["a"].getFloat()
          animatedBnbGoldenChildB = bone["world"]["b"].getFloat()
          animatedBnbGoldenChildC = bone["world"]["c"].getFloat()
          animatedBnbGoldenChildD = bone["world"]["d"].getFloat()
          animatedBnbGoldenChildTx = bone["world"]["tx"].getFloat()
          animatedBnbGoldenChildTy = bone["world"]["ty"].getFloat()
    if animatedSlideGoldenJson.hasKey("time"):
      animatedSlideGoldenTime = animatedSlideGoldenJson["time"].getFloat()
    if animatedSlideGoldenJson.hasKey("bones") and animatedSlideGoldenJson["bones"].kind == JArray:
      animatedSlideGoldenBoneCount = animatedSlideGoldenJson["bones"].elems.len
      for bone in animatedSlideGoldenJson["bones"].elems:
        if bone.hasKey("name") and bone["name"].getStr() == "root":
          animatedSlideGoldenRootA = bone["world"]["a"].getFloat()
          animatedSlideGoldenRootB = bone["world"]["b"].getFloat()
          animatedSlideGoldenRootC = bone["world"]["c"].getFloat()
          animatedSlideGoldenRootD = bone["world"]["d"].getFloat()
          animatedSlideGoldenRootTx = bone["world"]["tx"].getFloat()
          animatedSlideGoldenRootTy = bone["world"]["ty"].getFloat()
        elif bone.hasKey("name") and bone["name"].getStr() == "child":
          animatedSlideGoldenChildA = bone["world"]["a"].getFloat()
          animatedSlideGoldenChildB = bone["world"]["b"].getFloat()
          animatedSlideGoldenChildC = bone["world"]["c"].getFloat()
          animatedSlideGoldenChildD = bone["world"]["d"].getFloat()
          animatedSlideGoldenChildTx = bone["world"]["tx"].getFloat()
          animatedSlideGoldenChildTy = bone["world"]["ty"].getFloat()
    if preservedAnimatedAsset.animations.len >= 2:
      let allChannels = preservedAnimatedAsset.animations[0]
      allChannelsName = allChannels.name
      allChannelsDuration = allChannels.duration
      allChannelsTimelineCount = allChannels.boneTimelines.len
      for timeline in allChannels.boneTimelines:
        if timeline.target == "root" and timeline.kind == translateTimeline:
          translateTarget = timeline.target
          for key in timeline.vectorKeys:
            translateTimes.add key.time
            translateXs.add key.x
            translateYs.add key.y
            translateCurveX.add key.curveX.kind
            translateCurveY.add key.curveY.kind
        elif timeline.target == "root" and timeline.kind == rotateTimeline:
          rotateTarget = timeline.target
          for key in timeline.scalarKeys:
            rotateTimes.add key.time
            rotateValues.add key.value
            rotateCurves.add key.curve.kind
        elif timeline.target == "root" and timeline.kind == scaleTimeline:
          scaleTarget = timeline.target
          for key in timeline.vectorKeys:
            scaleTimes.add key.time
            scaleXs.add key.x
            scaleYs.add key.y
            scaleCurveX.add key.curveX.kind
            scaleCurveY.add key.curveY.kind

      let slideOnly = preservedAnimatedAsset.animations[1]
      slideName = slideOnly.name
      slideDuration = slideOnly.duration
      slideTimelineCount = slideOnly.boneTimelines.len
      for timeline in slideOnly.boneTimelines:
        if timeline.target == "child" and timeline.kind == translateTimeline:
          slideTarget = timeline.target
          for key in timeline.vectorKeys:
            slideTimes.add key.time
            slideXs.add key.x
            slideYs.add key.y
      for bone in preservedAnimatedAsset.skeleton.bones:
        if bone.name == "child":
          slideBoneRestX = bone.local.x
          slideBoneRestY = bone.local.y
          slideBoneRestRotation = bone.local.rotation
          slideBoneRestScaleX = bone.local.scaleX
          slideBoneRestScaleY = bone.local.scaleY
    if roundTrippedAnimatedAsset.animations.len >= 2:
      let allChannels = roundTrippedAnimatedAsset.animations[0]
      rtAllChannelsName = allChannels.name
      rtAllChannelsDuration = allChannels.duration
      rtAllChannelsTimelineCount = allChannels.boneTimelines.len
      for timeline in allChannels.boneTimelines:
        if timeline.target == "root" and timeline.kind == translateTimeline:
          rtTranslateTarget = timeline.target
          for key in timeline.vectorKeys:
            rtTranslateTimes.add key.time
            rtTranslateXs.add key.x
            rtTranslateYs.add key.y
        elif timeline.target == "root" and timeline.kind == rotateTimeline:
          rtRotateTarget = timeline.target
          for key in timeline.scalarKeys:
            rtRotateTimes.add key.time
            rtRotateValues.add key.value
        elif timeline.target == "root" and timeline.kind == scaleTimeline:
          rtScaleTarget = timeline.target
          for key in timeline.vectorKeys:
            rtScaleTimes.add key.time
            rtScaleXs.add key.x
            rtScaleYs.add key.y

      let slideOnly = roundTrippedAnimatedAsset.animations[1]
      rtSlideName = slideOnly.name
      rtSlideDuration = slideOnly.duration
      rtSlideTimelineCount = slideOnly.boneTimelines.len
      for timeline in slideOnly.boneTimelines:
        if timeline.target == "child" and timeline.kind == translateTimeline:
          rtSlideTarget = timeline.target
          for key in timeline.vectorKeys:
            rtSlideTimes.add key.time
            rtSlideXs.add key.x
            rtSlideYs.add key.y

    writeFile(dbUnsupportedAnimPath, """{
  "version": "5.6.300.1",
  "name": "db_unsupported_anim",
  "armature": [
    {
      "type": "Armature",
      "frameRate": 24,
      "name": "unsupported_anim_arm",
      "bone": [{"name": "root"}],
      "animation": [{"name": "empty", "duration": 0}]
    }
  ]
}
""")
    writeFile(dbUnsupportedAnimOutPath, "sentinel output")
    let rejectedUnsupportedAnim = runProcess(
      cliPath,
      ["import-dragonbones", dbUnsupportedAnimPath, dbUnsupportedAnimOutPath],
    )
    let rejectedUnsupportedAnimOutput = readFile(dbUnsupportedAnimOutPath)

    # --setup-only must skip animation channel validation while preserving
    # structural armature validation above.
    writeFile(dbSetupOnlySkipsAnimPath, dbArmatureJson("""{"name": "invalid_but_suppressed", "duration": 1, "bone": [
        {"name": "root", "translateFrame": [
          {"duration": 1, "tweenEasing": 0.5},
          {"duration": 0}
        ]}
      ]}"""))
    let setupOnlySkippedInvalidAnimation = runProcess(
      cliPath,
      ["import-dragonbones", dbSetupOnlySkipsAnimPath, dbSetupOnlySkipsAnimOutPath, "--setup-only"],
    )
    let setupOnlySkippedAsset =
      if fileExists(dbSetupOnlySkipsAnimOutPath): loadBonyJsonAsset(readFile(dbSetupOnlySkipsAnimOutPath))
      else: bonyAsset(skeletonData(skeletonHeader("err", "0"), @[boneData("err", "")]))

    # Current local policy accepts animation.duration == 0 when the channel is a
    # single zero-duration terminator key.
    writeFile(dbZeroDurationAnimPath, dbArmatureJson("""{"name": "zero", "duration": 0, "bone": [
        {"name": "root", "translateFrame": [
          {"duration": 0}
        ]}
      ]}"""))
    let importedZeroDurationAnimation = runProcess(
      cliPath,
      ["import-dragonbones", dbZeroDurationAnimPath, dbZeroDurationAnimOutPath],
    )
    let zeroDurationAsset =
      if fileExists(dbZeroDurationAnimOutPath): loadBonyJsonAsset(readFile(dbZeroDurationAnimOutPath))
      else: bonyAsset(skeletonData(skeletonHeader("err", "0"), @[boneData("err", "")]))

    recordDbReject(
      "nonzero_tween",
      dbArmatureJson("""{"name": "bad", "duration": 1, "bone": [
        {"name": "root", "translateFrame": [
          {"duration": 1, "tweenEasing": 0.5},
          {"duration": 0}
        ]}
      ]}"""),
      "unsupportedFeature", "target=animation[bad].bone[root].translateFrame[0]", "capability=tweenEasing",
    )
    recordDbReject(
      "well_formed_curve",
      dbArmatureJson("""{"name": "bad", "duration": 1, "bone": [
        {"name": "root", "translateFrame": [
          {"duration": 1, "curve": [0, 0, 1, 1]},
          {"duration": 0}
        ]}
      ]}"""),
      "unsupportedFeature", "target=animation[bad].bone[root].translateFrame[0]", "capability=curve",
    )
    recordDbReject(
      "malformed_curve",
      dbArmatureJson("""{"name": "bad", "duration": 1, "bone": [
        {"name": "root", "translateFrame": [
          {"duration": 1, "curve": [0, 1]},
          {"duration": 0}
        ]}
      ]}"""),
      "unsupportedFeature", "target=animation[bad].bone[root].translateFrame[0]", "capability=curve",
    )
    recordDbReject(
      "clockwise",
      dbArmatureJson("""{"name": "bad", "duration": 1, "bone": [
        {"name": "root", "rotateFrame": [
          {"duration": 1, "clockwise": 1},
          {"duration": 0}
        ]}
      ]}"""),
      "unsupportedFeature", "target=animation[bad].bone[root].rotateFrame[0]", "capability=clockwise",
    )
    recordDbReject(
      "slot_channel",
      dbArmatureJson(
        """{"name": "bad", "duration": 0, "slot": [{"name": "slot1"}]}""",
        extraArmatureFields = """,
      "slot": [{"name": "slot1", "parent": "root"}]""",
      ),
      "unsupportedFeature", "target=animation[0]", "capability=slot",
    )
    recordDbReject(
      "invalid_bone_reference",
      dbArmatureJson("""{"name": "bad", "duration": 1, "bone": [
        {"name": "ghost", "translateFrame": [
          {"duration": 1},
          {"duration": 0}
        ]}
      ]}"""),
      "invalidReference", "target=ghost", "capability=bone",
    )
    recordDbReject(
      "bad_duration_sum",
      dbArmatureJson("""{"name": "bad", "duration": 2, "bone": [
        {"name": "root", "translateFrame": [
          {"duration": 1},
          {"duration": 0}
        ]}
      ]}"""),
      "schemaViolation", "target=animation[bad].bone[root]", "capability=translateFrame",
    )
    recordDbReject(
      "missing_terminator",
      dbArmatureJson("""{"name": "bad", "duration": 1, "bone": [
        {"name": "root", "translateFrame": [{"duration": 1}]}
      ]}"""),
      "schemaViolation", "target=animation[bad].bone[root]", "capability=translateFrame",
    )
    recordDbReject(
      "negative_scale",
      dbArmatureJson(
        """{"name": "bad", "duration": 0, "bone": [
        {"name": "root", "translateFrame": [{"duration": 0}]}
      ]}""",
        boneJson = """[{"name": "root", "transform": {"scX": -1}}]""",
      ),
      "unsupportedFeature", "target=bone[0].transform", "capability=negativeScale",
    )
    recordDbReject(
      "duplicate_bone_entry",
      dbArmatureJson("""{"name": "bad", "duration": 0, "bone": [
        {"name": "root", "translateFrame": [{"duration": 0}]},
        {"name": "root", "translateFrame": [{"duration": 0}]}
      ]}"""),
      "schemaViolation", "target=animation[bad].bone[root]", "capability=bone",
    )
    recordDbReject(
      "duplicate_animation_name",
      dbArmatureJson("""{"name": "bad", "duration": 0, "bone": [
        {"name": "root", "translateFrame": [{"duration": 0}]}
      ]},
      {"name": "bad", "duration": 0, "bone": [
        {"name": "root", "translateFrame": [{"duration": 0}]}
      ]}"""),
      "schemaViolation", "target=animation[bad]", "capability=name",
    )
    for field in ["fadeInTime", "playTimes", "blendType", "type", "frame", "ffd"]:
      let value =
        if field in ["blendType", "type"]:
          "\"unsupported\""
        elif field in ["frame", "ffd"]:
          "[]"
        else:
          "1"
      recordDbReject(
        "animation_field_" & field,
        dbArmatureJson("""{"name": "bad", "duration": 0, """" & field & """": """ & value & """}"""),
        "unsupportedFeature", "target=animation[0]", "capability=" & field,
      )

    then:
      compileResult.exitCode == 0
      importDb.exitCode == 0
      importDb.output.strip() == ""
      importedStaticAsset.animations.len == 0
      importDbStaticPreserved.exitCode == 0
      importDbStaticPreserved.output.strip() == ""
      preservedStaticAsset.animations.len == 0
      dbJsonToBnb.exitCode == 0
      dbBnbToJson.exitCode == 0
      imported.bones.len == 3
      imported.bones[0].name == "root"
      imported.bones[1].name == "torso"
      imported.bones[1].parent == "root"
      imported.bones[2].name == "arm"
      imported.bones[2].parent == "torso"
      closeTo(imported.bones[1].local.y, -10.0)   # Y-flip: 10 → -10
      closeTo(imported.bones[1].local.rotation, -5.0)  # rotation = -skY = -5
      closeTo(imported.bones[1].local.shearY, 0.0)  # shearY = skY - skX = 5 - 5 = 0
      closeTo(imported.bones[2].local.rotation, 10.0)  # rotation = -skY = -(-10) = 10
      closeTo(imported.bones[2].local.shearY, 5.0)   # shearY = skY - skX = -10 - (-15) = 5
      imported.slots.len == 1
      imported.slots[0].name == "body_slot"
      imported.slots[0].bone == "torso"
      rejectedMesh.exitCode != 0
      rejectedMesh.output.contains("unsupportedFeature")
      rejectedMesh.output.contains("target=skin.slot[slot1].display[0]")
      rejectedMesh.output.contains("capability=mesh")
      not rejectedMeshLeftPartial
      rejectedBadParent.exitCode != 0
      rejectedBadParent.output.contains("invalidReference")
      rejectedBadParent.output.contains("target=slot1")
      rejectedBadParent.output.contains("capability=parent")
      not rejectedBadParentLeftPartial
      not rejectedMesh.output.contains("Traceback")
      not rejectedBadParent.output.contains("Traceback")
      rejectedDisplayXform.exitCode != 0
      rejectedDisplayXform.output.contains("unsupportedFeature")
      rejectedDisplayXform.output.contains("target=skin.slot[slot1].display[0]")
      rejectedDisplayXform.output.contains("capability=displayTransform")
      not rejectedDisplayXform.output.contains("Traceback")
      not rejectedDisplayXformLeftPartial
      importedAnimated.exitCode == 0
      importedAnimated.output.contains("--setup-only: animation suppressed")
      setupOnlyAnimatedAsset.animations.len == 0
      importedAnimatedPreserved.exitCode == 0
      importedAnimatedPreserved.output.strip() == ""
      preservedAnimatedJson.contains("\"animations\"")
      preservedAnimatedCanonical == preservedAnimatedJson
      dbAnimatedJsonToBnb.exitCode == 0
      dbAnimatedBnbToJson.exitCode == 0
      animatedGolden.exitCode == 0
      animatedBnbGolden.exitCode == 0
      animatedSlideGolden.exitCode == 0
      animatedGoldenWithoutContext.exitCode != 0
      animatedGoldenWithoutContext.output.contains("--t is reserved")
      not fileExists(dbAnimatedRejectedGoldenPath)
      animatedGoldenUnknownClip.exitCode != 0
      animatedGoldenUnknownClip.output.contains("unknown animation: missing_clip")
      not fileExists(dbAnimatedUnknownGoldenPath)
      closeTo(animatedGoldenTime, 0.5)
      animatedGoldenBoneCount == 2
      closeTo(animatedGoldenRootTx, 17.0)
      closeTo(animatedGoldenRootTy, -24.0)
      closeTo(animatedGoldenChildA, 2.8526931902892088)
      closeTo(animatedGoldenChildB, -2.606805302750525)
      closeTo(animatedGoldenChildC, 2.1171916904428425)
      closeTo(animatedGoldenChildD, 5.012637114579177)
      closeTo(animatedGoldenChildTx, 17.630207252958858)
      closeTo(animatedGoldenChildTy, -29.813629850888823)
      closeTo(animatedBnbGoldenTime, 0.5)
      animatedBnbGoldenBoneCount == 2
      closeTo(animatedBnbGoldenRootTx, 17.0)
      closeTo(animatedBnbGoldenRootTy, -24.0)
      closeTo(animatedBnbGoldenChildA, 2.8526931902892088)
      closeTo(animatedBnbGoldenChildB, -2.606805302750525)
      closeTo(animatedBnbGoldenChildC, 2.1171916904428425)
      closeTo(animatedBnbGoldenChildD, 5.012637114579177)
      closeTo(animatedBnbGoldenChildTx, 17.630207252958858)
      closeTo(animatedBnbGoldenChildTy, -29.813629850888823)
      closeTo(animatedSlideGoldenTime, 0.25)
      animatedSlideGoldenBoneCount == 2
      closeTo(animatedSlideGoldenRootA, 1.7320508075688774)
      closeTo(animatedSlideGoldenRootB, -0.9999999999999999)
      closeTo(animatedSlideGoldenRootC, 0.5209445330007912)
      closeTo(animatedSlideGoldenRootD, 2.954423259036624)
      closeTo(animatedSlideGoldenRootTx, 10.0)
      closeTo(animatedSlideGoldenRootTy, -20.0)
      closeTo(animatedSlideGoldenChildA, 2.5021633808029353)
      closeTo(animatedSlideGoldenChildB, -1.955014827716376)
      closeTo(animatedSlideGoldenChildC, 1.674800890964038)
      closeTo(animatedSlideGoldenChildD, 7.140062609558906)
      closeTo(animatedSlideGoldenChildTx, 14.935680156206237)
      closeTo(animatedSlideGoldenChildTy, -24.47721162951831)
      preservedAnimatedAsset.animations.len == 2
      roundTrippedAnimatedAsset.animations.len == 2
      allChannelsName == "all_channels"
      rtAllChannelsName == "all_channels"
      closeTo(allChannelsDuration, 1.0)
      closeTo(rtAllChannelsDuration, 1.0)
      allChannelsTimelineCount == 3
      rtAllChannelsTimelineCount == 3
      translateTarget == "root"
      rtTranslateTarget == "root"
      translateTimes.len == 3
      rtTranslateTimes.len == 3
      closeTo(translateTimes[0], 0.0)
      closeTo(translateTimes[1], 0.5)
      closeTo(translateTimes[2], 1.0)
      closeTo(rtTranslateTimes[0], 0.0)
      closeTo(rtTranslateTimes[1], 0.5)
      closeTo(rtTranslateTimes[2], 1.0)
      closeTo(translateXs[0], 15.0)
      closeTo(translateYs[0], -18.0)
      closeTo(translateXs[1], 17.0)
      closeTo(translateYs[1], -24.0)
      closeTo(translateXs[2], 10.0)
      closeTo(translateYs[2], -20.0)
      closeTo(rtTranslateXs[0], 15.0)
      closeTo(rtTranslateYs[0], -18.0)
      closeTo(rtTranslateXs[1], 17.0)
      closeTo(rtTranslateYs[1], -24.0)
      closeTo(rtTranslateXs[2], 10.0)
      closeTo(rtTranslateYs[2], -20.0)
      translateCurveX == @[linearCurve, steppedCurve, steppedCurve]
      translateCurveY == @[linearCurve, steppedCurve, steppedCurve]
      rotateTarget == "root"
      rtRotateTarget == "root"
      rotateTimes.len == 2
      rtRotateTimes.len == 2
      closeTo(rotateTimes[0], 0.0)
      closeTo(rotateTimes[1], 1.0)
      closeTo(rtRotateTimes[0], 0.0)
      closeTo(rtRotateTimes[1], 1.0)
      closeTo(rotateValues[0], -45.0)
      closeTo(rotateValues[1], -30.0)
      closeTo(rtRotateValues[0], -45.0)
      closeTo(rtRotateValues[1], -30.0)
      rotateCurves == @[linearCurve, steppedCurve]
      scaleTarget == "root"
      rtScaleTarget == "root"
      scaleTimes.len == 2
      rtScaleTimes.len == 2
      closeTo(scaleTimes[0], 0.0)
      closeTo(scaleTimes[1], 1.0)
      closeTo(rtScaleTimes[0], 0.0)
      closeTo(rtScaleTimes[1], 1.0)
      closeTo(scaleXs[0], 3.0)
      closeTo(scaleYs[0], 1.5)
      closeTo(scaleXs[1], 2.0)
      closeTo(scaleYs[1], 3.0)
      closeTo(rtScaleXs[0], 3.0)
      closeTo(rtScaleYs[0], 1.5)
      closeTo(rtScaleXs[1], 2.0)
      closeTo(rtScaleYs[1], 3.0)
      scaleCurveX == @[linearCurve, steppedCurve]
      scaleCurveY == @[linearCurve, steppedCurve]
      slideName == "slide_only"
      rtSlideName == "slide_only"
      closeTo(slideDuration, 0.5)
      closeTo(rtSlideDuration, 0.5)
      slideTimelineCount == 1
      rtSlideTimelineCount == 1
      slideTarget == "child"
      rtSlideTarget == "child"
      slideTimes.len == 2
      rtSlideTimes.len == 2
      closeTo(slideTimes[0], 0.0)
      closeTo(slideTimes[1], 0.5)
      closeTo(rtSlideTimes[0], 0.0)
      closeTo(rtSlideTimes[1], 0.5)
      closeTo(slideXs[0], 5.0)
      closeTo(slideYs[0], 1.0)
      closeTo(slideXs[1], 1.0)
      closeTo(slideYs[1], -2.0)
      closeTo(rtSlideXs[0], 5.0)
      closeTo(rtSlideYs[0], 1.0)
      closeTo(rtSlideXs[1], 1.0)
      closeTo(rtSlideYs[1], -2.0)
      closeTo(slideBoneRestX, 1.0)
      closeTo(slideBoneRestY, -2.0)
      closeTo(slideBoneRestRotation, -6.0)
      closeTo(slideBoneRestScaleX, 1.5)
      closeTo(slideBoneRestScaleY, 2.5)
      rejectedUnsupportedAnim.exitCode != 0
      rejectedUnsupportedAnim.output.contains("unsupportedFeature")
      rejectedUnsupportedAnim.output.contains("target=animation[empty]")
      rejectedUnsupportedAnim.output.contains("capability=animation")
      not rejectedUnsupportedAnim.output.contains("Traceback")
      rejectedUnsupportedAnimOutput == "sentinel output"
      setupOnlySkippedInvalidAnimation.exitCode == 0
      setupOnlySkippedInvalidAnimation.output.contains("--setup-only: animation suppressed")
      setupOnlySkippedAsset.animations.len == 0
      importedZeroDurationAnimation.exitCode == 0
      zeroDurationAsset.animations.len == 1
      closeTo(zeroDurationAsset.animations[0].duration, 0.0)
      dbRejectMatrixFailures.join("\n") == ""

    for path in [cliPath, skePath, dbOutPath, dbStaticNoAnimOutPath, dbBnbPath, dbRoundTripPath,
                 dbRejectMeshPath, dbRejectMeshOutPath,
                 dbRejectBadParentPath, dbRejectBadParentOutPath,
                 dbRejectDisplayXformPath, dbRejectDisplayXformOutPath,
                 dbAnimatedPath, dbAnimatedOutPath, dbAnimatedPreserveOutPath,
                 dbAnimatedBnbPath, dbAnimatedRoundTripPath, dbAnimatedGoldenPath,
                 dbAnimatedBnbGoldenPath, dbAnimatedSlideGoldenPath, dbAnimatedRejectedGoldenPath,
                 dbAnimatedUnknownGoldenPath,
                 dbUnsupportedAnimPath, dbUnsupportedAnimOutPath,
                 dbSetupOnlySkipsAnimPath, dbSetupOnlySkipsAnimOutPath,
                 dbZeroDurationAnimPath, dbZeroDurationAnimOutPath]:
      if fileExists(path):
        removeFile(path)
