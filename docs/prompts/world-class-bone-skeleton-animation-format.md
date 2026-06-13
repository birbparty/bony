# Project Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown. This task graph will be executed by AI agents working in parallel, coordinated through MCP Agent Mail with file reservations to prevent conflicts.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary setup, implementation, testing, and documentation tasks. Go beyond the basics - consider edge cases, error handling, security considerations, and integration points. Each task should be specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

## Project Information

### Links to Relevant Documentation
- **Core functional spec (binding):** `/Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md` — the clean-room specification for the `bony` 2D skeletal + deform animation format, reference runtime, algorithms, and conformance suite. This document defines *what* to build and *how the data is shaped*. Sections: §1 clean-room mandate (binding), §2 prior-art capability matrix, §3 goals/non-goals, §4 conventions, §5 conceptual data model, §6 file format (`.bony` JSON / `.bnb` binary), §7 runtime architecture, §8 algorithms, §9 tooling, §10 conformance/testing, §11 versioning, §12 milestones M1–M10, §13 open decisions (defaults locked), §14 naming, §15 references.
- **Style/structure reference (non-binding):** `/Users/punk1290/Downloads/viewy-v2-native-backends-plan.md` — a phased Nim project plan from the same ecosystem. Use it as a model for *how to structure phases, acceptance criteria, and "conformance suite as the contract"* discipline. Not part of this project's scope.
- treeform Nim ecosystem libraries referenced by the spec (§9.1): `vmath`, `chroma`, `pixie`, `jsony`.

### Project Description
Build a world-class, clean-room 2D **bone skeleton + deform animation format** (`bony`) with first-class language runtimes shipped out of the box. The format is a superset of the practical skeletal model (Spine/DragonBones class: bone hierarchy, slots, weighted meshes/LBS, skins, IK/transform/path/physics constraints) **plus first-class deform** (Live2D-class warp/rotation deformers and parameter-driven keyform blending) **plus interactivity** (Rive-class state machine with typed inputs, transitions, listeners). It ships two lossless serializations — a readable `.bony` JSON interchange form and a compact, forward-compatible, type-keyed `.bnb` binary — and a deterministic, renderer-agnostic runtime.

**Runtimes:**
- **Nim** is the **reference runtime** and defines bit-for-bit conformance (treeform stack). It also hosts the headless CLI (`bony play …`), the software reference rasterizer, the atlas packer, auto-weights, importers, and the golden-vector tooling.
- **Dart/Flutter** is a **first-class v1 runtime** that must pass the shared conformance suite, with a Flutter rendering integration (`CustomPainter`-style).
- **C#** is **deferred to a later phase** but the format and conformance design must keep it cleanly addable; its intended embedders are **Unity and Godot**.

Clean-room engineering is **binding** (spec §1): implement only from the functional descriptions and public/textbook animation math; invent fresh identifiers, key names, type tags, binary opcodes, and chunk ordering; never copy or transliterate Spine/Live2D/DragonBones/Rive source or reproduce another format's byte/key layout field-for-field. Pick documented defaults where choices are open (spec §13) and move on.

### Technical Stack
- **Format / spec (language-neutral):** `.bony` UTF-8 JSON interchange + `.bnb` little-endian binary (4-byte `BONY` fingerprint, packed `major<<16|minor` version, flags, Table-of-Contents mapping every property key → backing primitive type for skip-ability, optional interned string table, flat type-keyed object stream terminated by property key 0, optional embedded atlas). A versioned **`bony.schema.json`** JSON Schema is the single source of truth for keys; **default tables live in code** and drive default-omission. An **append-only type/property key registry** with a small **code-gen step** keeps JSON and binary in lockstep.
- **Nim reference runtime + tooling:** treeform stack — `vmath` (2D/affine math), `chroma` (color), `pixie` (software rasterizer + atlas image I/O), `jsony` (`.bony` JSON), hand-rolled LEB128 / `flatty`/`binny`-style helpers for `.bnb`. Per the global Nim rule, the repo gets a root `nim.cfg` with `--path:"src"` matching the `.nimble` `srcDir`. Packaged as a Nimble package.
  - **Primary real-time renderer: `naylib`** (Nim raylib bindings) is the prioritized rendering target for the Nim runtime. The runtime stays renderer-agnostic (emits the backend-neutral `DrawBatch` command list per spec §7.6); naylib is the first-class adapter that consumes those batches. Confirm naylib is permissively licensed (zlib/MIT) before it becomes a hard dependency (license-scan bead).
  - **A `DrawBatch→raylib semantics` contract bead precedes the naylib adapter** (the adapter depends on it): a blend-mode table including per-page **premultiplied alpha** (raylib defaults to straight-alpha `BLEND_ALPHA`; PMA pages need `BLEND_ALPHA_PREMULTIPLY` or a custom mode), the **2-color tint-black shader** contract (raylib has no built-in two-color tint — a custom shader is required), and the clip strategy (v1 convex clipping is geometry-side per §8.9, so the adapter consumes pre-clipped triangles; document stencil-vs-geometry).
  - **naylib done-criterion under Linux-only, GPU-less CI** (so "prioritized" is measurable, not unverifiable): the adapter bead is done when it (a) compiles+links against naylib on Linux, (b) passes a **headless smoke test** that builds `DrawBatch`es and asserts the adapter issues the mapped raylib draw calls without crashing (offscreen / `xvfb` or a mock raylib seam), and (c) has a documented manual visual-check step. naylib output is **never** the conformance source — numeric goldens are.
  - **`pixie` software rasterizer is retained but scoped to conformance:** it backs the headless image-diff goldens (deterministic, reference-runtime-only — see determinism contracts), **not** the shipped real-time path.
