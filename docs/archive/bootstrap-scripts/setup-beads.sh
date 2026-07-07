#!/bin/bash
# Project: bony — 2D skeletal + deform animation format
# Generated: 2026-06-13
# Creates the full Beads task graph for the bony monorepo per the binding
# coordination/sequencing/determinism contracts. Creates beads only — does NOT
# implement the project and does NOT commit.

set -e

if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating project beads..."

# ============================================================================
# Phase 0: Repo scaffold, clean-room process, shared sources of truth & contracts
# ============================================================================

REPO=$(bd create "Scaffold monorepo layout (spec/ registry/ codegen/ runtime-nim/ runtime-dart/ cli/ conformance/ docs/)" \
  -d "Create top-level dirs per the coordination section as file-reservation boundaries. Add MIT LICENSE, root nim.cfg with --path:\"src\" matching .nimble srcDir, Nimble package skeleton (runtime-nim/), pub.dev package skeleton (runtime-dart/), conformance/ and docs/ roots. spec/ registry/ conformance/ are CONTENDED shared surfaces — serialize edits, one bead at a time." \
  -p 0 -l setup -t chore --silent)

CLEANROOM=$(bd create "Write docs/CLEANROOM.md + PROVENANCE and the no-fetch-source build rule" \
  -d "Record clean-room mandate (spec §1), carry the §15 capability-only-never-source reference list with per-tool caveats. Standing instruction: agents MUST NOT fetch Spine/Live2D/Rive/DragonBones runtime source via web tools while implementing. Implementation derives only from the binding spec + cited public/textbook math." \
  -p 0 -l docs -t task --silent)
bd dep add $CLEANROOM $REPO

LICENSE_SCAN=$(bd create "License-scan Nim deps (vmath, chroma, pixie, jsony, flatty/binny, naylib) before they become hard deps" \
  -d "Verify each Nim dependency is MIT/Apache (permissive) — verified, not assumed. naylib must be zlib/MIT before it becomes a hard dependency. No GPL/CC/proprietary-derived code. Record results under docs/. Feeds CI license/provenance scan." \
  -p 0 -l core -t task --silent)
bd dep add $LICENSE_SCAN $REPO

REGISTRY=$(bd create "Define append-only type/property-key registry as the canonical binary source of truth" \
  -d "registry/ is the SINGLE declarative source for the .bnb wire: every object type + property -> stable varuint key + backing primitive type; append-only; key 0 reserved as terminator forever. bony.schema.json is generated/cross-checked FROM this + default tables, NOT an independent second source. CONTENDED surface: registry/**." \
  -p 0 -l core -t task --silent)
bd dep add $REGISTRY $REPO

KEY_RANGES=$(bd create "Emit registry/key-ranges.md reserving a varuint band per milestone BEFORE any milestone touches registry/" \
  -d "Committed artifact, not a sentence. Map each milestone M1..M10 -> a reserved varuint key band. Every later registry-editing bead must cite 'use only your allocated range from key-ranges.md'. This range map (plus MCP Agent Mail reservation on registry/**) is what lets M5/M7/M8 edit registry in parallel WITHOUT a serializing dep chain — there is no dep edge for that serialization." \
  -p 0 -l core -t task --silent)
bd dep add $KEY_RANGES $REGISTRY

DEFAULT_TABLES=$(bd create "Author default-table source (drives default-omission) cross-checked against registry" \
  -d "Default tables live in code and drive default-omission on serialize / default-apply on load. Source-of-truth: defaults in code, keys in registry, schema generated. Lives alongside spec/ + registry/ as a contended shared surface input to codegen." \
  -p 0 -l core -t task --silent)
bd dep add $DEFAULT_TABLES $REGISTRY

TOC_SKIP=$(bd create "Resolve ToC skip semantics for array-of-struct (length-prefix vs richer descriptor)" \
  -d "Spec §6.2 'array-of-<prim>' backing types cannot describe array-of-struct (weighted vertices n×(boneIndex,bindX,bindY,weight), keyframe arrays); an old reader cannot compute skip length, so forward-compat skip tests are unbuildable as written. Decide: length-prefix every value (byte count, skip needs no type knowledge) OR define a richer backing-type descriptor. Design bead — GATES M6." \
  -p 0 -l core -t task --silent)
bd dep add $TOC_SKIP $REGISTRY

CODEGEN=$(bd create "Build codegen that emits Nim + Dart encode/decode from registry + default tables, plus the JSON Schema" \
  -d "Dart encode/decode is GENERATED in lockstep, NOT hand-written against the registry — same as Nim. Emit both runtimes' boilerplate + generate/cross-check spec/bony.schema.json. C# generation is a later target of the same codegen. CONTENDED: codegen/**." \
  -p 0 -l core -t task --silent)
bd dep add $CODEGEN $REGISTRY
bd dep add $CODEGEN $DEFAULT_TABLES
bd dep add $CODEGEN $TOC_SKIP

FLOAT_CONTRACT=$(bd create "Determinism feasibility spike + write the float-math contract (docs/float-math-contract.md)" \
  -d "M1, before committing conventions. Dart has NO f32 arithmetic — IEEE-754 doubles only; f32 exists only as Float32List storage with rounding on store. Nim has native f32/f64 + FP-flag sensitivity. Pin: f32-vs-f64 storage-vs-intermediate-compute per runtime, accumulation order for skinning sums + physics integration, and that transcendentals (sin/cos/atan2/pow) are NOT bit-identical across libm/Dart VM (abs<=1e-4 tolerance is the mitigation). Spike must verify IK/path/Bézier accumulate within abs<=1e-4." \
  -p 0 -l core -t task --silent)
bd dep add $FLOAT_CONTRACT $REPO

XFORM_MATH=$(bd create "Specify transform composition: inherit-rotation/scale/reflection factoring + 5 transformModes (§8.1)" \
  -d "From-first-principles decomposition (clean-room forbids copying; the spec gives no formulas). Document once in spec/, shared across runtimes. A golden per transformMode is added at M2. Output: written contract in spec/ or docs/." \
  -p 0 -l core -t task --silent)
bd dep add $XFORM_MATH $FLOAT_CONTRACT

