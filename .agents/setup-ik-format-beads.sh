#!/bin/bash
# Project: bony
# Change: Define project-owned IK constraint format — step 1 of 3
#         (registry keys + codegen-generated JSON schema + Nim data model + contract note)
# Plan:   .agents/plans/ik-constraint-format-registry-schema-model-contract.md
# Generated: 2026-06-29
#
# AS-BUILT: this reproduces the graph AFTER the two-reviewer /ralph-readiness pass.
# Two changes vs. the first draft, both required for autonomous /ralph execution:
#   1. SETUP bead (root Makefile `test` target) added FIRST — ralph's per-iteration
#      VERIFY auto-detects a test runner only for go.mod/package.json/pyproject.toml/
#      Cargo.toml/Makefile; this repo (Nim + Python codegen) has none at root, so
#      without it every iteration's gate runs nothing.
#   2. registry + defaults + codegen + regen MERGED into ONE atomic bead — codegen/
#      generate.py validate_sources() runs unconditionally (generate.py:1262) and
#      fails unless the registry `objects` entry AND defaults coverage land together,
#      so under ralph's merge-to-main model neither half can pass alone or leave main green.
#
# Grounded facts (verified against source):
#   - registry/wire.yml: next-free type key 4002 (path=4000, pathAttachment=4001);
#     next-free property key 4014 (last M5 prop rotateMix=4013).
#     Reuse target=4000 (string), order=4002 (varint), name (shared) — do NOT re-declare.
#   - blendAxes (key 6041, backingType bytes) -> the `axes` canonical_json_overrides()
#     entry is the array-of-strings precedent for `bones` (NOT controlPoints).
#   - codegen/generate.py: PACKED_BYTES_METADATA@26, canonical_json_overrides()@559,
#     schema_for_property()@875, validate_sources@194 (called@1262), 4 artifacts@1264-1267.
#   - runtime-nim/src/bony/model.nim: ckIk first@33, PathConstraintData@77,
#     pathConstraintData*@281, quantizeF32@206, BoneData@51 (no world pos/length).
#
# NOTE: the live Beads/Dolt DB is authoritative. Re-running this in a repo that already
# has these beads will create duplicates — it is provided for reproducibility/audit.

set -e

if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating change beads..."

# ========================================
# Parent epic — rollup only; never a blocking dep, never dispatched as work.
# ========================================

