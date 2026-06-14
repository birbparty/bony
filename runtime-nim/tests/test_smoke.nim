import std/strutils

import bddy
import bony

proc raisesBonyLoadError(input: string): bool =
  try:
    discard loadBonyJson(input)
    false
  except BonyLoadError:
    true

spec "bony package":
  it "exposes version":
    then:
      bonyVersion == "0.1.0"

  it "exports generated registry metadata":
    then:
      bonyRegistryVersion == 1
      bonyBackingTypes.len == 7
      bonyBackingTypes[0].id == "varuint"
      bonyTypeKeys.len == 2
      bonyPropertyKeys.len == 3
      bonyPropertyDefaults.len == 2
      bonyRequiredProperties.len == 2

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
  ]
}
""")

    then:
      data.header.name == "demo"
      data.header.version == "0.1.0"
      data.bones.len == 2
      data.bones[0].parent == ""
      data.bones[1].parent == "root"

  it "serializes defaults by omission":
    let data = SkeletonData(
      header: SkeletonHeader(name: "demo", version: "0.1.0"),
      bones: @[BoneData(name: "root", parent: "")]
    )

    let output = toBonyJson(data)

    then:
      output.contains("\"name\": \"demo\"")
      not output.contains("\"version\"")
      not output.contains("\"parent\"")

  it "rejects duplicate bone names":
    then:
      raisesBonyLoadError("""{"skeleton":{"name":"demo"},"bones":[{"name":"root"},{"name":"root"}]}""")

  it "rejects child-before-parent order":
    then:
      raisesBonyLoadError("""{"skeleton":{"name":"demo"},"bones":[{"name":"child","parent":"root"}]}""")

  it "wraps malformed JSON as a load error":
    then:
      raisesBonyLoadError("""{"skeleton":""")
