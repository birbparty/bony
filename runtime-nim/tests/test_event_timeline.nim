## Event-timeline runtime wiring tests (prompt 28, bony-5yt9).
##
## Covers unit A of docs/event-timeline-contract.md: the JSON loader, the `.bnb`
## `eventKeys` codec, and the load-validated invariants (a)-(e). A clip that owns
## an event timeline must survive json -> bnb -> json byte-losslessly, and each
## contract rejection must fire a `schemaViolation`.

import std/strutils

import bony
import testutil

# A full asset carrying one event timeline with two keyframes: the first sets
# every EventData field to a non-default value; the second relies on all the
# reserved defaults (intValue 0, floatValue 0.0, empty strings, volume 1.0,
# balance 0.0). Equal/ascending times exercise the non-decreasing rule.
const eventFixture = """{
  "skeleton": {"name": "ev", "version": "0.2.0"},
  "bones": [{"name": "root"}],
  "animations": [
    {
      "name": "clip",
      "eventTimelines": [
        {
          "keyframes": [
            {
              "t": 0.5,
              "name": "footstep",
              "intValue": 3,
              "floatValue": 1.5,
              "stringValue": "left",
              "audioPath": "sfx/step.wav",
              "volume": 0.75,
              "balance": -0.25
            },
            {"t": 1.0, "name": "land"}
          ]
        }
      ]
    }
  ]
}
"""

proc viaBnb(text: string): string =
  toBonyJson(loadKnownBonyBnbAsset(toBonyBnb(loadBonyJsonAsset(text))))

# --- Round-trip: json -> bnb -> json is byte-lossless ------------------------
block roundTrip:
  let canonical = canonicalJson(eventFixture, asset = true)
  doAssert canonical.contains("\"eventTimelines\""), "canonical JSON must emit eventTimelines"
  doAssert canonical.contains("\"footstep\""), "event name must survive load+emit"
  doAssert canonical.contains("\"audioPath\": \"sfx/step.wav\""), "audioPath must survive"

  let cycled = viaBnb(eventFixture)
  doAssert cycled == canonical, "event timeline changed after json->bnb->json"
  doAssert canonicalJson(cycled, asset = true) == cycled, "event canonical JSON is not stable"

  # Byte-level: the .bnb re-encoded from the cycled JSON matches the original.
  let bytes0 = toBonyBnb(loadBonyJsonAsset(eventFixture))
  let bytes1 = toBonyBnb(loadBonyJsonAsset(cycled))
  doAssert bytes0 == bytes1, "event timeline .bnb bytes are not stable"

# --- Decoded values (including reserved defaults) ----------------------------
block decodedValues:
  let asset = loadKnownBonyBnbAsset(toBonyBnb(loadBonyJsonAsset(eventFixture)))
  doAssert asset.animations.len == 1
  let timelines = asset.animations[0].eventTimelines
  doAssert timelines.len == 1
  let keys = timelines[0].keys
  doAssert keys.len == 2

  let first = keys[0].event
  doAssert keys[0].time == quantizeF32(0.5)
  doAssert first.name == "footstep"
  doAssert first.intValue == 3'i32
  doAssert first.floatValue == quantizeF32(1.5)
  doAssert first.stringValue == "left"
  doAssert first.audioPath == "sfx/step.wav"
  doAssert first.volume == quantizeF32(0.75)
  doAssert first.balance == quantizeF32(-0.25)

  let second = keys[1].event
  doAssert keys[1].time == quantizeF32(1.0)
  doAssert second.name == "land"
  doAssert second.intValue == 0'i32
  doAssert second.floatValue == 0.0
  doAssert second.stringValue == ""
  doAssert second.audioPath == ""
  doAssert second.volume == quantizeF32(1.0)
  doAssert second.balance == 0.0

# --- Load edge cases (a)-(e), docs/event-timeline-contract.md ----------------
proc fixtureWithKeyframes(keyframes: string): string =
  """{
  "skeleton": {"name": "ev", "version": "0.2.0"},
  "bones": [{"name": "root"}],
  "animations": [
    {"name": "clip", "eventTimelines": [{"keyframes": [""" & keyframes & """]}]}
  ]
}
"""

block edgeCases:
  # (a) empty event name -> reject
  doAssert raisesBonyLoadError(
    proc() = discard loadBonyJsonAsset(fixtureWithKeyframes("""{"t": 0.0, "name": ""}""")),
    schemaViolation), "empty event name must be rejected"

  # (b) negative keyframe time -> reject
  doAssert raisesBonyLoadError(
    proc() = discard loadBonyJsonAsset(fixtureWithKeyframes("""{"t": -1.0, "name": "e"}""")),
    schemaViolation), "negative event time must be rejected"

  # (c) strictly decreasing adjacent times -> reject
  doAssert raisesBonyLoadError(
    proc() = discard loadBonyJsonAsset(fixtureWithKeyframes(
      """{"t": 1.0, "name": "a"}, {"t": 0.5, "name": "b"}""")),
    schemaViolation), "decreasing event times must be rejected"

  # (d) zero keyframes on a declared event timeline -> reject
  doAssert raisesBonyLoadError(
    proc() = discard loadBonyJsonAsset("""{
  "skeleton": {"name": "ev", "version": "0.2.0"},
  "bones": [{"name": "root"}],
  "animations": [{"name": "clip", "eventTimelines": [{"keyframes": []}]}]
}
"""),
    schemaViolation), "empty event timeline must be rejected"

