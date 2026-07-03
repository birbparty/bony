# Deform Timeline Format — Analysis Note

Analysis beads: **bony-68lj.1 / .2 / .3** (epic **bony-68lj**, prompt 23 of the M4
deform-timeline milestone). Read-and-document only — no source was edited. Every
fact below is grounded against the files cited (line numbers as of this commit).
This note is the source material for the downstream contract/registry/codegen
beads:

- **bony-68lj.4** — resolve the deform packed-payload key fork (Option R reuse
  `timelineKeys` 2004 vs Option N mint `deformKeys`=3009 bytes). Reads §2, §3.
- **bony-68lj.5** — write `docs/deform-timeline-contract.md`. Reads §1, §3, §4.
- **bony-68lj.7** — edit `registry/wire.yml` (M4 band). Reads §2.

Agents run fresh with no shared memory; this file is the hand-off.

> **Scope reminder (prompt 23 = contract + schema/registry/codegen ONLY).** No
> runtime loader, no `AnimationClip`/mixer/`buildDrawBatches` wiring (prompt 24),
> no conformance rig/golden (prompt 25), no Dart runtime logic beyond regenerated
> `wire.dart` (prompt 26), no round-trip test. Confirmed corollary: adding a
> `deformTimeline` typeKey with **no decode path** is legal in this slice (see §2.4).

---

## 1. The project-owned deform types (the serialized shape)

Source: `runtime-nim/src/bony/mesh/deform.nim`. The deform machinery already
exists standalone in the runtime; it is **not** yet wired into `AnimationClip`
(that is prompt-24 territory, confirmed in §1.4).

### 1.1 `MeshDelta` — deform.nim:8-10
```nim
MeshDelta* = object
  x*: float64
  y*: float64
```
Fields in order: `x: float64`, `y: float64`. Constructor `meshDelta` (deform.nim:26)
quantizes both through `quantizeF32` — the **stored Nim type is float64 but the
value is float32-precision**, so the wire encoding is f32 (mirror the timeline
`writeF32To` precedent, §3).

### 1.2 `DeformKeyframe` — deform.nim:12-16
```nim
DeformKeyframe* = object
  time*: float64
  offset*: uint32
  deltas*: seq[MeshDelta]
  curve*: TimelineCurve
```
Fields in order: `time: float64` (f32-quantized), `offset: uint32`, `deltas:
seq[MeshDelta]`, `curve: TimelineCurve`. `offset` is the first vertex index the
delta run applies to (sparse runs allowed); `deltas.len` is the run length. The
`curve` is the **same `TimelineCurve`** used by bone/slot timelines — reuse its
existing wire encoding verbatim (§3).

### 1.3 `DeformTimeline` — deform.nim:18-23
```nim
DeformTimeline* = object
  skin*: string
  slot*: string
  attachment*: string
  vertexCount*: int
  keys*: seq[DeformKeyframe]
```
Fields in order: `skin: string`, `slot: string`, `attachment: string`,
`vertexCount: int`, `keys: seq[DeformKeyframe]`.

> **NAMING FORK — record both, they differ deliberately.** The runtime
> keyframe-list field is **`keys`** (deform.nim:23), CONFIRMED (not `keyframes`).
> The readable canonical JSON for the prompt-23 contract will expose it as
> **`keyframes`** (the human-facing name). Downstream schema/codegen (bony-68lj.5,
> .10, .11) must map wire/runtime `keys` ↔ canonical-JSON `keyframes`. `vertexCount`
> is a plain `int`, not a fixed-width uint — encode as `varuint`.

### 1.4 Validation — `validateDeformTimeline` (deform.nim:66-80, exported)
The contract's required/non-empty rules are already enforced in code; mirror them
in `spec/defaults.yml` `requiredProperties`:
1. `skin` must be non-empty (deform.nim:67-68) — `"deform timeline skin must not be empty"`.
2. `slot` must be non-empty (69-70).
3. `attachment` must be non-empty (71-72).
4. `vertexCount > 0` (73-74) — `"deform timeline vertex count must be positive"`.
5. `keys.len >= 1` (75-76) — at least one keyframe.
6. key times **strictly increasing** (77-80): `keys[i-1].time >= keys[i].time` → error.

Per-key, `validateDeformKey` (deform.nim:53-63, private):
- `time >= 0` after quantization (55-56).
- `deltas.len >= 1` (57-58).
- `int(offset) + deltas.len <= vertexCount` (59-60) — the delta run must fit the mesh.

All raise `newBonyLoadError(schemaViolation, ...)`.

