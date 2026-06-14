# cli

Command-line harness and tooling for conversion, playback, and conformance
generation.

## M6 conversion

The current Nim CLI entry point is `cli/bony_cli.nim`.

```bash
nim c -o:bony --path:runtime-nim/src cli/bony_cli.nim
./bony json-to-bnb input.bony output.bnb
./bony bnb-to-json input.bnb output.bony
```

The M6 commands cover the currently registered `SkeletonData` objects:
`skeleton`, `bone`, `slot`, and `region`.

`bnb-to-json` is intentionally strict: it rejects embedded atlas payloads,
unknown object types, and unknown property keys because the current `.bony`
JSON surface has no preservation bucket for those bytes. The byte-stability
domain for `bnb -> json -> bnb` is canonical known-model `.bnb` emitted by the
current writer.
