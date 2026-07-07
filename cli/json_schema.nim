## Small JSON validation helpers for CLI import/script formats.

import std/[json, math]

type
  JsonSchemaRaiser* = proc(target, capability, message: string) {.closure.}


proc validateKeys*(node: JsonNode; allowed: openArray[string]; target: string; fail: JsonSchemaRaiser) =
  if node.kind != JObject:
    fail(target, "object", "expected object")
  for key in node.keys:
    var found = false
    for allowedKey in allowed:
      if key == allowedKey:
        found = true
        break
    if not found:
      fail(target, "unknownKey", "unknown key: " & key)


proc requireObject*(
  node: JsonNode;
  target: string;
  fail: JsonSchemaRaiser;
  capability = "object";
  message = "expected object";
): JsonNode =
  if node.kind != JObject:
    fail(target, capability, message)
  node


proc requireArray*(
  node: JsonNode;
  target: string;
  fail: JsonSchemaRaiser;
  capability = "array";
  message = "expected array";
): JsonNode =
  if node.kind != JArray:
    fail(target, capability, message)
  node


proc requireField*(
  node: JsonNode;
  key, target: string;
  fail: JsonSchemaRaiser;
  capability = "";
  message = "";
): JsonNode =
  if not node.hasKey(key):
    let cap = if capability.len > 0: capability else: key
    let msg = if message.len > 0: message else: "missing required field: " & key
    fail(target, cap, msg)
  node[key]


proc requireNumber*(
  node: JsonNode;
  target, capability: string;
  fail: JsonSchemaRaiser;
  message = "expected number";
  finiteMessage = "expected finite number";
): float64 =
  if node.kind notin {JInt, JFloat}:
    fail(target, capability, message)
  result = node.getFloat()
  if classify(result) in {fcNan, fcInf, fcNegInf}:
    fail(target, capability, finiteMessage)


proc requireNumberType*(
  node: JsonNode;
  target, capability: string;
  fail: JsonSchemaRaiser;
  message = "expected number";
): float64 =
  if node.kind notin {JInt, JFloat}:
    fail(target, capability, message)
  node.getFloat()


proc requirePositiveInt*(
  node: JsonNode;
  target, capability: string;
  fail: JsonSchemaRaiser;
  message = "expected integer";
  positiveMessage = "expected positive integer";
): int =
  if node.kind != JInt:
    fail(target, capability, message)
  result = node.getInt()
  if result <= 0:
    fail(target, capability, positiveMessage)


proc optionalString*(
  node: JsonNode;
  key, defaultValue, target: string;
  fail: JsonSchemaRaiser;
  message = "expected string";
): string =
  if not node.hasKey(key):
    return defaultValue
  if node[key].kind != JString:
    fail(target, key, message)
  node[key].getStr()
