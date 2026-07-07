include smoke_support

spec "bnb wire smoke coverage":
  it "encodes and rejects .bnb varints canonically":
    var bytes: seq[byte]
    bytes.writeVaruint(0)
    bytes.writeVaruint(127)
    bytes.writeVaruint(128)
    bytes.writeVaruint(624485)
    var index = 0

    then:
      bytes == @[0'u8, 127'u8, 128'u8, 1'u8, 229'u8, 142'u8, 38'u8]
      bytes.readVaruint(index) == 0
      bytes.readVaruint(index) == 127
      bytes.readVaruint(index) == 128
      bytes.readVaruint(index) == 624485

    bytes.setLen(0)
    bytes.writeVarint(-1)
    bytes.writeVarint(1)
    index = 0

    then:
      bytes.readVarint(index) == -1
      bytes.readVarint(index) == 1
      raisesBonyLoadError(proc() =
        var badIndex = 0
        discard readVaruint(@[128'u8, 0'u8], badIndex)
      , malformedVarint)
      raisesBonyLoadError(proc() =
        var badIndex = 0
        discard readVaruint(@[128'u8], badIndex)
      , truncatedInput)

  it "encodes .bnb headers and ToC entries":
    var bytes: seq[byte]
    bytes.writeHeader(flags = bnbStringTableFlag)
    bytes.writeToc(@[
      BnbTocEntry(propertyKey: 1000, backingTypeCode: backingTypeCode("f32")),
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
    ])
    var index = 0
    let header = bytes.readHeader(index)
    let toc = bytes.readToc(index)

    then:
      bytes[0 .. 3] == @[byte(ord('B')), byte(ord('O')), byte(ord('N')), byte(ord('Y'))]
      header.major == bnbMajorVersion
      header.minor == bnbMinorVersion
      header.flags == bnbStringTableFlag
      toc.len == 2
      toc[0].propertyKey == 1
      toc[1].propertyKey == 1000
      toc.backingTypeCodeFor(1) == backingTypeCode("string")
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeHeader(flags = 1'u64 shl 8)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.add bnbFingerprint
        bad.writeVaruint(packedVersion(bnbMajorVersion + 1, 0))
        bad.writeVaruint(0)
        var badIndex = 0
        discard bad.readHeader(badIndex)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.add bnbFingerprint
        bad.writeVaruint(packedVersion())
        bad.writeVaruint(1'u64 shl 8)
        var badIndex = 0
        discard bad.readHeader(badIndex)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeToc(@[
          BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
          BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
        ])
      , duplicateKey)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeToc(@[BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("f32"))])
      , invalidBackingType)

  it "reads .bnb length-prefixed property records":
    let toc = @[
      BnbTocEntry(propertyKey: 900000, backingTypeCode: 250'u8),
    ]
    var bytes: seq[byte]
    bytes.writePropertyRecord(900000, @[1'u8, 2'u8, 3'u8, 4'u8])
    bytes.writePropertyTerminator()
    var index = 0
    let record = bytes.readPropertyRecord(index, toc)
    let terminator = bytes.skipPropertyRecord(index, toc)

    then:
      record.propertyKey == 900000
      record.payload == @[1'u8, 2'u8, 3'u8, 4'u8]
      terminator == 0
      index == bytes.len
      raisesBonyLoadError(proc() =
        var badIndex = 0
        discard readPropertyRecord(bytes, badIndex, @[])
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad = @[1'u8, 4'u8, 1'u8, 2'u8]
        var badIndex = 0
        discard readPropertyRecord(bad, badIndex, @[BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string"))])
      , truncatedInput)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeVaruint(900000)
        bad.writeVaruint(bnbMaxPropertyPayloadBytes + 1)
        var badIndex = 0
        discard skipPropertyRecord(bad, badIndex, toc)
      , resourceLimitExceeded)

    bytes.setLen(0)
    bytes.writePropertyRecord(900000, @[5'u8, 6'u8, 7'u8])
    index = 0

    then:
      bytes.skipPropertyRecord(index, toc) == 900000
      index == bytes.len

  it "reads .bnb type-keyed object streams":
    let toc = @[
      BnbTocEntry(propertyKey: 900000, backingTypeCode: 250'u8),
      BnbTocEntry(propertyKey: 900001, backingTypeCode: 251'u8),
    ]
    var bytes: seq[byte]
    bytes.writeObjectRecord(999999, @[
      BnbPropertyRecord(propertyKey: 900000, payload: @[1'u8, 2'u8]),
    ])
    bytes.writeObjectRecord(2, @[
      BnbPropertyRecord(propertyKey: 900001, payload: @[9'u8]),
      BnbPropertyRecord(propertyKey: 900000, payload: @[3'u8, 4'u8]),
    ])
    bytes.writeObjectStreamTerminator()
    var index = 0
    let skippedTypeKey = bytes.skipObjectRecord(index, toc)
    let known = bytes.readObjectRecord(index, toc)
    let terminator = bytes.skipObjectRecord(index, toc)

    then:
      skippedTypeKey == 999999
      known.typeKey == 2
      known.properties.len == 2
      known.properties[0].propertyKey == 900000
      known.properties[0].payload == @[3'u8, 4'u8]
      known.properties[1].propertyKey == 900001
      known.properties[1].payload == @[9'u8]
      terminator == 0
      index == bytes.len
      isKnownTypeKey(2)
      not isKnownTypeKey(999999)

    index = 0
    let stream = bytes.readObjectStream(index, toc)

    then:
      stream.len == 1
      stream[0].typeKey == 2
      stream[0].properties.len == 2
      index == bytes.len
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeObjectRecord(2, @[
          BnbPropertyRecord(propertyKey: 900000, payload: @[]),
          BnbPropertyRecord(propertyKey: 900000, payload: @[]),
        ])
      , duplicateKey)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeObjectRecord(0, @[])
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeObjectRecord(2, @[BnbPropertyRecord(propertyKey: 900000, payload: @[])])
        var badIndex = 0
        discard bad.readObjectRecord(badIndex, @[])
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeVaruint(2)
        bad.writePropertyRecord(900000, @[])
        var badIndex = 0
        discard bad.readObjectRecord(badIndex, toc)
      , truncatedInput)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeVaruint(2)
        bad.writePropertyRecord(900000, @[])
        bad.writePropertyRecord(900000, @[])
        bad.writePropertyTerminator()
        var badIndex = 0
        discard bad.readObjectRecord(badIndex, toc)
      , duplicateKey)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeVaruint(999999)
        bad.writePropertyRecord(900000, @[])
        bad.writePropertyRecord(900000, @[])
        bad.writePropertyTerminator()
        var badIndex = 0
        discard bad.skipObjectRecord(badIndex, toc)
      , duplicateKey)

  it "handles .bnb embedded atlas trailer bytes":
    var bytes: seq[byte]
    bytes.writeHeader(flags = bnbEmbeddedAtlasFlag)
    bytes.writeToc(@[])
    bytes.writeObjectStreamTerminator()
    bytes.writeEmbeddedAtlas(@[1'u8, 2'u8, 3'u8])
    var index = 0
    let header = bytes.readHeader(index)
    discard bytes.readToc(index)
    let objects = bytes.readObjectStream(index, @[])
    let atlas = bytes.readEmbeddedAtlas(index, header)

    then:
      objects.len == 0
      atlas == @[1'u8, 2'u8, 3'u8]
      index == bytes.len
      raisesBonyLoadError(proc() =
        var bad = bytes
        var badIndex = 0
        let badHeader = bad.readHeader(badIndex)
        discard bad.readToc(badIndex)
        discard bad.readObjectStream(badIndex, @[])
        discard bad.readEmbeddedAtlas(badIndex, BnbHeader(major: badHeader.major, minor: badHeader.minor, flags: 0))
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bad: seq[byte]
        bad.writeHeader(flags = 0)
        bad.writeToc(@[])
        bad.writeObjectStreamTerminator()
        bad.add 42'u8
        var badIndex = 0
        let badHeader = bad.readHeader(badIndex)
        discard bad.readToc(badIndex)
        discard bad.readObjectStream(badIndex, @[])
        discard bad.readEmbeddedAtlas(badIndex, badHeader)
      , schemaViolation)

  it "emits atlas-backed region texturePage and UVs from JSON and .bnb":
    let jsonData = loadBonyJson(readFile(repoPath("conformance", "assets", "m24_atlas_region_rig.bony")))
    let bnbData = loadBonyBnb(cast[seq[byte]](readFile(repoPath("conformance", "assets", "bnb", "m24_atlas_region_rig.bnb"))))
    let jsonBatch = buildDrawBatches(jsonData)[0]
    let bnbBatch = buildDrawBatches(bnbData)[0]
    then:
      jsonBatch.texturePage == "atlas_0.png"
      bnbBatch.texturePage == jsonBatch.texturePage
      closeTo(jsonBatch.vertices[0].u, 0.25)
      closeTo(jsonBatch.vertices[0].v, 0.125)
      closeTo(jsonBatch.vertices[2].u, 0.5)
      closeTo(jsonBatch.vertices[2].v, 0.375)
      closeTo(bnbBatch.vertices[0].u, jsonBatch.vertices[0].u)
      closeTo(bnbBatch.vertices[2].v, jsonBatch.vertices[2].v)

  it "rejects malformed semantic .bnb payloads":
    then:
      raisesBonyLoadError(proc() =
        var table = initStringTable()
        var skeletonNamePayload: seq[byte]
        skeletonNamePayload.writeStringPayload(table, "demo")
        var boneNamePayload: seq[byte]
        boneNamePayload.writeStringPayload(table, "root")
        var bytes: seq[byte]
        bytes.writeHeader(flags = bnbStringTableFlag)
        bytes.writeToc(@[
          BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
          BnbTocEntry(propertyKey: 1007, backingTypeCode: backingTypeCode("bool")),
        ])
        bytes.writeStringTable(table)
        bytes.writeObjectRecord(1, @[BnbPropertyRecord(propertyKey: 1, payload: skeletonNamePayload)])
        bytes.writeObjectRecord(2, @[
          BnbPropertyRecord(propertyKey: 1, payload: boneNamePayload),
          BnbPropertyRecord(propertyKey: 1007, payload: @[2'u8]),
        ])
        bytes.writeObjectStreamTerminator()
        discard loadBonyBnb(bytes)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var table = initStringTable()
        var skeletonNamePayload: seq[byte]
        skeletonNamePayload.writeStringPayload(table, "demo")
        var bytes: seq[byte]
        bytes.writeHeader(flags = bnbStringTableFlag)
        bytes.writeToc(@[
          BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
          BnbTocEntry(propertyKey: 1014, backingTypeCode: backingTypeCode("f32")),
        ])
        bytes.writeStringTable(table)
        bytes.writeObjectRecord(1, @[
          BnbPropertyRecord(propertyKey: 1, payload: skeletonNamePayload),
          BnbPropertyRecord(propertyKey: 1014, payload: @[0'u8, 0'u8, 0'u8, 0'u8]),
        ])
        bytes.writeObjectStreamTerminator()
        discard loadBonyBnb(bytes)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bytes: seq[byte]
        bytes.writeHeader(flags = bnbStringTableFlag)
        bytes.writeToc(@[])
        bytes.writeStringTable(initStringTable())
        bytes.writeObjectStreamTerminator()
        discard loadBonyBnb(bytes)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var table = initStringTable()
        var namePayload: seq[byte]
        namePayload.writeStringPayload(table, "demo")
        var bytes: seq[byte]
        bytes.writeHeader(flags = bnbStringTableFlag)
        bytes.writeToc(@[
          BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
          BnbTocEntry(propertyKey: 900000, backingTypeCode: backingTypeCode("bytes")),
        ])
        bytes.writeStringTable(table)
        bytes.writeObjectRecord(1, @[
          BnbPropertyRecord(propertyKey: 1, payload: namePayload),
          BnbPropertyRecord(propertyKey: 900000, payload: @[1'u8]),
        ])
        bytes.writeObjectStreamTerminator()
        discard loadKnownBonyBnb(bytes)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var bytes: seq[byte]
        bytes.writeHeader(flags = bnbEmbeddedAtlasFlag or bnbStringTableFlag)
        bytes.writeToc(@[])
        bytes.writeStringTable(initStringTable())
        bytes.writeObjectStreamTerminator()
        bytes.writeEmbeddedAtlas(@[1'u8])
        discard loadKnownBonyBnb(bytes)
      , schemaViolation)

  it "encodes .bnb string tables in first-seen order":
    var table = initStringTable()

    then:
      table.intern("root") == 0
      table.intern("slot") == 1
      table.intern("root") == 0
      table.values == @["root", "slot"]

    var bytes: seq[byte]
    bytes.writeStringTable(table)
    var index = 0
    let decoded = bytes.readStringTable(index)

    then:
      bytes == @[
        2'u8,
        4'u8, byte(ord('r')), byte(ord('o')), byte(ord('o')), byte(ord('t')),
        4'u8, byte(ord('s')), byte(ord('l')), byte(ord('o')), byte(ord('t')),
      ]
      decoded.values == @["root", "slot"]
      decoded.stringAt(0) == "root"
      decoded.stringAt(1) == "slot"
      index == bytes.len
      raisesBonyLoadError(proc() = discard decoded.stringAt(2), unknownRequiredReference)

  it "encodes .bnb string payload indexes":
    var table = initStringTable()
    var payload: seq[byte]
    payload.writeStringPayload(table, "root")
    payload.writeStringPayload(table, "slot")
    payload.writeStringPayload(table, "root")

    then:
      payload == @[0'u8, 1'u8, 0'u8]
      table.values == @["root", "slot"]
      readStringPayload(payload[0 .. 0], table) == "root"
      readStringPayload(payload[1 .. 1], table) == "slot"
      raisesBonyLoadError(proc() = discard readStringPayload(@[2'u8], table), unknownRequiredReference)
      raisesBonyLoadError(proc() = discard readStringPayload(@[0'u8, 0'u8], table), schemaViolation)

  it "preserves duplicate .bnb string table entries by index":
    var bytes: seq[byte]
    bytes.writeVaruint(2)
    bytes.writeVaruint(4)
    bytes.add @[byte(ord('r')), byte(ord('o')), byte(ord('o')), byte(ord('t'))]
    bytes.writeVaruint(4)
    bytes.add @[byte(ord('r')), byte(ord('o')), byte(ord('o')), byte(ord('t'))]
    var index = 0
    let table = bytes.readStringTable(index)

    then:
      table.values == @["root", "root"]
      table.stringAt(0) == "root"
      table.stringAt(1) == "root"
      index == bytes.len

  it "rejects malformed .bnb string tables":
    then:
      raisesBonyLoadError(proc() =
        var bytes: seq[byte]
        bytes.writeVaruint(bnbMaxStringTableEntries + 1)
        var index = 0
        discard bytes.readStringTable(index)
      , resourceLimitExceeded)
      raisesBonyLoadError(proc() =
        var bytes: seq[byte]
        bytes.writeVaruint(1)
        bytes.writeVaruint(bnbMaxStringBytes + 1)
        var index = 0
        discard bytes.readStringTable(index)
      , resourceLimitExceeded)
      raisesBonyLoadError(proc() =
        let bytes = @[1'u8, 1'u8, 255'u8]
        var index = 0
        discard bytes.readStringTable(index)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        let bytes = @[1'u8, 3'u8, 0xED'u8, 0xA0'u8, 0x80'u8]
        var index = 0
        discard bytes.readStringTable(index)
      , schemaViolation)
      raisesBonyLoadError(proc() =
        var table = initStringTable()
        discard table.intern("\xED\xA0\x80")
      , schemaViolation)
      raisesBonyLoadError(proc() =
        let bytes = @[1'u8, 4'u8, byte(ord('r'))]
        var index = 0
        discard bytes.readStringTable(index)
      , truncatedInput)
