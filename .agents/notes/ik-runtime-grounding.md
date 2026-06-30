# IK Runtime Grounding (bony-me5.1)

Independent re-confirmation of the facts the step-2 runtime IK plan
(`.agents/plans/runtime-ik-constraint-evaluation.md`) relies on, verified against
`main` on 2026-06-29. **No code in this bead** — this note is the deliverable.
Every claim below was checked by reading the cited source line; all CONFIRMED.

## A. Frozen registry constants — `runtime-nim/src/bony/generated/wire.nim`

| key | id | value | backingType | line |
|---|---|---|---|---|
| type | `ikConstraint` | 4002 | — | wire.nim:47 |
| property | `bones` | 4014 | `bytes` (packed) | wire.nim:100 |
| property | `mix` | 4015 | `f32` | wire.nim:101 |
| property | `bendPositive` | 4016 | `bool` | wire.nim:102 |

`target` / `order` in the objectSpec REUSE the shared property keys already in
`semantic.nim` (`targetKey=4000`, `orderKey=4002`). Type-key 4002 and
property-key 4002 are in SEPARATE namespaces — no collision. Do NOT mint new keys.

## B. `bones` packing + per-case solver feed — `docs/ik-constraint-format-contract.md`

- **§2 (lines 39–51):** `bones` = `varuint count`, then `count × varuint
  string-table index` for each bone name, chain order root→tip. These are
  STRING-TABLE indices, not skeleton bone-order indices. Same packing precedent
  as `blendAxes` (key 6041) — mirror that pack/unpack helper.
- **§3 (lines 59–68):** solver selection by `bones.len`: 1→`solveOneBoneIk`,
  2→`solveTwoBoneIk`, ≥3→`solveChainIk` (FABRIK).
- **§4 (lines 86–97):** per-case feed signatures:
  - 1: `solveOneBoneIk(origin, length, currentRotation, target, mix)`
  - 2: `solveTwoBoneIk(origin, parentLength, childLength, parentRotation, childRotation, target, bendSign, mix)`
  - ≥3: `solveChainIk(points, lengths, target, mix)`
- **§5 (lines 99–105):** `bendPositive` is consumed ONLY by `solveTwoBoneIk`;
  loaded-and-ignored for 1-bone and ≥3-bone (no load error, no effect).

## C. Path precedent — `transform.nim` / `update_cache.nim`

- `applyRuntimePathConstraint` (transform.nim:251–259): resolves bone name→index
  via `indexes` table, mutates the bone's local, re-worlds it, marks computed.
  This is the write-back shape `applyRuntimeIk` mirrors — but IK chains write
  MULTIPLE mutually parent→child bones (all in `writes`), so `applyRuntimeIk`
  must FK-compose and write sequentially, not the single-bone path.
- `buildConstraintUpdateCache*(bones, descriptors)` (update_cache.nim:107–110)
  is the generic ordered builder; `buildPathConstraintUpdateCache` (169–174)
  feeds it path descriptors with `reads = @[path.target]` only (parent lineage
  walked automatically by `emitReadDependencies`). The combined builder must feed
  BOTH path and IK descriptors into ONE `buildConstraintUpdateCache` call.

## D. Solver output conventions — `runtime-nim/src/bony/constraints/ik.nim`

- `solveOneBoneIk` (84–102): `result.rotation` is ABSOLUTE world degrees
  (lerp of absolute base→target, line 97).
- `solveChainIk` (155–242): `result.rotations` are ABSOLUTE world degrees
  (`arctan2` between consecutive world points, line 242).
- `solveTwoBoneIk` (105–152): `result.parentRotation` ABSOLUTE; `result.childRotation`
  RELATIVE-to-parent — proven by line 144 composing `parentRotation + childRotation`
  to get the child's absolute angle.

**Consequence for `applyRuntimeIk`:** do NOT use one uniform absolute→local
conversion. One-bone + chain results convert absolute→local via the parent-inverse
machinery; the two-bone CHILD is already relative-to-parent. `mix` is applied ONCE
inside the solver (do not re-blend — that yields mix²).

## E. Model foundation seam (for bony-me5.2) — `runtime-nim/src/bony/model.nim`

Verified state on `main` so the next bead does not have to re-discover it:

- `IkConstraintData` exists (model.nim:90–98) but its fields are UNEXPORTED
  (`name`/`bones`/`target`/`order`/`hasMix`/`mix`/`hasBendPositive`/`bendPositive`,
  no `*`). `SkeletonData.ikConstraints` exists (model.nim:199) and is also
  UNEXPORTED. There is NO `ikConstraints*(data)` collection accessor (contrast
  `proc paths*` at model.nim:437) and NO IK field accessors.
- `runtimeEvaluable*(path: PathConstraintData)` lives at model.nim:405 and checks
  ONLY constraint-local flags (`hasPosition or hasTranslateMix or hasRotateMix`) —
  no skeleton access. The IK overload does NOT exist yet.
- **Decision (plan §Description line 49, form (a)):** add
  `runtimeEvaluable*(ik: IkConstraintData): bool` as the constraint-only form
  `mix > 0` (and `bones.len >= 1`), mirroring the path predicate's purity. Move
  bone/target name resolution to the apply path, where `boneIndexes()` already
  raises/skips unknown bones. Keep degenerate IK non-fatal.

**Entry-gate gotcha (transform.nim:127–133):** `computeWorldTransforms` sets
`hasRuntimePaths` by scanning `data.paths` ONLY, then gates the entire
constraint-applying branch on it. A pure-IK rig with no runtime-evaluable path
falls through to the plain branch and silently never evaluates — the plan calls
this "the single easiest defect to ship." The core-eval bead MUST extend this gate
to also fire on a `runtimeEvaluable` IK constraint. (Covered by the plan; recorded
here so it is not lost between beads.)

## Outcome

All claims in §A–§D CONFIRMED against source; §E records the model.nim foundation
state and the resolved `runtimeEvaluable*(ik)` signature decision. The step-2 plan
is grounded. Downstream: bony-me5.2 has the verified model.nim seam + signature
decision it needs; bony-me5.9 (Dart parity) depends only on the frozen keys (§A)
and contract (§B), both confirmed. Binary/transform/jsonio seams beyond what is
cited above were NOT independently audited here — defer to the plan's per-bead
line-number citations for those.
