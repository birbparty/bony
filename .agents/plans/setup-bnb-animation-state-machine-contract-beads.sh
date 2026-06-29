#!/bin/bash
# Project: bony
# Change: Define project-owned .bnb contract for serialized animations and state machines
# Generated: 2026-06-29

set -euo pipefail

if [ ! -d ".beads" ]; then
    bd init
fi

echo "Creating .bnb animation/state-machine contract beads..."

EPIC=$(bd create "Epic: Define .bnb animation and state-machine contract" \
  --type epic \
  --priority 0 \
  --labels epic \
  --description "Rollup for defining the project-owned .bnb v1 contract for already-local animations and state machines. This epic is organizational only; do not add dependency edges to or from it. The runtime .bnb playback gate in cli/bony_cli.nim remains in place until a later implementation slice." \
  --silent)
bd update "$EPIC" --status in_progress

ANALYZE_LOCAL_SURFACE=$(bd create "Analyze existing local animation and state-machine surfaces before binary contract work" \
  --type task \
  --priority 0 \
  --labels analysis \
  --parent "$EPIC" \
  --description "Inspect the current project-owned JSON/runtime surface and record the exact contract boundaries to preserve. Include runtime-nim/src/bony/anim/timelines.nim timeline kinds and keyframe validation, runtime-nim/src/bony/statemachine/core.nim inputs/layers/states/transitions/listeners, runtime-nim/src/bony/jsonio.nim loadBonyJsonAnimations/loadBonyJsonStateMachines, runtime-nim/src/bony/model.nim SkeletonData fields, runtime-dart/lib/src/model.dart SkeletonData animations/stateMachines, runtime-dart/lib/src/loader.dart JSON validation and .bnb loader omissions, runtime-dart/lib/src/anim.dart, and runtime-dart/lib/src/statemachine.dart. Note that docs/specs/ and docs/adr/ are absent; docs live directly under docs/ with docs/spikes and docs/prompts only." \
  --silent)

CLEANROOM_REVIEW=$(bd create "Review clean-room and provenance constraints for the binary animation/state-machine contract" \
  --type task \
  --priority 0 \
  --labels analysis,cleanup \
  --parent "$EPIC" \
  --description "Review docs/CLEANROOM.md, docs/PROVENANCE.md, docs/comparable-feature-set.md, and the local binding spec at /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md. Record that this slice may use only project-owned local JSON/runtime behavior and capability categories; do not inspect or derive from DragonBones, Spine, Rive, Live2D, Lottie runtime/importer source, exact wire layouts, generated definitions, or copied docs prose." \
  --silent)

OBJECT_FAMILY_CONTRACT=$(bd create "Choose binary object families for animations, timelines, and state machines" \
  --type decision \
  --priority 0 \
  --labels contract \
  --parent "$EPIC" \
  --description "Define the project-owned .bnb object shape before registry edits. Decide parent records, child records, and any packed bytes payloads for AnimationClip, bone timelines, slot timelines, event timelines if retained, curve/keyframe payloads, StateMachine, inputs, layers, states, blend clips, transitions, conditions, and listeners. Preserve existing local features only: bone scalar/vector/inherit timelines, slot attachment/color/two-color/sequence timelines, clip state, blend1d state, typed inputs, transitions, conditions, and listeners. Keep the shape small enough for a follow-up runtime/CLI implementation slice." \
  --silent)

CANONICAL_ORDER_CONTRACT=$(bd create "Define canonical object order, child adjacency, string traversal, and default omission rules" \
  --type task \
  --priority 0 \
  --labels contract \
  --parent "$EPIC" \
  --description "Extend the binding rules in docs/binary-canonicalization.md or the new contract doc so animation records are emitted before state-machine records, timeline/keyframe child objects immediately follow their owning animation when child records are chosen, state-machine child records immediately follow their owning machine/layer/state when chosen, and string table traversal follows canonical object order, property order, and packed bytes field order. Preserve default omission semantics from docs/json-canonicalization.md, docs/binary-canonicalization.md, and spec/defaults.yml." \
  --silent)

