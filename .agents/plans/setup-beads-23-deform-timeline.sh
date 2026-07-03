#!/bin/bash
# Project: bony
# Change: Introduce clip-owned deformTimeline FORMAT CONTRACT (M4 registry keys +
#         canonical JSON / wire schema + regenerated codec artifacts). Contract +
#         schema/registry/codegen ONLY — no runtime loader, no AnimationClip/mixer/
#         draw-batch wiring, no conformance rig, no Dart logic. Prompt 23 of 4 in
#         the M4 deform-timeline milestone (24 = load/round-trip, 25 = conformance,
#         26 = Dart parity).
# Source prompt: .agents/big-change-prompts/23-contract-deform-timeline-format.md
# Generated: 2026-07-03
#
# Facts below were GROUNDED against the live tree before generation:
#   deform.nim: MeshDelta(x,y: float64) @8-10; DeformKeyframe(time, offset: uint32,
#     deltas: seq[MeshDelta], curve: TimelineCurve) @12-16; DeformTimeline(skin, slot,
#     attachment, vertexCount, KEYS: seq[DeformKeyframe]) @18-23 — NOTE the keyframe
#     list field is `keys`, not `keyframes`; validateDeformTimeline @66-80 (non-empty
#     skin check @67-68); deformTimeline ctor @83-95; sampleDeformDeltas @112-137;
#     applyDeformDeltas @140-153; applyDeformTimeline @156-166.
#   model.nim: MeshAttachment @109, deformAttachment*: string @120.
#   timelines.nim: TimelineCurveKind @8-11, TimelineCurve @13-18; AnimationClip @137-142
#     has boneTimelines/slotTimelines/eventTimelines, NO deformTimelines.
#   registry/wire.yml: typeKeys 3000(clipping)/3001(mesh) spent -> 3002 free;
#     propertyKeys 3000-3005 spent -> 3006/3007/3008/3009 free; slotTimeline typeKey=2002
#     @319-324; slotIndex=2002/timelineKeys=2004(bytes) @914-930; slotTimeline objects
#     entry @1241-1246 props [slotIndex, slotTimelineKind, timelineKeys]; animationClip
#     objects entry @1231-1234 doc "Animation clip parent record; followed immediately by
#     owned boneTimeline and slotTimeline records."; bones string-table bytes key=4014.
#   generate.py: PACKED_BYTES_METADATA @26-63 (keyed by property id; timelineKeys layout
#     -> docs/binary-animation-state-machine-object-families.md#keyframe-payloads;
#     meshVertices -> docs/mesh-attachment-contract.md#packed-meshvertices-byte-layout-bnb);
#     coverage rule @321-339; canonical_json_overrides() @589 ($defs merged @479);
#     animationClip override literal @786-803 (additionalProperties:False, only
#     name/boneTimelines/slotTimelines); x-bony-packedBytes stamp @994-995; --check @1379;
#     4 outputs written @1387-1390.
#   spec/defaults.yml: objectDefaults @99, requiredProperties @446; meshAttachment
#     requiredProperties template @483-498 (each entry carries reason + ownerBead).
#   test_smoke.nim: bonyTypeKeys.len==28 @112, bonyPropertyKeys.len==101 @113,
#     bonyPropertyDefaults.len==55 @114, bonyRequiredProperties.len==74 @115.

set -e

# Initialize beads if needed
if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating deformTimeline format-contract beads..."

# ========================================
# Parent epic — every task below is parented to it (--parent "$EPIC").
# Organizational rollup only: NEVER a blocking dep (no `bd dep add` to/from it),
# never dispatched as work. Marked in_progress so it stays out of `bd ready`.
# Cite "$EPIC" as the owning/milestone bead in new registry/defaults `doc`/`ownerBead`.
# ========================================

