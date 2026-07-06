#!/bin/bash
# Project: bony
# Change: DragonBones importer bone-animation tier
# Generated: 2026-07-06
#
# Analysis notes captured before graph creation:
# - docs/specs/ and docs/adr/ are absent in this repository. The controlling
#   context is docs/CLEANROOM.md, docs/PROVENANCE.md,
#   docs/comparable-feature-set.md, docs/dragonbones-importer-design.md,
#   docs/animation-state-machine-contract-boundaries.md, and
#   docs/nim-loaded-asset-shape.md.
# - cli/bony_cli.nim owns the current DragonBones adapter model. It parses
#   static bones, slots, skins, image displays, setup transforms, and only
#   records DbArmature.hasAnimation before writing toBonyJson(SkeletonData).
# - runtime-nim/src/bony/asset.nim, jsonio.nim, and binary/semantic.nim already
#   expose aggregate BonyAsset JSON and BNB preservation APIs.
# - runtime-nim/src/bony/anim/timelines.nim already provides the exported
#   AnimationClip, boneScalarTimeline, boneVectorTimeline, scalarKeyframe, and
#   vector2Keyframe constructors needed by the importer.
# - Existing CLI coverage is mostly in runtime-nim/tests/test_smoke.nim. A
#   small include-based CLI-private test module exists at
#   runtime-nim/tests/test_cli_pose.nim.

set -euo pipefail

if [ ! -d ".beads" ]; then
  bd init
fi

echo "Creating DragonBones bone-animation importer task graph..."

# Parent epic. This is a rollup only: every work item below uses --parent
# "$EPIC"; no bd dep add command points to or from the epic.
EPIC=$(bd create "Epic: Implement DragonBones importer bone-animation tier" \
  -t epic \
  -p 0 \
  --labels dragonbones,importer,animation,epic \
  --description "Rollup for the clean-room DragonBones importer Tier 1 bone-animation work. This epic replaces the existing tracker bony-0vu9 and covers parsing, validation, emission, CLI sampling, fixtures, rejection diagnostics, round-trip checks, and final verification. Scope is limited to translateFrame, rotateFrame, and scaleFrame bone channels documented in docs/dragonbones-importer-design.md." \
  --acceptance "Epic is complete only after all child beads are closed, bony-0vu9 is superseded by this epic, supported DragonBones bone animation imports produce BonyAsset animations, unsupported out-of-tier animation fails deterministically without partial output, and python3 codegen/generate.py --check, python3 -m unittest discover -s codegen -p 'test_*.py', and make test pass." \
  --silent)
bd update "$EPIC" --status in_progress
bd supersede bony-0vu9 --with "$EPIC"

# Phase 1: Analysis and preparation

CONTEXT=$(bd create "Ground DragonBones importer scope in local clean-room docs and current CLI/runtime interfaces" \
  -t task \
  -p 0 \
  --labels analysis \
  --parent "$EPIC" \
  --description "File reservations: docs/dragonbones-importer-design.md, docs/CLEANROOM.md, docs/PROVENANCE.md, docs/comparable-feature-set.md, docs/animation-state-machine-contract-boundaries.md, docs/nim-loaded-asset-shape.md, cli/bony_cli.nim, runtime-nim/src/bony/anim/timelines.nim, runtime-nim/src/bony/asset.nim, runtime-nim/src/bony/jsonio.nim, runtime-nim/src/bony/binary/semantic.nim, runtime-nim/tests/test_smoke.nim, runtime-nim/tests/test_cli_pose.nim, and Makefile for read-only analysis. Confirm docs/specs/ and docs/adr/ are absent, so the listed local docs control the change. Map the existing DbTransform, DbDisplay, DbSkinSlotEntry, DbSkin, DbBoneEntry, DbSlotEntry, DbArmature, importDragonbones, BonyAsset, toBonyJson(BonyAsset), loadBonyJsonAsset, toBonyBnb(BonyAsset), loadKnownBonyBnbAsset, and AnimationClip constructor interfaces." \
  --acceptance "Notes on the bead identify the exact importer section and test locations to touch, the aggregate asset API path to preserve animations, the existing timeline constructors to reuse, current CLI nonzero --t behavior, and risk areas: silent animation drop, setup-only semantics, unsupported slot channels, duration sums, partial output, and clean-room field-name containment. No implementation code is changed by this bead." \
  --silent)