REFERENCE_SEMANTICS=$(bd create "Define binary reference semantics for animation and state-machine records after load" \
  --type task \
  --priority 0 \
  --labels contract \
  --parent "$EPIC" \
  --description "Specify how binary records resolve to the same semantic graph as JSON after load. Cover bones, slots, attachments, animation clips, timelines, state-machine inputs, layers, states, blend clips, transitions, conditions, and listeners. Define whether references are string-backed, index-backed, or packed in bytes, and how they map back to project-owned names after binary load. Align with docs/load-validation-contract.md reference resolution rules and reject known references to skipped unknown binary objects." \
  --silent)

VALIDATION_OWNERSHIP=$(bd create "Define validation ownership for existing timeline and state-machine kinds" \
  --type task \
  --priority 0 \
  --labels contract \
  --parent "$EPIC" \
  --description "Document which checks belong to schema, registry/default decoding, loader validation, and runtime constructors. Cover non-empty names, duplicate names, sorted keyframe times, valid curve control points, f32 time/value quantization, color channel domains, sequence delay/mode domains, clip duration, blend1d numeric input requirements, blend clip sort/duplicate value rules, transition condition type matching, listener target resolution, layer initial state resolution, and existing typed error categories from runtime-nim/src/bony/model.nim and docs/load-validation-contract.md." \
  --silent)

NIM_ASSET_DECISION=$(bd create "Decide Nim loaded-asset shape for preserving animations and state machines" \
  --type decision \
  --priority 0 \
  --labels contract \
  --parent "$EPIC" \
  --description "Decide whether Nim extends runtime-nim/src/bony/model.nim SkeletonData with animations/stateMachines or introduces a project-owned loaded-asset aggregate that carries SkeletonData plus seq[AnimationClip] plus seq[StateMachine]. Explain how .bony -> .bnb -> .bony preserves animation/state-machine data while existing setup/deformer binary APIs continue to work. This is a contract decision only; do not remove the .bnb state-machine playback rejection in cli/bony_cli.nim." \
  --silent)

WRITE_CONTRACT_DOC=$(bd create "Write docs/binary-animation-state-machine-contract.md and cross-link binding decisions" \
  --type task \
  --priority 1 \
  --labels docs,contract \
  --parent "$EPIC" \
  --description "Create docs/binary-animation-state-machine-contract.md or update equivalent binding docs if the standalone file is not chosen. The doc must cover object families, canonical order, child adjacency, string traversal, reference semantics, default omission, validation ownership, Nim asset-shape decision, append-only registry constraints, and explicit out-of-scope runtime acceptance. Link related rules from docs/binary-canonicalization.md, docs/binary-toc-skip-semantics.md, docs/load-validation-contract.md, docs/json-canonicalization.md, docs/CLEANROOM.md, and docs/PROVENANCE.md." \
  --silent)

REGISTRY_M3_M8=$(bd create "Append M3 and M8 animation/state-machine entries to registry/wire.yml" \
  --type task \
  --priority 1 \
  --labels registry \
  --parent "$EPIC" \
  --description "Reserve and append only new typeKeys, propertyKeys, and objects needed by the contract in registry/wire.yml. Use only your allocated range from registry/key-ranges.md: M3 2000..2999 for animations/timelines/curves and M8 7000..7999 for state machines/layers/transitions/listeners. Do not renumber, delete, repurpose, or change backing types for existing M1/M2/M5/M7 entries. Include ownerBead references, docs for packed bytes layouts, and object property lists that keep property keys globally backing-type compatible. Reservation notes: shared registry/default/codegen surface includes registry/wire.yml, spec/defaults.yml, codegen/generate.py, codegen/test_generate.py, spec/bony.schema.json, runtime-nim/src/bony/generated/wire.nim, and runtime-dart/lib/src/generated/wire.dart." \
  --silent)

