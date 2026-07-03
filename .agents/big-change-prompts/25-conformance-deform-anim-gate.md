# /big-change prompt - conformance (M18 animated mesh-deform story rig + goldens)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 4** of the M4 deform-timeline milestone. Depends
> on `24-runtime-nim-deform-timeline.md` (the Nim runtime that generates the
> goldens). Prompt `26-dart-deform-timeline-parity.md` consumes the goldens this
> prompt commits.
> **Candidate category:** frontier.

---

/big-change Add the first animated (nonzero-time) mesh conformance rig: a state-machine-driven "deform story" whose clip contains a deform timeline that moves a mesh's vertices over time, with committed multi-sample numeric goldens and a `.bnb` fixture, proving the cross-runtime deform-timeline contract.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Every existing mesh conformance rig (`m12`-`m17`) is a **setup-pose (`t=0`)**
golden; there is no animated mesh in the suite. And nonzero-time golden
generation is only reachable through the **state-machine + input-script story
path** - `bony golden-gen --t <nonzero>` is explicitly guarded to setup-pose
(`requireSetupPoseTime`, `cli/bony_cli.nim:175-180`: "`--t is reserved until
serialized animations are available`"), so every nonzero-t golden in the suite
(`m8_gesture_story`, `m9_non_scalar_story`, `m5_ik_story`, `m5_physics_story`) is
a state-machine story. This prompt adds `m18`, a state-machine **deform story**:
a mesh whose vertices are animated by a clip-owned deform timeline, sampled at
several times, following the exact `m9`/`m5-physics` story precedent.

**The rig (`conformance/assets/m18_mesh_deform_anim_rig.bony`).** Keep it
single-purpose and minimal - one animated mesh, nothing else:

- One identity `root` bone.
- One draw-order slot `mesh_slot` referencing an **unweighted** mesh attachment
  `panel` (raw `(x,y)` vertices in `root` space - unweighted keeps the golden's
  motion attributable solely to the deform deltas, not to skinning). Use a small
  vertex count (e.g. a 5-vertex diamond fan like `m17`, or a 4-vertex quad) so
  the golden is human-readable.
- **No** M7 deformer on this mesh, **no** clipping, **no** constraints (per the
  prompt-24 normative-order scope guard: the deform-vs-M7 ordering stays
  documented-but-unexercised in v1).
- One animation clip `wiggle` containing a `deformTimeline` (skin `"default"`,
  slot `mesh_slot`, attachment `panel`) with **at least three keyframes** that
  move one or more vertices by a clearly super-tolerance amount (>> `1e-4`; aim
  for tens of skeleton units) - e.g. key 0 at `t=0` with a single
  **zero-magnitude** delta at the target rim vertex's offset (a `(0,0)` delta -
  NOT an empty deltas list, which `validateDeformKey` rejects at
  `mesh/deform.nim:57-58`; the zero delta renders the static mesh at rest while
  still validating), key 1 at `t=0.5` pushing that rim vertex `+30` in x, key 2
  at `t=1.0` returning it toward `0`. Use a linear curve for at least one segment
  and (optionally) a stepped
  segment to exercise both interpolation paths in `sampleDeformDeltas`
  (`runtime-nim/src/bony/mesh/deform.nim:112-137`).
- One state machine `deform_story` whose single layer plays `wiggle` (mirror the
  `m9_non_scalar` state-machine rig shape; it is the simplest SM-plays-one-clip
  precedent).

**The input script (`conformance/scripts/m18_deform_story.json`).** Mirror
`conformance/scripts/m9_non_scalar_story.json`: `format`
`"bony.input-script.v1"`, `asset` `"m18_mesh_deform_anim_rig.bony"`,
`stateMachine` `"deform_story"`, and 3 samples with **stable names** and nonzero
times, e.g. `{"name":"rest","t":0.0}`, `{"name":"mid","t":0.5}`,
`{"name":"end","t":1.0}` (inputs `{}`). Must conform to
`spec/bony-input-script.schema.json`.

**The goldens.** State-machine scripts name goldens `<script-stem>_<sample>.json`
(`conformance/README.md`), so generate and commit
`conformance/goldens/m18_deform_story_rest.json`,
`m18_deform_story_mid.json`, `m18_deform_story_end.json` via
`bony golden-gen conformance/assets/m18_mesh_deform_anim_rig.bony <out>
--state-machine deform_story --input-script conformance/scripts/m18_deform_story.json
--sample <name>`. Also generate the `.bnb` fixture
`conformance/assets/bnb/m18_mesh_deform_anim_rig.bnb` via
`bony json-to-bnb`, so the input-script gate replays the `.bnb` against the same
goldens (the gate auto-picks up a matching `bnb/<stem>.bnb`,
`conformance/README.md` "input-script" section).

**Non-vacuity (state it in the README rig section).** Document, with the actual
generated numbers, that the animated vertex's world position in
`drawBatches[].vertices` sweeps a super-tolerance distance across `rest -> mid ->
end` (e.g. `x: 0 -> 30 -> ~0`), that the u/v are carried through unchanged, and
that a runtime which ignores the deform timeline (renders the static mesh at
every sample) fails at `mid`/`end`. Confirm the three goldens are **not**
byte-identical to each other and not to a static-mesh render.

**Wiring the rig into the suite:**

1. Author the four files (rig `.bony`, script, and generate the three goldens +
   the `.bnb`) following `conformance/README.md` "Adding a new milestone" steps.
2. Add an `m18` row to the milestone-coverage table in `conformance/README.md`
   ("Animated mesh deform: a clip-owned deform timeline moves mesh vertices over
   time; first nonzero-time mesh golden") and a dedicated `### M18 ...` rig
   section describing the geometry, the deform keys, and the non-vacuity numbers
   (mirror the `### M5 physics rig` / `### M17 mesh-clip rig` write-ups).
3. Confirm the input-script gate and round-trip gate pick up the new asset:
   `python3 scripts/ci/input_script_run.py --bony-bin <bin>` replays both the
   `.bony` and the `.bnb` against the three goldens; `round_trip_run.py`
   confirms the `.bnb` is byte-lossless.
4. Image golden is **not** required (mark it "pending (no PNG golden produced)"
   in the README image-golden table, consistent with the other story rigs).

Build the CLI and run the full suite locally to generate and verify:
```
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim
python3 scripts/ci/suite_run.py --bony-bin /tmp/bony_bin
```

**Links to Relevant Documentation**
- Binding contract: docs/deform-timeline-contract.md (prompt 23)
- Conformance guide: conformance/README.md (milestone table; "Numeric golden
  format"; "Input-script format"; "CI gates"; "Adding a new milestone" steps
  1-6; the state-machine story naming rule `<script-stem>_<sample>.json`)
- Closest precedents to copy:
  - conformance/assets/m9_non_scalar_rig.bony + conformance/scripts/
    m9_non_scalar_story.json + conformance/goldens/m9_non_scalar_story_projected.json
    (simplest SM-plays-one-clip nonzero-t story)
  - the `### M5 physics rig` README section (the model for a time-driven,
    non-vacuous, multi-sample story write-up)
  - conformance/assets/m17_mesh_clip_rig.bony (a 5-vertex diamond-fan unweighted
    mesh, for the geometry)
- Nim deform sampling algorithm the goldens must match:
  runtime-nim/src/bony/mesh/deform.nim (sampleDeformDeltas 112-137)
- CLI: cli/bony_cli.nim (golden-gen usage 17-18; state-machine golden path
  writeNumericGolden 1799-1843; --t setup-pose guard 175-180)
- Schema for the script: spec/bony-input-script.schema.json
- Suite runners: scripts/ci/suite_run.py, conformance_run.py,
  input_script_run.py, round_trip_run.py
- Template: the mesh conformance slice
  .agents/big-change-prompts/21-conformance-mesh-rig-golden.md and its landed diff
- Beads: file under the deform-timeline milestone parent

**Success Criteria**
- `conformance/assets/m18_mesh_deform_anim_rig.bony`,
  `conformance/scripts/m18_deform_story.json`,
  `conformance/assets/bnb/m18_mesh_deform_anim_rig.bnb`, and the three goldens
  `m18_deform_story_{rest,mid,end}.json` exist and are committed.
- The script validates against `spec/bony-input-script.schema.json`.
- The three goldens are non-vacuous (animated vertex sweeps a super-`1e-4`
  distance across samples), are not byte-identical to each other, and the README
  rig section documents the actual numbers.
- `python3 scripts/ci/suite_run.py --bony-bin /tmp/bony_bin` passes end to end,
  including the input-script gate replaying **both** the `.bony` and the
  `m18_..._rig.bnb` against the committed goldens, and the round-trip gate.
- `conformance/README.md` gains the `m18` coverage row, the `### M18` rig
  section, and the image-golden "pending" entry.
- Regenerating the goldens on a clean checkout reproduces them byte-identically
  (float-math determinism).
- `make test` passes.

**Constraints**
- Preserve clean-room posture: the rig and its goldens are authored from the
  project's own contract + runtime; do not derive geometry, motion, or field
  shapes from any third-party asset or runtime.
- Keep the rig single-purpose: one animated unweighted mesh via a deform
  timeline. Do NOT combine it with an M7 deformer, clipping, constraints,
  weighting, per-vertex color, or multiple slots (those are covered elsewhere or
  are separate milestones), so the golden's motion is attributable solely to the
  deform timeline.
- Use the state-machine story path for nonzero-time sampling; do NOT unlock or
  rely on plain `--t` clip sampling (`requireSetupPoseTime` stays as is - that is
  a separate format decision, not this milestone).
- Keep Rive importer out of scope; keep Spine importer blocked.
- Keep the slice to one meaningful implementation session: one rig + script +
  three goldens + `.bnb` + README wiring, all gates green.
