.PHONY: test dart-test

# Repo-level gate used by /ralph's per-iteration VERIFY step and by the
# registry README's format-gate requirement for any registry/** edit.
# Runs, in fail-fast order:
#   1. the codegen format check (sources <-> generated agree),
#   2. the Python codegen unit tests,
#   3. the Nim runtime model COMPILE check (fast fail on library errors), and
#   4. the Nim runtime unit and conformance tests, and
#   5. the Dart runtime UNIT TESTS.
#
# Step 4 is gated here deliberately — not just the `nim check` compile in step 3.
# The runtime tests carry the change-detector and conformance-fixture-count
# assertions (e.g. registry key/property counts, the `loaded == N` bnb-fixture
# count). Running only `nim check` let a stale `loaded == 8` assertion survive
# ~13 ralph iterations after a fixture was added, because a green compile is not
# a green test run. See bony-bru.
#
# NOTE: these are the raw `nim c -r` invocations from bony.nimble's `test` task,
# NOT `nimble test` — nimble SWALLOWS a failing task's exec exit code and returns
# 0, which would make this gate vacuously green (the very failure mode above).
# Raw `nim c -r` propagates the non-zero exit so `make` fails the recipe.
test:
	python3 codegen/generate.py --check
	python3 -m unittest discover -s codegen -p 'test_*.py'
	nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim
	cd runtime-nim && nim c -r --hints:off tests/test_smoke.nim
	cd runtime-nim && nim c -r --hints:off tests/test_bnb_wire.nim
	cd runtime-nim && nim c -r --hints:off tests/test_canonical_serialization.nim
	cd runtime-nim && nim c -r --hints:off tests/test_path_constraints.nim
	cd runtime-nim && nim c -r --hints:off tests/test_transform_constraints.nim
	cd runtime-nim && nim c -r --hints:off tests/test_physics_eval.nim
	cd runtime-nim && nim c -r --hints:off tests/test_nested_rig.nim
	cd runtime-nim && nim c -r --hints:off tests/test_draw_batches.nim
	cd runtime-nim && nim c -r --hints:off tests/test_cli_harness.nim
	cd runtime-nim && nim c -r --hints:off tests/test_dragonbones_import.nim
	cd runtime-nim && nim c -r --hints:off tests/test_mesh_geometry.nim
	cd runtime-nim && nim c -r --hints:off tests/test_mesh_deform.nim
	cd runtime-nim && nim c -r --hints:off tests/test_clipping.nim
	cd runtime-nim && nim c -r --hints:off tests/test_deformers.nim
	cd runtime-nim && nim c -r --hints:off tests/test_parameters_timelines.nim
	cd runtime-nim && nim c -r --hints:off tests/test_animation_mixing.nim
	cd runtime-nim && nim c -r --hints:off tests/test_state_machine_runtime.nim
	cd runtime-nim && nim c -r --hints:off tests/test_state_machine_validation.nim
	cd runtime-nim && nim c -r --hints:off tests/test_helper_geometry.nim
	cd runtime-nim && nim c -r --hints:off -d:bonyExcludeMain --path:../cli tests/test_cli_pose.nim
	cd runtime-nim && nim c -r --hints:off -d:bonyExcludeMain --path:../cli tests/test_m20_skin_conformance.nim
	cd runtime-nim && nim c -r --hints:off -d:bonyExcludeMain --path:../cli tests/test_m22_skin_required_conformance.nim
	cd runtime-nim && nim c -r --hints:off -d:bonyExcludeMain --path:../cli tests/test_m21_pointer_listener_conformance.nim
	cd runtime-nim && nim c -r --hints:off -d:bonyExcludeMain --path:../cli tests/test_m23_nested_rig_conformance.nim
	cd runtime-nim && nim c -r --hints:off tests/test_ik_current_pivot.nim
	cd runtime-nim && nim c -r --hints:off tests/test_skin_resolution.nim
	cd runtime-nim && nim c -r --hints:off tests/test_bnb_byte_stability.nim
	cd runtime-nim && nim c -r --hints:off tests/test_bnb_fuzz.nim
	cd runtime-nim && nim c -r --hints:off tests/test_json_bnb_json_idempotency.nim
	cd runtime-nim && nim c -r --hints:off tests/test_event_timeline.nim
	cd runtime-nim && nim c -r --hints:off tests/test_pointer_listener.nim
	$(MAKE) dart-test

dart-test:
	cd runtime-dart && flutter test
