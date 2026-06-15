# Package

version       = "0.1.0"
author        = "birbparty"
description   = "Clean-room bony 2D skeletal animation reference runtime"
license       = "MIT"
srcDir        = "src"
bin           = @[]

requires "pixie == 6.1.0"
requires "naylib == 26.08.0"

# Tests use the local sibling checkout at ../../bddy, matching ~/git/bddy when
# this repository lives at ~/git/bony.
task test, "Run the Nim smoke tests":
  exec "nim c -r tests/test_smoke.nim"

task bench, "Run the non-gating perf harness (always exits 0)":
  exec "nim c -r --path:src bench_perf.nim"
