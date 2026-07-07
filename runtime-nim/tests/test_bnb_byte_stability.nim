import std/[os, osproc, sequtils]

import bony
import testutil

proc f32Payload(value: float64): seq[byte] =
  let stored = float32(quantizeF32(value))
  let bits = cast[uint32](stored)
  @[
    byte(bits and 0xff'u32),
    byte((bits shr 8) and 0xff'u32),
    byte((bits shr 16) and 0xff'u32),
    byte((bits shr 24) and 0xff'u32),
  ]

proc varintPayload(value: int): seq[byte] =
  result.writeVarint(int64(value))

proc f64Payload(value: float64): seq[byte] =
  let bits = cast[uint64](requireFiniteF64(value))
  for shift in countup(0, 56, 8):
    result.add byte((bits shr shift) and 0xff'u64)

proc currentModelFixture(): SkeletonData =
  skeletonData(
    skeletonHeader("demo", "0.2.0"),
    @[
      boneData("root", "", localTransform(x = -0.0, y = 2.5, rotation = 45.25)),
      boneData(
        "child",
        "root",
        localTransform(
          x = 3.25,
          inheritRotation = false,
          inheritScale = false,
          inheritReflection = false,
          transformMode = onlyTranslation,
        ),
      ),
    ],
    @[slotData("bodySlot", "root", "body")],
    @[regionAttachment("body", 8.0, 4.0)],
    @[pathAttachmentData("curve", 0.0, 0.0, 1.25, 2.5, 3.5, 4.75, 6.0, 7.25)],
    @[pathConstraintData("follow", "child", "root", "curve", order = -1)],
  )

proc extendedScalarAssetFixture(): BonyAsset =
  let bones = @[
    boneData("root", ""),
    boneData("tip", "root", localTransform(x = 2.0, y = 1.0), skinRequired = true),
  ]
  let meshBase = skeletonData(skeletonHeader("extended", "1.2.3"), bones)
  let cloth = unweightedMeshAttachment(
    meshBase,
    "cloth",
    @[meshUv(0.0, 0.0), meshUv(1.0, 0.0), meshUv(0.0, 1.0)],
    @[0'u16, 1'u16, 2'u16],
    @[unweightedMeshVertex(0.0, 0.0), unweightedMeshVertex(1.0, 0.0), unweightedMeshVertex(0.0, 1.0)],
  )
  let angle = parameterAxis("angle", -1.0, 1.0, 0.25)
  let warp = WarpLattice(
    rows: 2'u32,
    cols: 2'u32,
    minX: -1.0,
    minY: -1.0,
    maxX: 1.0,
    maxY: 1.0,
    controlPoints: @[
      deformerPoint(-1.0, -1.0),
      deformerPoint(1.0, -1.0),
      deformerPoint(-1.0, 1.0),
      deformerPoint(1.0, 1.0),
    ],
  )
  let skeleton = skeletonData(
    skeletonHeader("extended", "1.2.3"),
    bones,
    slots = @[
      slotData("maskSlot", "root", "mask"),
      slotData("regionSlot", "root", "body"),
      slotData("meshSlot", "root", "cloth"),
      slotData("hitSlot", "tip", "hit"),
      slotData("boxSlot", "tip", "bounds"),
    ],
    regions = @[regionAttachment("body", 2.0, 3.0)],
    pathAttachments = @[pathAttachmentData("curve", 0.0, 0.0, 1.0, 0.0, 1.5, 1.0, 2.0, 1.0)],
    paths = @[pathConstraintData(
      "follow", "tip", "root", "curve",
      skinRequired = true,
      hasPosition = true,
      position = 0.0,
      hasTranslateMix = true,
      translateMix = 1.0,
      hasRotateMix = true,
      rotateMix = 0.0,
    )],
    parameters = @[angle],
    deformers = @[
      DeformerRecord(
        deformer: warpDeformer("warp", warp),
        keyformBlend: keyformBlend(
          @[angle],
          @[
            pointKeyform(@[parameterSample(angle, -1.0)], warp.controlPoints),
            pointKeyform(@[parameterSample(angle, 1.0)], warp.controlPoints),
          ],
        ),
      ),
    ],
    ikConstraints = @[ikConstraintData(
      "ik",
      "root",
      @["tip"],
      skinRequired = true,
      hasMix = true,
      mix = 1.0,
      hasBendPositive = true,
      bendPositive = true,
    )],
    transformConstraints = @[transformConstraintData(
      "tc",
      "tip",
      "root",
      skinRequired = true,
      hasTranslateMix = true,
      translateMix = 1.0,
      hasRotateMix = true,
      rotateMix = 1.0,
      hasScaleMix = true,
      scaleMix = 1.0,
      hasShearMix = true,
      shearMix = 1.0,
    )],
    physicsConstraints = @[physicsConstraintData(
      "pc",
      "tip",
      {pcX, pcRotate},
      skinRequired = true,
      hasInertia = true,
      inertia = 0.0,
      hasStrength = true,
      strength = 0.0,
      hasDamping = true,
      damping = 0.0,
      hasMass = true,
      mass = 1.0,
      hasGravity = true,
      gravity = 0.0,
      hasWind = true,
      wind = 0.0,
      hasMix = true,
      mix = 1.0,
    )],
    clippingAttachments = @[clipAttachmentData("mask", @[0.0, -1.0, 2.0, -1.0, 2.0, 2.0, 0.0, 2.0], "meshSlot")],
    meshAttachments = @[cloth],
    skins = @[
      skinData(
        "default",
        @[
          skinEntryData("maskSlot", "mask", "mask"),
          skinEntryData("regionSlot", "body", "body"),
          skinEntryData("meshSlot", "cloth", "cloth"),
          skinEntryData("hitSlot", "hit", "hit"),
          skinEntryData("boxSlot", "bounds", "bounds"),
        ],
        bones = @["tip"],
        ikConstraints = @["ik"],
        transformConstraints = @["tc"],
        pathConstraints = @["follow"],
        physicsConstraints = @["pc"],
      ),
    ],
    pointAttachments = @[pointAttachmentData("hit", 1.0, 0.0, 0.0)],
    boundingBoxAttachments = @[boundingBoxAttachmentData("bounds", @[-1.0, -1.0, 1.0, -1.0, 1.0, 1.0])],
    nestedRigAttachments = @[nestedRigAttachmentData("nested", "childSkeleton", skin = "default", animation = "idle")],
  )
  let deform = deformTimeline("default", "meshSlot", cloth, @[deformKeyframe(0.0, 0'u32, @[meshDelta(0.0, 0.0)])])
  let idle = animationClip(skeleton, "idle", deformTimelines = @[deform])
  let machine = stateMachine(
    "machine",
    @[
      stateMachineLayer(
        "main",
        @[
          stateMachineState("idle", idle),
          stateMachineBlendState("blend", "level", @[stateMachineBlendClip(idle, 0.0)]),
        ],
        initialState = "blend",
        transitions = @[
          stateMachineTransition("idle", "blend", @[stateMachineNumberCondition("level", numberEqualsCondition, 0.0)]),
          stateMachineTransition("blend", "idle", @[stateMachineBoolCondition("pressed", true)]),
        ],
      ),
    ],
    inputs = @[
      stateMachineBoolInput("pressed"),
      stateMachineNumberInput("level"),
      stateMachineTriggerInput("pulse"),
    ],
    listeners = @[
      stateMachineStateEnterListener("enter_blend", "main", "blend"),
      stateMachineTransitionListener("idle_to_blend", "main", "idle", "blend"),
      stateMachinePointerListener(
        "press_false",
        pointerDownListener,
        "hitSlot",
        pointHelperTarget,
        "hit",
        "pressed",
        hitRadius = 0.0,
        hasHitRadius = true,
        boolValue = false,
        hasBoolValue = true,
      ),
      stateMachinePointerListener(
        "level_zero",
        pointerMoveListener,
        "hitSlot",
        pointHelperTarget,
        "hit",
        "level",
        hitRadius = 0.0,
        hasHitRadius = true,
        numberValue = 0.0,
        hasNumberValue = true,
      ),
    ],
  )
  bonyAsset(skeleton, @[idle], @[machine])

proc viaJson(bytes: openArray[byte]): seq[byte] =
  toBonyBnb(loadBonyJson(toBonyJson(loadKnownBonyBnb(bytes))))

proc viaJsonAsset(bytes: openArray[byte]): seq[byte] =
  toBonyBnb(loadBonyJsonAsset(toBonyJson(loadKnownBonyBnbAsset(bytes))))
proc writeBytes(path: string; data: openArray[byte]) =
  var content = newString(data.len)
  for index, value in data:
    content[index] = char(value)
  writeFile(path, content)

proc expectStable(name: string; bytes: seq[byte]) =
  let cycled = viaJson(bytes)
  doAssert cycled == bytes, name & " changed after bnb->json->bnb"

proc expectCanonicalizes(name: string; bytes, canonical: seq[byte]) =
  let cycled = viaJson(bytes)
  doAssert cycled == canonical, name & " did not canonicalize to expected bytes"
  doAssert viaJson(cycled) == cycled, name & " canonicalized bytes are not stable"

proc readPropertyKeys(input: openArray[byte]; index: var int): seq[uint64] =
  while true:
    let propertyKey = input.readVaruint(index)
    if propertyKey == 0:
      return
    let byteLength = input.readVaruint(index)
    doAssert byteLength <= uint64(input.len - index), "property byteLength exceeds input"
    result.add propertyKey
    index += int(byteLength)

type ObjectPropertyShape = tuple[typeKey: uint64, propertyKeys: seq[uint64]]

proc objectPropertyShapes(bytes: openArray[byte]): seq[ObjectPropertyShape] =
  var index = 0
  let header = bytes.readHeader(index)
  doAssert header.flags == bnbStringTableFlag
  discard bytes.readToc(index)
  discard bytes.readStringTable(index)
  while true:
    let typeKey = bytes.readVaruint(index)
    if typeKey == 0:
      break
    result.add (typeKey: typeKey, propertyKeys: bytes.readPropertyKeys(index))
  doAssert index == bytes.len, "shape inspection must consume canonical .bnb"

proc inspectCanonicalCurrentModel(bytes: openArray[byte]) =
  var index = 0
  let header = bytes.readHeader(index)
  doAssert header.flags == bnbStringTableFlag
  let toc = bytes.readToc(index)
  var previous = 0'u64
  for itemIndex, item in toc:
    if itemIndex > 0:
      doAssert previous < item.propertyKey, "ToC keys must be strictly ascending"
    previous = item.propertyKey
  doAssert toc.mapIt(it.propertyKey) == @[
    1'u64,
    2'u64,
    3'u64,
    1000'u64,
    1001'u64,
    1002'u64,
    1007'u64,
    1008'u64,
    1009'u64,
    1010'u64,
    1012'u64,
    1013'u64,
    1014'u64,
    1015'u64,
    4000'u64,
    4001'u64,
    4002'u64,
    4003'u64,
    4004'u64,
    4005'u64,
    4006'u64,
    4007'u64,
    4008'u64,
    4009'u64,
    4010'u64,
  ]
  let strings = bytes.readStringTable(index)
  doAssert strings.values == @[
    "demo",
    "0.2.0",
    "root",
    "child",
    "onlyTranslation",
    "bodySlot",
    "body",
    "curve",
    "follow",
  ]

  doAssert bytes.readVaruint(index) == 1
  doAssert bytes.readPropertyKeys(index) == @[1'u64, 2'u64]
  doAssert bytes.readVaruint(index) == 2
  doAssert bytes.readPropertyKeys(index) == @[1'u64, 1001'u64, 1002'u64]
  doAssert bytes.readVaruint(index) == 2
  doAssert bytes.readPropertyKeys(index) == @[1'u64, 3'u64, 1000'u64, 1007'u64, 1008'u64, 1009'u64, 1010'u64]
  doAssert bytes.readVaruint(index) == 1000
  doAssert bytes.readPropertyKeys(index) == @[1'u64, 1012'u64, 1013'u64]
  doAssert bytes.readVaruint(index) == 1001
  doAssert bytes.readPropertyKeys(index) == @[1'u64, 1014'u64, 1015'u64]
  doAssert bytes.readVaruint(index) == 4001
  doAssert bytes.readPropertyKeys(index) == @[
    1'u64,
    4003'u64,
    4004'u64,
    4005'u64,
    4006'u64,
    4007'u64,
    4008'u64,
    4009'u64,
    4010'u64,
  ]
  doAssert bytes.readVaruint(index) == 4000
  doAssert bytes.readPropertyKeys(index) == @[1'u64, 1012'u64, 4000'u64, 4001'u64, 4002'u64]
  doAssert bytes.readVaruint(index) == 0
  doAssert index == bytes.len, "canonical .bnb must not contain trailing bytes"

proc inspectExtendedScalarAsset(bytes: openArray[byte]) =
  let actual = objectPropertyShapes(bytes)
  let expected: seq[ObjectPropertyShape] = @[
    (1'u64, @[1'u64, 2'u64]),
    (2'u64, @[1'u64]),
    (2'u64, @[1'u64, 3'u64, 1000'u64, 1001'u64, 4027'u64]),
    (1000'u64, @[1'u64, 1012'u64, 1013'u64]),
    (1000'u64, @[1'u64, 1012'u64, 1013'u64]),
    (1000'u64, @[1'u64, 1012'u64, 1013'u64]),
    (1000'u64, @[1'u64, 1012'u64, 1013'u64]),
    (1000'u64, @[1'u64, 1012'u64, 1013'u64]),
    (1001'u64, @[1'u64, 1014'u64, 1015'u64]),
    (1002'u64, @[1'u64, 1000'u64, 1001'u64, 1002'u64]),
    (1003'u64, @[1'u64, 3000'u64]),
    (4001'u64, @[1'u64, 4003'u64, 4004'u64, 4005'u64, 4006'u64, 4007'u64, 4008'u64, 4009'u64, 4010'u64]),
    (3000'u64, @[1'u64, 3000'u64, 3001'u64]),
    (3001'u64, @[1'u64, 3003'u64, 3004'u64, 3005'u64]),
    (3005'u64, @[1'u64, 3012'u64, 3013'u64, 3014'u64]),
    (4002'u64, @[1'u64, 4000'u64, 4014'u64, 4015'u64, 4016'u64, 4027'u64]),
    (4003'u64, @[1'u64, 1012'u64, 4000'u64, 4012'u64, 4013'u64, 4017'u64, 4018'u64, 4027'u64]),
    (4000'u64, @[1'u64, 1012'u64, 4000'u64, 4001'u64, 4011'u64, 4012'u64, 4013'u64, 4027'u64]),
    (4004'u64, @[1'u64, 1012'u64, 4019'u64, 4020'u64, 4021'u64, 4022'u64, 4023'u64, 4024'u64, 4025'u64, 4026'u64, 4027'u64]),
    (3003'u64, @[1'u64, 4028'u64, 4029'u64, 4030'u64, 4031'u64, 4032'u64]),
    (3004'u64, @[1011'u64, 3010'u64, 3011'u64]),
    (3004'u64, @[1011'u64, 3010'u64, 3011'u64]),
    (3004'u64, @[1011'u64, 3010'u64, 3011'u64]),
    (3004'u64, @[1011'u64, 3010'u64, 3011'u64]),
    (3004'u64, @[1011'u64, 3010'u64, 3011'u64]),
    (6000'u64, @[1'u64, 6000'u64, 6001'u64, 6002'u64]),
    (6001'u64, @[6010'u64, 6012'u64]),
    (6002'u64, @[6022'u64, 6023'u64, 6024'u64, 6025'u64, 6026'u64]),
    (6004'u64, @[6040'u64, 6041'u64]),
    (6005'u64, @[6042'u64, 6043'u64]),
    (6005'u64, @[6042'u64, 6043'u64]),
    (2000'u64, @[1'u64]),
    (3002'u64, @[1011'u64, 3006'u64, 3007'u64, 3008'u64, 3009'u64]),
    (7000'u64, @[1'u64]),
    (7001'u64, @[1'u64, 7000'u64]),
    (7001'u64, @[1'u64, 7000'u64]),
    (7001'u64, @[1'u64, 7000'u64]),
    (7002'u64, @[1'u64, 7010'u64]),
    (7003'u64, @[1'u64, 7020'u64, 7021'u64]),
    (7003'u64, @[1'u64, 7020'u64, 7023'u64]),
    (7004'u64, @[7030'u64, 7031'u64]),
    (7005'u64, @[7040'u64, 7041'u64]),
    (7006'u64, @[7050'u64, 7051'u64, 7053'u64]),
    (7005'u64, @[7040'u64, 7041'u64]),
    (7006'u64, @[7050'u64, 7051'u64]),
    (7007'u64, @[1'u64, 7060'u64, 7061'u64, 7063'u64]),
    (7007'u64, @[1'u64, 7060'u64, 7061'u64, 7062'u64, 7063'u64]),
    (7007'u64, @[1'u64, 7060'u64, 7064'u64, 7065'u64, 7066'u64, 7067'u64, 7068'u64, 7070'u64]),
    (7007'u64, @[1'u64, 7060'u64, 7064'u64, 7065'u64, 7066'u64, 7067'u64, 7069'u64, 7070'u64]),
  ]
  doAssert actual == expected, $actual

proc expectEmitRejectsInvalidUnicode() =
  try:
    discard toBonyBnb(skeletonData(skeletonHeader("\xff", "0.1.0"), @[boneData("root", "")]))
    raise newException(AssertionDefect, "invalid unicode emitted")
  except BonyLoadError as exc:
    doAssert exc.kind == schemaViolation

proc expectCliRoundTrip(canonical: seq[byte]) =
  let cliPath = "/tmp/bony_bnb_byte_stability_cli"
  let inputPath = "/tmp/bony_bnb_byte_stability_input.bnb"
  let jsonPath = "/tmp/bony_bnb_byte_stability_output.bony"
  let outputPath = "/tmp/bony_bnb_byte_stability_output.bnb"
  for path in [cliPath, inputPath, jsonPath, outputPath]:
    if fileExists(path):
      removeFile(path)

  let compileResult = execCmdEx(
    "nim c --path:src --path:../../bddy/src -o:" & cliPath & " ../cli/bony_cli.nim",
    options = {poStdErrToStdOut},
  )
  doAssert compileResult.exitCode == 0, compileResult.output
  writeBytes(inputPath, canonical)
  let toJson = runProcess(cliPath, ["bnb-to-json", inputPath, jsonPath])
  doAssert toJson.exitCode == 0, toJson.output
  let toBnb = runProcess(cliPath, ["json-to-bnb", jsonPath, outputPath])
  doAssert toBnb.exitCode == 0, toBnb.output
  doAssert readBytes(outputPath) == canonical, "CLI bnb->json->bnb changed canonical bytes"

  for path in [cliPath, inputPath, jsonPath, outputPath]:
    if fileExists(path):
      removeFile(path)

proc nonCanonicalCurrentModelBytes(): seq[byte] =
  var table = initStringTable()
  let demo = table.stringPayload("demo")
  let version = table.stringPayload("0.2.0")
  let root = table.stringPayload("root")
  let child = table.stringPayload("child")
  let onlyTranslationName = table.stringPayload("onlyTranslation")
  let bodySlot = table.stringPayload("bodySlot")
  let body = table.stringPayload("body")
  let curve = table.stringPayload("curve")
  let follow = table.stringPayload("follow")

  result.writeHeader(flags = bnbStringTableFlag)
  result.writeVaruint(25)
  for entry in [
    BnbTocEntry(propertyKey: 4010, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4009, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4008, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4007, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4006, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4005, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4004, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4003, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4002, backingTypeCode: backingTypeCode("varint")),
    BnbTocEntry(propertyKey: 4001, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 4000, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1015, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 1014, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 1013, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1012, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1010, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1009, backingTypeCode: backingTypeCode("bool")),
    BnbTocEntry(propertyKey: 1008, backingTypeCode: backingTypeCode("bool")),
    BnbTocEntry(propertyKey: 1007, backingTypeCode: backingTypeCode("bool")),
    BnbTocEntry(propertyKey: 1002, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 1001, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 1000, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 3, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 2, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
  ]:
    result.writeVaruint(entry.propertyKey)
    result.add entry.backingTypeCode
  result.writeStringTable(table)

  result.writeVaruint(1)
  result.writePropertyRecord(2, version)
  result.writePropertyRecord(1, demo)
  result.writePropertyTerminator()

  result.writeVaruint(2)
  result.writePropertyRecord(1002, f32Payload(45.25))
  result.writePropertyRecord(1001, f32Payload(2.5))
  result.writePropertyRecord(1, root)
  result.writePropertyTerminator()

  result.writeVaruint(2)
  result.writePropertyRecord(1010, onlyTranslationName)
  result.writePropertyRecord(1009, boolPayload(false))
  result.writePropertyRecord(1008, boolPayload(false))
  result.writePropertyRecord(1007, boolPayload(false))
  result.writePropertyRecord(1000, f32Payload(3.25))
  result.writePropertyRecord(3, root)
  result.writePropertyRecord(1, child)
  result.writePropertyTerminator()

  result.writeVaruint(1000)
  result.writePropertyRecord(1013, body)
  result.writePropertyRecord(1012, root)
  result.writePropertyRecord(1, bodySlot)
  result.writePropertyTerminator()

  result.writeVaruint(1001)
  result.writePropertyRecord(1015, f32Payload(4.0))
  result.writePropertyRecord(1014, f32Payload(8.0))
  result.writePropertyRecord(1, body)
  result.writePropertyTerminator()

  result.writeVaruint(4001)
  result.writePropertyRecord(4010, f64Payload(7.25))
  result.writePropertyRecord(4009, f64Payload(6.0))
  result.writePropertyRecord(4008, f64Payload(4.75))
  result.writePropertyRecord(4007, f64Payload(3.5))
  result.writePropertyRecord(4006, f64Payload(2.5))
  result.writePropertyRecord(4005, f64Payload(1.25))
  result.writePropertyRecord(4004, f64Payload(0.0))
  result.writePropertyRecord(4003, f64Payload(0.0))
  result.writePropertyRecord(1, curve)
  result.writePropertyTerminator()

  result.writeVaruint(4000)
  result.writePropertyRecord(4002, varintPayload(-1))
  result.writePropertyRecord(4001, curve)
  result.writePropertyRecord(4000, root)
  result.writePropertyRecord(1012, child)
  result.writePropertyRecord(1, follow)
  result.writePropertyTerminator()

  result.writeObjectStreamTerminator()

let canonical = toBonyBnb(currentModelFixture())
expectStable("canonical current model fixture", canonical)
inspectCanonicalCurrentModel(canonical)
expectCanonicalizes("non-canonical toc and property order", nonCanonicalCurrentModelBytes(), canonical)
expectCliRoundTrip(canonical)

let minimal = toBonyBnb(skeletonData(skeletonHeader("minimal", "0.1.0"), @[boneData("root", "")]))
expectStable("default omission fixture", minimal)
expectEmitRejectsInvalidUnicode()

let extendedAsset = toBonyBnb(extendedScalarAssetFixture())
doAssert viaJsonAsset(extendedAsset) == extendedAsset, "extended scalar asset changed after bnb->json->bnb"
inspectExtendedScalarAsset(extendedAsset)

echo ".bnb byte-stability gate passed"

include smoke_support

spec "bnb committed fixture smoke coverage":
  it "round trips SkeletonData through canonical .bnb":
    let source = loadBonyJson("""
{
  "bones": [
    {
      "scaleY": 2,
      "name": "root",
      "x": 0.1000000001
    },
    {
      "parent": "root",
      "name": "child",
      "inheritRotation": false,
      "inheritScale": false,
      "inheritReflection": false,
      "transformMode": "onlyTranslation"
    }
  ],
  "regions": [
    {
      "height": 4,
      "name": "body",
      "width": 8
    }
  ],
  "slots": [
    {
      "attachment": "body",
      "bone": "root",
      "name": "bodySlot"
    }
  ],
  "skeleton": {
    "version": "0.2.0",
    "name": "demo"
  }
}
""")
    let bnbBytes = toBonyBnb(source)
    let decoded = loadBonyBnb(bnbBytes)
    let decodedJson = toBonyJson(decoded)
    let stableBytes = toBonyBnb(loadBonyJson(decodedJson))

    then:
      decodedJson == toBonyJson(source)
      stableBytes == bnbBytes

    var index = 0
    let header = bnbBytes.readHeader(index)
    let toc = bnbBytes.readToc(index)
    let strings = bnbBytes.readStringTable(index)

    then:
      header.flags == bnbStringTableFlag
      toc.len == 13
      toc[0].propertyKey == 1
      toc[^1].propertyKey == 1015
      strings.values == @[
        "demo",
        "0.2.0",
        "root",
        "child",
        "onlyTranslation",
        "bodySlot",
        "body",
      ]

  it "loads .bnb while skipping unknown objects":
    var table = initStringTable()
    var namePayload: seq[byte]
    namePayload.writeStringPayload(table, "demo")
    var bytes: seq[byte]
    bytes.writeHeader(flags = bnbStringTableFlag)
    bytes.writeToc(@[
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 900000, backingTypeCode: backingTypeCode("bytes")),
    ])
    bytes.writeStringTable(table)
    bytes.writeObjectRecord(999999, @[BnbPropertyRecord(propertyKey: 900000, payload: @[1'u8, 2'u8])])
    bytes.writeObjectRecord(1, @[BnbPropertyRecord(propertyKey: 1, payload: namePayload)])
    bytes.writeObjectStreamTerminator()

    let loaded = loadBonyBnb(bytes)

    then:
      toBonyJson(loaded) == """{
  "skeleton": {
    "name": "demo"
  },
  "bones": [],
  "slots": [],
  "regions": []
}
"""
      raisesBonyLoadError(proc() = discard loadKnownBonyBnb(bytes), schemaViolation)

  it "loads committed forward-compat fixture skipping the unknown object":
    let path = repoPath("conformance", "assets", "bnb", "forward_compat.bnb")
    let fixture = cast[seq[byte]](readFile(path))
    let data = loadBonyBnb(fixture)
    then:
      data.header.name == "m6-compat"
      data.bones.len == 1
      data.bones[0].name == "root"
      raisesBonyLoadError(proc() = discard loadKnownBonyBnb(fixture), schemaViolation)

  it "loads all committed m*_rig.bnb conformance fixtures":
    let bnbDir = repoPath("conformance", "assets", "bnb")
    var loaded = 0
    for entry in walkDir(bnbDir):
      if entry.kind == pcFile and entry.path.endsWith("_rig.bnb"):
        let fixture = cast[seq[byte]](readFile(entry.path))
        discard loadBonyBnb(fixture)
        inc loaded
    then:
      loaded == 27  # m1–m5, m5_ik, m5_transform, m5_physics, m7, m8, m9_non_scalar, m11_clip, m12_mesh, m13_mesh_deform, m14_mesh_warp, m15_mesh_unweighted_deform, m16_mesh_multi_deform, m17_mesh_clip, m18_mesh_deform_anim, m19_event, m20_skin, m21_pointer_listener, m22_skin_required, m23_nested, m23_nested_child, m24_atlas_region, m25_draw_order
