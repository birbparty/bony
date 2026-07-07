## Shared metadata helpers for generated wire defaults.

import std/[json, strutils, tables]

import bony/generated/wire
import bony/model

proc defaultKey(objectId, propertyId: string): string =
  objectId & "\x1f" & propertyId

let bonyDefaultValues = block:
  var values = initTable[string, string]()
  for entry in bonyPropertyDefaults:
    values[defaultKey(entry.objectId, entry.propertyId)] = entry.value
  values

proc defaultRaw(objectId, propertyId: string): string =
  let key = defaultKey(objectId, propertyId)
  if key in bonyDefaultValues:
    return bonyDefaultValues[key]
  raise newBonyLoadError(schemaViolation, "missing generated default for " & objectId & "." & propertyId)

proc defaultString*(objectId, propertyId: string): string =
  parseJson(defaultRaw(objectId, propertyId)).getStr()

proc defaultFor*(objectId, propertyId: string): string =
  defaultString(objectId, propertyId)

proc defaultFloat*(objectId, propertyId: string): float64 =
  parseJson(defaultRaw(objectId, propertyId)).getFloat()

proc defaultBool*(objectId, propertyId: string): bool =
  parseJson(defaultRaw(objectId, propertyId)).getBool()

proc defaultInt*(objectId, propertyId: string): int =
  defaultRaw(objectId, propertyId).parseInt()
