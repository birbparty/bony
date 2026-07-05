# /big-change prompt - Nim runtime (skin attachment resolution)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 4**. Depends on
> `31-contract-skin-attachment-sets.md`; it implements the Nim reference
> behavior defined there.
> **Candidate category:** frontier.

---

/big-change Implement first-class skin attachment-set loading and active-skin draw resolution in the Nim reference runtime, preserving `"default"` fallback and existing setup-pose behavior.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

After prompt 31 lands the contract and wire shape, implement the Nim reference
runtime slice. Today `SkeletonData` stores global `regions`,
`clippingAttachments`, and `meshAttachments`, `SlotData.attachment` is a single
attachment name, `validateSkeletonData` accepts a slot attachment if it appears
in any global attachment-name set, and `buildDrawBatches` builds maps by global
attachment name. Deform timelines reject non-`"default"` skins in
`runtime-nim/src/bony/anim/timelines.nim`. This prompt changes those `bony`-owned
seams to support declared skin attachment sets.

Implement exactly this Nim slice:

1. Extend `runtime-nim/src/bony/model.nim` with skin records matching
   `docs/skin-attachment-set-contract.md`. Add them to `SkeletonData`,
   `skeletonData(...)`, `validateSkeletonData(...)`, and public getters as the
   local pattern requires. Validate unique skin names, required `"default"`,
   unique `(skin, slot, attachment)` entries, known slot names, known attachment
   definitions, and fallback rules from the contract.
2. Update JSON load/write in `runtime-nim/src/bony/jsonio.nim`: accept the new
   top-level `skins` key, parse it, emit canonical JSON, and stop hard-rejecting
   non-`"default"` deform timelines when the referenced skin exists and the
   `(skin, slot, attachment)` binding resolves to a mesh attachment. Keep the
   existing no-skin assets valid by synthesizing the `"default"` skin behavior
   defined by the contract.
3. Update `.bnb` load/write in `runtime-nim/src/bony/binary/semantic.nim`: emit
   and read the new skin object shape from prompt 31, preserve canonical object
   ordering, and keep `python3 codegen/generate.py --check` happy. Do not change
   existing type/property keys except for prompt-31 append-only additions.
4. Update draw resolution in `runtime-nim/src/bony/transform.nim`: add a narrow
   active-skin parameter or helper path, defaulting to `"default"`, so existing
   `buildDrawBatches(data)` output stays byte-identical while tests can request
   another skin. Resolve visible slot attachments as active skin first, then
   `"default"` fallback, then the setup slot's own attachment rule from the
   contract. Preserve clipping behavior for region and mesh batches.
5. Update animation pose rebuild in `runtime-nim/src/bony/anim/mixer.nim` so
   skin declarations survive `applyPose` just as mesh/clipping attachments and
   deform overrides currently survive.
6. Add focused Nim tests in `runtime-nim/tests/test_smoke.nim` or a dedicated
   `runtime-nim/tests/test_skin_resolution.nim`, and wire a new dedicated test
   binary into `runtime-nim/README.md` or the root `Makefile` test target if the
   project pattern requires it.

Keep this Nim-only: no conformance golden, no Dart runtime, no importer behavior,
no linked mesh/inheritDeform, no `skinRequired` constraints, and no nested rigs.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Skin contract from step 1: docs/skin-attachment-set-contract.md
- Deform binding: docs/deform-timeline-contract.md
- Mesh/clip draw behavior: docs/mesh-attachment-contract.md,
  docs/clipping-attachment-contract.md
- Binary ordering: docs/binary-canonicalization.md
- Nim model/validation: runtime-nim/src/bony/model.nim
- Nim JSON loader/writer: runtime-nim/src/bony/jsonio.nim
- Nim BNB loader/writer: runtime-nim/src/bony/binary/semantic.nim
- Nim draw batches: runtime-nim/src/bony/transform.nim
- Nim animation pose rebuild: runtime-nim/src/bony/anim/mixer.nim
- Tests and gate: runtime-nim/tests/test_smoke.nim, Makefile
- Beads: parent bony-g2gr; this slice bony-5735; depends on bony-4set

**Success Criteria**
- Nim loads, validates, emits, and round-trips a `skins` array from `.bony` JSON
  and `.bnb` using the prompt-31 contract.
- Existing assets with no explicit skins continue to load and produce unchanged
  default draw batches.
- A non-default active skin can swap a slot-visible region or mesh through the
  project-owned fallback rule without changing slot draw order or clipping rules.
- Deform timelines may target declared non-default skins only when they resolve
  to a mesh attachment with matching vertex count; unresolved skins or bindings
  are rejected.
- Verification passes: `python3 codegen/generate.py --check`,
  `python3 -m unittest discover -s codegen -p 'test_*.py'`, and the repo's Nim
  test gate, including the new skin-resolution tests.

**Constraints**
- Preserve clean-room posture: match only `bony`'s own contract and local runtime
  architecture; do not derive behavior from third-party runtimes or formats.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not broaden to linked meshes, nested rigs, `skinRequired` constraints, or
  importer parsing.
- Keep default-skin output for existing M1-M19 conformance assets stable.