DEFAULTS_SCHEMA_SOURCE=$(bd create "Update spec/defaults.yml for contract-owned defaults and required properties" \
  --type task \
  --priority 1 \
  --labels registry,codegen \
  --parent "$EPIC" \
  --description "Add only defaults or required-property entries needed by the new animation and state-machine registry objects. Preserve default omission compatibility with docs/json-canonicalization.md and docs/binary-canonicalization.md. Every object property introduced in registry/wire.yml must be covered exactly once by objectDefaults or requiredProperties so codegen/generate.py validate_sources remains strict. Do not hand-edit spec/bony.schema.json in this bead." \
  --silent)

CODEGEN_SCHEMA_SUPPORT=$(bd create "Extend codegen for animation/state-machine schema and packed bytes metadata if needed" \
  --type task \
  --priority 1 \
  --labels codegen \
  --parent "$EPIC" \
  --description "Update codegen/generate.py only where the new contract requires generator behavior beyond current primitive schema mapping. Preserve registry/default validation for key ranges, duplicate keys, object property coverage, backing types, and generated schema order. If packed bytes payloads cannot be expressed structurally in the generated JSON Schema, document the generator gap explicitly in the contract and add validation tests that guard the chosen behavior." \
  --silent)

REGENERATE_ARTIFACTS=$(bd create "Regenerate generated wire tables and JSON schema through codegen/generate.py" \
  --type task \
  --priority 1 \
  --labels codegen \
  --parent "$EPIC" \
  --description "Run the established generator path after registry/default/codegen source edits. Generated outputs are spec/bony.schema.json, spec/DEFAULTS.md, runtime-nim/src/bony/generated/wire.nim, and runtime-dart/lib/src/generated/wire.dart. Treat these files as generated artifacts, not independent hand-maintained sources. Verify python3 codegen/generate.py --check succeeds after regeneration." \
  --silent)

GENERATOR_TESTS=$(bd create "Add focused generator tests for append-only registry/default/schema behavior" \
  --type task \
  --priority 2 \
  --labels testing,codegen \
  --parent "$EPIC" \
  --description "Extend codegen/test_generate.py with focused tests for the new M3/M8 entries and any generator behavior added for this contract. Prove keys remain in allocated bands, existing entries stay append-only, default coverage is complete, generated Nim and Dart wire metadata expose the new entries, schema root order includes animations before stateMachines, and existing conformance assets remain valid. Keep tests small and deterministic." \
  --silent)

DOC_INDEX_AND_USER_GATE=$(bd create "Update docs and CLI user-facing notes without enabling .bnb playback" \
  --type task \
  --priority 2 \
  --labels docs \
  --parent "$EPIC" \
  --description "Link the new binary animation/state-machine contract from docs/README.md and update adjacent docs only where needed: docs/binary-canonicalization.md, docs/load-validation-contract.md, docs/json-canonicalization.md, registry/README.md, spec/README.md, and cli/README.md. cli/README.md and cli/bony_cli.nim must continue to make clear that state-machine input scripts require .bony until the runtime implementation slice accepts .bnb playback." \
  --silent)

SCHEMA_ASSET_VALIDATION=$(bd create "Validate generated schema against committed conformance assets" \
  --type task \
  --priority 2 \
  --labels testing \
  --parent "$EPIC" \
  --description "Run python3 scripts/ci/schema_validate_assets.py after generated schema changes. Existing assets conformance/assets/m8_rig.bony, conformance/assets/m9_non_scalar_rig.bony, and the rest of conformance/assets/*.bony must continue to validate. If schema limitations around packed bytes or animation/state-machine structure are discovered, file a follow-up bead rather than silently loosening additionalProperties or bypassing the generated schema source." \
  --silent)

CONTRACT_VERIFICATION=$(bd create "Run minimum contract verification commands and record results" \
  --type task \
  --priority 2 \
  --labels testing,cleanup \
  --parent "$EPIC" \
  --description "Before closing this contract slice, run at minimum: python3 codegen/generate.py --check; python3 -m unittest discover -s codegen -p 'test_*.py'; python3 scripts/ci/schema_validate_assets.py. If code changed beyond codegen/registry/schema/docs, add the nearest affected runtime or CLI tests. Record any unavailable tool or dependency explicitly. Confirm the current .bnb state-machine replay rejection remains unchanged." \
  --silent)

