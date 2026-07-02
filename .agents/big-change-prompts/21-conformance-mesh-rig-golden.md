# /big-change prompt - conformance rig + golden (M4 mesh attachment + skinning)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 4** of the M4 mesh-attachment + skinning
> milestone. Depends on `19` (format) and `20` (Nim skins meshes into draw
> batches). Produces the committed cross-runtime golden that `22` (Dart parity)
> must match. **Candidate category:** frontier.

---

/big-change Add a mesh-attachment conformance rig and its numeric golden: a weighted mesh whose vertices are shared across two posed bones, so the committed golden's skinned world positions and uvs are non-vacuous and cross-runtime-binding, wired into all conformance gates.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Prompts 19-20 made the Nim reference load and skin mesh attachments. This slice
commits the **cross-runtime contract**: a rig, its `.bnb`, a numeric golden, and
an input script, wired into the conformance gates so any runtime claiming mesh
support (Nim now, Dart in prompt 22) must reproduce the same skinned geometry
within `1e-4`.

Follow the "Adding a new milestone" recipe in `conformance/README.md:358-366`
exactly (create rig -> `json-to-bnb` -> `golden-gen --t 0.0` -> input script ->
commit all four -> verify gates). Reuse the asset-naming approach the clipping rig
used: because the `m1..m10` asset stems are taken, name this rig with a
non-colliding token (recommend `m12_mesh_rig`, mirroring how the clip rig is
`m11_clip_rig` even though its registry band is M4; the milestone token only names
the asset). State in the README that the `M12` token names the asset only and the
owning registry band is still **M4**.

Design the rig for a **non-vacuous, skinning-dominated golden**:

1. **Bones**: `root` (identity) plus two children posed so a shared vertex blends
   observably - e.g. `boneA` and `boneB` at different translations/rotations off
   `root`, chosen so a 50/50-weighted vertex lands strictly between the two
   single-bone FK results (delta well above `1e-4`). Keep the pose a setup pose
   (`--t 0.0`); no animation or state machine is needed.
2. **One slot** `mesh_slot` referencing a **weighted** `MeshAttachment`:
   - A small triangulated mesh (recommend >= 4 vertices, >= 2 triangles) with
     distinct per-vertex `uvs` (so a runtime that drops or mis-orders uvs fails).
   - At least one vertex weighted across **both** `boneA` and `boneB` (e.g.
     `weight 0.5/0.5`), and at least one vertex weighted fully to a single bone,
     so the golden exercises both the blend and the single-influence path. Weights
     per vertex sum to 1 within `1e-4`.
   - `triangles` referencing all vertices, `len mod 3 == 0`.
3. **Non-vacuity, documented**: in `conformance/README.md`, add a `### M12 mesh
   rig (m12_mesh_rig)` subsection (mirror the depth of the M5-transform/physics and
   M11-clip subsections). Show the skinned world position of the shared vertex and
   the two single-bone FK positions it sits between, and state the numeric delta
   (>> `1e-4`), so a reader can see the golden is skinning-dominated, not a
   pass-through. Note that region batches carry uniform color `(1,1,1,1)` and the
   mesh v1 record has no per-vertex color, so r/g/b/a is uniform-and-unobservable
   here; the golden's non-vacuity rests on skinned geometry + uvs + triangle
   indices.

Concretely:

1. Create `conformance/assets/m12_mesh_rig.bony` (a valid `.bony` per the prompt-19
   schema, with a `meshAttachments` array holding the weighted mesh; the slot's
   `attachment` names the mesh). It must pass `schema_validate_assets.py`.
2. Generate the binary: `bony json-to-bnb conformance/assets/m12_mesh_rig.bony
   conformance/assets/bnb/m12_mesh_rig.bnb` (build the CLI first per
   `conformance/README.md:340-345`). Confirm it is non-empty and byte-stable on
   re-run (float-math contract).
3. Generate the numeric golden: `bony golden-gen conformance/assets/m12_mesh_rig.bony
   conformance/goldens/m12_mesh_rig_t0.json --t 0.0`. The golden's `drawBatches`
   must contain the mesh slot's skinned world vertices, uvs, and triangle indices.
   Note the **actual** committed golden shape (see `m11_clip_rig_t0.json`) stores
   each draw-batch vertex as `{x, y, u, v, r, g, b, a}` plus a separate `indices`
   array - a mesh needs no golden field a region does not already have. The prose
   "Numeric golden format" section in `conformance/README.md` (~248-278) is
   **stale** (it shows `"vertices": [[x, y], ...]` with no u/v and no `indices`);
   update that prose to match the real emitted shape while you add the M12
   subsection, rather than treating it as the format reference.