### 1.5 Mesh dependency — `MeshAttachment.deformAttachment`
Source: `runtime-nim/src/bony/model.nim:109-120`. CONFIRMED field
`deformAttachment*: string` at **model.nim:120**. A `DeformTimeline.attachment`
resolves against this. Full `MeshAttachment` field order: `name, path, uvs,
triangles, vertices, weighted, hull, edges, parentMesh, inheritDeform,
deformAttachment`.

- Default behavior (raw ctor `meshAttachmentData`, model.nim:465-490): when
  `deformAttachment` is empty it **defaults to `name`** (model.nim:489) — the
  effective stored value is never `""`.
- Threading (`runtime-nim/src/bony/mesh/attachments.nim`): `meshAttachment*`
  (46-68) and `weightedMeshAttachment*` (84-97) take a `deformAttachment = ""`
  param and forward it; `unweightedMeshAttachment*` (71-81) omits it (→ defaults to
  `name`).
- `deformTimeline*` ctor (deform.nim:83) sets `attachment: mesh.deformAttachment`
  and `vertexCount: mesh.vertices.len`, then validates. `applyDeformTimeline`
  (deform.nim:156) asserts `mesh.deformAttachment == timeline.attachment`
  (deform.nim:162) — the deform's `attachment` is the *deform key*, not the raw
  attachment name.

### 1.6 `AnimationClip` has **no** deform field yet (prompt-24 boundary)
Source: `runtime-nim/src/bony/anim/timelines.nim:137-142`.
```nim
AnimationClip* = object
  name: string
  duration: float64
  boneTimelines: seq[BoneTimeline]
  slotTimelines: seq[SlotTimeline]
  eventTimelines: seq[EventTimeline]
```
CONFIRMED present: `boneTimelines`, `slotTimelines`, `eventTimelines` (getters at
timelines.nim:178-180). CONFIRMED ABSENT: no `deformTimelines` field, no getter,
no `deform` import, and the `animationClip*` ctor (578-623) takes only the three
timeline seqs. Adding `deformTimelines` to the clip aggregate is **prompt 24**, not
this slice. For prompt 23 the registry may add a *doc-only* note that
`animationClip` will later own `deformTimeline` children (bony-68lj.8), but no
`deformTimelines` property is wired.

---

## 2. Registry state — next-free keys, templates, and the sync-check probe

Source: `registry/wire.yml` (1296 lines). M4 band = 3000-3999.

### 2.1 Next-free TYPE key (M4)
- In use: `clippingAttachment`=3000 (wire.yml:230), `meshAttachment`=3001 (236).
  Next declared typeKey jumps to `path`=4000.
- **Next-free typeKey = 3002** (3002-3010 all free). Assign to the new
  `deformTimeline` object.

### 2.2 Next-free PROPERTY keys (M4)
In use in the 3000 band:

| key  | id            | backingType |
|------|---------------|-------------|
| 3000 | vertices      | bytes  |
| 3001 | untilSlot     | string |
| 3002 | meshWeighted  | bool   |
| 3003 | meshVertices  | bytes  |
| 3004 | meshUvs       | bytes  |
| 3005 | meshTriangles | bytes  |

- **Next-free propertyKey = 3006** (3006/3007/3008/3009/3010 free). bony-68lj.7
  mints `deformSkin`/`deformAttachment`/`deformVertexCount` from 3006 upward; the
  packed-payload key fork (bony-68lj.4) decides whether a `deformKeys`=3009 bytes
  key is also minted (Option N) or `timelineKeys`=2004 is reused (Option R).

### 2.3 Templates (verbatim anchors to copy)
- **`slotTimeline` typeKey entry** (wire.yml:319-324): `key: 2002`, `milestone: M3`,
  `status: active`, doc `"Slot animation timeline child record owned by the most
  recent animationClip."`
- **`slotTimeline` objects entry** (wire.yml:1241-1246): ordered props
  `[slotIndex, slotTimelineKind, timelineKeys]`.
- **`boneTimeline` objects entry** (wire.yml:1235-1240): ordered props
  `[boneIndex, boneTimelineKind, timelineKeys]`.
- **`animationClip` objects entry** (wire.yml:1231-1234): props `[name]`, doc
  `"Animation clip parent record; followed immediately by owned boneTimeline and
  slotTimeline records."`
  - ⚠ **Discrepancy to preserve, not "fix":** the animationClip **typeKey** entry
    doc (wire.yml:312) omits "immediately" (`"...followed by owned boneTimeline and
    slotTimeline records."`). The two docs are intentionally worded differently;
    when bony-68lj.8 updates the child-family doc, match the *objects-entry*
    style (with "immediately") and do not touch the typeKey-entry doc unless the
    bead says so.
