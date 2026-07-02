# /big-change prompt - conformance gate (M5 physics constraint, Nim reference)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 4** of the M5 physics milestone. Depends on
> `12-runtime-nim-physics-evaluation.md` (needs a working evaluator). Must land
> before `14-dart-physics-constraint-parity.md` (Dart is gated on the numeric
> golden this prompt produces).
> **Candidate category:** frontier.

---

/big-change Add a cross-runtime conformance gate for physics constraints: a state-machine-driven story rig whose spring offset settles non-vacuously over time, with Nim reference goldens.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Physics is time-dependent: at `t=0` a freshly seeded spring has zero offset, so
a single setup-pose (`t=0`) golden would be **vacuous**. The conformance gate
must drive time. The input-script harness already supports this ONLY through the
state-machine story path: per `spec/bony-input-script.schema.json`,
state-machine scripts "apply sample inputs, advance by the delta from the
previous sample time, and then evaluate," carrying a `StateMachineRuntime`
across samples — and `cli/bony_cli.nim` (~line 178) reserves plain `--t` for
setup-pose output only. So the physics rig must be a **state-machine story**,
exactly like `m5_ik_story` (`conformance/scripts/m5_ik_story.json` →
`conformance/goldens/m5_ik_story_{rest,reach_mid,reach_end}.json`) and
`m8_gesture_story`.

Build exactly this (Nim reference only):
1. **Rig.** `conformance/assets/m5_physics_rig.bony`: a small skeleton with one
   bone driven by a `physicsConstraint` on at least one channel (e.g. `rotate`
   or `x`) with a non-zero `strength` (and a non-zero `mass`/`damping` so it
   settles rather than diverges), plus a state machine whose clip animates the
   bone's target so the spring is excited and then settles. Choose parameters so
   the spring is clearly under- or critically-damped and the offset trajectory
   is monotone-per-segment and well above `1e-4` between samples. Generate
   `conformance/assets/bnb/m5_physics_rig.bnb` with the Nim CLI
   `bony json-to-bnb <src.bony> <dst.bnb>` (the tool that produced
   `m5_ik_rig.bnb`/`m5_transform_rig.bnb`).
2. **Story script.** `conformance/scripts/m5_physics_story.json`
   (`bony.input-script.v1`, with a `stateMachine` field and named samples,
   mirroring `m5_ik_story.json`): at least three samples at increasing `t`
   (e.g. `rest` at `t=0`, `excited` at a mid time, `settled` at a later time)
   so the harness advances the physics state by the inter-sample delta.
3. **Goldens.** Emit `conformance/goldens/m5_physics_story_{rest,excited,settled}.json`
   from the Nim reference via the CLI `golden-gen ... --state-machine <name>
   --input-script <script.json> --sample <name>` path (see the "Adding a new
   milestone" / story recipe in `conformance/README.md`). The CI scripts under
   `scripts/ci/` VERIFY goldens; they do not emit them.
4. **Gate wiring.** The CI runners (`conformance_run.py`, `input_script_run.py`,
   `round_trip_run.py`, `schema_validate_assets.py`) auto-discover assets/
   scripts/goldens by glob, so a correctly-named story rig is picked up with no
   registration-list edit — confirm this by running `python3
   scripts/ci/suite_run.py` and seeing the new goldens exercised. Separately,
   the Nim unit test `runtime-nim/tests/test_smoke.nim` has a
   `"loads all committed m*_rig.bnb conformance fixtures"` test that hardcodes
   `loaded == 10` (test_smoke.nim:467, walking `conformance/assets/bnb/*_rig.bnb`);
   adding `m5_physics_rig.bnb` makes it an 11th fixture, so bump that count to
   `11` or `make test` fails.
5. **Docs.** Add an `M5 (physics)` row to the milestone-coverage table in
   `conformance/README.md` and an `m5_physics_rig` section mirroring the
   `M5 (IK)` story section, explicitly documenting the **non-vacuous** offset
   trajectory across samples (report the actual channel value / world-angle or
   world-translation delta between `rest`, `excited`, and `settled`, and confirm
   each inter-sample delta exceeds `1e-4`). Note in that section that the story
   goldens are Nim-only until the Dart parity slice (prompt 14) lands — mirror
   the wording already used for the `m5_ik_story` Dart-pending note.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Physics runtime contract: docs/physics-integrator-contract.md
- Conformance overview + story recipe: conformance/README.md
- Input-script schema (state-machine time-advance semantics):
  spec/bony-input-script.schema.json
- Analogous story assets to template: conformance/assets/m5_ik_rig.bony,
  conformance/scripts/m5_ik_story.json,
  conformance/goldens/m5_ik_story_{rest,reach_mid,reach_end}.json; and
  conformance/scripts/m8_gesture_story.json
- CLI (golden emission, story path; plain `--t` is setup-pose only): cli/bony_cli.nim
- CI runners: scripts/ci/suite_run.py, scripts/ci/conformance_run.py,
  scripts/ci/input_script_run.py, scripts/ci/round_trip_run.py,
  scripts/ci/schema_validate_assets.py
- Repo gate: Makefile `test` target
- Beads: file under the physics milestone parent before implementing

**Success Criteria**
- `conformance/assets/m5_physics_rig.bony` + `.../bnb/m5_physics_rig.bnb` +
  `conformance/scripts/m5_physics_story.json` +
  `conformance/goldens/m5_physics_story_{rest,excited,settled}.json` exist and
  validate (`python3 scripts/ci/schema_validate_assets.py` passes).
- The Nim reference reproduces every physics story golden from BOTH the `.bony`
  and the `.bnb` (JSON and binary loaders agree); `python3 scripts/ci/suite_run.py`
  passes end-to-end.
- The goldens are **non-vacuous and settling**: `conformance/README.md`
  documents the offset trajectory and confirms each inter-sample delta exceeds
  `1e-4`, and the trajectory settles (does not diverge) across samples.
- `conformance/README.md` has an `M5 (physics)` coverage row and rig section.
- `make test` passes.

**Constraints**
- Preserve clean-room posture (no third-party runtime/importer source, wire
  layouts, keys, docs prose, or example rigs). The rig and parameters are
  project-authored.
- The physics golden MUST be a state-machine story (time-advanced across
  samples). Do NOT try to force a non-vacuous physics result through a
  setup-pose (`--t 0`) golden — plain `--t` is reserved for setup pose.
- Do **NOT** implement the Dart runtime here (prompt 14) — the story goldens are
  Nim-only this slice, and the README must say so.
- Keep the slice to one meaningful implementation session: one story rig, its
  goldens, gate wiring, and docs.
