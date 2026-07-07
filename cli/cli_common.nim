## Shared helpers and diagnostics for the bony CLI.

import std/[parseutils, strutils]

import bony


type
  CliDiagnosticKind* = enum
    cliSchemaViolation = "schemaViolation"
    cliUnsupportedFeature = "unsupportedFeature"
    cliInvalidReference = "invalidReference"
    cliCycleDetected = "cycleDetected"
    cliMissingAsset = "missingAsset"
    cliUnsupportedVersion = "unsupportedVersion"

  CliDiagnostic* = object of CatchableError
    kind*: CliDiagnosticKind
    target*: string
    capability*: string


proc newCliDiagnostic*(kind: CliDiagnosticKind; target, capability, message: string): ref CliDiagnostic =
  new(result)
  result.kind = kind
  result.target = target
  result.capability = capability
  result.msg = message


proc raiseCli*(kind: CliDiagnosticKind; target, capability, message: string) =
  raise newCliDiagnostic(kind, target, capability, message)


proc cliMessage*(exc: ref CliDiagnostic): string =
  result = $exc.kind
  if exc.target.len > 0:
    result.add " target=" & exc.target
  if exc.capability.len > 0:
    result.add " capability=" & exc.capability
  if exc.msg.len > 0:
    result.add " " & exc.msg


proc raiseLottie*(kind: CliDiagnosticKind; target, capability, message: string) =
  raiseCli(kind, target, capability, message)


proc raiseDb*(kind: CliDiagnosticKind; target, capability, message: string) =
  raiseCli(kind, target, capability, message)


proc raiseLottieSchema*(target, capability, message: string) =
  raiseLottie(cliSchemaViolation, target, capability, message)


proc raiseDbSchema*(target, capability, message: string) =
  raiseDb(cliSchemaViolation, target, capability, message)


proc raiseBonySchema*(target, capability, message: string) =
  raise newBonyLoadError(schemaViolation, message)


proc readBytes*(path: string): seq[byte] =
  let content = readFile(path)
  result = newSeq[byte](content.len)
  for index, ch in content:
    result[index] = byte(ord(ch))


proc writeBytes*(path: string; bytes: openArray[byte]) =
  var content = newString(bytes.len)
  for index, value in bytes:
    content[index] = char(value)
  writeFile(path, content)


proc parseFloatArg*(value, name: string): float64 =
  var parsed: float
  let consumed = parseFloat(value, parsed)
  if consumed != value.len:
    raise newBonyLoadError(schemaViolation, name & " must be a number")
  quantizeF32(parsed, name)


proc parsePositiveIntArg*(value, name: string): int =
  var parsed: int
  let consumed = parseInt(value, parsed)
  if consumed != value.len or parsed <= 0:
    raise newBonyLoadError(schemaViolation, name & " must be a positive integer")
  parsed


proc parseNonNegativeIntArg*(value, name: string): int =
  var parsed: int
  let consumed = parseInt(value, parsed)
  if consumed != value.len or parsed < 0:
    raise newBonyLoadError(schemaViolation, name & " must be a non-negative integer")
  parsed


proc requireSetupPoseTime*(time: float64) =
  if time != 0.0:
    raise newBonyLoadError(
      schemaViolation,
      "--t is reserved until serialized animations are available; use --t 0 for setup-pose output",
    )


const validOrigins* = ["center", "top-left"]
const originErrMsg* = "origin must be center or top-left"


proc loadInputSkeleton*(path: string): SkeletonData =
  if path.toLowerAscii.endsWith(".bnb"):
    loadBonyBnb(readBytes(path))
  else:
    loadBonyJson(readFile(path))


proc loadInputAsset*(path: string): BonyAsset =
  if path.toLowerAscii.endsWith(".bnb"):
    loadBonyBnbAsset(readBytes(path))
  else:
    loadBonyJsonAsset(readFile(path))


proc applyViewportTransform*(batches: seq[DrawBatch]; width, height: int): seq[DrawBatch] =
  # Translate world-space vertices to pixel space for `bony play` image output.
  # Transform: screen_x = world_x + width/2; screen_y = height/2 - world_y.
  # This places the skeleton origin at the viewport centre and flips y (world is
  # y-up; pixels are y-down). Rigs with geometry within ±width/2 and ±height/2
  # of the origin will be visible; larger or off-centre rigs may still clip.
  # For odd dimensions, width/2 and height/2 are 0.5-fractional (e.g. 127.5 for
  # width=255), which is harmless — vertices land at half-pixel offsets and the
  # rasterizer rounds to the nearest integer via the normal fill rule.
  #
  # INVARIANT: only `vertices` are rewritten to screen space; `batch.world` and
  # `clipId` remain in world space and must not be mixed with the transformed
  # vertices by any future consumer.
  let cx = float64(width) * 0.5
  let cy = float64(height) * 0.5
  result = batches
  for i in 0 ..< result.len:
    for j in 0 ..< result[i].vertices.len:
      result[i].vertices[j].x = result[i].vertices[j].x + cx
      result[i].vertices[j].y = cy - result[i].vertices[j].y



proc rejectUnsupportedFeature*(target, capability, message: string) =
  raiseCli(cliUnsupportedFeature, target, capability, message)


proc requireTier1*(supported: bool; target, capability, message: string) =
  if not supported:
    rejectUnsupportedFeature(target, capability, message)
