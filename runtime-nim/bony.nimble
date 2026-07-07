# Package

version       = "0.1.0"
author        = "birbparty"
description   = "Clean-room bony 2D skeletal animation reference runtime"
license       = "MIT"
srcDir        = "src"
bin           = @[]

requires "pixie == 6.1.0"
requires "naylib == 26.08.0"

# Tests use the local sibling checkout at ../../bddy, matching ~/git/bddy when
# this repository lives at ~/git/bony.
task test, "Run the Nim smoke tests":
  exec "nim c -r tests/test_smoke.nim"
  exec "nim c -r tests/test_bnb_wire.nim"
  exec "nim c -r tests/test_canonical_serialization.nim"
  exec "nim c -r tests/test_path_constraints.nim"
  exec "nim c -r tests/test_transform_constraints.nim"
  exec "nim c -r tests/test_physics_eval.nim"
  exec "nim c -r tests/test_nested_rig.nim"
  exec "nim c -r tests/test_draw_batches.nim"
  exec "nim c -r tests/test_cli_harness.nim"
  exec "nim c -r tests/test_dragonbones_import.nim"
  exec "nim c -r tests/test_mesh_geometry.nim"
  exec "nim c -r tests/test_mesh_deform.nim"
  exec "nim c -r tests/test_clipping.nim"
  exec "nim c -r tests/test_deformers.nim"
  exec "nim c -r tests/test_parameters_timelines.nim"
  exec "nim c -r tests/test_animation_mixing.nim"
  exec "nim c -r tests/test_state_machine_runtime.nim"
  exec "nim c -r tests/test_state_machine_validation.nim"
  exec "nim c -r tests/test_helper_geometry.nim"
  # CLI-private pose procs: included with -d:bonyExcludeMain (skips main());
  # --path:../cli resolves the CLI's local imports (nim.cfg supplies src + bddy).
  exec "nim c -r -d:bonyExcludeMain --path:../cli tests/test_cli_pose.nim"
  # IK current-pivot anchoring: includes transform.nim to drive private
  # applyRuntimeIk with a moved parent world (nim.cfg supplies src).
  exec "nim c -r tests/test_ik_current_pivot.nim"
  # Skin resolution, pointer/listener, and serialization-boundary suites.
  exec "nim c -r tests/test_skin_resolution.nim"
  exec "nim c -r tests/test_pointer_listener.nim"
  # Serialization-boundary suites (deterministic): BNB byte-stability, BNB
  # negative/mutation fuzz, and JSON<->BNB<->JSON idempotency.
  exec "nim c -r tests/test_bnb_byte_stability.nim"
  exec "nim c -r tests/test_bnb_fuzz.nim"
  exec "nim c -r tests/test_json_bnb_json_idempotency.nim"
  # Event-timeline load + eventKeys .bnb round-trip + load-validation invariants.
  exec "nim c -r tests/test_event_timeline.nim"
  exec "nim c -r tests/test_draw_order_timeline.nim"

task bench, "Run the non-gating perf harness (always exits 0)":
  exec "nim c -r bench_perf.nim"
