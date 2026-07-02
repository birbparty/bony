# /big-change prompt - Dart parity (M4 clipping attachment)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 4 of 4** of the M4 clipping-attachment milestone.
> Depends on `15`, `16`, and `17` (the format, the Nim runtime effect, and the
> committed golden). This slice makes the Dart runtime honor the same golden.
> **Candidate category:** frontier.

---

/big-change Bring the Dart runtime to clipping-attachment parity: load the record, clip covered draw batches with the same deterministic algorithm as Nim, and pass the M11 clip conformance golden within 1e-4.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Prompts 15-17 defined the clipping record, made the Nim reference clip draw
batches, and committed the cross-runtime golden `m11_clip_rig_t0.json`. The Dart
runtime still hardcodes `clipId: ''` (`runtime-dart/lib/src/transform.dart:1138`)
and has **no** polygon-clipping code (confirmed absent). This slice ports both the
load path and the clip evaluation so Dart reproduces the committed golden.

Already in place (Dart):
- `runtime-dart/lib/src/model.dart`: `SlotData` (45-55), `RegionAttachment`
  (57-67), `DrawBatch` with `clipId` (600-622, `clipId` at `:618`), `DrawVertex`
  x/y/u/v/r/g/b/a (578-598), `SkeletonData` collections `slots`/`regions`/
  `pathAttachments` (221-251).
- `runtime-dart/lib/src/loader.dart`: JSON `_parseSlot` (42-48), `_parseRegion`
  (50-56), `_parsePathAttachment` (584+), assembly (2678-2746); `.bnb`
  accumulators (1637-1640), `_bnbRegion` (1823-1829), `_bnbPathAttachment`
  (1921-1933), type-tag constants (e.g. `_bnbPathAttachment = 4001` at `:942`,
  known-type list `:1073`), assembly (2391-2394). Wire keys come from generated
  `runtime-dart/lib/src/generated/wire.dart` (regenerated in prompt 15).
- `runtime-dart/lib/src/transform.dart`: `buildDrawBatches` (`:1113`, region map
  1119-1121, slot loop 1123-1148, `clipId: ''` at `:1138`, deformer re-map copy
  preserving `clipId: batch.clipId` at `:1170`).
- Conformance test harness `runtime-dart/test/m10_conformance_test.dart`:
  `_expectClose` (`:25`), `_expectAffine` (`:33`), `_checkGolden` (`:42`),
  drawBatch metadata compare incl. `clipId` (`:120`), vertices/indices compares
  (136-169), `main()` registrations (M5-Transform 192-196).

Build exactly this:

1. **Dart model**: add a `ClippingAttachment` class (mirror `RegionAttachment`
   57-67 / `PathAttachment` 197-219) with `name` (String), `vertices`
   (`List<double>` flat x,y pairs), `untilSlot` (String); add a
   `clippingAttachments` list to `SkeletonData` (fields 238-250, constructor
   222-236) beside `pathAttachments`.

2. **Dart loaders**: JSON — add a `_parseClippingAttachment` (mirror `_parseRegion`
   50-56 / `_parsePathAttachment`) and thread `clippingAttachments` into the
   `SkeletonData(...)` assembly (~2744). `.bnb` — add a `_bnbClippingAttachment`
   type-tag constant = `3000` (the M4 type key defined in prompt 15; confirm from
   `generated/wire.dart`), register it in the known-type list (`:1073`), add a
   decode `case` (mirror `_bnbRegion` 1823-1829 / `_bnbPathAttachment` 1921-1933,
   decoding the packed-f32 `vertices` bytes and the `untilSlot` string), add a
   `clips` accumulator (1637-1640), and thread into assembly (2391-2394).

3. **Dart clip evaluation**: author a convex Sutherland–Hodgman clip over
   `DrawVertex` (there is no Dart clip utility to reuse — write it fresh but match
   the Nim algorithm in `docs/clipping-attachment-contract.md` exactly: same
   inside/intersection test, same `u,v,r,g,b,a` interpolation at intersections,
   same fan re-triangulation, same f32 quantization at the output boundary). In
   `buildDrawBatches`: after building batches, set `clipId` on the covered
   draw-order range (from after the clip's slot through `untilSlot` inclusive, else
   to end) and clip those batches' vertices, exactly as Nim does. Preserve the
   existing deformer re-map path (the `clipId: batch.clipId` copy at `:1170`
   already threads it) so a clipped batch keeps its clip result through deformer
   remapping. Match Nim's f32 rounding so results agree within `1e-4`.

