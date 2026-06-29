# IK Constraint Format — FROZEN (source of truth)

Freeze bead: **bony-b5d.2** (epic bony-b5d). This file is the **authoritative,
append-only** record of the IK constraint wire/JSON format. Steps 2–3 and every
downstream bead (bony-b5d.3 registry+defaults+codegen, bony-b5d.7 model) MUST
match this exactly. Grounding for these decisions: `.agents/notes/ik-format-analysis-note.md`.

**Decision-record only — no registry/defaults/codegen/model source was edited in
this bead.** Key/field spellings below are frozen here; the implementation beads
realize them.

---

## 1. Object + top-level collection

- **Registry object id:** `ikConstraint`, **type key = 4002** (next-free M5 type
  key; M5 typeKeys in use are `path`=4000, `pathAttachment`=4001 —
  wire.yml:229-240).
- **Top-level JSON array key:** `ikConstraints`. This is **auto-derived** as
  `object_id + "s"` (`ikConstraint` → `ikConstraints`) at
  `codegen/generate.py:480` (`collection_id = root_collection_overrides.get(object_id, object_id + "s")`).
  **Do NOT add a `root_collection_overrides` entry** — the regular plural is exactly
  the desired key, unlike `animationClip`→`animations` / `stateMachine`→`stateMachines`.

---

## 2. Fields (FROZEN names, casing, keys, backing types, defaults)

| field | required? | default | property key | backingType | notes |
|-------|-----------|---------|--------------|-------------|-------|
| `name` | **required** | — | reuse `name` = **1** | string | `minLength: 1` (schema_for_property name rule, generate.py:879) |
| `bones` | **required** | — | **NEW 4014** | **bytes** | packed list — see §3; JSON shape = non-empty array of strings |
| `target` | **required** | — | reuse `target` = **4000** | string | the target bone name |
| `order` | optional | `0` | reuse `order` = **4002** | varint | world-transform sequencing slot |
| `mix` | optional | `1.0` | **NEW 4015** | f32 | range **[0,1]** (schema `minimum:0, maximum:1`; runtime `requireMix`, ik.nim:49) |
| `bendPositive` | optional | `true` | **NEW 4016** | bool | elbow bend direction; see §4 |

- **New property keys minted (append-only, M5 band):** `bones`=4014, `mix`=4015,
  `bendPositive`=4016. Highest prior M5 property key was `rotateMix`=4013.
- **Reused property keys (same key, same backingType):** `name`=1 (string),
  `target`=4000 (string), `order`=4002 (varint).
- **`requiredProperties` = `[bones, name, target]`.** The other three
  (`order`, `mix`, `bendPositive`) live in `objectDefaults` with the defaults
  above. (Coverage rule: every property appears in exactly one of
  `objectDefaults` / `requiredProperties` — defaults.yml:65, validate_sources
  generate.py:261-309.)

### Deliberately NOT carried over from `path`
`bone` (singular), `path`, `position`, `translateMix`, `rotateMix`. IK uses a
**plural packed `bones` list** instead of path's singular `bone` (key 1012), so
key 1012 is **not** reused here.

---

## 3. `bones` wire encoding — CENTRAL FREEZE (append-only for the format's lifetime)

- **backingType `bytes`**, packed as: **`varuint count` followed by
  `count × (varuint string-table index)`** — one string-table index per bone name,
  in chain order. This is exactly the **`blendAxes` precedent** (key 6041, bytes,
  wire.yml:716-722: "varuint count followed by count*(varuint string-table index)").
- **JSON shape:** a **non-empty array of strings** (bone names), chain order from
  root to tip.
- This encoding is frozen permanently; later changes may only append, never
  renumber or repack.

---

## 4. `bendPositive` semantics

- Permitted in the schema for **ALL** IK constraints (any bone count).
- **Loaded and then ignored** for 1-bone and ≥3-bone constraints — only
  `solveTwoBoneIk` consumes a bend direction (`bendSign`, ik.nim:110; neither
  `solveOneBoneIk` nor `solveChainIk` takes it).
- Mapping: `bendPositive == true` → `bendSign = +1.0`; `false` → `-1.0`.

---

## 5. `bones` → solver-inputs mapping (FROZEN)

Chain points are **rest-pose world origins**, computed at runtime — never stored
(`BoneData` has only `name`/`parent`/`local`, no world position or segment length,
model.nim:51-54):

- **points** = each bone's rest-pose world origin, in chain order,
  **`++ [target bone rest-pose world origin]`**.
  ⇒ `#points = #bones + 1`.
- **lengths** = distances between consecutive points ⇒ `#lengths = #bones`.
  Rest-pose-derived at runtime, **never persisted**.

### Solver selection by bone count
| `#bones` | solver | bend dir |
|----------|--------|----------|
| 1 | `solveOneBoneIk` (ik.nim:84) | n/a (bendPositive ignored) |
| 2 | `solveTwoBoneIk` (ik.nim:105) | uses `bendPositive`→`bendSign` |
| ≥3 | `solveChainIk` (ik.nim:155, FABRIK) | n/a (bendPositive ignored) |

`mix` (default 1.0, [0,1]) is passed to every solver as the blend weight.

---

## 6. Downstream bead checklist (what must match this freeze)

- **bony-b5d.3** (registry + defaults + codegen + regen, atomic single merge):
  add `ikConstraint` typeKey 4002; property keys `bones`=4014/bytes,
  `mix`=4015/f32, `bendPositive`=4016/bool; object `- type: ikConstraint` with
  ordered properties `[name, bones, target, order, mix, bendPositive]`;
  defaults.yml objectDefaults (`order=0`, `mix=1.0`, `bendPositive=true`) +
  requiredProperties `[bones, name, target]`; regenerate all four artifacts;
  `make test` / `generate.py --check` green. (One bead because validate_sources
  cross-checks registry↔defaults and `--check` would fail on a half-change.)
- **bony-b5d.7** (model.nim): `IkConstraintData` (name, bones: seq[string],
  target, order, mix, bendPositive + has-flags as the path precedent uses),
  `SkeletonData` field following the short-plural convention used by
  `paths: seq[PathConstraintData]` (model.nim:188), and an `ikConstraintData*`
  constructor mirroring `pathConstraintData*` (model.nim:281) with `mix` validated
  to [0,1] via the quantize/require pattern.
