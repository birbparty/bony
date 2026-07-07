# Regression gate for the M20 skin conformance fixture. Included with
# -d:bonyExcludeMain so the CLI's private golden-gen proc can be exercised
# without invoking main().

import std/[os, strutils]

include "../../cli/bony_cli.nim"
import testutil

const
  assetJson = "../conformance/assets/m20_skin_rig.bony"
  assetBnb = "../conformance/assets/bnb/m20_skin_rig.bnb"
  defaultScript = "../conformance/scripts/m20_skin_default.json"
  variantScript = "../conformance/scripts/m20_skin_variant.json"
  defaultGolden = "../conformance/goldens/m20_skin_default_default.json"
  variantGolden = "../conformance/goldens/m20_skin_variant_variant.json"

checkStateMachineGolden(assetJson, defaultGolden, "bony_m20", "default", "skin_story", defaultScript)
checkStateMachineGolden(assetBnb, defaultGolden, "bony_m20", "default", "skin_story", defaultScript)
checkStateMachineGolden(assetJson, variantGolden, "bony_m20", "variant", "skin_story", variantScript)
checkStateMachineGolden(assetBnb, variantGolden, "bony_m20", "variant", "skin_story", variantScript)

echo "M20 skin conformance CLI tests passed"