- **Generic timeline keys:** `slotIndex`=2002 varuint (wire.yml:914-920),
  `timelineKeys`=2004 bytes (928-934, doc points at
  `docs/binary-animation-state-machine-object-families.md`). Sibling context:
  `boneIndex`=2000, `boneTimelineKind`=2001, `slotTimelineKind`=2003.
- **String-table bytes precedent** — `bones`=4014 bytes (wire.yml:648-654): packed
  as `varuint count` then `count × (varuint string-table index)`. This is the
  template for a packed list of string references. The `string` backingType
  (code 5, wire.yml:109-111) uses the same "read varuint string-table index"
  indirection — strings are never inline, always a string-table index. If the
  deform packed layout references the skin/attachment inside the blob, use this
  index mechanism; but note skin/slot/attachment are better modeled as top-level
  `string` properties (§1.3), reserving the packed blob for the keyframe array.

### 2.4 Sync-check probe — will typeKey 3002 with NO decode path break `make test`?
**A change-detector exists and WILL trip; the decode-less typeKey itself is
tolerated.** Two distinct effects:

**(a) Change-detector counts — MUST be updated (bony-68lj.15).**
`runtime-nim/tests/test_smoke.nim:107-115` hard-asserts the *generated* registry
totals:
```nim
bonyTypeKeys.len == 28
bonyPropertyKeys.len == 101
bonyPropertyDefaults.len == 55
bonyRequiredProperties.len == 74
```
Adding `deformTimeline` typeKey → `bonyTypeKeys.len` becomes **29**; each new
propertyKey bumps `bonyPropertyKeys.len` past 101; each defaults/required entry
bumps 55/74. **These four literals must be updated to the regenerated totals or
`make test` (step `test_smoke.nim`) fails.** This is the concrete gate, not an
optional cleanup.

**(b) codegen `--check` gate — sources and generated must land together.**
`Makefile:22-23` (`make test`) runs `python3 codegen/generate.py --check` first;
it diffs `registry/wire.yml` against `runtime-nim/src/bony/generated/wire.nim`
(and the two schemas + `wire.dart`). Editing `wire.yml` **without** regenerating
all four artifacts fails immediately. → registry edit + defaults + regen are one
atomic landing (bony-68lj.13). Full gate order: codegen --check → codegen
unittests → `nim check` → test_smoke → physics → cli-pose → ik → byte-stability →
fuzz → json idempotency.

**(c) A decode-less typeKey is otherwise SAFE.** The hand-written `*TypeKey`
constants in `binary/semantic.nim` (16-37, 117-122; e.g. `meshAttachmentTypeKey =
3001'u64`) are **not** cross-checked against the generated table by any test — the
mapping is manual, so no assertion fires for the missing `deformTimelineTypeKey`.
Both decode dispatches (`decodeSkeletonObjects` case at semantic.nim:1464;
`decodeAnimationObjects` case at 1802) have a tolerant `else: discard`
(1748-1750, 1831-1832) — an undecoded registered typeKey is silently dropped, no
exhaustiveness requirement over `uint64`. The binary read path
(`framing.readObjectStream`:403-415) skips unknown typeKeys via
`skipObjectProperties`.

**(d) The one fail-hard path does NOT apply to 3002.**
`semantic.readKnownObjectStream` (2060-2061) raises on typeKeys that are **not**
in the registry (`.bnb JSON conversion cannot preserve unknown object type`).
Once 3002 is in the regenerated registry, `isKnownTypeKey(3002)` is true, so this
guard passes. It would only fire if a fixture contained a typeKey absent from the
registry — not our case. (Exercised by `test_json_bnb_json_idempotency.nim`,
Makefile step last.) **Caveat:** this only stays green if no existing fixture
contains a 3002 record with property shapes codegen can't round-trip; since no
asset uses deform yet (bony-68lj.16 verifies via
`scripts/ci/schema_validate_assets.py`), the slice is safe.

---

## 3. The curve tail — reuse verbatim, do NOT invent a second encoding

Source: `runtime-nim/src/bony/binary/semantic.nim`. The deform packed layout MUST
call the existing `writeCurve`/`readCurve` procs; the encoding is:

### 3.1 Tag discrimination (semantic.nim:690-694)
```nim
proc curveTag(curve: TimelineCurve): uint64 =
  case curve.kind
  of linearCurve: 0
  of steppedCurve: 1
  of bezierCurve: 2
```
Enum order `linearCurve=0, steppedCurve=1, bezierCurve=2` (timelines.nim:8-11).
Tag is a **varuint**; values 0/1/2 each encode as a **single byte** `0x00`/`0x01`/
`0x02` (minimal-encoding enforced on read, framing.nim:99).

