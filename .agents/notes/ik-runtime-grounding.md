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

## Outcome

All claims CONFIRMED. The step-2 plan is grounded; downstream beads bony-me5.2
(model accessors + `runtimeEvaluable`) and bony-me5.9 (Dart parity) are unblocked
to proceed against these verified seams.