# --- Accepted cases: equal times, and out-of-range volume/balance (case e) ---
block acceptedCases:
  # Equal adjacent times are accepted (non-decreasing, NOT strictly increasing).
  let equalTimes = fixtureWithKeyframes(
    """{"t": 0.5, "name": "a"}, {"t": 0.5, "name": "b"}""")
  let asset = loadBonyJsonAsset(equalTimes)
  doAssert asset.animations[0].eventTimelines[0].keys.len == 2

  # (e) volume/balance outside 0..1 / -1..1 are carried verbatim, never clamped.
  let wild = fixtureWithKeyframes(
    """{"t": 0.0, "name": "a", "volume": 5.0, "balance": -3.0}""")
  let wildAsset = loadKnownBonyBnbAsset(toBonyBnb(loadBonyJsonAsset(wild)))
  let ev = wildAsset.animations[0].eventTimelines[0].keys[0].event
  doAssert ev.volume == quantizeF32(5.0), "volume must be carried verbatim"
  doAssert ev.balance == quantizeF32(-3.0), "balance must be carried verbatim"

echo "test_event_timeline: OK"

include smoke_support

spec "event timeline smoke coverage":
  it "builds event timelines with per-fire overrides":
    let data = animationFixture()
    let footstep = eventData(
      "footstep",
      intValue = 1'i32,
      floatValue = 0.5,
      stringValue = "left",
      audioPath = "step.wav",
      volume = 0.8,
      balance = -0.25,
    )
    let clip = animationClip(
      data,
      "walk",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.25, footstep, 2'i32, 0.75, "right"),
        eventKeyframe(0.5, footstep),
      ])],
    )
    let keys = clip.eventTimelines[0].keys

    then:
      closeTo(clip.duration, 0.5)
      keys.len == 2
      keys[0].event.name == "footstep"
      keys[0].event.intValue == 2'i32
      closeTo(keys[0].event.floatValue, 0.75)
      keys[0].event.stringValue == "right"
      keys[0].event.audioPath == "step.wav"
      closeTo(keys[0].event.volume, quantizeF32(0.8))
      closeTo(keys[0].event.balance, quantizeF32(-0.25))
      keys[1].event.intValue == 1'i32
      raisesBonyLoadError(proc() = discard eventTimeline(@[eventKeyframe(1.0, footstep), eventKeyframe(0.5, footstep)]), schemaViolation)

  it "dispatches animation events advanced by update":
    let data = animationFixture()
    let clip = animationClip(
      data,
      "events",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.25, eventData("first")),
        eventKeyframe(0.5, eventData("second")),
      ])],
    )
    var state = animationState(1)
    state.setAnimation(0, clip)
    state.update(0.3)

    then:
      state.events.len == 1
      state.events[0].trackIndex == 0
      state.events[0].event.name == "first"
      closeTo(state.events[0].time, 0.25)

    state.update(0.3)

    then:
      state.events.len == 1
      state.events[0].event.name == "second"

  it "dispatches events from multiple timelines chronologically":
    let data = animationFixture()
    let clip = animationClip(
      data,
      "orderedEvents",
      eventTimelines = @[
        eventTimeline(@[
          eventKeyframe(0.8, eventData("late")),
          eventKeyframe(0.8, eventData("sameTimeFirst")),
        ]),
        eventTimeline(@[
          eventKeyframe(0.2, eventData("early")),
          eventKeyframe(0.8, eventData("sameTimeSecond")),
        ]),
      ],
    )
    var state = animationState(1)
    state.setAnimation(0, clip)
    state.update(1.0)

    then:
      state.events.len == 4
      state.events[0].event.name == "early"
      state.events[1].event.name == "late"
      state.events[2].event.name == "sameTimeFirst"
      state.events[3].event.name == "sameTimeSecond"

  it "dispatches looped events across wrapped time":
    let data = animationFixture()
    let clip = animationClip(
      data,
      "loop",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.25, eventData("tap")),
        eventKeyframe(0.75, eventData("end")),
      ])],
    )
    var state = animationState(1)
    state.setAnimation(0, clip, loop = true)
    state.update(1.0)

    then:
      state.events.len == 3
      state.events[0].event.name == "tap"
      state.events[1].event.name == "end"
      state.events[2].event.name == "tap"
      closeTo(state.events[2].time, 1.0)

  it "gates incoming events by mix threshold during crossfade":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 0.0)])],
    )
    let attack = animationClip(
      data,
      "attack",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.2, eventData("tooEarly")),
        eventKeyframe(0.6, eventData("hit")),
      ])],
    )
    var state = animationState(1)
    state.setAnimation(0, idle)
    state.addAnimation(0, attack, delay = 0.1, mixDuration = 1.0)
    state.tracks[0].eventThreshold = 0.5
    state.update(0.1)
    state.update(0.4)

    then:
      state.events.len == 0

    state.update(0.2)

    then:
      state.events.len == 1
      state.events[0].event.name == "hit"

  it "does not dispatch pre-threshold events during a large crossfade update":
    let data = animationFixture()
    let idle = animationClip(
      data,
      "idle",
      @[boneScalarTimeline("root", rotateTimeline, @[scalarKeyframe(0.0, 0.0), scalarKeyframe(1.0, 0.0)])],
    )
    let attack = animationClip(
      data,
      "attack",
      eventTimelines = @[eventTimeline(@[
        eventKeyframe(0.2, eventData("tooEarly")),
        eventKeyframe(0.6, eventData("hit")),
      ])],
    )
    var state = animationState(1)
    state.setAnimation(0, idle)
    state.addAnimation(0, attack, delay = 0.1, mixDuration = 1.0)
    state.tracks[0].eventThreshold = 0.5
    state.update(0.75)

    then:
      state.events.len == 1
      state.events[0].event.name == "hit"
