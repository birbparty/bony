# Regression gate for the M22 skinRequired conformance fixture. Included with
# -d:bonyExcludeMain so the CLI's private golden-gen proc can be exercised
# without invoking main().

import std/[os, strutils]

include "../../cli/bony_cli.nim"

const
  assetJson = "../conformance/assets/m22_skin_required_rig.bony"
  assetBnb = "../conformance/assets/bnb/m22_skin_required_rig.bnb"
  defaultScript = "../conformance/scripts/m22_skin_required_default.json"
  variantScript = "../conformance/scripts/m22_skin_required_variant.json"
  defaultRestGolden = "../conformance/goldens/m22_skin_required_default_rest.json"
  defaultLateGolden = "../conformance/goldens/m22_skin_required_default_late.json"
  variantRestGolden = "../conformance/goldens/m22_skin_required_variant_rest.json"
  variantActiveGolden = "../conformance/goldens/m22_skin_required_variant_active.json"
  variantSettledGolden = "../conformance/goldens/m22_skin_required_variant_settled.json"

proc canonicalText(path: string): string =
  readFile(path).strip()

proc checkGolden(assetPath, scriptPath, sampleName, expectedPath: string) =
  let outPath = getTempDir() / ("bony_m22_" & sampleName & "_" & extractFilename(assetPath) & ".json")
  try:
    writeNumericGolden(@[
      assetPath,
      outPath,
      "--state-machine",
      "skin_required_story",
      "--input-script",
      scriptPath,
      "--sample",
      sampleName,
    ])
    doAssert canonicalText(outPath) == canonicalText(expectedPath)
  finally:
    if fileExists(outPath):
      removeFile(outPath)

proc raisesBonyLoadError(action: proc(); kind: BonyLoadErrorKind): bool =
  try:
    action()
    false
  except BonyLoadError as exc:
    exc.kind == kind

let assetText = readFile(assetJson)
let asset = loadBonyJsonAsset(assetText)
let data = asset.skeleton
let variant = activeSkinMembership(data, "variant")

doAssert data.skins[1].bones == @["shared_helper", "variant_extra"]
doAssert variant.bones[1]
doAssert variant.bones[2]

checkGolden(assetJson, defaultScript, "rest", defaultRestGolden)
checkGolden(assetBnb, defaultScript, "rest", defaultRestGolden)
checkGolden(assetJson, defaultScript, "late", defaultLateGolden)
checkGolden(assetBnb, defaultScript, "late", defaultLateGolden)
checkGolden(assetJson, variantScript, "rest", variantRestGolden)
checkGolden(assetBnb, variantScript, "rest", variantRestGolden)
checkGolden(assetJson, variantScript, "active", variantActiveGolden)
checkGolden(assetBnb, variantScript, "active", variantActiveGolden)
checkGolden(assetJson, variantScript, "settled", variantSettledGolden)
checkGolden(assetBnb, variantScript, "settled", variantSettledGolden)

let unknownRef = assetText.replace("\"bones\": [\"shared_helper\"]", "\"bones\": [\"ghost\"]")
let duplicateRef = assetText.replace(
  "\"physicsConstraints\": [\"skin_spring\"]",
  "\"physicsConstraints\": [\"skin_spring\", \"skin_spring\"]",
)
let nonRequiredRef = assetText.replace("\"bones\": [\"shared_helper\"]", "\"bones\": [\"root\"]")
let missingRequiredParent = assetText
  .replace("\"bones\": [\"shared_helper\"]", "\"bones\": []")
  .replace("\"bones\": [\"shared_helper\", \"variant_extra\"]", "\"bones\": [\"variant_extra\"]")
let transformMissingTarget = assetText.replace(
  "{\"name\": \"copy_target\", \"parent\": \"root\", \"x\": 90, \"y\": 30}",
  "{\"name\": \"copy_target\", \"parent\": \"root\", \"x\": 90, \"y\": 30, \"skinRequired\": true}",
)

doAssert raisesBonyLoadError(proc() = discard loadBonyJsonAsset(unknownRef), unknownRequiredReference)
doAssert raisesBonyLoadError(proc() = discard loadBonyJsonAsset(duplicateRef), duplicateKey)
doAssert raisesBonyLoadError(proc() = discard loadBonyJsonAsset(nonRequiredRef), schemaViolation)
doAssert raisesBonyLoadError(proc() = discard loadBonyJsonAsset(missingRequiredParent), schemaViolation)
doAssert raisesBonyLoadError(proc() = discard loadBonyJsonAsset(transformMissingTarget), schemaViolation)

echo "M22 skinRequired conformance CLI tests passed"
