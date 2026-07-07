# Regression gate for the M23 nested-rig conformance fixture. Included with
# -d:bonyExcludeMain so the CLI's private golden-gen proc can be exercised
# without invoking main().

import std/[os, strutils, tables]

include "../../cli/bony_cli.nim"
import testutil

const
  assetJson = "../conformance/assets/m23_nested_rig.bony"
  assetBnb = "../conformance/assets/bnb/m23_nested_rig.bnb"
  scriptPath = "../conformance/scripts/m23_nested_rig_sample.json"
  goldenPath = "../conformance/goldens/m23_nested_rig_t0.json"

let host = loadBonyJson(readFile(assetJson))
let child = loadBonyJson(readFile("../conformance/assets/m23_nested_child_rig.bony"))
let legacy = buildDrawBatches(host)
let nested = buildNestedDrawBatches(host, {"childRig": child}.toTable)

doAssert legacy.len == 2
doAssert legacy[0].slot == "under_slot"
doAssert legacy[1].slot == "after_slot"

doAssert nested.len == 4
doAssert nested[0].slot == "under_slot"
doAssert nested[1].slot == "face_slot"
doAssert nested[1].attachment == "wide_face"
doAssert nested[1].clipId == "host_clip"
doAssert nested[2].slot == "after_slot"
doAssert nested[3].slot == "face_slot"
doAssert nested[3].attachment == "default_face"
doAssert nested[3].clipId == ""
doAssert abs(nested[1].vertices[0].x - 45.0) <= 1e-4

checkInputScriptGolden(assetJson, goldenPath, "bony_m23", "setup", scriptPath)
checkInputScriptGolden(assetBnb, goldenPath, "bony_m23", "setup", scriptPath)

let tempDir = getTempDir()
let noBinaryScript = tempDir / "bony_m23_missing_binary_child.json"
writeFile(noBinaryScript, readFile(scriptPath).replace(
  """,
      "binaryAsset": "bnb/m23_nested_child_rig.bnb"
    }""",
  """
    }""",
))
doAssert raisesBonyLoadError(proc() =
  writeNumericGolden(@[
    assetBnb,
    tempDir / "bony_m23_missing_binary_child_out.json",
    "--input-script",
    noBinaryScript,
    "--sample",
    "setup",
  ])
, unknownRequiredReference)
if fileExists(noBinaryScript):
  removeFile(noBinaryScript)

let stateMisuseScript = tempDir / "bony_m23_state_misuse.json"
writeFile(stateMisuseScript, readFile(scriptPath).replace(
  "\"asset\": \"m23_nested_rig.bony\",",
  "\"asset\": \"m23_nested_rig.bony\",\n  \"stateMachine\": \"not_allowed\",",
))
doAssert raisesBonyLoadError(proc() =
  writeNumericGolden(@[
    assetJson,
    tempDir / "bony_m23_state_misuse_out.json",
    "--state-machine",
    "not_allowed",
    "--input-script",
    stateMisuseScript,
    "--sample",
    "setup",
  ])
, schemaViolation)
if fileExists(stateMisuseScript):
  removeFile(stateMisuseScript)

echo "M23 nested-rig conformance CLI tests passed"
