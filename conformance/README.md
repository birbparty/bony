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
| M5 (transform) | `m5_transform_rig` | Transform constraint: a constrained bone blended toward a rotated/scaled/sheared target at a partial `0.5` mix on all four channels (`translateMix`/`rotateMix`/`scaleMix`/`shearMix`) |
| M5 (physics) | `m5_physics_rig` | Physics constraint: a critically-damped spring on a bone's `rotate` channel, driven by a state-machine story whose clip steps the target so the spring is excited and then settles over time (the only time-driven, stateful conformance rig) |
| M6 | `forward_compat.bnb` | Forward-compatibility: unknown future fields are silently dropped |
| M7 | `m7_rig` | Deformers (warp, rotation, bone) |
| M8 | `m8_rig` | Animation timelines (bone rotate/translate/scale/shear), state machines |
| M9 | `m9_non_scalar_rig` | Non-scalar animation timelines and state-machine projection |
| M11 | `m11_clip_rig` | Clipping attachment: convex clip polygon partially covering a region slot, `untilSlot`-bounded range |

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
  bone `chain_c` world angle sweeps ~31.7° (`rest`) → ~56.3° (`reach_mid`) →
  ~65.6° (`reach_end`).
- Under `mix: 0.5` and this geometry the chain reach is dominated by the terminal
  bone; interior bones `chain_a`/`chain_b` stay near 0° (world basis ≈ identity,
  `a≈1.0, b≈0`) — expected FABRIK behavior, not a defect.
- The bone `world` matrices in `m5_ik_story_rest.json` match those in
  `m5_ik_rig_t0.json` (the `target_slide` keyframe at `t=0` equals the rig's rest
  target translate). The two files are **not** byte-identical, though: the story
  golden additionally wraps the pose in state-machine metadata
  (`stateMachine`/`sample`/`layers`/`events`).
- Serialized `world` matrix entries are full float64; only IK point inputs are
  f32-quantized internally.
- Cross-runtime status: the setup-pose golden `m5_ik_rig_t0.json` is honored by
  **both** the Nim reference and the Dart runtime — Dart now evaluates IK in
  `computeWorldTransforms` and matches it within `1e-4`
  (`runtime-dart/test/m10_conformance_test.dart`). The state-machine story
  goldens (`m5_ik_story_*`) remain Nim-only pending the Dart story slice.

### M5 transform rig (`m5_transform_rig`)

`m5_transform_rig` is a third M5 asset dedicated to transform constraints (base
`m5_rig` covers path constraints; `m5_ik_rig` covers IK). It has three bones —
`root`, `constrained` (child of root at `x=40`), and `target` (child of root at
`x=80, y=60, rotation=45, scaleX=2, shearY=30`) — and one transform constraint
`follow` that drives `constrained` toward `target` with a **partial `0.5` mix on
all four channels** (`translateMix`/`rotateMix`/`scaleMix`/`shearMix`).

One input script drives it:
- `m5_transform_sample.json` — setup pose at `t=0` → golden `m5_transform_rig_t0.json`.

**Non-vacuous constrained-vs-unconstrained delta.** Without the constraint,
`constrained`'s world would be its plain FK pose: `tx=40, ty=0`, identity basis
(`a=1, b=0, c=0, d=1`) — i.e. rotation `0°`, `scaleX=scaleY=1`, `shearY=0`. With
the constraint solved at `t=0`, `m5_transform_rig_t0.json` records `constrained`
as `tx=60, ty=30, a≈1.38582, b≈0.57403, c≈-0.60876, d≈0.79335`, which decomposes
to rotation `22.5°`, `scaleX=1.5`, `scaleY=1.0`, `shearY=15°`. Every channel is
exactly the `0.5` midpoint between the unconstrained pose and the target
(rotation `0→45` ⇒ `22.5`, `scaleX 1→2` ⇒ `1.5`, `shearY 0→30` ⇒ `15`,
translation `(40,0)→(80,60)` ⇒ `(60,30)`). The world-affine delta is far above
the `1e-4` conformance tolerance — translation alone moves `hypot(20,30) ≈ 36.06`
skeleton units, and every mix channel contributes a distinct, observable change,
so a runtime that drops or mis-implements any single channel (including shear)
fails this golden.

