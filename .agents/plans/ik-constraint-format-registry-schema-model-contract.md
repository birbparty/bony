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
NEW_FEATURE — adding a new project-owned constraint **format** surface (registry keys + codegen-generated JSON schema + loaded Nim data model + contract note). No existing IK *format* code exists; the IK *solver* already exists but is unreachable.

### Description
Define the project-owned IK (inverse kinematics) constraint **format** — registry keys, the codegen-generated JSON schema surface, the loaded Nim data model, and the format contract note. **This is step 1 of 3.** It freezes the IK wire/JSON format that step 2 (Nim runtime decode/load/eval) consumes and step 3 (conformance assets) emits. Run this slice to completion before steps 2 and 3.

The Nim IK solver already exists at `runtime-nim/src/bony/constraints/ik.nim` (`solveOneBoneIk`, `solveTwoBoneIk`, `solveChainIk`) but no IK constraint can be expressed in `.bony` JSON, decoded from `.bnb`, or loaded into `SkeletonData` — the solver is unreachable dead code. `ConstraintKind` already lists `ckIk` first (`runtime-nim/src/bony/model.nim:33`) and the constraint ordering contract already assigns IK a priority (`docs/constraint-total-order.md`).

This slice closes only the **format** half: it allocates IK registry keys in the M5 band, declares the object's property membership, encodes its defaults/required fields, teaches codegen to emit its JSON shape, regenerates the JSON schemas, defines the in-memory `IkConstraintData` model plus its constructor, and records the format contract. It deliberately does **NOT** wire the solver into the pose pipeline, add the JSON/binary loader, add binary decode, or add conformance assets — those are steps 2 and 3. After this slice the format (keys, names, wire encoding) is frozen so the runtime decode in step 2 has stable keys.

#### CRITICAL: the JSON schema is GENERATED, not hand-authored
`spec/bony.schema.json:5` self-describes as "Generated canonical .bony JSON schema from registry/wire.yml and spec/defaults.yml," and `codegen/generate.py` writes **four** generated artifacts (generate.py:1264-1267): `spec/bony.schema.json` (`SCHEMA_PATH`), `spec/bony-wire.schema.json` (`WIRE_SCHEMA_PATH`), `runtime-nim/src/bony/generated/wire.nim` (`NIM_WIRE_PATH`), and `runtime-dart/lib/src/generated/wire.dart` (`DART_WIRE_PATH`). Adding the IK type/property keys and the objects membership entry changes `generate_nim`/`generate_dart` output too, so **all four** files are rewritten by the regen and must be committed; `python3 codegen/generate.py --check` fails if ANY of the four is stale. **Never hand-edit any of these four generated files** — hand edits are clobbered on the next regen and fail the freshness gate that `registry/README.md` mandates for any registry edit. The generated files are downstream artifacts; the *sources* are `registry/wire.yml`, `spec/defaults.yml`, and the codegen overrides in `codegen/generate.py`. (The Dart wire file regenerates mechanically even though Dart runtime work is otherwise out of scope — it must still be regenerated and committed to keep `--check` green.)

