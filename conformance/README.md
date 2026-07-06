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
| M12 | `m12_mesh_rig` | Weighted mesh attachment: skinned vertices shared across two bones, per-vertex uvs, triangle list |
| M13 | `m13_mesh_deform_rig` | Mesh × deformer: a 5-vertex (non-quad) weighted mesh further deformed by a rotation deformer after skinning |
| M14 | `m14_mesh_warp_rig` | Mesh × warp self-scoping: a warp lattice box covering only 2 of 5 mesh vertices — in-bounds verts warped, out-of-bounds verts unchanged |
| M15 | `m15_mesh_unweighted_deform_rig` | Unweighted mesh (raw x/y, FK-skinned through the slot bone) under a rotation deformer |
| M16 | `m16_mesh_multi_deform_rig` | Multiple ordered deformers on a mesh: rotation (order 0) then a warp parented to it (order 1), exercising composition + parent-frame chaining |
| M17 | `m17_mesh_clip_rig` | Mesh × clipping: a triangle-soup mesh inside a clip range, clipped **per-triangle** (shared interior vertex preserved; some triangles cut, some pass through) |
| M18 | `m18_mesh_deform_anim_rig` | Animated mesh deform: a clip-owned deform timeline moves mesh vertices over time; first nonzero-time mesh golden |
| M19 | `m19_event_rig` | Animation events: a clip-owned event timeline fires distinct value-carrying events at keyframe times, surfaced in the golden's `animationEvents` channel via incremental per-sample-window dispatch through the Nim and Dart clip-mirror story paths |
| M20 | `m20_skin_rig` | Skin attachment sets: active-skin attachment lookup, default-skin fallback for missing variant entries, JSON/BNB parity, and deform-timeline resolution through the selected skin |
| M21 | `m21_pointer_listener_rig` | Pointer helper listeners: bounding-box and point helper hit testing, pointer-driven bool/number/trigger input mutation, same-sample state transition, and pointer events in the state-machine `events` channel |
| M22 | `m22_skin_required_rig` | `skinRequired` activation: default-plus-active-skin membership, inactive required bone draw suppression, required IK/transform/path no-op vs active solve, later active constraint order stability, and inactive/active physics behavior |

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
  goldens (`m5_ik_story_*`) are honored by both runtimes as well —
  `runtime-dart/test/m5_ik_story_test.dart` replays the `ik_story` machine and
  matches them within `1e-4`.

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

### M12 mesh rig (`m12_mesh_rig`)

`m12_mesh_rig` is the M4 mesh-attachment conformance asset (the milestone token
`M12` only names the asset — the registry key band is still M4). It has three
bones and one draw-order slot:

- `root` — identity.
- `boneA` — child of `root` at local `(x=10, y=0)`, so its world translation is
  `(10, 0)`.
- `boneB` — child of `root` at local `(x=0, y=10)`, so its world translation is
  `(0, 10)`.
