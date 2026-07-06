# Regression gate for the M21 pointer-listener conformance fixture. Included
# with -d:bonyExcludeMain so the CLI's private golden-gen proc can be exercised
# without invoking main().

import std/[os, strutils]

include "../../cli/bony_cli.nim"

const
  assetJson = "../conformance/assets/m21_pointer_listener_rig.bony"
  assetBnb = "../conformance/assets/bnb/m21_pointer_listener_rig.bnb"
  storyScript = "../conformance/scripts/m21_pointer_listener_story.json"
  samples = ["rest", "enter", "down", "move", "up", "exit"]

proc canonicalText(path: string): string =
  readFile(path).strip()

proc checkGolden(assetPath, sampleName: string) =
  let expectedPath = "../conformance/goldens/m21_pointer_listener_" & sampleName & ".json"
  let outPath = getTempDir() / ("bony_m21_" & sampleName & "_" & extractFilename(assetPath) & ".json")
  try:
    writeNumericGolden(@[
      assetPath,
      outPath,
      "--state-machine",
      "pointer_story",
      "--input-script",
      storyScript,
      "--sample",
      sampleName,
    ])
    doAssert canonicalText(outPath) == canonicalText(expectedPath)
  finally:
    if fileExists(outPath):
      removeFile(outPath)

for sample in samples:
  checkGolden(assetJson, sample)
  checkGolden(assetBnb, sample)

echo "M21 pointer listener conformance CLI tests passed"
