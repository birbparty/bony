# /big-change prompt - conformance (skinRequired activation gate)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 4**. Depends on
> `45-runtime-nim-skin-required-activation.md`; must land before
> `47-runtime-dart-skin-required-activation.md`.
> **Candidate category:** frontier.

---

/big-change Add shared conformance coverage for skinRequired activation.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Add the shared conformance gate for `docs/skin-required-activation-contract.md`
after the Nim reference runtime implements the behavior. The conformance assets
must make the runtime behavior observable and non-vacuous for later Dart parity.

Create a new conformance rig and script set, update `conformance/README.md`, and
generate goldens with the Nim reference CLI/runtime. The exact milestone label
can follow the next available conformance row, but the asset should clearly be
named for skin-required activation, for example `m22_skin_required_rig`.

The fixture should cover the contract's runtime and validation cases in a small
asset set:

- A `"default"` skin contributes shared required membership and a non-default
  skin adds an extra required bone/slot/attachment.
- An inactive required bone makes its slot/attachment/helper output disappear.
- A required IK/transform/path constraint is inactive under one skin and active
  under another without reordering later active constraints.
- A required physics constraint is inactive for at least one sample, does not
  advance state, then is reactivated and resets.
- JSON and `.bnb` fixtures produce matching numeric goldens.
- Malformed membership cases are covered by focused loader/unit tests rather
  than bloating the main numeric golden.

Keep this slice centered on conformance and Nim-generated goldens. Dart parity
lands in prompt 47.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Binding contract: docs/skin-required-activation-contract.md
- Conformance suite: conformance/README.md
- Existing skin conformance: conformance/assets/m20_skin_rig.bony,
  conformance/scripts/m20_skin_default.json,
  conformance/scripts/m20_skin_variant.json,
  conformance/goldens/m20_skin_default_default.json,
  conformance/goldens/m20_skin_variant_variant.json
- Existing physics story conformance: conformance/assets/m5_physics_rig.bony,
  conformance/scripts/m5_physics_story.json,
  conformance/goldens/m5_physics_story_rest.json,
  conformance/goldens/m5_physics_story_excited.json,
  conformance/goldens/m5_physics_story_settled.json
- CLI/golden generation: cli/bony_cli.nim, cli/README.md
- Nim tests/gates: runtime-nim/tests/test_m20_skin_conformance.nim,
  runtime-nim/tests/test_physics_eval.nim, Makefile
- Beads: bony-i4x6, bony-i4x6.3

**Success Criteria**
- A new `.bony` conformance asset exists under `conformance/assets/` for
  skin-required activation.
- A matching `.bnb` fixture exists under `conformance/assets/bnb/`.
- Input scripts under `conformance/scripts/` exercise at least the default-skin
  and non-default active-skin paths, and any time/stateful physics samples
  needed by the fixture.
- Goldens under `conformance/goldens/` make inactive-vs-active behavior
  observable above `1e-4` tolerance: emitted draw batches differ, active
  constraint output differs, and physics no-advance/reactivation behavior is
  visible.
- `conformance/README.md` documents the new row and explains the non-vacuous
  deltas.
- Nim tests or CLI tests assert the `.bony` and `.bnb` forms produce matching
  goldens and that malformed membership cases are rejected with typed error
  categories.
- Dart tests may be prepared but should not be required to pass in this slice.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not add importer mapping or broaden the serialized format beyond prompts
  44 and 45.
- Do not hand-author numeric expected values without a clear Nim reference
  generation path; regenerate goldens through the existing CLI/runtime.
- Keep Dart runtime parity for prompt 47.