4. Create the input script `conformance/scripts/m12_mesh_sample.json` (setup pose,
   no state machine; mirror an existing `*_sample.json` such as
   `m11_clip_sample.json`); it must conform to `spec/bony-input-script.schema.json`.
5. Wire it into the CI gates: the numeric-golden gate
   (`scripts/ci/conformance_run.py`) replays `.bony` -> golden and the `.bnb` ->
   same golden (M6 gate); the round-trip gate (`round_trip_run.py`) covers
   `m12_mesh_rig.bnb` via the `*_rig.bnb` glob. Confirm all gates in
   `scripts/ci/suite_run.py` pass locally.
6. Update `conformance/README.md`'s milestone coverage table (`:27-41`) with an
   `M12` row (`m12_mesh_rig` | "Weighted mesh attachment: skinned vertices shared
   across two bones, per-vertex uvs, triangle list"), the new subsection, and the
   image-golden table (`:230-244`) marking `m12_mesh_rig` PNG golden as pending
   (no PNG produced here). Set the rig's cross-runtime status to "honored by the
   Nim reference; Dart pending prompt 22."

Keep the rig **single-purpose**: one weighted mesh at a setup pose. Do NOT combine
it with clipping, animation, a state machine, constraints, or deformers, and do
NOT add a second rig - those broaden scope and muddy the golden's non-vacuity
story.

**Links to Relevant Documentation**
- Conformance recipe + format: conformance/README.md (Adding a new milestone
  358-366; numeric-golden format 248-278; input-script format 283-323; CI gates
  328-336; local run 340-353)
- Mesh contract: docs/mesh-attachment-contract.md
- Float math contract: docs/float-math-contract.md (1e-4, byte-stable regeneration)
- Freshest template (mirror closely): the clipping conformance slice - prompt
  .agents/big-change-prompts/17-conformance-clipping-rig-golden.md and the landed
  `m11_clip_rig` assets/goldens/scripts; also the M5-transform rig
  (`m5_transform_rig`) as a non-animated, non-vacuous setup-pose golden with a
  documented constrained-vs-unconstrained delta.
- Input-script schema: spec/bony-input-script.schema.json
- CI scripts: scripts/ci/conformance_run.py, round_trip_run.py, suite_run.py,
  schema_validate_assets.py
- Existing assets to mirror shape: conformance/assets/m11_clip_rig.bony,
  conformance/assets/bnb/m11_clip_rig.bnb, conformance/goldens/m11_clip_rig_t0.json,
  conformance/scripts/m11_clip_sample.json
- Beads: file under the mesh-attachment milestone parent, dependent on the
  prompt-20 bead

**Success Criteria**
- `conformance/assets/m12_mesh_rig.bony` exists, validates against the schema, and
  carries a weighted mesh with >= 4 vertices, >= 2 triangles, distinct uvs, and at
  least one vertex weighted 50/50 across two bones.
- `conformance/assets/bnb/m12_mesh_rig.bnb`,
  `conformance/goldens/m12_mesh_rig_t0.json`, and
  `conformance/scripts/m12_mesh_sample.json` are committed; the golden's mesh-slot
  draw batch carries the skinned world vertices, uvs, and triangle indices.
- The golden is reproduced identically from both `.bony` and `.bnb` (JSON and
  binary loaders agree) and regenerates byte-identically on re-run.
- The shared-vertex skinned position sits strictly between the two single-bone FK
  positions, with a documented delta `>> 1e-4`; `conformance/README.md` records
  the rig, the `### M12 mesh rig` subsection with that delta, and the cross-runtime
  status (Nim honored, Dart pending prompt 22).
- All conformance gates pass locally via `python3 scripts/ci/suite_run.py
  --bony-bin <bin>`: numeric-golden (`.bony` and `.bnb`), round-trip, input-script,
  and schema-validate; `make test` passes.

**Constraints**
- Preserve clean-room posture: the rig is a `bony`-owned fixture; do not copy any
  third-party sample rig, mesh, or golden.
- Determinism: the golden must be regenerated by the committed CLI, not
  hand-authored, and must be byte-stable per `docs/float-math-contract.md`. Do not
  hand-edit generated golden numbers.
- Do NOT change the format, registry, schema, or runtime code in this slice
  (those are prompts 19-20), and do NOT touch the Dart runtime (prompt 22).
- Keep the rig single-purpose (one weighted mesh, setup pose); no clipping,
  animation, state machine, constraints, or deformers.
- Keep the slice to one meaningful implementation session: one rig + its four
  committed artifacts + README wiring + gate verification.