EPIC=$(bd create "Epic: deformTimeline format contract + M4 registry keys + schema/codegen regen (prompt 23 of M4 deform-timeline milestone)" \
  -d "Mint the wire format for a clip-owned deformTimeline record (animated per-vertex mesh offsets): binding contract doc, M4 registry keys, canonical-JSON + wire schema, and the four regenerated codec artifacts. Contract + schema/registry/codegen ONLY. Explicit NON-goals (prompts 24/25/26): no runtime loader, no AnimationClip/mixer/buildDrawBatches wiring, no conformance rig/golden, no Dart runtime logic beyond regenerated wire.dart, no round-trip test. Natural cut line: unit A = contract doc + registry keys + objects entry; unit B = codegen (PACKED_BYTES_METADATA / canonical_json_overrides / defaults.yml) + four-file regen with codegen --check green + provenance. Do NOT land unit A leaving codegen --check red." \
  -t epic -p 0 --label epic --silent)
bd update "$EPIC" --status in_progress

# ========================================
# Phase 1: Analysis & Grounding (read-only; confirm symbols, write durable note)
# ========================================

ANALYZE_DEFORM=$(bd create "Confirm project-owned deform types/procs and record the exact serialized shape" \
  -d "Read runtime-nim/src/bony/mesh/deform.nim and record exact field names/order/types for the serialized shape: MeshDelta(x,y: float64) @8-10; DeformKeyframe(time; offset: uint32; deltas: seq[MeshDelta]; curve: TimelineCurve) @12-16; DeformTimeline(skin, slot, attachment: string; vertexCount; keys: seq[DeformKeyframe]) @18-23 — IMPORTANT: the runtime keyframe-list field is named 'keys', while the readable canonical JSON will use 'keyframes'; record both. validateDeformTimeline @66-80 requires non-empty skin @67-68. Also confirm the mesh dependency: model.nim MeshAttachment @109 with deformAttachment*: string @120 (attachments.nim threads it into ctors). Confirm anim/timelines.nim TimelineCurveKind @8-11 / TimelineCurve @13-18 and that AnimationClip @137-142 has boneTimelines/slotTimelines/eventTimelines but NO deformTimelines (prompt-24 territory). Append findings to .agents/notes/deform-timeline-format-decisions.md (downstream beads read it; agents run fresh with no shared memory)." \
  -p 0 --label analysis --parent "$EPIC" --silent)

ANALYZE_REGISTRY=$(bd create "Confirm M4 next-free registry keys + capture slotTimeline/animationClip templates + probe typeKey<->decode sync check" \
  -d "In registry/wire.yml confirm: typeKeys 3000/3001 spent (clipping/mesh) so 3002 free; propertyKeys 3000-3005 spent (vertices/untilSlot/meshWeighted/meshVertices/meshUvs/meshTriangles) so 3006/3007/3008/3009 free. Capture as templates: slotTimeline typeKey entry (=2002, @319-324); the slotTimeline objects entry (@1241-1246, ordered props [slotIndex, slotTimelineKind, timelineKeys]) and boneTimeline objects entry (@1235-1240); the animationClip objects entry (@1231-1234) and its exact doc string 'Animation clip parent record; followed immediately by owned boneTimeline and slotTimeline records.'; generic timeline keys slotIndex=2002 (varuint) and timelineKeys=2004 (bytes) @914-930; the bones string-table bytes key=4014 mechanism. ALSO probe: is there any sync/consistency check between generated typeKeys (generated/wire.nim) and hand-written *TypeKey constants or the decode dispatch in binary/semantic.nim (clippingAttachment/meshAttachment decode)? Adding typeKey 3002 with NO decode path (prompt-24 territory) could break make test if such a check exists — record whether it exists and the fallback. Write findings to .agents/notes/deform-timeline-format-decisions.md." \
  -p 0 --label analysis --parent "$EPIC" --silent)

ANALYZE_CURVE=$(bd create "Document the exact curve-tail encoding the deform packed layout must reuse verbatim" \
  -d "Read writeTimelineKeys curve serialization in runtime-nim/src/bony/binary/semantic.nim (the timelineKeys curve tail used by bone/slot timelines) and anim/timelines.nim TimelineCurveKind/TimelineCurve @8-18. Document the exact byte encoding of the curve tail (linear/stepped/bezier) so the deform packed layout reuses it verbatim — do NOT invent a second curve encoding. Append the encoding note to .agents/notes/deform-timeline-format-decisions.md." \
  -p 0 --label analysis --parent "$EPIC" --silent)

