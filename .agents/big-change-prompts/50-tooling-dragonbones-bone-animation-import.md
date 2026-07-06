# /big-change prompt - tooling (DragonBones bone-animation import)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 3 of 4**. Can run independently of steps 1 and 2;
> the final preflight prompt depends on this importer tier.
> **Candidate category:** useful.

---

/big-change Implement the DragonBones importer bone-animation tier already specified by the project-owned design note.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

`docs/dragonbones-importer-design.md` defines a clean-room Tier 1 importer that
includes bone `translateFrame`, `rotateFrame`, and `scaleFrame` animation
channels. The current CLI importer in `cli/bony_cli.nim` imports static bones,
slots, default skin image displays, and setup transforms, but it does not parse
or emit DragonBones animation clips. It also has a path where animation can be
present and omitted unless `--setup-only` is used.

Implement the specified bone-animation tier:

- Extend the importer-owned adapter model in `cli/bony_cli.nim` with animation,
  bone-channel, and per-channel frame records as described in
  `docs/dragonbones-importer-design.md`.
- Parse only the project-owned input contract already recorded in the design
  note.
- Emit bony-native `AnimationClip` data for supported bone translate, rotate,
  and scale channels using the repository's existing animation model and JSON
  writer.
- Reject slot channels, mesh displays, Bezier curves, non-zero easing,
  `clockwise`, negative scale, and other out-of-tier features with deterministic
  diagnostics.
- Add CLI fixtures that compare canonical `.bony` output and at least one
  nonzero-time golden from the imported animation.

Do not read external DragonBones runtime/importer code, generated schemas, or
third-party prose. This slice is driven by the local design note and
user-supplied fixture JSON only.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md
- DragonBones importer design: docs/dragonbones-importer-design.md
- Animation/state-machine boundary: docs/animation-state-machine-contract-boundaries.md,
  docs/nim-loaded-asset-shape.md
- CLI importer: cli/bony_cli.nim
- Nim animation model and JSON/Binary preservation:
  runtime-nim/src/bony/anim/timelines.nim,
  runtime-nim/src/bony/anim/mixer.nim,
  runtime-nim/src/bony/jsonio.nim,
  runtime-nim/src/bony/binary/semantic.nim
- Existing CLI tests: runtime-nim/tests/test_smoke.nim,
  runtime-nim/tests/test_cli_pose.nim
- Beads: bony-0vu9

**Success Criteria**
- `bony import-dragonbones` emits bony animation clips for supported
  `translateFrame`, `rotateFrame`, and `scaleFrame` channels.
- Imported channel times use `armature.frameRate`; terminator frames and
  duration sums follow `docs/dragonbones-importer-design.md`.
- `--setup-only` remains the explicit way to suppress valid animation. Without
  `--setup-only`, supported animation is preserved and unsupported animation
  fails rather than being silently dropped.
- Tests cover linear translate, rotate, and scale channels; a single-channel
  animation that holds other channels at rest; a no-animation static rig; and a
  nonzero-time numeric golden generated through the normal CLI path.
- Rejection fixtures cover at least `clockwise`, non-zero `tweenEasing`,
  well-formed `curve`, slot channels, invalid bone channel references, bad
  duration sums, and partial-output prevention on failure.
- Diagnostic text is deterministic and does not copy third-party docs prose.
- Verification passes:
  - `python3 codegen/generate.py --check`
  - `python3 -m unittest discover -s codegen -p 'test_*.py'`
  - `make test`

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- DragonBones field names may appear only at the importer parser boundary and
  in importer-owned fixtures/diagnostics.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not implement DragonBones mesh displays, slot color/display animation,
  IK/constraint import, atlas import, multiple-armature composition, negative
  scale, Bezier easing, or shortest-arc `clockwise` handling.
- Do not change bony runtime animation semantics to fit DragonBones input.