- **Dart/Flutter runtime:** pure Dart package (model + loaders for `.bony` and `.bnb` + runtime tick + render-command emission) plus a Flutter integration layer (`CustomPainter`/`RenderObject`). Packaged for pub.dev.
- **C# runtime (deferred phase, design-for now):** target .NET, managed core runtime with adapter seams for **Unity** and **Godot** embedders; no implementation in v1 beyond conformance-vector compatibility checks and design notes.
- **CLI + conformance harness:** Nim. `bony` CLI subcommands: `json→bnb`, `bnb→json`, `play asset.bnb --anim walk --t 1.5 --out frame.png`, `--state-machine` driving with input scripts, atlas packer, auto-weights, importers (DragonBones `_ske.json`, Lottie). Golden vectors = `.bony`/`.bnb` assets + `(time, inputs)` sample scripts + expected per-bone world transforms, per-slot color/attachment, emitted f32 vertex buffers (tolerance `abs ≤ 1e-4`), plus image-diff PNG goldens.

### Specific Requirements
- **License:** MIT for the format spec and all runtimes (consistent with the clean-room mandate). Add `LICENSE` and clean-room provenance notes; no GPL/CC-encumbered or proprietary-derived code.
- **Determinism (hard requirement) — defined per artifact (do NOT say "bit-for-bit within a tolerance"; those are different bars):**
  - *Numeric pose outputs* (per-bone world transforms, per-slot color, emitted f32 vertex/index buffers): the cross-runtime contract is **agreement within `abs ≤ 1e-4`**, NOT bit-identity. This is the bar the Dart runtime is gated against.
  - *`bnb → json → bnb`*: **byte-stable after canonicalization** (true bit-identity, single runtime).
  - *`json → bnb → json`*: **idempotent modulo default omission**, given documented JSON canonicalization rules (see coordination section).
  - *Image-diff PNG goldens*: **reference-runtime-only regression tests**, NOT a cross-runtime gate (two rasterizers cannot match pixels; the cross-runtime gate is the numeric goldens above). Pin a concrete metric + threshold (e.g. max per-channel delta ≤ N, or SSIM ≥ X) rather than "perceptual diff".
  - Honor the locked defaults: fixed **16-sample** Bézier solve table (§8.3, §13), fixed-substep physics accumulator (e.g. 1/60 s, §8.7), deterministic ordered update cache (O(bones + constraints), §7.2), linear-blend skinning in v1 (dual-quat hook only, §13), convex clipping in v1 / concave behind a flag (§8.9, §13), string interning on by default (§13). The Nim reference runtime is authoritative and **produces the committed golden vectors**; the conformance suite is the cross-runtime contract (see coordination section for how Dart is gated).
