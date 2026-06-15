# Generates the M6 forward-compat .bnb fixture.
# A compliant reader must skip the unknown object (typeKey=999999) and load the
# known skeleton + bone records. Tests the "skip unknown, continue" contract.
#
# Usage: nim c --path:runtime-nim/src --path:~/git/bddy/src -r scripts/gen_compat_fixture.nim <output.bnb>

import std/[os, strformat]
import bony

when isMainModule:
  if paramCount() < 1:
    quit("Usage: gen_compat_fixture <output.bnb>", 1)
  let outPath = paramStr(1)

  # Pre-intern all strings before writing the string table
  var table = initStringTable()
  var namePayload: seq[byte]
  namePayload.writeStringPayload(table, "m6-compat")
  var rootPayload: seq[byte]
  rootPayload.writeStringPayload(table, "root")

  # ToC covers known property keys (name=1, version/parent=3) plus the two unknown
  # property keys that appear inside the unknown object (900000, 900001).
  # Required: skipPropertyRecord validates every property key against the ToC via
  # backingTypeCodeFor, which raises schemaViolation for any key absent from the ToC.
  let toc = @[
    BnbTocEntry(propertyKey: 1'u64, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 3'u64, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 900000'u64, backingTypeCode: 250'u8),
    BnbTocEntry(propertyKey: 900001'u64, backingTypeCode: 251'u8),
  ]

  var fixture: seq[byte]
  fixture.writeHeader(flags = bnbStringTableFlag)
  fixture.writeToc(toc)
  fixture.writeStringTable(table)

  # Known object: skeleton header (typeKey=1), name="m6-compat"
  fixture.writeObjectRecord(
    1'u64,
    @[BnbPropertyRecord(propertyKey: 1'u64, payload: namePayload)],
  )

  # Unknown object: typeKey=999999, properties use unknown keys 900000 and 900001.
  # A forward-compat reader must skip this entire object and continue.
  fixture.writeVaruint(999999'u64)
  fixture.writePropertyRecord(900000'u64, @[0x42'u8, 0xDE'u8, 0xAD'u8])
  fixture.writePropertyRecord(900001'u64, @[0xFF'u8])
  fixture.writePropertyTerminator()

  # Known object: root bone (typeKey=2), name="root"
  fixture.writeObjectRecord(
    2'u64,
    @[BnbPropertyRecord(propertyKey: 1'u64, payload: rootPayload)],
  )

  # Object stream terminator
  fixture.writeObjectStreamTerminator()

  # Verify it loads correctly
  let data = loadBonyBnb(fixture)
  doAssert data.header.name == "m6-compat", &"Expected skeleton 'm6-compat', got '{data.header.name}'"
  doAssert data.bones.len == 1, &"Expected 1 bone, got {data.bones.len}"
  doAssert data.bones[0].name == "root", &"Expected bone 'root', got '{data.bones[0].name}'"

  writeFile(outPath, cast[string](fixture))
  echo &"✓ {outPath}: {fixture.len} bytes — loads correctly (skeleton=m6-compat, 1 bone: root)"
