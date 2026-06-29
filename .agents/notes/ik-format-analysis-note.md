# IK Constraint Format — Analysis Note

Analysis bead: **bony-b5d.1** (epic bony-b5d). Read-and-document only — no source
was edited. Every fact below is grounded against the files cited (line numbers as
of this commit). This note is the source material for the format-freeze bead
(bony-b5d.2) and the later registry/defaults/codegen/model implementation beads.

---

## 1. The codegen-driven format flow (`codegen/generate.py`)

The format is **source-driven**: two checked-in YAML files are the source of
truth, and four artifacts are *generated* from them. You never hand-edit the
artifacts.

### Sources (inputs)
- `registry/wire.yml` — append-only key registry: `typeKeys`, `propertyKeys`
  (each with a `backingType`), and `objects` (each object = a `type` + an ordered
  `properties` list). Path constants: `REGISTRY_PATH` (generate.py:19).
- `spec/defaults.yml` — per-object `objectDefaults` and `requiredProperties`.
  Path: `DEFAULTS_PATH` (generate.py:20).

### Validation gate — `validate_sources()` (generate.py:194, called **unconditionally** at 1262)
Runs before any artifact is produced, on every invocation (not just `--check`).
Enforces:
- Format tokens (`bony-wire-registry`, `bony-default-table`).
- typeKeys / propertyKeys: no duplicate ids or keys; key `0` reserved; each key
  inside its declared milestone range; `backingType` references a declared type.
- objects: each `object.type` is a declared typeKey; each property reference is a
  declared propertyKey.
- **Default coverage (the trap, generate.py:261-309):** *every* property of every
  registry object must appear in **exactly one** of `objectDefaults` or
  `requiredProperties` — never both, never neither. A registry property with no
  defaults entry → `missing coverage` failure; a defaults entry with no registry
  property → `extra coverage` failure.

> **Consequence for implementation sequencing:** because `validate_sources()` runs
> unconditionally and cross-checks both files, a registry object and its
> defaults.yml coverage (plus the regenerated artifacts) must land **together**.
> Half a change cannot pass the gate alone. This is why the IK contract step
> (registry keys + schema + model) is scoped as one atomic bead.

### Schema generation
- `generate_wire_schema(registry, defaults)` (generate.py:493) → `bony-wire.schema.json`:
  flat schema, one `$def` per registry object, collections as uniform `id + "s"`.
- `generate_schema(registry, defaults)` (generate.py:442) → `bony.schema.json`:
  starts from the wire schema, then merges `canonical_json_overrides()`
  (generate.py:559) for human-authored nested structures, filters
  `hidden_binary_children`, and renames root collections via
  `root_collection_overrides` (generate.py:468; e.g. `animationClip`→`animations`).
- `schema_for_property(property_id, backing_type)` (generate.py:875) maps a
  registry property to JSON-schema. Backing type drives the base type; a few
  property ids get extra constraints — notably **`position`/`translateMix`/
  `rotateMix` → `minimum: 0, maximum: 1`** (generate.py:891-893), and `name` →
  `minLength: 1`. New IK mix-like properties in [0,1] should follow this pattern.

### Packed-bytes precedent — `PACKED_BYTES_METADATA` (generate.py:26)
For `bytes`-backed properties that pack a binary blob, an entry here makes
`schema_for_property()` attach an `x-bony-packedBytes` extension (generate.py:877).
Today only `timelineKeys` is registered. The registry-level precedent for a
packed-bytes property is **`blendAxes`** (see §2). IK does *not* need packed bytes
for the M5 contract (its fields are scalar), but the precedent is the model to
follow if a packed bone-list is ever chosen.

### Artifacts (outputs) — `write_or_check` (generate.py:1264-1267)
1. `SCHEMA_PATH` = `spec/bony.schema.json` (canonical)
2. `WIRE_SCHEMA_PATH` = `spec/bony-wire.schema.json` (flat)
3. `NIM_WIRE_PATH` = `runtime-nim/src/bony/generated/wire.nim`
4. `DART_WIRE_PATH` = `runtime-dart/lib/src/generated/wire.dart`

