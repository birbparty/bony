# codegen

Generators for Nim and Dart encode/decode code derived from `registry/` and
the default tables.

Run the generator from the repository root:

```bash
python3 codegen/generate.py
python3 codegen/generate.py --check
```

Inputs:

- `registry/wire.yml`
- `spec/defaults.yml`

Generated outputs:

- `runtime-nim/src/bony/generated/wire.nim`
- `runtime-dart/lib/src/generated/wire.dart`
- `spec/bony.schema.json`

The generator validates registry/default-table consistency before writing any
outputs. Later feature beads append concrete registry objects and defaults; this
same generator then emits the matching runtime metadata and schema from those
source files.
