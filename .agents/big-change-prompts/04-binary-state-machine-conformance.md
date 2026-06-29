# /big-change prompt - conformance/ci (.bnb state-machine replay gate)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 3**. Depends on step 2 enabling `.bnb`
> animation/state-machine loading and CLI replay.
> **Candidate category:** frontier.

---

/big-change Add conformance coverage for `.bnb` state-machine input-script replay.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Once `.bnb` assets preserve animations and state machines, make that behavior a
conformance gate. The existing input-script gate validates `.bony`
state-machine replay; this slice should make `.bnb` replay compare against the
same committed state-machine goldens whenever a matching binary fixture exists.

This closes the loop for `bony-0vw`: `.bnb` is no longer a setup-pose-only
shipping format for animated interactive assets.

**Links to Relevant Documentation**

- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md`
- Conformance docs: `conformance/README.md`
- CLI docs: `cli/README.md`
- Input-script schema: `spec/bony-input-script.schema.json`
- Numeric golden comparator: `scripts/ci/_golden_compare.py`
- Numeric golden runner: `scripts/ci/conformance_run.py`
- Input-script runner: `scripts/ci/input_script_run.py`
- Round-trip runner: `scripts/ci/round_trip_run.py`
- Suite runner: `scripts/ci/suite_run.py`
- Schema validation runner: `scripts/ci/schema_validate_assets.py`
- Existing M8 asset: `conformance/assets/m8_rig.bony`
- Existing M8 binary fixture: `conformance/assets/bnb/m8_rig.bnb`
- Existing M8 input scripts: `conformance/scripts/m8_sample.json`,
  `conformance/scripts/m8_gesture_story.json`
- Existing M8 state-machine goldens:
  `conformance/goldens/m8_gesture_story_initial_idle.json`,
  `conformance/goldens/m8_gesture_story_wave_on.json`,
  `conformance/goldens/m8_gesture_story_speed_mid.json`,
  `conformance/goldens/m8_gesture_story_speed_fast.json`,
  `conformance/goldens/m8_gesture_story_jump_trigger.json`,
  `conformance/goldens/m8_gesture_story_wave_off.json`,
  `conformance/goldens/m8_gesture_story_settled_idle.json`
- Existing M9 non-scalar asset and fixtures:
  `conformance/assets/m9_non_scalar_rig.bony`,
  `conformance/assets/bnb/m9_non_scalar_rig.bnb`,
  `conformance/goldens/m9_non_scalar_rig_t0.json`
- Beads: `bony-0vw`, `bony-03b`, `bony-n4l`

**Current Local Facts To Preserve**

- `scripts/ci/input_script_run.py` is the canonical consumer of
  `bony.input-script.v1` and currently invokes `golden-gen` once per script
  sample against the `.bony` asset named by the script.
- `scripts/ci/conformance_run.py` already compares setup-pose `.bony` and
  `.bnb` assets against the same `*_t0.json` goldens.
- `scripts/ci/round_trip_run.py` already checks `.bony -> .bnb` bytes and
  `.bnb -> .bony -> .bnb` byte stability for `*_rig.bnb` fixtures.
- `conformance/README.md` documents M8 input-script state-machine goldens, but
  its milestone table does not currently list the present M9 non-scalar asset.
- `conformance/assets/bnb/m8_rig.bnb` and
  `conformance/assets/bnb/m9_non_scalar_rig.bnb` already exist; after step 2,
  they may need regeneration because the binary writer should preserve
  animation/state-machine data.

**Success Criteria**

- Regenerate committed `.bnb` fixtures whose canonical bytes change because
  animations/state machines are now serialized. At minimum, verify
  `conformance/assets/bnb/m8_rig.bnb`; include other changed fixtures only when
  `scripts/ci/round_trip_run.py` proves they need it.
- Update `scripts/ci/input_script_run.py` so a state-machine script runs against
  the `.bony` asset and, when a matching `conformance/assets/bnb/<stem>.bnb`
  exists, also runs against that `.bnb` asset and compares to the same committed
  golden. Keep setup-pose-only scripts backward-compatible.
- Ensure `.bnb` state-machine replay uses the same sample-name golden naming
  scheme as `.bony` replay; do not create duplicate golden files just because
  the input asset extension differs.
- Update labels/output in `scripts/ci/input_script_run.py` so failures make it
  clear whether `.bony` or `.bnb` replay failed.
- Keep `scripts/ci/conformance_run.py` setup-pose `.bnb` checks intact.
- Keep `scripts/ci/round_trip_run.py` byte-stability checks intact after
  fixture regeneration.
- Update `conformance/README.md` to document `.bnb` state-machine replay as a
  cross-runtime gate and to list the existing M9 non-scalar rig accurately.
- Update `cli/README.md` if step 2 did not already remove stale `.bony`-only
  language.
- Verification commands should include at minimum:

```bash
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim
python3 scripts/ci/round_trip_run.py --bony-bin /tmp/bony_bin
python3 scripts/ci/conformance_run.py --bony-bin /tmp/bony_bin
python3 scripts/ci/input_script_run.py --bony-bin /tmp/bony_bin
python3 scripts/ci/suite_run.py --bony-bin /tmp/bony_bin
cd runtime-dart && dart test
```

**Constraints**

- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not expand the input-script schema unless a concrete conformance failure
  proves the existing schema cannot express `.bnb` parity.
- Do not regenerate image goldens unless the image gate fails for a behavior
  change introduced by steps 1 or 2. The open regen trackers `bony-03b` and
  `bony-n4l` remain separate obligations.
- Do not add new animation/state-machine capability; this slice gates binary
  parity for the features already present.