CHARACTERIZE=$(bd create "Add characterization tests for current DragonBones static import behavior and diagnostics" \
  -t task \
  -p 0 \
  --labels prep,testing \
  --parent "$EPIC" \
  --description "File reservations: runtime-nim/tests/test_smoke.nim and any importer-owned temporary fixture strings created inside that test. Preserve the current minimal _ske.json static import checks near the existing DragonBones smoke test, including Y-flip, skew decomposition, parent sorting, mesh display rejection, invalid slot parent rejection, and display transform rejection. Keep fixtures user-supplied or importer-owned and do not import external schemas or prose." \
  --acceptance "A failing implementation can still be characterized before animation support lands. Tests assert the current setup-only no-animation path remains valid, diagnostics include deterministic DbDiagnostic code/capability text with no Traceback, and no external DragonBones runtime/importer/schema source is referenced. Run at least cd runtime-nim && nim c -r --hints:off tests/test_smoke.nim for this bead." \
  --silent)
bd dep add "$CHARACTERIZE" "$CONTEXT"

# Phase 2: Parser and validation

PARSER=$(bd create "Extend cli DragonBones adapter records to parse animation, bone timelines, and channel frame arrays" \
  -t task \
  -p 1 \
  --labels impl,parser \
  --parent "$EPIC" \
  --description "File reservations: cli/bony_cli.nim DragonBones Importer section only. Add importer-owned records for animation clips, bone animation entries, and translateFrame, rotateFrame, and scaleFrame channel frames matching docs/dragonbones-importer-design.md. Parse only the local design note input contract: animation name, duration, bone timelines, translateFrame x/y duration/tweenEasing/curve, rotateFrame rotate/duration/tweenEasing/curve/clockwise, and scaleFrame x/y duration/tweenEasing/curve. Field names stay at the parser boundary. Do not touch runtime animation sampling semantics." \
  --acceptance "DbArmature carries parsed animations instead of only hasAnimation. Missing animation still produces a static import. setupOnly still skips channel validation beyond armature structure. Parser rejects malformed JSON shapes deterministically through DbDiagnostic. The code does not read or copy external DragonBones runtimes, importers, generated schemas, or docs prose." \
  --silent)
bd dep add "$PARSER" "$CONTEXT"

VALIDATION=$(bd create "Implement Tier 1 DragonBones animation validation and unsupported-feature diagnostics" \
  -t task \
  -p 1 \
  --labels impl,validation \
  --parent "$EPIC" \
  --description "File reservations: cli/bony_cli.nim DragonBones Importer section. Validate parsed animation channels before emission when setupOnly is false. Enforce positive armature frameRate, nonnegative animation duration, channel duration sums including duration 0 terminators equaling animation.duration, strictly deterministic target strings, and bone channel references resolving against imported bones. Reject slot animation channels, mesh displays already covered by static path, nonzero tweenEasing, well-formed curve objects, malformed curve values, clockwise, negative scale, and any out-of-tier animation field with DbDiagnostic code/capability text." \
  --acceptance "Unsupported or invalid animation fails before output write and includes deterministic code, target, and capability. setupOnly suppresses valid animation without validating channel-level unsupported features, except structural armature parse errors still fail. Duration mismatches, missing terminators, invalid bone timeline references, and slot channels are covered by diagnostic cases or notes for downstream tests. Scope does not expand to Bezier easing, slot color/display animation, mesh displays, IK/constraint import, multiple-armature composition, negative scale support, or display transform mapping." \
  --silent)
bd dep add "$VALIDATION" "$PARSER"

# Phase 3: Emission and CLI sampling

EMIT=$(bd create "Emit supported DragonBones bone channels as bony AnimationClip data through BonyAsset JSON" \
  -t task \
  -p 1 \
  --labels impl,emission \
  --parent "$EPIC" \
  --description "File reservations: cli/bony_cli.nim DragonBones Importer section, with read-only use of runtime-nim/src/bony/anim/timelines.nim, runtime-nim/src/bony/asset.nim, and runtime-nim/src/bony/jsonio.nim. Convert supported translateFrame, rotateFrame, and scaleFrame channels to bony boneVectorTimeline translateTimeline, boneScalarTimeline rotateTimeline, and boneVectorTimeline scaleTimeline data. Use armature.frameRate for seconds, include each non-empty channel duration 0 terminator as the endpoint keyframe, and construct AnimationClip via the existing constructor against the imported SkeletonData. importDragonbones should write toBonyJson(bonyAsset(data, animations)) when animation is preserved and may keep static SkeletonData output for no-animation or setup-only output if canonical behavior requires it." \
  --acceptance "Imported animation clip duration equals animation.duration / armature.frameRate. Translate values apply DragonBones Y-down to bony Y-up conversion, rotateFrame.rotate is applied as the documented additive rotation channel without changing rest shear, and scaleFrame multipliers apply to rest positive scale values. No runtime timeline interpolation behavior is changed. Existing static DragonBones, Lottie, json-to-bnb, bnb-to-json, play, and golden-gen setup-pose paths continue to pass smoke tests." \
  --silent)