CONSTRAINT_ORDER=$(bd create "Define + document constraint total-order invariant (§5.1/§7.2)" \
  -d "IK/transform/path/physics live in four arrays sharing a global 'order'. Define a total ordering for ties (e.g. order, then fixed array-kind priority, then array index) as a documented invariant — ties otherwise produce nondeterministic poses. Precedes M5." \
  -p 0 -l core -t task --silent)
bd dep add $CONSTRAINT_ORDER $FLOAT_CONTRACT

PHYSICS_CONTRACT=$(bd create "Write the physics integrator contract (§8.7)" \
  -d "Pin: integrator (semi-implicit vs explicit Euler — they diverge), leftover-time accumulator policy (carry remainder vs clamp), fixed substep (1/60 s) + max-substeps clamp, deterministic initial velocity/position seeding, and reset semantics. Precedes M5 physics constraint." \
  -p 0 -l core -t task --silent)
bd dep add $PHYSICS_CONTRACT $FLOAT_CONTRACT

JSON_CANON=$(bd create "Write JSON canonicalization rules (§6/§10)" \
  -d "Pin key sort order, float formatting, angle (degree<->radian) precision. Required before the json->bnb->json idempotency conformance bead (idempotent modulo default omission). Output: docs/ contract." \
  -p 0 -l core -t task --silent)
bd dep add $JSON_CANON $REPO

BINARY_CANON=$(bd create "Write binary canonicalization rules (§6.2/§10) for bnb->json->bnb byte-stability" \
  -d "Sibling contract to JSON canon for the bnb->json->bnb TRUE bit-identity bar (single runtime). Pin string-interning insertion order (first-seen vs sorted), object emission order (spec's 'canonical order' is undocumented — write it down), ToC property ordering, deterministic default-omission. Required before bnb->json->bnb conformance/CI gate." \
  -p 0 -l core -t task --silent)
bd dep add $BINARY_CANON $TOC_SKIP

HASH_BOUNDS=$(bd create "Record header.hash / bounds decision (§5.1) — decided defaults, do not re-open" \
  -d "bounds = nonessential/optional, recomputed on load, omitted from byte-stability, NOT a Dart conformance target. hash = a defined function over the canonical .bnb byte stream (excluding the hash field itself), cross-runtime stable — OR omitted entirely. Pick 'defined function' unless it complicates byte-stability, then drop it. Record the choice in docs/." \
  -p 0 -l core -t task --silent)
bd dep add $HASH_BOUNDS $BINARY_CANON

LOAD_VALIDATION=$(bd create "Specify load-time validation pass (§10 fuzz vs §6.2 forward-compat reconciliation)" \
  -d "Forward-compat says skip unknown gracefully; fuzzing says reject malformed hard — they meet in the same loader. Documented validation deliverable: reject cyclic refs (bone parents, deformer tree, skin-bone refs — index loops in binary, ordering violations in JSON), truncated/bad varints, length mismatches; STILL skip unknown-but-well-formed objects/properties. Acceptance bar: Nim = typed error, no panic/segfault, bounded time; Dart = typed exception, no hang. Gates M6 loaders + fuzz gate." \
  -p 0 -l core -t task --silent)
bd dep add $LOAD_VALIDATION $TOC_SKIP
bd dep add $LOAD_VALIDATION $BINARY_CANON

VERSIONING=$(bd create "Decide + record versioning relationship (format major.minor vs Nim pkg vs Dart pkg vs spec doc)" \
  -d "Record: on-disk header major.minor (§11), Nim package version, Dart package version, spec document version — and what v1 ships as. Same major must remain readable (unknown skipped via ToC). Append-only key registry, reserved terminator key 0. Output: docs/ versioning note." \
  -p 1 -l docs -t decision --silent)
bd dep add $VERSIONING $REPO

# ============================================================================
# Perf-harness scaffold (non-gating, early structural home)
# ============================================================================

PERF_HARNESS=$(bd create "Non-gating perf-harness scaffold (immutable SkeletonData / per-instance SkeletonInstance split, O(bones+constraints) cache)" \
  -d "Budgets are DEFERRED — do NOT gate on this. Give the §7.1 immutable-SkeletonData vs per-instance-SkeletonInstance split and the O(bones+constraints) update cache a structural home so budgets can be set/improved once there is something to measure. Lands by M10." \
  -p 2 -l nim-runtime -t task --silent)
bd dep add $PERF_HARNESS $REPO

# ============================================================================
# CI scaffold (early) — split, not one monolith
# ============================================================================

CI_SCAFFOLD=$(bd create "CI_SCAFFOLD (Linux-only): build+test+lint/vet, schema/registry/default-table in-sync, codegen-freshness, license/provenance scan" \
  -d "No platform matrix (macOS/Windows out of scope). Gates: build+test+lint/vet for Nim + Dart; schema/registry/default-table in-sync check; codegen-freshness check (committed codegen == freshly regenerated — without this an agent edits registry, forgets to regen, and passes CI, defeating lockstep); license/provenance scan. Incremental conformance gates attach to later milestones." \
  -p 0 -l deploy -t task --silent)
bd dep add $CI_SCAFFOLD $CODEGEN
bd dep add $CI_SCAFFOLD $LICENSE_SCAN

# ============================================================================
# Phase M1 (Nim): Core data model + .bony JSON I/O + HARNESS_CORE + goldens
# ============================================================================

