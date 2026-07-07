# Verification

## Required Local Gates

Run these from repo root unless noted:

```bash
python3 codegen/generate.py --check
python3 -m unittest discover -s codegen -p 'test_*.py'
(cd runtime-dart && flutter test)
make test
```

`make test` already includes the Dart Flutter test target, but keep the direct
`cd runtime-dart && flutter test` command in the implementation bead so writer
failures are easier to inspect.

## Writer-Specific Assertions

Add tests that prove:

- `writeBonyJson` is exported from `package:bony/bony.dart`.
- `writeBonyJson(loadBonyJson(text))` emits byte-identical Nim canonical JSON
  for selected conformance assets.
- `writeBonyJson(loadBonyBnb(bytes))` emits byte-identical Nim canonical JSON
  for representative `.bnb` conformance assets.
- `writeBonyJson(loadBonyJson(writeBonyJson(data))) == writeBonyJson(data)`.
- `loadBonyJson(writeBonyJson(data))` value-round-trips all serialized fields
  for valid data.
- Invalid data fails before emission with `BonyWriteException`, and validation
  failures preserve the underlying `FormatException` as `cause`.
- Defaults are omitted only when generated metadata says
  `omitWhenDefault: true`.
- Float32 fields are quantized through `quantizeF32`, and `-0.0` emits as `0`.
- JSON strings match canonical escaping requirements.
- `deformOverrides` is not serialized.
- General-number tests include Nim-derived golden spellings for exponent
  notation, safe-integer boundaries, and large/small magnitude doubles.
- Packed timeline, mesh, skin membership, deformer, and state-machine reference
  payloads emit structured canonical JSON, not raw byte arrays.

## Conformance Coverage

Minimum asset set for byte parity:

- `conformance/assets/m1_rig.bony`
- `conformance/assets/m5_ik_rig.bony`
- `conformance/assets/m5_transform_rig.bony`
- `conformance/assets/m5_physics_rig.bony`
- `conformance/assets/m11_clip_rig.bony`
- `conformance/assets/m12_mesh_rig.bony`
- `conformance/assets/m13_mesh_deform_rig.bony`
- `conformance/assets/m16_mesh_multi_deform_rig.bony`
- `conformance/assets/m18_mesh_deform_anim_rig.bony`
- `conformance/assets/m19_event_rig.bony`
- `conformance/assets/m20_skin_rig.bony`
- `conformance/assets/m21_pointer_listener_rig.bony`
- `conformance/assets/m22_skin_required_rig.bony`
- `conformance/assets/m23_nested_rig.bony`
- `conformance/assets/m24_atlas_region_rig.bony`

Prefer testing all `conformance/assets/*.bony` once the fixture path exists.

Minimum `.bnb` asset set for byte parity:

- `conformance/assets/bnb/m1_rig.bnb`
- `conformance/assets/bnb/m5_ik_rig.bnb`
- `conformance/assets/bnb/m5_transform_rig.bnb`
- `conformance/assets/bnb/m5_physics_rig.bnb`
- `conformance/assets/bnb/m12_mesh_rig.bnb`
- `conformance/assets/bnb/m18_mesh_deform_anim_rig.bnb`
- `conformance/assets/bnb/m20_skin_rig.bnb`
- `conformance/assets/bnb/m23_nested_rig.bnb`
- `conformance/assets/bnb/m24_atlas_region_rig.bnb`

Prefer testing all `conformance/assets/bnb/*.bnb` once the fixture path exists.

## Fixture Freshness

If committed Nim canonical JSON fixtures are added, verification must include a
non-interactive freshness check. The check should:

- regenerate canonical JSON fixtures from current Nim `toBonyJson`;
- compare regenerated output with committed files byte-for-byte;
- fail on missing, extra, or stale fixtures;
- document the exact regeneration command in its `--help` output or adjacent
  docs.

The final gate must include this check either through `make test` or through an
explicit command listed in the implementation handoff.

## Generated-Code Checks

If codegen changes:

```bash
python3 codegen/generate.py
python3 codegen/generate.py --check
python3 -m unittest discover -s codegen -p 'test_*.py'
```

The implementation must commit regenerated files. Generated files must not be
hand-edited.

## API Compatibility Checks

Before finishing, run:

```bash
rg "Never encodeBonyObject|Never decodeBonyObject|no registered fields yet" runtime-dart codegen
rg "writeBonyJson" runtime-dart/lib runtime-dart/test
rg "copyWith" runtime-dart/lib/src/model/skin_model.dart runtime-dart/test
```

Expected:

- No exported Dart public throw stubs remain.
- `writeBonyJson` is exported through `runtime-dart/lib/bony.dart`.
- `SkeletonData.copyWith` is tested.

## Documentation Checks

Docs must answer:

- Is Dart `.bnb` writing supported now? If not, what is the intended
  downstream path?
- What causes `bonyRegistryVersion` to bump?
- How should downstream consumers combine package version, registry version,
  and commit SHA when deciding to repin?
- Callers should expect `BonyWriteException` from `writeBonyJson` for invalid
  data or emission failures.

## Handoff Requirements

The final implementation handoff should include:

- the final commit SHA;
- a note that Flashy should repin `runtime-dart` to that SHA;
- whether Flashy should delete `lib/export/bony/bony_exporter.dart` outright or
  reduce it to a thin adapter;
- any `.bnb` follow-up bead ID if the policy is read-only for Dart.
