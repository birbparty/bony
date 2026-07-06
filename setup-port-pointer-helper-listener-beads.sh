#!/usr/bin/env bash
# Project: bony
# Change: Port pointer helper listener dispatch to Dart and match M21 goldens
# Generated: 2026-07-06

set -euo pipefail

if [ ! -d ".beads" ]; then
  bd init
fi

echo "Creating Beads graph for Dart pointer helper listener dispatch..."

# Parent epic. This is an organizational rollup only: every task below is
# parented to it, and no blocking dependencies are added to or from the epic.
EPIC=$(bd create "Epic: Port pointer helper listener dispatch to Dart and match M21 goldens" \
  --type epic \
  --priority 0 \
  --labels epic,m21,pointer-listener,dart-parity \
  --description "Rollup for the Dart parity port of project-owned pointer helper listener runtime behavior. The serialized contract, Nim reference, conformance assets, and Dart model/loader fields already exist; this graph tracks the remaining Dart runtime, tests, and verification work." \
  --acceptance "All child tasks are closed; Dart pointer helper listener dispatch matches the Nim reference and all m21_pointer_listener rest/enter/down/move/up/exit goldens for both .bony and .bnb assets within 1e-4." \
  --notes "This epic is a rollup only. Do not add bd dep edges to or from it; use --parent membership for all child beads. Marked in_progress immediately so bd ready does not dispatch it as work." \
  --silent)
bd update "$EPIC" --status in_progress

# Phase 1: Analysis and characterization.
ANALYZE_REFERENCE=$(bd create "Analyze Nim pointer helper listener dispatch and helper geometry reference" \
  --type task \
  --priority 0 \
  --labels analysis,reference,nim \
  --parent "$EPIC" \
  --description "Read runtime-nim/src/bony/statemachine/core.nim and runtime-nim/src/bony/transform.nim around StateMachineListenerEvent, validatePointerListenerTargets, visibleSlotTarget, listenerHit, addPointerEvent, dispatchPointerListeners, worldPointAttachmentPose, worldBoundingBoxAttachmentPolygon, pointInHelperPolygon, pointerHitsPointTarget, and pointerHitsBoundingBoxTarget." \
  --acceptance "Notes or task updates capture the exact Nim dispatch order, active-skin/visible target rule, pointer event payload fields, finite-coordinate validation, point radius behavior, bounding-box boundary tolerance, and helper error cases needed for Dart parity." \
  --notes "Observed entry points include runtime-nim/src/bony/statemachine/core.nim:909 for dispatchPointerListeners and runtime-nim/src/bony/transform.nim:273 for helper world queries. helperGeometryTolerance is 1e-4 and point hits use distance <= hitRadius." \
  --silent)

MAP_DART_SURFACE=$(bd create "Map Dart model, loader, runtime, transform, and export seams for pointer listeners" \
  --type task \
  --priority 0 \
  --labels analysis,dart,surface \
  --parent "$EPIC" \
  --description "Inspect runtime-dart/lib/src/model.dart, loader.dart, statemachine.dart, transform.dart, and runtime-dart/lib/bony.dart. Confirm StateMachineListenerKind, PointerHelperTargetKind, StateMachineListener fields, loader validation, StateMachineRuntime input mutation APIs, lifecycle event compatibility, Affine2 helpers, and package-root export policy." \
  --acceptance "Task notes identify the exact Dart APIs to preserve, the missing runtime pieces, and whether any new helper query or dispatch symbols should be public or package-visible." \
  --notes "Current Dart state: model.dart already has pointer listener kinds and helper target fields; loader.dart parses/validates JSON and .bnb listener records; statemachine.dart currently emits lifecycle-only StateMachineListenerEvent payloads; transform.dart has Affine2 and _basisEpsilon but lacks helper hit-test APIs." \
  --silent)

