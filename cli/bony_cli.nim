## Minimal M6 conversion CLI.

import std/os

import bony


proc usage(): string =
  "usage: bony json-to-bnb <input.bony> <output.bnb>\n" &
    "       bony bnb-to-json <input.bnb> <output.bony>"


proc readBytes(path: string): seq[byte] =
  let content = readFile(path)
  result = newSeq[byte](content.len)
  for index, ch in content:
    result[index] = byte(ord(ch))


proc writeBytes(path: string; bytes: openArray[byte]) =
  var content = newString(bytes.len)
  for index, value in bytes:
    content[index] = char(value)
  writeFile(path, content)


proc main() =
  let args = commandLineParams()
  if args.len != 3:
    quit(usage(), QuitFailure)

  try:
    case args[0]
    of "json-to-bnb":
      writeBytes(args[2], toBonyBnb(loadBonyJson(readFile(args[1]))))
    of "bnb-to-json":
      writeFile(args[2], toBonyJson(loadKnownBonyBnb(readBytes(args[1]))))
    else:
      quit(usage(), QuitFailure)
  except BonyLoadError as exc:
    quit("bony: " & exc.msg, QuitFailure)
  except OSError as exc:
    quit("bony: " & exc.msg, QuitFailure)


when isMainModule:
  main()
