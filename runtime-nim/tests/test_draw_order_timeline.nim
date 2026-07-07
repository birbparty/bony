include smoke_support

const drawOrderFixture = """{
  "skeleton": {"name": "draw-order", "version": "0.1.0"},
  "bones": [{"name": "root"}],
  "regions": [
    {"name": "backRegion", "width": 1, "height": 1},
    {"name": "midRegion", "width": 1, "height": 1},
    {"name": "frontRegion", "width": 1, "height": 1}
  ],
  "slots": [
    {"name": "back", "bone": "root", "attachment": "backRegion"},
    {"name": "mid", "bone": "root", "attachment": "midRegion"},
    {"name": "front", "bone": "root", "attachment": "frontRegion"}
  ],
  "animations": [
    {
      "name": "shuffle",
      "drawOrderTimeline": {
        "keyframes": [
          {"t": 0.25, "offsets": [
            {"slot": "back", "offset": 2},
            {"slot": "front", "offset": -2}
          ]},
          {"t": 1.0, "offsets": []}
        ]
      }
    }
  ]
}
"""

proc batchSlots(data: SkeletonData): seq[string] =
  for batch in buildDrawBatches(data):
    result.add batch.slot

spec "draw-order timeline runtime coverage":
  it "loads, samples, applies, and preserves draw-order timelines through .bnb":
    let asset = loadBonyJsonAsset(drawOrderFixture)
    let clip = asset.animations[0]

    then:
      clip.hasDrawOrderTimeline
      clip.duration == quantizeF32(1.0)
      sampleDrawOrderTimeline(clip.drawOrderTimeline, asset.skeleton.slots, 0.0) == @["back", "mid", "front"]
      sampleDrawOrderTimeline(clip.drawOrderTimeline, asset.skeleton.slots, 0.5) == @["front", "mid", "back"]
      sampleDrawOrderTimeline(clip.drawOrderTimeline, asset.skeleton.slots, 1.0) == @["back", "mid", "front"]

    var dataRef = new SkeletonData
    dataRef[] = asset.skeleton
    var state = animationState(dataRef, 1)
    state.setAnimation(0, clip)
    state.tracks[0].current.time = quantizeF32(0.5)
    let posed = applyPose(asset.skeleton, state.sample())

    then:
      posed.slots.mapIt(it.name) == @["front", "mid", "back"]
      batchSlots(posed) == @["front", "mid", "back"]

    let cycled = loadKnownBonyBnbAsset(toBonyBnb(asset))

    then:
      cycled.animations.len == 1
      sampleDrawOrderTimeline(cycled.animations[0].drawOrderTimeline, cycled.skeleton.slots, 0.5) == @["front", "mid", "back"]
      toBonyBnb(cycled) == toBonyBnb(asset)
      canonicalJson(toBonyJson(cycled), asset = true) == toBonyJson(cycled)

  it "rejects duplicate target draw-order permutations":
    const bad = """{
      "skeleton": {"name": "bad", "version": "0.1.0"},
      "bones": [{"name": "root"}],
      "slots": [
        {"name": "a", "bone": "root"},
        {"name": "b", "bone": "root"}
      ],
      "animations": [
        {"name": "bad", "drawOrderTimeline": {"keyframes": [
          {"t": 0, "offsets": [{"slot": "a", "offset": 1}]}
        ]}}
      ]
    }"""

    then:
      raisesBonyLoadError(proc() = discard loadBonyJsonAsset(bad), schemaViolation)

  it "rejects animated draw orders that invalidate clipping ranges":
    const badClip = """{
      "skeleton": {"name": "bad-clip", "version": "0.1.0"},
      "bones": [{"name": "root"}],
      "regions": [
        {"name": "body", "width": 1, "height": 1},
        {"name": "tail", "width": 1, "height": 1}
      ],
      "clippingAttachments": [
        {"name": "mask", "vertices": [0, 0, 1, 0, 1, 1], "untilSlot": "bodySlot"}
      ],
      "slots": [
        {"name": "clipSlot", "bone": "root", "attachment": "mask"},
        {"name": "bodySlot", "bone": "root", "attachment": "body"},
        {"name": "tailSlot", "bone": "root", "attachment": "tail"}
      ],
      "animations": [
        {"name": "bad", "drawOrderTimeline": {"keyframes": [
          {"t": 0, "offsets": [
            {"slot": "clipSlot", "offset": 2},
            {"slot": "bodySlot", "offset": -1},
            {"slot": "tailSlot", "offset": -1}
          ]}
        ]}}
      ]
    }"""

    then:
      raisesBonyLoadError(proc() = discard loadBonyJsonAsset(badClip), schemaViolation)