# DECISION BEAD (wire-format-affecting; MUST resolve BEFORE any registry edit).
# PACKED_BYTES_METADATA (generate.py:26-63) is keyed by PROPERTY id; the schema stamps
# x-bony-packedBytes onto a property by that key (generate.py:994-995). Prompt 23 has an
# internal tension: it says BOTH "reuse timelineKeys (2004)" AND "the wire schema
# PACKED_BYTES_METADATA layout reference points at the deform contract anchor". These are
# incompatible because metadata is one-entry-per-property:
#   Option R (reuse timelineKeys 2004): objects entry uses timelineKeys; NO new key; but
#     the packed-bytes layout pointer stays on the SHARED scalar keyframe doc — the deform
#     contract anchor is documented but NOT referenced by the wire schema (criterion waived).
#   Option N (mint deformKeys=3009 bytes): its own PACKED_BYTES_METADATA entry points at the
#     deform contract anchor (matches vertices/meshVertices/bones per-payload pattern);
#     changes REGISTRY_KEYS, objects ordered props, DEFAULTS coverage, canonical JSON.
DECIDE_PACKED_KEY=$(bd create "Resolve the deform packed-payload key fork (Option R reuse timelineKeys 2004 vs Option N mint deformKeys=3009 bytes)" \
  -d "Read generate.py PACKED_BYTES_METADATA (@26-63, keyed by property id), the x-bony-packedBytes stamp (@994-995), the coverage rule (@321-339), canonical_json_overrides (@589), and the meshAttachment objectDefaults/requiredProperties template in spec/defaults.yml (@483-498). Decide: Option R reuses timelineKeys(2004) as the deform payload key (no new key; the packed-bytes pointer stays on docs/binary-animation-state-machine-object-families.md#keyframe-payloads, shared with bone/slot); Option N mints deformKeys=3009 (backingType bytes) so its own metadata entry points at the deform contract's packed-layout anchor. The prompt-23 criterion 'wire schema packedBytes layout reference points at the deform contract anchor' is ONLY satisfiable under Option N — if choosing Option R, flag that this criterion is knowingly waived. Write chosen option + rationale to .agents/notes/deform-timeline-format-decisions.md; every downstream registry/codegen bead reads it." \
  -p 0 --label analysis --parent "$EPIC" --silent)
bd dep add $DECIDE_PACKED_KEY $ANALYZE_CURVE
bd dep add $DECIDE_PACKED_KEY $ANALYZE_REGISTRY

# ========================================
# Phase 2: Unit A — Contract doc + Registry keys + objects entry
# (Do NOT land Unit A leaving `codegen --check` red — Unit B must follow before commit.)
# ========================================

