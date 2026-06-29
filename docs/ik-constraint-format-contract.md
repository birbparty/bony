# IK Constraint Format Contract

This contract records the frozen `.bony` / `.bnb` format for IK (inverse
kinematics) constraints and the binding rules that the Nim and Dart runtimes,
loaders, and the conformance harness must follow. It is the format half of the
M5 IK milestone; solver wiring, loaders, binary decode, and conformance assets
are separate slices and are out of scope here.

The repository keeps contract documents directly under `docs/` (there is no
`docs/specs/` or `docs/adr/`). The authoritative decision record that this note
formalizes is `.agents/notes/ik-format-freeze.md`; ordering interactions are
defined in [Constraint Total-Order Contract](./constraint-total-order.md)
(IK has `stageRank = 0` / kind rank `ik = 0`, applied before transform and path).

## 1. Frozen top-level key and fields

The top-level JSON collection key is **`ikConstraints`** (an array of IK
constraint objects). It is auto-derived as `objectId + "s"` from the registry
object id `ikConstraint`; there is no `root_collection_overrides` entry.

Each IK constraint object has exactly these fields (names and casing are frozen):

| field | JSON type | required | default | registry key / backing |
|-------|-----------|----------|---------|------------------------|
| `name` | string (minLength 1) | yes | — | reuse `name` = 1, string |
| `bones` | array of strings (minItems 1) | yes | — | `bones` = 4014, bytes (packed; see §2) |
| `target` | string | yes | — | reuse `target` = 4000, string |
| `order` | integer | no | `0` | reuse `order` = 4002, varint |
| `mix` | number in [0, 1] | no | `1.0` | `mix` = 4015, f32 |
| `bendPositive` | boolean | no | `true` | `bendPositive` = 4016, bool |

`requiredProperties` = `[bones, name, target]`; `order`/`mix`/`bendPositive` are
defaulted. The registry object property order is
`[name, bones, target, order, mix, bendPositive]`. Type key: `ikConstraint`
= 4002 (M5 band 4000–4999).

## 2. `bones` packed-bytes wire layout (append-only)

On the wire (`.bnb` and the flat wire schema) `bones` is backed by **bytes**,
packed as:

```
varuint count, followed by count * (varuint string-table index for bone name)
```

i.e. a count followed by that many varuint indices into the string table, one per
bone name, in chain order (root → tip). This is the same packing precedent as
`blendAxes` (key 6041). **This layout is frozen and append-only for the lifetime
of the format** — it may never be renumbered or repacked.

In authored JSON (`spec/bony.schema.json`) `bones` surfaces as a non-empty array
of strings (`minItems: 1`, items `{type: string, minLength: 1}`) via a
`canonical_json_overrides["ikConstraint"]` entry. The flat wire schema
(`spec/bony-wire.schema.json`) legitimately keeps `bones` as a base64 string with
an `x-bony-packedBytes` annotation. Both views describe the same data.

## 3. Solver selection by `bones` length

The number of bones selects the solver (the solvers already exist in
`runtime-nim/src/bony/constraints/ik.nim`):

| `len(bones)` | solver |
|--------------|--------|
| 1 | `solveOneBoneIk` |
| 2 | `solveTwoBoneIk` |
| ≥ 3 | `solveChainIk` (FABRIK) |

## 4. `bones` names → solver inputs

Bone names resolve to bones whose **rest-pose world origins** are FK-composed at
evaluation time (step 2); `BoneData` stores only `name`/`parent`/`local` — no
world position or segment length (`runtime-nim/src/bony/model.nim:51-54`).

The chain points and lengths are:

- **points** = each bone's rest-pose world origin, in chain order,
  `++ [target bone rest-pose world origin]` ⇒ `#points = #bones + 1`.
- **lengths** = distances between consecutive points ⇒ `#lengths = #bones`.
- **origin** = the first bone's rest-pose world origin.
- The **target bone's REST position closes the chain** (it supplies the leaf
  bone's length); the **target bone's CURRENT position is the goal** the solver
  reaches toward.

Per-case feed:

- **1 bone** → `solveOneBoneIk(origin, length, currentRotation, target, mix)`,
  with the single `length = |target_rest − bone0_rest|`.
- **2 bones** → `solveTwoBoneIk(origin, parentLength, childLength,
  parentRotation, childRotation, target, bendSign, mix)`, with
  `parentLength = |bone1_rest − bone0_rest|` and
  `childLength = |target_rest − bone1_rest|`.
- **≥ 3 bones** → `solveChainIk(points, lengths, target, mix)` with the
  full points/lengths arrays above.

In all cases `mix` is the blend weight in `[0, 1]`.

## 5. `bendPositive` is permitted-but-ignored outside two-bone

`bendPositive` is valid in the schema for **every** IK constraint regardless of
bone count, and loading it never raises an error. It is **consumed only by
`solveTwoBoneIk`** (mapped to `bendSign`: `true → +1.0`, `false → −1.0`). For
1-bone and ≥3-bone constraints it is loaded and ignored — no load error, no
effect.

## 6. Segment lengths are rest-pose-derived at runtime, never stored

This is a **binding decision**: IK segment lengths are computed from rest-pose
world origins at evaluation time and are **never** persisted in the format. The
format stores bone *names*, not lengths or positions. This keeps the constraint
record minimal and authoritative (lengths always reflect the current rest pose),
and is why `bones` carries names rather than precomputed geometry.

## 7. `IkConstraintData` fields are unexported

In `runtime-nim/src/bony/model.nim`, `IkConstraintData` is an exported type whose
**fields are unexported**, mirroring `PathConstraintData`. The exported
`ikConstraintData*` constructor quantizes `mix` through `quantizeF32` and enforces
`mix ∈ [0, 1]` (message `"ik.mix must be in [0, 1]"`, matching `requireMix` in
`constraints/ik.nim`). Step-2 loader/evaluation code reads these fields via
accessors/loader rather than directly.
