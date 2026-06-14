## M6 .bnb binary framing: header, ToC, LEB128, and property records.

import std/[algorithm, unicode, tables]

import bony/generated/wire
import bony/model

const
  bnbFingerprint* = [byte(ord('B')), byte(ord('O')), byte(ord('N')), byte(ord('Y'))]
  bnbMajorVersion* = 0'u64
  bnbMinorVersion* = 1'u64
  bnbEmbeddedAtlasFlag* = 1'u64
  bnbStringTableFlag* = 1'u64 shl 1
  bnbKnownFlags* = bnbStringTableFlag or bnbEmbeddedAtlasFlag
  bnbMaxPropertyPayloadBytes* = 67108864'u64
  bnbMaxStringTableEntries* = 1048576'u64
  bnbMaxStringBytes* = 1048576'u64
  maxVaruintBytes = 10
  maxTocEntries = 65536'u64

type
  BnbHeader* = object
    major*: uint64
    minor*: uint64
    flags*: uint64

  BnbTocEntry* = object
    propertyKey*: uint64
    backingTypeCode*: uint8

  BnbPropertyRecord* = object
    propertyKey*: uint64
    payload*: seq[byte]

  BnbStringTable* = object
    values*: seq[string]
    indexes: Table[string, uint64]


proc packedVersion*(major = bnbMajorVersion; minor = bnbMinorVersion): uint64 =
  (major shl 16) or minor


