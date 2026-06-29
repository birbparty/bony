# /big-change prompt - runtime (IK constraint evaluation)

> **How to use this in a later session**
> 1. `cd /Users/punk1290/git/bony`
> 2. Paste everything below the line into the session.
> Tell the agent: *all four inputs (Description, Links, Success Criteria,
> Constraints) are provided below - treat Questions 1-4 as pre-answered, echo
> them back once for a single confirmation, then proceed to auto-detection and
> generate the plan.*
>
> **Order:** this is **step 2 of 3**. Depends on step 1 freezing the IK
> registry keys, JSON schema, and `IkConstraintData` model. Blocks step 3.
> **Candidate category:** frontier.

---

/big-change Make IK constraints runtime-evaluable in the Nim reference runtime (load JSON + `.bnb`, integrate the existing solver into the pose pass) and load them in the Dart model for parity.

You already have all four `/big-change` inputs below - treat Questions 1-4 as
pre-answered, echo them back for one confirmation, then proceed.

**Description**

Step 1 defined the IK constraint format (registry keys, schema, `IkConstraintData`).
This slice makes it actually run in the Nim reference runtime, mirroring exactly
how path constraints are loaded and evaluated:

- JSON load/emit in `runtime-nim/src/bony/jsonio.nim` (path precedent: load at
  lines ~430-447, allowed-root-keys list at line 311, emit at lines ~1462-1482).
- Binary encode/decode in `runtime-nim/src/bony/binary/semantic.nim` (path
  precedent: type keys at lines 19-20, property keys at 51-52; the
  **path-constraint** emit loop is `for path in data.paths` at line **876** -
  note line 863 is the sibling `pathAttachment` loop, not the constraint loop).
- A combined deterministic ordered update-cache in
  `runtime-nim/src/bony/constraints/update_cache.nim`. The generic
  `buildConstraintUpdateCache` (line 107) already sorts every `ConstraintKind`
  except `ckPhysics` (line 116) - including `ckIk` - by `constraint-total-order.md`
  priority. **Do not build a second independent IK cache.** Today
  `transform.nim:136` calls `buildPathConstraintUpdateCache(data)`, which only
  emits path descriptors. Replace it with one builder that emits descriptors for
  **both** path and IK constraints into a single `descriptors` seq and calls
  `buildConstraintUpdateCache(data.bones, descriptors)` once, so cross-kind
  ordering (ckIk priority 0 runs before ckPath) is correct. For IK descriptors,
  set `writes` = the constrained `bones` list and `reads` = `[target]` plus the
  bones' parents (so the cache emits target/parent world transforms before the
  solve), exactly as `buildPathConstraintUpdateCache` (line 169) does for paths.
- Pose-pipeline integration in `runtime-nim/src/bony/transform.nim` (path
  precedent: the cache loop at lines 127-156 and `applyRuntimePathConstraint`
  implementation at line 251), dispatching each `ccekConstraint` entry by
  `entry.constraint.kind` to either the path apply or a new `applyRuntimeIk`,
  calling the **existing** solver `runtime-nim/src/bony/constraints/ik.nim`
  (`solveOneBoneIk`, `solveTwoBoneIk`, `solveChainIk`).

**Solver I/O mapping and write-back (the part most likely to be gotten wrong).**
The solver works in world space and returns rotations in **degrees**:
- Derive inputs from the **current world transforms** in the `worlds` array: each
  bone's origin point is its world translation; per-segment `lengths` are the
  rest-pose distances between consecutive bone origins (computed, not stored - see
  step 1); the `target` point is the target bone's world translation.
- Select the solver by `bones.len` (1/2/>=3). Pass `mix` and, for two-bone,
  `bendSign = if bendPositive: 1.0 else: -1.0`.
- The solver returns absolute world angles (`solveChainIk.rotations` are absolute
  segment angles, `ik.nim:29`). Convert each solved world angle back to that
  bone's **local** rotation before writing, using the same parent-inverse
  machinery the path integration already uses: `parentWorld` / `inverseAffine(
  parentWorld)` at `transform.nim:270-279`, with local rotation written at
  `transform.nim:293/307-311` and the bone re-worlded via `worldForBone` at
  `transform.nim:323`. Apply `mix` as a blend between the bone's current local
  rotation and the IK-solved local rotation. Downstream cache bone-groups then
  recompute world transforms for descendants.

The Dart runtime currently *parses* M5 constraints but defers evaluation to the
animated runtime (`runtime-dart/test/m5_constraint_test.dart` header note). Match
that posture: add `IkConstraintData` loading to `runtime-dart/lib/src/model.dart`
(sibling of `PathConstraintData` at line 65, `SkeletonData.paths` at line 132) so
`.bony`/`.bnb` IK assets round-trip through the Dart loader without error. Dart
*evaluation* parity is explicitly out of scope and tracked separately.

