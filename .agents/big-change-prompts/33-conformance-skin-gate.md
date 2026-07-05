# /big-change prompt - conformance (skin variant gate)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 4**. Depends on
> `31-contract-skin-attachment-sets.md` and
> `32-runtime-nim-skin-resolution.md`; it freezes the Nim behavior as shared
> conformance data.
> **Candidate category:** frontier.

---

/big-change Add a non-vacuous skin-variant conformance asset and goldens that prove active-skin attachment lookup, default fallback, JSON/BNB parity, and deform-timeline skin resolution in the Nim reference pipeline.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompts 31 and 32, freeze the skin behavior in shared conformance. The
asset should be small but non-vacuous: one default attachment, one named variant
attachment, and at least one fallback case where the active skin does not define
the slot binding and `"default"` is used. Include a mesh/deform case only if it
stays small; otherwise constrain the mesh/deform proof to a focused Nim unit
test and keep the conformance rig to visible attachment swaps.

Implement exactly this conformance slice:

1. Add a new asset after M19, for example
   `conformance/assets/m20_skin_rig.bony`, and its `.bnb` peer under
   `conformance/assets/bnb/`.
2. Add input scripts under `conformance/scripts/` that sample the same rig with
   the default skin and with a non-default active skin. If active-skin selection
   requires an input-script extension from prompt 31, use that contract exactly.
3. Generate goldens under `conformance/goldens/`, for example
   `m20_skin_default.json` and `m20_skin_variant.json`. The variant golden must
   show a draw-batch difference well above `1e-4` (different region dimensions,
   mesh vertices, or attachment id), while the fallback slot remains identical
   to default.
4. Update `conformance/README.md` with an M20 row and a section explaining why
   the golden is non-vacuous and how fallback is observed.
5. Add Nim CLI/golden tests that load both `.bony` and `.bnb`, run the input
   scripts, and compare against the committed goldens. Reuse existing conformance
   script/golden patterns from M18/M19 and the CLI entry points in
   `cli/bony_cli.nim`.
6. Preserve all existing M1-M19 goldens. Do not regenerate unrelated assets.

Keep this conformance-only: no Dart runtime parity, no importer behavior, no
linked mesh/inheritDeform, no `skinRequired` constraints, and no nested rigs.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Skin contract: docs/skin-attachment-set-contract.md
- Float tolerance: docs/float-math-contract.md
- Conformance index and precedents: conformance/README.md
- Existing story/input examples: conformance/scripts/m18_deform_story.json,
  conformance/scripts/m19_event_story.json
- Existing assets/goldens: conformance/assets/m19_event_rig.bony,
  conformance/goldens/m19_event_story_rest.json,
  conformance/goldens/m19_event_story_mid.json,
  conformance/goldens/m19_event_story_end.json
- CLI conformance path: cli/bony_cli.nim
- Nim runtime seams from step 2: runtime-nim/src/bony/model.nim,
  runtime-nim/src/bony/jsonio.nim, runtime-nim/src/bony/binary/semantic.nim,
  runtime-nim/src/bony/transform.nim
- Beads: parent bony-g2gr; this slice bony-lyg3; depends on bony-5735

**Success Criteria**
- A new M20 skin conformance asset exists in `.bony` and `.bnb` form with input
  scripts and committed JSON goldens.
- The default and variant samples differ in an observable draw-batch field well
  above `1e-4`, and at least one fallback slot proves `"default"` fallback.
- The Nim conformance gate reproduces the M20 goldens from both `.bony` and
  `.bnb` without changing any existing M1-M19 golden.
- `conformance/README.md` documents the M20 asset, non-vacuity, JSON/BNB parity,
  and Nim status.
- Verification passes: `python3 codegen/generate.py --check` and the repo's Nim
  conformance/test gate.

**Constraints**
- Preserve clean-room posture: use only local contracts and project-owned test
  assets; do not derive examples from third-party assets or docs.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not broaden to linked meshes, nested rigs, `skinRequired` constraints, or
  importer parsing.
- Keep the asset intentionally small and non-vacuous.
