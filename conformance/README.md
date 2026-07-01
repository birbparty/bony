# bony Conformance Suite

This directory contains the shared conformance assets, input scripts, and golden
vectors that define the **cross-runtime contract** for all bony runtime
implementations (Nim reference, Dart, and future runtimes).

Any compliant runtime must pass the numeric golden gate for every milestone it
claims to support.

---

## Directory layout

```
conformance/
  assets/          # Source rigs (.bony) and binary rigs (.bnb)
    bnb/           # Binary (.bnb) golden files — one per rig + forward_compat.bnb
  goldens/         # Numeric golden vectors (*_t0.json) + image goldens (*_play.png)
  scripts/         # Input-script descriptors (*_sample.json)
  README.md        # This file
```

---

## Milestone coverage

| Milestone | Asset | Features tested |
|-----------|-------|----------------|
| M1 | `m1_rig` | Joint hierarchy, region attachments, world-space vertex positions |
| M2 | `m2_rig` | World transforms (parent → child propagation, multi-level hierarchy) |
| M3 | `m3_rig` | Multi-slot draw ordering |
| M4 | `m4_rig` | Multiple region attachments, draw order |
| M5 | `m5_rig` | Path attachments, path constraints |
| M5 (IK) | `m5_ik_rig` | IK constraints: 1-bone (`reach_one`), 2-bone with `bendPositive: false` (`reach_two`), 3-bone FABRIK chain with `mix: 0.5` (`reach_chain`); state-machine-driven IK target animation |
| M6 | `forward_compat.bnb` | Forward-compatibility: unknown future fields are silently dropped |
| M7 | `m7_rig` | Deformers (warp, rotation, bone) |
| M8 | `m8_rig` | Animation timelines (bone rotate/translate/scale/shear), state machines |
| M9 | `m9_non_scalar_rig` | Non-scalar animation timelines and state-machine projection |

The `M5 (IK)` row is a second M5 asset (structured like the standalone M9 row):
the table is one-asset-per-row, so `m5_ik_rig` gets its own row rather than being
folded into the path-constraint `m5_rig` row.

### M5 IK rig (`m5_ik_rig`)

`m5_ik_rig` is a second M5 asset dedicated to IK constraints (base `m5_rig` covers
path constraints). It exercises three constraint shapes — a 1-bone constraint
(`reach_one`), a 2-bone constraint with `bendPositive: false` (`reach_two`), and a
3-bone FABRIK chain with `mix: 0.5` (`reach_chain`) — plus a state machine
(`ik_story`) whose `target_slide` clip slides the chain IK target from `(250, 20)`
to `(205, 40)`.

Two input scripts drive it:
- `m5_ik_sample.json` — setup pose at `t=0` → golden `m5_ik_rig_t0.json`.
- `m5_ik_story.json` — state-machine story with samples `rest` (t=0),
  `reach_mid` (t=0.5), `reach_end` (t=1.0) → goldens `m5_ik_story_<sample>.json`.

Notes for readers comparing runtimes:
- The story goldens are non-vacuous: as the target slides, the solved terminal
  bone `chain_c` rotates from ~31.7° to ~65.6° world angle.
- Under `mix: 0.5` and this geometry the chain reach is dominated by the terminal
  bone; interior bones `chain_a`/`chain_b` stay near 0° (expected FABRIK behavior,
  not a defect).
- `m5_ik_story_rest.json` equals `m5_ik_rig_t0.json` because the `target_slide`
  keyframe at `t=0` matches the rig's rest target translate.
- Serialized `world` matrix entries are full float64; only IK point inputs are
  f32-quantized internally.

### Image goldens (Nim reference rasterizer only)

Image goldens (`*_play.png`) are Nim-only regression artifacts for the reference
software rasterizer.  They are **not** part of the cross-runtime numeric contract
and do not need to be reproduced by Dart or other runtimes.

| Asset | Image golden |
|-------|-------------|
| m1_rig | `m1_rig_play.png` |
| m2_rig | `m2_rig_play.png` |
| m3_rig | `m3_rig_play.png` |
| m4_rig | `m4_rig_play.png` |
| m5_rig | `m5_rig_play.png` |
| m5_ik_rig | pending (no PNG golden produced) |
| m6 | n/a (binary-only fixture — no .bony source) |
| m7_rig | pending (gated on pixie rasterizer — bony-gzz) |
| m8_rig | `m8_rig_play.png` |
| m9_non_scalar_rig | pending |

---

## Numeric golden format (`bony.numeric-golden.v1`)

Each `*_t0.json` file has the format:

```json
{
  "format": "bony.numeric-golden.v1",
  "skeleton": "<name>",
  "t": 0.0,
  "bones": [
    {"name": "root", "a": 1.0, "b": 0.0, "c": 0.0, "d": 1.0, "tx": 0.0, "ty": 0.0}
  ],
  "slots": [
    {"name": "head_slot", "attachment": "head", "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
  ],
  "drawBatches": [
    {"slot": "head_slot", "vertices": [[-25.0, -25.0], [25.0, -25.0], [25.0, 25.0], [-25.0, 25.0]]}
  ]
}
```

