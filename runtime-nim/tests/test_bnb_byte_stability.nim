import bony

proc stringPayload(table: var BnbStringTable; value: string): seq[byte] =
  result.writeStringPayload(table, value)

proc f32Payload(value: float64): seq[byte] =
  let stored = float32(quantizeF32(value))
  let bits = cast[uint32](stored)
  @[
    byte(bits and 0xff'u32),
    byte((bits shr 8) and 0xff'u32),
    byte((bits shr 16) and 0xff'u32),
    byte((bits shr 24) and 0xff'u32),
  ]

proc boolPayload(value: bool): seq[byte] =
  if value:
    @[1'u8]
  else:
    @[0'u8]

proc varintPayload(value: int): seq[byte] =
  result.writeVarint(int64(value))

proc f64Payload(value: float64): seq[byte] =
  let bits = cast[uint64](requireFiniteF64(value))
  for shift in countup(0, 56, 8):
    result.add byte((bits shr shift) and 0xff'u64)

proc currentModelFixture(): SkeletonData =
  skeletonData(
    skeletonHeader("demo", "0.2.0"),
    @[
      boneData("root", "", localTransform(x = -0.0, y = 2.5, rotation = 45.25)),
      boneData(
        "child",
        "root",
        localTransform(
          x = 3.25,
          inheritRotation = false,
          inheritScale = false,
          inheritReflection = false,
          transformMode = onlyTranslation,
        ),
      ),
    ],
    @[slotData("bodySlot", "root", "body")],
    @[regionAttachment("body", 8.0, 4.0)],
    @[pathAttachmentData("curve", 0.0, 0.0, 1.25, 2.5, 3.5, 4.75, 6.0, 7.25)],
    @[pathConstraintData("follow", "child", "root", "curve", order = -1)],
  )

proc viaJson(bytes: openArray[byte]): seq[byte] =
  toBonyBnb(loadBonyJson(toBonyJson(loadKnownBonyBnb(bytes))))

proc expectStable(name: string; bytes: seq[byte]) =
  let cycled = viaJson(bytes)
  doAssert cycled == bytes, name & " changed after bnb->json->bnb"

proc expectCanonicalizes(name: string; bytes, canonical: seq[byte]) =
  let cycled = viaJson(bytes)
  doAssert cycled == canonical, name & " did not canonicalize to expected bytes"
  doAssert viaJson(cycled) == cycled, name & " canonicalized bytes are not stable"

proc nonCanonicalCurrentModelBytes(): seq[byte] =
  var table = initStringTable()
  let demo = table.stringPayload("demo")
  let version = table.stringPayload("0.2.0")
  let root = table.stringPayload("root")
  let child = table.stringPayload("child")
  let onlyTranslationName = table.stringPayload("onlyTranslation")
  let bodySlot = table.stringPayload("bodySlot")
  let body = table.stringPayload("body")
  let curve = table.stringPayload("curve")
  let follow = table.stringPayload("follow")

  result.writeHeader(flags = bnbStringTableFlag)
  result.writeVaruint(25)
  for entry in [
    BnbTocEntry(propertyKey: 4010, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4009, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4008, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4007, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4006, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4005, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4004, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4003, backingTypeCode: backingTypeCode("f64")),
    BnbTocEntry(propertyKey: 4002, backingTypeCode: backingTypeCode("varint")),
    BnbTocEntry(propertyKey: 4001, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 4000, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1015, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 1014, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 1013, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1012, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1010, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1009, backingTypeCode: backingTypeCode("bool")),
    BnbTocEntry(propertyKey: 1008, backingTypeCode: backingTypeCode("bool")),
    BnbTocEntry(propertyKey: 1007, backingTypeCode: backingTypeCode("bool")),
    BnbTocEntry(propertyKey: 1002, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 1001, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 1000, backingTypeCode: backingTypeCode("f32")),
    BnbTocEntry(propertyKey: 3, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 2, backingTypeCode: backingTypeCode("string")),
    BnbTocEntry(propertyKey: 1, backingTypeCode: backingTypeCode("string")),
  ]:
    result.writeVaruint(entry.propertyKey)
    result.add entry.backingTypeCode
  result.writeStringTable(table)

  result.writeVaruint(1)
  result.writePropertyRecord(2, version)
  result.writePropertyRecord(1, demo)
  result.writePropertyTerminator()

  result.writeVaruint(2)
  result.writePropertyRecord(1002, f32Payload(45.25))
  result.writePropertyRecord(1001, f32Payload(2.5))
  result.writePropertyRecord(1, root)
  result.writePropertyTerminator()

  result.writeVaruint(2)
  result.writePropertyRecord(1010, onlyTranslationName)
  result.writePropertyRecord(1009, boolPayload(false))
  result.writePropertyRecord(1008, boolPayload(false))
  result.writePropertyRecord(1007, boolPayload(false))
  result.writePropertyRecord(1000, f32Payload(3.25))
  result.writePropertyRecord(3, root)
  result.writePropertyRecord(1, child)
  result.writePropertyTerminator()

  result.writeVaruint(1000)
  result.writePropertyRecord(1013, body)
  result.writePropertyRecord(1012, root)
  result.writePropertyRecord(1, bodySlot)
  result.writePropertyTerminator()

  result.writeVaruint(1001)
  result.writePropertyRecord(1015, f32Payload(4.0))
  result.writePropertyRecord(1014, f32Payload(8.0))
  result.writePropertyRecord(1, body)
  result.writePropertyTerminator()

  result.writeVaruint(4001)
  result.writePropertyRecord(4010, f64Payload(7.25))
  result.writePropertyRecord(4009, f64Payload(6.0))
  result.writePropertyRecord(4008, f64Payload(4.75))
  result.writePropertyRecord(4007, f64Payload(3.5))
  result.writePropertyRecord(4006, f64Payload(2.5))
  result.writePropertyRecord(4005, f64Payload(1.25))
  result.writePropertyRecord(4004, f64Payload(0.0))
  result.writePropertyRecord(4003, f64Payload(0.0))
  result.writePropertyRecord(1, curve)
  result.writePropertyTerminator()

  result.writeVaruint(4000)
  result.writePropertyRecord(4002, varintPayload(-1))
  result.writePropertyRecord(4001, curve)
  result.writePropertyRecord(4000, root)
  result.writePropertyRecord(1012, child)
  result.writePropertyRecord(1, follow)
  result.writePropertyTerminator()

  result.writeObjectStreamTerminator()

let canonical = toBonyBnb(currentModelFixture())
expectStable("canonical current model fixture", canonical)
expectCanonicalizes("non-canonical toc and property order", nonCanonicalCurrentModelBytes(), canonical)

let minimal = toBonyBnb(skeletonData(skeletonHeader("minimal", "0.1.0"), @[boneData("root", "")]))
expectStable("default omission fixture", minimal)

echo ".bnb byte-stability gate passed"
