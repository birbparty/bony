## Event-timeline runtime wiring tests (prompt 28, bony-5yt9).
##
## Covers unit A of docs/event-timeline-contract.md: the JSON loader, the `.bnb`
## `eventKeys` codec, and the load-validated invariants (a)-(e). A clip that owns
## an event timeline must survive json -> bnb -> json byte-losslessly, and each
## contract rejection must fire a `schemaViolation`.

import std/strutils

import bony

proc raisesBonyLoadError(action: proc(); kind: BonyLoadErrorKind): bool =
  try:
    action()
    false
  except BonyLoadError as err:
    err.kind == kind

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

proc canonicalJson(text: string): string =
  toBonyJson(loadBonyJsonAsset(text))

proc viaBnb(text: string): string =
  toBonyJson(loadKnownBonyBnbAsset(toBonyBnb(loadBonyJsonAsset(text))))

# --- Round-trip: json -> bnb -> json is byte-lossless ------------------------
block roundTrip:
  let canonical = canonicalJson(eventFixture)
  doAssert canonical.contains("\"eventTimelines\""), "canonical JSON must emit eventTimelines"
  doAssert canonical.contains("\"footstep\""), "event name must survive load+emit"
  doAssert canonical.contains("\"audioPath\": \"sfx/step.wav\""), "audioPath must survive"

  let cycled = viaBnb(eventFixture)
  doAssert cycled == canonical, "event timeline changed after json->bnb->json"
  doAssert canonicalJson(cycled) == cycled, "event canonical JSON is not stable"

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
