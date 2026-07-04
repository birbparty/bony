# Event-Timeline Contract — Grounding Findings (bony-0ofc.1)

Grounding pass for the M3 animation-clip **event-timeline** format slice
(epic `bony-0ofc`, prompt `27-contract-event-timeline-format.md`). Every value
below was verified against the actual source on `main` at iteration 199 — line
numbers may drift, but the facts are confirmed. Downstream authoring tasks
(`bony-0ofc.2` contract doc, `bony-0ofc.3` registry edit, prompts 28–30) MUST
consume these findings and NOT re-derive them from the prose in prompt 27, which
contains two field-type inaccuracies corrected here.

## (1) Registry key allocation — CONFIRMED

- **Next-free M3 typeKey = `2003`.** Existing M3 typeKeys: `animationClip 2000`
  (`registry/wire.yml` ~:314), `boneTimeline 2001` (~:320), `slotTimeline 2002`
  (~:326). No typeKey uses `2003`. (Note: the literal string `2003` appears once
  in `wire.yml` at the `slotTimelineKind` **propertyKey** ~:956 — a different key
  space, not a collision.)
- **Next-free M3 propertyKey = `2005`.** Existing M3 propertyKeys: `boneIndex 2000`,
  `boneTimelineKind 2001`, `slotIndex 2002`, `slotTimelineKind 2003`,
  `timelineKeys 2004` (`wire.yml` ~:935–963). No propertyKey uses `2005`.
- **No literal "next-free" marker exists** in `wire.yml` or `registry/key-ranges.md`.
  These values are the highest-used + 1, inferred — not read from an explicit
  marker. `key-ranges.md` ~:21 confirms the M3 band `2000..2999` = "Animations,
  timelines, curves, mixing".
- **objects-block template** (for the new `eventTimeline` objects entry) is the
  `deformTimeline` block at `wire.yml` ~:1281–1288:
  ```yaml
  - type: deformTimeline
    properties:
      - deformSkin
      - slot
      - deformAttachment
      - deformVertexCount
      - deformKeys
    doc: Deform timeline child record owned by the most recent animationClip; ...
  ```
  Shape = `- type:` + `properties:` (propertyKey id-names) + `doc:`. The
  `animationClip` objects doc line (~:1268) should be extended to mention the
  owned `eventTimeline` records.

## (2) volume / balance bounds — CONFIRMED "carried verbatim" (with a type correction)

- **CORRECTION to prompt 27:** the Nim source declares `volume` and `balance` as
  **`float64`**, not `float32`. (Prompt 27 already had `floatValue` right as
  `f64/f32-quantized`; only `volume`/`balance` were mis-labeled `f32` there.)
  `EventData` (`timelines.nim` ~:99–106):
  ```nim
  EventData* = object
    name*: string
    intValue*: int32
    floatValue*: float64   # prompt 27: "f64/f32-quantized" — matches source
    stringValue*: string
    audioPath*: string
    volume*: float64       # prompt 27 said "f32" — actually f64 declared
    balance*: float64      # prompt 27 said "f32" — actually f64 declared
  ```
- **They are f32-quantized at construction**, not range-clamped. The `eventData`
  ctor (`timelines.nim` ~:471–479) applies `quantizeF32(..., "event.volume")`,
  `quantizeF32(..., "event.balance")`, `quantizeF32(..., "event.float")`.
  `validateEventData` (~:256–260) only re-quantizes as a round-trip check — no
  bounds.
- **No `0..1` / `-1..1` clamp anywhere.** `quantizeChannel` (~:221–224) does
  enforce `0..1` but is used for **colors only** (~:346–358), never events.
  `clamp01` (`mixer.nim` ~:95) applies only to track alpha/mix thresholds
  (~:130–134) and final weight (~:460), never event fields. Dispatch copies the
  event verbatim (`mixer.nim` ~:217, :224 `event: key.event`; :231–232 append).
- **Contract decision:** edge-case (e) documents `volume`/`balance`/`floatValue`
  as **carried verbatim modulo f32 quantization** — invents no clamp. The declared
  type is `float64` but effective precision is `f32` (quantized on construction),
  and cross-runtime compare tolerance is `1e-4` per `docs/float-math-contract.md`.
- **WIRE WIDTH (packed layout — do NOT emit f64):** `floatValue`, `volume`, and
  `balance` each pack on the `.bnb` wire as a **4-byte little-endian IEEE-754 f32**,
  NOT 8-byte f64. The `float64` above is an in-memory runtime type only; every
  value is `quantizeF32`'d on construction, so 4-byte f32 on the wire is lossless
  and required for parity. This mirrors how every other timeline float payload is
  written — `writeF32To` → `writeF32Payload` (`binary/semantic.nim` ~:678–679, :203)
  — and matches the deform packed layout (`docs/deform-timeline-contract.md`
  "Packed deformTimeline byte layout"). The packed-layout author (prompt 28) MUST
  pin `floatValue`/`volume`/`balance` = f32, alongside `intValue` = svarint (§3).

## (3) intValue encoding — CONFIRMED svarint (zigzag LEB128), not fixed i32

- `EventData.intValue` is **`int32`** (`timelines.nim` ~:101). CONFIRMED.
- bony writes signed integers as a **zigzag signed varint (LEB128)**, NOT a fixed
  4-byte i32. `writeVarintPayload` (`binary/semantic.nim` ~:262–263) delegates to
  `writeVarint` (`binary/framing.nim` ~:103–105):
  ```nim
  proc writeVarint*(output: var seq[byte]; value: int64) =
    let encoded = (uint64(value) shl 1) xor uint64(value shr 63)  # zigzag
    output.writeVaruint(encoded)
  ```
  "svarint" (protobuf `sint`) == this zigzag encoding. Decoders reverse it via
  `readVarint` (`framing.nim` ~:111–118).