bd dep add "$EMIT" "$VALIDATION"
bd dep add "$EMIT" "$CHARACTERIZE"

SETUP_ONLY=$(bd create "Preserve setup-only suppression and prevent partial DragonBones importer output on animation failures" \
  -t task \
  -p 1 \
  --labels impl,cli \
  --parent "$EPIC" \
  --description "File reservations: cli/bony_cli.nim importDragonbones implementation and runtime-nim/tests/test_smoke.nim for focused checks. Make --setup-only the explicit path that suppresses otherwise valid animations and keeps output static/setup-only. Without --setup-only, any parsed animation must either be emitted or fail; it must never be silently omitted. Ensure importer errors happen before writeFile or write to a temporary path that is only moved after success." \
  --acceptance "Tests prove valid animation with --setup-only emits no animations and prints the existing suppression style diagnostic, valid animation without --setup-only preserves animations, unsupported animation without --setup-only exits nonzero, and the requested output path is absent or unchanged after failure. Diagnostics do not include Traceback and do not quote third-party prose." \
  --silent)
bd dep add "$SETUP_ONLY" "$VALIDATION"

SAMPLE_PATH=$(bd create "Add a narrow normal runtime sampling path for imported plain animation clips if existing CLI cannot sample them" \
  -t task \
  -p 2 \
  --labels impl,cli,testing \
  --parent "$EPIC" \
  --description "File reservations: cli/bony_cli.nim and runtime-nim/tests/test_cli_pose.nim or runtime-nim/tests/test_smoke.nim. First verify whether golden-gen or play can already sample a plain .bony AnimationClip at nonzero time. If current CLI rejects nonzero --t for plain clips, add the narrowest helper needed for tests to sample one named clip through existing runtime animation APIs and pose application. Keep state-machine and input-script semantics unchanged, and do not broaden this bead into general playback UI work." \
  --acceptance "At least one nonzero-time sample of an imported DragonBones clip is generated through normal bony runtime sampling and produces numeric bone-world output. Existing setup-pose --t rejection remains for assets with no sampled animation context. State-machine input-script behavior, .bnb state-machine boundaries, and render paths are not loosened beyond the minimal clip sampling need." \
  --silent)
bd dep add "$SAMPLE_PATH" "$EMIT"

# Phase 4: Fixture and regression coverage

SUCCESS_TESTS=$(bd create "Add DragonBones bone-animation success fixtures and canonical output assertions" \
  -t task \
  -p 1 \
  --labels testing,fixtures \
  --parent "$EPIC" \
  --description "File reservations: runtime-nim/tests/test_smoke.nim and importer-owned inline _ske.json fixture strings or a new runtime-nim/tests fixture module if the smoke test becomes too large. Cover linear translateFrame, rotateFrame, and scaleFrame channels, step or hold behavior for absent/null tweenEasing, a single-channel animation that leaves other channels and omitted animated bones at setup rest, a static no-animation rig, and canonical .bony JSON output using loadBonyJsonAsset or JSON inspection. Fixtures must be project-owned test data, not copied from external DragonBones sources." \
  --acceptance "Success tests prove import-dragonbones emits an animations array with expected clip names, duration, timeline targets, timeline properties, key times, and endpoint keyframes. Tests verify no-animation output remains static, setup-only output suppresses valid animation, and imported canonical JSON round-trips through loadBonyJsonAsset -> toBonyJson. Run cd runtime-nim && nim c -r --hints:off tests/test_smoke.nim." \
  --silent)
bd dep add "$SUCCESS_TESTS" "$EMIT"
bd dep add "$SUCCESS_TESTS" "$SETUP_ONLY"

REJECTION_TESTS=$(bd create "Add DragonBones animation rejection fixtures for unsupported channels, easing, curves, references, durations, and partial output" \
  -t task \
  -p 1 \
  --labels testing,fixtures \
  --parent "$EPIC" \
  --description "File reservations: runtime-nim/tests/test_smoke.nim and importer-owned inline _ske.json fixture strings or a narrowly scoped fixture helper. Add nonzero tweenEasing, well-formed curve, malformed curve, clockwise, slot channel, invalid bone channel reference, bad duration sum, missing duration 0 terminator if distinguishable, negative scale, and partial-output prevention cases. Keep existing mesh display, invalid slot parent, and display transform rejections passing." \
  --acceptance "Each rejection exits nonzero, includes deterministic code/capability/target fragments, omits Traceback, and leaves no partial output file or leaves an existing output file unchanged. --setup-only skips supported animation channel validation as specified while structural armature errors still fail. Run cd runtime-nim && nim c -r --hints:off tests/test_smoke.nim." \
  --silent)
