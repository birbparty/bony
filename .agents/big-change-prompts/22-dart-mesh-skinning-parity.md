# /big-change prompt - Dart parity (M4 mesh attachment + skinning)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 4 of 4** of the M4 mesh-attachment + skinning
> milestone. Depends on `19` (format), `20` (Nim skinning eval), and `21` (the
> committed `m12_mesh_rig` golden). This slice makes the Dart runtime honor the
> same golden. **Candidate category:** frontier.

---

/big-change Bring the Dart runtime to mesh-attachment + skinning parity: load the mesh record from .bony and .bnb, skin it in buildDrawBatches with the same linear-blend algorithm as Nim, and pass the M12 mesh conformance golden within 1e-4.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Prompts 19-21 defined the mesh record, made the Nim reference skin meshes into
draw batches, and committed the cross-runtime golden `m12_mesh_rig_t0.json`. The
Dart runtime has **no** mesh support at all (confirmed absent: no mesh type-key,
no mesh class, no mesh decode/parse, no skinned draw-batch seam). This slice ports
the load path (JSON + `.bnb`) and the skinning evaluation so Dart reproduces the
committed golden.

Already in place (Dart), to mirror:
- `runtime-dart/lib/src/model.dart`: `RegionAttachment` (57-67), `PathAttachment`
  (197-219), `ClippingAttachment` (221-237), `SkeletonData` ctor (240-255) +
  collection fields `regions` (260) / `pathAttachments` (262) /
  `clippingAttachments` (263), `DrawVertex` (598-618, `x,y,u,v,r,g,b,a`),
  `DrawBatch` (620-642, `clipId` at 638, `indices` at 641).
- `runtime-dart/lib/src/loader.dart`: JSON `_parseRegion` (50-56),
  `_parseClippingAttachment` (58-70), `_parsePathAttachment` (598-610); JSON
  assembly building collections (2841-2856) threaded into `SkeletonData(...)`
  (2901-2916); `.bnb` type-tag constants (`_bnbRegion` 1058,
  `_bnbClippingAttachment` 1059, `_bnbPathAttachment` 1061), known-type set
  (1190-1197), decode cases (region 1969-1975, clipping 1976-1984, pathAttachment
  2076-2088), accumulators (1783-1786), `.bnb` assembly (2543-2558). Wire keys come
  from generated `runtime-dart/lib/src/generated/wire.dart` (regenerated in
  prompt 19; the `meshAttachment` type key 3001 is already present there).
- `runtime-dart/lib/src/transform.dart`: `buildDrawBatches` (1114), region map
  (1120-1122), slot loop emitting region batches (1125-1149, region lookup +
  `continue` at 1127-1128, `clipId: ''` at 1139), deformer re-map copy (1165-1192,
  `clipId: batch.clipId` at 1175), `_applyClipping` (1202+, clip map 1214-1216,
  `clipId: clip.name` at 1248).
- Conformance test harness `runtime-dart/test/m10_conformance_test.dart`:
  `_checkGolden` (42-171), drawBatch metadata compare incl. `clipId` (109-122),
  vertices compare `x,y,u,v,r,g,b,a` within `1e-4` (136-158), indices exact
  (160-169), `main()` registrations (M1 174, M8 180, M5-IK 186, M5-Transform 192,
  M11-Clip 198). Dual-loader `.bony`+`.bnb` pattern: `m5_physics_story_test.dart`
  (`for (final loader in const ['bony','bnb'])` at 87).

Build exactly this:

1. **Dart model** (`model.dart`): add mesh classes mirroring the Nim record and
   the prompt-19 contract - a `MeshInfluence` (`bone` String, `bindX`/`bindY`/
   `weight` double), a `MeshVertex` (either `x`/`y` for unweighted or
   `influences: List<MeshInfluence>` for weighted), a `MeshUv` (or a flat
   `List<double>` of u,v pairs), and a `MeshAttachment` (`name` String,
   `weighted` bool, `vertices`, `uvs`, `triangles: List<int>`). Add a
   `meshAttachments` list to `SkeletonData` (field beside `clippingAttachments`
   263; ctor param beside `clippingAttachments = const []` 247).