The generation flow that this slice must feed (all verified in `codegen/generate.py`):
1. **`registry/wire.yml` `typeKeys`** — add `ikConstraint` (next free type key `4002`; path=4000, pathAttachment=4001). The top-level JSON collection name is auto-derived as `object_id + "s"` (generate.py:480) → `ikConstraint` ⇒ **`ikConstraints`** automatically; no `root_collection_overrides` entry is needed.
2. **`registry/wire.yml` `propertyKeys`** — add IK-specific keys (next free property key `4014`; rotateMix=4013 is the current last M5 property key). Reuse the shared `target` (4000), `order` (4002), and the generic `name` property key; do NOT re-declare them.
3. **`registry/wire.yml` `objects:` block** (line ~920; `- type: path` at ~954) — add a `- type: ikConstraint` entry listing its property ids in order. Without this membership entry the object `$def` will not generate and `validate_sources` errors.
4. **`spec/defaults.yml`** — add an `objectDefaults` block and `requiredProperties` entries for `ikConstraint`. This is the authoritative source for the generated `required` array and `default` values (path precedent: `objectDefaults` ~170-191, `requiredProperties` ~372-387). The validator requires **every** object property to appear exactly once across `objectDefaults.properties` ∪ `requiredProperties` (defaults.yml rule ~65), so all six fields must be partitioned between the two lists.
5. **`codegen/generate.py`** — the flat wire schema auto-derives each property's JSON shape from its `backingType` via `schema_for_property` (generate.py:875), but the human-facing canonical JSON `$def` for any object whose JSON shape differs from the flat wire form is **hand-curated in `canonical_json_overrides()`** (generate.py:559) and overrides the auto shape (generate.py:449). Because `bones` is a bytes-packed list (see below) that must appear in JSON as an **array of strings** (not the auto base64 string), this slice MUST add an `ikConstraint` entry to `canonical_json_overrides()` AND a `bones` entry to `PACKED_BYTES_METADATA` (generate.py:26; precedent `timelineKeys`, and `controlPoints` for the array-shaped override).
6. **Regenerate** by running `python3 codegen/generate.py`, which rewrites all four generated artifacts: `spec/bony.schema.json`, `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, and `runtime-dart/lib/src/generated/wire.dart`. Commit all four.

#### IK data shape — decide and FREEZE in this slice
Derived from the existing `ik.nim` solver inputs and the `path` precedent, NOT from any third-party format. Final JSON names + casing (the source of truth for steps 2 and 3):

| JSON field | Required? | Default | Registry property key | backingType | Notes |
|---|---|---|---|---|---|
| `name` | required | — | reuse `name` | string | `minLength: 1` |
| `bones` | required | — | **new `4014`** | **bytes** (packed) | ordered bone names, root→tip; JSON = non-empty array of strings |
| `target` | required | — | reuse `target` (4000) | string | bone name whose world position is the IK goal |
| `order` | optional | `0` | reuse `order` (4002) | varint | signed global constraint order |
| `mix` | optional | `1.0` | **new `4015`** | f32 | range `[0,1]` (solver `mix`) |
| `bendPositive` | optional | `true` | **new `4016`** | bool | maps to solver `bendSign` (`true`→+1, `false`→-1) |

Top-level array key: **`ikConstraints`** (auto-derived; frozen).

**`bones` wire encoding — frozen now (this is the central freeze decision).** The `backingTypes` enum (`wire.yml:96-120`) is scalar-only — `varuint, varint, f32, bool, string, color, bytes, f64` — there is NO list/repeated backing type. The repo's idiom for a packed list inside one property key is `backingType: bytes` with a documented sub-layout. **Direct precedent: `blendAxes` (key 6041, `backingType: bytes`, "packed as varuint count followed by count*(varuint string-table index for axis name)").** Freeze `bones` identically: `backingType: bytes`, packed as **varuint count followed by count × varuint string-table index** (each index referencing a bone name in the string table). Record this byte layout in the contract note; step 2's binary decode inherits it and the append-only rule forbids changing it later. (Do NOT model `bones` as owned child records — that idiom is reserved for structured multi-field children like `stateMachineLayer`; a flat list of names is a packed-bytes property.)

**Which `path` fields are intentionally NOT carried over.** Although the implementation mirrors the `path` precedent's *structure* (registry entry style, `has*` optional flags, constructor with `quantizeF32`/range guards), the IK object deliberately **drops** path's `bone` (singular), `path`, `position`, `translateMix`, and `rotateMix` fields and **adds** `bones` (plural list), `mix`, and `bendPositive`. "Mirror path exactly" refers to *form and conventions*, not field set — do not carry over a spurious `bone` or `path` field.

**Binding decision — segment lengths are computed at runtime from rest-pose world positions and are NEVER stored in the format.** Do not allocate per-segment length keys. `BoneData` (`model.nim:51-54`) stores only `name`/`parent`/`local` — bone **world origins are FK-composed** along the parent chain (not stored), and there is **no bone-length/tip field** anywhere in the model. The leaf (tip) bone therefore has no successor to derive its length from; the chain is closed by the **target bone's rest-pose world origin**. Frozen mapping: the chain points are the `bones`' rest-pose world origins **followed by the `target` bone's rest-pose world origin**, so `#points = #bones + 1` and `#lengths = #bones` (one per bone, including the leaf). The `target` thus plays a dual role — its **rest-pose** position closes the chain (supplying the leaf bone's length) and its **current/animated** position is the goal the solver drives toward. This feeds each solver exactly: 1 bone → `solveOneBoneIk` (origin = bone0 rest origin, 1 length = `|target − bone0|`); 2 bones → `solveTwoBoneIk` (parentLength = `|bone1 − bone0|`, childLength = `|target − bone1|`); ≥3 bones → `solveChainIk` (`points.len = #bones+1 ≥ 2`, `lengths.len = points.len − 1`). The contract note must record this mapping and that world origins are FK-derived in step 2 (the earlier "target is NOT a chain point / `#lengths = #bones − 1`" framing is wrong — it underfeeds the 1- and 2-bone solvers).