4. **Dart conformance assertion**: register the M11 clip rig in
   `m10_conformance_test.dart`'s `main()` with a
   `_checkGolden('M11-Clip', '../conformance/assets/m11_clip_rig.bony',
   '../conformance/goldens/m11_clip_rig_t0.json')` call (mirror the M5-Transform
   registration at `192-196`; the file's `_checkGolden` groups are M1, M8, M5-IK,
   M5-Transform — it loads `.bony` JSON only). The existing `clipId` assertion
   (`:120`) and vertices/indices compares (`136-169`) will exercise the clip.
   **Cross-format `.bnb` coverage is optional here**: the CI `.bnb`→golden replay
   added in prompt 17 already pins Dart-independent binary parity, and
   `_checkGolden` only loads `.bony`. If you want an in-Dart `.bnb` assertion,
   follow the pattern in `runtime-dart/test/m5_physics_story_test.dart` (which
   loads both `.bony` and `bnb/*.bnb` against the same golden) rather than
   extending `_checkGolden` — do not invent a new mechanism.

5. **Update `conformance/README.md`** cross-runtime status for the M11 clip rig
   from "Nim now, Dart pending prompt 18" to "honored by both the Nim reference
   and the Dart runtime" (mirror the transform/physics status paragraphs), citing
   the Dart test.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Clipping contract (the shared algorithm Dart must match): docs/clipping-attachment-contract.md
- Float math contract: docs/float-math-contract.md (1e-4, quantize, determinism)
- Nim reference implementation to match (behavior, not copied line-for-line since
  languages differ): runtime-nim/src/bony/transform.nim buildDrawBatches +
  runtime-nim/src/bony/mesh/clipping.nim
- Dart model: runtime-dart/lib/src/model.dart (RegionAttachment 57-67,
  PathAttachment 197-219, DrawBatch 600-622, DrawVertex 578-598, SkeletonData
  221-251)
- Dart loader: runtime-dart/lib/src/loader.dart (JSON parsers 42-56 + 584+,
  assembly 2678-2746; bnb accumulators 1637-1640, region/path cases 1823-1933,
  type tags 942 + known-type list 1073, assembly 2391-2394)
- Dart transform: runtime-dart/lib/src/transform.dart (buildDrawBatches 1113,
  clipId '' 1138, deformer copy 1170)
- Dart conformance test: runtime-dart/test/m10_conformance_test.dart (_checkGolden
  42, clipId assert 120, vertices/indices 136-169, main registrations 174-196)
- Conformance golden + rig (from prompt 17): conformance/goldens/m11_clip_rig_t0.json,
  conformance/assets/m11_clip_rig.bony, conformance/assets/bnb/m11_clip_rig.bnb
- Dart test runner: runtime-dart/dart_test.yaml; run `dart test` in runtime-dart/
- Analogous freshest Dart-parity slice to mirror: the Dart physics parity slice
  (bead bony-22k, prompt 14) and the Dart transform parity slice (bead bony-cz7,
  prompt 10)
- Beads: file under the clipping milestone parent, dependent on the prompt-17 bead

**Success Criteria**
- Dart loads a `clippingAttachment` from both `.bony` JSON and `.bnb` into the new
  `ClippingAttachment`/`SkeletonData.clippingAttachments`, matching the Nim-parsed
  fields.
- Dart `buildDrawBatches` sets `clipId` over the correct covered range and clips
  those batches with the shared algorithm; out-of-range batches keep `clipId == ''`
  and unclipped quads.
- `runtime-dart/test/m10_conformance_test.dart` gains an `M11-Clip` group that
  loads `m11_clip_rig.bony` (and, optionally, `bnb/m11_clip_rig.bnb` via the
  `m5_physics_story_test.dart` pattern) and matches `m11_clip_rig_t0.json` within
  `1e-4` — including `clipId`, clipped vertices, and indices.
- `dart test` passes in `runtime-dart/`; existing Dart conformance tests still
  pass unchanged — the `m10_conformance_test.dart` groups (M1, M8, M5-IK,
  M5-Transform), the IK/transform story tests, and `m5_physics_story_test.dart`.
- `conformance/README.md` records the M11 clip rig as honored by both runtimes.

**Constraints**
- Preserve clean-room posture: the Dart clip is a fresh port of `bony`'s own
  project-owned algorithm; do not consult any third-party runtime's Dart/Flutter
  clip code.
- The Dart clip must be **deterministic and match Nim within 1e-4** — same
  intersection order, same interpolation, same fan triangulation, same f32
  quantization boundary. If the golden fails, fix the algorithm to match the
  contract; do NOT edit the committed golden (it is the Nim reference contract).
- Keep Rive importer work out of scope; keep Spine importer work blocked.
- Do NOT change the format, the registry, the Nim runtime, or the committed
  golden in this slice — those are prompts 15-17. This slice is Dart-only plus the
  README status update.
- Keep the slice to one meaningful implementation session: Dart load + clip eval +
  conformance assertion.