proc unpackVersion*(value: uint64): tuple[major, minor: uint64] =
  (major: value shr 16, minor: value and 0xffff'u64)


proc writeVaruint*(output: var seq[byte]; value: uint64) =
  var remaining = value
  while remaining >= 0x80'u64:
    output.add byte((remaining and 0x7f'u64) or 0x80'u64)
    remaining = remaining shr 7
  output.add byte(remaining)


proc writeStringBytes(output: var seq[byte]; value: string) =
  if uint64(value.len) > bnbMaxStringBytes:
    raise newBonyLoadError(resourceLimitExceeded, ".bnb string exceeds maximum UTF-8 byte length")
  output.writeVaruint(uint64(value.len))
  for ch in value:
    output.add byte(ord(ch))


proc validateStringValue(value: string) =
  if uint64(value.len) > bnbMaxStringBytes:
    raise newBonyLoadError(resourceLimitExceeded, ".bnb string exceeds maximum UTF-8 byte length")
  if value.validateUtf8 != -1:
    raise newBonyLoadError(schemaViolation, ".bnb string is not valid UTF-8")
  for rune in value.runes:
    let scalar = int(rune)
    if scalar >= 0xD800 and scalar <= 0xDFFF:
      raise newBonyLoadError(schemaViolation, ".bnb string is not a valid Unicode scalar sequence")


proc readVaruint*(input: openArray[byte]; index: var int): uint64 =
  let start = index
  var shift = 0
  while true:
    if index >= input.len:
      raise newBonyLoadError(truncatedInput, "truncated varuint")
    if index - start >= maxVaruintBytes:
      raise newBonyLoadError(malformedVarint, "varuint is too long")
    let value = uint64(input[index])
    inc index
    if shift == 63 and (value and 0x7e'u64) != 0:
      raise newBonyLoadError(malformedVarint, "varuint overflows uint64")
    result = result or ((value and 0x7f'u64) shl shift)
    if (value and 0x80'u64) == 0:
      break
    shift += 7
  let encodedLen = index - start
  if encodedLen > 1 and result < (1'u64 shl (7 * (encodedLen - 1))):
    raise newBonyLoadError(malformedVarint, "varuint is not minimally encoded")


proc writeVarint*(output: var seq[byte]; value: int64) =
  let encoded = (uint64(value) shl 1) xor uint64(value shr 63)
  output.writeVaruint(encoded)


proc readVarint*(input: openArray[byte]; index: var int): int64 =
  let encoded = input.readVaruint(index)
  let magnitude = int64(encoded shr 1)
  if (encoded and 1'u64) == 0:
    magnitude
  else:
    -magnitude - 1


proc initStringTable*(): BnbStringTable =
  BnbStringTable(indexes: initTable[string, uint64]())


proc intern*(table: var BnbStringTable; value: string): uint64 =
  validateStringValue(value)
  if value in table.indexes:
    return table.indexes[value]
  if uint64(table.values.len) >= bnbMaxStringTableEntries:
    raise newBonyLoadError(resourceLimitExceeded, ".bnb string table has too many entries")
  result = uint64(table.values.len)
  table.values.add value
  table.indexes[value] = result


proc appendStringTableValue(table: var BnbStringTable; value: string) =
  validateStringValue(value)
  if uint64(table.values.len) >= bnbMaxStringTableEntries:
    raise newBonyLoadError(resourceLimitExceeded, ".bnb string table has too many entries")
  if value notin table.indexes:
    table.indexes[value] = uint64(table.values.len)
  table.values.add value


proc stringAt*(table: BnbStringTable; index: uint64): string =
  if index >= uint64(table.values.len):
    raise newBonyLoadError(unknownRequiredReference, ".bnb string index out of range: " & $index)
  table.values[int(index)]


proc writeStringTable*(output: var seq[byte]; table: BnbStringTable) =
  output.writeVaruint(uint64(table.values.len))
  for value in table.values:
    validateStringValue(value)
    output.writeStringBytes(value)


proc readStringTable*(input: openArray[byte]; index: var int): BnbStringTable =
  result = initStringTable()
  let count = input.readVaruint(index)
  if count > bnbMaxStringTableEntries:
    raise newBonyLoadError(resourceLimitExceeded, ".bnb string table has too many entries")
  for _ in 0'u64 ..< count:
    let byteLength = input.readVaruint(index)
    if byteLength > bnbMaxStringBytes:
      raise newBonyLoadError(resourceLimitExceeded, ".bnb string exceeds maximum UTF-8 byte length")
    if byteLength > uint64(input.len - index):
      raise newBonyLoadError(truncatedInput, "truncated .bnb string table entry")
    let endIndex = index + int(byteLength)
    var value = newString(int(byteLength))
    for offset in 0 ..< int(byteLength):
      value[offset] = char(input[index + offset])
    index = endIndex
    result.appendStringTableValue(value)


proc writeStringPayload*(output: var seq[byte]; table: var BnbStringTable; value: string) =
  output.writeVaruint(table.intern(value))


proc readStringPayload*(payload: openArray[byte]; table: BnbStringTable): string =
  var index = 0
  let stringIndex = payload.readVaruint(index)
  if index != payload.len:
    raise newBonyLoadError(schemaViolation, ".bnb string payload has trailing bytes")
  table.stringAt(stringIndex)


proc backingTypeCode*(backingType: string): uint8 =
  for item in bonyBackingTypes:
    if item.id == backingType:
      return item.code
  raise newBonyLoadError(invalidBackingType, "unknown backing type: " & backingType)


proc propertyBackingTypeCode*(propertyKey: uint64): uint8 =
  for item in bonyPropertyKeys:
    if item.key == propertyKey:
      return backingTypeCode(item.backingType)
  raise newBonyLoadError(unknownRequiredReference, "unknown property key: " & $propertyKey)


proc isKnownPropertyKey*(propertyKey: uint64): bool =
  for item in bonyPropertyKeys:
    if item.key == propertyKey:
      return true
  false


proc writeHeader*(output: var seq[byte]; flags = bnbStringTableFlag; major = bnbMajorVersion; minor = bnbMinorVersion) =
  if (flags and not bnbKnownFlags) != 0:
    raise newBonyLoadError(schemaViolation, "unknown .bnb header flags")
  output.add bnbFingerprint
  output.writeVaruint(packedVersion(major, minor))
  output.writeVaruint(flags)


proc readHeader*(input: openArray[byte]; index: var int): BnbHeader =
  if input.len - index < bnbFingerprint.len:
    raise newBonyLoadError(truncatedInput, "truncated .bnb fingerprint")
  for expected in bnbFingerprint:
    if input[index] != expected:
      raise newBonyLoadError(schemaViolation, "invalid .bnb fingerprint")
    inc index
  let version = unpackVersion(input.readVaruint(index))
  if version.major != bnbMajorVersion:
    raise newBonyLoadError(schemaViolation, "unsupported .bnb major version: " & $version.major)
  let flags = input.readVaruint(index)
  if (flags and not bnbKnownFlags) != 0:
    raise newBonyLoadError(schemaViolation, "unknown .bnb header flags")
  BnbHeader(major: version.major, minor: version.minor, flags: flags)


proc tocOrder(a, b: BnbTocEntry): int = cmp(a.propertyKey, b.propertyKey)


proc normalizedToc(entries: openArray[BnbTocEntry]): seq[BnbTocEntry] =
  if uint64(entries.len) > maxTocEntries:
    raise newBonyLoadError(schemaViolation, "too many .bnb ToC entries")
  var seen = initTable[uint64, uint8]()
  for entry in entries:
    if entry.propertyKey == 0:
      raise newBonyLoadError(schemaViolation, ".bnb ToC property key 0 is reserved")
    if entry.propertyKey in seen:
      raise newBonyLoadError(duplicateKey, "duplicate .bnb ToC property key: " & $entry.propertyKey)
    if entry.propertyKey.isKnownPropertyKey:
      let expected = propertyBackingTypeCode(entry.propertyKey)
      if entry.backingTypeCode != expected:
        raise newBonyLoadError(invalidBackingType, ".bnb ToC backing type mismatch: " & $entry.propertyKey)
    seen[entry.propertyKey] = entry.backingTypeCode
    result.add entry
  result.sort(tocOrder)


proc writeToc*(output: var seq[byte]; entries: openArray[BnbTocEntry]) =
  let toc = normalizedToc(entries)
  output.writeVaruint(uint64(toc.len))
  for entry in toc:
    output.writeVaruint(entry.propertyKey)
    output.add entry.backingTypeCode


proc readToc*(input: openArray[byte]; index: var int): seq[BnbTocEntry] =
  let count = input.readVaruint(index)
  if count > maxTocEntries:
    raise newBonyLoadError(schemaViolation, "too many .bnb ToC entries")
  for _ in 0'u64 ..< count:
    let propertyKey = input.readVaruint(index)
    if index >= input.len:
      raise newBonyLoadError(truncatedInput, "truncated .bnb ToC backing type")
    let backingTypeCode = uint8(input[index])
    inc index
    result.add BnbTocEntry(propertyKey: propertyKey, backingTypeCode: backingTypeCode)
  result = normalizedToc(result)


proc backingTypeCodeFor*(toc: openArray[BnbTocEntry]; propertyKey: uint64): uint8 =
  for entry in toc:
    if entry.propertyKey == propertyKey:
      return entry.backingTypeCode
  raise newBonyLoadError(schemaViolation, ".bnb property key missing from ToC: " & $propertyKey)


proc writePropertyRecord*(output: var seq[byte]; propertyKey: uint64; payload: openArray[byte]) =
  if propertyKey == 0:
    raise newBonyLoadError(schemaViolation, ".bnb property key 0 is a terminator")
  output.writeVaruint(propertyKey)
  output.writeVaruint(uint64(payload.len))
  output.add payload


proc writePropertyTerminator*(output: var seq[byte]) =
  output.writeVaruint(0)


proc readPropertyRecord*(input: openArray[byte]; index: var int; toc: openArray[BnbTocEntry]): BnbPropertyRecord =
  result.propertyKey = input.readVaruint(index)
  if result.propertyKey == 0:
    return
  discard toc.backingTypeCodeFor(result.propertyKey)
  let byteLength = input.readVaruint(index)
  if byteLength > bnbMaxPropertyPayloadBytes:
    raise newBonyLoadError(resourceLimitExceeded, ".bnb property payload exceeds maximum length")
  if byteLength > uint64(input.len - index):
    raise newBonyLoadError(truncatedInput, ".bnb property payload exceeds remaining input")
  let payloadEnd = index + int(byteLength)
  result.payload = @input[index ..< payloadEnd]
  index = payloadEnd


proc skipPropertyRecord*(input: openArray[byte]; index: var int; toc: openArray[BnbTocEntry]): uint64 =
  result = input.readVaruint(index)
  if result == 0:
    return
  discard toc.backingTypeCodeFor(result)
  let byteLength = input.readVaruint(index)
  if byteLength > bnbMaxPropertyPayloadBytes:
    raise newBonyLoadError(resourceLimitExceeded, ".bnb property payload exceeds maximum length")
  if byteLength > uint64(input.len - index):
    raise newBonyLoadError(truncatedInput, ".bnb property payload exceeds remaining input")
  index += int(byteLength)