### Links to Relevant Documentation
- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research (capability categories ONLY): `docs/comparable-feature-set.md`
- Registry key bands: `registry/key-ranges.md` (M5 = `4000..4999`; row 23 already reads "IK, transform, path, and physics constraints")
- Registry format, conventions, and **Review Checklist** (mandates codegen `--check` + codegen unit tests for any `registry/**` edit): `registry/wire.yml`, `registry/README.md`
- Codegen (schema generator + tests): `codegen/generate.py`, `codegen/test_generate.py`, `codegen/README.md`
- Defaults source (authoritative for required/defaults): `spec/defaults.yml`; human-facing prose: `spec/DEFAULTS.md`
- Generated schemas (DO NOT hand-edit): `spec/bony.schema.json`, `spec/bony-wire.schema.json`; `spec/README.md`
- Constraint ordering contract: `docs/constraint-total-order.md`
- Existing IK solver (reference only — DO NOT modify in this slice): `runtime-nim/src/bony/constraints/ik.nim`
- Loaded-asset model: `runtime-nim/src/bony/model.nim`; loaded-asset shape doc: `docs/nim-loaded-asset-shape.md`
- JSON loader root-key validation (reference only; changed in step 2): `runtime-nim/src/bony/jsonio.nim:311`
- Schema-validation gate: `scripts/ci/schema_validate_assets.py`