AUDIT_ARCH_DOCS=$(bd create "Audit architecture context and confirm no docs/specs or docs/adr decisions are present" \
  --type task \
  --priority 1 \
  --labels analysis,docs \
  --parent "$EPIC" \
  --description "Check docs/specs/ and docs/adr/ before implementation, then use docs/CLEANROOM.md, docs/PROVENANCE.md, docs/pointer-helper-listener-contract.md, docs/helper-geometry-attachment-contract.md, docs/float-math-contract.md, conformance/README.md, and docs/comparable-feature-set.md only for allowed capability-category context." \
  --acceptance "Task notes state whether docs/specs or docs/adr exist in the checkout and list the contract docs that govern Dart behavior. Any contract defect found stops the Dart port and files follow-up work instead of creating Dart-only semantics." \
  --notes "Initial inspection found no docs/specs/ or docs/adr/ directories. Reference-only surfaces are runtime-nim/**, conformance/assets/m21_pointer_listener_rig.bony, conformance/assets/bnb/m21_pointer_listener_rig.bnb, conformance/scripts/m21_pointer_listener_story.json, and conformance/goldens/**." \
  --silent)

CHARACTERIZE_CURRENT_DART=$(bd create "Add Dart characterization tests before runtime pointer dispatch changes" \
  --type task \
  --priority 1 \
  --labels prep,testing,dart \
  --parent "$EPIC" \
  --description "Add focused tests around current Dart lifecycle listener event compatibility and existing pointer listener JSON/.bnb loading behavior before changing runtime dispatch. Prefer runtime-dart/test/m8_statemachine_test.dart for loader/listener coverage and avoid changing serialized semantics." \
  --acceptance "Tests prove existing lifecycle events keep listener/kind/layer/fromState/toState behavior and pointer listener records still load with slot, targetKind, target, hitRadius, input, boolValue, and numberValue populated. Existing malformed JSON validation remains covered." \
  --notes "Existing runtime-dart/test/m8_statemachine_test.dart has lifecycle event tests around line 259 and pointer helper listener JSON validation around line 644; extend locally or add a focused test if cleaner." \
  --silent)
bd dep add "$CHARACTERIZE_CURRENT_DART" "$MAP_DART_SURFACE"
bd dep add "$CHARACTERIZE_CURRENT_DART" "$AUDIT_ARCH_DOCS"

# Phase 2: Runtime implementation.
HELPER_QUERY_API=$(bd create "Implement Dart helper world query APIs in transform.dart" \
  --type task \
  --priority 0 \
  --labels impl,dart,geometry \
  --parent "$EPIC" \
  --description "Add Dart equivalents of Nim worldPointAttachmentPose and worldBoundingBoxAttachmentPolygon in runtime-dart/lib/src/transform.dart. Reuse existing Affine2, computeWorldTransforms, _transformPoint, and world rotation decomposition patterns." \
  --acceptance "Dart callers can query a point helper world x/y/rotation and a bounding-box helper world polygon by slot and attachment name; unknown slots or attachments raise FormatException-compatible errors; no helper attachments become visible draw batches." \
  --notes "Keep math aligned with runtime-nim/src/bony/transform.nim and docs/helper-geometry-attachment-contract.md. Do not edit registry, generated wire files, conformance assets, or Nim sources." \
  --silent)
bd dep add "$HELPER_QUERY_API" "$ANALYZE_REFERENCE"
bd dep add "$HELPER_QUERY_API" "$MAP_DART_SURFACE"

HELPER_HIT_TEST_API=$(bd create "Implement Dart helper hit testing for point radius and bounding-box polygons" \
  --type task \
  --priority 0 \
  --labels impl,dart,geometry \
  --parent "$EPIC" \
  --description "Add Dart equivalents of Nim pointInHelperPolygon, pointerHitsPointTarget, and pointerHitsBoundingBoxTarget. Point listeners hit when distance is <= hitRadius. Bounding-box listeners use transformed polygon vertices and helper boundary tolerance." \
  --acceptance "Point hit tests reject negative hitRadius and accept exact-radius hits. Polygon hit tests reject fewer than three points, accept points within the 1e-4 boundary tolerance, and match Nim ray-crossing behavior for inside/outside decisions." \
  --notes "Nim uses basisEpsilon 1e-12 and helperGeometryTolerance 1e-4. Dart already has _basisEpsilon in runtime-dart/lib/src/transform.dart; expose only the API surface needed by tests and host code." \
  --silent)
