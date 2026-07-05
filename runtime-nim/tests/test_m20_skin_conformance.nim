# Regression gate for the M20 skin conformance fixture. Included with
# -d:bonyExcludeMain so the CLI's private golden-gen proc can be exercised
# without invoking main().

import std/[os, strutils]

include "../../cli/bony_cli.nim"

const
  assetJson = "../conformance/assets/m20_skin_rig.bony"
  assetBnb = "../conformance/assets/bnb/m20_skin_rig.bnb"
  defaultScript = "../conformance/scripts/m20_skin_default.json"
  variantScript = "../conformance/scripts/m20_skin_variant.json"
  defaultGolden = "../conformance/goldens/m20_skin_default_default.json"
  variantGolden = "../conformance/goldens/m20_skin_variant_variant.json"

proc canonicalText(path: string): string =
  readFile(path).strip()

proc checkGolden(assetPath, scriptPath, sampleName, expectedPath: string) =
  let outPath = getTempDir() / ("bony_m20_" & sampleName & "_" & extractFilename(assetPath) & ".json")
  try:
    writeNumericGolden(@[
      assetPath,
      outPath,
      "--state-machine",
      "skin_story",
      "--input-script",
      scriptPath,
      "--sample",
      sampleName,
    ])
    doAssert canonicalText(outPath) == canonicalText(expectedPath)
  finally:
    if fileExists(outPath):
      removeFile(outPath)

checkGolden(assetJson, defaultScript, "default", defaultGolden)
checkGolden(assetBnb, defaultScript, "default", defaultGolden)
checkGolden(assetJson, variantScript, "variant", variantGolden)
checkGolden(assetBnb, variantScript, "variant", variantGolden)

echo "M20 skin conformance CLI tests passed"