- **Contract decision:** the packed `eventTimeline` layout pins `intValue = svarint`
  (zigzag signed LEB128), consistent with how bony encodes every other signed int.
  Do NOT specify a fixed i32.
- **Caveat (see §5-note):** `EventData` is currently **entirely non-serialized** —
  no code under `runtime-nim/src/bony/binary/` references `event`/`EventData`/
  `intValue`/`volume`/`balance`. `writeVarintPayload` is the generic integer-property
  encoder; it is not yet wired to event intValue. This slice **mints** the packed
  layout; the loader wiring is prompt 28.

## (4) animationClip JSON $defs injection path — CONFIRMED inline block

- The per-clip timeline arrays are injected **inline inside the `animationClip`
  object literal** returned by `canonical_json_overrides()`
  (`codegen/generate.py`, fn ~:595; block ~:792–814), NOT via a standalone
  per-record `$def`:
  ```python
  "animationClip": {
      "type": "object",
      "additionalProperties": False,        # ~:794 — new keys MUST be added here
      "properties": {
          "name": named_string,
          "boneTimelines": {"type": "array", "items": {"$ref": "#/$defs/boneTimeline"}, "default": []},
          "slotTimelines": {"type": "array", "items": {"$ref": "#/$defs/slotTimeline"}, "default": []},
          "deformTimelines": {"type": "array", "items": {"$ref": "#/$defs/deformTimeline"}, "default": []},
          # <-- add eventTimelines here (after deformTimelines, before the close)
      },
      "required": ["name"],
  },
  ```
- **`additionalProperties: False` is set** (~:794) — the new `eventTimelines`
  array MUST be added inside this `properties` map or asset JSON carrying it is
  rejected. Add, mirroring deformTimelines:
  ```python
  "eventTimelines": {"type": "array", "items": {"$ref": "#/$defs/eventTimeline"}, "default": []},
  ```
- This dict is merged into `schema["$defs"]` at ~:485.

## (5) hidden_binary_children decision — DECISION: eventTimeline is NOT hidden

- `hidden_binary_children` (`generate.py` ~:489–503) contains `boneTimeline` and
  `slotTimeline` (among state-machine/warp/keyform children). `deformTimeline` is
  **absent**.
- Emission semantics (`generate.py` ~:508–520): typeKeys **in** the set `continue`
  (skip) → no root-level binary collection. typeKeys **not in** the set auto-emit
  a root-level array collection named `id + "s"` (overridable via
  `root_collection_overrides` ~:504–507). So `deformTimeline` auto-emits a
  root-level `deformTimelines` collection.
- This is orthogonal to the per-clip canonical-JSON arrays in §4: all four
  families (bone/slot/deform/event) get a per-clip array; `hidden_binary_children`
  only governs the **root-level** binary collection.
- **DECISION:** `eventTimeline` **is NOT added to `hidden_binary_children`** — it
  mirrors `deformTimeline` (the freshest template this slice tracks), auto-emitting
  a root-level `eventTimelines` collection so the loader reaches event records the
  same way it reaches deform records. Rationale: prompt 27 designates deform
  (prompt 23) as the closest landed analog; consistency with it minimizes new
  loader surface in prompt 28.
- **Name note for prompt 28:** the auto-emitted root-level binary collection and
  the per-clip canonical-JSON array (§4) both use the literal name `eventTimelines`
  — this is the same dual-name shape `deformTimelines` already has, so the loader
  reaches records via the root `eventTimelines` collection exactly as it does for
  `deformTimelines`. No name disambiguation is needed.

## Codegen touchpoints for prompt 28 (confirmed to exist)

- `PACKED_BYTES_METADATA` (~:26) — map property_id → {payload, layout doc anchor,
  structuralSchema, validatedBy}. Add an `eventKeys` entry mirroring `deformKeys`
  (~:63, layout `docs/deform-timeline-contract.md#packed-...`); the new anchor is
  `docs/event-timeline-contract.md#packed-eventtimeline-byte-layout-bnb`.
- `timelineKeys` metadata (~:27), `deformKeys` metadata (~:63).
- Defaults-vs-registry coverage rule (~:307–315) and property-coverage (~:292–294).
- Schema packedBytes stamp in `schema_for_property()` (~:1015–1018): stamps
  `x-bony-packedBytes` when `backing_type == "bytes" and property_id in
  PACKED_BYTES_METADATA`. The new `eventKeys` (bytes-backed propertyKey 2005) will
  be stamped here.
- `generate.py` writes **4 files** (`main()` ~:1410–1413): `spec/bony.schema.json`,
  `spec/bony-wire.schema.json`, `runtime-nim/.../wire.nim`, `runtime-dart/.../wire.dart`.

## Net corrections carried forward (do not lose these)

1. `volume`/`balance` are declared **`float64`** (prompt 27 mis-labeled them `f32`;
   `floatValue` was already correct as f64/f32-quantized). All three are
   f32-quantized on construction, **never clamped** → "carried verbatim".
2. **Packed wire widths:** `floatValue`/`volume`/`balance` pack as **4-byte f32**
   (NOT f64 — the runtime `float64` is in-memory only); `intValue` packs as a
   **zigzag signed varint (svarint)**, never fixed i32.
3. `eventTimeline` is **NOT** hidden → auto-emits a root-level `eventTimelines`
   collection (mirrors deformTimeline); root collection and per-clip array share
   that name, as `deformTimelines` already does.
4. There is **no existing event serialization** to reuse; the packed layout is
   minted by this milestone, mirroring deform/timeline conventions.