NIM_MODEL=$(bd create "Nim M1: SkeletonData model + default tables + .bony JSON parser/serializer" \
  -d "Reservation: runtime-nim/src/**. Consume generated boilerplate from codegen. Default-omission on serialize, default-apply on load. treeform stack: vmath/chroma/jsony. Immutable SkeletonData vs per-instance SkeletonInstance split (§7.1)." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NIM_MODEL $CODEGEN
bd dep add $NIM_MODEL $FLOAT_CONTRACT

HARNESS_CORE=$(bd create "Nim CLI HARNESS_CORE: json<->bnb, play --t --out frame.png, --state-machine driving, numeric golden-gen" \
  -d "Reservation: cli/**. Built at M1 BEFORE M2 — numeric golden-gen has NO rasterizer dependency. EVERY GOLDEN_Mx (numeric) bead depends on this. Image golden-gen is a later add-on gated on the M2 software rasterizer. Without this edge an M1 golden would be produced by a tool that doesn't exist yet." \
  -p 0 -l cli -t feature --silent)
bd dep add $HARNESS_CORE $NIM_MODEL

ASSET_RIG=$(bd create "Author shared M1 example rig + (time,inputs) sample script in conformance/" \
  -d "Owned shared asset (hand-written rig) living in conformance/assets + conformance/scripts; consumed UNCHANGED by both runtimes, NOT re-derived per runtime. CONTENDED: conformance/**." \
  -p 1 -l conformance -t task --silent)
bd dep add $ASSET_RIG $NIM_MODEL

GOLDEN_M1=$(bd create "Generate + commit M1 numeric golden vectors via 'bony golden-gen'" \
  -d "Numeric goldens: per-bone world transforms, per-slot color/attachment, emitted f32 vertex+index buffers, agreement abs<=1e-4. This COMMITTED artifact is the dependency edge Dart M1 gates on (NOT the Nim task). Produced BY HARNESS_CORE." \
  -p 0 -l conformance -t task --silent)
bd dep add $GOLDEN_M1 $HARNESS_CORE
bd dep add $GOLDEN_M1 $ASSET_RIG

# Incremental CI gate: conformance-run gate enabled by first numeric goldens
CI_CONFORMANCE_GATE=$(bd create "CI gate: enable conformance-run (numeric goldens) on Linux, attached to M1 goldens" \
  -d "First incremental gate beyond CI_SCAFFOLD. Runs the conformance suite numeric-golden comparison (abs<=1e-4) for both runtimes on Linux. Becomes runnable once M1 numeric goldens exist." \
  -p 0 -l deploy -t task --silent)
bd dep add $CI_CONFORMANCE_GATE $CI_SCAFFOLD
bd dep add $CI_CONFORMANCE_GATE $GOLDEN_M1

CI_ASSET_SCHEMA_GATE=$(bd create "CI gate: asset-schema-validation against bony.schema.json, attached to first conformance assets" \
  -d "Validate all conformance/ .bony assets against the generated bony.schema.json. Runnable once the first conformance/ assets (ASSET_RIG) exist." \
  -p 1 -l deploy -t task --silent)
bd dep add $CI_ASSET_SCHEMA_GATE $CI_SCAFFOLD
bd dep add $CI_ASSET_SCHEMA_GATE $ASSET_RIG

# ============================================================================
# Phase M1 (Dart): gated on committed Nim goldens
# ============================================================================

DART_M1=$(bd create "Dart M1: SkeletonData model + .bony loader, gated against committed M1 goldens" \
  -d "Reservation: runtime-dart/lib/**, runtime-dart/test/**. Uses GENERATED Dart boilerplate from codegen. Conformance runner consumes the SAME committed conformance/ goldens — does not re-derive them. Edge is the GOLDEN_M1 artifact, not the Nim task." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M1 $GOLDEN_M1
bd dep add $DART_M1 $CODEGEN

# ============================================================================
# Phase M2 (Nim): world transforms + region attachments + draw order + renderers
# ============================================================================

NIM_M2=$(bd create "Nim M2: world transform pass + region attachments + draw order" \
  -d "Reservation: runtime-nim/src/**. Apply the §8.1 transform-composition contract (5 transformModes). Emit backend-neutral DrawBatch command list (§7.6). Renderer-agnostic core." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NIM_M2 $NIM_MODEL
bd dep add $NIM_M2 $XFORM_MATH

PIXIE_RASTER=$(bd create "Nim M2: pixie software reference rasterizer (conformance image goldens only)" \
  -d "Reservation: runtime-nim/src/render/software*. pixie-backed; deterministic, reference-runtime-only. Backs headless image-diff goldens, NOT the shipped real-time path. Consumes the DrawBatch command list." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $PIXIE_RASTER $NIM_M2

DRAWBATCH_RAYLIB=$(bd create "Contract: DrawBatch->raylib semantics (blend modes/PMA, 2-color tint-black shader, clip strategy)" \
  -d "PRECEDES the naylib adapter (adapter depends on it). Pin: blend-mode table incl per-page premultiplied alpha (raylib defaults to straight-alpha BLEND_ALPHA; PMA pages need BLEND_ALPHA_PREMULTIPLY or a custom mode); the 2-color tint-black shader contract (raylib has no built-in two-color tint — custom shader required); clip strategy (v1 convex clipping is geometry-side per §8.9, adapter consumes pre-clipped triangles; document stencil-vs-geometry). Output: written contract in docs/." \
  -p 0 -l core -t task --silent)
bd dep add $DRAWBATCH_RAYLIB $NIM_M2

NAYLIB_ADAPTER=$(bd create "Nim M2: naylib (raylib) renderer adapter — prioritized real-time target consuming DrawBatch" \
  -d "Reservation: runtime-nim/src/render/naylib*. Consumes the backend-neutral DrawBatch list. DONE-criterion under Linux-only, GPU-less CI: (a) compiles+links against naylib on Linux, (b) passes a HEADLESS SMOKE TEST that builds DrawBatches and asserts the adapter issues the mapped raylib draw calls without crashing (offscreen/xvfb or a mock raylib seam), (c) documented manual visual-check step. naylib output is NEVER the conformance source — numeric goldens are. There is NO Dart-naylib bead." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NAYLIB_ADAPTER $DRAWBATCH_RAYLIB
bd dep add $NAYLIB_ADAPTER $LICENSE_SCAN

ASSET_M2=$(bd create "Author shared M2 conformance asset (region-attachment rig) in conformance/" \
  -d "Owned shared asset for world-transform + region quad coverage. CONTENDED: conformance/**. Consumed unchanged by both runtimes." \
  -p 1 -l conformance -t task --silent)
bd dep add $ASSET_M2 $NIM_M2

GOLDEN_M2=$(bd create "Generate + commit M2 NUMERIC golden vectors (world transforms + region quad vertex/index buffers) + per-transformMode golden" \
  -d "Numeric golden is the Dart gate (abs<=1e-4): per-bone world transforms + region quad vertex+index buffers, PLUS a golden per transformMode (5). Depends on HARNESS_CORE (numeric golden-gen, no rasterizer dep). Even rendering milestone M2 gets a numeric golden so Dart never gates on an image golden." \
  -p 0 -l conformance -t task --silent)
bd dep add $GOLDEN_M2 $HARNESS_CORE
bd dep add $GOLDEN_M2 $NIM_M2
bd dep add $GOLDEN_M2 $ASSET_M2
bd dep add $GOLDEN_M2 $XFORM_MATH

IMG_GOLDEN_M2=$(bd create "Image golden-gen (Nim-only) + image-diff golden harness, gated on pixie rasterizer (M2)" \
  -d "Image-diff PNG goldens are an ADDITIONAL Nim-only artifact, reference-runtime-only regression tests — NEVER a Dart dependency edge (two rasterizers cannot match pixels). Pin a concrete metric+threshold (max per-channel delta <= N, or SSIM >= X), not 'perceptual diff'. Image golden-gen depends on the M2 software rasterizer." \
  -p 1 -l conformance -t task --silent)
bd dep add $IMG_GOLDEN_M2 $PIXIE_RASTER
bd dep add $IMG_GOLDEN_M2 $ASSET_M2

DART_M2=$(bd create "Dart M2: world transforms + region attachments numeric gate (gated on GOLDEN_M2)" \
  -d "Reservation: runtime-dart/lib/**. Consumes the SAME committed M2 numeric goldens. Edge is GOLDEN_M2, not the Nim task. No naylib counterpart." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M2 $GOLDEN_M2
bd dep add $DART_M2 $DART_M1

DART_M2_FLUTTER=$(bd create "Dart M2: Flutter CustomPainter/RenderObject render integration" \
  -d "Reservation: runtime-dart/lib/flutter/**. The Flutter render path is its OWN Dart bead (separate from the numeric gate). Consumes DrawBatch-equivalent command emission. Packaged for pub.dev." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M2_FLUTTER $DART_M2

# ============================================================================
# Phase M3: bone/slot timelines, Bézier easing, multi-track mixer, events
# ============================================================================

NIM_M3=$(bd create "Nim M3: bone/slot timelines + Bézier easing (fixed 16-sample) + multi-track mixer/crossfade + events" \
  -d "Reservation: runtime-nim/src/**. Fixed 16-sample Bézier solve table (§8.3/§13). Multi-track mixer with crossfade; event timelines. Deterministic ordered update cache." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NIM_M3 $NIM_M2

ASSET_M3=$(bd create "Author shared M3 conformance asset (animated rig + sample script) in conformance/" \
  -d "Owned shared asset covering timelines/easing/mixing/events. CONTENDED: conformance/**." \
  -p 1 -l conformance -t task --silent)
bd dep add $ASSET_M3 $NIM_M3

GOLDEN_M3=$(bd create "Generate + commit M3 numeric golden vectors (sampled poses across time/tracks)" \
  -d "Numeric Dart gate (abs<=1e-4): per-bone world transforms + per-slot color sampled at (time) points across mixed tracks. Depends on HARNESS_CORE." \
  -p 0 -l conformance -t task --silent)
bd dep add $GOLDEN_M3 $HARNESS_CORE
bd dep add $GOLDEN_M3 $NIM_M3
bd dep add $GOLDEN_M3 $ASSET_M3

IMG_GOLDEN_M3=$(bd create "Image golden (Nim-only) for M3 animated frames, gated on pixie rasterizer" \
  -d "Additional Nim-only image-diff regression frames. Never a Dart edge. Uses the pinned image metric+threshold." \
  -p 2 -l conformance -t task --silent)
bd dep add $IMG_GOLDEN_M3 $PIXIE_RASTER
bd dep add $IMG_GOLDEN_M3 $ASSET_M3

DART_M3=$(bd create "Dart M3: animations + Bézier easing + multi-track mixer + events (gated on GOLDEN_M3)" \
  -d "Reservation: runtime-dart/lib/**. Same 16-sample Bézier table. Edge is GOLDEN_M3." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M3 $GOLDEN_M3
bd dep add $DART_M3 $DART_M2

# ============================================================================
# Phase M4: meshes, LBS skinning, deform timelines, convex clipping, sequences
# (mesh + skinning may cluster)
# ============================================================================

NIM_M4_MESH=$(bd create "Nim M4 (cluster 1/4): mesh attachments + bind data" \
  -d "Reservation: runtime-nim/src/mesh/**. Single-owner cluster step: <=750 LOC, chained sequentially with the skinning/deform/clip steps so no two run concurrently on the same subtree." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NIM_M4_MESH $NIM_M3

NIM_M4_SKIN=$(bd create "Nim M4 (cluster 2/4): linear-blend skinning (LBS, v1; dual-quat hook only)" \
  -d "Reservation: runtime-nim/src/mesh/**. Linear-blend skinning per §13 (dual-quat is a hook only in v1). Skinning sum accumulation order per the float-math contract. Chained after mesh step." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NIM_M4_SKIN $NIM_M4_MESH
bd dep add $NIM_M4_SKIN $FLOAT_CONTRACT

NIM_M4_DEFORM=$(bd create "Nim M4 (cluster 3/4): deform timelines" \
  -d "Reservation: runtime-nim/src/mesh/**. Per-vertex deform timeline blending. Chained after skinning step." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NIM_M4_DEFORM $NIM_M4_SKIN

NIM_M4_CLIP=$(bd create "Nim M4 (cluster 4/4): convex clipping (v1) + sequences/flipbook" \
  -d "Reservation: runtime-nim/src/mesh/**. Convex clipping in v1 (concave behind a flag per §8.9/§13), geometry-side so renderer consumes pre-clipped triangles. Sequences/flipbook attachment. Chained after deform step." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NIM_M4_CLIP $NIM_M4_DEFORM

ASSET_M4=$(bd create "Author shared M4 'weighted/deforming/clipped character' asset in conformance/" \
  -d "Owned shared asset covering weighted mesh + deform + convex clip + sequence. CONTENDED: conformance/**. Consumed unchanged by both runtimes." \
  -p 1 -l conformance -t task --silent)
bd dep add $ASSET_M4 $NIM_M4_CLIP

GOLDEN_M4=$(bd create "Generate + commit M4 numeric golden vectors (skinned/deformed/clipped vertex+index buffers)" \
  -d "Numeric Dart gate (abs<=1e-4): emitted f32 vertex+index buffers after skinning/deform/clip, per-slot color/attachment. Depends on HARNESS_CORE." \
  -p 0 -l conformance -t task --silent)
bd dep add $GOLDEN_M4 $HARNESS_CORE
bd dep add $GOLDEN_M4 $NIM_M4_CLIP
bd dep add $GOLDEN_M4 $ASSET_M4

IMG_GOLDEN_M4=$(bd create "Image golden (Nim-only) for M4 weighted/deformed/clipped character, gated on pixie rasterizer" \
  -d "Additional Nim-only image-diff regression. Never a Dart edge. Pinned image metric+threshold." \
  -p 2 -l conformance -t task --silent)
bd dep add $IMG_GOLDEN_M4 $PIXIE_RASTER
bd dep add $IMG_GOLDEN_M4 $ASSET_M4

DART_M4=$(bd create "Dart M4: meshes + LBS skinning + deform + convex clipping + sequences (gated on GOLDEN_M4)" \
  -d "Reservation: runtime-dart/lib/**. f32 storage via Float32List, double compute per float-math contract. Edge is GOLDEN_M4." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M4 $GOLDEN_M4
bd dep add $DART_M4 $DART_M3

# ============================================================================
# Phase M5: constraints (SINGLE-OWNER CLUSTER, chained) + ordered update cache
# IK_SOLVER -> TRANSFORM_CON -> PATH_CON -> PHYSICS_CON -> ORDERED_CACHE
# ============================================================================

IK_SOLVER=$(bd create "Nim M5 (cluster 1/5): IK constraints (1-bone, 2-bone, chain/FABRIK-class)" \
  -d "Reservation: runtime-nim/src/constraints/**. Single-owner cluster, <=750 LOC, chained sequentially so no two cluster beads run concurrently on the same subtree. Uses only its allocated key-range from registry/key-ranges.md." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $IK_SOLVER $NIM_M4_CLIP
bd dep add $IK_SOLVER $CONSTRAINT_ORDER
bd dep add $IK_SOLVER $KEY_RANGES

TRANSFORM_CON=$(bd create "Nim M5 (cluster 2/5): transform constraints" \
  -d "Reservation: runtime-nim/src/constraints/**. Chained after IK_SOLVER. Use only allocated key-range from key-ranges.md." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $TRANSFORM_CON $IK_SOLVER

PATH_CON=$(bd create "Nim M5 (cluster 3/5): path constraints" \
  -d "Reservation: runtime-nim/src/constraints/**. Chained after TRANSFORM_CON. Use only allocated key-range from key-ranges.md." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $PATH_CON $TRANSFORM_CON

PHYSICS_CON=$(bd create "Nim M5 (cluster 4/5): physics constraints (fixed-substep accumulator per contract)" \
  -d "Reservation: runtime-nim/src/constraints/**. Chained after PATH_CON. Implement per the physics-integrator contract (integrator, accumulator policy, substep clamp, seeding, reset). Use only allocated key-range." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $PHYSICS_CON $PATH_CON
bd dep add $PHYSICS_CON $PHYSICS_CONTRACT

ORDERED_CACHE=$(bd create "Nim M5 (cluster 5/5): O(bones+constraints) deterministic ordered update cache" \
  -d "Reservation: runtime-nim/src/constraints/**. Chained after PHYSICS_CON. Deterministic ordered update cache (§7.2) enforcing the documented constraint total-order invariant. Closes the M5 cluster." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $ORDERED_CACHE $PHYSICS_CON
bd dep add $ORDERED_CACHE $CONSTRAINT_ORDER

ASSET_M5=$(bd create "Author shared M5 conformance asset (rig exercising IK/transform/path/physics + order ties) in conformance/" \
  -d "Owned shared asset covering all four constraint kinds and total-order tie cases. CONTENDED: conformance/**." \
  -p 1 -l conformance -t task --silent)
bd dep add $ASSET_M5 $ORDERED_CACHE

GOLDEN_M5=$(bd create "Generate + commit M5 numeric golden vectors (constrained poses, deterministic order)" \
  -d "Numeric Dart gate (abs<=1e-4): per-bone world transforms after constraint solve in deterministic order. Depends on HARNESS_CORE. Physics seeded deterministically per contract." \
  -p 0 -l conformance -t task --silent)
bd dep add $GOLDEN_M5 $HARNESS_CORE
bd dep add $GOLDEN_M5 $ORDERED_CACHE
bd dep add $GOLDEN_M5 $ASSET_M5

IMG_GOLDEN_M5=$(bd create "Image golden (Nim-only) for M5 constrained poses, gated on pixie rasterizer" \
  -d "Additional Nim-only image-diff regression. Never a Dart edge." \
  -p 2 -l conformance -t task --silent)
bd dep add $IMG_GOLDEN_M5 $PIXIE_RASTER
bd dep add $IMG_GOLDEN_M5 $ASSET_M5

DART_M5=$(bd create "Dart M5: IK/transform/path/physics constraints + ordered cache (gated on GOLDEN_M5)" \
  -d "Reservation: runtime-dart/lib/**. Implement the documented total-order + physics-integrator contracts identically. Edge is GOLDEN_M5." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M5 $GOLDEN_M5
bd dep add $DART_M5 $DART_M4

# ============================================================================
# Phase M6: .bnb binary (SINGLE-OWNER CLUSTER, chained) + round-trip tools
# TOC -> INTERN -> STREAM -> ROUNDTRIP
# ============================================================================

BNB_TOC=$(bd create "Nim M6 (cluster 1/4): .bnb header + Table-of-Contents (per ToC-skip contract)" \
  -d "Reservation: runtime-nim/src/binary/**. Single-owner cluster, <=750 LOC, chained. 4-byte BONY fingerprint, packed major<<16|minor version, flags, ToC mapping every property key -> backing primitive type for skip-ability. Implement the resolved array-of-struct skip semantics (length-prefix or richer descriptor). LEB128/varuint helpers." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $BNB_TOC $NIM_M4_CLIP
bd dep add $BNB_TOC $TOC_SKIP
bd dep add $BNB_TOC $CODEGEN

BNB_INTERN=$(bd create "Nim M6 (cluster 2/4): optional interned string table (per binary-canon insertion order)" \
  -d "Reservation: runtime-nim/src/binary/**. Chained after BNB_TOC. String interning on by default (§13). Insertion order pinned by the binary-canonicalization contract (first-seen vs sorted)." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $BNB_INTERN $BNB_TOC
bd dep add $BNB_INTERN $BINARY_CANON

BNB_STREAM=$(bd create "Nim M6 (cluster 3/4): flat type-keyed object stream (terminator key 0) + optional embedded atlas + load validation" \
  -d "Reservation: runtime-nim/src/binary/**. Chained after BNB_INTERN. Type-keyed object stream terminated by property key 0; optional embedded atlas. Apply the load-time validation pass (reject malformed, skip unknown-but-well-formed). Honors hash/bounds decision." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $BNB_STREAM $BNB_INTERN
bd dep add $BNB_STREAM $LOAD_VALIDATION
bd dep add $BNB_STREAM $HASH_BOUNDS

BNB_ROUNDTRIP=$(bd create "Nim M6 (cluster 4/4): json<->bnb round-trip tools (canonical, both directions)" \
  -d "Reservation: runtime-nim/src/binary/** + cli/**. Chained after BNB_STREAM. bnb->json->bnb byte-stable (true bit-identity) per binary-canon; json->bnb->json idempotent modulo default omission per JSON-canon. Closes the M6 cluster." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $BNB_ROUNDTRIP $BNB_STREAM
bd dep add $BNB_ROUNDTRIP $JSON_CANON
bd dep add $BNB_ROUNDTRIP $BINARY_CANON

ASSET_M6=$(bd create "Author shared M6 conformance asset (.bnb fixtures incl forward-compat unknown-object case) in conformance/" \
  -d "Owned shared asset: .bnb binaries + a forward-compat fixture carrying an unknown-but-well-formed object/property an old reader must skip. CONTENDED: conformance/**." \
  -p 1 -l conformance -t task --silent)
bd dep add $ASSET_M6 $BNB_ROUNDTRIP

GOLDEN_M6=$(bd create "Generate + commit M6 numeric golden vectors (decoded-from-.bnb poses/buffers)" \
  -d "Numeric Dart gate (abs<=1e-4): poses/colors/vertex+index buffers decoded from .bnb match the .bony-decoded goldens. Depends on HARNESS_CORE." \
  -p 0 -l conformance -t task --silent)
bd dep add $GOLDEN_M6 $HARNESS_CORE
bd dep add $GOLDEN_M6 $BNB_ROUNDTRIP
bd dep add $GOLDEN_M6 $ASSET_M6

CI_JSON_RT_GATE=$(bd create "CI gate: json->bnb->json idempotency (modulo default omission), attached to M6 + JSON-canon" \
  -d "Idempotency gate runnable once M6 round-trip tools + JSON canonicalization rules exist. Runs on Linux." \
  -p 0 -l deploy -t task --silent)
bd dep add $CI_JSON_RT_GATE $CI_SCAFFOLD
bd dep add $CI_JSON_RT_GATE $BNB_ROUNDTRIP
bd dep add $CI_JSON_RT_GATE $JSON_CANON

CI_BNB_RT_GATE=$(bd create "CI gate: bnb->json->bnb byte-stability, attached to M6 + binary-canon" \
  -d "True bit-identity gate runnable once M6 round-trip tools + binary canonicalization rules exist. Runs on Linux." \
  -p 0 -l deploy -t task --silent)
bd dep add $CI_BNB_RT_GATE $CI_SCAFFOLD
bd dep add $CI_BNB_RT_GATE $BNB_ROUNDTRIP
bd dep add $CI_BNB_RT_GATE $BINARY_CANON

CI_FWDCOMPAT_GATE=$(bd create "CI gate: forward-compat skip test, attached to M6 + ToC-skip + M6 asset" \
  -d "Asserts an old reader skips unknown-but-well-formed objects/properties using ToC skip lengths. Runnable once M6 + the forward-compat fixture exist. Runs on Linux." \
  -p 0 -l deploy -t task --silent)
bd dep add $CI_FWDCOMPAT_GATE $CI_SCAFFOLD
bd dep add $CI_FWDCOMPAT_GATE $BNB_STREAM
bd dep add $CI_FWDCOMPAT_GATE $TOC_SKIP
bd dep add $CI_FWDCOMPAT_GATE $ASSET_M6

CI_FUZZ_GATE=$(bd create "CI gate: fuzz the .bnb loader (reject malformed hard), attached to M6 + load-validation" \
  -d "Fuzz truncated/bad varints, length mismatches, cyclic refs — loader must reject with typed error (Nim) / typed exception (Dart), no panic/segfault/hang, bounded time. Runnable once M6 stream + load-validation spec exist. Runs on Linux." \
  -p 0 -l deploy -t task --silent)
bd dep add $CI_FUZZ_GATE $CI_SCAFFOLD
bd dep add $CI_FUZZ_GATE $BNB_STREAM
bd dep add $CI_FUZZ_GATE $LOAD_VALIDATION

DART_M6=$(bd create "Dart M6: .bnb loader (gated on GOLDEN_M6)" \
  -d "Reservation: runtime-dart/lib/**. Generated Dart decode boilerplate; implement load-time validation (typed exceptions, no hang). Edge is GOLDEN_M6." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M6 $GOLDEN_M6
bd dep add $DART_M6 $DART_M5

# ============================================================================
# Phase M7: warp/rotation deformers, parameter axes, keyform multilinear blend
# ============================================================================

NIM_M7=$(bd create "Nim M7: warp/rotation deformers + parameter axes + keyform multilinear blend + parameter timelines" \
  -d "Reservation: runtime-nim/src/deform/**. Live2D-class warp/rotation deformers, parameter axes, parameter-driven keyform multilinear blending, parameter timelines. Uses only its allocated key-range from key-ranges.md (parallel-safe with M5/M8 via reservation, no dep edge)." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $NIM_M7 $NIM_M4_CLIP
bd dep add $NIM_M7 $KEY_RANGES

ASSET_M7=$(bd create "Author shared M7 conformance asset (deformers + parameter axes + keyforms) in conformance/" \
  -d "Owned shared asset covering warp/rotation deformers and multilinear keyform blend. CONTENDED: conformance/**." \
  -p 1 -l conformance -t task --silent)
bd dep add $ASSET_M7 $NIM_M7

GOLDEN_M7=$(bd create "Generate + commit M7 numeric golden vectors (deformed vertex buffers under parameter blend)" \
  -d "Numeric Dart gate (abs<=1e-4): emitted vertex buffers + transforms under deformer/parameter/keyform blending. Depends on HARNESS_CORE." \
  -p 0 -l conformance -t task --silent)
bd dep add $GOLDEN_M7 $HARNESS_CORE
bd dep add $GOLDEN_M7 $NIM_M7
bd dep add $GOLDEN_M7 $ASSET_M7

IMG_GOLDEN_M7=$(bd create "Image golden (Nim-only) for M7 deformed frames, gated on pixie rasterizer" \
  -d "Additional Nim-only image-diff regression. Never a Dart edge." \
  -p 2 -l conformance -t task --silent)
bd dep add $IMG_GOLDEN_M7 $PIXIE_RASTER
bd dep add $IMG_GOLDEN_M7 $ASSET_M7

DART_M7=$(bd create "Dart M7: deformers + parameter axes + keyform blend (gated on GOLDEN_M7)" \
  -d "Reservation: runtime-dart/lib/**. Identical multilinear blend math. Edge is GOLDEN_M7." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M7 $GOLDEN_M7
bd dep add $DART_M7 $DART_M6

# ============================================================================
# Phase M8: state machine (SINGLE-OWNER CLUSTER, chained)
# SM_CORE -> SM_INPUTS -> SM_TRANSITIONS -> SM_LISTENERS -> SM_BLEND
# ============================================================================

SM_CORE=$(bd create "Nim M8 (cluster 1/5): state machine core + layers" \
  -d "Reservation: runtime-nim/src/statemachine/**. Single-owner cluster, <=750 LOC, chained. Rive-class state machine: layer structure + evaluation skeleton. Uses only its allocated key-range from key-ranges.md." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $SM_CORE $NIM_M7
bd dep add $SM_CORE $KEY_RANGES

SM_INPUTS=$(bd create "Nim M8 (cluster 2/5): typed inputs (bool/number/trigger)" \
  -d "Reservation: runtime-nim/src/statemachine/**. Chained after SM_CORE. Typed inputs driving the machine." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $SM_INPUTS $SM_CORE

SM_TRANSITIONS=$(bd create "Nim M8 (cluster 3/5): transitions + conditions" \
  -d "Reservation: runtime-nim/src/statemachine/**. Chained after SM_INPUTS. Transition graph + condition evaluation." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $SM_TRANSITIONS $SM_INPUTS

SM_LISTENERS=$(bd create "Nim M8 (cluster 4/5): listeners" \
  -d "Reservation: runtime-nim/src/statemachine/**. Chained after SM_TRANSITIONS. Listener events/callbacks." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $SM_LISTENERS $SM_TRANSITIONS

SM_BLEND=$(bd create "Nim M8 (cluster 5/5): blend states" \
  -d "Reservation: runtime-nim/src/statemachine/**. Chained after SM_LISTENERS. Blend states; closes the M8 cluster." \
  -p 0 -l nim-runtime -t feature --silent)
bd dep add $SM_BLEND $SM_LISTENERS

ASSET_M8=$(bd create "Author shared M8 conformance asset (state machine + input script) in conformance/" \
  -d "Owned shared asset: state machine rig + (time,inputs) script exercising transitions/listeners/blend states. CONTENDED: conformance/**." \
  -p 1 -l conformance -t task --silent)
bd dep add $ASSET_M8 $SM_BLEND

GOLDEN_M8=$(bd create "Generate + commit M8 numeric golden vectors (poses under input-driven state machine)" \
  -d "Numeric Dart gate (abs<=1e-4): per-bone transforms + per-slot color sampled while driving the state machine via the committed input script. Depends on HARNESS_CORE (--state-machine driving)." \
  -p 0 -l conformance -t task --silent)
bd dep add $GOLDEN_M8 $HARNESS_CORE
bd dep add $GOLDEN_M8 $SM_BLEND
bd dep add $GOLDEN_M8 $ASSET_M8

IMG_GOLDEN_M8=$(bd create "Image golden (Nim-only) for M8 state-driven frames, gated on pixie rasterizer" \
  -d "Additional Nim-only image-diff regression. Never a Dart edge." \
  -p 2 -l conformance -t task --silent)
bd dep add $IMG_GOLDEN_M8 $PIXIE_RASTER
bd dep add $IMG_GOLDEN_M8 $ASSET_M8

DART_M8=$(bd create "Dart M8: state machine (layers/inputs/transitions/listeners/blend) (gated on GOLDEN_M8)" \
  -d "Reservation: runtime-dart/lib/**. Identical transition/condition/listener/blend semantics. Edge is GOLDEN_M8." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_M8 $GOLDEN_M8
bd dep add $DART_M8 $DART_M7

# ============================================================================
# Phase M9: CLI tooling (Nim-only — NO Dart counterpart)
# atlas packer, auto-weights, importers (design-spike-first); Spine = BLOCKED
# ============================================================================

ATLAS_PACKER=$(bd create "Nim M9: atlas packer CLI subcommand" \
  -d "Reservation: cli/** (tooling, off critical path). Atlas packer using pixie image I/O; emits atlas pages + region metadata. Separate from HARNESS_CORE." \
  -p 1 -l cli -t feature --silent)
bd dep add $ATLAS_PACKER $HARNESS_CORE
bd dep add $ATLAS_PACKER $NIM_M2

AUTO_WEIGHTS=$(bd create "Nim M9: auto-weights CLI subcommand" \
  -d "Reservation: cli/** (tooling). Heat/bone-distance auto-weighting for meshes from textbook math (clean-room). Emits weighted vertex bind data." \
  -p 1 -l cli -t feature --silent)
bd dep add $AUTO_WEIGHTS $HARNESS_CORE
bd dep add $AUTO_WEIGHTS $NIM_M4_SKIN

IMPORT_SPIKE_DB=$(bd create "Design spike: DragonBones importer (skew->(rotation,shear) decomposition)" \
  -d "Reservation: docs/ + cli/. Design-spike FIRST per spec §9. Work out the skew->(rotation,shear) decomposition mapping DragonBones _ske.json to the bony model. No copying of DragonBones source. Output: design note gating the importer impl." \
  -p 1 -l cli -t task --silent)
bd dep add $IMPORT_SPIKE_DB $HARNESS_CORE
bd dep add $IMPORT_SPIKE_DB $CLEANROOM

IMPORT_DB=$(bd create "Nim M9: DragonBones (_ske.json) importer" \
  -d "Reservation: cli/** (tooling). Implements the importable subset per the design spike. Maps to the bony model; round-trips through json<->bnb." \
  -p 1 -l cli -t feature --silent)
bd dep add $IMPORT_DB $IMPORT_SPIKE_DB

IMPORT_SPIKE_LOTTIE=$(bd create "Design spike: Lottie importer (importable subset of a skeleton-less model)" \
  -d "Reservation: docs/ + cli/. Design-spike FIRST per spec §9. Define the importable subset of Lottie's skeleton-less model into bony. No copying of source. Output: design note gating the importer impl." \
  -p 1 -l cli -t task --silent)
bd dep add $IMPORT_SPIKE_LOTTIE $HARNESS_CORE
bd dep add $IMPORT_SPIKE_LOTTIE $CLEANROOM

IMPORT_LOTTIE=$(bd create "Nim M9: Lottie importer (defined subset)" \
  -d "Reservation: cli/** (tooling). Implements the defined importable subset per the design spike." \
  -p 1 -l cli -t feature --silent)
bd dep add $IMPORT_LOTTIE $IMPORT_SPIKE_LOTTIE

IMPORT_SPINE_BLOCKED=$(bd create "[BLOCKED] Spine importer — flagged for human/legal review before any work" \
  -d "Captured, NOT silently dropped (spec §9). BLOCKED pending human/legal review: Spine's format/runtime carry licensing constraints that must clear before clean-room importer work begins. Do NOT fetch Spine source. No implementation until unblocked by a human." \
  -p 3 -l cli -t task --silent)
bd dep add $IMPORT_SPINE_BLOCKED $CLEANROOM

# ============================================================================
# Phase M10: conformance consolidation + second-runtime validation + docs
# + C# design notes + perf-harness landed
# ============================================================================

ROUNDTRIP_BOTH=$(bd create "Conformance: round-trip suite both directions consolidated (json<->bnb)" \
  -d "Reservation: conformance/**. Consolidate json->bnb->json idempotency and bnb->json->bnb byte-stability test suites over all milestone assets. Both directions get a bead + a CI gate (gates already attached at M6)." \
  -p 1 -l conformance -t task --silent)
bd dep add $ROUNDTRIP_BOTH $BNB_ROUNDTRIP
bd dep add $ROUNDTRIP_BOTH $GOLDEN_M8

CONFORMANCE_CONSOLIDATE=$(bd create "Nim M10: conformance suite consolidation (numeric + image goldens + round-trip + fwd-compat + fuzz)" \
  -d "Reservation: conformance/**. Consolidate the full suite: numeric goldens per milestone (Dart gate), reference-only image goldens (Nim-only), round-trip both directions, forward-compat skip, fuzz. The suite is the cross-runtime contract." \
  -p 1 -l conformance -t task --silent)
bd dep add $CONFORMANCE_CONSOLIDATE $GOLDEN_M8
bd dep add $CONFORMANCE_CONSOLIDATE $ROUNDTRIP_BOTH
bd dep add $CONFORMANCE_CONSOLIDATE $CI_FWDCOMPAT_GATE
bd dep add $CONFORMANCE_CONSOLIDATE $CI_FUZZ_GATE
bd dep add $CONFORMANCE_CONSOLIDATE $IMG_GOLDEN_M8

DART_FULL_SUITE=$(bd create "Dart M10: full conformance-suite pass (second-runtime validation)" \
  -d "Reservation: runtime-dart/**. Dart passes the ENTIRE shared conformance suite (all numeric goldens M1-M8 abs<=1e-4, round-trip, forward-compat skip, fuzz). Final second-runtime validation gate." \
  -p 1 -l dart-runtime -t feature --silent)
bd dep add $DART_FULL_SUITE $DART_M8
bd dep add $DART_FULL_SUITE $CONFORMANCE_CONSOLIDATE

DOCS_M10=$(bd create "Docs M10: native docs + QA checklist (manual naylib visual checks)" \
  -d "Reservation: docs/**. Consolidate native docs, architecture/determinism contract index, and a QA checklist for manual renderer/visual checks (naylib). References registry/key-ranges.md." \
  -p 1 -l docs -t task --silent)
bd dep add $DOCS_M10 $CONFORMANCE_CONSOLIDATE
bd dep add $DOCS_M10 $NAYLIB_ADAPTER

CSHARP_DESIGN=$(bd create "Deferred C# design notes (Unity/Godot embedder seams; no v1 implementation)" \
  -d "Reservation: docs/**. Design-only: managed .NET core runtime with adapter seams for Unity and Godot embedders; how the same codegen later targets C#; conformance-vector compatibility checks. NO implementation in v1." \
  -p 2 -l csharp-design -t task --silent)
bd dep add $CSHARP_DESIGN $CONFORMANCE_CONSOLIDATE

PERF_HARNESS_LAND=$(bd create "Land perf-harness scaffold by M10 (non-gating) + record deferred budgets" \
  -d "Reservation: runtime-nim/ + docs/. Ensure the non-gating perf-harness scaffold is wired against the SkeletonData/SkeletonInstance split and O(bones+constraints) cache by M10. Budgets remain DEFERRED; do not gate." \
  -p 2 -l nim-runtime -t task --silent)
bd dep add $PERF_HARNESS_LAND $PERF_HARNESS
bd dep add $PERF_HARNESS_LAND $ORDERED_CACHE

echo ""
echo "Bead graph created! View with:"
echo "  bd ready              # List unblocked tasks"
echo "  bd dep cycles         # Verify no cycles"
echo "  bd list               # Count beads"
