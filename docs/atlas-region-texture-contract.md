# Atlas-Backed Region Texture Contract

This is the binding contract for canonical region texture metadata introduced by
bead `bony-2j7z`.

## Scope

This contract defines how project-owned atlas metadata becomes observable on
region draw batches. It covers:

- canonical `.bony` and `.bnb` region fields for a logical texture page id and
  UV rectangle;
- default behavior for existing hand-authored region attachments;
- how `bony pack-atlas` sidecar coordinates map into canonical region fields;
- the runtime `DrawBatch.texturePage` and per-vertex UV output for region
  attachments.

It does not define image packing algorithms, third-party atlas formats, GPU
state, raylib-specific behavior, mesh UV semantics, or importer behavior for
external authoring tools.

## Canonical Region Fields

Region attachments remain top-level `regions[]` records. The required fields
are unchanged:

- `name`
- `width`
- `height`

The optional canonical texture fields are:

- `texturePage`: logical atlas page id. Empty string means no texture page.
- `u0`, `v0`, `u1`, `v1`: unit-range UV rectangle on `texturePage`.
- `alphaMode`: texture-page alpha mode, either `straight` or `premultiplied`.

Defaults are:

```json
{
  "texturePage": "",
  "u0": 0.0,
  "v0": 0.0,
  "u1": 1.0,
  "v1": 1.0,
  "alphaMode": "straight"
}
```

These defaults preserve legacy M2 region behavior: old records that only carry
`name`, `width`, and `height` serialize back byte-identically and emit an empty
`DrawBatch.texturePage` with full-quad UVs.

## Validation

Loaders must enforce:

- `u0`, `v0`, `u1`, and `v1` are finite f32 values in `0..1`;
- the rectangle is ordered: `u0 <= u1` and `v0 <= v1`;
- `alphaMode` is exactly `straight` or `premultiplied`;
- if `texturePage` is empty, the UV rectangle and alpha mode must be the default
  values.

The `texturePage` value is a logical id. It is not a filesystem path and is not
resolved by core `SkeletonData` loading.

## Sidecar Atlas Mapping

`bony pack-atlas` emits `spec/bony-atlas.schema.json` sidecar records with
project-owned page and region placement metadata. A tool that binds that sidecar
to a `.bony` region must copy:

- `pages[region.page].name` into `regions[].texturePage`;
- `region.u0`, `region.v0`, `region.u1`, and `region.v1` into the same-named
  canonical region fields.

If the page PNG data is premultiplied, that binding tool must also set
`alphaMode` to `premultiplied`; otherwise it may omit `alphaMode` because
`straight` is the canonical default.

## DrawBatch Output

For a visible region attachment, `buildDrawBatches` emits:

- `DrawBatch.texturePage = region.texturePage`;
- vertex UVs from the region rectangle in the existing region vertex order:
  bottom-left `(u0, v0)`, bottom-right `(u1, v0)`, top-right `(u1, v1)`, and
  top-left `(u0, v1)`.

`DrawBatch` does not carry `alphaMode`. Renderer adapters resolve alpha mode
from their texture-page table, as specified by
`docs/drawbatch-raylib-contract.md`.

## Binary Format

The `.bnb` region object keeps its M2 type key and adds M9 property keys:

| Property | Key | Type | Default |
| --- | ---: | --- | --- |
| `texturePage` | `8000` | `string` | `""` |
| `u0` | `8001` | `f32` | `0.0` |
| `v0` | `8002` | `f32` | `0.0` |
| `u1` | `8003` | `f32` | `1.0` |
| `v1` | `8004` | `f32` | `1.0` |
| `alphaMode` | `8005` | `string` | `"straight"` |

Canonical writers omit these fields when they equal defaults.
