include smoke_support

spec "canonical serialization smoke coverage":
  it "loads .bony JSON and applies defaults":
    let data = loadBonyJson("""
{
  "skeleton": {
    "name": "demo"
  },
  "bones": [
    {
      "name": "root"
    },
    {
      "name": "child",
      "parent": "root"
    }
  ],
}
""")

    then:
      data.header.name == "demo"
      data.header.version == "0.1.0"
      data.bones.len == 2
      data.bones[0].parent == ""
      data.bones[1].parent == "root"

  it "serializes defaults by omission":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "")]
    )

    let output = toBonyJson(data)

    then:
      output.contains("\"name\": \"demo\"")
      not output.contains("\"version\"")
      not output.contains("\"parent\"")

  it "serializes minimal values canonically":
    let data = skeletonData(
      skeletonHeader("demo", "0.1.0"),
      @[boneData("root", "")]
    )

    then:
      toBonyJson(data) == """{
  "skeleton": {
    "name": "demo"
  },
  "bones": [
    {
      "name": "root"
    }
  ],
  "slots": [],
  "regions": []
}
"""

  it "serializes non-default values canonically":
    let data = skeletonData(
      skeletonHeader("demo", "0.2.0"),
      @[boneData("root", ""), boneData("child", "root")]
    )

    then:
      toBonyJson(data) == """{
  "skeleton": {
    "name": "demo",
    "version": "0.2.0"
  },
  "bones": [
    {
      "name": "root"
    },
    {
      "name": "child",
      "parent": "root"
    }
  ],
  "slots": [],
  "regions": []
}
"""

  it "rejects duplicate bone names":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root"},{"name":"root"}],"slots":[],"regions":[]}""",
        duplicateKey
      )

  it "rejects child-before-parent order":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"child","parent":"root"},{"name":"root"}],"slots":[],"regions":[]}""",
        orderingViolation
      )

  it "wraps malformed JSON as a load error":
    then:
      raisesBonyLoadError("""{"skeleton":""")

  it "rejects duplicate JSON object keys":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo","name":"dupe"},"bones":[],"slots":[],"regions":[]}""",
        duplicateKey
      )

  it "requires top-level bones":
    then:
      raisesBonyLoadError("""{"skeleton":{"name":"demo"}}""")

  it "defaults missing M2 collections to empty":
    let data = loadBonyJson("""{"skeleton":{"name":"demo"},"bones":[]}""")

    then:
      data.slots.len == 0
      data.regions.len == 0
      data.paths.len == 0

  it "requires non-empty names":
    then:
      raisesBonyLoadError("""{"skeleton":{"name":""},"bones":[],"slots":[],"regions":[]}""", schemaViolation)

  it "rejects missing parent references":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"child","parent":"missing"}],"slots":[],"regions":[]}""",
        unknownRequiredReference
      )

  it "rejects missing required fields":
    then:
      raisesBonyLoadError("""{"skeleton":{},"bones":[],"slots":[],"regions":[]}""", schemaViolation)
      raisesBonyLoadError("""{"skeleton":{"name":"demo"},"bones":[{}],"slots":[],"regions":[]}""", schemaViolation)

  it "rejects wrong field types and unknown fields":
    then:
      raisesBonyLoadError("""{"skeleton":{"name":7},"bones":[],"slots":[],"regions":[]}""", schemaViolation)
      raisesBonyLoadError("""{"skeleton":{"name":"demo"},"bones":[],"slots":[],"regions":[],"extra":true}""", schemaViolation)

  it "stores f32-backed numeric fields at f32 precision":
    let data = loadBonyJson("""{"skeleton":{"name":"demo"},"bones":[{"name":"root","x":0.1000000001}]}""")
    let expected = quantizeF32(0.1000000001)

    then:
      data.bones[0].local.x == expected
      toBonyJson(data).contains($expected)

  it "normalizes negative zero to positive zero (bony-iw6b)":
    then:
      # quantizeF32 is the single funnel for every f32 on both load paths, so
      # normalizing -0.0 -> +0.0 here makes the JSON emit (collapses to "0") and
      # the raw .bnb f32 encode (would keep the 0x80000000 sign bit) agree.
      cast[uint32](float32(quantizeF32(-0.0))) == 0'u32
      cast[uint32](float32(quantizeF32(0.0))) == 0'u32
      # A hand-authored -0.0 in a numeric field loads with +0.0 bits, not
      # 0x80000000, so it can no longer byte-diverge json<->bnb.
      cast[uint32](float32(
        loadBonyJson("""{"skeleton":{"name":"demo"},"bones":[{"name":"root","x":-0.0}]}""").bones[0].local.x
      )) == 0'u32
      # A tiny negative magnitude that underflows to -0.0 under f32 rounding is
      # normalized too, not just a literal -0.0 input.
      cast[uint32](float32(quantizeF32(-1.0e-60))) == 0'u32

  it "rejects f32-backed numeric overflow":
    then:
      raisesBonyLoadError(
        """{"skeleton":{"name":"demo"},"bones":[{"name":"root","x":1e999}]}""",
        numericOutOfRange
      )
