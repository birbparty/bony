import std/[os, osproc, streams]

import bony

const mixedOrderFixture = """
{
  "pathAttachments": [
    {
      "p3y": 6.25,
      "p3x": 5.5,
      "p2y": 4,
      "p2x": 3,
      "p1y": 2,
      "p1x": 0.10000000000000001,
      "p0y": 1e3,
      "p0x": -0,
      "name": "curve"
    }
  ],
  "regions": [
    {"height": 4.5, "width": 0.1000000001, "name": "body"}
  ],
  "slots": [
    {"attachment": "body", "bone": "child", "name": "bodySlot"}
  ],
  "paths": [
    {"order": -2, "path": "curve", "target": "root", "bone": "child", "name": "follow"}
  ],
  "bones": [
    {
      "transformMode": "normal",
      "inheritReflection": true,
      "inheritScale": true,
      "inheritRotation": true,
      "shearY": 0,
      "shearX": 0,
      "scaleY": 1,
      "scaleX": 1,
      "rotation": 45.2500000001,
      "y": 1e-3,
      "x": -0,
      "parent": "",
      "name": "root"
    },
    {
      "transformMode": "onlyTranslation",
      "inheritReflection": false,
      "inheritScale": false,
      "inheritRotation": false,
      "x": 3.25,
      "parent": "root",
      "name": "child"
    }
  ],
  "skeleton": {"version": "0.2.0", "name": "demo"}
}
"""

const canonicalFixture = """{
  "skeleton": {
    "name": "demo",
    "version": "0.2.0"
  },
  "bones": [
    {
      "name": "root",
      "y": 0.0010000000474974513,
      "rotation": 45.25
    },
    {
      "name": "child",
      "parent": "root",
      "x": 3.25,
      "inheritRotation": false,
      "inheritScale": false,
      "inheritReflection": false,
      "transformMode": "onlyTranslation"
    }
  ],
  "slots": [
    {
      "name": "bodySlot",
      "bone": "child",
      "attachment": "body"
    }
  ],
  "regions": [
    {
      "name": "body",
      "width": 0.10000000149011612,
      "height": 4.5
    }
  ],
  "pathAttachments": [
    {
      "name": "curve",
      "p0x": 0.0,
      "p0y": 1000.0,
      "p1x": 0.1,
      "p1y": 2.0,
      "p2x": 3.0,
      "p2y": 4.0,
      "p3x": 5.5,
      "p3y": 6.25
    }
  ],
  "paths": [
    {
      "name": "follow",
      "bone": "child",
      "target": "root",
      "path": "curve",
      "order": -2
    }
  ]
}
"""

proc canonicalJson(text: string): string =
  toBonyJson(loadBonyJson(text))

proc viaBnb(text: string): string =
  toBonyJson(loadKnownBonyBnb(toBonyBnb(loadBonyJson(text))))

proc readBytes(path: string): seq[byte] =
  let content = readFile(path)
  result = newSeq[byte](content.len)
  for index, ch in content:
    result[index] = byte(ord(ch))

proc runProcess(binary: string; args: openArray[string]): tuple[output: string; exitCode: int] =
  let process = startProcess(binary, args = args, options = {poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let exitCode = process.waitForExit()
  process.close()
  (output, exitCode)

proc expectJsonBnbJsonIdempotent(name, input, expected: string) =
  let canonical = canonicalJson(input)
  doAssert canonical == expected, name & " did not canonicalize to expected JSON"
  let cycled = viaBnb(input)
  doAssert cycled == canonical, name & " changed after json->bnb->json"
  doAssert canonicalJson(cycled) == cycled, name & " canonical JSON is not stable"

proc expectDefaultsReapplied() =
  let explicitDefaults = """{
  "skeleton": {"name": "defaults", "version": "0.1.0"},
  "bones": [
    {
      "name": "root",
      "parent": "",
      "x": 0,
      "y": 0,
      "rotation": -0,
      "scaleX": 1,
      "scaleY": 1,
      "shearX": 0,
      "shearY": 0,
      "inheritRotation": true,
      "inheritScale": true,
      "inheritReflection": true,
      "transformMode": "normal"
    }
  ],
  "slots": [],
  "regions": []
}
"""
  let omittedDefaults = """{"skeleton":{"name":"defaults"},"bones":[{"name":"root"}],"slots":[],"regions":[]}"""
  doAssert canonicalJson(explicitDefaults) == canonicalJson(omittedDefaults)
  doAssert viaBnb(explicitDefaults) == canonicalJson(omittedDefaults)

proc expectAngleBoundaryPreserved() =
  let data = loadBonyJson(mixedOrderFixture)
  let cycled = loadBonyJson(viaBnb(mixedOrderFixture))
  doAssert data.bones[0].local.rotation == cycled.bones[0].local.rotation

proc expectCliRoundTrip(expected: string) =
  let cliPath = "/tmp/bony_json_idempotency_cli"
  let inputPath = "/tmp/bony_json_idempotency_input.bony"
  let bnbPath = "/tmp/bony_json_idempotency_output.bnb"
  let outputPath = "/tmp/bony_json_idempotency_output.bony"
  for path in [cliPath, inputPath, bnbPath, outputPath]:
    if fileExists(path):
      removeFile(path)

  let compileResult = execCmdEx(
    "nim c --path:src --path:~/git/bddy/src -o:" & cliPath & " ../cli/bony_cli.nim",
    options = {poStdErrToStdOut},
  )
  doAssert compileResult.exitCode == 0, compileResult.output
  writeFile(inputPath, mixedOrderFixture)
  let toBnb = runProcess(cliPath, ["json-to-bnb", inputPath, bnbPath])
  doAssert toBnb.exitCode == 0, toBnb.output
  doAssert readBytes(bnbPath).len > 0
  let toJson = runProcess(cliPath, ["bnb-to-json", bnbPath, outputPath])
  doAssert toJson.exitCode == 0, toJson.output
  doAssert readFile(outputPath) == expected, "CLI json->bnb->json changed canonical JSON"

  for path in [cliPath, inputPath, bnbPath, outputPath]:
    if fileExists(path):
      removeFile(path)

expectJsonBnbJsonIdempotent("mixed-order numeric fixture", mixedOrderFixture, canonicalFixture)
expectDefaultsReapplied()
expectAngleBoundaryPreserved()
expectCliRoundTrip(canonicalFixture)

echo "json->bnb->json idempotency gate passed"