`--check` regenerates in memory and diffs against disk; any drift → exit 1
("stale generated files"). This is the freshness gate the root `Makefile` and the
registry README mandate.

---

## 2. The `path` precedent (the object IK mirrors)

### registry/wire.yml
- **Type key:** `path` = **4000** (wire.yml:26-27). Sibling in M5: `pathAttachment`
  = **4001** (wire.yml:32-33).
- **Object** (`- type: path`, wire.yml:954-964), ordered properties:
  `name, bone, target, path, order, position, translateMix, rotateMix`.
- **Property keys (M5 band 4000-4999):**

  | prop | key | backingType |
  |------|-----|-------------|
  | target | 4000 | string |
  | path | 4001 | string |
  | order | 4002 | varint |
  | p0x..p3y | 4003-4010 | f64 |
  | position | 4011 | f32 |
  | translateMix | 4012 | f32 |
  | rotateMix | 4013 | f32 |

### spec/defaults.yml
- `path` **objectDefaults** (defaults.yml:170-192): `order=0` (omitWhenDefault,
  applyOnLoad), `position=0.0`, `translateMix=1.0`, `rotateMix=0.0` (opt-in,
  *not* applyOnLoad).
- `path` **requiredProperties** (defaults.yml:372-387): `name, bone, target, path`.
- Coverage check (defaults.yml:65): "every object property must appear exactly
  once in either objectDefaults.properties or requiredProperties." Path's 8
  properties split 4 required / 4 defaulted — exactly the partition
  `validate_sources()` enforces.

### runtime-nim/src/bony/model.nim
- `ConstraintKind` enum (model.nim:32-36): `ckIk`(33), `ckTransform`(34),
  `ckPath`(35), `ckPhysics`(36). **`ckIk` already exists and sorts first** —
  `constraintKindRank` returns `0` for `ckIk` (model.nim:628); canonical order is
  "IK/transform/path/physics" (model.nim:634).
- `PathConstraintData` object (model.nim:77-88): `name, bone, target, path:
  string; order: int; hasPosition: bool; position: float64; hasTranslateMix:
  bool; translateMix: float64; hasRotateMix: bool; rotateMix: float64`. The
  `hasX`/`X` pairs mirror the omitWhenDefault optionals in defaults.yml.
- `pathConstraintData*` constructor (model.nim:281-312): defaults `order=0,
  position=0.0, translateMix=1.0, rotateMix=0.0`; runs each float through
  `quantizeF32` and validates mix ranges to [0,1].
- **SkeletonData field is `paths: seq[PathConstraintData]` (model.nim:188)** — note
  the field is `paths`, *not* `pathConstraints`. A parallel IK field should follow
  the same short-plural convention (e.g. `iks: seq[IkConstraintData]`); confirm the
  exact spelling at implementation time since the wire/schema collection name
  (`id + "s"`) and the Nim field must agree with codegen output.
- `quantizeF32` (model.nim:206-211): rejects NaN/Inf, round-trips through float32,
  raises `numericOutOfRange` otherwise. Every persisted f32 field uses it.
- `BoneData` (model.nim:51-54): `name, parent: string; local: LocalTransform`.

---

## 3. Key allocation for the IK object (next-free, append-only)

Per registry/README.md Review Checklist (registry/README.md:78-97): new keys must
be positive, unused, inside the owning milestone range
(`registry/key-ranges.md`), backing types of existing keys unchanged, key 0
reserved, and **`python3 codegen/generate.py --check` + `python3 -m unittest
discover -s codegen -p 'test_*.py'`** must pass. IK belongs to **M5 (4000-4999)**.

### Next-free TYPE key
- M5 typeKeys in use: `path`=4000, `pathAttachment`=4001.
- **Next-free type key = 4002** → assign to the new `ik` object.

### Next-free PROPERTY keys
- Highest M5 property key in use: `rotateMix`=4013.
- **Next-free property key = 4014** and upward (append-only).