### Affected Areas
Files this slice WILL modify (format sources only):
- `registry/wire.yml` — append type key `4002` (`ikConstraint`); append IK-specific property keys `4014` (`bones`, `bytes`), `4015` (`mix`, `f32`), `4016` (`bendPositive`, `bool`), each with `status: active`, `milestone: M5`, `ownerBead`, `backingType`, and a `doc` string (the `bones` doc must state the packed layout). Add the `- type: ikConstraint` membership entry to the `objects:` block listing `[name, bones, target, order, mix, bendPositive]`. Reuse `name`/`target`/`order` — do NOT re-declare. Append-only: no renumber/repurpose/delete.
- `spec/defaults.yml` — add an `objectDefaults` block for `ikConstraint` (with `object`, `ownerBead`, and a `properties` map) defaulting `order`=0, `mix`=1.0, `bendPositive`=true, where **each** property default carries `value`, `omitWhenDefault`, AND `applyOnLoad` (all three are validator-required, generate.py:275-277), plus an optional `doc` — matching the `path` precedent (defaults.yml:170-191). Add `requiredProperties` entries for `name`, `bones`, `target`, each with `object`, `property`, `reason`, AND `ownerBead` (all four required by the documented `entrySchemas`, defaults.yml:46-52; precedent 372-387). Ensure all six properties are partitioned exactly once across `objectDefaults` ∪ `requiredProperties`.
- `codegen/generate.py` — add `bones` to `PACKED_BYTES_METADATA` (packed-bytes layout/validation metadata, precedent `timelineKeys`); add an `ikConstraint` entry to `canonical_json_overrides()` as a **complete** object def (`"type": "object"`, `"additionalProperties": false` — every sibling override sets these and this is a format freeze) presenting `bones` as `{type: array, minItems: 1, items: {type: string, minLength: 1}}`, plus `name`/`target`/`order`/`mix`/`bendPositive` with the right types, defaults, and `mix` range `0..1`, and `required: [bones, name, target]`. (The override REPLACES the whole `$def` via `schema["$defs"].update(...)` at generate.py:449, so it must be self-complete.)
- `spec/bony.schema.json`, `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, **and** `runtime-dart/lib/src/generated/wire.dart` — all regenerated by running `python3 codegen/generate.py` (NOT hand-edited) and committed. Confirm the `ikConstraints` top-level array, the `ikConstraint` `$def`, and the flat wire `$def` appear in the JSON schemas, and that the Nim/Dart wire tables gain the `ikConstraint` object spec + new ids/keys.
- `runtime-nim/src/bony/model.nim` — add `IkConstraintData` object (unexported fields, mirroring `PathConstraintData`'s style: `name`, `bones: seq[string]`, `target`, `order: int`, `hasMix`/`mix`, `hasBendPositive`/`bendPositive`); add an `ikConstraints` field on `SkeletonData`; add an `ikConstraintData*` constructor mirroring `pathConstraintData*` (`quantizeF32` on `mix` + `[0,1]` guard, matching `ik.nim`'s `requireMix`). Must compile; must NOT be loaded or evaluated here.
- `registry/key-ranges.md` — no band change required; confirm the M5 row (line 23) still reads correctly.
- `spec/DEFAULTS.md` — update the human-facing prose to mention IK defaults (secondary to `defaults.yml`).
- New `docs/ik-constraint-format-contract.md` — the format contract note (see Contract requirements).

Files referenced but NOT modified in this slice (touched in steps 2/3):
- `runtime-nim/src/bony/constraints/ik.nim` (solver — reference only)
- `runtime-nim/src/bony/jsonio.nim` (`validateKnownKeys` allow-list + loader — step 2)
- `scripts/ci/schema_validate_assets.py` (existing assets must still validate; IK conformance assets arrive in step 3)

Architectural-context note: this repo has no `docs/specs/` or `docs/adr/` directories; contract/design decisions live in `docs/*-contract.md` / `docs/*-design.md` notes. Follow that convention for the new contract note.

#### Contract requirements (`docs/ik-constraint-format-contract.md`)
The contract note MUST record:
- The frozen top-level key (`ikConstraints`) and all field names + casing.
- The `bones` packed-bytes wire layout (varuint count + count × varuint string-table index) and that it is append-only.
- The **solver-selection rule by `bones` length**: 1 → `solveOneBoneIk`, 2 → `solveTwoBoneIk`, ≥3 → `solveChainIk`.
- The **precise mapping from `bones` (names) to solver inputs**, resolving the bone-vs-point mismatch. The solvers consume joint *points* with `#lengths = #points − 1` (`solveChainIk` requires `points.len ≥ 2`). Freeze: chain points = the `bones`' rest-pose world origins **followed by the `target` bone's rest-pose world origin**, giving `#points = #bones + 1` and `#lengths = #bones`. Origin = first bone's rest-pose world origin. The `target` bone's **rest-pose** position closes the chain (supplying the leaf bone's length); its **current** position is the goal. Spell out the per-case feed: 1 bone → `solveOneBoneIk` (1 length); 2 bones → `solveTwoBoneIk` (parentLength `|bone1−bone0|`, childLength `|target−bone1|`); ≥3 → `solveChainIk`. Note that `BoneData` stores no world position or length (model.nim:51-54): world origins are FK-composed from `local` transforms along the parent chain in step 2, and the no-stored-lengths freeze is sound only because the target rest-pose origin closes the chain.
- The **`bendPositive` behavior outside the two-bone case** (only `solveTwoBoneIk` takes `bendSign`): freeze that `bendPositive` is permitted in the schema for any IK constraint but is **loaded-and-ignored** for 1-bone and ≥3-bone constraints (no load error). State this explicitly so step 3 conformance assets encode the agreed behavior.
- The binding decision that segment lengths are rest-pose-derived at runtime and never stored.
- That `IkConstraintData` fields are unexported (matching `PathConstraintData`), so step 2 reads them via the module's accessors/loader, not direct field access.

### Success Criteria
- `registry/wire.yml` gains the `ikConstraint` type key (`4002`), the IK property keys (`4014` bones/bytes, `4015` mix/f32, `4016` bendPositive/bool), and the `- type: ikConstraint` objects membership entry — all within `4000..4999`, each key with `status`/`milestone: M5`/`ownerBead`/`backingType`/`doc`. `registry/key-ranges.md` M5 row still reads correctly.
- `spec/defaults.yml` gains `objectDefaults` (`order`=0, `mix`=1.0, `bendPositive`=true) and `requiredProperties` (`name`, `bones`, `target`) for `ikConstraint`, with every property partitioned across the two lists.
- `codegen/generate.py` gains the `bones` `PACKED_BYTES_METADATA` entry and the `ikConstraint` `canonical_json_overrides()` entry.
- Running `python3 codegen/generate.py` regenerates all four artifacts (`spec/bony.schema.json`, `spec/bony-wire.schema.json`, `runtime-nim/src/bony/generated/wire.nim`, `runtime-dart/lib/src/generated/wire.dart`) so that: the top-level `ikConstraints` array exists; the `ikConstraint` `$def` is `type: object`/`additionalProperties: false` and carries `bones` (array of strings, `minItems: 1`, items `minLength: 1`), `target`, `order`, optional `mix` (`0..1`), optional `bendPositive`, with `required: [bones, name, target]`; the flat wire `$def` reflects the registry; and the Nim/Dart wire tables gain the `ikConstraint` spec. All four generated files are committed, and `python3 codegen/generate.py --check` reports the tree up to date afterward.
- `runtime-nim/src/bony/model.nim` gains `IkConstraintData`, an `ikConstraints` field on `SkeletonData`, and an `ikConstraintData*` constructor mirroring `pathConstraintData*`. Model compiles; it is NOT yet loaded or evaluated (that is step 2).
- `docs/ik-constraint-format-contract.md` records every item under "Contract requirements" above.
- NO solver code, loader code, binary decode, pose-pipeline integration, or conformance asset is added in this slice.
- Verification gate (format-only; all must pass):
  ```bash
  python3 -c "import yaml,sys; yaml.safe_load(open('registry/wire.yml'))"
  python3 -c "import yaml,sys; yaml.safe_load(open('spec/defaults.yml'))"
  python3 codegen/generate.py                       # regenerate both schemas
  python3 codegen/generate.py --check               # tree is up to date
  python3 -m unittest discover -s codegen -p 'test_*.py'
  python3 -c "import json,sys; json.load(open('spec/bony.schema.json'))"
  python3 -c "import json,sys; json.load(open('spec/bony-wire.schema.json'))"
  nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim
  python3 scripts/ci/schema_validate_assets.py || true   # existing assets must still validate; IK assets arrive in step 3
  ```

### Constraints
- **Clean-room posture (hard gate):** do not inspect or derive from DragonBones, Spine, Rive, Live2D, or Lottie runtime source, importer source, generated definitions, exact wire layouts, type/property keys, or copied docs prose. The IK data shape MUST be derived from the existing `ik.nim` solver inputs and the `path`-constraint precedent only.
- Use `docs/comparable-feature-set.md` for capability **categories** only.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- **IK only.** Do not define, register, or schema transform constraints or physics constraints; their solvers remain unwired and out of scope for this milestone.
- **Append-only registry:** never renumber, repurpose, or delete an existing key. Allocate from the free M5 band (`4002` type; `4014`–`4016` property) only. Once chosen, the `bones` `backingType` and packed layout are frozen for the lifetime of the format.
- Do NOT change the `ConstraintKind` enum order — `ckIk` is already first and `docs/constraint-total-order.md` derives priority from it.
- Do NOT hand-edit `spec/bony.schema.json` or `spec/bony-wire.schema.json` — regenerate via `codegen/generate.py`.
- Keep the slice small enough for one meaningful implementation session.

---

## Your Task

Analyze this codebase change and create a comprehensive **Beads task graph** using the `bd` CLI. Beads provides dependency-aware, conflict-free task management for multi-agent execution.

Before creating the task graph, you MUST first analyze the affected areas of the codebase:

1. Read the codegen flow end to end (`codegen/generate.py`: `generate_schema`, `generate_wire_schema`, `canonical_json_overrides`, `PACKED_BYTES_METADATA`, `schema_for_property`, `root_collection_overrides`) and `codegen/README.md` so the schema tasks edit *sources*, not generated output.
2. Read the `path` precedent across `registry/wire.yml` (type 4000, props 4000-4013, objects `- type: path`), `spec/defaults.yml` (objectDefaults/requiredProperties for path), and `runtime-nim/src/bony/model.nim` (PathConstraintData/constructor).
3. Read `registry/README.md`'s Review Checklist and confirm the codegen `--check` + unittest commands.
4. Confirm the next-free keys (type `4002`; property `4014`+), the reused keys (`name`, `target` 4000, `order` 4002), and the `blendAxes` packed-bytes precedent for `bones`.
5. Read `runtime-nim/src/bony/constraints/ik.nim` to ground the `bones`→solver-inputs mapping and the rest-pose-length decision.
6. Assess risk: hand-editing generated schemas (forbidden), missing the `objects:` membership entry, missing `defaults.yml` entries, a nonexistent `bones` backing type, missing codegen overrides, accidental solver/loader wiring (out of scope).

Use your analysis to make each bead specific — reference actual file paths, line numbers, and the `path`/`blendAxes` precedents.

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
# Change: Define project-owned IK constraint format (registry + defaults + codegen + model + contract)
# Generated: 2026-06-29

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

EPIC=$(bd create "Epic: IK constraint format (registry + defaults + codegen + model + contract)" -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work — keep it out of `bd ready`

# ========================================
# Phase 1: Analysis & name freeze
# ========================================

ANALYZE=$(bd create "Document the codegen-driven format flow and the path precedent: codegen/generate.py (generate_schema/generate_wire_schema/canonical_json_overrides/PACKED_BYTES_METADATA/schema_for_property/root_collection_overrides), registry/wire.yml path entries (type 4000, props 4000-4013, objects '- type: path'), spec/defaults.yml path objectDefaults/requiredProperties, and model.nim PathConstraintData. Capture next-free keys (type 4002, property 4014+), reused keys (name, target 4000, order 4002), and the blendAxes packed-bytes precedent (key 6041)" -p 0 --label analysis --parent "$EPIC" --silent)

FREEZE=$(bd create "Freeze the IK format: top-level array ikConstraints (auto-derived); fields name, bones, target, order, mix, bendPositive; bones wire encoding = backingType bytes packed as varuint count + count*(varuint string-table index) per blendAxes precedent; required name/bones/target; defaults order=0/mix=1.0/bendPositive=true; bendPositive permitted-but-ignored for non-two-bone; bones->solver mapping and rest-pose-length rule. This output is the source of truth for steps 2 and 3 and for all downstream tasks" -p 0 --label prep --parent "$EPIC" --silent)
bd dep add $FREEZE $ANALYZE

# ========================================
# Phase 2: Registry + defaults sources
# ========================================

REGISTRY=$(bd create "registry/wire.yml: append type key 4002 (ikConstraint); append property keys 4014 bones(bytes, doc states packed varuint count + count*(varuint string-table index)), 4015 mix(f32), 4016 bendPositive(bool), each with status/milestone:M5/ownerBead/backingType/doc; add objects entry '- type: ikConstraint / properties: [name, bones, target, order, mix, bendPositive]'. Reuse name/target/order; do not re-declare. Append-only" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGISTRY $FREEZE

DEFAULTS=$(bd create "spec/defaults.yml: add objectDefaults block for ikConstraint (object, ownerBead, properties map) defaulting order=0/mix=1.0/bendPositive=true where each property carries value+omitWhenDefault+applyOnLoad (all three, validator-required) +optional doc, per path precedent; add requiredProperties entries for name/bones/target each with object+property+reason+ownerBead. Partition all six properties exactly once across objectDefaults and requiredProperties" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $DEFAULTS $FREEZE

# ========================================
# Phase 3: Codegen overrides + schema regen
# ========================================

CODEGEN=$(bd create "codegen/generate.py: add bones to PACKED_BYTES_METADATA (packed-bytes layout/validation metadata, precedent timelineKeys); add ikConstraint to canonical_json_overrides() as a complete object def (type:object, additionalProperties:false) with bones as {type:array, minItems:1, items:{type:string, minLength:1}}, name(minLength 1), target(string), order(integer default 0), mix(number 0..1 default 1.0), bendPositive(bool default true), required [bones, name, target]. The override replaces the whole \$def so it must be self-complete" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CODEGEN $REGISTRY
bd dep add $CODEGEN $DEFAULTS

REGEN=$(bd create "Regenerate all four artifacts: run python3 codegen/generate.py to rewrite spec/bony.schema.json, spec/bony-wire.schema.json, runtime-nim/src/bony/generated/wire.nim, and runtime-dart/lib/src/generated/wire.dart; commit all four. Confirm top-level ikConstraints array, the ikConstraint \$def (type:object/additionalProperties:false, bones array of strings minItems 1, target, order, mix 0..1, bendPositive, required [bones,name,target]), the flat wire \$def, and the Nim/Dart wire tables gain ikConstraint. Do NOT hand-edit any generated file" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGEN $CODEGEN

# ========================================
# Phase 4: Nim model
# ========================================

MODEL=$(bd create "runtime-nim/src/bony/model.nim: add IkConstraintData (unexported fields: name, bones seq[string], target, order int, hasMix/mix, hasBendPositive/bendPositive), add ikConstraints field on SkeletonData, add ikConstraintData* constructor mirroring pathConstraintData* (quantizeF32 mix + [0,1] guard per ik.nim requireMix). Drop path's bone/path fields. Must compile; do NOT load or evaluate" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $MODEL $FREEZE

# ========================================
# Phase 5: Docs (defaults prose + contract note)
# ========================================

DEFAULTS_MD=$(bd create "spec/DEFAULTS.md: document IK human-facing defaults (order=0, mix=1.0, bendPositive=true), secondary to defaults.yml" -p 2 --label docs --parent "$EPIC" --silent)
bd dep add $DEFAULTS_MD $DEFAULTS

CONTRACT=$(bd create "Write docs/ik-constraint-format-contract.md: frozen JSON names/casing; bones packed-bytes layout (append-only); solver-selection-by-bones-length; precise bones-names->solver-inputs mapping: chain points = bones rest-pose world origins ++ [target rest-pose world origin], so #points=#bones+1 and #lengths=#bones; origin=first bone; target REST position closes the chain (leaf bone length), target CURRENT position is the goal; world origins are FK-composed (BoneData has no stored world pos/length, model.nim:51-54); bendPositive permitted-but-ignored for non-two-bone; rest-pose-derived-lengths binding decision; IkConstraintData fields unexported. Cross-link constraint-total-order.md" -p 1 --label docs --parent "$EPIC" --silent)
bd dep add $CONTRACT $REGEN
bd dep add $CONTRACT $MODEL

# ========================================
# Phase 6: Verification gate
# ========================================

VERIFY=$(bd create "Run format-only verification gate: yaml load wire.yml + defaults.yml; python3 codegen/generate.py then --check (tree up to date); python3 -m unittest discover -s codegen -p 'test_*.py'; json.load bony.schema.json + bony-wire.schema.json; nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim; python3 scripts/ci/schema_validate_assets.py (existing assets still validate). Confirm key-ranges.md M5 row, and that NO solver/loader/decode/pipeline/conformance code was added" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $VERIFY $REGEN
bd dep add $VERIFY $MODEL
bd dep add $VERIFY $DEFAULTS_MD
bd dep add $VERIFY $CONTRACT

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
- The epic is a **rollup, not work**: never `bd dep add` to or from it. Membership is `--parent`; `bd dep add` is reserved for real ordering edges *between task beads*.
- **Keep the epic out of `bd ready`** by marking it active right after creation: `bd update "$EPIC" --status in_progress`.
- An epic must have **≥ 2 children** to be meaningful.

### Priority Levels
- `-p 0` = Critical (blocking other work, or high-risk changes needing early validation)
- `-p 1` = High (important implementation work)
- `-p 2` = Medium (standard work)
- `-p 3` = Low (cleanup, nice-to-haves)

### Labels (Phase Grouping)
- `analysis` - Understanding current state
- `prep` - Name/format freeze
- `impl` - Core implementation (registry, defaults, codegen, regen, model)
- `testing` - Verification gate
- `docs` - Documentation (defaults prose, contract note)
- `cleanup` - Post-rollout cleanup

### Dependency Rules
1. Never create cycles
2. Analysis + format freeze complete before implementation begins
3. Use `bd dep add CHILD PARENT` (child depends on parent completing first)
4. **Schema regen is downstream**: `REGISTRY` and `DEFAULTS` (parallel, both depend on `FREEZE`) → `CODEGEN` → `REGEN`. `MODEL` runs in parallel off `FREEZE`. Do NOT model the schema as a sibling of the registry.
5. `bd dep add` is for ordering edges **between task beads only** — never attach a task to the epic with it

### Task Granularity
- Each bead should be completable in **under 750 lines of code changed**
- Split by source seam: registry, defaults, codegen overrides, schema regen, model, defaults-prose, contract, verify

---

## Change-Specific Considerations

### For New Features
- Start with analysis of the closest existing feature (the `path` constraint) **and the codegen flow** — the single biggest risk is treating the generated schema as hand-editable.
- This is a format-freeze slice: the deliverable is a stable contract, not behavior. There is no feature flag and no runtime rollout. The load-bearing output is name/casing/wire-encoding stability across registry ↔ defaults ↔ codegen ↔ generated schema ↔ model ↔ (future) loader.
- Treat the freeze task as first-class: every downstream task consumes its frozen decisions (especially the `bones` packed-bytes layout, which append-only rules make irreversible).

---

## File Reservation Planning

```bash
# Reservation notes (add as bead descriptions):
# registry/wire.yml             — append-only; single writer (REGISTRY task)
# spec/defaults.yml             — single writer (DEFAULTS task)
# codegen/generate.py           — single writer (CODEGEN task)
# spec/bony.schema.json,
# spec/bony-wire.schema.json,
# runtime-nim/src/bony/generated/wire.nim,
# runtime-dart/lib/src/generated/wire.dart — GENERATED; only the REGEN task touches them, via codegen (never hand-edit); commit all four
# runtime-nim/src/bony/model.nim— single writer (MODEL task); must keep compiling
# spec/DEFAULTS.md              — single writer (DEFAULTS_MD task)
# docs/ik-constraint-format-contract.md — new file (CONTRACT task)
# DO NOT TOUCH: ik.nim, jsonio.nim, schema_validate_assets.py (steps 2/3)
```

---

## Verification Steps

After generating the script:

1. **Run it**: `chmod +x setup-beads.sh && ./setup-beads.sh`
2. **Check the rollup**: `bd children "$EPIC"` lists every task bead; `bd dep tree` shows them under the epic with no orphan tasks
3. **Check ready work**: `bd ready` shows the analysis/freeze tasks and NOT the epic
4. **Check no cycles**: `bd dep cycles` reports none

---

## Completeness Checklist

- [ ] A single parent epic (`-t epic`); every task bead parented via `--parent "$EPIC"`; no orphan tasks; no blocking dep to/from the epic
- [ ] Analysis of the codegen flow AND the `path`/`blendAxes` precedents
- [ ] Format freeze task (names, bones packed-bytes layout, defaults, bendPositive rule, bones→solver mapping) consumed by all downstream tasks
- [ ] Registry task (type 4002 + props 4014-4016 + objects membership entry; reuse name/target/order)
- [ ] Defaults task (`defaults.yml` objectDefaults + requiredProperties, all props partitioned)
- [ ] Codegen task (`PACKED_BYTES_METADATA` + `canonical_json_overrides` for ikConstraint)
- [ ] Schema regen task (run `generate.py`; verify + commit all FOUR generated files: both JSON schemas + nim/dart wire; never hand-edit)
- [ ] Model task (`IkConstraintData` + field + constructor, unexported fields, compiles only)
- [ ] Defaults-prose task (`DEFAULTS.md`)
- [ ] Contract-note task (all Contract requirements)
- [ ] Verification task running the full gate incl. codegen `--check` + codegen unit tests
- [ ] Correct dependency chain: FREEZE → {REGISTRY, DEFAULTS} → CODEGEN → REGEN; MODEL ∥ off FREEZE; no cycles
- [ ] Explicit out-of-scope guard: no solver/loader/decode/pipeline/conformance changes; no hand-edited schemas
```