bd dep add "$REJECTION_TESTS" "$VALIDATION"
bd dep add "$REJECTION_TESTS" "$SETUP_ONLY"

NUMERIC_GOLDEN=$(bd create "Add nonzero-time numeric golden coverage for imported DragonBones animation sampling" \
  -t task \
  -p 1 \
  --labels testing,conformance \
  --parent "$EPIC" \
  --description "File reservations: runtime-nim/tests/test_smoke.nim, runtime-nim/tests/test_cli_pose.nim if the sampling helper is include-tested, and any conformance asset path only if choosing checked-in fixtures over inline temp files. Use the imported animation output from import-dragonbones and sample at a nonzero time through the normal runtime path established by the sampling bead. Assert numeric world transforms for at least translate, rotate, and scale effects with tolerance consistent with existing closeTo or closeWithin helpers." \
  --acceptance "The test imports a DragonBones fixture, samples a nonzero animation time, and verifies numeric bone-world output rather than only string-level JSON. It also demonstrates a single-channel animation holds omitted channels at setup rest. The sampling path remains narrow and does not require external assets unless image dimensions are explicitly part of the fixture." \
  --silent)
bd dep add "$NUMERIC_GOLDEN" "$SUCCESS_TESTS"
bd dep add "$NUMERIC_GOLDEN" "$SAMPLE_PATH"

BNB_ROUNDTRIP=$(bd create "Validate imported DragonBones animations preserve through bony JSON to BNB to JSON aggregate conversion" \
  -t task \
  -p 2 \
  --labels testing,roundtrip \
  --parent "$EPIC" \
  --description "File reservations: runtime-nim/tests/test_smoke.nim, with read-only reliance on cli/bony_cli.nim json-to-bnb and bnb-to-json commands and runtime-nim/src/bony/binary/semantic.nim aggregate APIs. Use an imported DragonBones animation fixture, convert .bony to .bnb and back, and assert loadBonyJsonAsset(to-json result).animations preserves clip count, names, durations, timeline kinds, targets, key times, and values. Do not add registry keys or generated schema changes." \
  --acceptance "Round-trip coverage fails if imported animations are dropped by conversion. Existing static round-trip tests still pass. The bead confirms the importer tier relies on already-present aggregate binary APIs and does not introduce new wire families or codegen changes." \
  --silent)
bd dep add "$BNB_ROUNDTRIP" "$SUCCESS_TESTS"

# Phase 5: Documentation and verification

DOCS=$(bd create "Update local DragonBones importer docs with implemented Tier 1 behavior and diagnostics boundaries" \
  -t task \
  -p 2 \
  --labels docs \
  --parent "$EPIC" \
  --description "File reservations: docs/dragonbones-importer-design.md, docs/CLEANROOM.md, docs/PROVENANCE.md, and cli/README.md only if CLI behavior text changes. Document the implemented Tier 1 behavior without copying third-party documentation prose. Record that import-dragonbones preserves bone translate/rotate/scale animations unless --setup-only is supplied, and list deterministic unsupported diagnostics at a capability level." \
  --acceptance "Docs mention the local project-owned input contract, supported translateFrame/rotateFrame/scaleFrame tier, setup-only suppression, unsupported slot channels, easing/curve/clockwise/negative-scale rejection, partial-output prevention, and clean-room constraints. No docs/specs/ or docs/adr/ paths are introduced for this change." \
  --silent)
bd dep add "$DOCS" "$EMIT"
bd dep add "$DOCS" "$REJECTION_TESTS"

VERIFY=$(bd create "Run full verification for DragonBones importer bone-animation tier and close the epic when green" \
  -t task \
  -p 0 \
  --labels verification,cleanup \
  --parent "$EPIC" \
  --description "File reservations: no source reservations except small test expectation fixes directly caused by preceding beads. Run the required verification commands from the plan: python3 codegen/generate.py --check, python3 -m unittest discover -s codegen -p 'test_*.py', and make test. Inspect git status and bd children for the epic. Close all completed child beads and then close the epic only after the graph is green." \
  --acceptance "Verification commands pass exactly as required. The task notes include command outputs or concise summaries, any residual follow-up is filed as a new bead, all completed beads under the epic are closed, and the final branch has no unintended generated drift. Work is not considered done until the repository session close protocol commits and pushes code plus bead data." \
  --silent)
bd dep add "$VERIFY" "$NUMERIC_GOLDEN"
bd dep add "$VERIFY" "$BNB_ROUNDTRIP"
bd dep add "$VERIFY" "$DOCS"

echo ""
echo "Created DragonBones importer task graph:"
echo "  Epic: $EPIC"
echo ""
echo "Inspect with:"
echo "  bd show $EPIC"
echo "  bd children $EPIC"
echo "  bd ready"
