import std/[os, osproc]

import bony
import testutil

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
  "paths": [
    {
      "name": "follow",
      "bone": "child",
      "target": "root",
      "path": "curve",
      "order": -2
    }
  ],
  "pathAttachments": [
    {
      "name": "curve",
      "p0x": 0,
      "p0y": 1000,
      "p1x": 0.1,
      "p1y": 2,
      "p2x": 3,
      "p2y": 4,
      "p3x": 5.5,
      "p3y": 6.25
    }
  ]
}
"""

# IK constraint fixture (bony-me5.8). Mixed key order + a full ikConstraints
# entry with non-default order/mix/bendPositive so every emitted IK field is
# exercised on the round-trip. This is an in-test temporary fixture only — it is
# NOT a committed conformance asset. IK conformance fixtures arrive in step 3
# (bony-grr); scripts/ci/round_trip_run.py does not cover IK yet.
const ikMixedOrderFixture = """
{
  "ikConstraints": [
    {
      "bendPositive": false,
      "mix": 0.5,
      "order": 1,
      "target": "goal",
      "bones": ["b0", "b1"],
      "name": "ik"
    }
  ],
  "bones": [
    {"name": "root"},
    {"name": "b0", "parent": "root", "x": 10},
    {"name": "b1", "parent": "b0", "x": 10},
    {"name": "goal", "parent": "root", "x": 20, "y": 5}
  ],
  "skeleton": {"name": "ikdemo", "version": "0.2.0"}
}
"""

const ikCanonicalFixture = """{
  "skeleton": {
    "name": "ikdemo",
    "version": "0.2.0"
  },
  "bones": [
    {
      "name": "root"
    },
    {
      "name": "b0",
      "parent": "root",
      "x": 10
    },
    {
      "name": "b1",
      "parent": "b0",
      "x": 10
    },
    {
      "name": "goal",
      "parent": "root",
      "x": 20,
      "y": 5
    }
  ],
  "slots": [],
  "regions": [],
  "ikConstraints": [
    {
      "name": "ik",
      "bones": ["b0", "b1"],
      "target": "goal",
      "order": 1,
      "mix": 0.5,
      "bendPositive": false
    }
  ]
}
"""

# Companion IK fixture that omits mix/order/bendPositive so every optional field
# takes its default-omit emit path (hasMix = false, order == default, bendPositive
# == default). Together with ikMixedOrderFixture this exercises both the
# all-fields-present and all-defaults-omitted IK emit gates on the round-trip.
const ikOmitFixture = """
{
  "skeleton": {"name": "ikmin", "version": "0.2.0"},
  "bones": [
    {"name": "root"},
    {"name": "b0", "parent": "root", "x": 10},
    {"name": "goal", "parent": "root", "x": 20}
  ],
  "ikConstraints": [
    {"name": "ik", "bones": ["b0"], "target": "goal"}
  ]
}
"""

const ikOmitCanonicalFixture = """{
  "skeleton": {
    "name": "ikmin",
    "version": "0.2.0"
  },
  "bones": [
    {
      "name": "root"
    },
    {
      "name": "b0",
      "parent": "root",
      "x": 10
    },
    {
      "name": "goal",
      "parent": "root",
      "x": 20
    }
  ],
  "slots": [],
  "regions": [],
  "ikConstraints": [
    {
      "name": "ik",
      "bones": ["b0"],
      "target": "goal"
    }
  ]
}
"""

proc viaBnb(text: string): string =
  toBonyJson(loadKnownBonyBnb(toBonyBnb(loadBonyJson(text))))

proc expectJsonBnbJsonIdempotent(name, input, expected: string) =
  let canonical = canonicalJson(input)
  doAssert canonical == expected, name & " did not canonicalize to expected JSON"
  let cycled = viaBnb(input)
  doAssert cycled == canonical, name & " changed after json->bnb->json"
  doAssert canonicalJson(cycled) == cycled, name & " canonical JSON is not stable"

proc expectDefaultsReapplied() =
  const expected = """{
  "skeleton": {
    "name": "defaults"
  },
  "bones": [
    {
      "name": "root"
    }
  ],
  "slots": [],
  "regions": []
}
"""
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
  doAssert canonicalJson(explicitDefaults) == expected
  doAssert canonicalJson(omittedDefaults) == expected
  doAssert viaBnb(explicitDefaults) == expected

proc expectAngleBoundaryPreserved() =
  let data = loadBonyJson(mixedOrderFixture)
  let cycled = loadBonyJson(viaBnb(mixedOrderFixture))
  doAssert data.bones[0].local.rotation == cycled.bones[0].local.rotation
  doAssert abs(data.bones[0].local.rotation - cycled.bones[0].local.rotation) <= 1e-4

proc compileCli(cliPath: string) =
  if fileExists(cliPath):
    removeFile(cliPath)
  let compileResult = execCmdEx(
    "nim c --path:src --path:" & getHomeDir() / "git/bddy/src" & " -o:" & cliPath & " ../cli/bony_cli.nim",
    options = {poStdErrToStdOut},
  )
  doAssert compileResult.exitCode == 0, compileResult.output

proc expectCliRoundTrip(cliPath, fixture, expected: string) =
  let inputPath = "/tmp/bony_json_idempotency_input.bony"
  let bnbPath = "/tmp/bony_json_idempotency_output.bnb"
  let outputPath = "/tmp/bony_json_idempotency_output.bony"
  for path in [inputPath, bnbPath, outputPath]:
    if fileExists(path):
      removeFile(path)

  writeFile(inputPath, fixture)
  let toBnb = runProcess(cliPath, ["json-to-bnb", inputPath, bnbPath])
  doAssert toBnb.exitCode == 0, toBnb.output
  doAssert readBytes(bnbPath).len > 0
  let toJson = runProcess(cliPath, ["bnb-to-json", bnbPath, outputPath])
  doAssert toJson.exitCode == 0, toJson.output
  doAssert readFile(outputPath) == expected, "CLI json->bnb->json changed canonical JSON"

  for path in [inputPath, bnbPath, outputPath]:
    if fileExists(path):
      removeFile(path)

# bony-me5.8: prove IK survives a full CLI round-trip byte-for-byte in BOTH
# directions on a temporary local fixture. Cycle the fixture through
# json-to-bnb -> bnb-to-json -> json-to-bnb -> bnb-to-json and diff bytes across
# the second cycle: the two .bnb outputs must be byte-identical (bnb->json->bnb
# stable) and the two .bony outputs must be byte-identical (json->bnb->json
# stable). Also pin the CLI's emitted JSON to `expected`: byte-stability alone is
# a fixed-point check and would stay green even if the CLI (which goes through
# the BonyAsset load/emit path, distinct from the SkeletonData path the
# in-process golden validates) silently dropped IK. The content golden proves IK
# actually survives the CLI round-trip. Not covered by scripts/ci/round_trip_run.py.
proc expectCliRoundTripBytesStable(name, cliPath, fixture, expected: string) =
  let inputPath = "/tmp/bony_ik_roundtrip_input.bony"
  let bnb1Path = "/tmp/bony_ik_roundtrip_1.bnb"
  let json1Path = "/tmp/bony_ik_roundtrip_1.bony"
  let bnb2Path = "/tmp/bony_ik_roundtrip_2.bnb"
  let json2Path = "/tmp/bony_ik_roundtrip_2.bony"
  let scratch = [inputPath, bnb1Path, json1Path, bnb2Path, json2Path]
  for path in scratch:
    if fileExists(path):
      removeFile(path)

  writeFile(inputPath, fixture)
  let toBnb1 = runProcess(cliPath, ["json-to-bnb", inputPath, bnb1Path])
  doAssert toBnb1.exitCode == 0, name & " json-to-bnb (1) failed: " & toBnb1.output
  let toJson1 = runProcess(cliPath, ["bnb-to-json", bnb1Path, json1Path])
  doAssert toJson1.exitCode == 0, name & " bnb-to-json (1) failed: " & toJson1.output
  let toBnb2 = runProcess(cliPath, ["json-to-bnb", json1Path, bnb2Path])
  doAssert toBnb2.exitCode == 0, name & " json-to-bnb (2) failed: " & toBnb2.output
  let toJson2 = runProcess(cliPath, ["bnb-to-json", bnb2Path, json2Path])
  doAssert toJson2.exitCode == 0, name & " bnb-to-json (2) failed: " & toJson2.output

  doAssert readBytes(bnb1Path).len > 0, name & " produced an empty .bnb"
  doAssert readBytes(bnb1Path) == readBytes(bnb2Path),
    name & " bnb->json->bnb was not byte-stable"
  doAssert readFile(json1Path) == readFile(json2Path),
    name & " json->bnb->json was not byte-stable"
  doAssert readFile(json1Path) == expected,
    name & " CLI round-trip did not emit the expected canonical JSON"

  for path in scratch:
    if fileExists(path):
      removeFile(path)

expectJsonBnbJsonIdempotent("mixed-order numeric fixture", mixedOrderFixture, canonicalFixture)
expectJsonBnbJsonIdempotent("IK constraint fixture", ikMixedOrderFixture, ikCanonicalFixture)
expectJsonBnbJsonIdempotent("IK omit-default fixture", ikOmitFixture, ikOmitCanonicalFixture)
expectDefaultsReapplied()
expectAngleBoundaryPreserved()

let cliPath = "/tmp/bony_json_idempotency_cli"
compileCli(cliPath)
expectCliRoundTrip(cliPath, mixedOrderFixture, canonicalFixture)
expectCliRoundTripBytesStable("IK constraint fixture", cliPath, ikMixedOrderFixture, ikCanonicalFixture)
expectCliRoundTripBytesStable("IK omit-default fixture", cliPath, ikOmitFixture, ikOmitCanonicalFixture)
if fileExists(cliPath):
  removeFile(cliPath)

echo "json->bnb->json idempotency gate passed"
