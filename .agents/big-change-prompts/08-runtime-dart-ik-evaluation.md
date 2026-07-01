# /big-change prompt - runtime-dart (M5-IK Dart evaluation parity)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 1 of 1** for the Dart IK evaluation milestone. It
> depends on the already-landed M5-IK format + Nim runtime + committed goldens
> (prompts 05-07). Can run independently now; nothing else is queued behind it
> except the optional story-golden follow-up noted under Scope.
> **Candidate category:** frontier.

---

/big-change Port the M5 IK solvers into the Dart runtime so `computeWorldTransforms` evaluates IK constraints at pose time (matching the Nim reference), and add the m5_ik setup-pose golden to the Dart cross-runtime conformance gate.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

The M5-IK format, the Nim reference solver, and the cross-runtime numeric
goldens have all landed. The Dart runtime currently only *loads* IK constraint
data (`IkConstraintData` + `SkeletonData.ikConstraints`) and returns the
unconstrained setup-pose hierarchy — `docs/ik-constraint-format-contract.md`
§8 marks Dart IK evaluation as "deferred to a later slice." This milestone
closes that gap: implement the three IK solvers in Dart, wire them into the
world-transform pass mirroring the existing path-constraint evaluation
machinery, and match the committed golden `conformance/goldens/m5_ik_rig_t0.json`
within the `1e-4` cross-runtime tolerance.

The Nim reference to mirror (do not re-derive geometry — port its behavior):

- Solvers: `runtime-nim/src/bony/constraints/ik.nim` — these have **no Dart
  equivalent yet** and must be newly ported (confirmed: no `solve*`
  functions or `*IkResult` types exist anywhere under `runtime-dart/`). Port
  into a new `runtime-dart/lib/src/ik.dart` module:
  - `solveOneBoneIk` (line 84), `solveTwoBoneIk` (line 105), `solveChainIk`
    (line 155), and their result types `OneBoneIkResult` / `TwoBoneIkResult` /
    `ChainIkResult` (ik.nim:17-30).
  - FABRIK numerics: `fabrikIterations = 8`, `fabrikTolerance = 1e-4`, the
    collinear/degenerate bend-plane seeding (lines ~182-200) and the
    root-past-total-length straight-line case (lines ~175-181). Port these
    exactly — they are load-bearing for the chain case.
  - IK point inputs are f32-quantized **at point construction** via the
    `ikPoint(x, y)` helper (`ik.nim:33-34`), which quantizes both coordinates
    with `quantizeF32` (Dart already has `quantizeF32` in
    `runtime-dart/lib/src/deform.dart:13`). The conformance note records that
    "only IK point inputs are f32-quantized internally," so apply quantization
    when constructing the target, `restOrigins`, and `currentOrigins` points —
    NOT on solver output or elsewhere — or the result can miss the `1e-4`
    tolerance.
- Evaluation entry point + geometry contract: `applyRuntimeIk`
  (`runtime-nim/src/bony/transform.nim:389-524`). The load-bearing rules:
  - **Fixed segment lengths from the REST pose** (`restWorldFor`,
    transform.nim:357; `ikDistance`, line 353), but the chain **anchors at the
    CURRENT (live) joint origins** so a moved parent is tracked — this is the
    me5.13 "current-pivot anchoring" contract decision (§4). `mix` is applied
    ONCE inside the solver, so `mix = 0` is the current-pose identity.
  - The solver reads the bones' CURRENT world rotations
    (`worldRotationDegrees`, transform.nim:349) and the target's CURRENT world
    position. For the 2-bone case the child rotation input is RELATIVE to the
    parent (current child world rotation minus current parent world rotation);
    1-bone and chain solvers return ABSOLUTE world angles. The write-back
    normalizes to absolute (`solvedWorldAngles`, transform.nim:462-503).
  - **Ordering:** the target (and any external chain-root parent) must already
    be computed before the constraint runs; otherwise raise the Dart
    equivalent of Nim's `orderingViolation` (transform.nim:418, 447) — reuse the
    same ordering model as `_applyRuntimePathConstraint`.
  - Sequential FK write-back (transform.nim:505-524): convert each solved
    absolute world angle to the bone's LOCAL rotation against its
    already-re-worlded parent (subtract parent world rotation only when the bone
    inherits rotation), set the local rotation, re-world the bone, mark computed.