**Links to Relevant Documentation**
- Clean room: `docs/CLEANROOM.md`
- Provenance: `docs/PROVENANCE.md`
- Comparable research: `docs/comparable-feature-set.md`
- Constraint ordering contract: `docs/constraint-total-order.md`
- Transform composition contract: `docs/transform-composition-contract.md`
- Float-math/determinism contract: `docs/float-math-contract.md`
- Binary canonicalization: `docs/binary-canonicalization.md`,
  `docs/binary-toc-skip-semantics.md`
- IK solver (already implemented; integrate, do not rewrite the math):
  `runtime-nim/src/bony/constraints/ik.nim`
- Path-constraint runtime precedent: `runtime-nim/src/bony/transform.nim`,
  `runtime-nim/src/bony/constraints/path_constraints.nim`,
  `runtime-nim/src/bony/constraints/update_cache.nim`
- JSON loader/emitter: `runtime-nim/src/bony/jsonio.nim`
- Binary loader/emitter: `runtime-nim/src/bony/binary/semantic.nim`
- Dart model: `runtime-dart/lib/src/model.dart`
- Step 1 output: the frozen IK registry keys, schema, and `IkConstraintData` model.

**Current Local Facts To Preserve**
- `ik.nim` already quantizes via `quantizeF32` and uses `fabrikIterations = 8`,
  `fabrikTolerance = 1e-4`. Do not change the solver math or constants; the
  cross-runtime tolerance is `1e-4` (`docs/float-math-contract.md`).
- The generic `buildConstraintUpdateCache` (`update_cache.nim:107`) already
  excludes `ckPhysics` and orders all other kinds; reuse it via a single combined
  builder (see above). Do not duplicate the generic sort/ordering logic.
- Path integration only evaluates entries whose constraint is `runtimeEvaluable`
  (`runtimeEvaluable*(path: PathConstraintData)` at `model.nim:370`, used at
  `transform.nim:130`). Add the IK equivalent `runtimeEvaluable*(ik:
  IkConstraintData): bool` and define its condition explicitly: true when the
  `target` and every entry in `bones` resolve to known bones and `mix > 0`.
  Keep degenerate/unsolvable IK (unreachable target, zero-length segment)
  non-fatal and deterministic by relying on the solver's existing fallbacks
  (`ik.nim:175-200`); do not add new error paths for them.
- `jsonio.nim:311` `validateKnownKeys(root, [...])` must gain the IK top-level key
  chosen in step 1, or IK assets will be rejected as unknown keys.
- `.bnb` round-trip must stay byte-stable: after adding IK encode/decode,
  `scripts/ci/round_trip_run.py` must still pass for all existing fixtures
  (no IK fixtures exist yet - they arrive in step 3).

**Success Criteria**
- Nim loads IK constraints from `.bony` JSON and from `.bnb`, evaluates them in
  the world-transform pass via the existing `ik.nim` solver, and writes results
  through the same path the path-constraint integration uses.
- New Nim unit tests in `runtime-nim/tests/` (extend `test_smoke.nim` or add a
  focused test) cover: one-bone reach, two-bone bend (both `bendSign`), an
  N-bone chain, `mix` interpolation at `0`/`0.5`/`1`, and a degenerate
  unreachable target. Assert deterministic output within `1e-4`.
- IK constraints survive `json -> bnb -> json` and `bnb -> json -> bnb`
  byte-stable round-trips (proven by a temporary local fixture during
  development; committed conformance fixtures are added in step 3).
- `runtime-dart/lib/src/model.dart` loads `IkConstraintData` and existing Dart
  tests still pass; Dart evaluation parity is explicitly deferred and noted in a
  test comment, matching the existing path-constraint deferral note.
- No new format keys or schema fields beyond what step 1 froze. If step 2 reveals
  the step-1 format is insufficient, stop and amend step 1's registry/schema
  rather than inventing keys here.
- Verification:

```bash
nim check --hints:off --path:runtime-nim/src runtime-nim/src/bony.nim
cd runtime-nim && nimble test && cd ..
nim c --path:runtime-nim/src -o:/tmp/bony_bin cli/bony_cli.nim
python3 scripts/ci/round_trip_run.py --bony-bin /tmp/bony_bin
python3 scripts/ci/conformance_run.py --bony-bin /tmp/bony_bin
python3 scripts/ci/suite_run.py --bony-bin /tmp/bony_bin
cd runtime-dart && dart test && cd ..
```

**Constraints**
- Preserve clean-room posture: do not inspect or derive from DragonBones,
  Spine, Rive, Live2D, or Lottie runtime source, importer source, generated
  definitions, exact wire layouts, type/property keys, or copied docs prose.
- Use `docs/comparable-feature-set.md` only for capability categories.
- Keep Rive importer work out of scope.
- Keep Spine importer work blocked for human/legal review.
- Do not modify the IK solver math in `ik.nim`; integrate it. If a genuine bug is
  found in the solver, file a separate bead rather than expanding this slice.
- IK only - do not wire transform or physics constraints.
- Dart scope is model loading/parity only; no Dart IK evaluation.
- Keep `.bnb` byte-stability and all existing conformance gates green.
- Keep the slice small enough for one meaningful implementation session.
