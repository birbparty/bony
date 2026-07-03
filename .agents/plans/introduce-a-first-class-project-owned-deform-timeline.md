# Big Change Planning with Beads

## Agent Instructions

You are an expert software architect creating a comprehensive task breakdown for a change to an existing codebase. This task graph will be executed by AI agents working in parallel, coordinated through MCP Agent Mail with file reservations to prevent conflicts.

<quality_expectations>
Create a thorough, production-ready task graph. Include all necessary analysis, preparation, implementation, testing, and documentation tasks. Go beyond the basics — consider edge cases, error handling, security considerations, backwards compatibility, and integration points. Each task should be specific enough for an agent to execute independently without ambiguity.
</quality_expectations>

<critical_constraint>
You must NOT implement any of the changes yourself. Your ONLY output is a bash shell script containing `bd create` and `bd dep add` commands. Do NOT use `bd add` — the correct command is `bd create`. Do not write code. Do not create files other than the shell script. Do not modify existing files. Read and analyze the codebase, then produce the script.

The script MUST create a single parent **epic** first (`bd create -t epic`) and parent **every** task bead to it via `--parent "$EPIC"`, so the whole change is one trackable rollup. The epic is an organizational rollup only — never make it a blocking dependency (do NOT `bd dep add` to or from the epic; `bd dep add` is for real ordering edges between task beads, and a blocking edge on an epic both excludes it wrongly and inverts `bd dep tree`). Membership is the `--parent` relationship, nothing else.
</critical_constraint>

## Change Information

### Change Type
NEW_FEATURE

(Adds a net-new serialized record class — `deformTimeline` — to the binding format: a binding contract doc, M4 registry keys, canonical-JSON + wire schema, and regenerated codec artifacts. Confirmed net-new: `DeformTimeline`/`sampleDeformDeltas` appear only in `runtime-nim/src/bony/mesh/deform.nim`, nowhere in `jsonio.nim`, `anim/`, `binary/`, `model.nim`, or `asset.nim`; there is no registry type key, no `$defs` entry in either schema, and no `deformTimelines` field on `AnimationClip`. This is **step 1 of 4** of the M4 deform-timeline milestone — **format contract + schema/registry/codegen ONLY**. It must land before prompt 24 (runtime load/round-trip wiring); prompts 25 (conformance) and 26 (Dart parity) follow.)

### Description
Introduce a first-class, project-owned **deform timeline** (an animated per-vertex mesh-offset / FFD timeline owned by an animation clip) as a binding **format contract** plus the **registry keys**, **canonical JSON + wire schema**, and **regenerated codec artifacts** for a clip-owned `deformTimeline` record — **contract + schema/registry/codegen only**. Runtime load/round-trip wiring and all clip/mixer/draw-batch behavior land in prompt 24 and are explicitly OUT OF SCOPE here.

`bony` already has a fully-built but **entirely non-serialized** deform-timeline runtime. The types `MeshDelta`, `DeformKeyframe`, `DeformTimeline` and the sampler/apply procs (`sampleDeformDeltas*`, `applyDeformDeltas*`, `applyDeformTimeline*`, `deformTimeline*`, `deformKeyframe*`, `validateDeformTimeline*`) all exist in `runtime-nim/src/bony/mesh/deform.nim`, but no loader ever constructs a `DeformTimeline` and no clip owns one. The registry M4 band `3000..3999` is scoped "Meshes, weights, skins, **deform timelines**, clipping"; mesh + clipping have spent typeKeys `3000`/`3001` and propertyKeys `3000..3005`, so **deform timelines are the last unspent M4-band feature**. This milestone mints the wire format so prompt 24 can add the load path.