bd dep add "$HELPER_HIT_TEST_API" "$HELPER_QUERY_API"

POINTER_EVENT_PAYLOAD=$(bd create "Extend Dart StateMachineListenerEvent for pointer listener payloads without breaking lifecycle callers" \
  --type task \
  --priority 0 \
  --labels impl,dart,statemachine \
  --parent "$EPIC" \
  --description "Extend runtime-dart/lib/src/statemachine.dart StateMachineListenerEvent so pointer events can expose slot, target kind/name, input, input kind, bool value, number value, trigger marker, pointer x/y, and pointer-presence marker. Preserve existing lifecycle event constructor behavior and public fields used by M8 tests." \
  --acceptance "Lifecycle event tests keep passing without requiring callers to provide pointer-only fields. Pointer event instances can represent every payload field emitted by Nim addPointerEvent, including hasPointer true and triggerValue for trigger inputs." \
  --notes "Nim StateMachineListenerEvent includes listener, kind, layer/from/to lifecycle fields, slot, targetKind, target, input, inputKind, boolValue/hasBoolValue, numberValue/hasNumberValue, triggerValue, pointerX, pointerY, and hasPointer." \
  --silent)
bd dep add "$POINTER_EVENT_PAYLOAD" "$ANALYZE_REFERENCE"
bd dep add "$POINTER_EVENT_PAYLOAD" "$CHARACTERIZE_CURRENT_DART"

POINTER_DISPATCH=$(bd create "Implement Dart StateMachineRuntime pointer listener dispatch" \
  --type task \
  --priority 0 \
  --labels impl,dart,statemachine \
  --parent "$EPIC" \
  --description "Add StateMachineRuntime.dispatchPointerListeners or the local-pattern equivalent in runtime-dart/lib/src/statemachine.dart. Validate pointer kind, finite pointer coordinates, active helper visibility through the current skin, geometry hits, input kind/value mutation, and event append order." \
  --acceptance "Dispatch rejects non-pointer listener kinds; scans listeners in array order; skips inactive slot targets; mutates bool/number/trigger inputs before transition evaluation; appends pointer events to the existing events channel before update/evaluate can append later lifecycle events; animationEvents is untouched." \
  --notes "Use existing setBoolInput, setNumberInput, and fireTrigger methods. Match Nim dispatchPointerListeners rather than inventing new input-script or hover-state semantics. Host code must be able to call dispatch, then update(0.0), and see pointer events before transition lifecycle events." \
  --silent)
bd dep add "$POINTER_DISPATCH" "$HELPER_HIT_TEST_API"
bd dep add "$POINTER_DISPATCH" "$POINTER_EVENT_PAYLOAD"

EXPORT_POINTER_API=$(bd create "Export any required public Dart pointer helper dispatch/query API from runtime-dart/lib/bony.dart" \
  --type task \
  --priority 2 \
  --labels impl,dart,api \
  --parent "$EPIC" \
  --description "Update runtime-dart/lib/bony.dart only if the new helper query or pointer dispatch symbols are intended for package consumers or conformance tests. Keep internal helpers private where package-visible access is enough." \
  --acceptance "All tests import through the package root where appropriate, no debug rendering APIs are exposed, and no new serialized pointer listener kinds, helper target kinds, or registry keys are introduced." \
  --notes "This task may be a no-op if implementation uses existing exported runtime types and package-private helpers are sufficient." \
  --silent)
bd dep add "$EXPORT_POINTER_API" "$POINTER_DISPATCH"

