# /big-change prompt - Dart runtime (skin parity)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 4 of 4**. Depends on
> `31-contract-skin-attachment-sets.md`, `32-runtime-nim-skin-resolution.md`, and
> `33-conformance-skin-gate.md`; it ports the fixed Nim behavior and committed
> M20 goldens to Dart.
> **Candidate category:** frontier.

---

/big-change Port first-class skin attachment-set loading and active-skin draw resolution to Dart, proving parity against the committed M20 skin conformance goldens from both `.bony` and `.bnb`.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompts 31-33 land, Dart must mirror the `bony`-owned skin model and pass
the M20 conformance gate. Today Dart has global `meshAttachments`, global
attachment lookup in `runtime-dart/lib/src/transform.dart`, JSON/BNB loaders in
`runtime-dart/lib/src/loader.dart`, and deform timelines that hard-reject
non-`"default"` skins. This prompt ports only the fixed Nim behavior and
committed goldens.

Implement exactly this Dart slice:

1. Extend `runtime-dart/lib/src/model.dart` with skin records matching
   `docs/skin-attachment-set-contract.md` and the Nim model from prompt 32. Carry
   them through `SkeletonData`.
2. Update JSON and `.bnb` loading in `runtime-dart/lib/src/loader.dart` for the
   prompt-31 wire shape. Validate duplicate skin names, required `"default"`,
   binding references, fallback invariants, and deform timeline skin resolution
   to match Nim.
3. Update `runtime-dart/lib/src/transform.dart` so `buildDrawBatches` can resolve
   visible slot attachments using the active skin, default fallback, and setup
   attachment rule from the contract. Preserve existing default behavior when no
   active skin is supplied.
4. Update `runtime-dart/lib/src/anim.dart` pose rebuild so skin declarations
   survive `applyPose`, matching the existing preservation of
   `meshAttachments`, `clippingAttachments`, and `deformOverrides`.
5. Add `runtime-dart/test/m20_skin_test.dart` or equivalent. Reproduce the
   committed M20 skin goldens from both
   `../conformance/assets/m20_skin_rig.bony` and
   `../conformance/assets/bnb/m20_skin_rig.bnb`, checking exact string fields and
   numeric fields within `1e-4`.
6. Update the M20 cross-runtime status paragraph in `conformance/README.md` once
   Dart passes.

Keep this Dart-only: do not change the format, registry, Nim runtime, or
committed goldens. Dart must reproduce the fixed contract and Nim goldens.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Skin contract: docs/skin-attachment-set-contract.md
- Float tolerance: docs/float-math-contract.md
- Committed M20 assets/goldens from step 3:
  conformance/assets/m20_skin_rig.bony,
  conformance/assets/bnb/m20_skin_rig.bnb,
  conformance/goldens/m20_skin_default.json,
  conformance/goldens/m20_skin_variant.json
- Dart model/load/draw/pose seams: runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart, runtime-dart/lib/src/transform.dart,
  runtime-dart/lib/src/anim.dart
- Dart conformance precedents: runtime-dart/test/m19_event_story_test.dart,
  runtime-dart/test/m18_deform_story_test.dart,
  runtime-dart/test/m10_conformance_test.dart
- Nim parity source from step 2: runtime-nim/src/bony/model.nim,
  runtime-nim/src/bony/jsonio.nim, runtime-nim/src/bony/binary/semantic.nim,
  runtime-nim/src/bony/transform.nim
- Beads: parent bony-g2gr; this slice bony-8fhg; depends on bony-lyg3

**Success Criteria**
- Dart loads and validates the skin contract from `.bony` and `.bnb`.
- Dart default-skin behavior for existing M1-M19 assets remains unchanged.
- Dart active-skin draw resolution reproduces the committed M20 default and
  variant goldens from both `.bony` and `.bnb` within `1e-4`.
- Dart deform timelines accept declared non-default skins only when the binding
  resolves to a mesh attachment with matching vertex count, matching Nim errors
  for invalid assets.
- `conformance/README.md` records M20 Nim+Dart parity.
- Verification passes: `cd runtime-dart && dart test`.

**Constraints**
- Preserve clean-room posture: port from `bony`'s own Nim reference and
  contracts only; do not derive behavior from third-party runtimes or formats.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not broaden to linked meshes, nested rigs, `skinRequired` constraints, or
  importer parsing.
- Do not regenerate or edit committed M20 goldens in this Dart parity slice.