- `mesh_slot` — references the **weighted** `mesh` attachment (its `bone` is
  `root`; a weighted mesh ignores the slot bone for skinning, so `slot.bone` only
  supplies the batch's metadata `world`, not the vertices).

The `mesh` attachment is a 4-vertex, 2-triangle weighted mesh
(`triangles [0,1,2, 0,2,3]`) with distinct per-vertex uvs
(`[0,0], [1,0], [1,1], [0,1]`). Its four vertices exercise both the blend and the
single-influence skinning paths:

- **v0** — shared **50/50** across `boneA` (bind `(0,0)`) and `boneB` (bind
  `(0,0)`).
- **v1** — **fully** `boneA`, bind `(4,0)`.
- **v2** — **fully** `boneB`, bind `(0,4)`.
- **v3** — shared with **asymmetric** weights `0.25`/`0.75` across `boneA`
  (bind `(2,2)`) and `boneB` (bind `(2,2)`).

**Non-vacuous, skinning-dominated delta.** The shared vertex **v0** in
`m12_mesh_rig_t0.json` skins to the world position **`(5, 5)`**. That is the
linear blend `0.5 · boneA·(0,0) + 0.5 · boneB·(0,0) = 0.5·(10,0) + 0.5·(0,10)`,
which sits **strictly between** the two single-bone FK results it interpolates:
`boneA`-only would place it at **`(10, 0)`** and `boneB`-only at **`(0, 10)`**.
The blended point is `≈ 7.07` (`= √(5² + 5²)`) away from **each** single-bone FK
result — five orders of magnitude above the `1e-4` tolerance — so a runtime that
drops a weight, uses only one influence, or mis-orders the blend fails the golden.
The single-influence vertices pin the FK path: **v1** lands at `boneA·(4,0) =
(14, 0)` and **v2** at `boneB·(0,4) = (0, 14)`. Per-vertex uvs are carried
straight through (`v2` = `u=1, v=1`), so a runtime that drops or reorders uvs also
fails.

The **asymmetric** vertex **v3** additionally pins the actual weight
multiplication (not merely an equal average of influences): with weights
`0.25`/`0.75` it skins to `0.25·boneA·(2,2) + 0.75·boneB·(2,2) =
0.25·(12,2) + 0.75·(2,12) = (4.5, 9.5)`, whereas a runtime that averaged its two
influences equally (ignoring the weights) would place it at `(7, 7)` — a `≈ 3.54`
delta, so weight handling is observable and not covered up by the `0.5/0.5`
vertices.

Region batches carry uniform color `(1,1,1,1)`, and the version-1 mesh record has
**no** per-vertex color, so every mesh vertex's `r/g/b/a` is a uniform `1.0` and color is
**not** an observable channel here — the golden's non-vacuity rests entirely on
the skinned geometry, the uvs, and the triangle indices.

Notes for readers comparing runtimes:
- The golden is reproduced identically from both `m12_mesh_rig.bony` and
  `conformance/assets/bnb/m12_mesh_rig.bnb` (the JSON and binary loaders agree;
  the `.bnb` is non-empty at 289 bytes), and regenerates byte-identically on
  re-run per the float-math contract.
- This rig is single-purpose (one weighted mesh at a setup pose) and deliberately
  combines no clipping, animation, state machine, constraints, or deformers.
  Mesh × clipping is covered separately by `m17_mesh_clip_rig`.
- Cross-runtime status: the setup-pose golden `m12_mesh_rig_t0.json` is honored by
  **both** the Nim reference and the Dart runtime — Dart now loads the mesh record
  (JSON + `.bnb`) and skins it in `buildDrawBatches` with the same linear-blend
  formula, matching the golden within `1e-4` (`runtime-dart/test/m10_conformance_test.dart`,
  the `M12-Mesh` group; the Dart `.bnb` mesh decode + skinning path is additionally
  pinned by `runtime-dart/test/m12_mesh_bnb_test.dart`).

### M17 mesh-clip rig (`m17_mesh_clip_rig`)

`m17_mesh_clip_rig` is the per-triangle mesh-clipping conformance asset (the
milestone token `M17` only names the asset — the registry key band is still M4).
It combines a **mesh** attachment and a **clipping** attachment, the first rig to
put a mesh inside a clip's covered range. One identity `root` bone and two
draw-order slots:

- `clip_slot` — references the `clip_mask` clipping attachment (its own slot);
  produces no draw batch.
- `mesh_slot` — an unweighted 5-vertex mesh, **inside** the clip range
  (`untilSlot: mesh_slot`), so it is clipped.

The `mesh` is a **triangle soup**: a diamond fan of four triangles
(`triangles [0,1,2, 0,2,3, 0,3,4, 0,4,1]`) all sharing the **interior center
vertex 0** `(0,0)`, with rim vertices `(50,0)`, `(0,50)`, `(-50,0)`, `(0,-50)`.
The vertex list is deliberately **not** a convex boundary ring, so the region
convex-ring clip (`clipDrawBatchPolygon`) would mis-triangulate it — only
per-triangle clipping (`clipDrawBatchTriangles`) is correct here.

The clip polygon `clip_mask` is the rectangle
`[(-100,-100), (20,-100), (20,100), (-100,100)]` — the half-plane `x <= 20`.

**Non-vacuous per-triangle delta (geometry + u/v).** Only the right rim vertex
`(50,0)` is outside `x <= 20`, so the two triangles that use it are cut while the
two left triangles pass through unchanged. The `mesh_slot` batch in
`m17_mesh_clip_rig_t0.json` carries `clipId: "clip_mask"` and **14 vertices / 18
indices** (up from the raw 5 vertices / 12 indices): the two clipped triangles
each become a 4-vertex fan, and the two interior triangles re-emit their 3
vertices. The removed corner `(50,0)` appears in **no** output vertex
(`max x == 20`), and new vertices land on the `x = 20` cut — e.g. `(20,0)` with
`u = 0.7` (interpolated `0.4` along the `v0→v1` edge from `u=0.5` to `u=1.0`) and
`(20,30)` with `u=0.7, v=0.8`. Those interpolated u/v values are well above the
`1e-4` tolerance, so a runtime that skips clipping, clips the mesh as one convex
ring, or mis-interpolates u/v fails the golden. The shared center vertex `(0,0)`
appears once per triangle that references it (per-triangle fans duplicate shared
vertices), which a convex-ring interpretation would not produce.

Notes for readers comparing runtimes:
- The golden is reproduced identically from both `m17_mesh_clip_rig.bony` and
  `conformance/assets/bnb/m17_mesh_clip_rig.bnb` (the JSON and binary loaders
  agree; the `.bnb` is non-empty at 295 bytes), and regenerates byte-identically
  on re-run per the float-math contract.
- Cross-runtime status: the setup-pose golden `m17_mesh_clip_rig_t0.json` is
  honored by **both** the Nim reference and the Dart runtime — Dart clips mesh
  batches per-triangle in `buildDrawBatches` with the same algorithm, matching the
  golden within `1e-4` (`runtime-dart/test/m10_conformance_test.dart`, the
  `M17-MeshClip` group; the Dart `.bnb` mesh-clip path is additionally pinned by
  `runtime-dart/test/m17_mesh_clip_bnb_test.dart`).

### M18 mesh-deform-anim rig (`m18_mesh_deform_anim_rig`)

`m18_mesh_deform_anim_rig` is the first **animated (nonzero-time) mesh**
conformance rig — every earlier mesh asset (`m12`–`m17`) is a setup-pose (`t=0`)
golden. It proves the cross-runtime **deform-timeline** contract: a clip-owned
`deformTimeline` that moves a mesh's vertices over time, sampled through the
state-machine story path (the milestone token `M18` only names the asset — the
registry key band is still M4).

The rig is deliberately single-purpose: one identity `root` bone and one
draw-order slot `mesh_slot` referencing an **unweighted** 5-vertex diamond-fan
mesh `panel` (center `(0,0)`, rim `(50,0)`, `(0,50)`, `(-50,0)`, `(0,-50)`;
`triangles [0,1,2, 0,2,3, 0,3,4, 0,4,1]`). Unweighted geometry keeps the golden's
motion attributable **solely** to the deform deltas, not to skinning. There is
**no** M7 deformer, clipping, constraint, weighting, or per-vertex color on this
mesh (per the prompt-24 normative-order scope guard, the deform-vs-M7 ordering
stays documented-but-unexercised in v1).

**The deform timeline.** One animation clip `wiggle` owns a `deformTimeline`
(skin `"default"`, slot `mesh_slot`, attachment `panel`, `vertexCount 5`) with
three keyframes that offset **only the right rim vertex 1** (`offset: 1`, a
single-delta run):

| key | `t` | delta at v1 | curve (segment to next key) |
|-----|----:|------------:|-----------------------------|
| 0 | `0.0` | `(0, 0)` | `linear` |
| 1 | `0.5` | `(+30, 0)` | `stepped` |
| 2 | `1.0` | `(+6, 0)`  | — (last key) |

Key 0 carries a **zero-magnitude** `(0,0)` delta rather than an empty deltas list
(`validateDeformKey` rejects an empty run, `anim/timelines.nim`), so the rest
sample renders the static mesh while still validating. A state machine
`deform_story` has one layer `mesh` playing `wiggle` (the simplest
SM-plays-one-clip precedent, mirroring `m9_non_scalar`).

One story script drives it:
- `m18_deform_story.json` — state-machine story with samples `rest` (t=0),
  `mid` (t=0.5), `end` (t=1.0) → goldens `m18_deform_story_<sample>.json`.

**Non-vacuous vertex sweep (geometry + u/v carry-through).** The three story
samples land exactly on the three keyframe times, so each golden reads its
keyframe's deltas directly. Reading the `mesh_slot` batch's animated **vertex 1**
world position in `drawBatches[].vertices` (the mesh is in identity `root` space,
so world = base + delta):

| sample | v1 world `x` | v1 `(u, v)` | Δ from rest |
|--------|-------------:|-------------|------------:|
| `rest` (t=0)   | `50.0` | `(1.0, 0.5)` | — |
| `mid` (t=0.5)  | `80.0` | `(1.0, 0.5)` | `+30.0` |
| `end` (t=1.0)  | `56.0` | `(1.0, 0.5)` | `+6.0` |

The animated vertex sweeps `x: 50 → 80 → 56` — every inter-sample delta
(`+30.0`, `−24.0`) is far above the `1e-4` conformance tolerance. The other four
vertices are unchanged, and v1's `u/v` (`1.0, 0.5`) are **carried through the
deform untouched** (deform offsets position, not texture coordinates). A runtime
that ignores the deform timeline renders the static mesh (v1 `x = 50`) at every
sample and therefore **fails at `mid` and `end`**. The three goldens are **not**
byte-identical to each other (distinct mesh geometry at `mid`/`end`, plus
distinct `time`/`sample`/layer-time metadata) and none matches a static-mesh
render.

Notes for readers comparing runtimes:
- The goldens are reproduced identically from both `m18_mesh_deform_anim_rig.bony`
  and `conformance/assets/bnb/m18_mesh_deform_anim_rig.bnb` (the JSON and binary
  loaders agree; the `.bnb` is non-empty at 371 bytes), and regenerate
  byte-identically on re-run per the float-math contract.
- Serialized vertex positions are f32-quantized at the mesh output boundary
  (`applyDeformDeltas` quantizes `x`/`y`); the deltas here are exact integers so
  no rounding is visible.
- The `curve` kinds (`linear` on `rest→mid`, `stepped` on `mid→end`) are
  structural: because the samples are keyframe-aligned, `sampleDeformDeltas`
  returns each keyframe's deltas directly without traversing the
  interpolation/stepped branches — those paths are exercised by the unit sampler
  tests, not by these goldens.
- The per-layer `layers[].pose` object in these goldens carries **no** `deforms`
  array — the resolved deform override is transient (excluded from the pose
  serialization per docs/deform-timeline-contract.md). The deform's effect is
  observable only in `drawBatches[].vertices`, which is therefore the non-vacuity
  anchor for this rig (not the layer pose).
- The `deform_story` machine is **single-layer**, so these goldens drive the
  deform through the aggregate pose but do not exercise multi-layer deform
  *overlay* (one layer's deform merging over another's) — that coverage is tracked
  in `bony-353d`.
- Cross-runtime status: the `m18_deform_story_*` goldens are honored by **both**
  the Nim reference and the Dart runtime. Dart ports the deform sampler
  (`sampleDeformDeltas`) and the after-skinning delta application
  (`applyDeformDeltas`) into `runtime-dart/lib/src/anim.dart` and
  `runtime-dart/lib/src/transform.dart`, carrying the sampled deltas through the
  posed `SkeletonData` (the same transient-override seam Nim uses, staged in
  `applyPose`), and reproduces every animated draw-batch vertex within `1e-4`
  from both the `.bony` and the `.bnb`
  (`runtime-dart/test/m18_deform_story_test.dart`).

### M19 event rig (`m19_event_rig`)

`m19_event_rig` is the first conformance rig whose golden's non-vacuity rests on
**dispatched animation events**. It proves the cross-runtime **event-timeline**
contract (`docs/event-timeline-contract.md`): a clip-owned `eventTimeline` fires
distinct, value-carrying events at keyframe times, dispatched through the mixer
along the state-machine story path and surfaced in the numeric golden's
**`animationEvents`** channel (distinct from the M8 state-machine listener
`events` array). The milestone token `M19` only names the asset — the registry
key band is still **M3** (events are M3; prompt 27).

The rig is deliberately single-purpose: one identity `root` bone and one
draw-order slot `panel_slot` referencing a static 50×50 region attachment
`panel`. The geometry is incidental — a static region keeps the bones, slots, and
draw batches trivially identical across all three samples, so the **only** signal
that changes between goldens is the event channel. There is no mesh, deform,
clipping, constraint, or multi-layer overlay.

**The event timeline.** One animation clip `pulse` owns a single `eventTimeline`
with three keyframes. `animationClip` derives the clip duration from the event
timeline's last key time, so `pulse` has duration `1.0` and the `t=1.0` event
fires:

| key | `t` | `name` | `intValue` | `floatValue` | `stringValue` |
|-----|----:|--------|-----------:|-------------:|---------------|
| 0 | `0.5` | `hit`  | `7`  | `1.5`  | `"left"`  |
| 1 | `0.5` | `hit2` | `11` | `-2.5` | `"right"` |
| 2 | `1.0` | `land` | `-3` | `0.25` | `""`      |

`hit` and `hit2` share `t=0.5`, exercising the **non-decreasing** (not strictly
increasing) ordering rule events uniquely allow, and their stable dispatch order
(`hit` before `hit2`, by authoring order). `land` carries an **empty**
`stringValue` in a *fired* event, and a negative `intValue`. `audioPath`,
`volume`, and `balance` stay at their reserved defaults (`""`/`1.0`/`0.0`) —
audio fields are carried but not exercised, per the metadata-only non-goal. A
state machine `event_story` has one layer `base` playing `pulse` (the simplest
SM-plays-one-clip precedent, mirroring `m9_non_scalar` / `m18`).

One story script drives it:
- `m19_event_story.json` — state-machine story with samples `rest` (t=0),
  `mid` (t=0.5), `end` (t=1.0) → goldens `m19_event_story_<sample>.json`.

**Non-vacuous event dispatch (incremental per-sample windows).** Dispatch is
delta-based and **exclusive on `fromTime`**: each sample fires only the events
whose key time falls in its own inter-sample window `(fromTime, toTime]`, and the
event list is **reset between samples** (not accumulated). A `t=0` sample advances
by `0` and fires nothing. The three keyframe-aligned samples therefore read:

| sample | window | `animationEvents` fired |
|--------|--------|-------------------------|
| `rest` (t=0)   | `[0, 0]`   | *(none — channel omitted)* |
| `mid` (t=0.5)  | `(0, 0.5]` | `[hit, hit2]` |
| `end` (t=1.0)  | `(0.5, 1.0]` | `[land]` |

Each fired event carries its exact `name`/`intValue`/`floatValue`/`stringValue`.
The channel is **omitted** at `rest` (empty window), fires **both** co-timed
events at `mid` in authoring order, and fires **only** `land` at `end` — **not**
the cumulative `[hit, hit2, land]`. A runtime that ignores event timelines emits
no `animationEvents` and therefore **fails at `mid` and `end`**; a runtime that
replays from absolute `t=0` each sample (rather than incrementally) would emit the
cumulative list at `end` and also fail. The three goldens are **not**
byte-identical to each other (distinct `animationEvents`, plus distinct
`time`/`sample`/layer-time metadata).

Notes for readers comparing runtimes:
- The goldens are reproduced identically from both `m19_event_rig.bony` and
  `conformance/assets/bnb/m19_event_rig.bnb` (the JSON and binary loaders agree;
  the `.bnb` is non-empty at 271 bytes), keeping **binary event playback** in the
  cross-runtime contract, and regenerate byte-identically on re-run.
- `floatValue`, `volume`, and `balance` are f32-quantized on load; the values here
  (`1.5`, `-2.5`, `0.25`) are exact in f32 so no rounding is visible.
- The static region slot means `bones`, `slots`, and `drawBatches` are identical
  across the three goldens — the event channel is the sole non-vacuity anchor.
- The `event_story` machine is **single-layer**, so `trackIndex` is `0` on every
  dispatched event.
- Cross-runtime status: the `m19_event_story_*` goldens are honored by **both**
  the Nim reference and the Dart runtime. Dart ports the event-timeline model
  (`EventData`/`EventKeyframe`/`EventTimeline` + `AnimationClip.eventTimelines` in
  `runtime-dart/lib/src/model.dart`), the JSON and packed `.bnb` `eventKeys`
  loaders (`runtime-dart/lib/src/loader.dart`), and the mixer dispatch
  (`_dispatchEventsForEntry` in `runtime-dart/lib/src/anim.dart`, gating on the
  half-open `(fromTime, toTime]` window with the `eventThreshold` mix-in
  behavior). It reproduces every `animationEvents` array within `1e-4` (exact
  strings/ints) from both the `.bony` and the `.bnb` by replaying
  **incrementally** — carrying one `AnimationState` across samples and reading the
  events fired per inter-sample window (`AnimationState.update` resets its event
  list each call), never a fresh-runtime absolute-time update
  (`runtime-dart/test/m19_event_story_test.dart`). Event dispatch remains a
  **mixer-level primitive**: the Nim CLI story runner mirrors each layer's active
  clip onto its own single-track `AnimationState` and collects that track's
  dispatched events (`cli/bony_cli.nim:1456-1525`). Dart now carries the same
  clip-mirror bridge inside `StateMachineRuntime.evaluate`; after each evaluate
  call, `StateMachineRuntime.animationEvents` contains the events fired for that
  state-machine step, and the Dart `.bony`/`.bnb` parity tests assert the bridge
  against the M19 goldens.

### M20 skin rig (`m20_skin_rig`)

`m20_skin_rig` freezes the first shared skin-attachment-set behavior in
conformance. It has one identity `root` bone and three visible slot attachment
names: `body`, `badge`, and `patch`. Those names are resolved through `skins`
before draw batches are built; the slot setup attachment remains the visible
name in `slots[]`, while `drawBatches[].attachment` records the concrete region
or mesh target.

The rig defines two skins:
- `default` maps `body` to `body_default_region` (`20x20`), `badge` to
  `badge_default_region` (`12x12`), and `patch` to `patch_default_mesh`.
- `armor` maps `body` to `body_armor_region` (`46x28`) and `patch` to
  `patch_variant_mesh`, but intentionally omits `badge`.

Two scripts drive the same state machine with different `activeSkin` values:
- `m20_skin_default.json` → `m20_skin_default_default.json`
- `m20_skin_variant.json` → `m20_skin_variant_variant.json`

**Non-vacuous active-skin and fallback proof.** The default golden's body batch
is `body_default_region` with corners at `(-10,-10)` and `(10,10)`. The variant
golden's body batch is `body_armor_region` with corners at `(-23,-14)` and
`(23,14)`, a geometry delta far above `1e-4`. The `badge_slot` has no `armor`
entry, so it falls back through the required `default` skin and remains
`badge_default_region` with identical `12x12` vertices in both goldens. A runtime
that ignores active skins fails the body batch; a runtime that omits fallback
drops or changes the badge batch.

The `patch` slot keeps the mesh/deform proof focused. A `skin_pose` clip owns a
deform timeline for skin `armor`, visible attachment `patch`. The mixer resolves
that binding through the skin to `patch_variant_mesh`, so the variant golden's
third patch vertex moves from `y=8` to `y=20`; the default golden uses
`patch_default_mesh` and remains undeformed. This proves deform timelines resolve
through skin lookup without introducing linked meshes, `inheritDeform`,
`skinRequired`, nested rigs, or importer behavior.

Notes for readers comparing runtimes:
- The goldens are reproduced identically from both `m20_skin_rig.bony` and
  `conformance/assets/bnb/m20_skin_rig.bnb`; the Nim CLI regression test
  (`runtime-nim/tests/test_m20_skin_conformance.nim`) exercises both files
  through the same script/golden path used by CI.
- Cross-runtime status: the M20 goldens are honored by **both** the Nim
  reference and the Dart runtime. Dart loads skin declarations from `.bony` and
  `.bnb`, resolves active-skin draw batches with default fallback, resolves
  deform timelines through skin lookup, and reproduces both committed goldens
  within `1e-4` (`runtime-dart/test/m20_skin_test.dart`).

### M21 pointer listener rig (`m21_pointer_listener_rig`)

`m21_pointer_listener_rig` freezes the Nim reference behavior for pointer
listeners over non-rendered helper geometry. It has one `button` bone with two
helper slots:
- `button_box_slot` exposes the `button_hit` bounding-box attachment.
- `button_point_slot` exposes the `spark_point` point attachment.

The `pointer_story` state machine carries four inputs: `hover` (bool),
`pressed` (bool), `intensity` (number), and `pulse` (trigger). Five pointer
listeners mutate those inputs:
- `box_enter` (`pointerEnter`) sets `hover = true` on the bounding box.
- `box_down` (`pointerDown`) sets `pressed = true` on the bounding box.
- `point_move` (`pointerMove`) sets `intensity = 4.5` on the point radius.
- `point_up` (`pointerUp`) fires `pulse` on the point radius.
- `box_exit` (`pointerExit`) sets `hover = false` on the bounding box.

One story script drives six samples:
- `m21_pointer_listener_story.json` → `m21_pointer_listener_<sample>.json` for
  `rest`, `enter`, `down`, `move`, `up`, and `exit`.

**Non-vacuous pointer and transition proof.** The `down` sample dispatches
`box_down` before transition evaluation, so `pressed` becomes true and the
state machine transitions from `idle` to `pressed` in the same sample. Its
`events` array records the pointer event first, then the existing lifecycle
order: `idle_exit`, `idle_to_pressed`, `pressed_enter`. The entered `pressed`
state samples a `30°` button rotation at `t=0`, changing the `button` world
basis from identity to `a≈0.8660, b≈0.5`. The later point samples hit the rotated
point location `(57.320507, 10)`, proving point helper hit testing uses the
current world transform rather than setup-only coordinates.

Notes for readers comparing runtimes:
- The goldens are reproduced identically from both
  `m21_pointer_listener_rig.bony` and
  `conformance/assets/bnb/m21_pointer_listener_rig.bnb`; the `.bnb` fixture is
  non-empty at 846 bytes.
- Pointer listener events are state-machine listener events in the existing
  `events` channel. They are not `animationEvents`; pointer records include
  listener name/kind, slot, target kind/name, mutated input/value, and pointer
  world coordinates.
- Cross-runtime status: the `m21_pointer_listener_*` story goldens are honored
  by **both** the Nim reference and the Dart runtime. Dart replays the story from
  both `m21_pointer_listener_rig.bony` and
  `conformance/assets/bnb/m21_pointer_listener_rig.bnb`, dispatching pointer
  listeners against current helper geometry, preserving same-sample pointer
  events before lifecycle transition events, and matching inputs, listener
  payloads, world transforms, slot metadata, and draw batches within `1e-4`
  (`runtime-dart/test/m21_pointer_listener_test.dart`).

### M22 skinRequired rig (`m22_skin_required_rig`)

`m22_skin_required_rig` freezes the shared activation contract from
`docs/skin-required-activation-contract.md`. Its `default` skin activates the
required `shared_helper` bone, while the `variant` skin repeats that membership
and adds the required `variant_extra` bone plus required IK, transform, path, and
physics constraints. Repeating `shared_helper` across `default` and `variant`
proves duplicate references across the union are idempotent; duplicates within
one skin/family remain invalid and are covered by the Nim loader test.

Two scripts drive the same `skin_required_story` state machine with different
`activeSkin` values:
- `m22_skin_required_default.json` -> `m22_skin_required_default_rest.json` and
  `m22_skin_required_default_late.json`.
- `m22_skin_required_variant.json` -> `m22_skin_required_variant_rest.json`,
  `m22_skin_required_variant_active.json`, and
  `m22_skin_required_variant_settled.json`.

**Non-vacuous activation proof.** In the default late sample, `variant_extra` is
inactive: its world matrix is all zeros and the draw batches contain only
`shared_slot`. In the variant active sample, `variant_extra` is active at
`tx=10, ty=20` and the draw batches contain both `shared_slot` and
`variant_slot`; the variant slot resolves to the larger `variant_active_region`
through active-skin lookup.

**Non-vacuous constraint proof.** With the default skin, required constraints are
no-ops: `copy_bone` stays at `(50,0)`, `path_bone` stays at `tx=70`, and the
required IK bone keeps its setup basis. With the variant skin, those constraints
activate: `ik_bone` rotates to a 90 degree basis, `copy_bone` moves to
`(90,30)`, and `path_bone` moves to `tx=100`. The non-required `later_active`
transform constraint remains active in both skins and keeps `later_bone.tx=11`,
proving inactive required cache entries do not reorder later active work.

**Non-vacuous physics proof.** The required `skin_spring` physics constraint is
inactive under the default skin: after the late sample at `t=0.2`,
`phys_bone.tx` is still `120`. Under the variant skin, the same stateful story
advances the spring: `phys_bone.tx` moves to `120.348381` at `active` and
`121.276993` at `settled`, well above the `1e-4` tolerance. The dedicated Nim
runtime physics test covers the skin-swap case where an inactive required
physics constraint is reactivated and must reset.

Notes for readers comparing runtimes:
- The goldens are reproduced identically from both
  `m22_skin_required_rig.bony` and
  `conformance/assets/bnb/m22_skin_required_rig.bnb`; the `.bnb` fixture is
  non-empty at 1122 bytes.
- The Nim CLI regression test
  (`runtime-nim/tests/test_m22_skin_required_conformance.nim`) exercises JSON
  and `.bnb` parity for all five samples and checks focused malformed membership
  failures for `unknownRequiredReference`, `duplicateKey`, and
  `schemaViolation`.
- Cross-runtime status: this row is a Nim reference conformance gate. Dart
  parity is intentionally deferred to the next skinRequired activation slice.

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
| m12_mesh_rig | pending (no PNG golden produced) |
| m17_mesh_clip_rig | pending (no PNG golden produced) |
| m18_mesh_deform_anim_rig | pending (no PNG golden produced) |
| m19_event_rig | pending (no PNG golden produced) |
| m20_skin_rig | pending (no PNG golden produced) |
| m21_pointer_listener_rig | pending (no PNG golden produced) |
| m22_skin_required_rig | pending (no PNG golden produced) |

---

## Numeric golden format (`bony.numeric-golden.v1`)

Each `*_t0.json` file has the format (the shape below is the **actual** CLI
output — mirror `m11_clip_rig_t0.json` / `m12_mesh_rig_t0.json`, not a
hand-authored abbreviation):

```json
{
  "format": "bony.numeric-golden.v1",
  "skeleton": "<name>",
  "version": "1.0.0",
  "time": 0.0,
  "bones": [
    {"name": "root", "parent": "",
     "world": {"a": 1.0, "b": 0.0, "c": 0.0, "d": 1.0, "tx": 0.0, "ty": 0.0}}
  ],
  "slots": [
    {"name": "head_slot", "bone": "root", "attachment": "head",
     "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
  ],
  "drawBatches": [
    {"slot": "head_slot", "bone": "root", "attachment": "head",
     "texturePage": "", "blendMode": "normal", "clipId": "",
     "world": {"a": 1.0, "b": 0.0, "c": 0.0, "d": 1.0, "tx": 0.0, "ty": 0.0},
     "vertices": [
       {"x": -25.0, "y": -25.0, "u": 0.0, "v": 0.0, "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
       {"x": 25.0, "y": -25.0, "u": 1.0, "v": 0.0, "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
       {"x": 25.0, "y": 25.0, "u": 1.0, "v": 1.0, "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0},
       {"x": -25.0, "y": 25.0, "u": 0.0, "v": 1.0, "r": 1.0, "g": 1.0, "b": 1.0, "a": 1.0}
     ],
     "indices": [0, 1, 2, 2, 3, 0]}
  ]
}
```

Fields:
- `time` — the sampled pose time in seconds (the setup-pose goldens use `0.0`).
- `bones[].parent` — parent bone name (`""` for a root).
- `bones[].world.{a,b,c,d,tx,ty}` — world transform matrix (column-major 2×3),
  nested under a `world` object.
- `slots[].{bone,attachment}` — the slot's bone and active attachment name.
- `slots[].{r,g,b,a}` — projected light color used by draw-batch vertices.
- `slots[].{darkR,darkG,darkB}` — optional projected dark color for two-color timelines.
- `slots[].{sequenceIndex,sequenceDelay,sequenceMode}` — optional sampled sequence metadata.
- `drawBatches[].{slot,bone,attachment,texturePage,blendMode,clipId,world}` — the
  batch's identity and metadata. A **mesh** batch uses the same fields as a region
  batch — `texturePage` and `blendMode` come from the slot/defaults (`""` /
  `"normal"`), and `clipId` is set to the clip name when the mesh slot falls in a
  clip's covered range (meshes clip per-triangle; see `m17_mesh_clip_rig`).
- `drawBatches[].vertices[]` — each vertex is an object
  `{x, y, u, v, r, g, b, a}` (world position, texture coordinate, and per-vertex
  color); a mesh carries no golden field a region does not already have.
- `drawBatches[].indices` — a flat triangle-index list into that batch's
  `vertices` (region quads use `[0,1,2,2,3,0]`; a mesh uses its own `triangles`).
- `deformers` — present only when deformers affect the pose (M7+).

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
- `activeSkin`: optional runtime skin for draw-batch attachment lookup on
  state-machine scripts. Omitted scripts use `"default"`.
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
