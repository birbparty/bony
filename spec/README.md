# spec

Language-neutral format contracts, generated JSON Schema, and written algorithm
notes live here.

- `bony.schema.json` is generated canonical `.bony` JSON shape. It exposes
  authoring/runtime fields such as top-level `animations` and nested
  `stateMachines[].layers`.
- `bony-wire.schema.json` is generated flat registry-object shape. It exposes
  `.bnb` object-stream records such as `animationClips`, `boneTimelines`, and
  `stateMachineInputs`, plus wire-only annotations such as
  `x-bony-packedBytes`.
- `defaults.yml` is the canonical default and required-property table consumed
  by codegen and loaders.

Regenerate schemas and runtime metadata with:

```bash
python3 codegen/generate.py
python3 codegen/generate.py --check
```
