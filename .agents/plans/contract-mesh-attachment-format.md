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

This slice adds a **new first-class loadable attachment record** (mesh attachment) to the `.bony`/`.bnb` format. There is no existing mesh serialization to migrate or refactor — the mesh runtime math exists but is entirely non-serialized, so this is net-new format surface. It follows the proven region → path → clipping attachment-class progression (the clipping slice, prompt 15 / bead `bony-jkt`, is the closest template to mirror).

### Description
Introduce a first-class, project-owned **mesh attachment** (weighted or unweighted, with per-vertex UVs and a triangle list) as a loadable, validated, round-trippable `.bony`/`.bnb` format record, plus a binding contract document. **Format and load ONLY — no draw-batch emission, no `buildDrawBatches` change, no skinning evaluation, no conformance rig/golden, and no Dart runtime work in this slice.** A mesh loads, validates, and round-trips through JSON and `.bnb`, and nothing yet draws it.

Concretely this slice delivers:

1. **Contract doc** `docs/mesh-attachment-contract.md` — a binding contract mirroring the heading structure of `docs/clipping-attachment-contract.md` (whose actual headings are `## Model`, `## Convex-polygon invariants (load-validated)`, `## Range edge cases (normative)`, `` ## Packed `vertices` byte layout (`.bnb`) ``, `## Deterministic clip algorithm (forward reference …)`, `## Related contracts`): Status/owner-bead line; cleanroom/provenance paragraph; `## Model`; a load-validated-invariants section (tolerances tied to the `1e-4` bound in `docs/float-math-contract.md`); a normative edge-case table for cases (a)–(g); **three separate** packed-byte sections (one per `bytes` property — clipping has only one, so there is no 1:1 template); a forward-reference `## Deterministic skinning algorithm (forward reference — implemented in prompt 20)` section; and `## Related contracts`. Cross-linked from `docs/README.md` under "Attachment Contracts".

   **Pin the three packed-section headings + their GitHub-slug anchors as the single source of truth shared by the doc and `PACKED_BYTES_METADATA` (`generate.py --check` fails on any drift):**
   - `` ## Packed `meshVertices` byte layout (`.bnb`) `` → anchor `#packed-meshvertices-byte-layout-bnb`
   - `` ## Packed `meshUvs` byte layout (`.bnb`) `` → anchor `#packed-meshuvs-byte-layout-bnb`
   - `` ## Packed `meshTriangles` byte layout (`.bnb`) `` → anchor `#packed-meshtriangles-byte-layout-bnb`

   Three things MUST be pinned normatively for prompt 22 (Dart) to byte/behavior-match: (i) the packed `.bnb` byte layouts per `bytes` property (anchored as above, referenced from the wire schema); (ii) the skinning formula + evaluation order (linear blend `worldPos = sum_i weight_i * (boneWorld_i * (bindX_i, bindY_i))`, influences accumulated in stored order, f32 quantization at the output boundary via the `quantizeF32` proc (defined in `runtime-nim/src/bony/model.nim`; the `1e-4` tolerance is specified in `docs/float-math-contract.md`), matching `skinMeshVertices` `skinning.nim:55-69`, agreement within `1e-4`); (iii) mesh `DrawBatch` metadata defaults (`texturePage = ""` and the slot's blend mode — mesh record carries neither) and the v1 non-goal that **mesh attachments are not clipped**.

2. **Registry** (`registry/wire.yml`, M4 band `3000..3999` only): add type key `meshAttachment = 3001` (mirror `clippingAttachment` typeKey at `wire.yml:229-234`); property keys `meshWeighted = 3002` (bool), `meshVertices = 3003` (bytes), `meshUvs = 3004` (bytes), `meshTriangles = 3005` (bytes) (mirror clipping property block `wire.yml:502-515`); **reuse** the global `name` key (do not allocate a new one); add an `objects:` entry `meshAttachment` with ordered properties `[name, meshWeighted, meshVertices, meshUvs, meshTriangles]` (mirror `wire.yml:1083-1088`). Cite this slice's owning bead in every new entry's `doc`.

3. **Codegen** (`codegen/generate.py`): add `PACKED_BYTES_METADATA` entries (mirror `vertices` at `generate.py:39-44`) for `meshVertices`, `meshUvs`, `meshTriangles`, each with a `layout` anchor pointing at the exact anchors pinned in step 1 (`docs/mesh-attachment-contract.md#packed-meshvertices-byte-layout-bnb`, `#packed-meshuvs-byte-layout-bnb`, `#packed-meshtriangles-byte-layout-bnb`) — these MUST match the contract heading slugs verbatim or `--check` fails; hand-author the full `canonical_json_overrides()` (`generate.py:571+`) `$defs/meshAttachment` — `name`, `weighted`, plus structured `uvs` (numeric array, `minItems 2`, even length), `triangles` (integer array, `minItems 3`, length `mod 3 == 0`), and `vertices` (array of vertex objects, items `{ "oneOf": [ {unweighted x,y}, {weighted influences[] } ] }`); add `spec/defaults.yml` entries — one `objectDefaults` (`meshWeighted → {value:false, omitWhenDefault:true, applyOnLoad:true}`) and `requiredProperties` for `name, meshVertices, meshUvs, meshTriangles` each carrying `reason` + `ownerBead` (mirror clipping `defaults.yml:170-176` / `468-475`; coverage rule at `generate.py:307-315` requires every property to appear exactly once across the two sets). Regen the 4 generated files (`spec/bony.schema.json`, `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, `runtime-dart/lib/src/generated/wire.dart`) — never hand-edit; the top-level collection auto-names `meshAttachments` (no `root_collection_overrides` entry). `python3 codegen/generate.py --check` must pass.

4. **Import-cycle / type-home**: `mesh/attachments.nim` imports `model` (its validator takes `SkeletonData`), so `model.nim` cannot import `mesh/*`. Resolve exactly as clipping did — **move the four mesh record type definitions** (`MeshAttachment`, `MeshVertex`, `MeshUv`, `MeshInfluence`, `attachments.nim:10-37`) into `runtime-nim/src/bony/model.nim` beside `ClipAttachmentData` (`model.nim:88-91`); update `mesh/attachments.nim` and `mesh/skinning.nim` to consume them from `model`; do NOT duplicate the type; keep the constructor/validator/skinning **procs** where they are. `nim check` is the cycle gate.

5. **Nim model** (`model.nim`): add `meshAttachments: seq[MeshAttachment]` to `SkeletonData` (near `clippingAttachments` at `:254`), a `meshAttachments*` accessor (mirror `clippingAttachments*` at `:694`; record getters follow the `569-571` pattern), and thread a `meshAttachments` param through:
   - the single `skeletonData*` constructor (**one proc only**, at `model.nim:1059-1088` — there is **no** second "overload"; the field assignment is at ~`:1082`);
   - **both** `validateSkeletonData*` paths — the `openArray` validator at `:750` (whose `clippingAttachments` param sits at `:762`) and the `SkeletonData` wrapper at `:1091`.

   The new param **MUST carry a default** (`meshAttachments: openArray[MeshAttachment] = []` on the validator, `= @[]` where a seq is taken), exactly as clipping's param defaults to `[]` at `:762`. There are ~62 positional callers of `skeletonData(...)`/`validateSkeletonData(...)` (3 in non-test source — `jsonio.nim:695`, `binary/semantic.nim:1618`, `anim/mixer.nim` — plus ~59 in `runtime-nim/tests/`, 46 of them in `test_smoke.nim`); a non-defaulted append breaks the build across all of them. Appending last + defaulting means existing positional call sites need no edit.

6. **Nim load-time validation — decide the construction/validation seam explicitly (load-bearing).** The existing `meshAttachment(data: SkeletonData; …)` constructor (`attachments.nim:134-161`) takes a `SkeletonData` and validates immediately at `:161` — **it is NOT usable during parsing**, because both loaders accumulate per-section seqs and call `skeletonData(...)` exactly once at the end (`jsonio.nim:695`, `binary/semantic.nim:1618`); no assembled `SkeletonData` exists mid-parse, and building a partial one would run full `validateSkeletonData` on an incomplete skeleton and fail. Mirror how clipping actually works: clipping parses into plain **value** records via `clipAttachmentData(...)` (a no-`SkeletonData` ctor) and defers ALL cross-reference validation to `validateSkeletonData`, where the checks are **inlined** (`model.nim:806+`), not delegated to a per-record proc. Therefore:
   - **Add a raw-value mesh constructor** (no `SkeletonData` param — mirror `clipAttachmentData`) that builds a `MeshAttachment` from parsed fields **without** validating, for the loaders to call. (The existing `SkeletonData`-taking `meshAttachment(...)` may stay for other callers, but the load path must not use it mid-parse.)
   - **Wire the mesh edge-case validation into `validateSkeletonData`** (the `openArray` path at `model.nim:750`) so every loaded mesh runs the (a)–(g) checks — the success-criteria rejection tests depend on this. Because `validateMeshAttachment` needs bone names but that path holds no `SkeletonData` value, **pin one of**: (a) refactor `validateMeshAttachment` to accept a bone-name set / `bones` openArray instead of a `SkeletonData` (preferred — keeps one implementation), or (b) build the bone-name set inline in `validateSkeletonData` and call a set-taking helper. Do NOT re-implement the geometry checks the validator already does — call it.
   - **Net-new `SkeletonData`-path checks:** cross-collection **unique non-empty mesh names**, and **widening the slot→attachment accepted-name set** (currently region + clipping names, `model.nim:806-815` region/clip name collection) to include mesh-attachment names — the single structural coupling change.

7. **Nim JSON loader** (`jsonio.nim`): add `"meshAttachments"` to the root key allowlist (`:324`); parse the array into **raw `MeshAttachment` values via the no-`SkeletonData` ctor from step 6** (mirror clipping's `clipAttachmentData` block at `:444-463`), accumulate into a `loadedMeshAttachments` seq, and thread it into the single `skeletonData(...)` assembly at `:695`; add the writer branch (mirror clipping's serialize path) for JSON→JSON round-trip. **No mid-parse ordering hazard** once construction is validation-free: bone-name resolution for weighted influences happens later inside `validateSkeletonData`, after the whole skeleton (including bones) is assembled. The weighted round-trip + unknown-bone-rejection tests confirm this.

8. **Nim BNB loader** (`binary/semantic.nim`): add `meshAttachmentTypeKey = 3001` (mirror `clippingAttachmentTypeKey = 3000` at `:19`); add the write branch (mirror clipping encode `943-948`) and a `var meshes` accumulator + a decode `of meshAttachmentTypeKey:` case (mirror clipping decode `1433-1441`, which builds a raw `clipAttachmentData` value) in the `case record.typeKey` dispatch — build **raw `MeshAttachment` values** via the no-`SkeletonData` ctor from step 6; thread `meshes` into the single `skeletonData(...)` assembly at `:1618`. The three packed `bytes` payloads encode/decode exactly per the contract byte layout, including string-table indices for weighted influence bone names (same string-table mechanism as the `bones` key `4014`).

**Canonical edge-case enumeration (a)–(g)** — one source of truth shared by the contract table, the validation work (step 6), and the tests (Success Criteria). Letters, disposition, where enforced, and the covering test:

| Case | Rule | Disposition | Enforced by | Test |
|------|------|-------------|-------------|------|
| (a) | `uvs.len != vertices.len` | reject | `validateMeshAttachment` (`attachments.nim:84`) | mismatched uvs/vertices length |
| (b) | `triangles.len mod 3 != 0`, or any index `>= vertexCount` | reject | validator (`:89`, `:104-106`) | `triangles mod 3 != 0`; out-of-range triangle index (two tests) |
| (c) | weighted vertex weights don't sum to 1 within `1e-4`, or zero influences | reject | validator (`:128-129`) | weighted weights don't sum to 1 |
| (d) | weighted influence names an unknown bone | reject | validator (`:125-126`), via the bone-name set wired in step 6 | weighted influence names unknown bone |
| (e) | empty mesh (zero vertices or zero triangles) | reject (mesh must have ≥ 1 triangle) | validator (`:82`, `:89`) | empty mesh |
| (f) | mesh in `meshAttachments` referenced by zero slots | **allowed, inert** (no check) | n/a | covered implicitly by the round-trip test (a loaded, unreferenced mesh survives round-trip) |
| (g) | `weighted==false` with non-empty influences, or `weighted==true` with unweighted `(x,y)` payload | reject | validator (`:110-131`) | `weighted`/payload-shape mismatch |

The only **net-new** `SkeletonData`-path checks beyond the validator are **unique non-empty mesh names** and the **slot→attachment widening** (step 6); the 8th test — a slot whose `attachment` names a mesh is **accepted** — exercises that widening (distinct from (f)'s inert-mesh case).

**Packed byte layouts** (pin normatively in the contract): `meshVertices` = `varuint vertexCount`, then when unweighted `vertexCount * (f32 x, f32 y)`; when weighted, per vertex `varuint influenceCount` then `influenceCount * (varuint boneStringIndex, f32 bindX, f32 bindY, f32 weight)`. `meshUvs` = `varuint count` then `count * (f32 u, f32 v)`. `meshTriangles` = `varuint count` then `count * (varuint vertexIndex)`.

**Naming note:** canonical JSON field names are the readable `weighted`/`vertices`/`uvs`/`triangles`, but registry property ids are `meshWeighted`/`meshVertices`/`meshUvs`/`meshTriangles` (plain `vertices` id is already taken by clipping — reusing it hits the duplicate-key error at `generate.py:253`). The hand-written JSON loaders must map each JSON field to its property key rather than assuming field-name == property-id.

Keep the record **minimal**: serialized fields are exactly `name`, `weighted`, `vertices`, `uvs`, `triangles`. Do NOT add deform timelines, linked/parent meshes, sequences, edges/hull, per-vertex color, or a `skinRequired` gate. Out-of-scope `MeshAttachment` fields (`path`, `hull`, `edges`, `parentMesh`, `inheritDeform`, `deformAttachment`) get no registry key/schema — load to defaults if kept on the runtime type.

### Links to Relevant Documentation
- Source prompt: `.agents/big-change-prompts/19-contract-mesh-attachment-format.md` (step 1 of 4 of the M4 mesh-attachment + skinning milestone; precedes prompts 20 runtime eval, 21 conformance, 22 Dart parity)
- Clean room: `docs/CLEANROOM.md` (run the new-identifier checklist for net-new serialized names)
- Provenance: `docs/PROVENANCE.md` (add the mesh-naming entry — names taken from bony's own pre-existing mesh runtime types, not any surveyed product)
- Comparable research: `docs/comparable-feature-set.md` (mesh/deformation named as a capability category ONLY — NOT an implementation source)
- Float math contract: `docs/float-math-contract.md` (specifies the `1e-4` tolerance; note `quantizeF32` is a Nim proc defined in `runtime-nim/src/bony/model.nim`, not in this doc — cite it as source, not as defined here)
- Existing non-serialized Nim mesh runtime this slice wires in: `runtime-nim/src/bony/mesh/attachments.nim` (`MeshAttachment` 26-37, `MeshVertex` 20-24, `MeshUv` 10-12, `MeshInfluence` 14-18, `meshAttachment` ctor 134-161, `validateMeshAttachment` 79, `weightSumTolerance` 7) and `runtime-nim/src/bony/mesh/skinning.nim` (`skinMeshVertices` 35-93, formula 55-69)
- Freshest end-to-end template (mirror closely): the clipping format/load slice — `.agents/big-change-prompts/15-contract-clipping-attachment-format.md` and its landed diff (bead `bony-jkt`); `docs/clipping-attachment-contract.md` as the doc template
- Registry key bands: `registry/key-ranges.md` (M4 = `3000..3999`; next-free typeKey `3001`, next-free propertyKey `3002`)
- Registry source: `registry/wire.yml` (clippingAttachment typeKey 229-234; clipping property block 502-515; bones packed-bytes key 4014 at 614-620; warpControlPoints packed pairs 6026 at 789-795; objects clippingAttachment entry 1083-1088)
- Defaults source of truth: `spec/defaults.yml` (clipping objectDefaults 170-176, requiredProperties 468-475; coverage rule)
- Codegen: `codegen/generate.py` (PACKED_BYTES_METADATA 26-45, coverage 307-315, canonical_json_overrides 571+, wire schema 505-568, root_collection_overrides 480-483, writes 4 files 1285-1292)
- Nim model: `runtime-nim/src/bony/model.nim` (ClipAttachmentData 88-91, SkeletonData collections 248-260, record getters 569-571, clippingAttachments accessor 694; the **single** `skeletonData*` ctor at 1059-1088 with field assign ~1082 — there is no second overload; `validateSkeletonData*` openArray path at 750 with `clippingAttachments` param at 762, and the `SkeletonData` wrapper path at 1091; clipping edge-case checks inlined at 806+)
- Nim JSON loader: `runtime-nim/src/bony/jsonio.nim` (root allowlist 324, clipping load 443-463)
- Nim BNB loader: `runtime-nim/src/bony/binary/semantic.nim` (type-key constants 18-21, clipping encode 943-948, decode dispatch case 1413-1457 with clipping case 1433-1441)
- Docs index: `docs/README.md` (Attachment Contracts section — add the new row)
- Change-detector counts: `runtime-nim/tests/test_smoke.nim` (current: `bonyTypeKeys.len == 27`, `bonyPropertyKeys.len == 97`, `bonyPropertyDefaults.len == 54`, `bonyRequiredProperties.len == 70` at lines 102-105 — adding 1 type + 4 property keys WILL break these; reset to the exact regenerated totals)
- Repo gate: `Makefile` `test` target + `python3 codegen/generate.py --check` + `python3 scripts/ci/schema_validate_assets.py`

### Affected Areas
- **`docs/`** — new `docs/mesh-attachment-contract.md`; edits to `docs/README.md`, `docs/PROVENANCE.md`, `docs/CLEANROOM.md`
- **`registry/wire.yml`** — 1 type key + 4 property keys + 1 `objects:` entry (M4 band only)
- **`spec/defaults.yml`** — objectDefaults + requiredProperties for the mesh properties
- **`codegen/generate.py`** — `PACKED_BYTES_METADATA` + `canonical_json_overrides` entries
- **Generated (regen only, never hand-edit)** — `spec/bony.schema.json`, `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, `runtime-dart/lib/src/generated/wire.dart`
- **`runtime-nim/src/bony/model.nim`** — relocate 4 mesh record types; add `meshAttachments` field/accessor/ctor threading; validation widening
- **`runtime-nim/src/bony/mesh/attachments.nim`** + **`mesh/skinning.nim`** — consume moved types from `model`
- **`runtime-nim/src/bony/jsonio.nim`** — JSON read + write, ordering caveat
- **`runtime-nim/src/bony/binary/semantic.nim`** — BNB read + write, packed bytes + string table
- **`runtime-nim/tests/`** — new round-trip + rejection fixtures/tests; update `test_smoke.nim` key counts
- **No Dart runtime logic, no draw-batch/skinning eval, no conformance rig** (prompts 20–22)

### Success Criteria
- `docs/mesh-attachment-contract.md` exists, is listed in `docs/README.md`, and normatively specifies the model, load-validated invariants + tolerances, the edge-case table (a)–(g), the packed `.bnb` byte layouts (with heading anchors), and the forward-referenced skinning formula/order.
- `registry/wire.yml` gains `meshAttachment` type (`3001`), `meshWeighted` (`3002`, bool), `meshVertices` (`3003`, bytes), `meshUvs` (`3004`, bytes), `meshTriangles` (`3005`, bytes), and an `objects:` entry; `name` is reused; no key collides; all new keys in `3000..3999`.
- `spec/defaults.yml` covers every `meshAttachment` property exactly once across objectDefaults + requiredProperties; `python3 codegen/generate.py --check` passes.
- Codegen regenerated (both schemas + `generated/wire.nim` + `generated/wire.dart`) with no hand-edits; canonical JSON `$defs/meshAttachment` expresses the structured vertex/uv/triangle shape; `python3 scripts/ci/schema_validate_assets.py` passes for all existing assets.
- The four mesh record types live in `model.nim` (moved, no duplication, no new import cycle); `SkeletonData` gains `meshAttachments`; `nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim` is clean.
- A NEW Nim round-trip unit test loads BOTH an unweighted and a weighted mesh from a `.bony` JSON fixture AND its `.bnb`, and asserts the parsed mesh (name, weighted, vertices incl. influences, uvs, triangles) matches across JSON and binary loaders. Load-validation tests cover rejections for: mismatched `uvs`/`vertices` length; `triangles.len mod 3 != 0`; an out-of-range triangle index; a weighted vertex whose weights do not sum to 1; a weighted influence naming an unknown bone; an empty mesh; a `weighted`/payload-shape mismatch; and acceptance of a slot whose `attachment` names a mesh.
- `docs/PROVENANCE.md` gains the mesh-naming entry; the `docs/CLEANROOM.md` new-identifier checklist is satisfied for the net-new serialized names.
- `runtime-nim/tests/test_smoke.nim` key-count assertions (`bonyTypeKeys.len` / `bonyPropertyKeys.len` / `bonyPropertyDefaults.len` / `bonyRequiredProperties.len`) updated to the exact regenerated totals (from 27/97/54/70).
- `make test` passes.

### Constraints
- **Clean-room posture:** do not inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime source, importer source, generated definitions, exact wire layouts, type/property keys, mesh/weight field names, or copied docs prose. The mesh model, field names, weight encoding, and skinning formula are project-owned (they already exist in bony's own `mesh/` runtime).
- Use `docs/comparable-feature-set.md` only to justify the mesh capability category, not its design.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for human/legal review.
- Registry edits: use only the M4 band (`3000..3999`) per `registry/key-ranges.md`, and follow that file's shared-surface reservation rule.
- Land the registry entry, `defaults.yml` entries, `PACKED_BYTES_METADATA`, canonical-JSON overrides, schema regen, and codegen **together** — `validate_sources()` fails if they drift apart.
- Do **NOT** emit a draw batch, change `buildDrawBatches`, apply skinning, add a conformance rig/golden, or touch the Dart runtime. Those are prompts 20, 21, 22. This slice ends when a mesh attachment loads, validates, and round-trips through JSON and `.bnb` — but nothing draws it yet.
- Keep to one meaningful implementation session. Natural cut line if long: **unit A** = contract doc + registry + `PACKED_BYTES_METADATA` + `canonical_json_overrides` + `defaults.yml` + schema regen (all four generated files) landing together with `--check` green; **unit B** = the Nim model relocation + JSON/BNB loaders + validation widening + tests. Do NOT land unit A without unit B in a way that leaves `make test` red.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Check `docs/specs/` and `docs/adr/` for existing architectural decisions (none present in this repo — architectural context lives in `docs/*-contract.md` and `registry/key-ranges.md`)
2. Examine the directory/module structure of the affected areas listed above
3. Identify key interfaces, APIs, and integration points that must be preserved (the `skeletonData(...)` constructor arity, the `validateSkeletonData*` paths, the `case record.typeKey` BNB dispatch, the `validate_sources()` codegen coupling gate)
4. Note existing test patterns and coverage in the affected areas (`runtime-nim/tests/`, `test_smoke.nim` key-count change detector, clipping round-trip/rejection tests as the template)
5. Assess risk areas where changes could break existing functionality (the import-cycle type relocation; the constructor-arity change — the appended param MUST default so the ~62 positional callers, 46 in `test_smoke.nim`, still compile; using a **raw-value** mesh ctor in the loaders and deferring weighted-influence/bone validation to `validateSkeletonData` rather than the `SkeletonData`-taking ctor; the packed-bytes/string-table encoding; the `validate_sources()` land-together drift gate)

Use your analysis to make each bead specific — reference actual file paths, module names, and patterns you observed. Mirror the clipping slice (prompt 15 / bead `bony-jkt`) as the closest landed template throughout.

Then generate a shell script that creates the complete task graph.

**IMPORTANT: Your ONLY deliverable is a bash shell script with `bd create` commands. Not an implementation plan. Not a design document. Not a code review. A runnable `.sh` script.**

Respect the unit-A / unit-B cut line from the Constraints when sequencing dependencies, and encode the `validate_sources()` "land together" coupling as ordering edges so the schema/registry/defaults/regen beads gate the generated-file regen bead, which in turn gates the Nim loader beads.

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
# Change: M4 mesh attachment — loadable/validated/round-trippable format record + contract (format & load only)
# Generated: 2026-07-02

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

EPIC=$(bd create "Epic: M4 mesh attachment format + load (contract, registry, Nim JSON/BNB)" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work — keep it out of `bd ready`

# ... analysis, contract, registry/codegen (unit A), Nim relocation + loaders (unit B),
#     tests, docs/provenance, and final gate beads, all --parent "$EPIC" ...

echo ""
echo "Bead graph created! View with:"
echo "  bd show $EPIC"
echo "  bd children $EPIC"
echo "  bd ready"
```

---

## Bead Creation Guidelines

### Epic / Hierarchy (REQUIRED)
- Create exactly **one parent epic** for the whole change: `EPIC=$(bd create "Epic: <change summary>" -t epic -p 0 --label epic --silent)`.
- Parent **every** task bead to it: add `--parent "$EPIC"` to every `bd create` (children inherit the epic's labels unless you pass `--no-inherit-labels`).
- The epic is a **rollup, not work**: never `bd dep add` to or from it. Membership is `--parent`; `bd dep add` is reserved for real ordering edges *between task beads*.
- **Keep the epic out of `bd ready`** by marking it active right after creation: `bd update "$EPIC" --status in_progress`.
- An epic must have **≥ 2 children** to be meaningful.
- For very large changes you MAY use phase sub-epics, but a single top-level epic is the default.

### Priority Levels
- `-p 0` = Critical (blocking other work, or high-risk changes needing early validation)
- `-p 1` = High (important implementation work)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (cleanup, nice-to-haves)

### Labels (Phase Grouping)
- `analysis` - Understanding current state
- `prep` - Preparation work (characterization tests, feature flags, scaffolding)
- `impl` - Core implementation
- `testing` - Test coverage
- `migration` - Data/code migration
- `docs` - Documentation updates
- `cleanup` - Post-rollout cleanup

### Dependency Rules
1. Never create cycles
2. Analysis tasks should complete before implementation begins
3. Characterization tests should exist before changing code
4. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
5. Parallel work should share a common ancestor, not depend on each other
6. `bd dep add` is for ordering edges **between task beads only**

### Task Granularity
- Each bead should be completable in **under 750 lines of code changed**
- Tasks should be atomic enough for one agent to complete without coordination
- If a task requires multiple file areas, consider splitting by file area

---

## Change-Specific Considerations

### For New Features
- Start with analysis of similar existing features (the clipping slice is the direct template — diff bead `bony-jkt`)
- The mesh runtime math already exists and is tested; this slice wires it into the serialized format, so the "new feature" is the format/load surface, not the geometry algorithms
- Include documentation (contract doc), provenance/cleanroom, and change-detector (`test_smoke.nim`) updates
- No feature flag / gradual rollout needed — an unreferenced mesh in `meshAttachments` is inert (edge case (f))

---

## File Reservation Planning

```bash
# CAUTION — high-coupling / high-contention surfaces:
# codegen coupling: registry/wire.yml + spec/defaults.yml + codegen/generate.py + the 4 generated
#   files must land together — validate_sources() fails on drift. Reserve them as one unit (unit A).
# runtime-nim/src/bony/model.nim — type relocation + constructor arity change; many positional callers.
# runtime-nim/src/bony/binary/semantic.nim — case record.typeKey dispatch; packed bytes + string table.
# runtime-nim/src/bony/jsonio.nim — root allowlist + loader ordering (weighted meshes after bones).
# runtime-nim/tests/test_smoke.nim — key-count change detector; set to regenerated totals last.
```

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check the rollup**: `bd children "$EPIC"` lists every task bead; `bd dep tree` shows them under the epic with no orphan tasks
3. **Check ready work**: `bd ready` shows the analysis/contract/registry tasks and **not** the epic
4. **Check no cycles**: `bd dep cycles` reports none

---

## Completeness Checklist

- [ ] A single parent epic (`-t epic`); every task bead parented to it; no orphan tasks; no blocking dep to/from the epic
- [ ] Analysis of the clipping template + affected `model.nim`/loader seams
- [ ] Contract doc (`docs/mesh-attachment-contract.md`) with normative edge-case table + packed byte layouts + skinning forward-ref
- [ ] Registry (5 keys, M4 band) + `objects:` entry
- [ ] `spec/defaults.yml` coverage (objectDefaults + requiredProperties, each with reason/ownerBead)
- [ ] `PACKED_BYTES_METADATA` + `canonical_json_overrides` + schema/codegen regen (4 generated files) landing together, `--check` green (unit A)
- [ ] Mesh-type relocation into `model.nim` with no import cycle
- [ ] `SkeletonData.meshAttachments` field/accessor/ctor threading + positional-caller updates
- [ ] Validation widening (unique mesh names + slot→attachment accepted set) — no re-implementing validator checks
- [ ] JSON loader read+write with weighted-after-bones ordering
- [ ] BNB loader read+write with packed bytes + string-table for weighted influences
- [ ] New round-trip test (unweighted + weighted, JSON + `.bnb`) + rejection tests for (a)–(g) + slot-accept
- [ ] `test_smoke.nim` key counts updated to regenerated totals
- [ ] PROVENANCE + CLEANROOM entries
- [ ] `make test` + `generate.py --check` + `schema_validate_assets.py` all green
- [ ] Clear dependency chains with no cycles; unit-A gates unit-B
