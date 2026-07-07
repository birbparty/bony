# Regression gate for the M21 pointer-listener conformance fixture. Included
# with -d:bonyExcludeMain so the CLI's private golden-gen proc can be exercised
# without invoking main().

import std/[os, strutils]

include "../../cli/bony_cli.nim"
import testutil

const
  assetJson = "../conformance/assets/m21_pointer_listener_rig.bony"
  assetBnb = "../conformance/assets/bnb/m21_pointer_listener_rig.bnb"
  storyScript = "../conformance/scripts/m21_pointer_listener_story.json"
  samples = ["rest", "enter", "down", "move", "up", "exit"]

for sample in samples:
  let expectedPath = "../conformance/goldens/m21_pointer_listener_" & sample & ".json"
  checkStateMachineGolden(assetJson, expectedPath, "bony_m21", sample, "pointer_story", storyScript)
  checkStateMachineGolden(assetBnb, expectedPath, "bony_m21", sample, "pointer_story", storyScript)

echo "M21 pointer listener conformance CLI tests passed"
