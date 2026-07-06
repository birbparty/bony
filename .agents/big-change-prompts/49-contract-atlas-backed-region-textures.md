# /big-change prompt - contract + format (atlas-backed region textures)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 4**. Can run independently of step 1; the final
> preflight prompt depends on this gate existing.
> **Candidate category:** comparable-gap.

---

/big-change Define and implement the project-owned atlas-backed region texture surface so region draw batches can carry texture pages and UV rectangles from bony-owned atlas metadata.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`bony pack-atlas` already writes deterministic sidecar atlas metadata
(`spec/bony-atlas.schema.json`, `cli/atlas_packer.nim`, `cli/bony_cli.nim`), and
the renderers already consume `DrawBatch.texturePage`, UVs, and explicit alpha
mode (`runtime-nim/src/render/software_rasterizer.nim`,
`docs/drawbatch-raylib-contract.md`). But canonical `.bony` region records still
carry only `name`, `width`, and `height`; region draw batches therefore use an
empty texture page and full-quad default UVs.

Create the smallest binding surface that lets project-owned atlas metadata feed
region draw batches:

- Define a contract for region texture metadata: texture page id, UV rectangle,
  optional alpha mode, and default behavior for existing hand-authored regions.
- Add registry/default/schema/codegen support if the metadata becomes part of
  canonical `.bony`/`.bnb`; otherwise explicitly keep it as a CLI sidecar-only
  contract and explain why it is not serialized into `SkeletonData`.
- Wire Nim model/load/draw-batch output so a textured region emits the declared
  `texturePage` and UVs while old regions remain byte-identical.
- Port the same load and draw-batch behavior to Dart if the surface is
  canonical format data.
- Add a small image or numeric conformance fixture proving UVs and page ids are
  observable.

Do not broaden into Lottie shape rasterization, DragonBones atlas parsing,
Spine atlas compatibility, or renderer-specific packing algorithms.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- Atlas sidecar schema: spec/bony-atlas.schema.json
- Atlas packer: cli/atlas_packer.nim, cli/bony_cli.nim
- Region model and loader: runtime-nim/src/bony/model.nim,
  runtime-nim/src/bony/jsonio.nim, runtime-dart/lib/src/model.dart,
  runtime-dart/lib/src/loader.dart
- Draw-batch and renderer contracts: runtime-nim/src/bony/transform.nim,
  runtime-dart/lib/src/transform.dart,
  runtime-nim/src/render/software_rasterizer.nim,
  docs/drawbatch-raylib-contract.md
- Registry/default/codegen sources, if canonical fields are added:
  registry/wire.yml, registry/key-ranges.md, spec/defaults.yml,
  codegen/generate.py
- Conformance fixtures: conformance/assets/, conformance/goldens/,
  scripts/ci/image_diff_check.py
- Beads: bony-2j7z

**Success Criteria**
- A binding atlas-backed region texture contract exists under `docs/` and is
  linked from `docs/README.md`.
- The contract states whether the texture metadata is canonical format data or
  CLI sidecar-only data. If canonical, `registry/wire.yml`,
  `spec/defaults.yml`, generated schemas, Nim loader/writer, and Dart
  loader/writer are updated consistently.
- Existing region-only assets without texture metadata produce the same numeric
  goldens as before.
- A textured region fixture emits non-empty `DrawBatch.texturePage` and UV
  values that differ from the default full-quad UVs by more than `1e-4`.
- If image coverage is added, the fixture uses the Nim software rasterizer and
  `scripts/ci/image_diff_check.py`; it must not require GPU/raylib state.
- `docs/CLEANROOM.md` and `docs/PROVENANCE.md` record any net-new serialized
  identifiers and explain them from project-owned atlas/region terminology.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`
  - `cd runtime-dart && dart test` if Dart-visible format data changes

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, atlas formats, or copied
  docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not implement Lottie Tier 2 shape rasterization or DragonBones atlas
  parsing in this slice.
- Do not add renderer-specific raylib behavior beyond consuming the existing
  `DrawBatch` stream.
- Use only allocated key ranges from `registry/key-ranges.md` for any registry
  edits.
