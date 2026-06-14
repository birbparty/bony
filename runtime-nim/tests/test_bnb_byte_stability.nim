import std/[os, osproc, sequtils, streams]

import bony

proc stringPayload(table: var BnbStringTable; value: string): seq[byte] =
  result.writeStringPayload(table, value)

proc f32Payload(value: float64): seq[byte] =
  let stored = float32(quantizeF32(value))
  let bits = cast[uint32](stored)
  @[
    byte(bits and 0xff'u32),
    byte((bits shr 8) and 0xff'u32),
    byte((bits shr 16) and 0xff'u32),
    byte((bits shr 24) and 0xff'u32),
  ]

proc boolPayload(value: bool): seq[byte] =
  if value:
    @[1'u8]
  else:
    @[0'u8]

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

proc viaJson(bytes: openArray[byte]): seq[byte] =
  toBonyBnb(loadBonyJson(toBonyJson(loadKnownBonyBnb(bytes))))

proc readBytes(path: string): seq[byte] =
  let content = readFile(path)
  result = newSeq[byte](content.len)
  for index, ch in content:
    result[index] = byte(ord(ch))

proc writeBytes(path: string; data: openArray[byte]) =
  var content = newString(data.len)
  for index, value in data:
    content[index] = char(value)
  writeFile(path, content)

proc runProcess(binary: string; args: openArray[string]): tuple[output: string; exitCode: int] =
  let process = startProcess(binary, args = args, options = {poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let exitCode = process.waitForExit()
  process.close()
  (output, exitCode)

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

echo ".bnb byte-stability gate passed"