Notes for readers comparing runtimes:
- Serialized `world` matrix entries are full float64; the four mixes are
  f32-quantized internally (backing type `f32`).
- The golden is reproduced identically from both `m5_transform_rig.bony` and
  `conformance/assets/bnb/m5_transform_rig.bnb` (the JSON and binary loaders
  agree; the `.bnb` is non-empty at 215 bytes).
- Cross-runtime status: the setup-pose golden `m5_transform_rig_t0.json` is
  honored by **both** the Nim reference and the Dart runtime — Dart now evaluates
  transform constraints in `computeWorldTransforms` and matches it within `1e-4`
  (`runtime-dart/test/m10_conformance_test.dart`, the `M5-Transform` group).

### M5 physics rig (`m5_physics_rig`)

`m5_physics_rig` is a fourth M5 asset dedicated to the physics constraint (base
`m5_rig` covers path constraints; `m5_ik_rig` covers IK; `m5_transform_rig`
covers transform constraints). It is bony's **only time-driven, stateful**
conformance rig. Three bones — `root`, `anchor` (child of root at `y=100`), and
`pendulum` (child of `anchor` at `x=40`) — and one physics constraint
`bob_spring` on `pendulum`'s `rotate` channel (`channels: 4`), a **critically
damped** spring (`strength: 100`, `damping: 20`, `mass: 1` ⇒
`damping² = 4·mass·strength`, `inertia: 1`, `physicsMix: 1`). A state machine
`physics_story` plays the `swing` clip, which steps `pendulum`'s target rotation
from `0°` to `45°` early in the clip and then holds it, exciting the spring.

**Why a state-machine story (not a `--t` setup pose).** Physics is
time-dependent: at `t=0` a freshly seeded spring has zero offset, so a
setup-pose (`--t 0`) golden would be **vacuous**. The conformance gate must
advance time, and the input-script harness advances physics only through the
state-machine story path — each sample advances the stateful physics stage by
the delta from the previous sample time, carrying `PhysicsConstraintState`
across samples (see `advancePhysics` in `runtime-nim/src/bony/transform.nim`,
wired into the story golden path in `cli/bony_cli.nim`). Per the integrator
contract each advance is capped at 8 fixed `1/60 s` substeps, so the story keeps
inter-sample deltas at `0.1 s` (6 substeps, nothing dropped).

One story script drives it:
- `m5_physics_story.json` — state-machine story with samples `rest` (t=0),
  `excited` (t=0.1), `settled` (t=0.2) → goldens `m5_physics_story_<sample>.json`.

**Non-vacuous, settling offset trajectory.** The spring offset is the physics
signal: `pendulum`'s solved `rotate` = target + offset. Reading the pendulum
`world` basis angle (`atan2(b, a)`) at each sample:

| sample | target | world angle | spring offset | Δ world angle |
|--------|-------:|------------:|--------------:|--------------:|
| `rest` (t=0)     | `0°`  | `0.000000°`  | `0.000000°`   | — |
| `excited` (t=0.1)| `45°` | `14.289967°` | `−30.710033°` | `+14.289967°` |
| `settled` (t=0.2)| `45°` | `28.336548°` | `−16.663452°` | `+14.046581°` |

The offset magnitude runs `0° → 30.71° → 16.66°`: the target step excites the
spring at `excited`, then it **settles** — by `settled` the offset has decayed
~46% back toward zero, and the world angle relaxes monotonically toward the
`45°` target across these samples. Critical damping (`damping² = 4·mass·strength`)
is the fastest response that reaches equilibrium without oscillating, so no
overshoot is expected past the sampled window. Each inter-sample world angle
delta (`14.289967°`, `14.046581°`) is far above the `1e-4` conformance
tolerance, and the offset converges toward zero rather than diverging.

Notes for readers comparing runtimes:
- Serialized `world` matrix entries are full float64; the physics substep
  arithmetic is f64 with f32 rounding only at the public output boundary.
