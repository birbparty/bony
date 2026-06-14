import std/[strformat, times]

import bony

const perCaseTimeBudgetSeconds = 0.25

proc bytes(text: string): seq[byte] =
  result = newSeq[byte](text.len)
  for index, ch in text:
    result[index] = byte(ord(ch))

proc stringPayload(table: var BnbStringTable; value: string): seq[byte] =
  result.writeStringPayload(table, value)

proc boolPayload(value: bool): seq[byte] =
  if value:
    @[1'u8]
  else:
    @[0'u8]

proc expectReject(name: string; input: openArray[byte]; kinds: set[BonyLoadErrorKind]) =
  let started = epochTime()
  try:
    discard loadBonyBnb(input)
    raise newException(AssertionDefect, name & " unexpectedly loaded")
  except BonyLoadError as exc:
    if exc.kind notin kinds:
      raise newException(
        AssertionDefect,
        &"{name} rejected with {exc.kind}, expected one of {kinds}: {exc.msg}",
      )
  let elapsed = epochTime() - started
  if elapsed > perCaseTimeBudgetSeconds:
    raise newException(AssertionDefect, &"{name} exceeded per-case time budget: {elapsed:.3f}s")

proc expectLoads(name: string; input: openArray[byte]) =
  let started = epochTime()
  try:
    discard loadBonyBnb(input)
  except BonyLoadError as exc:
    raise newException(AssertionDefect, &"{name} unexpectedly rejected with {exc.kind}: {exc.msg}")
  let elapsed = epochTime() - started
  if elapsed > perCaseTimeBudgetSeconds:
    raise newException(AssertionDefect, &"{name} exceeded per-case time budget: {elapsed:.3f}s")

proc expectTypedOrValid(name: string; input: openArray[byte]) =
  let started = epochTime()
  try:
    discard loadBonyBnb(input)
  except BonyLoadError:
    discard
  let elapsed = epochTime() - started
  if elapsed > perCaseTimeBudgetSeconds:
    raise newException(AssertionDefect, &"{name} exceeded per-case time budget: {elapsed:.3f}s")

proc validBnb(): seq[byte] =
  toBonyBnb(skeletonData(skeletonHeader("demo", "0.1.0"), @[boneData("root", "")]))

proc headerWithToc(toc: openArray[BnbTocEntry]; table: BnbStringTable): seq[byte] =
  result.writeHeader(flags = bnbStringTableFlag)
  result.writeToc(toc)
  result.writeStringTable(table)

proc skeletonRecord(namePayload: seq[byte]): seq[byte] =
  result.writeObjectRecord(1, @[BnbPropertyRecord(propertyKey: 1, payload: namePayload)])

proc boneRecord(namePayload: seq[byte]; parentPayload: seq[byte] = @[]): seq[byte] =
  var properties = @[BnbPropertyRecord(propertyKey: 1, payload: namePayload)]
  if parentPayload.len > 0:
    properties.add BnbPropertyRecord(propertyKey: 3, payload: parentPayload)
  result.writeObjectRecord(2, properties)

proc malformedCases(): seq[tuple[name: string; input: seq[byte]; kinds: set[BonyLoadErrorKind]]] =
  result.add ("wrong fingerprint", bytes("B0NY"), {schemaViolation})
  result.add ("truncated header", bytes("BO"), {truncatedInput})

  var unsupportedMajor: seq[byte]
  unsupportedMajor.add bnbFingerprint
  unsupportedMajor.writeVaruint(packedVersion(bnbMajorVersion + 1, 0))
  unsupportedMajor.writeVaruint(bnbStringTableFlag)
  result.add ("unsupported major version", unsupportedMajor, {schemaViolation})

  var badVersion = bytes("BONY")
  badVersion.add @[
    0x80'u8,
    0x80'u8,
    0x80'u8,
    0x80'u8,
    0x80'u8,
    0x80'u8,
    0x80'u8,
    0x80'u8,
    0x80'u8,
    0x80'u8,
    0x00'u8,
  ]
  result.add ("non-terminating header varuint", badVersion, {malformedVarint})

  var nonMinimal: seq[byte]
  nonMinimal.add bnbFingerprint
  nonMinimal.add @[0x80'u8, 0x00'u8]
  result.add ("non-minimal varuint encoding", nonMinimal, {malformedVarint})

  var tocTruncated: seq[byte]
  tocTruncated.writeHeader(flags = bnbStringTableFlag)
  tocTruncated.writeVaruint(1)
  tocTruncated.writeVaruint(1)
  result.add ("truncated toc backing type", tocTruncated, {truncatedInput})

  var invalidUtf8: seq[byte]
  invalidUtf8.writeHeader(flags = bnbStringTableFlag)
  invalidUtf8.writeToc(@[])
  invalidUtf8.writeVaruint(1)
  invalidUtf8.writeVaruint(1)
  invalidUtf8.add 0xff'u8
  result.add ("invalid utf8 string table entry", invalidUtf8, {schemaViolation})

  var longPayload: seq[byte]
  longPayload.writeHeader(flags = 0)
  longPayload.writeToc(@[BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string"))])
  longPayload.writeVaruint(1)
  longPayload.writeVaruint(1)
  longPayload.writeVaruint(8)
  longPayload.add 0'u8
  result.add ("property payload length exceeds remaining input", longPayload, {truncatedInput})

  var table = initStringTable()
  let demo = table.stringPayload("demo")
  let root = table.stringPayload("root")
  var shortBool = headerWithToc(
    @[
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 1007, backingTypeCode: backingTypeCode("bool")),
    ],
    table,
  )
  shortBool.add skeletonRecord(demo)
  shortBool.writeVaruint(2)
  shortBool.writePropertyRecord(1, root)
  shortBool.writePropertyRecord(1007, @[])
  shortBool.writePropertyTerminator()
  shortBool.writeObjectStreamTerminator()
  result.add ("known payload shorter than decoder consumes", shortBool, {schemaViolation})

  var longBool = headerWithToc(
    @[
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 1007, backingTypeCode: backingTypeCode("bool")),
    ],
    table,
  )
  longBool.add skeletonRecord(demo)
  longBool.writeVaruint(2)
  longBool.writePropertyRecord(1, root)
  longBool.writePropertyRecord(1007, @[1'u8, 0'u8])
  longBool.writePropertyTerminator()
  longBool.writeObjectStreamTerminator()
  result.add ("known payload longer than decoder consumes", longBool, {schemaViolation})

  var duplicateProperty = headerWithToc(
    @[BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string"))],
    table,
  )
  duplicateProperty.writeVaruint(1)
  duplicateProperty.writePropertyRecord(1, demo)
  duplicateProperty.writePropertyRecord(1, demo)
  duplicateProperty.writePropertyTerminator()
  duplicateProperty.writeObjectStreamTerminator()
  result.add ("duplicate property key in object", duplicateProperty, {duplicateKey})

  var outOfRangeString = headerWithToc(
    @[BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string"))],
    table,
  )
  var badStringIndex: seq[byte]
  badStringIndex.writeVaruint(99)
  outOfRangeString.add skeletonRecord(badStringIndex)
  outOfRangeString.writeObjectStreamTerminator()
  result.add ("out-of-range string payload index", outOfRangeString, {unknownRequiredReference})

  var missingToc = headerWithToc(@[], table)
  missingToc.add skeletonRecord(demo)
  missingToc.writeObjectStreamTerminator()
  result.add ("property key absent from toc", missingToc, {schemaViolation})

  var unknownMalformedLength = headerWithToc(
    @[BnbTocEntry(propertyKey: 900000, backingTypeCode: 250'u8)],
    table,
  )
  unknownMalformedLength.writeVaruint(999999)
  unknownMalformedLength.writeVaruint(900000)
  unknownMalformedLength.writeVaruint(4)
  unknownMalformedLength.add @[1'u8]
  result.add ("unknown property malformed length", unknownMalformedLength, {truncatedInput})

  var mismatchedToc: seq[byte]
  mismatchedToc.writeHeader(flags = bnbStringTableFlag)
  mismatchedToc.writeVaruint(1)
  mismatchedToc.writeVaruint(1)
  mismatchedToc.add backingTypeCode("f32")
  result.add ("known property toc backing mismatch", mismatchedToc, {invalidBackingType})

  var trailing = validBnb()
  trailing.add 42'u8
  result.add ("trailing bytes after object stream", trailing, {schemaViolation})

  var cycleTable = initStringTable()
  let cycleDemo = cycleTable.stringPayload("demo")
  let boneA = cycleTable.stringPayload("a")
  let boneB = cycleTable.stringPayload("b")
  var cyclicBones = headerWithToc(
    @[
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 3, backingTypeCode: backingTypeCode("string")),
    ],
    cycleTable,
  )
  cyclicBones.add skeletonRecord(cycleDemo)
  cyclicBones.add boneRecord(boneA, boneB)
  cyclicBones.add boneRecord(boneB, boneA)
  cyclicBones.writeObjectStreamTerminator()
  result.add ("cyclic bone parents reject through parent-order validation", cyclicBones, {orderingViolation})

  var duplicateNames = headerWithToc(
    @[BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string"))],
    table,
  )
  duplicateNames.add skeletonRecord(demo)
  duplicateNames.add boneRecord(root)
  duplicateNames.add boneRecord(root)
  duplicateNames.writeObjectStreamTerminator()
  result.add ("duplicate name-addressable bone entries", duplicateNames, {duplicateKey})

  var unknownSlotBoneTable = initStringTable()
  let slotDemo = unknownSlotBoneTable.stringPayload("demo")
  let slotName = unknownSlotBoneTable.stringPayload("slot")
  let missingBone = unknownSlotBoneTable.stringPayload("missing")
  var unknownSlotBone = headerWithToc(
    @[
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 1012, backingTypeCode: backingTypeCode("string")),
    ],
    unknownSlotBoneTable,
  )
  unknownSlotBone.add skeletonRecord(slotDemo)
  unknownSlotBone.writeObjectRecord(1000, @[
    BnbPropertyRecord(propertyKey: 1, payload: slotName),
    BnbPropertyRecord(propertyKey: 1012, payload: missingBone),
  ])
  unknownSlotBone.writeObjectStreamTerminator()
  result.add ("binary out-of-range slot bone reference", unknownSlotBone, {unknownRequiredReference})

  var invalidFlags = headerWithToc(
    @[
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 1007, backingTypeCode: backingTypeCode("bool")),
      BnbTocEntry(propertyKey: 1008, backingTypeCode: backingTypeCode("bool")),
      BnbTocEntry(propertyKey: 1009, backingTypeCode: backingTypeCode("bool")),
    ],
    table,
  )
  invalidFlags.add skeletonRecord(demo)
  invalidFlags.writeVaruint(2)
  invalidFlags.writePropertyRecord(1, root)
  invalidFlags.writePropertyRecord(1007, boolPayload(false))
  invalidFlags.writePropertyRecord(1008, boolPayload(false))
  invalidFlags.writePropertyRecord(1009, boolPayload(true))
  invalidFlags.writePropertyTerminator()
  invalidFlags.writeObjectStreamTerminator()
  result.add ("invalid transform-mode flag triple", invalidFlags, {schemaViolation})

  var hostileCount: seq[byte]
  hostileCount.writeHeader(flags = bnbStringTableFlag)
  hostileCount.writeToc(@[])
  hostileCount.writeVaruint(bnbMaxStringTableEntries + 1)
  result.add ("hostile string-table count limit", hostileCount, {resourceLimitExceeded})

proc skippedUnknownObject(): seq[byte] =
  var table = initStringTable()
  let demo = table.stringPayload("demo")
  let root = table.stringPayload("root")
  result = headerWithToc(
    @[
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 3, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 900000, backingTypeCode: 250'u8),
      BnbTocEntry(propertyKey: 900001, backingTypeCode: 251'u8),
    ],
    table,
  )
  result.add skeletonRecord(demo)
  result.writeVaruint(999999)
  result.writePropertyRecord(900000, @[1'u8, 2'u8, 3'u8])
  result.writePropertyRecord(900001, @[4'u8])
  result.writePropertyTerminator()
  result.add boneRecord(root)
  result.writeObjectStreamTerminator()

proc skippedUnknownProperty(): seq[byte] =
  var table = initStringTable()
  let demo = table.stringPayload("demo")
  let root = table.stringPayload("root")
  result = headerWithToc(
    @[
      BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
      BnbTocEntry(propertyKey: 900000, backingTypeCode: 250'u8),
    ],
    table,
  )
  result.add skeletonRecord(demo)
  result.writeVaruint(2)
  result.writePropertyRecord(1, root)
  result.writePropertyRecord(900000, @[1'u8, 2'u8])
  result.writePropertyTerminator()
  result.writeObjectStreamTerminator()

proc deterministicMutations(seedInput: openArray[byte]) =
  for prefixLen in 0 ..< seedInput.len:
    expectReject("valid file truncated at " & $prefixLen, seedInput[0 ..< prefixLen], {
      truncatedInput,
      malformedVarint,
      schemaViolation,
      unknownRequiredReference,
    })

  var state = 0x5eed1234'u32
  for caseIndex in 0 ..< 512:
    state = state * 1664525'u32 + 1013904223'u32
    var mutated = @seedInput
    let offset = int(state mod uint32(mutated.len))
    state = state * 1664525'u32 + 1013904223'u32
    mutated[offset] = mutated[offset] xor byte(1'u32 shl (state mod 8'u32))
    if caseIndex mod 7 == 0 and mutated.len > 2:
      mutated.setLen(int((state mod uint32(mutated.len - 1)) + 1))
    expectTypedOrValid("deterministic mutation " & $caseIndex, mutated)

let started = epochTime()
let valid = validBnb()
expectLoads("baseline valid bnb", valid)
expectLoads("unknown object properties are skipped", skippedUnknownObject())
expectLoads("unknown known-object property is skipped", skippedUnknownProperty())

for item in malformedCases():
  expectReject(item.name, item.input, item.kinds)

deterministicMutations(valid)

let elapsed = epochTime() - started
if elapsed > 10.0:
  raise newException(AssertionDefect, &".bnb fuzz gate exceeded time budget: {elapsed:.3f}s")

echo &".bnb fuzz gate passed in {elapsed:.3f}s"