- **Performance budgets:** **open / deferred** for now — no hard numbers in v1. Keep the immutable-`SkeletonData` vs per-instance-`SkeletonInstance` split (§7.1) and the O(bones+constraints) update cache so budgets can be set and improved once there is something to measure. Add a perf-harness scaffold but do not gate on it.
- **CI:** **Linux only. No multi-platform matrix.** CI runs the Nim reference runtime build + tests and the Dart runtime build + tests on Linux, and executes the conformance suite (golden vectors + round-trip + forward-compat skip tests + fuzzing) on Linux. (macOS/Windows runners explicitly out of scope.)
- **Versioning / forward-compat:** header `major.minor`; same major must remain readable (unknown objects/properties skipped via ToC); append-only key registry with reserved terminator key 0; new attachment/constraint/timeline/state-machine kinds added as new type keys. Forward-compat skip behavior is tested.
- **Scope discipline:** v1 deliverable = format + Nim reference runtime + Dart runtime + headless CLI + conformance suite (+ C# design notes). Out of scope for v1: editor UI, 3D, byte/feature compatibility with any existing format, data binding (v2), vector-path renderer tier (defer to tier 2 behind a flag), C# implementation. Follow the spec milestone order M1→M10; don't gold-plate ahead of a milestone.

---

## Build Coordination, Sequencing & Determinism Contracts (binding for the task graph)

These resolve gaps the binding spec leaves implicit. The generated bead graph **must** encode them — an autonomous multi-agent build cannot be allowed to guess here. Where a contract needs a written artifact, make it its own deliverable bead before the implementation it gates.

### Repo layout (decided: monorepo)
Single repo. Top-level directories are the file-reservation boundaries for parallel agents:
```
spec/            # bony.schema.json, key registry source, default-table source, written contracts (CONTENDED — serialize edits)
registry/        # append-only type/property-key registry (declarative source of truth for the binary) (CONTENDED)
codegen/         # generator that emits Nim + Dart encode/decode boilerplate from registry/ + spec/
runtime-nim/     # Nim reference runtime + software rasterizer
runtime-dart/    # pure Dart runtime + Flutter integration
cli/             # Nim CLI (harness-core + tooling) — may live under runtime-nim/
conformance/     # SHARED: golden vectors, example/test assets, (time,inputs) scripts, image goldens (CONTENDED)
docs/            # native docs, CLEANROOM.md, PROVENANCE, float-math contract, qa-checklist
```
Reservation rule: `spec/`, `registry/`, and `conformance/` are **contended shared surfaces** — only one bead may edit each at a time; never parallelize edits to them (see source-of-truth ownership below).

### Source-of-truth ownership (resolve the double-assignment)
- The **`registry/` key table is the single canonical declarative source** for the binary wire (every object type + property → stable `varuint` key + backing primitive type; append-only; key 0 reserved as terminator forever).
- `spec/bony.schema.json` is canonical for **JSON structure/validation** and is **generated from / cross-checked against** the registry + default tables — it is NOT an independent second source of truth.
- `codegen/` emits **both** Nim and Dart encode/decode from `registry/` (Dart is NOT hand-written against the registry — it is generated in lockstep, the same as Nim). C# generation is a later target of the same codegen.
- Adding any object/property/timeline/constraint kind = **one bead** that edits `registry/` + default tables + re-runs codegen, owned by that feature area.
- **Reserved key ranges are a committed artifact, not a sentence.** The REGISTRY bead emits `registry/key-ranges.md` mapping each milestone → a reserved `varuint` band *before any milestone touches `registry/`*. Every later registry-editing bead's description must cite "use only your allocated range from `key-ranges.md`." Note: the bead graph's `bd dep` edges do NOT serialize concurrent `registry/` edits — that is enforced at execution time by MCP Agent Mail file reservation on `registry/**`. The key-range map is what lets M5/M7/M8 proceed in parallel *without* a serializing dep chain; state this so the generator doesn't assume a dep edge exists where there is only a reservation + a range allocation.

### Nim → Dart sequencing (the golden-vector dependency edge)
- Dart work for a feature area depends on the **Nim reference for that area being closed AND its golden vectors committed** — not merely started. The dependency edge in the bead graph is the *committed golden-vector artifact*, not the Nim implementation task. This prevents Dart from chasing an unfrozen reference and silently drifting inside the 1e-4 band.
- **Golden-edge rule (generator must apply uniformly):** *every* milestone emits a **numeric** golden (per-bone world transforms, per-slot color/attachment, emitted vertex+index buffers) — that numeric golden is the Dart gate. **Image-diff PNG goldens are an additional Nim-only artifact and are NEVER a Dart dependency edge.** So even M2 (rendering) has a numeric golden (world transforms + region quad vertex buffers) that Dart M2 gates on; Dart never gates on an image golden.
- **Numeric vs image golden-gen are split** to avoid an ordering bug: **numeric `golden-gen` has no rasterizer dependency and exists at M1** (it is part of harness-core, built before M2). **Image `golden-gen` depends on the M2 software rasterizer.** Every `GOLDEN_Mx` (numeric) bead therefore depends on the `HARNESS_CORE` bead, not on M2.
- **Per-milestone Dart counterpart (avoid over/under-generation):** not every Nim milestone has a 1:1 Dart bead. M2 → Dart consumes the same numeric goldens; the Flutter `CustomPainter` render path is its own Dart bead; **there is no Dart-naylib bead**. M6 → Dart `.bnb` loader gated on goldens. **M9 (CLI tooling: atlas/auto-weights/importers) → no Dart bead (Nim-only).** State the Dart counterpart (or its absence) per milestone in the enumeration below.
- Golden vectors and example/test assets ("hand-written rig" M1, "weighted/deforming/clipped character" M4) are **owned shared artifacts** living in `conformance/`, created by explicit Nim/CLI-track beads, consumed unchanged by both runtimes. They are not re-derived per runtime.

### CLI split (harness vs tooling)
- **`HARNESS_CORE` bead** (early, gates ALL golden generation): `json↔bnb`, `play … --t … --out frame.png`, `--state-machine` input-script driving, and **numeric `golden-gen`**. Built at M1 (depends on `NIM_MODEL` + codegen), *before* M2. **Every `GOLDEN_Mx` bead depends on `HARNESS_CORE`** — without this edge the example's M1 golden would be produced by a tool that doesn't exist yet (a real defect to avoid).
- **tooling** (M9, off critical path): atlas packer, auto-weights, DragonBones/Lottie importers. Do not let a bead treat "the CLI" as one unit.

### Determinism contracts that need written specs (own beads, early)
- **Float-math contract** (M1, before committing conventions): Dart has **no f32 arithmetic** — all numbers are IEEE-754 doubles; f32 exists only as `Float32List` storage with rounding on store. Nim has native f32/f64 and FP-flag sensitivity. The contract must pin: f32-vs-f64 for storage vs intermediate compute in each runtime, accumulation order for skinning sums and physics integration, and that transcendentals (`sin/cos/atan2/pow`) are not bit-identical across libm/Dart VM (the `abs ≤ 1e-4` tolerance is the mitigation — verify IK/path/Bézier accumulate under it). Start M1 with a **determinism feasibility spike** bead.
- **Transform composition algorithm** (§8.1): write the from-first-principles decomposition for inherit-rotation/scale/reflection factoring and the five `transformMode` combinations (the spec gives no formulas, and this is exactly what clean-room forbids copying). Document once in `spec/`, share across runtimes, and add a golden per `transformMode`.
- **ToC skip semantics for array-of-struct** (§6.2 format hole): the spec's ToC backing types ("array-of-<prim>") cannot describe array-of-struct properties (weighted vertices = `n×(boneIndex,bindX,bindY,weight)`, keyframe arrays), so an old reader cannot compute skip length — forward-compat skip tests are unbuildable as written. Resolve early: either length-prefix every value (byte count, so skipping never needs type knowledge) or define a richer backing-type descriptor. This is a design bead gating M6.
- **Constraint total-order** (§5.1/§7.2): IK/transform/path/physics live in four arrays sharing a global `order`; define and test a total ordering for ties (e.g. `order`, then fixed array-kind priority, then array index) as a documented invariant — ties otherwise produce nondeterministic poses.
- **Physics integrator contract** (§8.7): pin the integrator (semi-implicit vs explicit Euler — they diverge), leftover-time accumulator policy (carry remainder vs clamp), max-substeps clamp, deterministic initial velocity/position seeding, and `reset` semantics.
- **JSON canonicalization rules** (§6/§10): key sort order, float formatting, angle (degree↔radian) precision — required before the `json→bnb→json` idempotency conformance bead.
- **Binary canonicalization rules** (§6.2/§10): the sibling contract for the **`bnb→json→bnb` byte-stability** bar. Pin string-interning insertion order (first-seen vs sorted), object emission order (the spec's "canonical order" is undocumented — write it down), ToC property ordering, and deterministic default-omission. Required before the `bnb→json→bnb` conformance/CI gate. Both round-trip directions get a bead and a CI gate.
- **`header.hash` / `bounds`** (§5.1) — **decided defaults (do not re-open):** `bounds` is **nonessential/optional**, recomputed on load, omitted from byte-stability and not a Dart conformance target. `hash` is a **defined function over the canonical `.bnb` byte stream** (excluding the hash field itself) — cross-runtime stable — OR omitted entirely; pick "defined function" unless it complicates byte-stability, then drop it. Record the choice.
- **Load-time validation pass** (§10 fuzzing vs §6.2 forward-compat): forward-compat says "skip unknown gracefully"; fuzzing says "reject malformed hard" — they meet in the same loader. Own a documented validation deliverable that rejects cyclic references (bone parents, deformer tree, skin-bone refs — index loops in the binary, ordering violations in JSON), truncated/bad varints, and length mismatches, while still skipping *unknown-but-well-formed* objects/properties. Define the acceptance bar per runtime (Nim: typed error, no panic/segfault, bounded time; Dart: typed exception, no hang).

### CI (Linux-only, no matrix) — split, not one monolithic bead
Do NOT emit a single CI bead gated only on codegen — several gates can't run until later milestones, so one bead is both an ordering lie and >750 LOC. Split into:
- **`CI_SCAFFOLD`** (early, gated on codegen): build + test + lint/vet + **schema/registry/default-table in-sync check** + **codegen freshness check** (committed codegen == freshly regenerated — without this an agent can edit the registry, forget to regen, and pass CI, defeating lockstep) + **license/provenance scan** (below).
- **Incremental gate beads**, each attached to the milestone that first makes it runnable: conformance-run gate → M1 numeric goldens; asset-schema-validation → first `conformance/` assets; **`json→bnb→json` idempotency gate** → M6 + JSON-canon contract; **`bnb→json→bnb` byte-stability gate** → M6 + binary-canon contract; forward-compat skip + fuzz gates → M6.

### Clean-room process (operationalized, not a "notes" line)
- `docs/CLEANROOM.md` + `PROVENANCE`: record that implementation derives only from the binding spec + cited public/textbook math; carry the spec §15 reference list with its capability-only-never-source caveats per tool.
- Explicit standing instruction in the build: **agents must not fetch Spine/Live2D/Rive/DragonBones runtime source via web tools while implementing.**
- **Deferred Spine importer**: a *blocked* bead flagged for human/legal review (per spec §9) — captured, not silently dropped. DragonBones/Lottie importers need design-spike beads first (skew→(rotation,shear) decomposition for DragonBones; the importable subset for Lottie's skeleton-less model).
- **License-scan bead**: verify each Nim dep (`vmath`, `chroma`, `pixie`, `jsony`, `flatty`/`binny`) is MIT/Apache before it becomes a hard dependency — verified, not assumed; no GPL/CC/proprietary-derived code.

### Task-graph shaping notes
- **Cluster ≠ one big bead, and ≠ parallel beads.** A "single-owner multi-bead cluster" is **multiple ≤750-LOC beads under one owner-label, chained by sequential `bd dep` edges**, all reserving the same file subtree so they never run concurrently. This reconciles the ≤750-LOC granularity rule with the no-collision intent. Apply to: the state machine (§7.5), the constraint solver set (§8.2/8.5/8.6/8.7), and the binary ToC+stream (§6.2). Example for M5: `IK_SOLVER → TRANSFORM_CON → PATH_CON → PHYSICS_CON → ORDERED_CACHE`, each `-l nim-runtime`, each <750 LOC, chained so no two run at once on `runtime-nim/src/constraints/**`.
- **Label convention:** use `-l` (comma-separated for multiple, e.g. `-l nim-runtime,core`) consistently — NOT `--label` in some beads and `-l` in others. Prefer one primary area label per bead from the taxonomy.
- **Priority policy (keyed to label, so the tail doesn't flatten to p2):** shared contracts + Nim reference on the critical path = `-p 0`; conformance goldens that gate Dart = `-p 0`; Dart runtime, CLI tooling, docs, perf-harness = `-p 1`/`-p 2`; deferred C# design + blocked Spine importer = `-p 2`/`-p 3`.
- Add a **non-gating** perf-harness scaffold bead early so the immutable-`SkeletonData` / per-instance-`SkeletonInstance` split (§7.1) and the O(bones+constraints) update cache get a structural home (budgets are deferred; do not gate on them).
- Decide and record versioning relationship: format on-disk `major.minor` (§11) vs Nim package vs Dart package vs the spec document — and what v1 ships as.

### Per-milestone bead enumeration (EXPAND THIS — do not leave M2–M10 as a comment)
The example script below fully wires Phase 0 + M1 and then collapses M2–M10 into a comment. **You must expand every milestone into real beads** following this pattern. For each milestone: Nim impl bead(s) (clusters where noted) → shared `conformance/` asset bead → numeric `GOLDEN_Mx` bead (deps `HARNESS_CORE`) → Dart bead gated on `GOLDEN_Mx`. Image goldens (M2+) are extra Nim-only beads. The minimum expected beads:

| Milestone | Nim deliverable | Cluster? | Dart counterpart | Notes |
|---|---|---|---|---|
| **M1** | SkeletonData model + `.bony` JSON I/O + default tables | no | Dart model + `.bony` loader (gated on GOLDEN_M1) | also: HARNESS_CORE, float-math spike, ASSET_RIG |
| **M2** | world transforms + region attachments + draw order; **naylib renderer adapter**; pixie software rasterizer | no | Dart numeric gate + Flutter `CustomPainter` render bead; **NO Dart-naylib** | first image goldens here; transform-math contract golden per transformMode |
| **M3** | bone/slot timelines, Bézier easing (16-sample), multi-track mixer + crossfade, events | no | Dart anims/mixer (gated on GOLDEN_M3) | |
| **M4** | meshes, LBS skinning, deform timelines, clipping (convex), sequences/flipbook | mesh+skinning may cluster | Dart meshes/skinning/deform (gated on GOLDEN_M4) | "weighted/deforming/clipped character" asset |
| **M5** | IK (1/2-bone+chain), transform, path, physics constraints + ordered update cache | **YES** (chain) | Dart constraints (gated on GOLDEN_M5) | constraint total-order + physics-integrator contracts precede |
| **M6** | `.bnb` binary: ToC, string interning, type-keyed object stream, round-trip tools | **YES** (chain) | Dart `.bnb` loader (gated on GOLDEN_M6) | ToC-skip + binary-canon + JSON-canon contracts precede; round-trip + forward-compat + fuzz CI gates attach here |
| **M7** | warp/rotation deformers, parameter axes, keyform multilinear blend, parameter timelines | no | Dart deformers/parameters (gated on GOLDEN_M7) | |
| **M8** | state machine: layers, typed inputs, transitions/conditions, listeners, blend states | **YES** (chain) | Dart state machine (gated on GOLDEN_M8) | |
| **M9** | CLI tooling: atlas packer, auto-weights, DragonBones/Lottie importers | no | **none (Nim-only)** | importers = design-spike-first; **Spine importer = BLOCKED bead flagged for legal** |
| **M10** | conformance suite consolidation + second-runtime validation + docs | no | Dart full-suite pass | C# design-notes bead (`-l csharp-design`); perf-harness scaffold lands by here |

---

## Your Task

Analyze this project and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

---

<critical_constraint>
Your ONLY output is a bash shell script. Do NOT use `bd add` — the correct command to create a bead is `bd create`. Use `bd dep add` for dependencies. Do not implement anything yourself.
</critical_constraint>

## Output Format

Generate a shell script that creates the full task graph. The script should:

1. **Initialize Beads** (if not already initialized)
2. **Create all beads** with appropriate priorities
3. **Establish dependencies** between beads
4. **Add labels** for phase grouping

### Example Output

This is an illustrative shape for THIS project — note the monorepo setup, the shared-contract beads that gate implementation, and the **golden-vector dependency edge from Nim to Dart**. Do not emit web-app beads (no Vite/auth/API-client/Tailwind).

```bash
#!/bin/bash
# Project: bony — 2D skeletal + deform animation format
# Generated: 2026-06-13

set -e

if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating project beads..."

# ========================================
# Phase 0: Repo, contracts & shared sources of truth
# ========================================

REPO=$(bd create "Scaffold monorepo layout (spec/ registry/ codegen/ runtime-nim/ runtime-dart/ cli/ conformance/ docs/)" \
  -d "Create top-level dirs per the coordination section. Add MIT LICENSE, root nim.cfg with --path:\"src\" matching .nimble srcDir, Nimble + pub.dev package skeletons. Reservation boundaries: one dir per runtime; spec/ registry/ conformance/ are contended." \
  -p 0 -l setup --silent)

CLEANROOM=$(bd create "Write docs/CLEANROOM.md + PROVENANCE and the no-fetch-source build rule" \
  -d "Record clean-room mandate (spec §1), §15 capability-only reference list, and the standing instruction that agents must not fetch Spine/Live2D/Rive/DragonBones runtime source while implementing." \
  -p 0 -l docs --silent)
bd dep add $CLEANROOM $REPO

REGISTRY=$(bd create "Define append-only type/property-key registry as the canonical binary source of truth" \
  -d "registry/ is the single declarative source for the .bnb wire (object/property -> stable varuint key + backing type; key 0 reserved terminator forever). Allocate reserved key ranges per milestone up front. bony.schema.json is generated/cross-checked from this, NOT independent." \
  -p 0 -l core --silent)
bd dep add $REGISTRY $REPO

TOC_SKIP=$(bd create "Resolve ToC skip semantics for array-of-struct (length-prefix vs richer descriptor)" \
  -d "Spec §6.2 'array-of-<prim>' cannot describe weighted-vertex / keyframe array-of-struct; an old reader can't compute skip length. Decide length-prefixed values or extended backing-type descriptor. Gates M6." \
  -p 0 -l core --silent)
bd dep add $TOC_SKIP $REGISTRY

CODEGEN=$(bd create "Build codegen that emits Nim + Dart encode/decode from registry + default tables" \
  -d "Dart is generated in lockstep, NOT hand-written. Emit both runtimes' boilerplate + the JSON Schema. C# is a later target of the same generator." \
  -p 0 -l core --silent)
bd dep add $CODEGEN $REGISTRY
bd dep add $CODEGEN $TOC_SKIP

FLOAT_CONTRACT=$(bd create "Determinism feasibility spike + write the float-math contract" \
  -d "Dart has no f32 arithmetic (doubles only; f32 via Float32List storage). Pin f32/f64 storage-vs-compute per runtime, accumulation order (skinning sums, physics), transcendental tolerance. Verify IK/path/Bezier stay within abs<=1e-4. Output: docs/float-math-contract.md." \
  -p 0 -l core --silent)
bd dep add $FLOAT_CONTRACT $REPO

XFORM_MATH=$(bd create "Specify transform composition for inherit/reflection + 5 transformModes (§8.1)" \
  -d "From-first-principles decomposition (clean-room: no copying). One shared spec doc + a golden per transformMode." \
  -p 1 -l core --silent)
bd dep add $XFORM_MATH $FLOAT_CONTRACT

CI=$(bd create "Linux-only CI: build+test+conformance, schema/registry in-sync, codegen-freshness, json->bnb->json idempotency, asset-schema-validation, license scan" \
  -d "No platform matrix. Codegen-freshness gate (committed == regenerated) is mandatory or lockstep is unenforced. License-scan verifies vmath/chroma/pixie/jsony/flatty are MIT/Apache." \
  -p 0 -l deploy --silent)
bd dep add $CI $CODEGEN

# ========================================
# Phase M1 (Nim): Core data model + JSON I/O
# ========================================

NIM_MODEL=$(bd create "Nim: SkeletonData model + default tables + .bony JSON parser/serializer" \
  -d "Reservation: runtime-nim/**. Consume generated boilerplate. Default-omission on serialize, default-apply on load." \
  -p 0 -l nim-runtime --silent)
bd dep add $NIM_MODEL $CODEGEN
bd dep add $NIM_MODEL $FLOAT_CONTRACT

HARNESS_CORE=$(bd create "Nim CLI harness-core: json<->bnb, play, --state-machine, numeric golden-gen" \
  -d "Reservation: cli/**. Built at M1 BEFORE M2 — numeric golden-gen has no rasterizer dependency. Every GOLDEN_Mx bead depends on this. Image golden-gen is a later add-on gated on the M2 software rasterizer." \
  -p 0 -l cli --silent)
bd dep add $HARNESS_CORE $NIM_MODEL

ASSET_RIG=$(bd create "Author shared M1 example rig + (time,inputs) sample script in conformance/" \
  -d "Owned shared asset consumed by both runtimes; do not re-derive per runtime." \
  -p 1 -l conformance --silent)
bd dep add $ASSET_RIG $NIM_MODEL

GOLDEN_M1=$(bd create "Generate + commit M1 numeric golden vectors via 'bony golden-gen'" \
  -d "Numeric goldens (transforms/colors/vertex+index buffers, abs<=1e-4). This committed artifact is the dependency edge Dart M1 gates on." \
  -p 0 -l conformance --silent)
bd dep add $GOLDEN_M1 $HARNESS_CORE   # <-- produced BY the CLI, so it must exist first
bd dep add $GOLDEN_M1 $NIM_MODEL
bd dep add $GOLDEN_M1 $ASSET_RIG

# ========================================
# Phase M1 (Dart): gated on committed Nim goldens
# ========================================

DART_M1=$(bd create "Dart: SkeletonData model + .bony loader, gated against committed M1 goldens" \
  -d "Reservation: runtime-dart/**. Uses generated Dart boilerplate. Conformance runner consumes the SAME committed conformance/ goldens — does not re-derive them." \
  -p 1 -l dart-runtime --silent)
bd dep add $DART_M1 $GOLDEN_M1   # <-- edge is the golden artifact, not the Nim task

# ... continue M2..M10 for Nim (each: implement -> author assets -> golden-gen),
#     then the matching Dart bead gated on that milestone's committed goldens.
#     M2 renderer: PRIORITIZE the naylib (raylib) adapter consuming the DrawBatch
#     command list (runtime-nim/src/render/naylib*) as the real-time target; keep the
#     pixie software rasterizer (runtime-nim/src/render/software*) for conformance image
#     goldens only. Single-owner clusters: state machine (§7.5), constraint set
#     (§8.2/8.5/8.6/8.7), binary ToC+stream (§6.2). CLI harness-core early (M2), tooling
#     (atlas/auto-weights/importers) at M9. DragonBones/Lottie importers = design-spike-
#     first; Spine importer = BLOCKED bead flagged for legal. Non-gating perf-harness early.

echo ""
echo "Bead graph created! View with:"
echo "  bd ready              # List unblocked tasks"
```

---

## Bead Creation Guidelines

### Priority Levels
- `-p 0` = Critical (blocking other work)
- `-p 1` = High (important but not blocking)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (nice to have)

### Labels (Phase Grouping)
Use `--label` to group beads by area (use THESE, not web-app labels):
- `setup` - Repo/monorepo scaffolding, packaging skeletons
- `core` - Shared contracts: registry, codegen, schema, default tables, format design
- `nim-runtime` - Nim reference runtime + naylib renderer + software rasterizer
- `dart-runtime` - Dart runtime + Flutter integration
- `cli` - Headless CLI (harness-core + tooling subcommands)
- `conformance` - Golden vectors, shared test assets, conformance runners
- `docs` - Docs, CLEANROOM/PROVENANCE, written determinism contracts
- `deploy` - Linux CI gates
- `csharp-design` - Deferred C# design notes (no implementation in v1)

### Dependency Rules
1. Never create cycles
2. Every bead should have a clear dependency chain back to setup tasks
3. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
4. Parallel work should share a common ancestor, not depend on each other

### Task Granularity
- Each bead should be completable in **under 750 lines of code**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area

---

## File Reservation Planning

For each major work area, note the file patterns that will need exclusive reservation:

```bash
# Reservation notes for THIS monorepo (add as bead descriptions):
# Shared contracts (CONTENDED — serialize, one bead at a time): registry/**, spec/bony.schema.json, codegen/**
# Nim runtime:        runtime-nim/src/**, runtime-nim/tests/**   (renderer adapter: runtime-nim/src/render/naylib*)
# Nim software raster: runtime-nim/src/render/software*          (pixie; conformance image goldens only)
# Dart runtime:       runtime-dart/lib/**, runtime-dart/test/**  (Flutter integration: runtime-dart/lib/flutter/**)
# CLI:                cli/**                                     (harness-core vs tooling subcommands)
# Conformance (CONTENDED shared): conformance/goldens/**, conformance/assets/**, conformance/scripts/**
# Docs/contracts:     docs/**                                   (CLEANROOM.md, PROVENANCE, float-math-contract.md)
```

This helps agents claim appropriate file surfaces when they start work.

---

## Context Documentation

Place any important context in `docs/` (the monorepo docs root — not `prompts/docs/`) for agents to reference. This includes:
- Architecture decisions and the written determinism contracts (float-math, transform composition, constraint total-order, physics integrator, JSON + binary canonicalization)
- `CLEANROOM.md` / `PROVENANCE` and the clean-room reference notes
- The `registry/key-ranges.md` allocation map (lives under `registry/`, referenced here)
- QA checklist for manual renderer/visual checks (naylib)

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check ready work**: `bd ready` should show initial setup tasks

---

## Completeness Checklist

Ensure your task graph includes (domain-specific for `bony` — NOT web-app items):

- [ ] Monorepo scaffold + MIT LICENSE + Nimble/pub.dev skeletons + root `nim.cfg` (`--path:"src"`)
- [ ] Shared contracts: append-only key registry, codegen (Nim + Dart), JSON Schema generated/checked from registry, default tables
- [ ] Written determinism contracts as deliverables: float-math contract, transform composition (§8.1), constraint total-order, physics integrator, JSON canonicalization, `header.hash`/`bounds`, ToC array-of-struct skip
- [ ] Nim reference runtime per milestone M1→M10 (model, world transforms, animations/curves/mixing, meshes/skinning/deform/clipping/sequences, constraints, binary `.bnb`, deformers/parameters/keyforms, state machine)
- [ ] Nim renderer: **naylib (raylib) as the prioritized real-time renderer adapter** consuming the backend-neutral DrawBatch command list, plus the `pixie` software rasterizer for headless conformance image goldens
- [ ] CLI: harness-core (`json↔bnb`, `play`, `--state-machine`, `golden-gen`) early; tooling (atlas packer, auto-weights, importers) at M9
- [ ] Dart runtime per milestone, each **gated on that milestone's committed Nim golden vectors**; Flutter rendering integration
- [ ] Shared example/test assets + golden-vector generation beads (owned, in `conformance/`)
- [ ] Conformance suite: numeric goldens (`abs ≤ 1e-4`), reference-only image-diff goldens, round-trip idempotency, forward-compat skip tests, fuzzing
- [ ] Clean-room process: CLEANROOM.md/PROVENANCE, no-fetch-source rule, deferred Spine importer as a BLOCKED bead, dependency license-scan
- [ ] Deferred C# design notes (Unity/Godot embedder seams; no v1 implementation)
- [ ] Linux-only CI gates (no matrix): build/test/conformance + codegen-freshness + schema-sync + round-trip + license scan
- [ ] Non-gating perf-harness scaffold (budgets deferred); single-owner clusters for state machine / constraint set / binary stream
- [ ] Clear dependency chains with no cycles; Nim→Dart edges are the committed golden artifacts
