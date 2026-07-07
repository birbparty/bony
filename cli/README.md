# cli

Command-line harness and tooling for conversion, playback, and conformance
generation.

## Harness core

The current Nim CLI entry point is `cli/bony_cli.nim`.

```bash
nim c -o:bony --path:runtime-nim/src cli/bony_cli.nim
./bony json-to-bnb input.bony output.bnb
./bony bnb-to-json input.bnb output.bony
./bony golden-gen input.bony output.numeric.json --t 0
./bony golden-gen input.bony output.numeric.json \
  --state-machine gesture --input-script script.json --sample wave_on
./bony play input.bony --t 0 --out frame.png --width 256 --height 256
./bony play input.bony --state-machine gesture --input-script script.json --out story.png
./bony import-dragonbones input_ske.json output.bony --assets-dir images
```

`golden-gen` emits the cross-runtime numeric conformance surface for the
currently loaded setup pose: per-bone world transforms plus emitted draw-batch
vertex and index buffers. It intentionally does not depend on a rasterizer.
For setup-pose execution, `--t` must be `0`; non-zero values fail rather than
emitting misleading setup-pose output.

For `.bony` or `.bnb` state-machine execution, `golden-gen` requires
`--state-machine <name> --input-script <script.json> --sample <name-or-index>`.
The input script owns sample times and typed inputs. The emitted JSON extends
`bony.numeric-golden.v1` with `stateMachine`, `sample`, `inputs`, `layers`, and
`events` fields so the numeric gate verifies active states, sampled layer poses,
trigger consumption, and listener event order.
State-machine samples containing color, color2, or sequence channels fail
explicitly until those channels are projected into the top-level slot and
draw-batch output contract.

`play` renders the current setup pose through the Nim software rasterizer. PNG
image output is a reference-runtime convenience path, not the cross-runtime
numeric conformance source. With `--state-machine` and `--input-script`, `play`
renders a horizontal contact sheet: one cell per script sample, using the same
input replay semantics as `golden-gen`.

The `.bnb` conversion commands preserve static setup data plus the local
animation and state-machine records supported by the aggregate asset loader.
State-machine input-script replay uses the same semantics for `.bony` and
`.bnb` assets when the binary contains the requested machine and clips.

`bnb-to-json` is intentionally strict: it rejects embedded atlas payloads,
unknown object types, and unknown property keys because the current `.bony`
JSON surface has no preservation bucket for those bytes. The byte-stability
domain for `bnb -> json -> bnb` is canonical known-model `.bnb` emitted by the
current writer.

State-machine input scripts may target `.bnb` assets generated from the named
`.bony` source in the script. Missing binary animation or state-machine records
fail with the same unknown-reference diagnostics as missing JSON data.

## DragonBones Import

`import-dragonbones` converts the project-owned Tier 1 subset documented in
`docs/dragonbones-importer-design.md`. Static armatures produce static `.bony`
JSON. Supported bone `translateFrame`, `rotateFrame`, and `scaleFrame` channels
are preserved as bony `AnimationClip` data unless `--setup-only` is supplied.

`--setup-only` emits rest-pose setup data and suppresses animation before
animation-channel validation. Normal imports fail rather than silently dropping
unsupported animation data. Diagnostics use stable `code`, `target`, and
`capability` fragments, and validation failures occur before the output path is
written.