2. **Dart loaders** (`loader.dart`):
   - JSON: add a `_parseMeshAttachment` (mirror `_parseClippingAttachment` 58-70)
     decoding the structured vertex/uv/triangle shape prompt 19 emits in the
     canonical JSON schema; build the `meshAttachments` collection (mirror
     2853-2856) and thread it into `SkeletonData(...)` (beside `clippingAttachments:`
     2908).
   - `.bnb`: add a `_bnbMeshAttachment = 3001` type-tag constant (confirm the value
     from `generated/wire.dart`), register it in the known-type set (1190-1197),
     add a `meshes` accumulator (beside `clips` 1786), add a decode `case
     _bnbMeshAttachment:` (mirror the clipping case 1976-1984) that decodes the
     three packed `bytes` payloads **exactly** per the mesh contract's byte layout
     - including the string-table indices for weighted influence bone names (the
     same string-table mechanism the region/clipping string fields use) - and
     thread `meshAttachments: meshes` into the `.bnb` assembly (beside
     `clippingAttachments: clips` 2550).

3. **Dart skinning + emission** (`transform.dart`): author a fresh linear-blend
   skinning routine over the Dart mesh record (there is no Dart skinning util to
   reuse - write it to match the Nim `skinMeshVertices` formula/order in
   `docs/mesh-attachment-contract.md` exactly: `worldPos = sum_i weight_i *
   (boneWorld_i * (bindX_i, bindY_i))`, influences accumulated in stored order;
   unweighted = the slot bone's FK transform of `(x, y)`; f32 quantization at the
   output boundary). In `buildDrawBatches`: build a `meshMap` beside `regionMap`
   (1120-1122); in the slot loop (1125-1149), **before** the region `continue` at
   1127-1128, dispatch on a mesh: skin its vertices, wrap each into a `DrawVertex`
   with `r=g=b=a=1.0` and the mesh's `u,v`, set `indices` to the mesh triangles,
   set `clipId: ''`, and set `slot`/`bone`/`attachment`/`world`/`blendMode`/
   `texturePage` exactly as the region path and the Nim reference do (matching the
   mesh DrawBatch metadata defaults pinned in `docs/mesh-attachment-contract.md`),
   emitting one batch per mesh slot in draw-order position. Preserve the deformer
   re-map path (the `clipId: batch.clipId` copy at 1175 already threads it).
   **Meshes are not clipped in v1** (same decision as Nim prompt 20): make
   `_applyClipping` (1202+) **skip mesh batches** exactly as the Nim clip pass
   does, so a mesh in a clip range keeps `clipId == ''` and its full triangle set -
   do NOT run `clipDrawBatchPolygon` over a mesh (it would fan-collapse the triangle
   soup). Match Nim's f32 rounding so results agree within `1e-4`.

4. **Dart conformance assertion** (`m10_conformance_test.dart`): register the M12
   mesh rig in `main()` with a `_checkGolden('M12-Mesh',
   '../conformance/assets/m12_mesh_rig.bony',
   '../conformance/goldens/m12_mesh_rig_t0.json')` call (mirror the M11-Clip
   registration at 198-202). The existing vertices (`x,y,u,v`) and indices
   compares (136-169) will exercise the skinning. **Additionally** add an in-Dart
   `.bnb` assertion for this rig following the `m5_physics_story_test.dart`
   dual-loader pattern (load both `m12_mesh_rig.bony` and `bnb/m12_mesh_rig.bnb`
   against the same golden) - the `.bnb` mesh decode path (packed weighted
   vertices + string-table bone names) is new and error-prone, so pin it in Dart
   rather than relying only on the CI `.bnb` replay.

5. **Update `conformance/README.md`** cross-runtime status for the M12 mesh rig
   from "Nim honored, Dart pending prompt 22" to "honored by both the Nim reference
   and the Dart runtime" (mirror the transform/physics/clip status paragraphs),
   citing the Dart test.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Mesh contract (the shared skinning formula + packed byte layout Dart must match):
  docs/mesh-attachment-contract.md
