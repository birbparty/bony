# codegen

Generators for Nim and Dart encode/decode code derived from `registry/` and
the default tables.

Run the generator from the repository root:

```bash
python3 codegen/generate.py
python3 -m unittest discover -s codegen -p 'test_*.py'
python3 codegen/generate.py --check
```

Inputs:

- `registry/wire.yml`
- `spec/defaults.yml`

Generated outputs:

- `runtime-nim/src/bony/generated/wire.nim`
- `runtime-dart/lib/src/generated/wire.dart`
- `spec/bony.schema.json`
- `spec/bony-wire.schema.json`

The generator validates registry/default-table consistency before writing any
outputs. Later feature beads append concrete registry objects and defaults; this
same generator then emits the matching runtime metadata and schema from those
source files. Runtime outputs include backing type, type key, property key,
object membership, default-table, required-property, and generated encode/decode
dispatch surfaces. `spec/bony.schema.json` describes the canonical `.bony` JSON
shape; `spec/bony-wire.schema.json` describes the flat registry-object view used
for generated wire metadata.

## Packed Bytes

The wire schema maps `bytes` properties to base64 strings. Some bytes properties
carry packed binary subformats that cannot be expressed structurally without
duplicating loader logic. For those properties, codegen may add a
`x-bony-packedBytes` annotation that names the payload contract and the document
that owns the byte layout. The wire schema still validates only the base64
carrier; loaders validate payload length, kind-specific shape, numeric domains,
and reference resolution.