### 3.2 Write (semantic.nim:712-718)
```nim
proc writeCurve(result: var seq[byte]; curve: TimelineCurve) =
  result.writeVaruint(curve.curveTag)
  if curve.kind == bezierCurve:
    result.writeF32To(curve.c1x)
    result.writeF32To(curve.c1y)
    result.writeF32To(curve.c2x)
    result.writeF32To(curve.c2y)
```
`writeF32To` → `writeF32Payload` (semantic.nim:197-203): IEEE-754 **32-bit float,
4 bytes, little-endian** (LSB first), value first pushed through `quantizeF32`.

### 3.3 Read (semantic.nim:697-722) mirrors write exactly
Read varuint tag → tag 0 = `linearTimelineCurve` (no payload), tag 1 =
`steppedTimelineCurve` (no payload), tag 2 = read 4 f32 in order `c1x, c1y, c2x,
c2y` via `bezierTimelineCurve(...)`. Any tag ≥ 3 → `schemaViolation` (`".bnb <ctx>
curve kind is invalid"`).

### 3.4 Precise on-wire tail per kind (the normative bytes)
| kind    | bytes | layout |
|---------|-------|--------|
| linear  | 1  | `0x00` |
| stepped | 1  | `0x01` |
| bezier  | 17 | `0x02` + f32 c1x + f32 c1y + f32 c2x + f32 c2y (LE, 4B each) |

Note `TimelineCurve` fields are float64 in memory but **f32 on the wire**
(quantized), and the object's fields are non-exported (accessed via getters
`kind`/`c1x`/`c1y`/`c2x`/`c2y`, timelines.nim:148-152). Exported curve constants:
`linearTimelineCurve`, `steppedTimelineCurve` (timelines.nim:145-146),
`bezierTimelineCurve(c1x,c1y,c2x,c2y)` (validates c1x/c2x ∈ [0,1]).

### 3.5 How the tail sits inside a timeline-key payload (context for the packed layout)
In `writeTimelineKeys` (semantic.nim:787-852) each keyframe writes its scalar
fields first (all f32: `time`, then value/vector/color components), then the curve
tail as the trailing element (one `writeCurve` for scalar timelines, two for
bone vector timelines `curveX`/`curveY`). Read side asserts `index == payload.len`
at the end (855-893) — **no trailing bytes allowed**. The deform packed keyframe
should follow the same shape: fixed scalar prefix (`time` f32, `offset` varuint,
delta count + deltas), then the reused curve tail, and the whole blob length-framed
so the reader can assert full consumption.

---

## 4. Quick reference for downstream beads

| Need | Value | Source |
|------|-------|--------|
| Milestone band | M4 = 3000-3999 | wire.yml |
| Next-free type key | **3002** | wire.yml (clipping=3000, mesh=3001) |
| Next-free property key | **3006+** | wire.yml (meshTriangles=3005 last) |
| Runtime keyframe field name | **`keys`** (JSON exposes `keyframes`) | deform.nim:23 |
| DeformTimeline field order | skin, slot, attachment, vertexCount, keys | deform.nim:18-23 |
| DeformKeyframe field order | time, offset, deltas, curve | deform.nim:12-16 |
| MeshDelta | x, y (f32-quantized float64) | deform.nim:8-10 |
| Required (non-empty) | skin, slot, attachment; vertexCount>0; ≥1 key | deform.nim:66-80 |
| Mesh dep field | `deformAttachment: string` | model.nim:120 |
| AnimationClip has deform? | **NO** (prompt-24) | timelines.nim:137-142 |
| Curve tail reuse | `writeCurve`/`readCurve` verbatim | semantic.nim:712-722 |
| Curve tag | varuint 0/1/2; bezier +4×f32 LE c1x,c1y,c2x,c2y | semantic.nim:690-718 |
| timelineKeys (Option R) | key 2004, bytes | wire.yml:928-934 |
| String-table packed-list precedent | `bones` 4014 bytes | wire.yml:648-654 |
| Change-detector counts to bump | typeKeys 28→29, props 101→, defaults 55, req 74 | test_smoke.nim:112-115 |
| Codegen gate | `generate.py --check` (4 artifacts) | Makefile:22-23 |
| Decode-less typeKey tolerated? | YES (else: discard, skip unknown) | semantic.nim:1748,1831; framing.nim:412 |
| Mandatory full gate | `make test` | Makefile:22-32 |

No JSON key or Nim wire spelling is *committed* here — those are frozen by
bony-68lj.4 (packed-key fork) and bony-68lj.5 (contract doc). This note establishes
the grounded inputs for those decisions.