Fields:
- `bones[].{a,b,c,d,tx,ty}` — world transform matrix (column-major 2x3)
- `slots[].attachment` — active attachment name (or `null`)
- `slots[].{r,g,b,a}` — projected light color used by draw-batch vertices
- `slots[].{darkR,darkG,darkB}` — optional projected dark color for two-color timelines
- `slots[].{sequenceIndex,sequenceDelay,sequenceMode}` — optional sampled sequence metadata
- `drawBatches` — world-space vertex quads in draw order
- `deformers` — present only when deformers affect the pose (M7+)

**Tolerance**: numeric fields are compared with absolute tolerance `1e-4`.
String and integer fields (names, indices, blend modes) are compared exactly.

---

## Input-script format (`bony.input-script.v1`)

Each `*_sample.json` file drives the numeric golden gate:

```json
{
  "format": "bony.input-script.v1",
  "asset": "m1_rig.bony",
  "samples": [
    {"t": 0.0, "inputs": {}}
  ]
}
```

- `asset`: filename resolved relative to `conformance/assets/`
- `stateMachine`: optional target state machine. When present, the script is
  replayed through `golden-gen --state-machine ... --input-script ... --sample ...`.
- `samples[].name`: stable sample identifier. Required by the conformance
  runner for state-machine scripts. Numeric-only names are reserved for CLI
  sample indexes.
- `samples[].t`: absolute script time in seconds. State-machine execution
  advances by the delta from the previous sample time.
- `samples[].inputs`: typed input changes. Booleans target bool inputs, numbers
  target number inputs, and the string `"fire"` targets trigger inputs.

State-machine numeric/render execution projects sampled slot channels into the
top-level output contract: `rgb`, `alpha`, `rgba`, and `rgba2` update slot
colors and draw-batch vertex colors, while `sequence` resolves the slot's
current attachment by replacing its numeric suffix with the sampled index.

Setup-pose scripts without `stateMachine` keep the legacy golden naming scheme:
`<asset-stem>_t<time>.json`. State-machine scripts use
`<script-stem>_<sample-name>.json`, for example
`m8_gesture_story_wave_on.json`, so multiple samples can share a time without
colliding.

For state-machine scripts, `input_script_run.py` replays the source `.bony`
asset and, when a matching `conformance/assets/bnb/<asset-stem>.bnb` fixture
exists, replays that `.bnb` fixture against the same committed golden. This
keeps binary animation/state-machine playback in the cross-runtime contract
without duplicating golden files by asset extension.

---

## CI gates

All gates run in `.github/workflows/ci.yml` after building the bony CLI binary.

| Gate | Script | What it checks |
|------|--------|---------------|
| numeric-golden | `scripts/ci/conformance_run.py` | `.bony` to golden JSON within tolerance; `.bnb` to same golden (M6 gate) |
| image-golden | `scripts/ci/image_diff_check.py` | `.bony` to rendered PNG within pixel delta (Nim-only; requires Pillow) |
| input-script | `scripts/ci/input_script_run.py` | Input-script schema + `.bony`/matching `.bnb` state-machine golden vectors (cross-runtime contract) |
| round-trip | `scripts/ci/round_trip_run.py` | json to bnb bytes match committed golden; bnb to json to bnb is byte-lossless |

### Running the full suite locally

```bash
# Build the CLI first
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim

# Run all gates via the master runner
python3 scripts/ci/suite_run.py --bony-bin /tmp/bony_bin

# Or run individual gates
python3 scripts/ci/conformance_run.py   --bony-bin /tmp/bony_bin
python3 scripts/ci/input_script_run.py  --bony-bin /tmp/bony_bin
python3 scripts/ci/round_trip_run.py    --bony-bin /tmp/bony_bin
# Image gate requires Pillow:
pip install 'Pillow>=10.0.0,<12'
python3 scripts/ci/image_diff_check.py  --bony-bin /tmp/bony_bin
```

---

## Adding a new milestone

1. Create the rig: `conformance/assets/mN_rig.bony`
2. Generate the binary golden: `bony json-to-bnb conformance/assets/mN_rig.bony conformance/assets/bnb/mN_rig.bnb`
3. Generate the numeric golden: `bony golden-gen conformance/assets/mN_rig.bony conformance/goldens/mN_rig_t0.json --t 0.0`
4. Create the input script: `conformance/scripts/mN_sample.json` (must conform to `spec/bony-input-script.schema.json`; see an existing sample as a template)
5. Commit all four files and verify all gates pass.
6. Image golden (Nim-only): `bony play conformance/assets/mN_rig.bony conformance/goldens/mN_rig_play.png`

The `forward_compat.bnb` fixture is a special case: it has no `.bony` source and
is excluded from the round-trip gate (`*_rig.bnb` glob).  It is tested by a
dedicated smoke test (`test_smoke.nim`).
