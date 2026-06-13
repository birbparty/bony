# bony

Clean-room 2D skeletal and deform animation format with a Nim reference
runtime, Dart runtime, CLI tooling, and shared conformance suite.

## Repository Layout

- `spec/` - format schema and language-neutral contracts.
- `registry/` - append-only type and property key registry.
- `codegen/` - generated encoder/decoder tooling.
- `runtime-nim/` - Nim reference runtime package.
- `runtime-dart/` - Dart runtime package.
- `cli/` - command-line harness and tooling.
- `conformance/` - shared assets, scripts, and golden vectors.
- `docs/` - process notes and design documentation.