### Reused keys (global propertyKey scope — same key, same backingType)
- `name` = **1**, string (wire.yml:345-351, M1).
- `target` = **4000**, string (wire.yml:478-484).
- `order` = **4002**, varint (wire.yml:492-498).

  IK can reference these existing property keys rather than minting new ones,
  exactly as `path` reuses `name`/`target`/`order`. Any genuinely new IK property
  (e.g. a mix, a bend-direction flag, a bone list) gets a fresh key from 4014+.

### blendAxes packed-bytes precedent (if a packed bone list is ever needed)
- `blendAxes` = key **6041**, `backingType: bytes` (wire.yml:716-722, M7): "packed
  as varuint count followed by count*(varuint string-table index)". This is the
  template for encoding a variable-length list of bone-name references as one
  bytes property. For the M5 IK *contract* this is likely unnecessary (scalar
  fields suffice), but it is the documented pattern if the design later packs a
  multi-bone chain.

---

## 4. Solver inputs → required IK fields (`runtime-nim/src/bony/constraints/ik.nim`)

The IK solver already exists; the format must carry exactly what it consumes.

- `solveOneBoneIk(origin, length, currentRotation, target, mix=1.0)`
  (ik.nim:84-102).
- `solveTwoBoneIk(origin, parentLength, childLength, parentRotation,
  childRotation, target, bendSign=1.0, mix=1.0)` (ik.nim:105-152).
- `solveChainIk(points, lengths, target, mix=1.0)` (ik.nim:155-243, FABRIK).
- `requireMix(value)` (ik.nim:49-52): finite and within **[0,1]**, else
  `schemaViolation`. Matches the `position/translateMix/rotateMix` [0,1] schema
  constraint and `pathConstraintData`'s validation — the IK `mix` field must be
  modeled the same way.

**Bones → solver-inputs mapping.** Origins, lengths, and current rotations are
derived from `BoneData`/`LocalTransform` at solve time — they are *not* stored on
the constraint. What the **constraint record** must persist:
- the constrained **bone(s)** (one for one-bone, parent+child for two-bone, an
  ordered chain for chain IK) — by stable bone name, like `path.bone`;
- the **target** bone (reuse `target` key 4000, string);
- the **mix** blend weight in [0,1] (new property key, `f32`, default per design —
  Spine convention is `mix=1.0`);
- the **bend direction** for two-bone solves (`bendSign` ±1 → a small int/varint
  or bool "bendPositive"); chain/one-bone ignore it;
- an **order** (reuse `order` key 4002, varint) for world-transform sequencing,
  like every other constraint.

The exact property set, spellings, defaults, and required/defaulted partition are
**frozen by bony-b5d.2**; this note establishes the grounded inputs for that
decision. No JSON key or Nim field spelling is committed here.

---

## 5. Quick reference for downstream beads

| Need | Value | Source |
|------|-------|--------|
| Milestone band | M5 = 4000-4999 | wire.yml:64-67 |
| Next-free type key | **4002** | wire.yml (path=4000, pathAttachment=4001) |
| Next-free property key | **4014+** | wire.yml (rotateMix=4013 is last) |
| Reuse: name | key 1, string | wire.yml:345-351 |
| Reuse: target | key 4000, string | wire.yml:478-484 |
| Reuse: order | key 4002, varint | wire.yml:492-498 |
| Packed-bytes precedent | blendAxes key 6041, bytes | wire.yml:716-722 |
| Model mirror | PathConstraintData | model.nim:77-88, 281-312 |
| Skeleton field convention | `paths: seq[...]` (short plural) | model.nim:188 |
| ckIk already defined, sorts first | enum + rank 0 | model.nim:33, 628 |
| f32 validation | quantizeF32 | model.nim:206-211 |
| mix [0,1] validation | requireMix / schema min0max1 | ik.nim:49, generate.py:891 |
| Coverage rule | each prop in defaults OR required, exactly once | defaults.yml:65; generate.py:261 |
| Mandatory gate | `generate.py --check` + unittest discover | registry/README.md:95,97 |
