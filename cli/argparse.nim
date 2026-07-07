## Tiny positional argument cursor for command-specific CLI parsers.

type
  ArgCursor* = object
    args*: seq[string]
    index*: int
    usageText*: string


proc initArgCursor*(args: seq[string]; usageText: string): ArgCursor =
  ArgCursor(args: args, usageText: usageText)


proc done*(cursor: ArgCursor): bool =
  cursor.index >= cursor.args.len


proc current*(cursor: ArgCursor): string =
  cursor.args[cursor.index]


proc advance*(cursor: var ArgCursor) =
  inc cursor.index


proc requireValue*(cursor: var ArgCursor; flag: string): string =
  if cursor.index + 1 >= cursor.args.len:
    quit(cursor.usageText, QuitFailure)
  result = cursor.args[cursor.index + 1]
  cursor.index += 2


proc failUsage*(cursor: ArgCursor) =
  quit(cursor.usageText, QuitFailure)
