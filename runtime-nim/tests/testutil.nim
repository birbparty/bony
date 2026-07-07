import std/[os, osproc, streams, strutils]

import bony

proc raisesBonyLoadError*(input: string): bool =
  try:
    discard loadBonyJson(input)
    false
  except BonyLoadError:
    true

proc raisesBonyLoadError*(input: string; kind: BonyLoadErrorKind): bool =
  try:
    discard loadBonyJson(input)
    false
  except BonyLoadError as exc:
    exc.kind == kind

proc raisesBonyLoadError*(action: proc()): bool =
  try:
    action()
    false
  except BonyLoadError:
    true

proc raisesBonyLoadError*(action: proc(); kind: BonyLoadErrorKind): bool =
  try:
    action()
    false
  except BonyLoadError as exc:
    exc.kind == kind

proc raisesAnyBonyLoadError*(action: proc()): bool =
  ## True only if `action` raises a BonyLoadError of any kind. A non-BonyLoadError
  ## propagates so malformed input assertions still catch decoder defects.
  try:
    action()
    false
  except BonyLoadError:
    true

proc closeWithin*(actual, expected, tolerance: float64): bool =
  abs(actual - expected) <= tolerance

proc closeTo*(actual, expected: float64): bool =
  closeWithin(actual, expected, 1e-9)

proc canonicalText*(path: string): string =
  readFile(path).strip()

proc canonicalJson*(text: string; asset = false): string =
  if asset:
    toBonyJson(loadBonyJsonAsset(text))
  else:
    toBonyJson(loadBonyJson(text))

proc readBytes*(path: string): seq[byte] =
  let content = readFile(path)
  result = newSeq[byte](content.len)
  for index, ch in content:
    result[index] = byte(ord(ch))

proc runProcess*(
  binary: string;
  args: openArray[string],
): tuple[output: string; exitCode: int] =
  let process = startProcess(binary, args = args, options = {poStdErrToStdOut})
  let output = process.outputStream.readAll()
  let exitCode = process.waitForExit()
  process.close()
  (output, exitCode)

proc stringPayload*(table: var BnbStringTable; value: string): seq[byte] =
  result.writeStringPayload(table, value)

proc boolPayload*(value: bool): seq[byte] =
  if value:
    @[1'u8]
  else:
    @[0'u8]

template checkGolden*(
  assetPath, expectedPath, outPrefix, sampleName: string;
  argsAfterOutput: openArray[string],
) =
  mixin writeNumericGolden
  let outPath = getTempDir() / (
    outPrefix & "_" & sampleName & "_" & extractFilename(assetPath) & ".json"
  )
  try:
    var args = @[assetPath, outPath]
    for arg in argsAfterOutput:
      args.add(arg)
    writeNumericGolden(args)
    doAssert canonicalText(outPath) == canonicalText(expectedPath)
  finally:
    if fileExists(outPath):
      removeFile(outPath)

template checkStateMachineGolden*(
  assetPath, expectedPath, outPrefix, sampleName, stateMachine, scriptPath: string,
) =
  checkGolden(assetPath, expectedPath, outPrefix, sampleName, @[
    "--state-machine", stateMachine,
    "--input-script", scriptPath,
    "--sample", sampleName,
  ])

template checkInputScriptGolden*(
  assetPath, expectedPath, outPrefix, sampleName, scriptPath: string,
) =
  checkGolden(assetPath, expectedPath, outPrefix, sampleName, @[
    "--input-script", scriptPath,
    "--sample", sampleName,
  ])
