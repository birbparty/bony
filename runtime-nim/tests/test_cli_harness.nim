include smoke_support

spec "cli harness smoke coverage":
  it "runs the CLI harness core commands":
    let cliPath = "/tmp/bony_cli_harness_smoke"
    let assetPath = "/tmp/bony_cli_harness_asset.bony"
    let bnbPath = "/tmp/bony_cli_harness_asset.bnb"
    let roundTripPath = "/tmp/bony_cli_harness_roundtrip.bony"
    let goldenPath = "/tmp/bony_cli_harness_golden.json"
    let framePath = "/tmp/bony_cli_harness_frame.png"
    let frameTopLeftPath = "/tmp/bony_cli_harness_frame_top_left.png"
    let stateAssetPath = repoPath("conformance", "assets", "m8_rig.bony")
    let stateBnbPath = "/tmp/m8_rig.bnb"
    let stateScriptPath = "/tmp/bony_cli_harness_state_script.json"
    let badStateScriptPath = "/tmp/bony_cli_harness_bad_state_script.json"
    let duplicateStateScriptPath = "/tmp/bony_cli_harness_duplicate_state_script.json"
    let numericStateScriptPath = "/tmp/bony_cli_harness_numeric_state_script.json"
    let colorStateAssetPath = "/tmp/bony_cli_harness_color_state.bony"
    let colorStateScriptPath = "/tmp/bony_cli_harness_color_state_script.json"
    let colorStateGoldenPath = "/tmp/bony_cli_harness_color_state_golden.json"
    let colorStateFramePath = "/tmp/bony_cli_harness_color_state_frame.png"
    let stateGoldenPath = "/tmp/bony_cli_harness_state_golden.json"
    let stateFramePath = "/tmp/bony_cli_harness_state_frame.png"
    let lottiePath = "/tmp/bony_cli_harness_lottie.json"
    let lottieOutPath = "/tmp/bony_cli_harness_lottie.bony"
    let lottieBnbPath = "/tmp/bony_cli_harness_lottie.bnb"
    let lottieRoundTripPath = "/tmp/bony_cli_harness_lottie_roundtrip.bony"
    let lottieAssetsDir = "/tmp/bony_cli_harness_lottie_assets"
    for path in [
      cliPath,
      assetPath,
      bnbPath,
      roundTripPath,
      goldenPath,
      framePath,
      frameTopLeftPath,
      stateScriptPath,
      stateBnbPath,
      badStateScriptPath,
      duplicateStateScriptPath,
      numericStateScriptPath,
      colorStateAssetPath,
      colorStateScriptPath,
      colorStateGoldenPath,
      colorStateFramePath,
      stateGoldenPath,
      stateFramePath,
      lottiePath,
      lottieOutPath,
      lottieBnbPath,
      lottieRoundTripPath,
    ]:
      if fileExists(path):
        removeFile(path)
    if dirExists(lottieAssetsDir):
      removeDir(lottieAssetsDir)

    let compileResult = execCmdEx(
      "nim c --path:" & repoPath("runtime-nim", "src") & " -o:" & cliPath & " " & repoPath("cli", "bony_cli.nim"),
      options = {poStdErrToStdOut},
    )
    let fixture = skeletonData(
      skeletonHeader("cli-demo", "0.1.0"),
      @[
        boneData("root", "", localTransform(x = 2.0, y = 3.0)),
        boneData("child", "root", localTransform(x = 4.0)),
      ],
      @[slotData("body", "child", "bodyRegion")],
      @[regionAttachment("bodyRegion", 2.0, 4.0)],
    )
    writeFile(assetPath, toBonyJson(fixture))

    let jsonToBnb = runProcess(cliPath, ["json-to-bnb", assetPath, bnbPath])
    let bnbToJson = runProcess(cliPath, ["bnb-to-json", bnbPath, roundTripPath])
    let golden = runProcess(cliPath, ["golden-gen", bnbPath, goldenPath, "--t", "0"])
    let play = runProcess(cliPath, ["play", assetPath, "--out", framePath, "--width", "8", "--height", "8", "--t", "0"])
    let playTopLeft = runProcess(cliPath, ["play", assetPath, "--out", frameTopLeftPath, "--width", "8", "--height", "8", "--t", "0", "--origin", "top-left"])
    let playBadOrigin = runProcess(cliPath, ["play", assetPath, "--out", framePath, "--origin", "bad"])
    let unsupportedTime = runProcess(cliPath, ["golden-gen", assetPath, goldenPath, "--t", "1.25"])
    writeFile(stateScriptPath, """{
  "format": "bony.input-script.v1",
  "asset": "m8_rig.bony",
  "stateMachine": "gesture",
  "samples": [
    {"name": "idle", "t": 0.0, "inputs": {}},
    {"name": "move", "t": 0.1, "inputs": {"wave": true, "speed": 0.75}},
    {"name": "jump", "t": 0.2, "inputs": {"jump": "fire"}},
    {"name": "idle_again", "t": 0.3, "inputs": {"wave": false}}
  ]
}
""")
    writeFile(badStateScriptPath, """{
  "format": "bony.input-script.v1",
  "asset": "m8_rig.bony",
  "stateMachine": "gesture",
  "samples": [
    {"t": 0.0, "inputs": {}}
  ]
}
""")
    writeFile(duplicateStateScriptPath, """{
  "format": "bony.input-script.v1",
  "asset": "m8_rig.bony",
  "stateMachine": "gesture",
  "samples": [
    {"name": "dup", "t": 0.0, "inputs": {"wave": true, "wave": false}}
  ]
}
""")
    writeFile(numericStateScriptPath, """{
  "format": "bony.input-script.v1",
  "asset": "m8_rig.bony",
  "stateMachine": "gesture",
  "samples": [
    {"name": "1", "t": 0.0, "inputs": {}}
  ]
}
""")
    writeFile(colorStateAssetPath, """{
  "skeleton": {"name": "color-sm"},
  "bones": [
    {"name": "root"},
    {"name": "body_bone", "parent": "root", "x": -4},
    {"name": "glow_bone", "parent": "root"},
    {"name": "fx_bone", "parent": "root", "x": 4}
  ],
  "slots": [
    {"name": "body", "bone": "body_bone", "attachment": "body"},
    {"name": "glow", "bone": "glow_bone", "attachment": "glow"},
    {"name": "fx", "bone": "fx_bone", "attachment": "fx_0"}
  ],
  "regions": [
    {"name": "body", "width": 2, "height": 2},
    {"name": "glow", "width": 2, "height": 2},
    {"name": "fx_0", "width": 2, "height": 2},
    {"name": "fx_1", "width": 2, "height": 2}
  ],
  "animations": [
    {
      "name": "alpha",
      "slotTimelines": [
        {
          "slot": "body",
          "property": "alpha",
          "keyframes": [{"t": 0.0, "a": 0.5}]
        }
      ]
    },
    {
      "name": "two_color",
      "slotTimelines": [
        {
          "slot": "glow",
          "property": "rgba2",
          "keyframes": [{"t": 0.0, "r": 0.25, "g": 0.5, "b": 0.75, "a": 0.8, "dr": 0.1, "dg": 0.2, "db": 0.3}]
        }
      ]
    },
    {
      "name": "sequence",
      "slotTimelines": [
        {
          "slot": "fx",
          "property": "sequence",
          "keyframes": [
            {"t": 0.0, "index": 0, "delay": 0.1, "mode": "loop"},
            {"t": 0.2, "index": 0, "delay": 0.1, "mode": "loop"}
          ]
        }
      ]
    }
  ],
  "stateMachines": [
    {
      "name": "color",
      "layers": [
        {
          "name": "base",
          "states": [{"name": "alpha", "kind": "clip", "clip": "alpha"}]
        },
        {
          "name": "light",
          "states": [{"name": "two_color", "kind": "clip", "clip": "two_color"}]
        },
        {
          "name": "fx",
          "states": [{"name": "sequence", "kind": "clip", "clip": "sequence"}]
        }
      ]
    }
  ]
}
""")
    writeFile(colorStateScriptPath, """{
  "format": "bony.input-script.v1",
  "asset": "bony_cli_harness_color_state.bony",
  "stateMachine": "color",
  "samples": [
    {"name": "alpha", "t": 0.1, "inputs": {}}
  ]
}
""")
    let stateGolden = runProcess(
      cliPath,
      [
        "golden-gen", stateAssetPath, stateGoldenPath,
        "--state-machine", "gesture",
        "--input-script", stateScriptPath,
        "--sample", "move",
      ],
    )
    let statePlay = runProcess(
      cliPath,
      [
        "play", stateAssetPath,
        "--state-machine", "gesture",
        "--input-script", stateScriptPath,
        "--out", stateFramePath,
        "--width", "16",
        "--height", "16",
      ],
    )
    let missingStateScript = runProcess(
      cliPath,
      ["golden-gen", stateAssetPath, stateGoldenPath, "--state-machine", "gesture", "--sample", "move"],
    )
    let missingStateSample = runProcess(
      cliPath,
      [
        "golden-gen", stateAssetPath, stateGoldenPath,
        "--state-machine", "gesture",
        "--input-script", stateScriptPath,
        "--sample", "missing",
      ],
    )
    let badStateScript = runProcess(
      cliPath,
      ["play", stateAssetPath, "--input-script", badStateScriptPath, "--out", stateFramePath],
    )
    let duplicateStateScript = runProcess(
      cliPath,
      [
        "golden-gen", stateAssetPath, stateGoldenPath,
        "--state-machine", "gesture",
        "--input-script", duplicateStateScriptPath,
        "--sample", "dup",
      ],
    )
    let numericStateScript = runProcess(
      cliPath,
      [
        "golden-gen", stateAssetPath, stateGoldenPath,
        "--state-machine", "gesture",
        "--input-script", numericStateScriptPath,
        "--sample", "1",
      ],
    )
    let colorStateGolden = runProcess(
      cliPath,
      [
        "golden-gen", colorStateAssetPath, colorStateGoldenPath,
        "--state-machine", "color",
        "--input-script", colorStateScriptPath,
        "--sample", "alpha",
      ],
    )
    let colorStatePlay = runProcess(
      cliPath,
      [
        "play", colorStateAssetPath,
        "--state-machine", "color",
        "--input-script", colorStateScriptPath,
        "--out", colorStateFramePath,
        "--width", "16",
        "--height", "16",
      ],
    )
    let stateTimeArg = runProcess(
      cliPath,
      ["play", stateAssetPath, "--state-machine", "gesture", "--input-script", stateScriptPath, "--out", stateFramePath, "--t", "0"],
    )
    let sampleWithoutInputScript = runProcess(
      cliPath,
      ["golden-gen", assetPath, goldenPath, "--t", "0", "--sample", "ignored"],
    )
    let stateJsonToBnb = runProcess(cliPath, ["json-to-bnb", stateAssetPath, stateBnbPath])
    let bnbStateMachine = runProcess(
      cliPath,
      [
        "golden-gen", stateBnbPath, stateGoldenPath,
        "--state-machine", "gesture",
        "--input-script", stateScriptPath,
        "--sample", "move",
      ],
    )
    createDir(lottieAssetsDir)
    writeFile(lottieAssetsDir / "body.png", "not decoded by Tier 1")
    writeFile(lottieAssetsDir / "hand.png", "not decoded by Tier 1")
    writeFile(lottiePath, """{
  "w": 100,
  "h": 80,
  "fr": 24,
  "ip": 0,
  "op": 24,
  "assets": [
    {"id": "bodyAsset", "path": "body.png", "w": 20, "h": 10},
    {"id": "handAsset", "path": "hand.png", "w": 8, "h": 6}
  ],
  "layers": [
    {
      "name": "hand",
      "kind": "image",
      "parent": 2,
      "transform": {
        "position": [5, 0],
        "scale": [50, 50]
      },
      "image": {"asset": "handAsset"}
    },
    {
      "name": "2",
      "kind": "image",
      "transform": {
        "position": [10, 10]
      },
      "image": {"asset": "bodyAsset"}
    },
    {
      "name": "body",
      "kind": "image",
      "transform": {
        "anchor": [10, 0],
        "position": [50, 40],
        "rotation": 30,
        "scale": [100, 100]
      },
      "image": {"asset": "bodyAsset"}
    }
  ]
}
""")
    let importLottie = runProcess(
      cliPath,
      ["import-lottie", lottiePath, lottieOutPath, "--assets-dir", lottieAssetsDir, "--setup-only"],
    )
    let lottieJsonToBnb = runProcess(cliPath, ["json-to-bnb", lottieOutPath, lottieBnbPath])
    let lottieBnbToJson = runProcess(cliPath, ["bnb-to-json", lottieBnbPath, lottieRoundTripPath])
    let imported = loadBonyJson(readFile(lottieRoundTripPath))
    let rejectOpacityPath = "/tmp/bony_cli_harness_lottie_opacity.json"
    let rejectShapePath = "/tmp/bony_cli_harness_lottie_shape.json"
    let rejectMissingPath = "/tmp/bony_cli_harness_lottie_missing.json"
    let rejectAnimatedPath = "/tmp/bony_cli_harness_lottie_animated.json"
    writeFile(rejectOpacityPath, """{"w":10,"h":10,"fr":24,"ip":0,"op":1,"assets":[{"id":"a","path":"body.png","w":1,"h":1}],"layers":[{"name":"faded","kind":"image","transform":{"opacity":50},"image":{"asset":"a"}}]}""")
    writeFile(rejectShapePath, """{"w":10,"h":10,"fr":24,"ip":0,"op":1,"layers":[{"name":"shape","kind":"shape","shapes":[]}]}""")
    writeFile(rejectMissingPath, """{"h":10,"fr":24,"ip":0,"op":1,"assets":[{"id":"a","path":"body.png","w":1,"h":1}],"layers":[{"name":"missing","kind":"image","image":{"asset":"a"}}]}""")
    writeFile(rejectAnimatedPath, """{"w":10,"h":10,"fr":24,"ip":0,"op":1,"assets":[{"id":"a","path":"body.png","w":1,"h":1}],"layers":[{"name":"animated","kind":"image","transform":{"position":[{"t":0,"v":[0,0]},{"t":1,"v":[1,1]}]},"image":{"asset":"a"}}]}""")
    let rejectedOpacity = runProcess(
      cliPath,
      ["import-lottie", rejectOpacityPath, "/tmp/bony_cli_harness_lottie_bad.bony", "--assets-dir", lottieAssetsDir],
    )
    let rejectedShape = runProcess(
      cliPath,
      ["import-lottie", rejectShapePath, "/tmp/bony_cli_harness_lottie_bad.bony", "--assets-dir", lottieAssetsDir],
    )
    let rejectedMissing = runProcess(
      cliPath,
      ["import-lottie", rejectMissingPath, "/tmp/bony_cli_harness_lottie_bad.bony", "--assets-dir", lottieAssetsDir],
    )
    let rejectedAnimated = runProcess(
      cliPath,
      ["import-lottie", rejectAnimatedPath, "/tmp/bony_cli_harness_lottie_bad.bony", "--assets-dir", lottieAssetsDir],
    )
    let goldenJson = parseJson(readFile(goldenPath))
    let stateGoldenJson = if fileExists(stateGoldenPath): parseJson(readFile(stateGoldenPath)) else: newJObject()
    let colorStateGoldenJson = if fileExists(colorStateGoldenPath): parseJson(readFile(colorStateGoldenPath)) else: newJObject()
    let stateImage = if fileExists(stateFramePath): decodeImage(readFile(stateFramePath)) else: newImage(1, 1)
    let colorStateImage = if fileExists(colorStateFramePath): decodeImage(readFile(colorStateFramePath)) else: newImage(1, 1)

    then:
      compileResult.exitCode == 0
      jsonToBnb.exitCode == 0
      bnbToJson.exitCode == 0
      golden.exitCode == 0
      play.exitCode == 0
      playTopLeft.exitCode == 0
      playBadOrigin.exitCode != 0
      playBadOrigin.output.contains("origin must be center or top-left")
      stateGolden.exitCode == 0
      statePlay.exitCode == 0
      stateGoldenJson["format"].getStr() == "bony.numeric-golden.v1"
      stateGoldenJson["stateMachine"].getStr() == "gesture"
      stateGoldenJson["sample"].getStr() == "move"
      stateGoldenJson["inputs"].elems.len == 3
      stateGoldenJson["layers"].elems.len == 2
      stateGoldenJson["layers"].elems[0]["state"].getStr() == "move"
      stateGoldenJson["events"].elems.len == 3
      stateGoldenJson["events"].elems[0]["listener"].getStr() == "idle_exit"
      closeTo(stateGoldenJson["layers"].elems[0]["pose"]["scalars"].elems[0]["value"].getFloat(), 10.0)
      stateImage.width == 64
      stateImage.height == 16
      missingStateScript.exitCode != 0
      missingStateScript.output.contains("requires --input-script")
      missingStateSample.exitCode != 0
      missingStateSample.output.contains("unknown input-script sample")
      badStateScript.exitCode != 0
      badStateScript.output.contains("samples require name")
      duplicateStateScript.exitCode != 0
      duplicateStateScript.output.contains("duplicate JSON object key: wave")
      numericStateScript.exitCode != 0
      numericStateScript.output.contains("numeric-only")
      colorStateGolden.exitCode == 0
      colorStatePlay.exitCode == 0
      colorStateGoldenJson["slots"].elems[0]["name"].getStr() == "body"
      closeTo(colorStateGoldenJson["slots"].elems[0]["a"].getFloat(), 0.5)
      closeTo(colorStateGoldenJson["drawBatches"].elems[0]["vertices"].elems[0]["a"].getFloat(), 0.5)
      colorStateGoldenJson["slots"].elems[1]["name"].getStr() == "glow"
      closeTo(colorStateGoldenJson["slots"].elems[1]["r"].getFloat(), 0.25)
      closeTo(colorStateGoldenJson["slots"].elems[1]["g"].getFloat(), 0.5)
      closeTo(colorStateGoldenJson["slots"].elems[1]["b"].getFloat(), 0.75)
      closeWithin(colorStateGoldenJson["slots"].elems[1]["a"].getFloat(), 0.8, 1e-6)
      closeWithin(colorStateGoldenJson["slots"].elems[1]["darkB"].getFloat(), 0.3, 1e-6)
      colorStateGoldenJson["slots"].elems[2]["name"].getStr() == "fx"
      colorStateGoldenJson["slots"].elems[2]["attachment"].getStr() == "fx_1"
      colorStateGoldenJson["slots"].elems[2]["sequenceIndex"].getInt() == 1
      colorStateGoldenJson["drawBatches"].elems[2]["attachment"].getStr() == "fx_1"
      colorStateImage.width == 16
      colorStateImage.height == 16
      colorStateImage[4, 8].a == 128
      stateTimeArg.exitCode != 0
      stateTimeArg.output.contains("--t cannot be combined")
      sampleWithoutInputScript.exitCode != 0
      sampleWithoutInputScript.output.contains("requires --input-script")
      stateJsonToBnb.exitCode == 0
      bnbStateMachine.exitCode == 0
      parseFile(stateGoldenPath)["stateMachine"].getStr() == "gesture"
      importLottie.exitCode == 0
      lottieJsonToBnb.exitCode == 0
      lottieBnbToJson.exitCode == 0
      unsupportedTime.exitCode != 0
      unsupportedTime.output.contains("--t is reserved")
      rejectedOpacity.exitCode != 0
      rejectedOpacity.output.contains("unsupportedFeature")
      rejectedOpacity.output.contains("capability=opacity")
      rejectedShape.exitCode != 0
      rejectedShape.output.contains("unsupportedFeature")
      rejectedShape.output.contains("capability=shape")
      rejectedMissing.exitCode != 0
      rejectedMissing.output.contains("schemaViolation")
      rejectedMissing.output.contains("missing required field: w")
      not rejectedMissing.output.contains("Traceback")
      rejectedAnimated.exitCode != 0
      rejectedAnimated.output.contains("unsupportedFeature")
      rejectedAnimated.output.contains("capability=position")
      fileExists(bnbPath)
      getFileSize(bnbPath) > 0
      loadBonyJson(readFile(roundTripPath)).header.name == "cli-demo"
      imported.header.name == "lottie-import"
      imported.bones.len == 4
      imported.bones[0].name == "composition"
      closeTo(imported.bones[0].local.x, -50.0)
      closeTo(imported.bones[0].local.y, -40.0)
      imported.bones[1].name == "body"
      imported.bones[1].parent == "composition"
      imported.bones[2].name == "hand"
      imported.bones[2].parent == "body"
      imported.bones[3].name == "2"
      imported.bones[3].parent == "composition"
      closeWithin(imported.bones[1].local.x, 41.34, 0.01)
      closeWithin(imported.bones[1].local.y, 35.0, 0.01)
      closeTo(imported.bones[1].local.rotation, 30.0)
      closeTo(imported.bones[2].local.x, 5.0)
      closeTo(imported.bones[2].local.scaleX, 0.5)
      imported.slots.len == 3
      imported.regions.len == 3
      closeTo(imported.regions[0].width, 8.0)
      closeTo(imported.regions[1].height, 10.0)
      closeTo(imported.regions[2].width, 20.0)
      goldenJson["format"].getStr() == "bony.numeric-golden.v1"
      goldenJson["time"].getFloat() == 0.0
      goldenJson["bones"].len == 2
      closeTo(goldenJson["bones"][0]["world"]["tx"].getFloat(), 2.0)
      closeTo(goldenJson["bones"][0]["world"]["ty"].getFloat(), 3.0)
      closeTo(goldenJson["bones"][1]["world"]["tx"].getFloat(), 6.0)
      closeTo(goldenJson["bones"][1]["world"]["ty"].getFloat(), 3.0)
      goldenJson["slots"].len == 1
      goldenJson["slots"][0]["name"].getStr() == "body"
      goldenJson["slots"][0]["attachment"].getStr() == "bodyRegion"
      goldenJson["slots"][0]["a"].getFloat() == 1.0
      goldenJson["drawBatches"].len == 1
      goldenJson["drawBatches"][0]["slot"].getStr() == "body"
      closeTo(goldenJson["drawBatches"][0]["vertices"][0]["x"].getFloat(), 5.0)
      closeTo(goldenJson["drawBatches"][0]["vertices"][0]["y"].getFloat(), 1.0)
      goldenJson["drawBatches"][0]["indices"].len == 6
      fileExists(framePath)
      getFileSize(framePath) > 0
      fileExists(frameTopLeftPath)
      readFile(framePath) != readFile(frameTopLeftPath)

    for path in [
      cliPath,
      assetPath,
      bnbPath,
      roundTripPath,
      goldenPath,
      framePath,
      frameTopLeftPath,
      stateScriptPath,
      badStateScriptPath,
      duplicateStateScriptPath,
      numericStateScriptPath,
      colorStateAssetPath,
      colorStateScriptPath,
      colorStateGoldenPath,
      colorStateFramePath,
      stateGoldenPath,
      stateFramePath,
      lottiePath,
      lottieOutPath,
      lottieBnbPath,
      lottieRoundTripPath,
      rejectOpacityPath,
      rejectShapePath,
      rejectMissingPath,
      rejectAnimatedPath,
      "/tmp/bony_cli_harness_lottie_bad.bony",
    ]:
      if fileExists(path):
        removeFile(path)
    if dirExists(lottieAssetsDir):
      removeDir(lottieAssetsDir)
