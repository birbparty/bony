# DrawBatch To Raylib Contract

This contract defines how the Nim `naylib` renderer adapter must consume the
backend-neutral `DrawBatch` command stream. It pins the raylib-facing behavior
before the adapter is implemented, while keeping the core runtime independent of
raylib.

## Scope

This document owns:

- The meaning of `DrawBatch.texturePage`, `blendMode`, vertex color, and index
  data at the raylib adapter boundary.
- The blend-mode table, including straight-alpha and premultiplied-alpha atlas
  pages.
- The two-color tint-black shader contract.
- The clipping strategy for v1.
- The minimum smoke-test surface for the later naylib adapter bead.

It does not define world-transform math, mesh skinning, clipping polygon
construction, atlas packing, image loading, or conformance image goldens.

## DrawBatch Inputs

`DrawBatch` is a renderer-neutral draw command. The adapter must treat the
sequence order as binding draw order and must not reorder batches unless a
future batching contract proves the reordered output is byte-for-byte
equivalent for the active render state.

Each batch contains:

- `texturePage`: logical atlas page identifier. The adapter resolves this to a
  raylib `Texture2D` and page metadata.
- `blendMode`: canonical Bony blend mode string.
- `vertices`: transformed world-space positions, UVs, and light vertex color.
- `indices`: triangle indices into `vertices`.
- `clipId`: diagnostic/authoring clip identifier only for v1 renderer adapters.

The adapter owns conversion from f64 runtime values to raylib's f32 vertex and
texture-coordinate inputs at the final draw boundary. The conversion must not
feed back into runtime state.

## Texture Page Alpha Mode

Every texture page consumed by the adapter has an alpha mode:

- `straight`: RGB is not multiplied by alpha.
- `premultiplied`: RGB is already multiplied by alpha.

The alpha mode is page metadata, not a property of the blend mode. Two batches
with the same `blendMode` can require different raylib blend setup if their
texture pages differ.

The adapter must not guess alpha mode from pixels at draw time. Missing page
metadata defaults to `straight` only for hand-written M2 region fixtures; atlas
loading work must make this metadata explicit before it emits real page data.

## Canonical Blend Modes

The adapter must accept these `DrawBatch.blendMode` values:

| Bony `blendMode` | Source-over formula, straight source color `S` and alpha `Sa` | Straight page raylib mode | PMA page raylib mode |
| --- | --- | --- | --- |
| `normal` | `S * Sa + D * (1 - Sa)` | `BLEND_ALPHA` | `BLEND_ALPHA_PREMULTIPLY` |
| `additive` | `S * Sa + D` | `BLEND_ADDITIVE` | custom factors `ONE, ONE` |
| `multiply` | `D * (S * Sa + (1 - Sa))` | `BLEND_MULTIPLIED` if the shader emits straight source color | custom shader/blend path |
| `screen` | `1 - (1 - D) * (1 - S * Sa)` | custom shader/blend path | custom shader/blend path |

`D` is the framebuffer destination color. Alpha-channel write behavior must be
consistent for offscreen tests:

```text
outAlpha = Sa + Da * (1 - Sa)        # normal, multiply, screen
outAlpha = min(1, Sa + Da)           # additive
```

Raylib's predefined `BlendMode` enum includes `BLEND_ALPHA` as the default
straight-alpha mode and `BLEND_ALPHA_PREMULTIPLY` for premultiplied textures.
The adapter must use the PMA path for premultiplied pages; drawing a PMA page
through `BLEND_ALPHA` double-multiplies RGB and is a contract violation.

If naylib exposes raylib custom blend factors, the adapter may use them
directly. Otherwise it must route unsupported combinations through an internal
mockable rendering seam so tests can still verify the intended raylib state.

Unknown `blendMode` values are load/runtime errors at the adapter boundary.
They must not silently fall back to `normal`.

## Color And Two-Color Tint

`DrawVertex.r/g/b/a` is the light color. When no dark color is present, the
adapter uses:

