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
= 4002 (M5 band 4000–4999). Note that type keys and property keys live in
**separate namespaces**, so the `ikConstraint` type key 4002 and the reused
`order` property key 4002 are not a collision.

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

Bone names resolve to bones whose world origins are FK-composed at evaluation
time (step 2); `BoneData` stores only `name`/`parent`/`local` — no world position
or segment length (`runtime-nim/src/bony/model.nim:51-54`).

Segment **lengths** are rest-pose-derived and fixed (§6), but the chain
**anchors at the live pose** — joint origins and the anchor come from the
*current* FK worlds. This is the M5 anchor decision (bony-me5.13): a chain whose
root has a moved/animated parent aims from the live pivot (so the end-effector
can reach a live target), and `mix=0` is the current-pose identity. Rest-derived
lengths keep bones rigid regardless of the live pose.

The chain points and lengths are:

- **lengths** = distances between consecutive REST-pose points — each bone's
  rest-pose world origin in chain order, closed by the target bone's rest-pose
  world origin ⇒ `#lengths = #bones`. Fixed regardless of the live pose (§6).
- **points** (≥3-bone chain only) = each bone's CURRENT world origin, in chain
  order, closed by the last bone's current tip (its current origin advanced by
  the last rest length along its current world direction) ⇒
  `#points = #bones + 1`. The 1- and 2-bone cases pass the anchor as `origin`
  rather than a points array.
- **origin** = the first bone's CURRENT world origin.
- The **target bone's REST position closes the rest chain** (it supplies the leaf
  bone's length); the **target bone's CURRENT position is the goal** the solver
  reaches toward.

Per-case feed:

- **1 bone** → `solveOneBoneIk(origin, length, currentRotation, target, mix)`,
  with `origin` the bone's current world origin and
  `length = |target_rest − bone0_rest|`.
- **2 bones** → `solveTwoBoneIk(origin, parentLength, childLength,
  parentRotation, childRotation, target, bendSign, mix)`, with `origin` the first
  bone's current world origin, `parentLength = |bone1_rest − bone0_rest|` and
  `childLength = |target_rest − bone1_rest|`. `childRotation` is the child's
  current rotation **relative to its parent** (current child world rotation minus
  current parent world rotation), since `solveTwoBoneIk` bends the child in
  parent-relative space.
- **≥ 3 bones** → `solveChainIk(points, lengths, target, mix)` with the
  current-pose points and rest-derived lengths above.

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

## 8. Runtime implementation status (handoff)

The runtime slice (§1's "separate slices") has landed for the reference runtime.
This section records the current per-runtime status so downstream work is not
misled about parity.

- **Nim reference runtime — IK evaluation is live.** Both loaders parse IK
  (`runtime-nim/src/bony/jsonio.nim` for `.bony`, `binary/semantic.nim` for
  `.bnb`), and IK is *evaluated* during the world-transform pass:
  `computeWorldTransforms` (`runtime-nim/src/bony/transform.nim`) applies each
  `runtimeEvaluable` constraint via `applyRuntimeIk`, feeding the solver in
  `constraints/ik.nim`. Covered by the Nim unit tests and the conformance /
  round-trip gates.

- **Dart runtime — IK evaluation is live.** The Dart runtime carries IK
  constraint *data* to parity: `IkConstraintData` + `SkeletonData.ikConstraints`
  (`runtime-dart/lib/src/model.dart`) and IK parse/decode for both JSON and
  `.bnb`, including load-time validation (`runtime-dart/lib/src/loader.dart`).
  IK is now also *evaluated* during the world-transform pass:
  `computeWorldTransforms` (`runtime-dart/lib/src/transform.dart`) applies each
  `runtimeEvaluable` constraint via `_applyRuntimeIk`, feeding the ported
  solvers in `runtime-dart/lib/src/ik.dart` — a line-for-line port of the Nim
  reference honoring the current-pivot anchoring contract (§4). Covered by the
  Dart solver/helper unit tests, the solved-output assertions in
  `runtime-dart/test/ik_constraint_test.dart`, and the M5-IK setup-pose golden
  gate in `runtime-dart/test/m10_conformance_test.dart`, which matches the
  committed `conformance/goldens/m5_ik_rig_t0.json` within `1e-4`.
