# Regression gate for the M22 skinRequired conformance fixture. Included with
# -d:bonyExcludeMain so the CLI's private golden-gen proc can be exercised
# without invoking main().

import std/[os, strutils]

include "../../cli/bony_cli.nim"
import testutil

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

let assetText = readFile(assetJson)
let asset = loadBonyJsonAsset(assetText)
let data = asset.skeleton
let variant = activeSkinMembership(data, "variant")

doAssert data.skins[1].bones == @["shared_helper", "variant_extra"]
doAssert variant.bones[1]
doAssert variant.bones[2]

checkStateMachineGolden(assetJson, defaultRestGolden, "bony_m22", "rest", "skin_required_story", defaultScript)
checkStateMachineGolden(assetBnb, defaultRestGolden, "bony_m22", "rest", "skin_required_story", defaultScript)
checkStateMachineGolden(assetJson, defaultLateGolden, "bony_m22", "late", "skin_required_story", defaultScript)
checkStateMachineGolden(assetBnb, defaultLateGolden, "bony_m22", "late", "skin_required_story", defaultScript)
checkStateMachineGolden(assetJson, variantRestGolden, "bony_m22", "rest", "skin_required_story", variantScript)
checkStateMachineGolden(assetBnb, variantRestGolden, "bony_m22", "rest", "skin_required_story", variantScript)
checkStateMachineGolden(assetJson, variantActiveGolden, "bony_m22", "active", "skin_required_story", variantScript)
checkStateMachineGolden(assetBnb, variantActiveGolden, "bony_m22", "active", "skin_required_story", variantScript)
checkStateMachineGolden(assetJson, variantSettledGolden, "bony_m22", "settled", "skin_required_story", variantScript)
checkStateMachineGolden(assetBnb, variantSettledGolden, "bony_m22", "settled", "skin_required_story", variantScript)

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