```text
dark = (0, 0, 0)
```

The naylib adapter must support two-color tint-black before it is considered
complete. Raylib's default texture drawing path has one vertex color and no
built-in tint-black operation, so the adapter must use a custom shader path for
all batches that carry a non-zero dark color or for any future batch schema that
declares tint-black support.

The shader contract is defined in normalized linear arithmetic over sampled
texture color `T`:

```text
Ta = sampled alpha
Trgb = sampled RGB

if page alpha mode is premultiplied and Ta > 0:
  C = Trgb / Ta
elif page alpha mode is premultiplied:
  C = (0, 0, 0)
else:
  C = Trgb

light = vertex light RGB
lightAlpha = vertex light alpha
dark = vertex dark RGB

tintedRgb = C * light + (1 - C) * dark
sourceAlpha = Ta * lightAlpha
```

For a straight-alpha blend path, the fragment source is:

```text
sourceRgb = tintedRgb
sourceAlpha = sourceAlpha
```

For a premultiplied-alpha blend path, the fragment source is:

```text
sourceRgb = tintedRgb * sourceAlpha
sourceAlpha = sourceAlpha
```

The adapter must choose one representation and matching blend state per page.
It must not pass premultiplied texture RGB through a straight-alpha shader
without first unpremultiplying for the tint calculation, and it must not output
straight RGB into a PMA blend state.

For batches with no dark color, the same shader may be used with
`dark = (0, 0, 0)`, but a simpler one-color shader is allowed if it produces the
same source color and alpha.

## Mesh Submission

The adapter draws indexed triangles. It must preserve:

- Triangle order within `indices`.
- Vertex UVs exactly after f64-to-f32 boundary conversion.
- Per-vertex light color.
- Per-vertex dark color when the future batch representation carries it.

The adapter may combine adjacent batches only when all render state is
identical: texture page, page alpha mode, blend mode, shader variant, clip
state, and any future material flags. Combined output must be equivalent to
drawing the original batches in order.

## Clipping

V1 clipping is geometry-side. The core runtime or mesh pipeline clips triangles
to the convex clip polygon before producing the `DrawBatch` stream. The naylib
adapter therefore consumes already-clipped triangles and submits them normally.

Adapter rules:

- Do not build the v1 contract around raylib stencil state.
- Do not open or close clip stacks from `clipId`.
- Treat `clipId` as diagnostic metadata for logging, assertions, or future
  debugging hooks.
- A batch with empty `indices` is skipped without changing render state.

An optimized stencil implementation may be added later for real-time rendering,
but it must be behind an explicit feature flag and must not be the source of
conformance image or numeric goldens. The default adapter path remains
geometry-side clipping.

## Headless Smoke-Test Contract

The naylib adapter bead must be testable in Linux-only, GPU-less CI. Its smoke
test must use a mockable raylib seam, offscreen context, or `xvfb` path to prove
that representative `DrawBatch` inputs issue the expected raylib operations.

Minimum smoke cases:

- `normal` straight page selects `BLEND_ALPHA`.
- `normal` PMA page selects `BLEND_ALPHA_PREMULTIPLY`.
- `additive` PMA page selects custom `ONE, ONE` factors or records the
  equivalent custom operation through the seam.
- Non-zero dark color selects the tint-black shader path.
- A pre-clipped triangle batch is submitted without stencil/clip-stack calls.
- Unknown blend mode fails explicitly.

The smoke test proves adapter state mapping and call sequencing. It is not a
conformance golden. Numeric runtime goldens remain the cross-runtime source of
truth, and image-diff PNG goldens are Nim-only artifacts.

## Determinism Requirements

- Preserve `DrawBatch` order.
- Choose blend state from `(blendMode, texturePage.alphaMode)`.
- Keep page alpha mode explicit in adapter metadata.
- Do not silently normalize or rewrite unknown blend modes.
- Do not derive clipping from host graphics state in the default path.
- Keep all raylib/naylib dependencies out of the renderer-neutral core runtime.