# Phase 3: Focused tests.
LOADER_REGRESSION_TESTS=$(bd create "Broaden Dart pointer listener loader regression tests for JSON and BNB" \
  --type task \
  --priority 1 \
  --labels testing,dart,loader \
  --parent "$EPIC" \
  --description "Extend runtime-dart/test/m8_statemachine_test.dart or add a focused loader test to cover valid pointer listener JSON and .bnb records plus malformed validation cases matching docs/pointer-helper-listener-contract.md and loader.dart behavior." \
  --acceptance "Coverage includes lifecycle fields on pointer listeners, pointer fields on lifecycle listeners, unknown slot/target/input, invalid target kind, missing/invalid point hitRadius, invalid bounding-box hitRadius, missing bool/number values, bool-vs-number mismatches, and forbidden trigger values for both feasible JSON and BNB paths." \
  --notes "Do not change wire semantics unless an actual mismatch with the project contract or Nim reference is found; if found, stop and file a contract/loader correction task." \
  --silent)
bd dep add "$LOADER_REGRESSION_TESTS" "$MAP_DART_SURFACE"
bd dep add "$LOADER_REGRESSION_TESTS" "$CHARACTERIZE_CURRENT_DART"

HELPER_GEOMETRY_TESTS=$(bd create "Add Dart helper query and hit-test unit tests" \
  --type task \
  --priority 1 \
  --labels testing,dart,geometry \
  --parent "$EPIC" \
  --description "Extend runtime-dart/test/helper_geometry_attachment_test.dart or add a focused test for helper world point pose, bounding-box polygon transformation, point radius hits, bounding-box inside/outside hits, boundary tolerance, and malformed query inputs." \
  --acceptance "Tests cover transformed helper coordinates, point hit at radius equality, point miss just outside radius, polygon boundary acceptance within 1e-4, polygon outside rejection, unknown helper references, and polygon size validation." \
  --notes "Existing helper_geometry_attachment_test.dart covers JSON/.bnb loading and invisibility to draw batches but not runtime query or hit-test behavior." \
  --silent)
bd dep add "$HELPER_GEOMETRY_TESTS" "$HELPER_HIT_TEST_API"

POINTER_DISPATCH_TESTS=$(bd create "Add Dart pointer dispatch unit tests for mutation, ordering, payloads, and lifecycle compatibility" \
  --type task \
  --priority 1 \
  --labels testing,dart,statemachine \
  --parent "$EPIC" \
  --description "Add focused StateMachineRuntime tests proving pointer dispatch behavior against a compact fixture with point and bounding-box helper listeners. Cover bool, number, and trigger input mutations, skipped misses, active-skin/visible-target gating, listener array order, pointer event payload fields, and lifecycle event compatibility after update." \
  --acceptance "A pointer dispatch mutates the configured input before transition evaluation; pointer events appear in events before transition/state lifecycle events caused by update(0.0); events use the state-machine events channel, not animationEvents; misses and inactive helper targets do not mutate inputs or emit events." \
  --notes "Mirror the intent of runtime-nim/tests/test_pointer_listener.nim while keeping Dart tests idiomatic and scoped." \
  --silent)
bd dep add "$POINTER_DISPATCH_TESTS" "$POINTER_DISPATCH"

# Phase 4: M21 conformance.
M21_REPLAY_TEST=$(bd create "Add Dart M21 pointer listener story conformance replay for JSON and BNB assets" \
  --type task \
  --priority 0 \
  --labels testing,dart,conformance,m21 \
  --parent "$EPIC" \
  --description "Create runtime-dart/test/m21_pointer_listener_test.dart following the story-test style from m5_ik_story_test.dart, m5_physics_story_test.dart, m18_deform_story_test.dart, and m19_event_story_test.dart. Replay conformance/scripts/m21_pointer_listener_story.json against conformance/assets/m21_pointer_listener_rig.bony and conformance/assets/bnb/m21_pointer_listener_rig.bnb." \
  --acceptance "The test compares rest, enter, down, move, up, and exit samples to conformance/goldens/m21_pointer_listener_*.json within 1e-4 for world transforms, draw batches, helper slot metadata, state-machine layers, and listener events." \
  --notes "Prefer one focused M21 test file over expanding setup-pose-only m10_conformance_test.dart. Do not modify M21 assets or goldens unless a proven contract defect is escalated." \
  --silent)
bd dep add "$M21_REPLAY_TEST" "$POINTER_DISPATCH"
bd dep add "$M21_REPLAY_TEST" "$EXPORT_POINTER_API"

