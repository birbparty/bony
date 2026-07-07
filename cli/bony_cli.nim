## Headless bony CLI harness core.

import bony
import std/os

import cli_common
import commands/auto_weights
import commands/golden_gen
import commands/import_dragonbones
import commands/import_lottie
import commands/pack_atlas
import commands/play


proc usage(): string =
    "usage: bony json-to-bnb <input.bony> <output.bnb>\n" &
    "       bony bnb-to-json <input.bnb> <output.bony>\n" &
    "       bony import-lottie <input.json> <output.bony> --assets-dir images [--setup-only] [--origin center|top-left]\n" &
    "       bony import-dragonbones <input_ske.json> <output.bony> [--assets-dir images] [--setup-only] [--allow-multiple-armatures]\n" &
    "       bony golden-gen <input.bony|input.bnb> <output.json> [--t seconds] [--animation clip]\n" &
    "       bony golden-gen <input.bony|input.bnb> <output.json> --input-script <script.json> --sample <name-or-index>\n" &
    "       bony golden-gen <input.bony|input.bnb> <output.json> --state-machine <name> --input-script <script.json> --sample <name-or-index>\n" &
    "       bony play <input.bony|input.bnb> --out frame.png [--t seconds] [--width px] [--height px] [--origin center|top-left]\n" &
    "       bony play <input.bony|input.bnb> --state-machine <name> --input-script <script.json> --out frame.png [--width px] [--height px] [--origin center|top-left]\n" &
    "       bony pack-atlas <images-dir> --out-dir <dir> [--page-size 2048] [--padding 2]\n" &
    "       bony auto-weights <input.json> <output.json>"


proc main() =
  let args = commandLineParams()
  if args.len == 0:
    quit(usage(), QuitFailure)

  try:
    case args[0]
    of "json-to-bnb":
      if args.len != 3:
        quit(usage(), QuitFailure)
      writeBytes(args[2], toBonyBnb(loadBonyJsonAsset(readFile(args[1]))))
    of "bnb-to-json":
      if args.len != 3:
        quit(usage(), QuitFailure)
      writeFile(args[2], toBonyJson(loadKnownBonyBnbAsset(readBytes(args[1]))))
    of "import-lottie":
      importLottie(args[1 .. ^1], usage())
    of "import-dragonbones":
      importDragonbones(args[1 .. ^1], usage())
    of "golden-gen":
      writeNumericGolden(args[1 .. ^1], usage())
    of "play":
      renderSetupPose(args[1 .. ^1], usage())
    of "pack-atlas":
      packAtlasCmd(args[1 .. ^1], usage())
    of "auto-weights":
      autoWeightsCmd(args[1 .. ^1], usage())
    else:
      quit(usage(), QuitFailure)
  except CliDiagnostic as exc:
    quit("bony: " & exc.cliMessage, QuitFailure)
  except BonyLoadError as exc:
    quit("bony: " & exc.msg, QuitFailure)
  except IOError as exc:
    quit("bony: " & exc.msg, QuitFailure)
  except OSError as exc:
    quit("bony: " & exc.msg, QuitFailure)


# bonyExcludeMain lets tests `include` this module to unit-test its private procs
# (e.g. applySequencePose) without running the CLI entry point.
when isMainModule and not defined(bonyExcludeMain):
  main()
