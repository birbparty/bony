# Package

version       = "0.1.0"
author        = "birbparty"
description   = "Clean-room bony 2D skeletal animation reference runtime"
license       = "MIT"
srcDir        = "src"
bin           = @[]

# Dependencies are added after the license-scan bead verifies them.

# Tests use the local sibling checkout at ~/git/bddy via runtime-nim/nim.cfg.
task test, "Run the Nim smoke tests":
  exec "nim c -r tests/test_smoke.nim"