The Dart seams to extend (all in `runtime-dart/lib/src/transform.dart`):

- `computeWorldTransforms` (line 448) currently branches only on
  `hasRuntimePaths` (line 450). Widen the gate to path-OR-ik:
  `data.paths.any((p) => p.runtimeEvaluable) || data.ikConstraints.any((c) => c.runtimeEvaluable)`,
  mirroring Nim's `hasRuntimeConstraints` loop (`transform.nim:137-147`).
- **Build ONE unified constraint update cache**, not two passes. Dart's current
  `_buildPathConstraintUpdateCache` (transform.dart:280-303) is path-only — it
  collects only `data.paths` and sorts by `(order, sourceIndex)`. Generalize it
  to collect BOTH `path.runtimeEvaluable` and `ik.runtimeEvaluable` constraints
  into a single ordered list, and generalize `_ConstraintEntry` to carry a
  constraint **kind** tag (path vs ik) alongside `sourceIndex`. The ordering is
  binding and defined by Nim's `compareConstraintEntries` +
  `constraintKindRank` (`runtime-nim/src/bony/model.nim:715-731`) and
  `docs/constraint-total-order.md`: sort by `order` value first, then by kind
  rank where **ckIk (0) precedes ckPath (2)** on a tie, then by source index.
  Do NOT iterate paths and IK in separate loops — a dual-loop gets the tie order
  wrong (an IK and a path both at `order = 0` must run IK first) and breaks the
  golden. Then dispatch each `_ConstraintEntry` by kind to
  `_applyRuntimePathConstraint` or the new `_applyRuntimeIk`, exactly as Nim's
  cache dispatches `ckPath`/`ckIk` (`transform.nim:167-176`).
- Reuse `_BoneGroupEntry` (line 54) for the bone-group entries interleaved
  between constraints — that part is already kind-agnostic.
- Reuse `_worldForBone` (line 114) for re-worlding, `_lerp` (line 191), and the
  `_Point`/`_distance` helpers (lines 30-33, 187). Add a Dart
  `worldRotationDegrees` equivalent (Nim transform.nim:349) and an f32-quantize
  helper matching `quantizeF32` if one does not already exist in the Dart model.
- `IkConstraintData` (`runtime-dart/lib/src/model.dart:90-119`) already exposes
  `bones`, `target`, `mix`, `bendPositive`, `order`, and the `runtimeEvaluable`
  getter (line 118). Read that class for the exact field set before coding.

**Links to Relevant Documentation**
- Clean room: docs/CLEANROOM.md
- Provenance: docs/PROVENANCE.md
- Comparable research: docs/comparable-feature-set.md (constraint family: capability category only)
- IK format + runtime-status contract: docs/ik-constraint-format-contract.md (esp. §3-§6 geometry, §8 per-runtime status to update)
- Nim solvers: runtime-nim/src/bony/constraints/ik.nim
- Nim evaluation entry: runtime-nim/src/bony/transform.nim:389-524 (+ helpers 349, 353, 357, 376)
- Dart runtime seam: runtime-dart/lib/src/transform.dart:448 (computeWorldTransforms), 280-368 (update cache), 370-443 (_applyRuntimePathConstraint), 114 (_worldForBone)
- Dart model: runtime-dart/lib/src/model.dart:90-119 (IkConstraintData), 166 (SkeletonData.ikConstraints)
- Conformance asset/golden/script: conformance/assets/m5_ik_rig.bony, conformance/goldens/m5_ik_rig_t0.json, conformance/scripts/m5_ik_sample.json
- Dart conformance gate to extend: runtime-dart/test/m10_conformance_test.dart
- Dart IK tests to upgrade: runtime-dart/test/ik_constraint_test.dart, runtime-dart/test/m5_constraint_test.dart (deferral note)
- Memory context: me5.13 contract decision = CURRENT-PIVOT anchoring (applyRuntimeIk feeds current FK origins; contract §4 amended)