- The goldens are reproduced identically from both `m5_physics_rig.bony` and
  `conformance/assets/bnb/m5_physics_rig.bnb` (the JSON and binary loaders agree;
  the `.bnb` is non-empty at 303 bytes).
- Cross-runtime status: the `m5_physics_story_*` goldens are honored by **both**
  the Nim reference and the Dart runtime. Dart ports the fixed-substep
  integrator (`runtime-dart/lib/src/physics_constraint.dart`) and a stateful
  advance seam (`advancePhysics` in `runtime-dart/lib/src/transform.dart`),
  carrying one physics state per constraint across the story samples, and
  reproduces every bone world matrix within `1e-4` from both the `.bony` and the
  `.bnb` (`runtime-dart/test/m5_physics_story_test.dart`).

### M11 clip rig (`m11_clip_rig`)

`m11_clip_rig` is the M4 clipping-attachment conformance asset (the milestone
token `M11` only names the asset — the registry key band is still M4). It has one
identity `root` bone and three draw-order slots:

- `clip_slot` — references the `clip_mask` clipping attachment (its own slot);
  produces no draw batch.
- `panel_slot` — a `100×100` region quad, **inside** the clip range, so it is
  clipped.
- `outside_slot` — a `40×40` region quad, **outside** the range (past
  `untilSlot: panel_slot`), so it stays unclipped.

The clip polygon `clip_mask` is the convex triangle
`[(-200,-200), (230,-200), (-200,230)]`, whose hypotenuse is the line `x + y = 30`
cutting **diagonally** across the `panel` quad (corners `±50`).

**Non-vacuous clipped-vs-unclipped delta (geometry + u/v).** The raw `panel` quad
is 4 vertices `(-50,-50)…(-50,50)` with corner u/v `0/1`. After clipping, the
`panel_slot` batch in `m11_clip_rig_t0.json` carries `clipId: "clip_mask"` and a
**5-vertex** fan (`indices [0,1,2,0,2,3,0,3,4]`): the corner `(50,50)` is removed
and two **new** vertices appear on the diagonal cut — `(50,-20)` with `u=1.0,
v=0.3` and `(-20,50)` with `u=0.3, v=1.0`. Those `0.3` values are u/v linearly
**interpolated** at the clip edge (`30/100` along the quad side), well above the
`1e-4` tolerance, so a runtime that skips clipping or mis-interpolates u/v fails
the golden. The `outside_slot` batch keeps `clipId: ""` and its unclipped 4-vertex
quad, making the `untilSlot` range boundary observable. Region batches carry
uniform color `(1,1,1,1)` and there is no format construct for a non-uniform quad,
so r/g/b/a interpolation is **not** observable here — it is covered by a dedicated
prompt-16 Nim unit test (`runtime-nim/tests/test_smoke.nim`, the "interpolates
r/g/b/a at a clip-edge intersection" case).

Notes for readers comparing runtimes:
- The golden is reproduced identically from both `m11_clip_rig.bony` and
  `conformance/assets/bnb/m11_clip_rig.bnb` (the JSON and binary loaders agree;
  the `.bnb` is non-empty at 248 bytes), and regenerates byte-identically on
  re-run per the float-math contract.
- Cross-runtime status: the setup-pose golden `m11_clip_rig_t0.json` is honored by
  **both** the Nim reference and the Dart runtime — Dart now loads the clipping
  record and clips draw batches in `buildDrawBatches` with the same
  Sutherland-Hodgman algorithm, matching the golden within `1e-4`
  (`runtime-dart/test/m10_conformance_test.dart`, the `M11-Clip` group; the Dart
  `.bnb` clip-load path is additionally covered by
  `runtime-dart/test/m11_clip_bnb_test.dart`).

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
| m5_transform_rig | pending (no PNG golden produced) |
| m5_physics_rig | pending (no PNG golden produced) |
| m6 | n/a (binary-only fixture — no .bony source) |
| m7_rig | pending (gated on pixie rasterizer — bony-gzz) |
| m8_rig | `m8_rig_play.png` |
| m9_non_scalar_rig | pending |
| m11_clip_rig | pending (no PNG golden produced) |

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
