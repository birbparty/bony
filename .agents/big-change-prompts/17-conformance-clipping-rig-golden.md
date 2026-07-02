# /big-change prompt - conformance (M4 clipping attachment rig + golden)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 4** of the M4 clipping-attachment milestone.
> Depends on `16-runtime-nim-clipping-evaluation.md` (the Nim runtime must
> actually clip so goldens are non-vacuous). Prompt 18 (Dart parity) consumes the
> golden this prompt commits.
> **Candidate category:** frontier.

---

/big-change Add a cross-runtime conformance rig, input script, and numeric golden for the clipping attachment, so the clip geometry is pinned by the golden gate.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Prompts 15-16 made clipping a loadable record and a real Nim runtime effect
(`buildDrawBatches` populates `clipId` and clips covered batches). Now pin it
with a conformance rig so any runtime claiming clipping must reproduce the same
clipped vertices. The conformance harness **auto-discovers** assets — dropping
`conformance/assets/*.bony` + `conformance/goldens/*_t0.json` (+ optional
`conformance/scripts/*_sample.json`) is enough; there is no manifest
(`scripts/ci/conformance_run.py:83,97`; `input_script_run.py:165`).

Build a **non-vacuous** clipping rig, following the freshest M5 asset pattern:

1. **Rig** `conformance/assets/m11_clip_rig.bony` (mirror the shape of
   `m5_transform_rig.bony` and a slot/region rig like `m1_rig.bony`): a small
   skeleton with at least one bone carrying a **region** slot whose quad is
   **partially covered** by a convex clip polygon, plus a `clippingAttachments`
   entry and a slot that references it. Choose geometry so the clip actually cuts
   the region quad — the clipped batch must have a vertex count and/or positions
   that differ from the raw quad, exercising **u/v interpolation** at the clip
   edges (a diagonal clip edge across the region quad is ideal). Note: region
   batches carry uniform color `(1,1,1,1)` and there is no format construct for a
   non-uniform-colored quad, so r/g/b/a interpolation is NOT observable in this
   golden — base non-vacuity on **geometry + u/v**, not color (rgba interpolation
   is covered by a prompt-16 unit test). Set `untilSlot`
   so the covered range is explicit and at least one slot lies *outside* the
   range (its batch must stay unclipped — `clipId == ""`), making the range
   semantics observable. Pick the milestone token `M11` for the asset name to
   avoid colliding with existing `m1..m10` assets (the registry key band is still
   M4; the asset naming is independent of the key band).

2. **Input script** `conformance/scripts/m11_clip_sample.json` (mirror
   `m5_transform_sample.json`): `{format: "bony.input-script.v1", asset:
   "m11_clip_rig.bony", samples: [{t: 0.0, inputs: {}}]}` — must conform to
   `spec/bony-input-script.schema.json`.

3. **Binary rig** `conformance/assets/bnb/m11_clip_rig.bnb` via
   `bony json-to-bnb conformance/assets/m11_clip_rig.bony
   conformance/assets/bnb/m11_clip_rig.bnb` (the round-trip + M6 gate replays the
   `.bnb` against the same golden).

4. **Numeric golden** `conformance/goldens/m11_clip_rig_t0.json` via
   `bony golden-gen conformance/assets/m11_clip_rig.bony
   conformance/goldens/m11_clip_rig_t0.json --t 0.0`. The golden must show
   non-empty `clipId` on covered batches (format `bony.numeric-golden.v1`;
   `drawBatches[].clipId` per the m1 golden shape) and clipped
   `vertices`/`indices` on the cut batch, and `clipId == ""` on the out-of-range
   batch.

5. **Document** the rig in `conformance/README.md` (add an `M11 | m11_clip_rig |
   Clipping attachment: convex clip polygon partially covering a region slot,
   untilSlot-bounded range` row to the milestone coverage table, plus a short
   subsection like the existing `M5 (transform)` writeup describing the
   non-vacuous clipped-vs-unclipped delta and the cross-runtime status —
   Nim-honored now, Dart pending prompt 18). Note in the image-golden table that
   the clip rig has no PNG golden (pending), matching how m5_ik/transform/physics
   are marked.

