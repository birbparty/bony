# Regression gate for the M25 animated draw-order conformance fixture. Included
# with -d:bonyExcludeMain so the CLI's private golden-gen proc can be exercised
# without invoking main().

include "../../cli/bony_cli.nim"
import testutil

const
  assetJson = "../conformance/assets/m25_draw_order_rig.bony"
  assetBnb = "../conformance/assets/bnb/m25_draw_order_rig.bnb"
  scriptPath = "../conformance/scripts/m25_draw_order_story.json"
  restGolden = "../conformance/goldens/m25_draw_order_story_rest.json"
  firstGolden = "../conformance/goldens/m25_draw_order_story_first.json"
  heldGolden = "../conformance/goldens/m25_draw_order_story_held.json"
  restoreGolden = "../conformance/goldens/m25_draw_order_story_restore.json"

let asset = loadBonyJsonAsset(readFile(assetJson))
let clip = asset.animations[0]

doAssert clip.hasDrawOrderTimeline
doAssert sampleDrawOrderTimeline(clip.drawOrderTimeline, asset.skeleton.slots, 0.0) == @["back_slot", "mid_slot", "front_slot"]
doAssert sampleDrawOrderTimeline(clip.drawOrderTimeline, asset.skeleton.slots, 0.25) == @["front_slot", "mid_slot", "back_slot"]
doAssert sampleDrawOrderTimeline(clip.drawOrderTimeline, asset.skeleton.slots, 0.5) == @["front_slot", "mid_slot", "back_slot"]
doAssert sampleDrawOrderTimeline(clip.drawOrderTimeline, asset.skeleton.slots, 1.0) == @["back_slot", "mid_slot", "front_slot"]

let bnbBytes = testutil.readBytes(assetBnb)
let bnbAsset = loadKnownBonyBnbAsset(bnbBytes)
doAssert toBonyBnb(loadBonyJsonAsset(toBonyJson(bnbAsset))) == bnbBytes

checkStateMachineGolden(assetJson, restGolden, "bony_m25", "rest", "draw_order_story", scriptPath)
checkStateMachineGolden(assetBnb, restGolden, "bony_m25", "rest", "draw_order_story", scriptPath)
checkStateMachineGolden(assetJson, firstGolden, "bony_m25", "first", "draw_order_story", scriptPath)
checkStateMachineGolden(assetBnb, firstGolden, "bony_m25", "first", "draw_order_story", scriptPath)
checkStateMachineGolden(assetJson, heldGolden, "bony_m25", "held", "draw_order_story", scriptPath)
checkStateMachineGolden(assetBnb, heldGolden, "bony_m25", "held", "draw_order_story", scriptPath)
checkStateMachineGolden(assetJson, restoreGolden, "bony_m25", "restore", "draw_order_story", scriptPath)
checkStateMachineGolden(assetBnb, restoreGolden, "bony_m25", "restore", "draw_order_story", scriptPath)

echo "M25 draw-order conformance CLI tests passed"