FOLLOWUP_BEADS=$(bd create "File follow-up beads for runtime .bnb playback and binary conformance implementation" \
  --type task \
  --priority 3 \
  --labels cleanup \
  --parent "$EPIC" \
  --description "Create explicit follow-up beads for work discovered outside this contract slice, especially prompt 03 runtime support for serializing/decoding animations and state machines, prompt 04 binary state-machine conformance, CLI removal of the .bnb playback rejection, conformance/assets/bnb/m8_rig.bnb regeneration when runtime support lands, and any Dart/Nim loader aggregate changes not safe to implement in this contract-only slice." \
  --silent)

bd dep add "$OBJECT_FAMILY_CONTRACT" "$ANALYZE_LOCAL_SURFACE"
bd dep add "$OBJECT_FAMILY_CONTRACT" "$CLEANROOM_REVIEW"
bd dep add "$CANONICAL_ORDER_CONTRACT" "$OBJECT_FAMILY_CONTRACT"
bd dep add "$REFERENCE_SEMANTICS" "$OBJECT_FAMILY_CONTRACT"
bd dep add "$VALIDATION_OWNERSHIP" "$ANALYZE_LOCAL_SURFACE"
bd dep add "$VALIDATION_OWNERSHIP" "$REFERENCE_SEMANTICS"
bd dep add "$NIM_ASSET_DECISION" "$ANALYZE_LOCAL_SURFACE"
bd dep add "$NIM_ASSET_DECISION" "$OBJECT_FAMILY_CONTRACT"
bd dep add "$WRITE_CONTRACT_DOC" "$CANONICAL_ORDER_CONTRACT"
bd dep add "$WRITE_CONTRACT_DOC" "$REFERENCE_SEMANTICS"
bd dep add "$WRITE_CONTRACT_DOC" "$VALIDATION_OWNERSHIP"
bd dep add "$WRITE_CONTRACT_DOC" "$NIM_ASSET_DECISION"
bd dep add "$REGISTRY_M3_M8" "$WRITE_CONTRACT_DOC"
bd dep add "$DEFAULTS_SCHEMA_SOURCE" "$REGISTRY_M3_M8"
bd dep add "$CODEGEN_SCHEMA_SUPPORT" "$DEFAULTS_SCHEMA_SOURCE"
bd dep add "$REGENERATE_ARTIFACTS" "$CODEGEN_SCHEMA_SUPPORT"
bd dep add "$GENERATOR_TESTS" "$CODEGEN_SCHEMA_SUPPORT"
bd dep add "$DOC_INDEX_AND_USER_GATE" "$WRITE_CONTRACT_DOC"
bd dep add "$DOC_INDEX_AND_USER_GATE" "$REGISTRY_M3_M8"
bd dep add "$SCHEMA_ASSET_VALIDATION" "$REGENERATE_ARTIFACTS"
bd dep add "$SCHEMA_ASSET_VALIDATION" "$GENERATOR_TESTS"
bd dep add "$FOLLOWUP_BEADS" "$WRITE_CONTRACT_DOC"
bd dep add "$CONTRACT_VERIFICATION" "$REGENERATE_ARTIFACTS"
bd dep add "$CONTRACT_VERIFICATION" "$GENERATOR_TESTS"
bd dep add "$CONTRACT_VERIFICATION" "$DOC_INDEX_AND_USER_GATE"
bd dep add "$CONTRACT_VERIFICATION" "$SCHEMA_ASSET_VALIDATION"
bd dep add "$CONTRACT_VERIFICATION" "$FOLLOWUP_BEADS"

echo ""
echo "Created epic: $EPIC"
echo "View the rollup with:"
echo "  bd show $EPIC"
echo "  bd children $EPIC"
echo "  bd ready"
echo "  bd dep cycles"