- Float math contract: docs/float-math-contract.md (1e-4, quantize, determinism)
- Nim reference to match (behavior, not copied line-for-line since languages
  differ): runtime-nim/src/bony/mesh/skinning.nim (skinMeshVertices 35-93) +
  the mesh dispatch added to runtime-nim/src/bony/transform.nim buildDrawBatches in
  prompt 20
- Dart model: runtime-dart/lib/src/model.dart (ClippingAttachment 221-237,
  SkeletonData 240-271, DrawVertex 598-618, DrawBatch 620-642)
- Dart loader: runtime-dart/lib/src/loader.dart (JSON parsers 50-70 + 598-610,
  assembly 2841-2856 + 2901-2916; bnb type tags 1054-1061, known-type set
  1190-1197, decode cases 1969-2088, accumulators 1783-1786, assembly 2543-2558)
- Dart transform: runtime-dart/lib/src/transform.dart (buildDrawBatches 1114,
  region map 1120-1122, slot loop 1125-1149, region continue 1127-1128,
  clipId '' 1139, deformer copy 1165-1192, _applyClipping 1202+)
- Dart conformance test: runtime-dart/test/m10_conformance_test.dart (_checkGolden
  42-171, clipId assert 120, vertices/indices 136-169, main registrations 173-203);
  dual-loader pattern runtime-dart/test/m5_physics_story_test.dart (loader loop 87)
- Generated wire keys: runtime-dart/lib/src/generated/wire.dart (meshAttachment
  type key 3001 + mesh property keys, present after prompt-19 regen)
- Conformance golden + rig (from prompt 21): conformance/goldens/m12_mesh_rig_t0.json,
  conformance/assets/m12_mesh_rig.bony, conformance/assets/bnb/m12_mesh_rig.bnb
- Dart test runner: runtime-dart/dart_test.yaml; run `dart test` in runtime-dart/
- Analogous freshest Dart-parity slices to mirror: the Dart clipping parity slice
  (prompt 18) and the Dart physics parity slice (prompt 14)
- Beads: file under the mesh-attachment milestone parent, dependent on the
  prompt-21 bead

**Success Criteria**
- Dart loads a mesh (weighted and unweighted) from both `.bony` JSON and `.bnb`
  into `MeshAttachment`/`SkeletonData.meshAttachments`, matching the Nim-parsed
  fields (name, weighted, vertices incl. influences, uvs, triangles).
- Dart `buildDrawBatches` emits one skinned `DrawBatch` per mesh slot with world
  vertices, uvs, and triangle indices matching the Nim reference; unweighted meshes
  via FK, weighted via linear-blend skinning in stored influence order.
- `runtime-dart/test/m10_conformance_test.dart` gains an `M12-Mesh` group that
  loads `m12_mesh_rig.bony` and matches `m12_mesh_rig_t0.json` within `1e-4`
  (vertices, uvs, indices), and a dual-loader assertion also matches
  `bnb/m12_mesh_rig.bnb` against the same golden.
- Meshes are not clipped in v1: `_applyClipping` skips mesh batches (matching Nim),
  so a mesh in or out of a clip range keeps `clipId == ''` and its full triangle
  set.
- `dart test` passes in `runtime-dart/`; existing Dart conformance tests still
  pass unchanged (m10 groups M1/M8/M5-IK/M5-Transform/M11-Clip, the IK/transform
  story tests, and `m5_physics_story_test.dart`).
- `conformance/README.md` records the M12 mesh rig as honored by both runtimes.

**Constraints**
- Preserve clean-room posture: the Dart skinning is a fresh port of `bony`'s own
  project-owned linear-blend formula; do not consult any third-party runtime's
  Dart/Flutter mesh or skinning code.
- The Dart skinning must be **deterministic and match Nim within 1e-4** - same
  influence accumulation order, same unweighted FK path, same f32 quantization
  boundary. If the golden fails, fix the Dart algorithm to match the contract; do
  NOT edit the committed golden (it is the Nim reference contract).
- Keep Rive importer work out of scope; keep Spine importer work blocked.
- Do NOT change the format, the registry, the Nim runtime, or the committed golden
  in this slice - those are prompts 19-21. This slice is Dart-only plus the README
  status update.
- Keep the slice to one meaningful implementation session: Dart mesh load
  (JSON + `.bnb`) + skinning eval + conformance assertion.