6. **Regenerate and commit deterministically**: generate the golden and `.bnb`
   from the committed `.bony` and verify they are stable on re-run (byte-identical
   golden across two `golden-gen` invocations, matching the float-math contract).

Do NOT add a Dart assertion here — that is prompt 18. This slice's gate is the
Nim reference producing the committed goldens through the CI scripts.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Clipping contract (the geometry the golden pins): docs/clipping-attachment-contract.md
- Float math contract: docs/float-math-contract.md (1e-4 tolerance, determinism)
- Conformance suite + "Adding a new milestone" recipe: conformance/README.md
- Rig template: conformance/assets/m5_transform_rig.bony; slot/region template:
  conformance/assets/m1_rig.bony
- Input-script template + schema: conformance/scripts/m5_transform_sample.json;
  spec/bony-input-script.schema.json
- Golden format: conformance/goldens/m5_transform_rig_t0.json (header) and
  conformance/goldens/m1_rig_t0.json (populated drawBatches with clipId)
- CI gates (auto-discovery): scripts/ci/conformance_run.py (globs assets 83,
  golden path 97, bnb 109), scripts/ci/input_script_run.py (globs scripts 165),
  scripts/ci/round_trip_run.py, scripts/ci/suite_run.py (GATES 27-32),
  scripts/ci/schema_validate_assets.py
- CLI: cli/bony_cli.nim (`json-to-bnb`, `golden-gen` subcommands)
- Analogous freshest conformance slice to mirror: the physics conformance story
  slice (bead bony-6hg, prompt 13) and the transform rig slice (bead bony-8i1.7)
- Beads: file under the clipping milestone parent, dependent on the prompt-16 bead

**Success Criteria**
- `conformance/assets/m11_clip_rig.bony`, `conformance/scripts/m11_clip_sample.json`,
  `conformance/assets/bnb/m11_clip_rig.bnb`, and
  `conformance/goldens/m11_clip_rig_t0.json` exist and are committed.
- The golden is **non-vacuous**: at least one covered draw batch has a non-empty
  `clipId` and clipped `vertices`/`indices` that differ from the raw region quad
  (geometry + interpolated u/v; color stays uniform `(1,1,1,1)`), and at least one
  batch outside the `untilSlot` range has `clipId == ""` and an unclipped quad.
  State the concrete clipped-vs-unclipped delta in `conformance/README.md`.
- `python3 scripts/ci/schema_validate_assets.py` passes (the rig validates against
  the regenerated schema).
- `python3 scripts/ci/suite_run.py --bony-bin <bin>` passes end to end: numeric
  golden (`.bony`→golden and `.bnb`→same golden within 1e-4), input-script, and
  round-trip gates all green for the new asset. Build the bin first with
  `nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim`.
- The golden and `.bnb` regenerate byte-identically on re-run.
- `conformance/README.md` documents the M11 clip rig (coverage table row + a
  subsection + image-golden "pending" note) with cross-runtime status "Nim now,
  Dart pending prompt 18".

**Constraints**
- Preserve clean-room posture: the rig geometry, clip polygon, and expected
  vertices are project-owned and derived only from `bony`'s own runtime + contract;
  do not model the rig after any third-party sample.
- Use `docs/comparable-feature-set.md` only for the capability category.
- Keep Rive importer work out of scope; keep Spine importer work blocked.
- Do NOT add a Dart conformance assertion (prompt 18) or change runtime code here
  — if a golden cannot be produced, the bug is in prompt 16's runtime, not this
  slice; fix forward there rather than hand-editing the golden.
- No manifest edits are needed — rely on auto-discovery; do not silently cap or
  skip any gate.
- Keep the slice to one meaningful implementation session: one conformance rig +
  its golden/script/bnb + README documentation.