**Success Criteria**
- Dart `computeWorldTransforms` evaluates all three IK shapes exercised by
  `m5_ik_rig` (1-bone `reach_one`, 2-bone `reach_two` with
  `bendPositive: false`, 3-bone FABRIK `reach_chain` with `mix: 0.5`) and its
  bone world matrices match `conformance/goldens/m5_ik_rig_t0.json` within
  absolute tolerance `1e-4`. (The t=0 setup pose is non-vacuous: solved IK
  differs from the unconstrained pose by a world delta of ~36 — so passing the
  golden proves real solving, not a no-op.)
- `runtime-dart/test/m10_conformance_test.dart` adds an
  `_checkGolden('M5-IK', '../conformance/assets/m5_ik_rig.bony', '../conformance/goldens/m5_ik_rig_t0.json')`
  entry and its header comment is updated to include M5-IK.
- `runtime-dart/test/ik_constraint_test.dart` is upgraded from load-only
  assertions to also assert SOLVED output (e.g. terminal bone world angle /
  world matrix for at least the 2-bone and chain cases), and the "IK evaluation
  is out of scope in Dart" comment (line 3) is removed/replaced.
- `runtime-dart/test/m5_constraint_test.dart` deferral note (lines 9-12) is
  updated to reflect that Dart now evaluates IK.
- `docs/ik-constraint-format-contract.md` §8 Dart bullet (lines 154-162) is
  rewritten to state Dart IK evaluation is live, mirroring the Nim bullet.
- `conformance/README.md` M5 (IK) row / notes remain accurate; if any text
  implies Dart does not cover IK, update it (the numeric goldens are the
  cross-runtime contract and Dart now honors them).
- Existing Dart tests still pass; existing Nim tests, conformance, round-trip,
  and input-script gates are unaffected.

**Verification commands**
```bash
# Dart: full suite (IK unit tests + m10 conformance gate)
cd runtime-dart && dart test && cd ..

# Nim + cross-runtime gates unchanged (build CLI, run suite)
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim
python3 scripts/ci/suite_run.py --bony-bin /tmp/bony_bin
```

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
  The only sources for the solver behavior are this project's own
  `runtime-nim/src/bony/constraints/ik.nim`, `transform.nim`, and
  `docs/ik-constraint-format-contract.md`.
- Use `docs/comparable-feature-set.md` only for capability categories, never
  for algorithm, identifier, or wire-shape detail.
- Keep Rive importer work out of scope. Keep Spine importer work blocked for
  human/legal review.
- Match the Nim reference numerically — do not invent a different solver, mix
  convention, quantization point, or anchoring model. Current-pivot anchoring
  (me5.13, contract §4) is binding.
- Do NOT change the `.bony`/`.bnb` format, the registry, the schema, the
  committed goldens, or the Nim runtime. This is a Dart-runtime + Dart-test +
  doc-status change only.
- **Scope guard — out of this slice:** the state-machine-driven IK *story*
  goldens (`conformance/goldens/m5_ik_story_{rest,reach_mid,reach_end}.json`)
  are a separate follow-up (they require Dart to drive `m5_ik_story.json`
  through the state machine and project the animated target). This slice gates
  the t=0 setup pose only. Also out of scope: transform/physics constraint
  families, and any broadening of the Dart conformance gate to m2/m3/m4/m5/m7/m9
  (a separate "useful" milestone).
- Keep the slice small enough for one meaningful implementation session.
