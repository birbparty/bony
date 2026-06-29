# cli

Command-line harness and tooling for conversion, playback, and conformance
generation.

## Harness core

The current Nim CLI entry point is `cli/bony_cli.nim`.

```bash
nim c -o:bony --path:runtime-nim/src cli/bony_cli.nim
./bony json-to-bnb input.bony output.bnb
./bony bnb-to-json input.bnb output.bony
./bony golden-gen input.bony output.numeric.json --t 0.5
./bony golden-gen input.bony output.numeric.json \
  --state-machine gesture --input-script script.json --sample wave_on
./bony play input.bony --t 0.5 --out frame.png --width 256 --height 256
./bony play input.bony --state-machine gesture --input-script script.json --out story.png
```

`golden-gen` emits the cross-runtime numeric conformance surface for the
currently loaded setup pose: per-bone world transforms plus emitted draw-batch
vertex and index buffers. It intentionally does not depend on a rasterizer.
For setup-pose execution, `--t` must be `0`; non-zero values fail rather than
emitting misleading setup-pose output.

For `.bony` state-machine execution, `golden-gen` requires
`--state-machine <name> --input-script <script.json> --sample <name-or-index>`.
The input script owns sample times and typed inputs. The emitted JSON extends
`bony.numeric-golden.v1` with `stateMachine`, `sample`, `inputs`, `layers`, and
`events` fields so the numeric gate verifies active states, sampled layer poses,
trigger consumption, and listener event order.

`play` renders the current setup pose through the Nim software rasterizer. PNG
image output is a reference-runtime convenience path, not the cross-runtime
numeric conformance source. With `--state-machine` and `--input-script`, `play`
renders a horizontal contact sheet: one cell per script sample, using the same
input replay semantics as `golden-gen`.

The M6 commands cover the currently registered `SkeletonData` objects:
`skeleton`, `bone`, `slot`, and `region`.

`bnb-to-json` is intentionally strict: it rejects embedded atlas payloads,
unknown object types, and unknown property keys because the current `.bony`
JSON surface has no preservation bucket for those bytes. The byte-stability
domain for `bnb -> json -> bnb` is canonical known-model `.bnb` emitted by the
current writer.

State-machine input scripts currently require `.bony` assets. `.bnb` playback
continues to support the setup-pose path only until the binary contract includes
animation and state-machine data.