**Project-owned model to define** (mirrors the already-existing project type in `mesh/deform.nim`; must NOT be derived from any third-party runtime's fields, wire layout, or naming):

1. A deform timeline is a **clip-owned timeline**, a third timeline family alongside `boneTimelines` and `slotTimelines`, authored under a new `deformTimelines` array on each animation clip. It targets a specific mesh attachment on a specific slot and animates that mesh's per-vertex offsets over time. Serialized shape mirrors `DeformTimeline` (`mesh/deform.nim:18-23`): `skin`, `slot`, `attachment`, `vertexCount`, and a list of keyframes.
2. Each keyframe mirrors `DeformKeyframe` (`mesh/deform.nim:12-16`): `time` (f32-quantized, non-negative, strictly increasing across the timeline), a sparse-window `offset` (uint) into the vertex list, a `deltas` list of `(x, y)` `MeshDelta` pairs (`mesh/deform.nim:8-10`), and a `curve` reusing the existing `TimelineCurveKind`/`TimelineCurve` linear/stepped/bezier machinery (`anim/timelines.nim:8-14`) and the shared `timelineKeys` curve encoding.
3. In prompt 24 (NOT here) the affected mesh's skinned vertices will be offset by the sampled deltas before draw-batch emission via `applyDeformDeltas` (`mesh/deform.nim:140-153`).

**The `skin` field decision (load-bearing).** `validateDeformTimeline*` (`mesh/deform.nim:66-68`) currently **requires a non-empty `skin`**, but `bony` has **no skin construct yet** (skins are a separate reserved M4 capability, not built here). Resolve without inventing a skin subsystem: adopt a **reserved default-skin identity** — the literal string `"default"` is the only accepted `skin` value in v1, documented as forward-compatible with a future skin milestone. Pin this in the contract: the loader accepts `skin == "default"` and rejects any other value (so a future skin milestone can widen the accepted set without breaking v1 files). Do **not** relax the validator to allow empty.

**Registry-key decision (M4 band `3000..3999` only).** Next-free M4 typeKey is `3002`; next-free M4 propertyKey is `3006` (confirmed against `registry/wire.yml`). Allocate:
- typeKey `deformTimeline` = `3002` (mirror the `slotTimeline` typeKey entry).
- Reuse generic timeline property keys where they fit: `slotIndex` (`2002`) for the target slot, and `timelineKeys` (`2004`, `backingType: bytes`) for the packed keyframe payload.
- New M4 property keys: `deformSkin` = `3006` (`backingType: varuint`, a string-table index), `deformAttachment` = `3007` (`backingType: varuint`, a string-table index into the mesh-attachment name), `deformVertexCount` = `3008` (`backingType: varuint`). The `deformSkin`/`deformAttachment` string-table index mechanism is the same one `bones` (key `4014`) and the attachment timelines use.
- Add a `deformTimeline` entry to the `objects:` list (mirror `slotTimeline`) with ordered properties `[deformSkin, slotIndex, deformAttachment, deformVertexCount, timelineKeys]`.
- Cite this milestone's owning bead in every new entry's `doc`; use only the M4 band.

**Packed `timelineKeys` byte layout for deform (pin normatively).** The deform keyframe payload is a `bytes` property. Specify exactly so prompts 24/26 byte-match: `varuint keyCount`, then per keyframe: `f32 time`, `varuint offset`, `varuint deltaCount`, `deltaCount * (f32 dx, f32 dy)`, then the **curve encoding identical to the existing `timelineKeys` curve tail** used by bone/slot timelines (reuse `writeTimelineKeys`'s curve serialization, `binary/semantic.nim:787-853`; do not invent a second curve encoding). Pin a stable heading anchor so the wire schema `PACKED_BYTES_METADATA` layout reference points at it.

### Links to Relevant Documentation
- **Source prompt (authoritative):** `.agents/big-change-prompts/23-contract-deform-timeline-format.md`
- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md` (add the deform-timeline naming entry)
- Comparable research: `docs/comparable-feature-set.md` ("Mesh and deformation" / "Animation timelines" are named comparable capabilities ONLY — NOT an implementation source; do not import any third party's deform field set, wire layout, or naming)
- Float math contract: `docs/float-math-contract.md` (`quantizeF32`, `1e-4` tolerance)
- Existing (non-serialized) Nim deform runtime this milestone wires in: `runtime-nim/src/bony/mesh/deform.nim` (`MeshDelta` 8-10, `DeformKeyframe` 12-16, `DeformTimeline` 18-23, `deformTimeline` ctor 83-95, `validateDeformTimeline` 66-80, `sampleDeformDeltas` 112-137, `applyDeformDeltas` 140-153, `applyDeformTimeline` 156-166) + its mesh dependency `runtime-nim/src/bony/mesh/attachments.nim` (`deformAttachment` field) + `model.nim` (`MeshAttachment.deformAttachment`)
- Freshest end-to-end template (mirror closely): `.agents/big-change-prompts/19-contract-mesh-attachment-format.md` and its landed diff — the "add a new loadable record end to end" template
- Contract doc structural template: `docs/mesh-attachment-contract.md` (Status/owner-bead line; cleanroom/provenance paragraph; `## Model`; `## Load-validated invariants`; `## Edge cases (normative)` table; `## Packed byte layout (.bnb)` anchor; forward-referenced algorithm section; `## Related contracts`)
- Registry key bands: `registry/key-ranges.md` (M4 = `3000..3999`; next-free typeKey `3002`, next-free propertyKey `3006`)
- Registry source: `registry/wire.yml` (slotTimeline typeKey; generic timeline property keys `slotIndex`/`slotTimelineKind`/`timelineKeys` @900-934; objects `boneTimeline`/`slotTimeline` entries @1231-1246; bones packed-bytes key `4014` string-table mechanism)
- Codegen: `codegen/generate.py` (`PACKED_BYTES_METADATA` @26-45, coverage rule @322-339, `canonical_json_overrides` @589+, writes 4 files)
- Defaults source of truth: `spec/defaults.yml` (mesh `objectDefaults` + `requiredProperties` as the template)
- Docs index: `docs/README.md` (add the new contract row under "Attachment Contracts" or a new "Animation Timeline Contracts" heading)
- Repo gate: Makefile `test` + `python3 codegen/generate.py --check` + `python3 scripts/ci/schema_validate_assets.py`
- Smoke change-detector: `runtime-nim/tests/test_smoke.nim` (`bonyTypeKeys.len`/`bonyPropertyKeys.len`/`bonyPropertyDefaults.len`/`bonyRequiredProperties.len`)

### Affected Areas
- **`docs/`** — new `docs/deform-timeline-contract.md` (binding contract); edits to `docs/README.md` (index row), `docs/PROVENANCE.md` (naming entry), `docs/CLEANROOM.md` (new-identifier checklist for `deformTimelines`, `deformSkin`, `deformAttachment`, `deformVertexCount`).
- **`registry/wire.yml`** — M4 band only: typeKey `deformTimeline` (`3002`); propertyKeys `deformSkin` (`3006`), `deformAttachment` (`3007`), `deformVertexCount` (`3008`), and — **only under Option N of the packed-key fork** — a dedicated payload bytes key `deformKeys` (`3009`); `deformTimeline` `objects:` entry (payload prop = `timelineKeys` under Option R, `deformKeys` under Option N); **doc-only** update to the existing `animationClip` objects entry so it names `deformTimeline` as a third owned child family. (Verified next-free: typeKeys `3000`/`3001` spent by clipping/mesh; propertyKeys `3000..3005` spent by `vertices`/`untilSlot`/`meshWeighted`/`meshVertices`/`meshUvs`/`meshTriangles`; `3009` next-free bytes-capable key.)
- **`codegen/generate.py`** — `PACKED_BYTES_METADATA` (deform payload layout anchor — resolved by the packed-key fork) and `canonical_json_overrides()` in **two** places: (1) a new `deformTimeline` `$defs` entry (readable JSON shape) and (2) a patch to the hand-authored `animationClip` override literal (`@786-803`, `additionalProperties:False`) adding the optional `deformTimelines` array — **without (2) the headline `deformTimelines` deliverable never appears** and `REGEN`'s own verification fails.
- **`.agents/notes/deform-timeline-format-decisions.md`** (new) — durable record of the packed-key fork resolution + curve-tail encoding + typeKey/decode sync-check finding, written by the analysis beads and read by every downstream registry/codegen bead (bd agents execute fresh with no shared memory).
- **`spec/defaults.yml`** — `objectDefaults` + `requiredProperties` coverage for every serialized `deformTimeline` property exactly once (coverage rule @322-339).
- **Generated artifacts (regenerated, NOT hand-edited):** `spec/bony.schema.json`, `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, `runtime-dart/lib/src/generated/wire.dart`. Animation-clip JSON `$defs` must gain an optional `deformTimelines` array.
- **`runtime-nim/tests/test_smoke.nim`** — bump the four registry change-detector counts to the regenerated totals (baseline: typeKeys `28`, propertyKeys `101`, propertyDefaults `55`, requiredProperties `74`).
- **Explicitly UNTOUCHED (prompt 24/25/26):** `runtime-nim/src/bony/anim/timelines.nim` (`AnimationClip`), `jsonio.nim`, `binary/semantic.nim` decode/flush, the mixer, `buildDrawBatches`, any conformance rig/golden, and all Dart runtime logic beyond the regenerated `generated/wire.dart`.

### Success Criteria
- `docs/deform-timeline-contract.md` exists, is listed in `docs/README.md`, and normatively specifies: the model; the load-validated invariants + tolerances (tied to `docs/float-math-contract.md`'s `1e-4` + f32 quantization); the edge-case table (a)–(g); the packed `.bnb` byte layout with a stable heading anchor; the forward-referenced deterministic sampling formula/order (from `sampleDeformDeltas*` `mesh/deform.nim:112-137`: nearest-preceding-key search, stepped short-circuit, linear `eased = curve.evaluate(t)` interpolation of expanded dense deltas, f32 quantization at the boundary; apply order via `applyDeformDeltas` `:140-153`); the `skin == "default"` reserved-identity decision; and a `## Cross-track mixing` section pinning the multi-clip policy (a deform timeline resolves like an **attachment channel** — thresholded / winner-take-by-track-weight, NOT weight-blended — documented-but-unexercised in v1).
- The edge-case table makes normative: (a) `skin != "default"` → reject; (b) empty `slot`/`attachment`, or `attachment` naming an unknown mesh on that slot → reject; (c) `vertexCount <= 0`, or disagreeing with the referenced mesh's vertex count → reject; (d) zero keyframes → reject; (e) a keyframe with zero deltas, or `offset + deltas.len > vertexCount` → reject; (f) non-strictly-increasing key times, or a negative time → reject; (g) a deform timeline whose slot/attachment pairing does not resolve to a loaded mesh attachment → reject.
- `registry/wire.yml` gains `deformTimeline` type (key `3002`), `deformSkin` (`3006`), `deformAttachment` (`3007`), `deformVertexCount` (`3008`) — plus `deformKeys` (`3009`) if Option N is chosen — and a `deformTimeline` `objects:` entry reusing `slotIndex` and the resolved payload key; the `animationClip` objects doc names `deformTimeline` as a third owned child; no key collides; all new keys in `3000..3999`.
- Codegen's `animationClip` canonical-JSON override is patched so a clip may carry an **optional** `deformTimelines` array (`additionalProperties:False` otherwise rejects it); the packed-key fork (reuse `timelineKeys` 2004 vs. mint `deformKeys` 3009) is resolved and recorded before any registry edit, because it changes the `.bnb` wire — the prompt-23 criterion "wire schema packedBytes layout reference points at the deform contract anchor" is satisfiable only under Option N, and choosing Option R knowingly waives it.
- `spec/defaults.yml` covers every serialized `deformTimeline` property exactly once across `objectDefaults` + `requiredProperties` (each `requiredProperties` entry carrying `reason` + `ownerBead`); `python3 codegen/generate.py --check` passes.
- Codegen regenerated (both schemas + `generated/wire.nim` + `generated/wire.dart`) with no hand-edits; the animation-clip JSON `$defs` gains an optional `deformTimelines` array whose items express the readable `skin`/`slot`/`attachment`/`keyframes` shape (`keyframes` = array of `{ "t": number, "offset": integer, "deltas": [ { "x": number, "y": number } ], "curve"?: ... }`; `vertexCount` derived from the mesh at load — stored in `.bnb`, not authored in JSON); `python3 scripts/ci/schema_validate_assets.py` passes for all existing assets.
- `docs/PROVENANCE.md` gains the deform-timeline naming entry (schema/field names taken from `bony`'s own pre-existing `mesh/deform.nim` runtime types, not from any surveyed product); the `docs/CLEANROOM.md` new-identifier checklist is satisfied for `deformTimelines`, `deformSkin`, `deformAttachment`, `deformVertexCount`.
- `runtime-nim/tests/test_smoke.nim` change-detector counts updated to the regenerated totals.
- `make test` passes.
- **Explicit NON-goal:** the runtime JSON+`.bnb` round-trip test and the load-validation rejections (a)–(g) are **deferred to prompt 24** (they need the `AnimationClip`/`jsonio`/`semantic` loader wiring this prompt does not touch). Do NOT claim or attempt a runtime round-trip test here — there is no loader for the record yet.

### Constraints
- Preserve clean-room posture: do not inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime source, importer source, generated definitions, exact wire layouts, type/property keys, deform/FFD field names, or copied docs prose. The deform-timeline model, field names, and sampling formula are project-owned (they already exist in `bony`'s own `mesh/deform.nim`).
- Use `docs/comparable-feature-set.md` only to justify the deform-animation capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for human/legal review.
- Do NOT build a skin subsystem — use only the reserved `"default"` skin identity. A general skin model is a separate milestone.
- Registry edits: use only the M4 band (`3000..3999`) per `registry/key-ranges.md`; follow that file's shared-surface reservation rule.
- Land the registry entry, `defaults.yml`, canonical-JSON overrides, schema regen, and codegen **together** — `validate_sources()` fails if they drift apart. Do the four generated files via `python3 codegen/generate.py` only (never hand-edit them).
- Do **NOT** wire the timeline into `AnimationClip`/mixer/`buildDrawBatches`, add a conformance rig/golden, or touch Dart runtime logic in this prompt. Those are prompts 24, 25, and 26.
- **Natural cut line if it runs long:** **unit A** = contract doc + registry keys + `objects:` entry; **unit B** = codegen (`PACKED_BYTES_METADATA` / `canonical_json_overrides` / `defaults.yml`) + the four-file regen with `codegen --check` green + provenance. **Do not land unit A leaving `codegen --check` red.**
- This slice ends when the `deformTimeline` record exists in the registry and both schemas, the codegen artifacts are regenerated, and the contract doc is written — but no runtime loads, validates, or round-trips it yet.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/specs/` and `docs/adr/` for existing architectural decisions (note: this repo uses `docs/*-contract.md` binding contracts and `docs/PROVENANCE.md`/`docs/CLEANROOM.md` governance rather than a `specs/`/`adr/` tree — read those).
2. Examine the directory/module structure of the affected areas listed above.
3. Identify key interfaces, APIs, and integration points that must be preserved.
4. Note existing test patterns and coverage in the affected areas.
5. Assess risk areas where changes could break existing functionality.

Use your analysis to make each bead specific — reference actual file paths, module names, and patterns you observed.

Then generate a shell script that creates the complete task graph.

**IMPORTANT: Your ONLY deliverable is a bash shell script with `bd create` commands. Not an implementation plan. Not a design document. Not a code review. A runnable `.sh` script.**

---

## Output Format

Generate a shell script that creates the full task graph. The script should:

1. **Initialize Beads** (if not already initialized)
2. **Create one parent epic** (`bd create -t epic`) representing the whole change, capturing its ID into `$EPIC`
3. **Create all task beads** with appropriate priorities, each parented to the epic via `--parent "$EPIC"`
4. **Establish dependencies** between task beads (ordering edges only — never to or from the epic)
5. **Add labels** for phase grouping (child beads inherit the epic's labels unless `--no-inherit-labels`)

### Example Output

```bash
#!/bin/bash
# Project: bony
# Change: Introduce clip-owned deformTimeline format contract (M4, contract+schema+codegen only)
# Generated: 2026-07-03

set -e

# Initialize beads if needed
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating change beads..."

# ========================================
# Parent epic — every task below is parented to it (--parent "$EPIC").
# The epic is an organizational rollup: it is NEVER given a blocking dep
# (no `bd dep add` to or from it) and is never dispatched as work itself.
# ========================================

EPIC=$(bd create "Epic: deformTimeline format contract + M4 registry keys + schema/codegen regen (prompt 23 of M4 deform-timeline milestone)" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work — keep it out of `bd ready`

# ========================================
# Phase 1: Analysis & Grounding (read-only; confirms symbols before edits)
# ========================================

ANALYZE_DEFORM=$(bd create "Confirm project-owned deform types/procs in runtime-nim/src/bony/mesh/deform.nim (MeshDelta 8-10, DeformKeyframe 12-16, DeformTimeline 18-23, validateDeformTimeline 66-80, sampleDeformDeltas 112-137, applyDeformDeltas 140-153) and the mesh-attachment dependency (attachments.nim deformAttachment, model.nim MeshAttachment.deformAttachment) — record exact field names/order for the serialized shape" -p 0 --label analysis --parent "$EPIC" --silent)

ANALYZE_REGISTRY=$(bd create "Confirm M4 next-free keys in registry/wire.yml: typeKey 3002 free (3000/3001 = clipping/mesh), propertyKeys 3006-3008 free (3000-3005 = vertices/untilSlot/meshWeighted/meshVertices/meshUvs/meshTriangles); next-free bytes-capable propertyKey after 3008 is 3009. Capture the slotTimeline typeKey entry, boneTimeline/slotTimeline objects entries (@1231-1246), the animationClip objects entry + its doc string (currently 'followed immediately by owned boneTimeline and slotTimeline records'), and generic timeline keys slotIndex(2002)/timelineKeys(2004) as templates. ALSO probe for any sync/consistency check between generated typeKeys (generated/wire.nim) and hand-written *TypeKey constants or decode dispatch in binary/semantic.nim (clippingAttachment/meshAttachment decode @~491/@~556): if such a check exists, adding typeKey 3002 with NO decode path (prompt 24 territory) could break make test — record whether it exists and the fallback if so. Write findings to a durable note (.agents/notes/deform-timeline-format-decisions.md) that downstream beads read" -p 0 --label analysis --parent "$EPIC" --silent)

ANALYZE_CURVE=$(bd create "Read writeTimelineKeys curve serialization (runtime-nim/src/bony/binary/semantic.nim:787-853) and TimelineCurveKind/TimelineCurve (anim/timelines.nim:8-14); document the exact curve-tail encoding the deform packed layout must reuse verbatim (no second curve encoding). Append the encoding note to .agents/notes/deform-timeline-format-decisions.md" -p 0 --label analysis --parent "$EPIC" --silent)

# DECISION BEAD (wire-format-affecting; must be resolved BEFORE any registry edit).
# PACKED_BYTES_METADATA (generate.py:26-45) is keyed by PROPERTY ID; the sole
# 'timelineKeys' (2004) entry's layout points at the SCALAR keyframe doc
# (docs/binary-animation-state-machine-object-families.md#keyframe-payloads), and
# the schema stamps x-bony-packedBytes onto a property by that key (generate.py:994).
# Prompt 23 contains an internal tension: it says BOTH "reuse timelineKeys (2004)"
# AND "the wire schema PACKED_BYTES_METADATA layout reference points at [the deform
# contract anchor]". These are incompatible because metadata is one-entry-per-property:
#   Option R (reuse timelineKeys 2004): objects entry uses timelineKeys; NO new key;
#     but the deform record's packed-bytes layout pointer stays on the SCALAR doc —
#     the deform contract anchor is documented but NOT referenced by the wire schema.
#   Option N (mint new M4 bytes key, e.g. deformKeys=3009, backingType bytes): its own
#     PACKED_BYTES_METADATA entry points at the deform contract anchor (matches the
#     per-payload pattern of vertices/meshVertices/bones); changes REGISTRY_KEYS,
#     REGISTRY_OBJECT ordered props, DEFAULTS coverage, and canonical JSON.
# Resolve this fork explicitly, pin it in the contract, and RECORD it in
# .agents/notes/deform-timeline-format-decisions.md before REGISTRY_KEYS runs.
DECIDE_PACKED_KEY=$(bd create "Resolve the deform packed-payload key fork (Option R reuse timelineKeys 2004 vs Option N mint deformKeys=3009 bytes). Read generate.py PACKED_BYTES_METADATA (@26-45, keyed by property id), the x-bony-packedBytes stamp (@994), coverage rule (@322-339), canonical_json_overrides (@589+), and the mesh objectDefaults/requiredProperties template in spec/defaults.yml. The prompt-23 success criterion 'wire schema packedBytes layout reference points at the deform contract anchor' is only satisfiable under Option N — flag if choosing Option R that this criterion is knowingly waived. Write the chosen option + rationale to .agents/notes/deform-timeline-format-decisions.md; every downstream registry/codegen bead reads that note" -p 0 --label analysis --parent "$EPIC" --silent)
bd dep add $DECIDE_PACKED_KEY $ANALYZE_CURVE
bd dep add $DECIDE_PACKED_KEY $ANALYZE_REGISTRY

# ========================================
# Phase 2: Unit A — Contract doc + Registry keys + objects entry
# (Do NOT land Unit A leaving `codegen --check` red — Unit B must follow before commit.)
# ========================================

CONTRACT_DOC=$(bd create "Write docs/deform-timeline-contract.md (binding). Mirror docs/mesh-attachment-contract.md structure: Status/owner-bead line; cleanroom/provenance paragraph; ## Model (skin/slot/attachment/vertexCount/keyframes mirroring DeformTimeline); ## Load-validated invariants tied to docs/float-math-contract.md (1e-4 + f32 quantization); normative ## Edge cases table (a)-(g); ## Packed byte layout (.bnb) with a STABLE heading anchor referenced by the wire schema; forward-ref ## Deterministic sampling algorithm (implemented in prompt 24) pinning sampleDeformDeltas formula + applyDeformDeltas order; the skin == 'default' reserved-identity decision; ## Cross-track mixing (attachment-channel / winner-take-by-track-weight, NOT weight-blended; documented-but-unexercised in v1); ## Related contracts" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CONTRACT_DOC $ANALYZE_DEFORM
bd dep add $CONTRACT_DOC $ANALYZE_CURVE

CONTRACT_PACKED_ANCHOR=$(bd create "In docs/deform-timeline-contract.md ## Packed byte layout (.bnb): pin normatively — varuint keyCount, then per keyframe: f32 time, varuint offset, varuint deltaCount, deltaCount*(f32 dx, f32 dy), then the curve tail identical to writeTimelineKeys (semantic.nim:787-853). Give the heading a stable anchor. Under Option N this anchor is the PACKED_BYTES_METADATA layout target; under Option R state explicitly in the contract that the wire schema packedBytes pointer references the shared scalar keyframe doc and this deform anchor is documentation-only. Read .agents/notes/deform-timeline-format-decisions.md for the chosen option" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CONTRACT_PACKED_ANCHOR $CONTRACT_DOC
bd dep add $CONTRACT_PACKED_ANCHOR $DECIDE_PACKED_KEY

REGISTRY_KEYS=$(bd create "Edit registry/wire.yml (M4 band only): add typeKey deformTimeline=3002 (mirror slotTimeline typeKey entry); add propertyKeys deformSkin=3006 (backingType varuint, string-table index), deformAttachment=3007 (backingType varuint, string-table index), deformVertexCount=3008 (backingType varuint). If Option N was chosen (read .agents/notes/deform-timeline-format-decisions.md): ALSO add deformKeys=3009 (backingType bytes) for the packed payload; if Option R, no bytes key is added and timelineKeys(2004) is reused instead. Cite the milestone owner bead in each new entry's doc. No key collides; all in 3000..3999" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGISTRY_KEYS $ANALYZE_REGISTRY
bd dep add $REGISTRY_KEYS $DECIDE_PACKED_KEY

REGISTRY_OBJECT=$(bd create "Edit registry/wire.yml objects: (1) add a deformTimeline entry (mirror slotTimeline @1241-1246) with ordered properties [deformSkin, slotIndex, deformAttachment, deformVertexCount, <PAYLOAD>] where <PAYLOAD> is timelineKeys(2004) under Option R or deformKeys(3009) under Option N (read the decisions note). (2) DOC-ONLY: update the existing animationClip objects entry doc string so it names deformTimeline as a third owned child family (currently 'followed immediately by owned boneTimeline and slotTimeline records' -> include deformTimeline). Do NOT touch binary/semantic.nim decode/flush — decode ownership wiring is prompt 24" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGISTRY_OBJECT $REGISTRY_KEYS

DOCS_INDEX=$(bd create "Add docs/deform-timeline-contract.md row to docs/README.md (under 'Attachment Contracts' or a new 'Animation Timeline Contracts' heading beside the mesh/clipping rows), with a one-line binding description" -p 2 --label docs --parent "$EPIC" --silent)
bd dep add $DOCS_INDEX $CONTRACT_DOC

# ========================================
# Phase 3: Unit B — Codegen (defaults + canonical JSON + packed metadata)
# ========================================

DEFAULTS=$(bd create "Add spec/defaults.yml entries covering every serialized deformTimeline property EXACTLY once across objectDefaults + requiredProperties (coverage rule generate.py:322-339). Each requiredProperties entry carries reason + ownerBead (mirror mesh @defaults.yml:468-475). Serialized set: deformSkin, slotIndex, deformAttachment, deformVertexCount, and the payload key (timelineKeys under Option R OR deformKeys under Option N — read the decisions note). PIN the deformVertexCount placement explicitly: it is a wire property that must be coverage-satisfied but is deliberately ABSENT from canonical JSON (derived from the mesh at load) — decide and document whether it lives in objectDefaults or requiredProperties, mirror how other derived/wire-only props are covered, and confirm its JSON absence trips no schema validation so codegen --check is deterministic" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $DEFAULTS $REGISTRY_OBJECT

CANONICAL_JSON=$(bd create "Edit codegen/generate.py canonical_json_overrides() TWO places: (1) add a deformTimeline \$defs entry (@589+) with readable shape { skin: const 'default', slot: string, attachment: string, keyframes: [ { t: number, offset: integer, deltas: [ { x: number, y: number } ], curve?: ... } ] } — vertexCount derived from the mesh at load, stored in .bnb, NOT authored in JSON. (2) PATCH the existing hand-authored animationClip override literal (@786-803, additionalProperties:False, currently only boneTimelines/slotTimelines) to add an OPTIONAL deformTimelines array: 'deformTimelines': {'type':'array','items':{'\$ref':'#/\$defs/deformTimeline'},'default':[]}. Without (2) the additionalProperties:False clip rejects deformTimelines and the headline deliverable never appears — nothing else in the graph produces it" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CANONICAL_JSON $REGISTRY_OBJECT

PACKED_METADATA=$(bd create "Per the DECIDE_PACKED_KEY resolution (read .agents/notes/deform-timeline-format-decisions.md): Option N -> add a PACKED_BYTES_METADATA entry (generate.py:26-45) keyed by the new deformKeys property id, with layout pointing at the deform contract's ## Packed byte layout anchor (mirror vertices/meshVertices/bones entries). Option R -> NO new metadata entry (timelineKeys 2004 keeps its existing scalar-doc layout pointer, shared with bone/slot); add a code comment recording that deform intentionally reuses it and the deform anchor is documentation-only. Document the choice in the code" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $PACKED_METADATA $DECIDE_PACKED_KEY
bd dep add $PACKED_METADATA $CONTRACT_PACKED_ANCHOR
bd dep add $PACKED_METADATA $REGISTRY_OBJECT

# ========================================
# Phase 4: Regen + Provenance/Cleanroom
# ========================================

REGEN=$(bd create "Run python3 codegen/generate.py to regenerate spec/bony.schema.json, spec/bony-wire.schema.json, runtime-nim/src/bony/generated/wire.nim, runtime-dart/lib/src/generated/wire.dart (NEVER hand-edit these four). Verify the animation-clip JSON \$defs gains an optional deformTimelines array with the readable skin/slot/attachment/keyframes item shape. python3 codegen/generate.py --check MUST pass" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGEN $DEFAULTS
bd dep add $REGEN $CANONICAL_JSON
bd dep add $REGEN $PACKED_METADATA

PROVENANCE=$(bd create "Add docs/PROVENANCE.md entry: deform-timeline schema/field names taken from bony's own pre-existing mesh/deform.nim runtime types (not derived from any surveyed product). Run the docs/CLEANROOM.md new-identifier checklist for net-new serialized names: deformTimelines, deformSkin, deformAttachment, deformVertexCount" -p 1 --label docs --parent "$EPIC" --silent)
bd dep add $PROVENANCE $REGISTRY_KEYS

# ========================================
# Phase 5: Verification & Change-Detector
# ========================================

SMOKE_COUNTS=$(bd create "Update runtime-nim/tests/test_smoke.nim registry change-detector counts to the regenerated totals: bonyTypeKeys.len (28 -> 29), bonyPropertyKeys.len (101 -> 104 for +deformSkin/+deformAttachment/+deformVertexCount), and bonyPropertyDefaults.len / bonyRequiredProperties.len to whatever the regen produces (read the generated wire.nim; do not guess)" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $SMOKE_COUNTS $REGEN

VALIDATE_ASSETS=$(bd create "Run python3 scripts/ci/schema_validate_assets.py — MUST pass for all existing assets against the regenerated schema (proves the new optional deformTimelines array does not break existing clip assets)" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $VALIDATE_ASSETS $REGEN

MAKE_TEST=$(bd create "Run make test (full gate) and confirm green, including python3 codegen/generate.py --check. EXPLICITLY confirm (do not assume) the whole gate tolerates a new typeKey (deformTimeline=3002) that has NO decode path / no *TypeKey constant / no dispatch in binary/semantic.nim — per the ANALYZE_REGISTRY sync-check probe. If make test surfaces a generated-typeKey<->semantic.nim consistency check that fails on the undecoded key, STOP: the slice is not buildable as scoped and needs escalation (do not add decode wiring — that is prompt 24). Do NOT add or attempt a runtime JSON/.bnb round-trip test for deformTimeline — there is no loader yet (deferred to prompt 24)" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $MAKE_TEST $SMOKE_COUNTS
bd dep add $MAKE_TEST $VALIDATE_ASSETS
bd dep add $MAKE_TEST $DOCS_INDEX
bd dep add $MAKE_TEST $PROVENANCE

echo ""
echo "Bead graph created! View with:"
echo "  bd show $EPIC          # The parent epic and its rollup"
echo "  bd children $EPIC      # All task beads under the epic"
echo "  bd ready              # List unblocked tasks (the epic itself is not work)"
```

---

## Bead Creation Guidelines

### Epic / Hierarchy (REQUIRED)
- Create exactly **one parent epic** for the whole change: `EPIC=$(bd create "Epic: <change summary>" -t epic -p 0 --label epic --silent)`.
- Parent **every** task bead to it: add `--parent "$EPIC"` to every `bd create` (children inherit the epic's labels unless you pass `--no-inherit-labels`).
- The epic is a **rollup, not work**: never `bd dep add` to or from it. Membership is `--parent`; `bd dep add` is reserved for real ordering edges *between task beads*. A blocking edge on an epic wrongly keeps it out of (or drops it into) `bd ready` and inverts `bd dep tree`.
- **Keep the epic out of `bd ready`** by marking it active right after creation: `bd update "$EPIC" --status in_progress`. `bd ready` excludes `in_progress`/`blocked`/`deferred`/`hooked`. Do **not** rely on `--exclude-type epic` — that flag is ineffective on some `bd`/`bn` builds, whereas status-based exclusion works everywhere.
- An epic must have **≥ 2 children** to be meaningful.
- For very large changes you MAY use phase sub-epics, but a single top-level epic is the default and is sufficient here.

### Priority Levels
- `-p 0` = Critical (blocking other work, or high-risk changes needing early validation)
- `-p 1` = High (important implementation work)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (cleanup, nice-to-haves)

### Labels (Phase Grouping)
- `analysis` - Understanding current state
- `prep` - Preparation work
- `impl` - Core implementation
- `testing` - Test coverage / gates
- `docs` - Documentation updates

### Dependency Rules
1. Never create cycles
2. Analysis tasks should complete before implementation begins
3. Registry/defaults/canonical-JSON/packed-metadata must all precede the four-file regen (validate_sources drift check)
4. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
5. Parallel work should share a common ancestor, not depend on each other
6. `bd dep add` is for ordering edges **between task beads only** — never to/from the epic

### Task Granularity
- Each bead should be completable in **under 750 lines of code changed**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area

---

## Change-Specific Considerations

### For New Features
- Start with analysis of the similar existing serialized record (the mesh-attachment slice, prompt 19, is the closest template — mirror its diff shape).
- No feature flag needed: the `deformTimelines` array is an **optional** JSON `$defs` addition; existing assets must still validate (that is `schema_validate_assets.py`).
- Include documentation (contract doc + README index) and provenance/cleanroom updates.
- **Critical NON-goal:** no runtime loader, no `AnimationClip` wiring, no mixer/`buildDrawBatches`, no conformance rig, no Dart logic. Those are prompts 24/25/26. Do not attempt a runtime round-trip test.

---

## File Reservation Planning

```bash
# Reservation notes (add as bead descriptions where relevant):
# Registry (shared surface, high contention): registry/wire.yml — M4 band 3000..3999 ONLY
# Codegen (shared): codegen/generate.py, spec/defaults.yml — land together with registry (validate_sources drift check)
# Generated (regenerated, never hand-edit): spec/bony.schema.json, spec/bony-wire.schema.json,
#   runtime-nim/src/bony/generated/wire.nim, runtime-dart/lib/src/generated/wire.dart
# Docs: docs/deform-timeline-contract.md (new), docs/README.md, docs/PROVENANCE.md, docs/CLEANROOM.md
# Tests: runtime-nim/tests/test_smoke.nim (change-detector counts only)
# DO NOT TOUCH: anim/timelines.nim, jsonio.nim, binary/semantic.nim decode/flush, mixer, buildDrawBatches, Dart runtime logic
```

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check the rollup**: `bd children "$EPIC"` lists every task bead; `bd dep tree` shows them under the epic with no orphan tasks
3. **Check ready work**: `bd ready` shows the Phase-1 analysis tasks and **not** the epic
4. **Check no cycles**: `bd dep cycles` reports none

---

## Completeness Checklist

- [ ] A single parent epic (`-t epic`); every task bead parented via `--parent "$EPIC"`; no orphan tasks; no blocking dep to/from the epic
- [ ] Analysis/grounding of `mesh/deform.nim`, registry next-free keys, curve encoding, codegen anchors
- [ ] Contract doc (`docs/deform-timeline-contract.md`) with model, invariants+tolerances, edge-case table (a)-(g), packed `.bnb` layout anchor, forward-ref sampling algorithm, `skin=="default"` decision, cross-track mixing, related contracts
- [ ] Packed-key fork (reuse `timelineKeys` 2004 vs. mint `deformKeys` 3009) resolved and recorded in `.agents/notes/deform-timeline-format-decisions.md` **before** registry edits
- [ ] Registry: typeKey `3002`, propertyKeys `3006/3007/3008` (+ `3009` under Option N), `deformTimeline` objects entry, and `animationClip` doc naming `deformTimeline` as a third owned child
- [ ] `spec/defaults.yml` coverage (each serialized property once; requiredProperties reason+ownerBead; `deformVertexCount` placement pinned despite JSON absence)
- [ ] Canonical-JSON: new `deformTimeline` `$defs` **and** the `animationClip` override patched to add the optional `deformTimelines` array; packed-bytes metadata matches the fork resolution
- [ ] Four-file regen via `codegen/generate.py`; `--check` green; animation-clip `$defs` gains optional `deformTimelines`
- [ ] `make test` explicitly confirmed green with a typeKey that has no decode path (no generated-typeKey↔`semantic.nim` sync check breaks)
- [ ] `docs/README.md` index row; `docs/PROVENANCE.md` entry; `docs/CLEANROOM.md` checklist
- [ ] `test_smoke.nim` change-detector counts bumped to regenerated totals
- [ ] `schema_validate_assets.py` passes; `make test` passes
- [ ] NO runtime loader / round-trip test / conformance rig / Dart logic (deferred to prompts 24/25/26); Unit A not landed with `codegen --check` red
- [ ] Clear dependency chains with no cycles
