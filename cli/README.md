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
./bony play input.bony --t 0.5 --out frame.png --width 256 --height 256
```

`golden-gen` emits the cross-runtime numeric conformance surface for the
currently loaded setup pose: per-bone world transforms plus emitted draw-batch
vertex and index buffers. It intentionally does not depend on a rasterizer.
Until animations have a serialized `.bony`/`.bnb` representation, `--t` must be
`0`; non-zero values fail rather than emitting misleading setup-pose output.

`play` renders the current setup pose through the Nim software rasterizer. PNG
image output is a reference-runtime convenience path, not the cross-runtime
numeric conformance source. Like `golden-gen`, it only accepts `--t 0` for now.

The M6 commands cover the currently registered `SkeletonData` objects:
`skeleton`, `bone`, `slot`, and `region`.

`bnb-to-json` is intentionally strict: it rejects embedded atlas payloads,
unknown object types, and unknown property keys because the current `.bony`
JSON surface has no preservation bucket for those bytes. The byte-stability
domain for `bnb -> json -> bnb` is canonical known-model `.bnb` emitted by the
current writer.

`--state-machine ... --input-script ...` is reserved by the harness for both
`play` and `golden-gen`, and fails explicitly until state machines and input
scripts have a serialized `.bony`/`.bnb` representation.
