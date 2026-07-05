# /big-change prompt - contract (first-class skin attachment sets)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 4**. Run first; later runtime, conformance, and
> Dart parity slices depend on the project-owned skin contract and wire shape.
> **Candidate category:** frontier.

---

/big-change Define the first-class `bony` skin attachment-set contract and wire shape, replacing the current reserved `"default"` skin placeholder with a project-owned model for named attachment variants.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony` has reached M19 event parity with no open beads, and the next local
frontier is first-class skins. The binding spec already calls for `skins[]` as
named attachment sets, `registry/key-ranges.md` reserves M4 for "Meshes, weights,
skins, deform timelines, clipping", `docs/deform-timeline-contract.md` currently
pins deform timelines to the reserved `"default"` skin, and
`docs/mesh-attachment-contract.md` explicitly keeps skins out of v1. This slice
must define the `bony`-owned contract before any loader or runtime changes.

Build a contract-only milestone:

1. Add `docs/skin-attachment-set-contract.md`. Define a narrow M4 skin model:
   a top-level `skins` array, a required always-present `"default"` skin, and
   named skin entries that map `(slot, attachment)` to a concrete attachment
   reference. Define lookup as active skin first, then `"default"` fallback.
   Keep setup slots as the default active attachment names until the runtime
   slice adds active-skin selection. Define duplicate/referential-validation
   rules, canonical JSON shape, `.bnb` object/child ordering, and how deform
   timelines resolve their `skin` field against the loaded skin set.
2. Update `docs/deform-timeline-contract.md` to replace the "reserved skin
   identity" rule with the new skin-resolution rule: `"default"` remains valid,
   non-default skins become valid only when declared, and the referenced
   `(skin, slot, attachment)` must resolve to a mesh attachment for deform
   timelines.
3. Update `docs/mesh-attachment-contract.md` to make clear that mesh records
   remain project-owned attachment definitions, while skin entries bind those
   definitions into slot-visible variants. Do not add linked meshes,
   `inheritDeform`, `skinRequired`, or nested rigs in this slice.
4. Update `docs/binary-canonicalization.md` only where needed to make the
   existing "attachments grouped by skin order, then slot order, then
   attachment name" rule concrete for the chosen skin object shape. Preserve the
   existing dependency order: `skeleton`, `bones`, `slots`, `attachments`, `ik`,
   `transforms`, `paths`, `physics`, `skins`, `events`, `parameters`,
   `deformers`, `animations`, `stateMachines`, `atlasMetadata`.
5. Add registry/default/schema entries for the skin records under the M4 band
   (`3000..3999`) using only unused keys from `registry/key-ranges.md`. Update
   `registry/wire.yml`, `spec/defaults.yml`, and `codegen/generate.py` metadata
   only as required for generated schemas and wire metadata. Regenerate generated
   files with `python3 codegen/generate.py`.
6. Update `docs/README.md`, `docs/CLEANROOM.md`, and `docs/PROVENANCE.md` with
   the new project-owned serialized identifiers and clean-room rationale.

Keep this slice contract/format only: no Nim runtime active-skin lookup, no
conformance rig, no Dart runtime, no importer behavior, no nested rigs, and no
`skinRequired` constraints.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Local binding spec: /Users/punk1290/Downloads/bony-2d-skeletal-format-spec.md
- Existing skin placeholder: docs/deform-timeline-contract.md
- Existing attachment contract: docs/mesh-attachment-contract.md
- Binary ordering contract: docs/binary-canonicalization.md
- Registry key bands: registry/key-ranges.md
- Registry/default/schema sources: registry/wire.yml, spec/defaults.yml,
  codegen/generate.py, spec/bony.schema.json, spec/bony-wire.schema.json
- Current model/load seams to leave behaviorally unchanged:
  runtime-nim/src/bony/model.nim, runtime-nim/src/bony/jsonio.nim,
  runtime-nim/src/bony/binary/semantic.nim, runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart
- Beads: parent bony-g2gr; this slice bony-4set

**Success Criteria**
- `docs/skin-attachment-set-contract.md` exists and normatively defines the
  first-class skin attachment-set model, JSON shape, `.bnb` object/child shape,
  lookup/fallback rule, validation rules, and explicit non-goals.
- `docs/deform-timeline-contract.md`, `docs/mesh-attachment-contract.md`, and
  `docs/binary-canonicalization.md` are updated consistently with the skin
  contract and still preserve existing M12-M19 behavior.
- `registry/wire.yml` and `spec/defaults.yml` contain only append-only M4-band
  additions; generated schema/runtime metadata is refreshed.
- `docs/CLEANROOM.md` and `docs/PROVENANCE.md` record the new serialized names
  as project-owned and not derived from comparable product layouts.
- Verification passes: `python3 codegen/generate.py --check` and
  `python3 -m unittest discover -s codegen -p 'test_*.py'`.

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Use only your allocated range from registry/key-ranges.md.
- Do not implement active-skin runtime lookup, conformance assets, Dart parity,
  linked meshes, nested rigs, or `skinRequired` constraints in this slice.
- Keep the slice small enough for one meaningful implementation session.