EPIC=$(bd create "Epic: IK constraint format (registry + defaults + codegen + model + contract)" \
  -d "Step 1 of 3 for project-owned IK constraints. Freeze the IK wire/JSON format that step 2 (Nim runtime decode/load/eval) consumes and step 3 (conformance assets) emits. Does NOT wire the solver, add loaders, add binary decode, or add conformance assets (steps 2/3). Clean-room: derive shape from ik.nim solver inputs + path precedent ONLY." \
  -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress   # rollup, not dispatchable work — keep out of `bd ready`

# ========================================
# Phase 0: ralph test-gate bootstrap (gates the whole graph)
# ========================================

SETUP=$(bd create "Add root Makefile 'test' target so ralph VERIFY auto-detects a gate" \
  -d "$(cat <<'EOF'
Create a repo-root Makefile so /ralph's VERIFY step auto-detects a real test runner (this Nim+Python repo has no go.mod/package.json/pyproject.toml/Cargo.toml/Makefile at root, so ralph currently runs NO tests per iteration). Add a Makefile at the repo root with a .PHONY `test` target running exactly:

	python3 codegen/generate.py --check
	python3 -m unittest discover -s codegen -p 'test_*.py'
	nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim

(Use real TAB indentation — Makefile recipes require tabs.) After it lands on main, every later iteration's VERIFY runs the real gate automatically. Acceptance: `make test` passes on the current (pre-IK-change) tree. Scope guard: create ONLY the root Makefile. This is the one acceptable vacuous-auto-VERIFY iteration (the Makefile does not exist yet while being created); /review covers it.
EOF
)" -p 0 --label prep --parent "$EPIC" --silent)

# ========================================
# Phase 1: Analysis & name freeze
# ========================================

ANALYZE=$(bd create "Document the codegen-driven format flow and the path/blendAxes precedents" \
  -d "$(cat <<'EOF'
Read codegen/generate.py end to end: generate_schema, generate_wire_schema, canonical_json_overrides()@559, PACKED_BYTES_METADATA@26, schema_for_property()@875, root_collection_overrides@468, validate_sources@194 (called unconditionally@1262), four write_or_check artifacts@1264-1267. Read the path precedent across registry/wire.yml (type 4000, props 4000-4013, objects '- type: path'@954), spec/defaults.yml (path objectDefaults ~170-191 + requiredProperties ~372-387), runtime-nim/src/bony/model.nim (PathConstraintData@77, pathConstraintData*@281, quantizeF32@206, BoneData@51, ckIk first@33). Read registry/README.md Review Checklist. Confirm next-free keys (type 4002; property 4014+), reused keys (name; target=4000; order=4002), blendAxes packed-bytes precedent (key 6041). Read ik.nim (solveOneBoneIk/solveTwoBoneIk/solveChainIk, requireMix@49).

OUTPUT: write your analysis note to `.agents/notes/ik-format-analysis-note.md` and commit it. SCOPE GUARD: read-and-document only — do NOT edit any registry/defaults/codegen/model source file.
EOF
)" -p 0 --label analysis --parent "$EPIC" --silent)
bd dep add "$ANALYZE" "$SETUP"

FREEZE=$(bd create "Freeze the IK format (source of truth for steps 2 and 3)" \
  -d "$(cat <<'EOF'
Freeze and record in a durable file. top-level array ikConstraints (auto-derived, generate.py:480). Fields+casing: name (required, reuse name key, string minLength 1), bones (required, NEW 4014, bytes), target (required, reuse 4000), order (optional default 0, reuse 4002 varint), mix (optional default 1.0, NEW 4015, f32, [0,1]), bendPositive (optional default true, NEW 4016, bool). bones wire encoding (CENTRAL FREEZE, append-only): backingType bytes packed as varuint count followed by count*(varuint string-table index) per blendAxes (key 6041); JSON = non-empty array of strings. required=[bones,name,target]. bendPositive permitted for all IK but loaded-and-ignored for 1-bone and >=3-bone (only solveTwoBoneIk takes bendSign). bones->solver: chain points = bones' rest-pose world origins ++ [target rest-pose world origin], so #points=#bones+1, #lengths=#bones; 1->solveOneBoneIk, 2->solveTwoBoneIk, >=3->solveChainIk. Lengths rest-pose-derived at runtime, NEVER stored (BoneData no world pos/length, model.nim:51). NOT carried from path: bone(singular), path, position, translateMix, rotateMix.

OUTPUT: write a freeze note to `.agents/notes/ik-format-freeze.md` and commit it. SCOPE GUARD: decision-record only — do NOT edit any registry/defaults/codegen/model source file.
EOF
)" -p 0 --label prep --parent "$EPIC" --silent)
bd dep add "$FREEZE" "$ANALYZE"

# ========================================
# Phase 2: Atomic format landing (registry + defaults + codegen + regen in ONE merge)
# ========================================

FORMAT=$(bd create "registry + defaults + codegen + regen: land ikConstraint format atomically (one merge)" \
  -d "$(cat <<'EOF'
Land the ikConstraint FORMAT atomically across registry + defaults + codegen + regenerated artifacts in ONE merge, so main stays green. These CANNOT merge independently: validate_sources() runs unconditionally (generate.py:1262) and fails if the registry `objects` entry and defaults coverage are not both present; objectDefaults also requires the object be declared in registry objects. Single writer for registry/wire.yml, spec/defaults.yml, codegen/generate.py, and the four generated artifacts.

STEP 1 — registry/wire.yml (append-only; never renumber/repurpose/delete):
- typeKeys: add id ikConstraint, key 4002.
- propertyKeys: add 4014 bones (backingType bytes; doc states 'varuint count followed by count*(varuint string-table index)'), 4015 mix (f32), 4016 bendPositive (bool). Each: status: active, milestone: M5, ownerBead, backingType, doc.
- objects: after '- type: path' (~line 954) add '- type: ikConstraint' listing [name, bones, target, order, mix, bendPositive]. REUSE name/target(4000)/order(4002).

STEP 2 — spec/defaults.yml:
- objectDefaults block for ikConstraint (order=0, mix=1.0, bendPositive=true), each carrying value+omitWhenDefault+applyOnLoad (generate.py:275-281) +optional doc, per path precedent (~170-191).
- requiredProperties for name, bones, target, each with object+property+reason+ownerBead (~46-52; precedent ~372-387).
- Partition all six EXACTLY ONCE: name/bones/target -> required; order/mix/bendPositive -> objectDefaults.

STEP 3 — codegen/generate.py (edit SOURCES, never generated files):
- Add 'bones' to PACKED_BYTES_METADATA@26 (precedent timelineKeys).
- Add ikConstraint to canonical_json_overrides()@559 as a COMPLETE self-contained $def (override REPLACES the whole $def via schema['$defs'].update@449): type:object, additionalProperties:false; bones {type:array, minItems:1, items:{type:string, minLength:1}}, name {type:string, minLength:1}, target {type:string}, order {type:integer, default:0}, mix {type:number, minimum:0, maximum:1, default:1.0}, bendPositive {type:boolean, default:true}; required:[bones,name,target].
- PRECEDENT for the array-of-strings override is the 'axes' entry (blendAxes key 6041) — NOT controlPoints (array of object $refs, wrong shape).

STEP 4 — regenerate + commit ALL FOUR: run `python3 codegen/generate.py` to rewrite spec/bony.schema.json, spec/bony-wire.schema.json, runtime-nim/src/bony/generated/wire.nim, runtime-dart/lib/src/generated/wire.dart. NEVER hand-edit. Commit all four.

GATE (all must pass): yaml-load both sources; python3 codegen/generate.py; python3 codegen/generate.py --check; python3 -m unittest discover -s codegen -p 'test_*.py'; json-load both schemas; make test. Confirm ikConstraints array + ikConstraint $def (array-of-strings bones minItems 1, mix 0..1, required [bones,name,target]) + flat wire $def + Nim/Dart wire tables.

SCOPE GUARD: NO solver/jsonio/loader/binary-decode/pose-pipeline/conformance changes (steps 2/3).
EOF
)" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add "$FORMAT" "$FREEZE"

# ========================================
# Phase 3: Nim model (parallel off FREEZE)
# ========================================

MODEL=$(bd create "runtime-nim/src/bony/model.nim: add IkConstraintData + SkeletonData field + constructor" \
  -d "$(cat <<'EOF'
Single writer for runtime-nim/src/bony/model.nim; must keep compiling. Add IkConstraintData with UNEXPORTED fields mirroring PathConstraintData (model.nim:77): name, bones: seq[string], target, order: int, hasMix/mix, hasBendPositive/bendPositive. Add an ikConstraints field on SkeletonData. Add exported ikConstraintData* constructor mirroring pathConstraintData* (model.nim:281): quantizeF32 on mix (defined model.nim:206) + [0,1] guard matching ik.nim requireMix (ik.nim:49). Drop path's bone/path fields. Do NOT change ConstraintKind order (ckIk first@33).

GATE: nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim (also `make test`). MUST compile but NOT be loaded/evaluated. SCOPE GUARD: no jsonio.nim/loader/binary-decode changes (step 2); touch only model.nim.
EOF
)" -p 0 --label impl --parent "$EPIC" --silent)
bd dep add "$MODEL" "$FREEZE"

# ========================================
# Phase 4: Docs (defaults prose + contract note)
# ========================================

DEFAULTS_MD=$(bd create "spec/DEFAULTS.md: document IK human-facing defaults" \
  -d "Single writer for spec/DEFAULTS.md. Document IK defaults prose: order=0, mix=1.0, bendPositive=true. Secondary to spec/defaults.yml (authoritative). Match existing DEFAULTS.md prose style." \
  -p 2 --label docs --parent "$EPIC" --silent)
bd dep add "$DEFAULTS_MD" "$FORMAT"

CONTRACT=$(bd create "Write docs/ik-constraint-format-contract.md (format contract note)" \
  -d "$(cat <<'EOF'
New file docs/ik-constraint-format-contract.md (repo convention: docs/*-contract.md). Record: (1) frozen top-level key ikConstraints + all field names/casing; (2) bones packed-bytes layout (varuint count + count*(varuint string-table index)), append-only; (3) solver-selection by bones length: 1->solveOneBoneIk, 2->solveTwoBoneIk, >=3->solveChainIk; (4) precise bones->solver mapping: chain points = bones' rest-pose world origins ++ [target rest-pose world origin], #points=#bones+1, #lengths=#bones; origin=first bone; target REST closes the chain (leaf length), target CURRENT is the goal; per-case feed (1: 1 length; 2: parentLength |bone1-bone0|, childLength |target-bone1|; >=3: solveChainIk); world origins FK-composed in step 2 (BoneData no world pos/length, model.nim:51-54); (5) bendPositive permitted-but-ignored for non-two-bone; (6) lengths rest-pose-derived, never stored; (7) IkConstraintData fields unexported. Cross-link docs/constraint-total-order.md.
EOF
)" -p 1 --label docs --parent "$EPIC" --silent)
bd dep add "$CONTRACT" "$FORMAT"
bd dep add "$CONTRACT" "$MODEL"

# ========================================
# Phase 5: Verification gate
# ========================================

VERIFY=$(bd create "Run the format-only verification gate" \
  -d "$(cat <<'EOF'
Run and confirm all pass: yaml-load wire.yml + defaults.yml; python3 codegen/generate.py; python3 codegen/generate.py --check (tree up to date); python3 -m unittest discover -s codegen -p 'test_*.py'; json-load bony.schema.json + bony-wire.schema.json; nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim; python3 scripts/ci/schema_validate_assets.py (existing assets still validate; IK assets arrive in step 3); make test. Confirm registry/key-ranges.md M5 row (line 23) still reads correctly, and that NO solver/loader/binary-decode/pose-pipeline/conformance-asset code was added.
EOF
)" -p 0 --label testing --parent "$EPIC" --silent)
bd dep add "$VERIFY" "$FORMAT"
bd dep add "$VERIFY" "$MODEL"
bd dep add "$VERIFY" "$DEFAULTS_MD"
bd dep add "$VERIFY" "$CONTRACT"

echo ""
echo "Bead graph created! View with:"
echo "  bd show $EPIC          # The parent epic and its rollup"
echo "  bd children $EPIC      # All task beads under the epic"
echo "  bd ready               # Unblocked tasks (starts at SETUP)"
echo "  bd dep cycles          # Should report none"
