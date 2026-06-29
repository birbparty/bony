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
| `bones` | **required** | — | **NEW 4014** | **bytes** | packed list — see §3; authored-JSON shape = non-empty array of strings **only via a codegen override (see §7-C2)** |
| `target` | **required** | — | reuse `target` = **4000** | string | the target bone name |
| `order` | optional | `0` | reuse `order` = **4002** | varint | world-transform sequencing slot |
| `mix` | optional | `1.0` | **NEW 4015** | f32 | range **[0,1]** — runtime-enforced (`requireMix`, ik.nim:49); the JSON-schema `minimum:0, maximum:1` requires a codegen edit (see §7-C1) |
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
- **Authored-JSON shape:** a **non-empty array of strings** (bone names), chain
  order from root to tip — items `{type: string, minLength: 1}`, `minItems: 1`
  (mirroring `keyformBlend.axes`, generate.py:641-645).
- **IMPORTANT — this array shape is NOT auto-derived.** A `bytes` property
  auto-generates to `{"type":"string","contentEncoding":"base64"}`
  (`schema_for_backing_type`, generate.py:868); `blendAxes` only renders as an
  array because `canonical_json_overrides["keyformBlend"]` hand-replaces it. So the
  authored array shape above requires the codegen override in §7-C2, without which
  `bones` would ship as a lone base64 string (the canonical schema today has **zero**
  `contentEncoding` fields). The wire schema legitimately keeps `bones` as base64.
- This encoding is frozen permanently; later changes may only append, never
  renumber or repack.

---

## 4. `bendPositive` semantics

- Permitted in the schema for **ALL** IK constraints (any bone count).
- **Loaded and then ignored** for 1-bone and ≥3-bone constraints — only
  `solveTwoBoneIk` consumes a bend direction (`bendSign`, ik.nim:110; neither
  `solveOneBoneIk` nor `solveChainIk` takes it).
- Mapping: `bendPositive == true` → `bendSign = +1.0`; `false` → `-1.0`
  *(derived disambiguation, not literally mandated by bony-b5d.2; grounded in
  `solveTwoBoneIk`'s `bendSign` default of `1.0`, ik.nim:110, matching the
  `bendPositive` default `true`)*.

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

## 6. Downstream bead checklist (advisory — §1-§5 are the binding contract)

*This section is forward guidance for the implementation beads, not part of the
frozen format contract. Treat §1-§5 (and §7) as binding; §6 as the checklist that
realizes them.*

- **bony-b5d.3** (registry + defaults + codegen + regen, atomic single merge):
  add `ikConstraint` typeKey 4002; property keys `bones`=4014/bytes,
  `mix`=4015/f32, `bendPositive`=4016/bool; object `- type: ikConstraint` with
  ordered properties `[name, bones, target, order, mix, bendPositive]`;
  defaults.yml objectDefaults (`order=0`, `mix=1.0`, `bendPositive=true`) +
  requiredProperties `[bones, name, target]`; **plus the two codegen edits in §7**;
  regenerate all four artifacts; `make test` / `generate.py --check` green. (One
  bead because validate_sources cross-checks registry↔defaults and `--check` would
  fail on a half-change.)
- **bony-b5d.7** (model.nim): `IkConstraintData` (name, bones: seq[string],
  target, order, mix, bendPositive + has-flags as the path precedent uses),
  `SkeletonData` field **`ikConstraints: seq[IkConstraintData]`** (full plural to
  match the JSON collection key §1, paralleling `paths: seq[PathConstraintData]`
  at model.nim:188), and an `ikConstraintData*` constructor mirroring
  `pathConstraintData*` (model.nim:281) with `mix` validated to [0,1] via the
  quantize/require pattern.

---

## 7. Required codegen edits in `generate.py` (binding — beyond registry/defaults)

These two edits are part of the binding contract: the registry+defaults edits
alone produce a schema that **contradicts** §2/§3. Both belong to bony-b5d.3.

- **C1 — `mix` JSON-schema range (wire schema).** `schema_for_property`
  (generate.py:875-894) only attaches `minimum:0`/`maximum:1` for `property_id in
  {"position", "translateMix", "rotateMix"}` (generate.py:891). A new id `mix` would
  otherwise emit a rangeless `{"type":"number"}`. **Add `"mix"` to that set** so the
  *wire* schema matches §2. (This is a *separate* mechanism from the runtime
  `requireMix` [0,1] guard at ik.nim:49 / the model constructor — the runtime check
  does NOT make the schema edit unnecessary; both are required.) This gap is silent:
  regen stays green and `--check` passes while the schema diverges, unless a
  conformance test asserts the `mix` range.
- **C2 — `bones` authored-JSON array.** A `bytes` property auto-generates to
  base64 (generate.py:868); the array-of-strings shape in §3 exists only via an
  override. **Add a `canonical_json_overrides["ikConstraint"]` entry** (mirroring
  `keyformBlend`, generate.py:637-653) that re-declares the authored `ikConstraint`
  object with `bones: {type: array, minItems: 1, items: {type: string, minLength:
  1}}` plus the other five fields. Without it `bones` ships as the only base64
  field in `bony.schema.json`, contradicting §3 and the `bones: seq[string]` model.
- **C1↔C2 interaction — the override must ALSO carry the `mix` range.** Because
  `generate_schema` does `schema["$defs"].update(canonical_json_overrides())`
  (generate.py:449), the C2 override **fully replaces** the authored `ikConstraint`
  `$def` — so C1's `schema_for_property` edit reaches only the *wire* schema, not
  `bony.schema.json`. The C2 override must therefore itself declare
  `mix: {type: number, minimum: 0, maximum: 1, default: 1.0}` (and the other field
  ranges/defaults it wants), or the authored schema lacks the `mix` range despite
  C1. Precedent to NOT blindly copy: `rotationDeformer.opacity` (generate.py:633) is
  `{type: number, default: 1.0}` with no min/max even though its field is 0..1 — an
  override that silently drops a range. Set the range in **both** C1 (wire) and the
  C2 override (authored).
- **Optional (S1):** `bones` does *not* strictly need a `PACKED_BYTES_METADATA`
  entry (generate.py:26) to match the `blendAxes` precedent — `blendAxes` itself is
  not listed there. Add `PACKED_BYTES_METADATA["bones"]` only if the team wants the
  *wire* schema to self-document the varuint-count+indices packing; record that as a
  conscious choice, not an oversight.