CONTRACT_DOC=$(bd create "Write docs/deform-timeline-contract.md (binding) mirroring docs/mesh-attachment-contract.md structure" \
  -d "Create docs/deform-timeline-contract.md, binding. Mirror docs/mesh-attachment-contract.md: a 'Status: **binding**. Owner bead: <this epic id>' line; a cleanroom/provenance paragraph (names project-owned, from bony's own mesh/deform.nim); ## Model (skin/slot/attachment/vertexCount/keyframes mirroring DeformTimeline @18-23 — note runtime field 'keys' maps to readable JSON 'keyframes'); ## Load-validated invariants tied to docs/float-math-contract.md (1e-4 tolerance + f32 quantization); a normative ## Load edge cases (normative) table (a)-(g) per the prompt's success criteria; ## Packed <bnb> byte layout with a STABLE heading anchor (own bead CONTRACT_PACKED_ANCHOR fills the body); a forward-ref ## Deterministic sampling algorithm (forward reference — implemented in prompt 24) pinning the sampleDeformDeltas formula (nearest-preceding-key search, stepped short-circuit, linear eased=curve.evaluate(t) interpolation of expanded dense deltas, f32 quantization at the boundary; deform.nim:112-137) and applyDeformDeltas order (:140-153); the skin == 'default' reserved-identity decision (loader accepts only 'default'; validator NOT relaxed to allow empty); a ## Cross-track mixing section (a deform timeline resolves like an ATTACHMENT channel — thresholded / winner-take-by-track-weight, NOT weight-blended; documented-but-unexercised in v1); ## Related contracts. Edge-case table (a)-(g): (a) skin!='default' reject; (b) empty slot/attachment or attachment naming unknown mesh on slot reject; (c) vertexCount<=0 or disagreeing with referenced mesh vertex count reject; (d) zero keyframes reject; (e) keyframe with zero deltas or offset+deltas.len>vertexCount reject; (f) non-strictly-increasing key times or negative time reject; (g) slot/attachment pairing not resolving to a loaded mesh attachment reject." \
  -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CONTRACT_DOC $ANALYZE_DEFORM
bd dep add $CONTRACT_DOC $ANALYZE_CURVE

CONTRACT_PACKED_ANCHOR=$(bd create "Pin the normative packed .bnb byte layout in docs/deform-timeline-contract.md with a stable anchor" \
  -d "In docs/deform-timeline-contract.md ## Packed <bnb> byte layout, pin normatively: varuint keyCount, then per keyframe: f32 time, varuint offset, varuint deltaCount, deltaCount*(f32 dx, f32 dy), then the curve tail IDENTICAL to writeTimelineKeys (binary/semantic.nim — the shared bone/slot curve encoding; no second encoding). Give the heading a stable anchor (mirror mesh-attachment-contract.md's #packed-meshvertices-byte-layout-bnb style). Read .agents/notes/deform-timeline-format-decisions.md for the chosen fork option: under Option N this anchor is the PACKED_BYTES_METADATA layout target; under Option R state explicitly in the contract that the wire schema packedBytes pointer references the shared scalar keyframe doc and this deform anchor is documentation-only." \
  -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CONTRACT_PACKED_ANCHOR $CONTRACT_DOC
bd dep add $CONTRACT_PACKED_ANCHOR $DECIDE_PACKED_KEY

REGISTRY_KEYS=$(bd create "Edit registry/wire.yml (M4 band only): add deformTimeline typeKey + deformSkin/deformAttachment/deformVertexCount property keys" \
  -d "In registry/wire.yml, M4 band (3000..3999) only: add typeKey deformTimeline=3002 (mirror the slotTimeline typeKey entry @319-324). Add propertyKeys deformSkin=3006 (backingType varuint, string-table index), deformAttachment=3007 (backingType varuint, string-table index into the mesh-attachment name), deformVertexCount=3008 (backingType varuint). If Option N was chosen (read .agents/notes/deform-timeline-format-decisions.md): ALSO add deformKeys=3009 (backingType bytes) for the packed payload; under Option R add no bytes key (timelineKeys=2004 is reused). The deformSkin/deformAttachment string-table index mechanism mirrors bones (key 4014). Cite the milestone owner bead (this epic id) in each new entry's doc. No key collides; all in 3000..3999. Do NOT touch binary/semantic.nim decode/flush — decode wiring is prompt 24." \
  -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGISTRY_KEYS $ANALYZE_REGISTRY
bd dep add $REGISTRY_KEYS $DECIDE_PACKED_KEY

REGISTRY_OBJECT=$(bd create "Add deformTimeline objects: entry + doc-only animationClip child-family update in registry/wire.yml" \
  -d "In registry/wire.yml objects: (1) add a deformTimeline entry (mirror slotTimeline @1241-1246) with ordered properties [deformSkin, slotIndex, deformAttachment, deformVertexCount, <PAYLOAD>], where <PAYLOAD> = timelineKeys(2004) under Option R or deformKeys(3009) under Option N (read .agents/notes/deform-timeline-format-decisions.md). slotIndex(2002) targets the slot. (2) DOC-ONLY: update the existing animationClip objects entry doc (@1231-1234, currently 'Animation clip parent record; followed immediately by owned boneTimeline and slotTimeline records.') so it names deformTimeline as a third owned child family. Do NOT touch binary/semantic.nim decode/flush — that is prompt 24." \
  -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGISTRY_OBJECT $REGISTRY_KEYS

DOCS_INDEX=$(bd create "Add docs/deform-timeline-contract.md row to docs/README.md" \
  -d "Add a docs/deform-timeline-contract.md row to docs/README.md under 'Attachment Contracts' or a new 'Animation Timeline Contracts' heading beside the mesh/clipping rows, with a one-line binding description." \
  -p 2 --label docs --parent "$EPIC" --silent)
bd dep add $DOCS_INDEX $CONTRACT_DOC

# ========================================
# Phase 3: Unit B — Codegen (defaults + canonical JSON + packed metadata)
# ========================================

DEFAULTS=$(bd create "Add spec/defaults.yml coverage for every serialized deformTimeline property exactly once" \
  -d "Add spec/defaults.yml entries covering every serialized deformTimeline property EXACTLY once across objectDefaults + requiredProperties (coverage rule generate.py:321-339 fails on missing/extra/overlap). Each requiredProperties entry carries reason + ownerBead (mirror meshAttachment @483-498, ownerBead = this epic id). Serialized set: deformSkin, slotIndex, deformAttachment, deformVertexCount, and the payload key (timelineKeys under Option R OR deformKeys under Option N — read the decisions note). PIN deformVertexCount placement explicitly: it is a wire property that must be coverage-satisfied but is deliberately ABSENT from canonical JSON (derived from the mesh at load) — decide/document whether it lives in objectDefaults or requiredProperties, mirror how other derived/wire-only props are covered, and confirm its JSON absence trips no schema validation so codegen --check is deterministic." \
  -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $DEFAULTS $REGISTRY_OBJECT

CANONICAL_JSON=$(bd create "Patch codegen/generate.py canonical_json_overrides(): new deformTimeline \$defs + optional deformTimelines on animationClip" \
  -d "Edit codegen/generate.py canonical_json_overrides() (@589) in TWO places: (1) add a deformTimeline \$defs entry with the readable shape { skin: const 'default', slot: string, attachment: string, keyframes: [ { t: number, offset: integer, deltas: [ { x: number, y: number } ], curve?: ... } ] } — vertexCount is derived from the mesh at load, stored in .bnb, NOT authored in JSON; the readable array is 'keyframes' even though the runtime type field is 'keys'. (2) PATCH the hand-authored animationClip override literal (@786-803, additionalProperties:False, currently only name/boneTimelines/slotTimelines) to add an OPTIONAL deformTimelines array: 'deformTimelines': {'type':'array','items':{'\$ref':'#/\$defs/deformTimeline'},'default':[]}. Without (2) the additionalProperties:False clip rejects deformTimelines and the headline deliverable never appears — nothing else in the graph produces it." \
  -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $CANONICAL_JSON $REGISTRY_OBJECT

PACKED_METADATA=$(bd create "Resolve PACKED_BYTES_METADATA per the packed-key fork (Option N entry vs Option R comment)" \
  -d "Per the DECIDE_PACKED_KEY resolution (read .agents/notes/deform-timeline-format-decisions.md): Option N -> add a PACKED_BYTES_METADATA entry (generate.py:26-63) keyed by the new deformKeys property id, layout pointing at the deform contract's ## Packed <bnb> byte layout anchor (mirror vertices/meshVertices/bones entries). Option R -> NO new metadata entry (timelineKeys 2004 keeps its existing scalar-doc layout pointer docs/binary-animation-state-machine-object-families.md#keyframe-payloads, shared with bone/slot); add a code comment recording that deform intentionally reuses it and the deform anchor is documentation-only. Document the choice in code." \
  -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $PACKED_METADATA $DECIDE_PACKED_KEY
bd dep add $PACKED_METADATA $CONTRACT_PACKED_ANCHOR
bd dep add $PACKED_METADATA $REGISTRY_OBJECT

# ========================================
# Phase 4: Regen + Provenance/Cleanroom
# ========================================

REGEN=$(bd create "Regenerate the four codec artifacts via python3 codegen/generate.py; codegen --check MUST pass" \
  -d "Run python3 codegen/generate.py to regenerate the FOUR outputs (NEVER hand-edit): spec/bony.schema.json, spec/bony-wire.schema.json, runtime-nim/src/bony/generated/wire.nim, runtime-dart/lib/src/generated/wire.dart. Verify the animation-clip JSON \$defs gains an optional deformTimelines array whose items express the readable skin/slot/attachment/keyframes shape. python3 codegen/generate.py --check MUST pass (validate_sources fails if registry/defaults/canonical-JSON/packed-metadata drifted)." \
  -p 0 --label impl --parent "$EPIC" --silent)
bd dep add $REGEN $DEFAULTS
bd dep add $REGEN $CANONICAL_JSON
bd dep add $REGEN $PACKED_METADATA

PROVENANCE=$(bd create "Add docs/PROVENANCE.md deform-timeline naming entry + run docs/CLEANROOM.md new-identifier checklist" \
  -d "Add a docs/PROVENANCE.md entry: deform-timeline schema/field names taken from bony's own pre-existing mesh/deform.nim runtime types (not derived from any surveyed product — DragonBones/Spine/Rive/Live2D/Lottie). Run the docs/CLEANROOM.md new-identifier checklist for the net-new serialized names: deformTimelines, deformSkin, deformAttachment, deformVertexCount." \
  -p 1 --label docs --parent "$EPIC" --silent)
bd dep add $PROVENANCE $REGISTRY_KEYS

# ========================================
# Phase 5: Verification & Change-Detector
# ========================================

SMOKE_COUNTS=$(bd create "Update runtime-nim/tests/test_smoke.nim registry change-detector counts to regenerated totals" \
  -d "Update runtime-nim/tests/test_smoke.nim (@112-115) to the regenerated totals: bonyTypeKeys.len (28 -> 29 for +deformTimeline); bonyPropertyKeys.len (101 -> 104 for +deformSkin/+deformAttachment/+deformVertexCount, or 105 if Option N adds +deformKeys); bonyPropertyDefaults.len (baseline 55) and bonyRequiredProperties.len (baseline 74) to whatever the regen produces. READ the regenerated generated/wire.nim for the exact numbers; do not guess." \
  -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $SMOKE_COUNTS $REGEN

VALIDATE_ASSETS=$(bd create "Run python3 scripts/ci/schema_validate_assets.py — must pass for all existing assets" \
  -d "Run python3 scripts/ci/schema_validate_assets.py — MUST pass for all existing assets against the regenerated schema, proving the new OPTIONAL deformTimelines array does not break existing clip assets." \
  -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $VALIDATE_ASSETS $REGEN

MAKE_TEST=$(bd create "Run make test (full gate) green, explicitly confirming a decode-less new typeKey does not break it" \
  -d "Run make test (full gate, includes python3 codegen/generate.py --check and the Nim tests) and confirm green. EXPLICITLY confirm (do not assume) the gate tolerates a new typeKey (deformTimeline=3002) that has NO decode path / no *TypeKey constant / no dispatch in binary/semantic.nim — per the ANALYZE_REGISTRY sync-check probe. If make test surfaces a generated-typeKey<->semantic.nim consistency check that fails on the undecoded key, STOP and escalate: the slice is not buildable as scoped (do NOT add decode wiring — that is prompt 24). Do NOT add or attempt a runtime JSON/.bnb round-trip test for deformTimeline — there is no loader yet (deferred to prompt 24)." \
  -p 0 --label testing --parent "$EPIC" --silent)
bd dep add $MAKE_TEST $SMOKE_COUNTS
bd dep add $MAKE_TEST $VALIDATE_ASSETS
bd dep add $MAKE_TEST $DOCS_INDEX
bd dep add $MAKE_TEST $PROVENANCE

echo ""
echo "Bead graph created! View with:"
echo "  bd show $EPIC          # The parent epic and its rollup"
echo "  bd dep tree            # Task beads under the epic; no orphans, no cycles"
echo "  bd ready               # Unblocked tasks (the epic itself is not work)"
echo "  bd dep cycles          # Should report none"