M21_NONVACUITY_TESTS=$(bd create "Add M21 pointer listener non-vacuity assertions for event ordering and asset parity" \
  --type task \
  --priority 1 \
  --labels testing,dart,conformance,m21 \
  --parent "$EPIC" \
  --description "Strengthen runtime-dart/test/m21_pointer_listener_test.dart with assertions that prove the story exercises the intended pointer behavior rather than only matching empty or static output." \
  --acceptance "The down sample proves pointer event precedes idle_exit, idle_to_pressed, and pressed_enter after transition evaluation. Move/up samples prove the rotated point and/or helper hit path is exercised. Exit proves hover false mutation. BNB output matches JSON output for listener event payloads and numeric output." \
  --notes "These assertions should complement golden comparisons and make failures diagnosable when dispatch ordering, hit testing, or BNB listener loading regresses." \
  --silent)
bd dep add "$M21_NONVACUITY_TESTS" "$M21_REPLAY_TEST"

# Phase 5: Documentation, verification, and closeout.
DOC_AUDIT=$(bd create "Audit pointer helper listener Dart parity docs after implementation" \
  --type task \
  --priority 2 \
  --labels docs,audit \
  --parent "$EPIC" \
  --description "Review docs/pointer-helper-listener-contract.md, docs/helper-geometry-attachment-contract.md, docs/float-math-contract.md, and conformance/README.md after the Dart port lands. Update only stale Dart parity notes or conformance status; do not broaden the serialized contract." \
  --acceptance "Docs remain accurate about helper target kinds, point hitRadius semantics, bounding-box boundary tolerance, listener event channel/order, and JSON/BNB conformance. If no edits are needed, close with notes explaining why." \
  --notes "Keep clean-room posture: do not add prose or behavior derived from third-party runtime/source material." \
  --silent)
bd dep add "$DOC_AUDIT" "$M21_REPLAY_TEST"

FULL_VERIFY=$(bd create "Run final verification for Dart pointer helper listener port" \
  --type task \
  --priority 0 \
  --labels testing,verification \
  --parent "$EPIC" \
  --description "Run the full required verification suite from the repo root after implementation and tests are in place: python3 codegen/generate.py --check; python3 -m unittest discover -s codegen -p 'test_*.py'; make test; cd runtime-dart && dart test." \
  --acceptance "All listed commands pass. bd dep cycles reports no cycles. bd children \$EPIC shows all child tasks under the epic. bd ready shows implementation-complete follow-up status and not the epic itself." \
  --notes "If any verification failure reveals follow-up work, file specific beads before closing this verification task." \
  --silent)
bd dep add "$FULL_VERIFY" "$LOADER_REGRESSION_TESTS"
bd dep add "$FULL_VERIFY" "$HELPER_GEOMETRY_TESTS"
bd dep add "$FULL_VERIFY" "$POINTER_DISPATCH_TESTS"
bd dep add "$FULL_VERIFY" "$M21_NONVACUITY_TESTS"
bd dep add "$FULL_VERIFY" "$DOC_AUDIT"

CLOSEOUT=$(bd create "Close out M21 Dart pointer listener parity graph and persist Beads state" \
  --type task \
  --priority 1 \
  --labels cleanup,closeout \
  --parent "$EPIC" \
  --description "After FULL_VERIFY passes, close completed beads, update the epic status, run bd preflight, push Beads data with bd dolt push, and include the implementation commit(s) in the normal git push flow." \
  --acceptance "All completed child beads are closed with useful reasons, remaining follow-up work has beads, bd dolt push succeeds, git push succeeds, and git status reports the branch is up to date with origin." \
  --notes "This is a workflow closeout task, not an implementation task. Keep it blocked until verification passes." \
  --silent)
bd dep add "$CLOSEOUT" "$FULL_VERIFY"

echo ""
echo "Created epic: $EPIC"
echo ""
echo "Inspect the graph with:"
echo "  bd show $EPIC"
echo "  bd children $EPIC"
echo "  bd dep tree $EPIC"
echo "  bd dep cycles"
echo "  bd ready"
